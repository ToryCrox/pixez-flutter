import 'dart:async';
import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:path/path.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:sqflite/sqflite.dart';

class HistorySummary {
  final int illustId;
  final int timestamp;
  final int lastPage;
  final int totalPages;

  HistorySummary({
    required this.illustId,
    required this.timestamp,
    required this.lastPage,
    required this.totalPages,
  });

  factory HistorySummary.fromMap(Map<String, dynamic> map) {
    return HistorySummary(
      illustId: map[HistoryDatabaseProvider.cIllustId] as int,
      timestamp: map[HistoryDatabaseProvider.cTimestamp] as int,
      lastPage: map[HistoryDatabaseProvider.cLastPage] as int,
      totalPages: map[HistoryDatabaseProvider.cTotalPages] as int,
    );
  }

  double get progress => totalPages > 1 ? lastPage / (totalPages - 1) : 1.0;
}

class HistoryDatabaseProvider {
  // Singleton pattern
  HistoryDatabaseProvider._privateConstructor();
  static final HistoryDatabaseProvider instance =
      HistoryDatabaseProvider._privateConstructor();
  factory HistoryDatabaseProvider() => instance;

  Database? _db;
  Future<void>? _openFuture;

  static const String tableHistory = 'history';
  static const String cIllustId = 'illust_id';
  static const String cData = 'data';
  static const String cTimestamp = 'timestamp';
  static const String cTitle = 'title';
  static const String cUserName = 'user_name';
  static const String cTags = 'tags';
  static const String cLastPage = 'last_page';
  static const String cTotalPages = 'total_pages';
  static const int maxRecordCount = 20000;

  Future<Database> get db async {
    final database = _db;
    if (database != null) return database;
    await open();
    return _db!;
  }

  FutureOr<void> open() {
    if (_db != null) return null;
    return _openFuture ??= _openInternal();
  }

