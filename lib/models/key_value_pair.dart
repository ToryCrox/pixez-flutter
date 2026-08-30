import 'dart:convert' show json;

import 'package:path/path.dart';
import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final String tableKVPair = 'kvpair';
final String columnId = '_id';
final String columnKey = 'key';
final String columnValue = 'value';
final String columnExpireTime = 'expire_time';
final String columnDateTime = 'date_time';

class KVPair {
  final int? id;
  final String key;
  final String value;
  final int expireTime;
  final int dateTime;

  const KVPair({
    this.id,
    this.key = '',
    this.value = '',
    this.expireTime = 0,
    this.dateTime = 0,
  });

  factory KVPair.fromMap(Map<String, dynamic> map) => KVPair(
        id: map.optIntOrNull(columnId),
        key: map.optString(columnKey),
        value: map.optString(columnValue),
        expireTime: map.optInt(columnExpireTime),
        dateTime: map.optInt(columnDateTime),
      );

  factory KVPair.fromJson(Map<String, dynamic> json) => KVPair.fromMap(json);

  Map<String, dynamic> toMap() => {
        columnId: id,
        columnKey: key,
        columnValue: value,
        columnExpireTime: expireTime,
        columnDateTime: dateTime,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([id, key, value, expireTime, dateTime]);

  KVPair copyWith({
    Object? id = TypeUtil.unset,
    String? key,
    String? value,
    int? expireTime,
    int? dateTime,
  }) => KVPair(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        key: key ?? this.key,
        value: value ?? this.value,
        expireTime: expireTime ?? this.expireTime,
        dateTime: dateTime ?? this.dateTime,
      );

  @override
  bool operator ==(Object other) =>
      other is KVPair && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => json.encode(toJson());
}

class KVProvider {
  late Database db;

  Future open() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'kvpair.db');
    db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table $tableKVPair ( 
  $columnId integer primary key autoincrement, 
  $columnKey text not null,
  $columnValue text not null,
  $columnExpireTime integer not null,
  $columnDateTime integer not null
  )
''');
      },
    );
    DatabaseRegistry.instance.register('配置数据库', path, () => db);
  }

  Future<KVPair> insert(KVPair todo) async {
    final id = await db.insert(
      tableKVPair,
      todo.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return todo.copyWith(id: id);
  }

  Future<KVPair?> getAccount(String key) async {
    final maps = await db.query(
      tableKVPair,
      columns: [
        columnId,
        columnKey,
        columnValue,
        columnExpireTime,
        columnDateTime,
      ],
      where: '$columnKey = ?',
      whereArgs: [key],
    );
    return maps.isEmpty ? null : KVPair.fromJson(maps.first);
  }

  Future<int> remove(String key) =>
      db.delete(tableKVPair, where: '$columnKey = ?', whereArgs: [key]);
  Future<int> deleteAll() => db.delete(tableKVPair);

  Future<int> update(KVPair todo) => db.update(
        tableKVPair,
        todo.toJson(),
        where: '$columnId = ?',
        whereArgs: [todo.id],
      );

  Future<List<KVPair>> getAllAccount() async {
    final maps = await db.query(
      tableKVPair,
      columns: [
        columnId,
        columnKey,
        columnValue,
        columnExpireTime,
        columnDateTime,
      ],
    );
    return maps.map(KVPair.fromJson).toList();
  }

  Future<void> delete(String key) async {
    await db.delete(tableKVPair, where: '$columnKey = ?', whereArgs: [key]);
  }
}
