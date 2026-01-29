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

  @action
  Future<void> loadTableData(String tableName, {bool resetPagination = true}) async {
    if (currentDb == null) return;
    isLoading = true;

    if (resetPagination) {
      currentPage = 0;
      sortColumn = null;
      sortAscending = true;
      tableColumns = [];
      searchColumn = '*';
    }

    try {
      // 1. 获取列结构 (确保针对当前 tableName 获取最新的列定义)
      final pragmaRows = await currentDb!.rawQuery("PRAGMA table_info($tableName)");
      tableColumns = pragmaRows.map((e) => e['name'] as String).toList();

      // 2. 构建查询
      String query = "SELECT * FROM $tableName";
      List<dynamic> arguments = [];

      // 增强型搜索逻辑
      if (searchText.isNotEmpty) {
        if (searchColumn == '*') {
          // 对所有列进行 OR LIKE (保持原有逻辑，但通常只在 LIKE 操作符下有意义)
          String whereClause = tableColumns.map((col) => "$col $searchOperator ?").join(" OR ");
          query += " WHERE $whereClause";
          final param = searchOperator == 'LIKE' ? "%$searchText%" : searchText;
          for (var i = 0; i < tableColumns.length; i++) {
            arguments.add(param);
          }
        } else {
          // 指定列搜索
          query += " WHERE $searchColumn $searchOperator ?";
          final param = searchOperator == 'LIKE' ? "%$searchText%" : searchText;
          arguments.add(param);
        }
      }

      // 统计总数 (带过滤)
      final countResult = await currentDb!.rawQuery("SELECT count(*) as count FROM ($query)", arguments);
      totalCount = countResult.first['count'] as int;

      // 排序
      if (sortColumn != null) {
        query += " ORDER BY $sortColumn ${sortAscending ? 'ASC' : 'DESC'}";
      }

      // 分页
      query += " LIMIT $pageSize OFFSET ${currentPage * pageSize}";

      final results = await currentDb!.rawQuery(query, arguments);
      tableData.clear();
      tableData.addAll(results);
    } catch (e) {
      tableData.clear();
    } finally {
      isLoading = false;
    }
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