  Future<void> _openInternal() async {
    try {
      String databasesPath = await getDatabasesPath();
      String path = join(databasesPath, 'pixez_history.db');

      _db = await openDatabase(
        path,
        version: 2,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE $tableHistory ADD COLUMN $cLastPage INTEGER DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE $tableHistory ADD COLUMN $cTotalPages INTEGER DEFAULT 0',
            );
          }
        },
        onCreate: (Database db, int version) async {
          await db.execute('''
          CREATE TABLE $tableHistory (
            $cIllustId INTEGER PRIMARY KEY,
            $cData TEXT NOT NULL,
            $cTimestamp INTEGER NOT NULL,
            $cTitle TEXT,
            $cUserName TEXT,
            $cTags TEXT,
            $cLastPage INTEGER DEFAULT 0,
            $cTotalPages INTEGER DEFAULT 0
          )
        ''');
          // 创建索引以加速搜索和排序
          await db.execute(
            'CREATE INDEX index_timestamp ON $tableHistory ($cTimestamp)',
          );
        },
      );
      // 注册到数据库管理中心
      DatabaseRegistry.instance.register('插画阅读历史', path, () => _db!);
    } finally {
      _openFuture = null;
    }
  }

  Future<void> insert(Illusts illust, {int lastPage = 0}) async {
    final database = await db;
    // 1. 序列化并压缩数据
    final jsonStr = jsonEncode(illust.toJson());
    final compressedData = TypeUtil.gzipEncodeString(jsonStr);

    // 2. 提取搜索字段
    final title = illust.title;
    final userName = illust.user.name;
    final tags = illust.tags.map((e) => e.name).join(' ');

    // 3. 插入数据 (Replace 策略更新时间戳)
    await database.insert(tableHistory, {
      cIllustId: illust.id,
      cData: compressedData,
      cTimestamp: DateTime.now().millisecondsSinceEpoch,
      cTitle: title,
      cUserName: userName,
      cTags: tags,
      cLastPage: lastPage,
      cTotalPages: illust.pageCount,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // 4. 检查并清理旧数据
    // 简单的清理策略：仅在启动app后第一次插入数据的时候检查
    if (!_hasCheckedCleanup) {
      _hasCheckedCleanup = true;
      _checkAndCleanHistory(database);
    }
  }

  Future<void> _checkAndCleanHistory(Database database) async {
    final count = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM $tableHistory'),
    );
    if (count == null || count <= maxRecordCount) return;

    final int overflowCount = count - maxRecordCount;
    int totalDeleted = 0;
    int offset = 0;
    const int chunkSize = 100;
    // 限制最大搜索深度，避免全下载情况下循环过久
    final int maxSearchDepth = maxRecordCount;

    while (totalDeleted < overflowCount && offset < maxSearchDepth) {
      final List<Map<String, dynamic>> oldRecords = await database.query(
        tableHistory,
        columns: [cIllustId],
        orderBy: '$cTimestamp ASC',
        limit: chunkSize,
        offset: offset,
      );

      if (oldRecords.isEmpty) break;

      final List<int> oldIds =
          oldRecords.map((e) => e[cIllustId] as int).toList();
      // 批量查询下载状态
      final downloadedIds = await downloadStore.getDownloadedIds(oldIds);

      // 找出未下载的 ID
      final idsToDelete =
          oldIds.where((id) => !downloadedIds.contains(id)).toList();

      if (idsToDelete.isNotEmpty) {
        // 限制删除数量，不要超过 overflowCount - totalDeleted
        final int batchTarget = overflowCount - totalDeleted;
        final List<int> finalDeleteIds =
            idsToDelete.length > batchTarget
                ? idsToDelete.take(batchTarget).toList()
                : idsToDelete;

        final deleteCount = await database.delete(
          tableHistory,
          where: '$cIllustId IN (${finalDeleteIds.join(',')})',
        );
        totalDeleted += deleteCount;

        // 更新 offset：增加本批次中被跳过（已下载）的数量
        offset += (oldIds.length - finalDeleteIds.length);
      } else {
        // 全部都是已下载，offset 直接步进
        offset += oldIds.length;
      }

      // 如果这一页没满，说明后面没数据了
      if (oldRecords.length < chunkSize) break;
    }

    if (totalDeleted > 0) {
      BotToast.showText(text: '已自动清理了 $totalDeleted 条旧历史记录');
    }
  }

  bool _hasCheckedCleanup = false;

  Future<List<Illusts>> query({
    String? keyword,
    int? limit,
    int? offset,
  }) async {
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
        where: '$cTitle LIKE ? OR $cUserName LIKE ? OR $cTags LIKE ?',
        whereArgs: [k, k, k],
        orderBy: '$cTimestamp DESC',
        limit: limit,
        offset: offset,
      );
    }

    return maps
        .map((e) {
          try {
            final compressedData = e[cData] as String;
            final jsonStr = TypeUtil.gzipDecodeString(compressedData);
            return Illusts.fromJson(jsonDecode(jsonStr));
          } catch (e) {
            return null;
          }
        })
        .whereType<Illusts>()
        .toList();
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

  /// 查询所有已读作品的摘要信息，用于内存缓存
  Future<List<HistorySummary>> queryAllReadSummaries() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      tableHistory,
      columns: [cIllustId, cTimestamp, cLastPage, cTotalPages],
    );
    return maps.map((e) => HistorySummary.fromMap(e)).toList();
  }

  /// 批量查询作品阅读进度摘要
  Future<List<HistorySummary>> queryHistorySummaries(List<int> ids) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      tableHistory,
      columns: [cIllustId, cTimestamp, cLastPage, cTotalPages],
      where: '$cIllustId IN (${ids.join(',')})',
    );
    return maps.map((e) => HistorySummary.fromMap(e)).toList();
  }

  Future<void> close() async {
    _db?.close();
    _db = null;
  }
}
