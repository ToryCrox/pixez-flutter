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

class BanTagPersist {
  final int? id;
  final String name;
  final String translateName;

  const BanTagPersist({this.id, this.name = '', this.translateName = ''});

  factory BanTagPersist.fromMap(Map<String, dynamic> map) => BanTagPersist(
        id: map.optIntOrNull('id'),
        name: map.optString('name'),
        translateName: map.optString('translate_name'),
      );
  factory BanTagPersist.fromJson(Map<String, dynamic> json) =>
      BanTagPersist.fromMap(json);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'translate_name': translateName,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([id, name, translateName]);

  BanTagPersist copyWith({
    Object? id = TypeUtil.unset,
    String? name,
    String? translateName,
  }) => BanTagPersist(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        name: name ?? this.name,
        translateName: translateName ?? this.translateName,
      );

  @override
  bool operator ==(Object other) =>
      other is BanTagPersist && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'BanTagPersist(${toMap()})';
}

extension BanTagPersistExtension on BanTagPersist {
  bool isRegexMatch(String tag) {
    if (name == tag) {
      return true;
    }
    if (!name.startsWith('r\'') || !name.endsWith('\'')) {
      return false;
    }
    try {
      final str = name.substring(2, name.length - 1);
      final regex = RegExp(str);
      return regex.hasMatch(tag);
    } catch (e) {
      return false;
    }
  }
}

final String columnId = 'id';
final String columnTranslateName = 'translate_name';
final String columnName = 'name';
final String tableBanTag = 'bantag';

class BanTagProvider {
  late Database db;

  Future open() async {
    String databasesPath = (await getDatabasesPath());
    String path = join(databasesPath, 'bantag.db');
    db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table $tableBanTag ( 
  $columnId integer primary key autoincrement, 
  $columnTranslateName text not null,
  $columnName text not null
  )
''');
      },
    );
    // 注册到数据库管理中心
    DatabaseRegistry.instance.register('标签屏蔽数据库', path, () => db);
  }

  Future<BanTagPersist> insert(BanTagPersist todo) async {
    final id = await db.insert(
      tableBanTag,
      todo.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return todo.copyWith(id: id);
  }

  Future<BanTagPersist?> getAccount(int id) async {
    List<Map<String, dynamic>> maps = await db.query(
      tableBanTag,
      columns: [columnId, columnTranslateName],
      where: '$columnId = ?',
      whereArgs: [id],
    );
    if (maps.length > 0) {
      return BanTagPersist.fromJson(maps.first);
    }
    return null;
  }

  Future<List<BanTagPersist>> getAllAccount() async {
    List<BanTagPersist> result = [];
    List<Map<String, dynamic>> maps = await db.query(
      tableBanTag,
      columns: [columnId, columnTranslateName, columnName],
    );

    if (maps.length > 0) {
      maps.forEach((f) {
        result.add(BanTagPersist.fromJson(f));
      });
    }
    return result;
  }

  Future<int> delete(int id) async {
    return await db.delete(
      tableBanTag,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAll() async {
    return await db.delete(tableBanTag);
  }

  Future<int> update(BanTagPersist todo) async {
    return await db.update(
      tableBanTag,
      todo.toJson(),
      where: '$columnId = ?',
      whereArgs: [todo.id],
    );
  }

  Future close() async => db.close();

  Future<List<BanTagPersist>> insertAll(List<BanTagPersist> list) async {
    final result = <BanTagPersist>[];
    await db.transaction((txn) async {
      for (final todo in list) {
        final id = await txn.insert(
          tableBanTag,
          todo.toJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        result.add(todo.copyWith(id: id));
      }
    });
    return result;
  }
}
