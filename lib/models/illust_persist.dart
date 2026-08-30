/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */

import 'package:path/path.dart';
import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class IllustPersist {
  final int? id;
  final int illustId;
  final int userId;
  final String pictureUrl;
  final String? userName;
  final String? title;
  final int time;

  const IllustPersist({
    this.id,
    this.illustId = 0,
    this.userId = 0,
    this.pictureUrl = '',
    this.time = 0,
    this.title,
    this.userName,
  });

  factory IllustPersist.fromMap(Map<String, dynamic> map) => IllustPersist(
        id: map.optIntOrNull('id'),
        illustId: map.optInt('illust_id'),
        userId: map.optInt('user_id'),
        pictureUrl: map.optString('picture_url'),
        time: map.optInt('time'),
        title: map.optStringOrNull('title'),
        userName: map.optStringOrNull('user_name'),
      );

  factory IllustPersist.fromJson(Map<String, dynamic> json) =>
      IllustPersist.fromMap(json);

  Map<String, dynamic> toMap() => {
        'id': id,
        'illust_id': illustId,
        'user_id': userId,
        'picture_url': pictureUrl,
        'user_name': userName,
        'title': title,
        'time': time,
      };

  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([
        id,
        illustId,
        userId,
        pictureUrl,
        userName,
        title,
        time,
      ]);

  IllustPersist copyWith({
    Object? id = TypeUtil.unset,
    int? illustId,
    int? userId,
    String? pictureUrl,
    Object? userName = TypeUtil.unset,
    Object? title = TypeUtil.unset,
    int? time,
  }) => IllustPersist(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        illustId: illustId ?? this.illustId,
        userId: userId ?? this.userId,
        pictureUrl: pictureUrl ?? this.pictureUrl,
        userName: identical(userName, TypeUtil.unset)
            ? this.userName
            : userName as String?,
        title: identical(title, TypeUtil.unset) ? this.title : title as String?,
        time: time ?? this.time,
      );

  @override
  bool operator ==(Object other) =>
      other is IllustPersist && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'IllustPersist(${toMap()})';
}

final String tableIllustPersist = 'illustpersist';
final String cid = "id";
final String cillust_id = "illust_id";
final String cuser_id = "user_id";
final String cpicture_url = "picture_url";
final String ctitle = "title";
final String cuser_name = "user_name";
final String ctime = "time";

class IllustPersistProvider {
  late Database db;

  void _createTableV2(Batch batch) {
    batch.execute('''
create table $tableIllustPersist ( 
  $cid integer primary key autoincrement, 
  $cillust_id integer not null,
  $cuser_id integer not null,
  $cpicture_url text not null,
  $ctitle text,
  $cuser_name text,
    $ctime integer not null
  )
''');
  }

  void _updateTableV1ToV2(Batch batch) {
    batch.execute('''
        ALTER TABLE $tableIllustPersist ADD $ctitle TEXT;
            ''');
    batch.execute('''
        ALTER TABLE $tableIllustPersist ADD $cuser_name TEXT;
    ''');
  }

  Future open() async {
    String databasesPath = (await getDatabasesPath());
    String path = join(databasesPath, 'illustpersist.db');
    db = await openDatabase(
      path,
      version: 2,
      onCreate: (Database db, int version) async {
        var batch = db.batch();
        _createTableV2(batch);
        await batch.commit();
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        var batch = db.batch();
        if (oldVersion < 2) {
          _updateTableV1ToV2(batch);
        }
        await batch.commit();
      },
    );
    // 注册到数据库管理中心
    DatabaseRegistry.instance.register('作品收藏数据库', path, () => db);
  }

  Future<IllustPersist> insert(IllustPersist todo) async {
    final result = await getAccount(todo.illustId);
    final toInsert = result == null ? todo : todo.copyWith(id: result.id);
    final id = await db.insert(
      tableIllustPersist,
      toInsert.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return toInsert.copyWith(id: id);
  }

  Future<IllustPersist?> getAccount(int illust_id) async {
    List<Map<String, dynamic>> maps = await db.query(
      tableIllustPersist,
      columns: [cid, cillust_id, cuser_id, cpicture_url, ctime],
      where: '$cillust_id = ?',
      whereArgs: [illust_id],
    );
    if (maps.length > 0) {
      return IllustPersist.fromJson(maps.first);
    }
    return null;
  }

  Future<List<IllustPersist>> getLikeIllusts(String word) async {
    List<IllustPersist> result = [];
    List<Map<String, dynamic>> maps = await db.query(
      tableIllustPersist,
      columns: [
        cid,
        cillust_id,
        cuser_id,
        cpicture_url,
        ctime,
        cuser_name,
        ctitle,
      ],
      where: '$ctitle LIKE ? or $cuser_name LIKE ?',
      whereArgs: ["%${word}%", "%${word}%"],
      orderBy: ctime,
    );

    if (maps.length > 0) {
      maps.forEach((f) {
        result.add(IllustPersist.fromJson(f));
      });
    }
    return result;
  }

  Future<List<IllustPersist>> getAllAccount() async {
    List<IllustPersist> result = [];
    List<Map<String, dynamic>> maps = await db.query(
      tableIllustPersist,
      columns: [
        cid,
        cillust_id,
        cuser_id,
        cpicture_url,
        ctime,
        cuser_name,
        ctitle,
      ],
      orderBy: ctime,
    );

    if (maps.length > 0) {
      maps.forEach((f) {
        result.add(IllustPersist.fromJson(f));
      });
    }
    return result;
  }

  Future<int> delete(int id) async {
    return await db.delete(
      tableIllustPersist,
      where: '$cillust_id = ?',
      whereArgs: [id],
    );
  }

  Future<int> update(IllustPersist todo) async {
    return await db.update(
      tableIllustPersist,
      todo.toJson(),
      where: '$cid = ?',
      whereArgs: [todo.id],
    );
  }

  Future close() async => db.close();

  Future deleteAll() async {
    return await db.delete(tableIllustPersist);
  }
}
