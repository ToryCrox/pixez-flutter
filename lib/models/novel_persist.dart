/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful, but WITHOUT ANY
 *  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 *  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along with
 *  this program. If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:pixez/page/database/database_registry.dart';
import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

class NovelPersist {
  final int? id;
  final int novelId;
  final int userId;
  final String pictureUrl;
  final int time;
  final String title;
  final String userName;

  const NovelPersist({
    this.id,
    this.novelId = 0,
    this.userId = 0,
    this.pictureUrl = '',
    this.time = 0,
    this.title = '',
    this.userName = '',
  });

  factory NovelPersist.fromMap(Map<String, dynamic> map) => NovelPersist(
        id: map.optIntOrNull('id'),
        novelId: map.optInt('novel_id'),
        userId: map.optInt('user_id'),
        pictureUrl: map.optString('picture_url'),
        time: map.optInt('time'),
        title: map.optString('title'),
        userName: map.optString('user_name'),
      );
  factory NovelPersist.fromJson(Map<String, dynamic> json) =>
      NovelPersist.fromMap(json);

  Map<String, dynamic> toMap() => {
        'id': id,
        'novel_id': novelId,
        'user_id': userId,
        'picture_url': pictureUrl,
        'time': time,
        'title': title,
        'user_name': userName,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([
        id,
        novelId,
        userId,
        pictureUrl,
        time,
        title,
        userName,
      ]);

  NovelPersist copyWith({
    Object? id = TypeUtil.unset,
    int? novelId,
    int? userId,
    String? pictureUrl,
    int? time,
    String? title,
    String? userName,
  }) => NovelPersist(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        novelId: novelId ?? this.novelId,
        userId: userId ?? this.userId,
        pictureUrl: pictureUrl ?? this.pictureUrl,
        time: time ?? this.time,
        title: title ?? this.title,
        userName: userName ?? this.userName,
      );

  @override
  bool operator ==(Object other) =>
      other is NovelPersist && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelPersist(${toMap()})';
}

final String tableNovelPersist = 'Novelpersist';
final String cid = "id";
final String cNovel_id = "novel_id";
final String cuser_id = "user_id";
final String cpicture_url = "picture_url";
final String ctime = "time";
final String ctitle = "title";
final String cuserName = "user_name";

class NovelPersistProvider {
  late Database db;

  Future open() async {
    String databasesPath = (await getDatabasesPath());
    String path = join(databasesPath, 'Novelpersist.db');
    db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table $tableNovelPersist ( 
  $cid integer primary key autoincrement, 
  $cNovel_id integer not null,
  $cuser_id integer not null,
  $cpicture_url text not null,
  $ctitle text not null,
  $cuserName text not null,
  $ctime integer not null
  )
''');
      },
    );
    // 注册到数据库管理中心
    DatabaseRegistry.instance.register('小说收藏数据库', path, () => db);
  }

  Future<NovelPersist> insert(NovelPersist todo) async {
    final result = await getAccount(todo.novelId);
    final toInsert = result == null ? todo : todo.copyWith(id: result.id);
    final id = await db.insert(
      tableNovelPersist,
      toInsert.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return toInsert.copyWith(id: id);
  }

  Future<NovelPersist?> getAccount(int Novel_id) async {
    List<Map<String, dynamic>> maps = await db.query(
      tableNovelPersist,
      columns: [
        cid,
        cNovel_id,
        cuser_id,
        cpicture_url,
        ctime,
        ctitle,
        cuserName,
      ],
      where: '$cNovel_id = ?',
      whereArgs: [Novel_id],
    );
    if (maps.length > 0) {
      return NovelPersist.fromJson(maps.first);
    }
    return null;
  }

  Future<List<NovelPersist>> getAllAccount() async {
    List<NovelPersist> result = [];
    List<Map<String, dynamic>> maps = await db.query(
      tableNovelPersist,
      columns: [
        cid,
        cNovel_id,
        cuser_id,
        cpicture_url,
        ctime,
        ctitle,
        cuserName,
      ],
      orderBy: "$ctime DESC",
    );

    if (maps.length > 0) {
      maps.forEach((f) {
        result.add(NovelPersist.fromJson(f));
      });
    }
    return result;
  }

  Future<int> delete(int id) async {
    return await db.delete(
      tableNovelPersist,
      where: '$cNovel_id = ?',
      whereArgs: [id],
    );
  }

  Future<int> update(NovelPersist todo) async {
    return await db.update(
      tableNovelPersist,
      todo.toJson(),
      where: '$cid = ?',
      whereArgs: [todo.id],
    );
  }

  Future close() async => db.close();

  Future deleteAll() async {
    return await db.delete(tableNovelPersist);
  }
}
