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

import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

class NovelViewerPersist {
  final int? id;
  final int novelId;
  final double offset;

  const NovelViewerPersist({this.id, this.novelId = 0, this.offset = 0});

  factory NovelViewerPersist.fromMap(Map<String, dynamic> map) =>
      NovelViewerPersist(
        id: map.optIntOrNull('id'),
        novelId: map.optInt('novel_id'),
        offset: map.optDouble('offset'),
      );
  factory NovelViewerPersist.fromJson(Map<String, dynamic> json) =>
      NovelViewerPersist.fromMap(json);

  Map<String, dynamic> toMap() => {
        'id': id,
        'novel_id': novelId,
        'offset': offset,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([id, novelId, offset]);

  NovelViewerPersist copyWith({
    Object? id = TypeUtil.unset,
    int? novelId,
    double? offset,
  }) => NovelViewerPersist(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        novelId: novelId ?? this.novelId,
        offset: offset ?? this.offset,
      );

  @override
  bool operator ==(Object other) => other is NovelViewerPersist &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelViewerPersist(${toMap()})';
}

final String tableNovelViewerPersist = 'NovelViewerPersist';
final String cid = "id";
final String cNovel_id = "novel_id";
final String cOffset = "offset";
final String cBook = "book";

class NovelViewerPersistProvider {
  late Database db;

  Future open() async {
    String databasesPath = (await getDatabasesPath());
    String path = join(databasesPath, 'NovelViewerPersist.db');
    db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table $tableNovelViewerPersist ( 
  $cid integer primary key autoincrement, 
  $cNovel_id integer not null,
  $cOffset REAL NOT NULL
  )
''');
      },
    );
    // 注册到数据库管理中心
    DatabaseRegistry.instance.register('小说阅读历史', path, () => db);
  }

  Future<NovelViewerPersist> insert(NovelViewerPersist todo) async {
    final result = await getNovelPersistById(todo.novelId);
    final toInsert = result == null ? todo : todo.copyWith(id: result.id);
    final id = await db.insert(
      tableNovelViewerPersist,
      toInsert.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return toInsert.copyWith(id: id);
  }

  Future<NovelViewerPersist?> getNovelPersistById(int Novel_id) async {
    List<Map<String, dynamic>> maps = await db.query(
      tableNovelViewerPersist,
      columns: [cid, cNovel_id, cOffset],
      where: '$cNovel_id = ?',
      whereArgs: [Novel_id],
    );
    if (maps.length > 0) {
      return NovelViewerPersist.fromJson(maps.first);
    }
    return null;
  }

  Future<List<NovelViewerPersist>> getAll() async {
    List<NovelViewerPersist> result = [];
    List<Map<String, dynamic>> maps = await db.query(
      tableNovelViewerPersist,
      columns: [cid, cNovel_id, cOffset],
    );

    if (maps.length > 0) {
      maps.forEach((f) {
        result.add(NovelViewerPersist.fromJson(f));
      });
    }
    return result;
  }

  Future<int> delete(int id) async {
    return await db.delete(
      tableNovelViewerPersist,
      where: '$cNovel_id = ?',
      whereArgs: [id],
    );
  }

  Future<int> update(NovelViewerPersist todo) async {
    return await db.update(
      tableNovelViewerPersist,
      todo.toJson(),
      where: '$cid = ?',
      whereArgs: [todo.id],
    );
  }

  Future close() async => db.close();

  Future deleteAll() async {
    return await db.delete(tableNovelViewerPersist);
  }
}
