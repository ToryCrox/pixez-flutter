import 'package:path/path.dart';
import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final String columnId = 'id';
final String columnCommentId = 'comment_id';
final String columnName = 'name';
final String tableBanComment = 'banComment';

class BanCommentPersist {
  final String commentId;
  final String name;
  final int? id;

  const BanCommentPersist({this.commentId = '', this.name = '', this.id});

  factory BanCommentPersist.fromMap(Map<String, dynamic> map) =>
      BanCommentPersist(
        commentId: map.optString('comment_id'),
        name: map.optString('name'),
        id: map.optIntOrNull('id'),
      );

  factory BanCommentPersist.fromJson(Map<String, dynamic> json) =>
      BanCommentPersist.fromMap(json);

  Map<String, dynamic> toMap() => {
        'comment_id': commentId,
        'name': name,
        'id': id,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([commentId, name, id]);

  BanCommentPersist copyWith({
    String? commentId,
    String? name,
    Object? id = TypeUtil.unset,
  }) => BanCommentPersist(
        commentId: commentId ?? this.commentId,
        name: name ?? this.name,
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
      );

  @override
  bool operator ==(Object other) => other is BanCommentPersist &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'BanCommentPersist(${toMap()})';
}

class BanCommenProvider {
  late Database db;

  Future open() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'banncommentid.db');
    db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table $tableBanComment ( 
  $columnId integer primary key autoincrement, 
  $columnCommentId text not null,
  $columnName text not null
  )
''');
      },
    );
    DatabaseRegistry.instance.register('评论屏蔽数据库', path, () => db);
  }

  Future<BanCommentPersist> insert(BanCommentPersist todo) async {
    final id = await db.insert(
      tableBanComment,
      todo.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return todo.copyWith(id: id);
  }

  Future<BanCommentPersist?> getAccount(int id) async {
    final maps = await db.query(
      tableBanComment,
      columns: [columnId, columnCommentId, columnName],
      where: '$columnId = ?',
      whereArgs: [id],
    );
    return maps.isEmpty ? null : BanCommentPersist.fromJson(maps.first);
  }

  Future<List<BanCommentPersist>> getAllAccount() async {
    final maps = await db.query(
      tableBanComment,
      columns: [columnId, columnCommentId, columnName],
    );
    return maps.map(BanCommentPersist.fromJson).toList();
  }

  Future<int> delete(int id) =>
      db.delete(tableBanComment, where: '$columnId = ?', whereArgs: [id]);
  Future<int> deleteAll() => db.delete(tableBanComment);

  Future<int> update(BanCommentPersist todo) => db.update(
        tableBanComment,
        todo.toJson(),
        where: '$columnId = ?',
        whereArgs: [todo.id],
      );

  Future close() => db.close();
}
