import 'dart:io';
import 'package:mobx/mobx.dart';
import 'package:sqflite/sqflite.dart';
import 'database_registry.dart';

part 'database_explorer_store.g.dart';

class DatabaseExplorerStore = _DatabaseExplorerStoreBase with _$DatabaseExplorerStore;

abstract class _DatabaseExplorerStoreBase with Store {
  @observable
  ObservableList<DatabaseEntry> entries = ObservableList<DatabaseEntry>();

  @observable
  DatabaseEntry? selectedEntry;

  @observable
  Database? currentDb;

  @observable
  bool isLoading = false;

  @observable
  ObservableList<Map<String, dynamic>> tables = ObservableList<Map<String, dynamic>>();

  @observable
  String dbPath = '';

  @observable
  int dbSize = 0;

  @action
  void init() {
    entries.clear();
    entries.addAll(DatabaseRegistry.instance.entries);
  }

  @action
  Future<void> selectDatabase(DatabaseEntry entry) async {
    isLoading = true;
    selectedEntry = entry;
    dbPath = entry.path;
    
    // 获取文件大小
    try {
      final file = File(dbPath);
      if (await file.exists()) {
        dbSize = await file.length();
      }
    } catch (e) {
      dbSize = 0;
    }

    try {
      currentDb = await entry.getDatabase();
      await loadTables();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> loadTables() async {
    if (currentDb == null) return;

    // 查询所有表 (不包括系统表和 sqlite_sequence)
    final List<Map<String, dynamic>> results = await currentDb!.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    );

    final List<Map<String, dynamic>> tableInfos = [];
    for (var row in results) {
      final tableName = row['name'] as String;
      // 预估行数
      final countResult = await currentDb!.rawQuery("SELECT count(*) as count FROM $tableName");
      final count = countResult.first['count'] as int;
      
      tableInfos.add({
        'name': tableName,
        'count': count,
      });
    }

    tables.clear();
    tables.addAll(tableInfos);
  }

  // --- 表格数据查看相关 ---

  @observable
  ObservableList<Map<String, dynamic>> tableData = ObservableList<Map<String, dynamic>>();

  @observable
  List<String> tableColumns = [];

  @observable
  String? sortColumn;

  @observable
  bool sortAscending = true;

  @observable
  String searchText = '';

  @observable
  String searchColumn = '*'; // '*' 表示所有列

  @observable
  String searchOperator = 'LIKE';

  @observable
  int pageSize = 50;

  @observable
  int currentPage = 0;

  @observable
  int totalCount = 0;

  @observable
  ObservableList<Map<String, dynamic>> tableFields = ObservableList<Map<String, dynamic>>();

  @observable
  ObservableList<Map<String, dynamic>> tableIndexes = ObservableList<Map<String, dynamic>>();

  @observable
  int tableBytes = 0;

  String? _currentDataTableName;

  @action
  Future<void> loadTableStructure(String tableName) async {
    if (currentDb == null) return;
    
    try {
      // 1. 获取字段详情
      final fields = await currentDb!.rawQuery("PRAGMA table_info($tableName)");
      tableFields.clear();
      tableFields.addAll(fields);

      // 2. 获取索引信息
      final indexes = await currentDb!.rawQuery(
        "SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name=?",
        [tableName]
      );
      tableIndexes.clear();
      tableIndexes.addAll(indexes);

      // 3. 获取行数统计 (同步更新 totalCount)
      final countResult = await currentDb!.rawQuery("SELECT count(*) as count FROM $tableName");
      totalCount = countResult.first['count'] as int;

      // 4. 估算磁盘空间 (尝试使用 dbstat, 如果不可用则返回 0)
      try {
        final sizeResult = await currentDb!.rawQuery(
          "SELECT sum(pgsize) as size FROM dbstat WHERE name=?",
          [tableName]
        );
        tableBytes = sizeResult.first['size'] as int? ?? 0;
      } catch (e) {
        // 如果 dbstat 虚拟表未编译进去，则设为 -1 表示不可用
        tableBytes = -1;
      }
    } catch (e) {
      // 错误处理
    }
  }

  @action
  Future<void> loadTableData(String tableName, {bool resetPagination = true}) async {
    if (currentDb == null) return;

    final isNewTable = _currentDataTableName != tableName;
    if (isNewTable) {
      isLoading = true; // 只有切换新表时才立即显示全局加载
      _currentDataTableName = tableName;
      tableColumns = [];
      tableData.clear();
      searchColumn = '*';
      searchText = '';
      currentPage = 0;
      sortColumn = null;
    } else if (resetPagination) {
      currentPage = 0;
    }

    // 内部方法，用于执行具体加载
    Future<void> doLoad() async {
      try {
        // 1. 确保列结构已就绪 (如果是新表或为空)
        if (tableColumns.isEmpty) {
          final pragmaRows = await currentDb!.rawQuery("PRAGMA table_info($tableName)");
          tableColumns = pragmaRows.map((e) => e['name'] as String).toList();
        }

        // 2. 构建查询
        String baseQuery = "SELECT * FROM $tableName";
        List<dynamic> arguments = [];

        if (searchText.isNotEmpty) {
          if (searchColumn == '*') {
            String whereClause = tableColumns.map((col) => "$col $searchOperator ?").join(" OR ");
            baseQuery += " WHERE $whereClause";
            final param = searchOperator == 'LIKE' ? "%$searchText%" : searchText;
            for (var i = 0; i < tableColumns.length; i++) {
              arguments.add(param);
            }
          } else {
            baseQuery += " WHERE $searchColumn $searchOperator ?";
            final param = searchOperator == 'LIKE' ? "%$searchText%" : searchText;
            arguments.add(param);
          }
        }

        // 并发执行总数查询和分页查询，减少等待时间
        final countFuture = currentDb!.rawQuery("SELECT count(*) as count FROM ($baseQuery)", arguments);
        
        String dataQuery = baseQuery;
        if (sortColumn != null) {
          dataQuery += " ORDER BY $sortColumn ${sortAscending ? 'ASC' : 'DESC'}";
        }
        dataQuery += " LIMIT $pageSize OFFSET ${currentPage * pageSize}";
        final dataFuture = currentDb!.rawQuery(dataQuery, arguments);

        final results = await Future.wait([countFuture, dataFuture]);
        
        // 集中更新可观察变量，减少 Observer 触发频率
        runInAction(() {
          totalCount = results[0].first['count'] as int;
          tableData.clear();
          tableData.addAll(results[1]);
        });
      } catch (e) {
        tableData.clear();
      } finally {
        isLoading = false;
      }
    }

    // 如果是切换表且异步已经在跑，可能需要防止竞态（简单处理：直接运行）
    await doLoad();
  }

  @action
  void setSort(String column) {
    if (sortColumn == column) {
      sortAscending = !sortAscending;
    } else {
      sortColumn = column;
      sortAscending = true;
    }
  }

  @action
  void setSearch(String text) {
    searchText = text;
  }

  @action
  void setSearchColumn(String col) {
    searchColumn = col;
  }

  @action
  void setSearchOperator(String op) {
    searchOperator = op;
  }

  @action
  void nextPage() {
    if ((currentPage + 1) * pageSize < totalCount) {
      currentPage++;
    }
  }

  @action
  void prevPage() {
    if (currentPage > 0) {
      currentPage--;
    }
  }
}
