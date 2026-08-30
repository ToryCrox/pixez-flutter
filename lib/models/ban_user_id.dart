/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 */
import 'package:path/path.dart';
import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class BanUserIdPersist {
  final String? userId;
  final int? id;
  final String? name;

  const BanUserIdPersist({this.userId, this.name, this.id});

  factory BanUserIdPersist.fromMap(Map<String, dynamic> map) =>
      BanUserIdPersist(
        userId: map.optStringOrNull(columnUserId),
        name: map.optStringOrNull(columnName),
        id: map.optIntOrNull(columnId),
      );

  factory BanUserIdPersist.fromJson(Map<String, dynamic> json) =>
      BanUserIdPersist.fromMap(json);

  Map<String, dynamic> toMap() => {
        columnId: id,
        columnUserId: userId,
        columnName: name,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([userId, id, name]);

  BanUserIdPersist copyWith({
    Object? userId = TypeUtil.unset,
    Object? name = TypeUtil.unset,
    Object? id = TypeUtil.unset,
  }) => BanUserIdPersist(
        userId: identical(userId, TypeUtil.unset) ? this.userId : userId as String?,
        name: identical(name, TypeUtil.unset) ? this.name : name as String?,
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
      );

  @override
  bool operator ==(Object other) => other is BanUserIdPersist &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'BanUserIdPersist(${toMap()})';
}

final String columnId = 'id';
final String columnUserId = 'user_id';
final String columnName = 'name';
final String tableBanUserId = 'banuserid';

class BanUserIdProvider {
  late Database db;

  Future open() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'banuserid.db');
    db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table $tableBanUserId ( 
  $columnId integer primary key autoincrement, 
  $columnUserId text not null,
  $columnName text not null
  )
''');
      },
    );
    DatabaseRegistry.instance.register('用户屏蔽数据库', path, () => db);
  }

  Future<BanUserIdPersist> insert(BanUserIdPersist todo) async {
    final id = await db.insert(
      tableBanUserId,
      todo.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return todo.copyWith(id: id);
  }

  Future<BanUserIdPersist?> getAccount(int id) async {
    final maps = await db.query(
      tableBanUserId,
      columns: [columnId, columnUserId, columnName],
      where: '$columnId = ?',
      whereArgs: [id],
    );
    return maps.isEmpty ? null : BanUserIdPersist.fromJson(maps.first);
  }

  Future<List<BanUserIdPersist>> getAllAccount() async {
    final maps = await db.query(
      tableBanUserId,
      columns: [columnId, columnUserId, columnName],
    );
    return maps.map(BanUserIdPersist.fromJson).toList();
  }

  Future<int> delete(int id) =>
      db.delete(tableBanUserId, where: '$columnId = ?', whereArgs: [id]);
  Future<int> deleteAll() => db.delete(tableBanUserId);

  Future<int> update(BanUserIdPersist todo) => db.update(
        tableBanUserId,
        todo.toJson(),
        where: '$columnId = ?',
        whereArgs: [todo.id],
      );

  Future close() => db.close();

  Future<List<BanUserIdPersist>> insertAll(List<BanUserIdPersist> list) async {
    final result = <BanUserIdPersist>[];
    await db.transaction((txn) async {
      for (final todo in list) {
        final id = await txn.insert(
          tableBanUserId,
          todo.toJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        result.add(todo.copyWith(id: id));
      }
    });
    return result;
  }
}
