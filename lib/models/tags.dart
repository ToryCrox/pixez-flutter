/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 */
import 'package:path/path.dart';
import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AutoWords {
  final List<Tags> tags;

  const AutoWords({this.tags = const []});
  factory AutoWords.fromMap(Map<String, dynamic> map) => AutoWords(
        tags: [
          ...map.optList('tags', (e) => Tags.fromMap(TypeUtil.parseMap(e))),
        ],
      );
  factory AutoWords.fromJson(Map<String, dynamic> json) => AutoWords.fromMap(json);
  Map<String, dynamic> toMap() => {'tags': tags.map((e) => e.toMap()).toList()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => tags.isEmpty;
  AutoWords copyWith({List<Tags>? tags}) => AutoWords(
        tags: tags == null ? [...this.tags] : [...tags],
      );
  @override
  bool operator ==(Object other) => other is AutoWords && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'AutoWords(${toMap()})';
}

class Tags {
  final String name;
  final String? translatedName;

  const Tags({this.name = '', this.translatedName});
  factory Tags.fromMap(Map<String, dynamic> map) => Tags(
        name: map.optString('name'),
        translatedName: map.optStringOrNull('translated_name'),
      );
  factory Tags.fromJson(Map<String, dynamic> json) => Tags.fromMap(json);
  Map<String, dynamic> toMap() => {'name': name, 'translated_name': translatedName};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([name, translatedName]);
  Tags copyWith({String? name, Object? translatedName = TypeUtil.unset}) => Tags(
        name: name ?? this.name,
        translatedName: identical(translatedName, TypeUtil.unset)
            ? this.translatedName
            : translatedName as String?,
      );
  @override
  bool operator ==(Object other) => other is Tags && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Tags(${toMap()})';
}

class TagsPersist {
  final int? id;
  final String name;
  final String translatedName;
  final int? type;

  const TagsPersist({
    this.id,
    this.name = '',
    this.translatedName = '',
    this.type = 0,
  });

  factory TagsPersist.fromMap(Map<String, dynamic> map) => TagsPersist(
        id: map.optIntOrNull('_id'),
        name: map.optString('name'),
        translatedName: map.optString('translated_name'),
        type: map.optIntOrNull('type'),
      );
  factory TagsPersist.fromJson(Map<String, dynamic> json) => TagsPersist.fromMap(json);
  Map<String, dynamic> toMap() => {
        '_id': id,
        'name': name,
        'translated_name': translatedName,
        'type': type,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([id, name, translatedName, type]);

  TagsPersist copyWith({
    Object? id = TypeUtil.unset,
    String? name,
    String? translatedName,
    Object? type = TypeUtil.unset,
  }) => TagsPersist(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        name: name ?? this.name,
        translatedName: translatedName ?? this.translatedName,
        type: identical(type, TypeUtil.unset) ? this.type : type as int?,
      );
  @override
  bool operator ==(Object other) => other is TagsPersist && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'TagsPersist(${toMap()})';
}

final String tableTag = 'tag';
final String columnId = '_id';
final String columnName = 'name';
final String columnTranslatedName = 'translated_name';
final String columnType = 'type';

class TagsPersistProvider {
  late Database db;

  Future open() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, '${tableTag}.db');
    db = await openDatabase(
      path,
      version: 2,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table $tableTag ( 
  $columnId integer primary key autoincrement, 
  $columnName text not null,
  $columnTranslatedName text not null,
  $columnType integer)
''');
      },
      onUpgrade: (db, oldVer, newVer) async {
        final batch = db.batch();
        if (oldVer == 1) _updateTableCompanyV1toV2(batch);
        await batch.commit();
      },
    );
    DatabaseRegistry.instance.register('标签数据库', path, () => db);
  }

  void _updateTableCompanyV1toV2(Batch batch) {
    batch.execute('ALTER TABLE $tableTag ADD $columnType integer');
  }

  Future<TagsPersist> insert(TagsPersist tag) async {
    final id = await db.insert(
      tableTag,
      tag.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return tag.copyWith(id: id);
  }

  Future<List<TagsPersist>> insertAll(List<TagsPersist> tags) async {
    final result = <TagsPersist>[];
    await db.transaction((txn) async {
      for (final tag in tags) {
        final id = await txn.insert(
          tableTag,
          tag.toJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        result.add(tag.copyWith(id: id));
      }
    });
    return result;
  }

  Future<TagsPersist?> getTodo(int id) async {
    final maps = await db.query(
      tableTag,
      columns: [columnId, columnName, columnTranslatedName, columnType],
      where: '$columnId = ?',
      whereArgs: [id],
    );
    return maps.isEmpty ? null : TagsPersist.fromJson(maps.first);
  }

  Future<List<TagsPersist>> getAllAccount() async {
    final maps = await db.query(
      tableTag,
      columns: [columnId, columnName, columnTranslatedName, columnType],
      orderBy: '$columnId DESC',
    );
    return maps.map(TagsPersist.fromJson).toList();
  }

  Future<int> delete(int id) => db.delete(tableTag, where: '$columnId = ?', whereArgs: [id]);
  Future<int> deleteAll({int type = 0}) => db.delete(tableTag, where: '$columnType = ?', whereArgs: [type]);
  Future<int> update(TagsPersist todo) => db.update(
        tableTag,
        todo.toJson(),
        where: '$columnId = ?',
        whereArgs: [todo.id],
      );
  Future close() => db.close();
}
