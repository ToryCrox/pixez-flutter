import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:pixez/manga_ocr/manga_ocr_models.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MangaOcrCacheKey {
  final String imageSha256;
  final int pageIndex;
  final String preprocessorId;
  final String preprocessorVersion;
  final String detectorId;
  final String detectorVersion;
  final String recognizerId;
  final String recognizerVersion;
  final MangaOcrOptions options;

  const MangaOcrCacheKey({
    required this.imageSha256,
    required this.pageIndex,
    required this.preprocessorId,
    required this.preprocessorVersion,
    required this.detectorId,
    required this.detectorVersion,
    required this.recognizerId,
    required this.recognizerVersion,
    required this.options,
  });

  String get value {
    final canonical = jsonEncode({
      'imageSha256': imageSha256,
      'pageIndex': pageIndex,
      'preprocessorId': preprocessorId,
      'preprocessorVersion': preprocessorVersion,
      'detectorId': detectorId,
      'detectorVersion': detectorVersion,
      'recognizerId': recognizerId,
      'recognizerVersion': recognizerVersion,
      'options': options.toJson(),
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}

class MangaOcrCache {
  static const tableName = 'manga_page_ocr_results';

  final String databaseName;
  final String? databasePath;
  final int maxEntries;
  Database? _database;
  Future<Database>? _opening;

  MangaOcrCache({
    this.databaseName = 'manga_ocr_cache.db',
    this.databasePath,
    this.maxEntries = 2000,
  });

  static Future<String> hashFile(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  Future<MangaPageOcrResult?> get(MangaOcrCacheKey key) async {
    final db = await _getDatabase();
    final rows = await db.query(
      tableName,
      columns: ['id', 'result_json'],
      where: 'cache_key = ?',
      whereArgs: [key.value],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    await db.update(
      tableName,
      {'accessed_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
    return MangaPageOcrResult.fromJson(
      jsonDecode(rows.first['result_json'] as String) as Map<String, dynamic>,
    );
  }

  Future<void> put(MangaOcrCacheKey key, MangaPageOcrResult result) async {
    final db = await _getDatabase();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(tableName, {
      'cache_key': key.value,
      'image_sha256': key.imageSha256,
      'page_index': key.pageIndex,
      'result_json': jsonEncode(result.toJson()),
      'created_at': now,
      'accessed_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _prune(db);
  }

  Future<int> clear() async => (await _getDatabase()).delete(tableName);

  Future<void> close() async {
    final db = _database;
    _database = null;
    _opening = null;
    await db?.close();
  }

  Future<Database> _getDatabase() async {
    final current = _database;
    if (current != null && current.isOpen) return current;
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    final databaseFile =
        databasePath ?? join(await getDatabasesPath(), databaseName);
    final db = await openDatabase(
      databaseFile,
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''
CREATE TABLE $tableName (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cache_key TEXT NOT NULL UNIQUE,
  image_sha256 TEXT NOT NULL,
  page_index INTEGER NOT NULL,
  result_json TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  accessed_at INTEGER NOT NULL
)
''');
        await database.execute(
          'CREATE INDEX idx_manga_ocr_image_page '
          'ON $tableName(image_sha256, page_index)',
        );
        await database.execute(
          'CREATE INDEX idx_manga_ocr_accessed_at '
          'ON $tableName(accessed_at)',
        );
      },
    );
    _database = db;
    _opening = null;
    if (databasePath == null) {
      DatabaseRegistry.instance.register('漫画 OCR 缓存', databaseFile, () => db);
    }
    return db;
  }

  Future<void> _prune(Database db) async {
    if (maxEntries <= 0) return;
    final rows = await db.rawQuery('SELECT COUNT(*) FROM $tableName');
    final count = rows.first.values.first as int? ?? 0;
    final excess = count - maxEntries;
    if (excess <= 0) return;
    await db.rawDelete(
      'DELETE FROM $tableName WHERE id IN '
      '(SELECT id FROM $tableName ORDER BY accessed_at ASC LIMIT ?)',
      [excess],
    );
  }
}
