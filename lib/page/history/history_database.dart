
import 'dart:convert';

import 'package:path/path.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/models/illust.dart';
import 'package:sqflite/sqflite.dart';

class HistoryDatabaseProvider {
  // Singleton pattern
  HistoryDatabaseProvider._privateConstructor();
  static final HistoryDatabaseProvider instance =
      HistoryDatabaseProvider._privateConstructor();
  factory HistoryDatabaseProvider() => instance;

  Database? _db;

  static const String tableHistory = 'history';
  static const String cIllustId = 'illust_id';
  static const String cData = 'data';
  static const String cTimestamp = 'timestamp';
  static const String cTitle = 'title';
  static const String cUserName = 'user_name';
  static const String cTags = 'tags';
  static const int maxRecordCount = 10000;

  Future<Database> get db async {
    if (_db != null) return _db!;
    await open();
    return _db!;
  }

  Future<void> open() async {
    if (_db != null) return;
    String databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'pixez_history.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $tableHistory (
            $cIllustId INTEGER PRIMARY KEY,
            $cData TEXT NOT NULL,
            $cTimestamp INTEGER NOT NULL,
            $cTitle TEXT,
            $cUserName TEXT,
            $cTags TEXT
          )
        ''');
        // 创建索引以加速搜索和排序
        await db.execute(
            'CREATE INDEX index_timestamp ON $tableHistory ($cTimestamp)');
      },
    );
  }

  Future<void> insert(Illusts illust) async {
    final database = await db;
    // 1. 序列化并压缩数据
    final jsonStr = jsonEncode(illust.toJson());
    final compressedData = TypeUtil.gzipEncodeString(jsonStr);

    // 2. 提取搜索字段
    final title = illust.title;
    final userName = illust.user.name;
    final tags = illust.tags.map((e) => e.name).join(' ');

    // 3. 插入数据 (Replace 策略更新时间戳)
    await database.insert(
      tableHistory,
      {
        cIllustId: illust.id,
        cData: compressedData,
        cTimestamp: DateTime.now().millisecondsSinceEpoch,
        cTitle: title,
        cUserName: userName,
        cTags: tags,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 4. 检查并清理旧数据
    // 简单的清理策略：仅在启动app后第一次插入数据的时候检查
    if (!_hasCheckedCleanup) {
      _hasCheckedCleanup = true;
      final count = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM $tableHistory'));
      if (count != null && count > maxRecordCount) {
        // 删除 timestamp 最小的 (最旧的)
        // 计算需要删除多少条
        final deleteCount = count - maxRecordCount;
        await database.execute('''
        DELETE FROM $tableHistory 
        WHERE $cIllustId IN (
          SELECT $cIllustId FROM $tableHistory ORDER BY $cTimestamp ASC LIMIT $deleteCount
        )
      ''');
      }
    }
  }

  bool _hasCheckedCleanup = false;

  Future<List<Illusts>> query({String? keyword, int? limit, int? offset}) async {
    final database = await db;
    List<Map<String, dynamic>> maps;
    if (keyword == null || keyword.trim().isEmpty) {
      maps = await database.query(
        tableHistory,
        orderBy: '$cTimestamp DESC',
        limit: limit,
        offset: offset,
      );
    } else {
      final k = '%$keyword%';
      maps = await database.query(
        tableHistory,
        where:
            '$cTitle LIKE ? OR $cUserName LIKE ? OR $cTags LIKE ?',
        whereArgs: [k, k, k],
        orderBy: '$cTimestamp DESC',
        limit: limit,
        offset: offset,
      );
    }

    return maps.map((e) {
      try {
        final compressedData = e[cData] as String;
        final jsonStr = TypeUtil.gzipDecodeString(compressedData);
        return Illusts.fromJson(jsonDecode(jsonStr));
      } catch (e) {
        return null;
      }
    }).whereType<Illusts>().toList();
  }

  Future<int> delete(int illustId) async {
    final database = await db;
    return await database.delete(
      tableHistory,
      where: '$cIllustId = ?',
      whereArgs: [illustId],
    );
  }

  Future<int> deleteAll() async {
    final database = await db;
    return await database.delete(tableHistory);
  }

  Future<void> close() async {
    _db?.close();
    _db = null;
  }
}
