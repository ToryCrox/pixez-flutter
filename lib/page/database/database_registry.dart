import 'dart:async';
import 'package:sqflite/sqflite.dart';

/// 数据库项定义
class DatabaseEntry {
  /// 数据库别名 (如 "下载数据库")
  final String name;

  /// 数据库原始路径 (用于显示和获取文件信息)
  final String path;

  /// 获取数据库实例的回调 (解耦具体的实现)
  final FutureOr<Database> Function() getDatabase;

  DatabaseEntry({
    required this.name,
    required this.path,
    required this.getDatabase,
  });
}

/// 数据库注册中心单例
class DatabaseRegistry {
  DatabaseRegistry._();
  static final DatabaseRegistry instance = DatabaseRegistry._();

  final List<DatabaseEntry> _entries = [];

  /// 获取所有已注册的数据库
  List<DatabaseEntry> get entries => List.unmodifiable(_entries);

  /// 注册一个数据库
  void register(String name, String path, FutureOr<Database> Function() getDatabase) {
    // 避免重复注册同名数据库
    if (_entries.any((e) => e.name == name)) return;
    
    _entries.add(DatabaseEntry(
      name: name,
      path: path,
      getDatabase: getDatabase,
    ));
  }
}
