import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AiCachedResult {
  final String sceneId;
  final String resourceKey;
  final String sourceHash;
  final String resultText;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AiCachedResult({
    required this.sceneId,
    required this.resourceKey,
    required this.sourceHash,
    required this.resultText,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AiCachedResult.fromMap(Map<String, Object?> map) {
    final metadataRaw = map['metadata_json'] as String? ?? '{}';
    Map<String, dynamic> metadata;
    try {
      metadata = jsonDecode(metadataRaw) as Map<String, dynamic>;
    } catch (_) {
      metadata = const {};
    }
    return AiCachedResult(
      sceneId: map['scene_id'] as String,
      resourceKey: map['resource_key'] as String,
      sourceHash: map['source_hash'] as String,
      resultText: map['result_text'] as String,
      metadata: metadata,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}

/// 可复用于翻译、摘要等 AI 场景的持久化结果缓存。
///
/// [sceneId] 隔离不同 AI 场景，[resourceKey] 关联业务对象，原文哈希用于在
/// 内容发生变化时自动失效。提示词、模型等可变信息放在 [metadata] 中，避免
/// 后续新增场景时修改表结构。
class AiResultCache {
  static const tableName = 'ai_cached_results';

  final String databaseName;
  final String? databasePath;
  final int maxEntries;
  Database? _database;
  Future<Database>? _opening;

  AiResultCache({
    this.databaseName = 'ai_result_cache.db',
    this.databasePath,
    this.maxEntries = 10000,
  });

  static String hashSource(String sourceText) =>
      sha256.convert(utf8.encode(sourceText)).toString();

  Future<AiCachedResult?> get({
    required String sceneId,
    required String resourceKey,
    required String sourceText,
  }) async {
    final db = await _getDatabase();
    final sourceHash = hashSource(sourceText);
    final rows = await db.query(
      tableName,
      where: 'scene_id = ? AND resource_key = ? AND source_hash = ?',
      whereArgs: [sceneId, resourceKey, sourceHash],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    await db.update(
      tableName,
      {'accessed_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
    return AiCachedResult.fromMap(rows.first);
  }

  Future<void> put({
    required String sceneId,
    required String resourceKey,
    required String sourceText,
    required String resultText,
    Map<String, dynamic> metadata = const {},
  }) async {
    final db = await _getDatabase();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(tableName, {
      'scene_id': sceneId,
      'resource_key': resourceKey,
      'source_hash': hashSource(sourceText),
      'result_text': resultText,
      'metadata_json': jsonEncode(metadata),
      'created_at': now,
      'updated_at': now,
      'accessed_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _prune(db);
  }

  Future<int> deleteResource({
    required String sceneId,
    required String resourceKey,
  }) async {
    final db = await _getDatabase();
    return db.delete(
      tableName,
      where: 'scene_id = ? AND resource_key = ?',
      whereArgs: [sceneId, resourceKey],
    );
  }

  Future<int> clearScene(String sceneId) async {
    final db = await _getDatabase();
    return db.delete(tableName, where: 'scene_id = ?', whereArgs: [sceneId]);
  }

  Future<int> clear() async {
    final db = await _getDatabase();
    return db.delete(tableName);
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    _opening = null;
    await db?.close();
  }

  Future<Database> _getDatabase() async {
    final current = _database;
    if (current != null && current.isOpen) return current;
    final opening = _opening ??= _open();
    try {
      return await opening;
    } catch (_) {
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final path = databasePath ?? join(await getDatabasesPath(), databaseName);
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (database, _) async {
        await database.execute('''
CREATE TABLE $tableName (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scene_id TEXT NOT NULL,
  resource_key TEXT NOT NULL,
  source_hash TEXT NOT NULL,
  result_text TEXT NOT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  accessed_at INTEGER NOT NULL,
  UNIQUE(scene_id, resource_key, source_hash)
)
''');
        await database.execute(
          'CREATE INDEX idx_ai_cache_accessed_at '
          'ON $tableName(accessed_at)',
        );
        await database.execute(
          'CREATE INDEX idx_ai_cache_resource '
          'ON $tableName(scene_id, resource_key)',
        );
      },
    );
    _database = db;
    _opening = null;
    if (databasePath == null) {
      DatabaseRegistry.instance.register('AI 结果缓存', path, () => db);
    }
    return db;
  }

  Future<void> _prune(Database db) async {
    if (maxEntries <= 0) return;
    final countRows = await db.rawQuery('SELECT COUNT(*) FROM $tableName');
    final count = countRows.first.values.first as int? ?? 0;
    final excess = count - maxEntries;
    if (excess <= 0) return;
    await db.rawDelete(
      'DELETE FROM $tableName WHERE id IN '
      '(SELECT id FROM $tableName ORDER BY accessed_at ASC LIMIT ?)',
      [excess],
    );
  }
}
