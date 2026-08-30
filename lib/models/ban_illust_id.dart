/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 */
import 'package:path/path.dart';
import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final String columnId = 'id';
final String columnIllustId = 'illust_id';
final String columnName = 'name';
final String tableBanIllustId = 'banillustid';

class BanIllustIdPersist {
  final String illustId;
  final String name;
  final int? id;

  const BanIllustIdPersist({this.illustId = '', this.name = '', this.id});

  factory BanIllustIdPersist.fromMap(Map<String, dynamic> map) =>
      BanIllustIdPersist(
        illustId: map.optString('illust_id'),
        name: map.optString('name'),
        id: map.optIntOrNull('id'),
      );

  factory BanIllustIdPersist.fromJson(Map<String, dynamic> json) =>
      BanIllustIdPersist.fromMap(json);

  Map<String, dynamic> toMap() => {
        'illust_id': illustId,
        'name': name,
        'id': id,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([illustId, name, id]);

  BanIllustIdPersist copyWith({
    String? illustId,
    String? name,
    Object? id = TypeUtil.unset,
  }) => BanIllustIdPersist(
        illustId: illustId ?? this.illustId,
        name: name ?? this.name,
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
      );

  @override
  bool operator ==(Object other) => other is BanIllustIdPersist &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'BanIllustIdPersist(${toMap()})';
}

class BanIllustIdProvider {
  late Database db;

  Future open() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'banillustid.db');
    db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table $tableBanIllustId ( 
  $columnId integer primary key autoincrement, 
  $columnIllustId text not null,
  $columnName text not null
  )
''');
      },
    );
    DatabaseRegistry.instance.register('作品屏蔽数据库', path, () => db);
  }

  Future<BanIllustIdPersist> insert(BanIllustIdPersist todo) async {
    final id = await db.insert(
      tableBanIllustId,
      todo.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return todo.copyWith(id: id);
  }

  Future<List<BanIllustIdPersist>> insertAll(
    List<BanIllustIdPersist> todos,
  ) async {
    final result = <BanIllustIdPersist>[];
    await db.transaction((txn) async {
      for (final todo in todos) {
        final id = await txn.insert(
          tableBanIllustId,
          todo.toJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        result.add(todo.copyWith(id: id));
      }
    });
    return result;
  }

  Future<BanIllustIdPersist?> getAccount(int id) async {
    final maps = await db.query(
      tableBanIllustId,
      columns: [columnId, columnIllustId, columnName],
      where: '$columnId = ?',
      whereArgs: [id],
    );
    return maps.isEmpty ? null : BanIllustIdPersist.fromJson(maps.first);
  }

  Future<List<BanIllustIdPersist>> getAllAccount() async {
    final maps = await db.query(
      tableBanIllustId,
      columns: [columnId, columnIllustId, columnName],
    );
    return maps.map(BanIllustIdPersist.fromJson).toList();
  }

  Future<int> delete(int id) =>
      db.delete(tableBanIllustId, where: '$columnId = ?', whereArgs: [id]);
  Future<int> deleteAll() => db.delete(tableBanIllustId);

  Future<int> update(BanIllustIdPersist todo) => db.update(
        tableBanIllustId,
        todo.toJson(),
        where: '$columnId = ?',
        whereArgs: [todo.id],
      );

  Future close() => db.close();
}
