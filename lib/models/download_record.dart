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
 */

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/models/illust.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../custom/log.dart';

/// 支持的图片后缀名
const kImageExtensions = ['.webp', '.jpg', '.png', '.gif', '.jpeg'];

// 下载的插画记录
class DownloadedIllust {
  final int illustId;
  final int userId;
  final String userName;
  final String title;
  final String type;
  final String caption;
  final String createDate;
  final int pageCount;
  final int width;
  final int height;
  final int sanityLevel;
  final int xRestrict;
  final int totalView;
  final int totalBookmarks;
  final String tags; // JSON格式存储
  final String relativePath; // 相对目录路径
  final int downloadTime; // 下载时间戳
  final String _illustJson; // 完整Illusts JSON（私有）

  // Getter 用于数据库序列化
  String get illustJson => _illustJson;

  DownloadedIllust({
    required this.illustId,
    required this.userId,
    required this.userName,
    required this.title,
    required this.type,
    required this.caption,
    required this.createDate,
    required this.pageCount,
    required this.width,
    required this.height,
    required this.sanityLevel,
    required this.xRestrict,
    required this.totalView,
    required this.totalBookmarks,
    required this.tags,
    required this.relativePath,
    required this.downloadTime,
    required String illustJson,
  }) : _illustJson = illustJson;

  factory DownloadedIllust.fromIllusts(Illusts illusts, String relativePath, {int? downloadTime}) {
    // 使用 copyWith 将需要移除的字段设置为空/默认值
    final optimizedIllusts = illusts.copyWith(
      id: 0,
      title: '',
      type: '',
      caption: '',
      createDate: '',
      pageCount: 0,
      width: 0,
      height: 0,
      sanityLevel: 0,
      xRestrict: 0,
      totalView: 0,
      totalBookmarks: 0,
      tags: [],
      user: illusts.user.copyWith(
        id: 0,
        name: '',
      ),
    );
    
    // 转换成 Map
    final optimizedJson = optimizedIllusts.toJson();
    
    // 使用 shrinkMap 移除空值，进一步优化 JSON 大小
    final shrunkJson = TypeUtil.shrinkMap(optimizedJson, copy: false);
    
    return DownloadedIllust(
      illustId: illusts.id,
      userId: illusts.user.id,
      userName: illusts.user.name,
      title: illusts.title,
      type: illusts.type,
      caption: illusts.caption,
      createDate: illusts.createDate,
      pageCount: illusts.pageCount,
      width: illusts.width,
      height: illusts.height,
      sanityLevel: illusts.sanityLevel,
      xRestrict: illusts.xRestrict,
      totalView: illusts.totalView,
      totalBookmarks: illusts.totalBookmarks,
      tags: jsonEncode(illusts.tags.map((t) => t.toJson()).toList()),
      relativePath: relativePath,
      downloadTime: downloadTime ?? DateTime.now().millisecondsSinceEpoch,
      illustJson: jsonEncode(shrunkJson),
    );
  }

  factory DownloadedIllust.fromJson(Map<String, dynamic> json) {
    return DownloadedIllust(
      illustId: json[DownloadedIllustColumns.illustId],
      userId: json[DownloadedIllustColumns.userId],
      userName: json[DownloadedIllustColumns.userName],
      title: json[DownloadedIllustColumns.title],
      type: json[DownloadedIllustColumns.type],
      caption: json[DownloadedIllustColumns.caption],
      createDate: json[DownloadedIllustColumns.createDate],
      pageCount: json[DownloadedIllustColumns.pageCount],
      width: json[DownloadedIllustColumns.width],
      height: json[DownloadedIllustColumns.height],
      sanityLevel: json[DownloadedIllustColumns.sanityLevel],
      xRestrict: json[DownloadedIllustColumns.xRestrict],
      totalView: json[DownloadedIllustColumns.totalView],
      totalBookmarks: json[DownloadedIllustColumns.totalBookmarks],
      tags: json[DownloadedIllustColumns.tags],
      relativePath: json[DownloadedIllustColumns.relativePath],
      downloadTime: json[DownloadedIllustColumns.downloadTime],
      illustJson: json[DownloadedIllustColumns.illustJson],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data[DownloadedIllustColumns.illustId] = illustId;
    data[DownloadedIllustColumns.userId] = userId;
    data[DownloadedIllustColumns.userName] = userName;
    data[DownloadedIllustColumns.title] = title;
    data[DownloadedIllustColumns.type] = type;
    data[DownloadedIllustColumns.caption] = caption;
    data[DownloadedIllustColumns.createDate] = createDate;
    data[DownloadedIllustColumns.pageCount] = pageCount;
    data[DownloadedIllustColumns.width] = width;
    data[DownloadedIllustColumns.height] = height;
    data[DownloadedIllustColumns.sanityLevel] = sanityLevel;
    data[DownloadedIllustColumns.xRestrict] = xRestrict;
    data[DownloadedIllustColumns.totalView] = totalView;
    data[DownloadedIllustColumns.totalBookmarks] = totalBookmarks;
    data[DownloadedIllustColumns.tags] = tags;
    data[DownloadedIllustColumns.relativePath] = relativePath;
    data[DownloadedIllustColumns.downloadTime] = downloadTime;
    data[DownloadedIllustColumns.illustJson] = illustJson;
    return data;
  }

  Illusts toIllusts() {
    // 使用 TypeUtil.parseMap 安全地将字符串转换为 Map
    final json = TypeUtil.parseMap(_illustJson);
    
    // 先从 illustJson 转换成 Illusts（即使 json 为空也能创建默认对象）
    final baseIllusts = Illusts.fromJson(json);
    
    // 使用 copyWith 从表字段赋值，避免硬编码 map 字段
    return baseIllusts.copyWith(
      id: illustId,
      title: title,
      type: type,
      caption: caption,
      createDate: createDate,
      pageCount: pageCount,
      width: width,
      height: height,
      sanityLevel: sanityLevel,
      xRestrict: xRestrict,
      totalView: totalView,
      totalBookmarks: totalBookmarks,
      tags: getTagsList(),
      user: baseIllusts.user.copyWith(
        id: userId,
        name: userName,
      ),
    );
  }

  List<Tags> getTagsList() {
    return TypeUtil.parseList(tags, (e) => Tags.fromMap(TypeUtil.parseMap(e)));
  }
}

/// 本地图片信息，包含路径和宽高
class LocalImageInfo {
  final String path;
  final int? width;
  final int? height;
  final int? fileSize;

  LocalImageInfo({
    required this.path,
    this.width,
    this.height,
    this.fileSize,
  });

  /// 获取宽高比（width / height），如果宽高未知则返回 null
  double? get aspectRatio {
    if (width != null && height != null && height! > 0) {
      return width! / height!;
    }
    return null;
  }

  @override
  String toString() {
    return 'LocalImageInfo{path: $path, width: $width, height: $height, fileSize: $fileSize}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalImageInfo &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          width == other.width &&
          height == other.height &&
          fileSize == other.fileSize;

  @override
  int get hashCode => Object.hash(path, width, height, fileSize);
}

// 下载的图片记录
class DownloadedImage {
  final int illustId;
  final int part;
  final String fileName;
  final String extension;
  final int fileSize;
  final String originalUrl;
  final String relativePath;
  final int? width; // 图片宽度
  final int? height; // 图片高度

  DownloadedImage({
    required this.illustId,
    required this.part,
    required this.fileName,
    required this.extension,
    required this.fileSize,
    required this.originalUrl,
    required this.relativePath,
    this.width,
    this.height,
  });

  factory DownloadedImage.fromJson(Map<String, dynamic> json) {
    return DownloadedImage(
      illustId: json[DownloadedImageColumns.illustId],
      part: json[DownloadedImageColumns.part],
      fileName: json[DownloadedImageColumns.fileName],
      extension: json[DownloadedImageColumns.extension],
      fileSize: json[DownloadedImageColumns.fileSize],
      originalUrl: json[DownloadedImageColumns.originalUrl],
      relativePath: json[DownloadedImageColumns.relativePath],
      width: json[DownloadedImageColumns.width],
      height: json[DownloadedImageColumns.height],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data[DownloadedImageColumns.illustId] = illustId;
    data[DownloadedImageColumns.part] = part;
    data[DownloadedImageColumns.fileName] = fileName;
    data[DownloadedImageColumns.extension] = extension;
    data[DownloadedImageColumns.fileSize] = fileSize;
    data[DownloadedImageColumns.originalUrl] = originalUrl;
    data[DownloadedImageColumns.relativePath] = relativePath;
    data[DownloadedImageColumns.width] = width;
    data[DownloadedImageColumns.height] = height;
    return data;
  }

  String getFullFileName() => '$fileName$extension';

  /// 获取图片宽高比（width / height），如果宽高未知则返回 null
  double? get aspectRatio {
    if (width != null && height != null && height! > 0) {
      return width! / height!;
    }
    return null;
  }
}

// 表名和列名常量
class DownloadedIllustColumns {
  static const String tableName = 'downloaded_illusts';
  static const String id = 'id';
  static const String illustId = 'illust_id';
  static const String userId = 'user_id';
  static const String userName = 'user_name';
  static const String title = 'title';
  static const String type = 'type';
  static const String caption = 'caption';
  static const String createDate = 'create_date';
  static const String pageCount = 'page_count';
  static const String width = 'width';
  static const String height = 'height';
  static const String sanityLevel = 'sanity_level';
  static const String xRestrict = 'x_restrict';
  static const String totalView = 'total_view';
  static const String totalBookmarks = 'total_bookmarks';
  static const String tags = 'tags';
  static const String relativePath = 'relative_path';
  static const String downloadTime = 'download_time';
  static const String illustJson = 'illust_json';
}

class DownloadedImageColumns {
  static const String tableName = 'downloaded_images';
  static const String id = 'id';
  static const String illustId = 'illust_id';
  static const String part = 'part';
  static const String fileName = 'file_name';
  static const String extension = 'extension';
  static const String fileSize = 'file_size';
  static const String originalUrl = 'original_url';
  static const String relativePath = 'relative_path';
  static const String width = 'width';
  static const String height = 'height';
}

// 待下载任务记录
class PendingDownloadColumns {
  static const String tableName = 'pending_downloads';
  static const String id = 'id';
  static const String part = 'part';
  static const String url = 'url';
  static const String illustJson = 'illust_json';
  static const String createTime = 'create_time';
  static const String status = 'status'; // 0=pending, 1=downloading, 2=failed
}

class DownloadedAuthorColumns {
  static const String tableName = 'downloaded_authors';
  static const String userId = 'user_id';
  static const String userName = 'user_name';
  static const String profileImageUrl = 'profile_image_url';
  static const String illustCount = 'illust_count';
  static const String totalFileSize = 'total_file_size';
  static const String lastDownloadTime = 'last_download_time';
  static const String lastUpdateTime = 'last_update_time';
}

class PendingDownload {
  final String id;
  final int part;
  final String url;
  final String illustJson;
  final int createTime;
  final String status;

  PendingDownload({
    required this.id,
    required this.part,
    required this.url,
    required this.illustJson,
    required this.createTime,
    required this.status,
  });

  factory PendingDownload.fromJson(Map<String, dynamic> json) {
    return PendingDownload(
      id: json[PendingDownloadColumns.id],
      part: json[PendingDownloadColumns.part],
      url: json[PendingDownloadColumns.url],
      illustJson: json[PendingDownloadColumns.illustJson],
      createTime: json[PendingDownloadColumns.createTime],
      status: json[PendingDownloadColumns.status] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data[PendingDownloadColumns.id] = id;
    data[PendingDownloadColumns.part] = part;
    data[PendingDownloadColumns.url] = url;
    data[PendingDownloadColumns.illustJson] = illustJson;
    data[PendingDownloadColumns.createTime] = createTime;
    data[PendingDownloadColumns.status] = status;
    return data;
  }
}

// 下载的作者记录
class DownloadedAuthor {
  int userId;
  String userName;
  String? profileImageUrl;
  int illustCount;
  int totalFileSize;
  int lastDownloadTime;
  int lastUpdateTime;

  DownloadedAuthor({
    required this.userId,
    required this.userName,
    this.profileImageUrl,
    required this.illustCount,
    required this.totalFileSize,
    required this.lastDownloadTime,
    required this.lastUpdateTime,
  });

  factory DownloadedAuthor.fromJson(Map<String, dynamic> json) {
    return DownloadedAuthor(
      userId: json[DownloadedAuthorColumns.userId],
      userName: json[DownloadedAuthorColumns.userName],
      profileImageUrl: json[DownloadedAuthorColumns.profileImageUrl],
      illustCount: json[DownloadedAuthorColumns.illustCount] ?? 0,
      totalFileSize: json[DownloadedAuthorColumns.totalFileSize] ?? 0,
      lastDownloadTime: json[DownloadedAuthorColumns.lastDownloadTime] ?? 0,
      lastUpdateTime: json[DownloadedAuthorColumns.lastUpdateTime] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data[DownloadedAuthorColumns.userId] = userId;
    data[DownloadedAuthorColumns.userName] = userName;
    if (profileImageUrl != null) {
      data[DownloadedAuthorColumns.profileImageUrl] = profileImageUrl;
    }
    data[DownloadedAuthorColumns.illustCount] = illustCount;
    data[DownloadedAuthorColumns.totalFileSize] = totalFileSize;
    data[DownloadedAuthorColumns.lastDownloadTime] = lastDownloadTime;
    data[DownloadedAuthorColumns.lastUpdateTime] = lastUpdateTime;
    return data;
  }
}

// 数据库Provider
class DownloadDatabaseProvider {
  late Database db;
  String? _basePath;

  String get basePath => _basePath ?? '';

  Future<void> open(String downloadPath) async {
    // downloadPath 是数据库所在目录，数据库文件在 downloadPath/download.db
    // _basePath 应该指向下载文件的基础目录，即 downloadPath/download
    _basePath = path.join(downloadPath, 'download');
    String dbPath = path.join(downloadPath, 'download.db');

    // 确保目录存在
    final dir = Directory(downloadPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    // 确保下载目录存在
    final downloadDir = Directory(_basePath!);
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    db = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE ${DownloadedIllustColumns.tableName} (
            ${DownloadedIllustColumns.id} INTEGER PRIMARY KEY AUTOINCREMENT,
            ${DownloadedIllustColumns.illustId} INTEGER NOT NULL UNIQUE,
            ${DownloadedIllustColumns.userId} INTEGER NOT NULL,
            ${DownloadedIllustColumns.userName} TEXT NOT NULL,
            ${DownloadedIllustColumns.title} TEXT NOT NULL,
            ${DownloadedIllustColumns.type} TEXT NOT NULL,
            ${DownloadedIllustColumns.caption} TEXT,
            ${DownloadedIllustColumns.createDate} TEXT NOT NULL,
            ${DownloadedIllustColumns.pageCount} INTEGER NOT NULL,
            ${DownloadedIllustColumns.width} INTEGER NOT NULL,
            ${DownloadedIllustColumns.height} INTEGER NOT NULL,
            ${DownloadedIllustColumns.sanityLevel} INTEGER NOT NULL,
            ${DownloadedIllustColumns.xRestrict} INTEGER NOT NULL,
            ${DownloadedIllustColumns.totalView} INTEGER NOT NULL,
            ${DownloadedIllustColumns.totalBookmarks} INTEGER NOT NULL,
            ${DownloadedIllustColumns.tags} TEXT NOT NULL,
            ${DownloadedIllustColumns.relativePath} TEXT NOT NULL,
            ${DownloadedIllustColumns.downloadTime} INTEGER NOT NULL,
            ${DownloadedIllustColumns.illustJson} TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE ${DownloadedImageColumns.tableName} (
            ${DownloadedImageColumns.id} INTEGER PRIMARY KEY AUTOINCREMENT,
            ${DownloadedImageColumns.illustId} INTEGER NOT NULL,
            ${DownloadedImageColumns.part} INTEGER NOT NULL,
            ${DownloadedImageColumns.fileName} TEXT NOT NULL,
            ${DownloadedImageColumns.extension} TEXT NOT NULL,
            ${DownloadedImageColumns.fileSize} INTEGER NOT NULL,
            ${DownloadedImageColumns.originalUrl} TEXT NOT NULL,
            ${DownloadedImageColumns.relativePath} TEXT NOT NULL,
            ${DownloadedImageColumns.width} INTEGER,
            ${DownloadedImageColumns.height} INTEGER,
            UNIQUE(${DownloadedImageColumns.illustId}, ${DownloadedImageColumns.part})
          )
        ''');

        // 创建待下载任务表
        await db.execute('''
          CREATE TABLE ${PendingDownloadColumns.tableName} (
            ${PendingDownloadColumns.id} TEXT PRIMARY KEY,
            ${PendingDownloadColumns.part} INTEGER NOT NULL,
            ${PendingDownloadColumns.url} TEXT NOT NULL,
            ${PendingDownloadColumns.illustJson} TEXT NOT NULL,
            ${PendingDownloadColumns.createTime} INTEGER NOT NULL,
            ${PendingDownloadColumns.status} TEXT NOT NULL DEFAULT 'pending'
          )
        ''');

        // 创建作者表
        await db.execute('''
          CREATE TABLE ${DownloadedAuthorColumns.tableName} (
            ${DownloadedAuthorColumns.userId} INTEGER PRIMARY KEY,
            ${DownloadedAuthorColumns.userName} TEXT NOT NULL,
            ${DownloadedAuthorColumns.profileImageUrl} TEXT,
            ${DownloadedAuthorColumns.illustCount} INTEGER DEFAULT 0,
            ${DownloadedAuthorColumns.totalFileSize} INTEGER DEFAULT 0,
            ${DownloadedAuthorColumns.lastDownloadTime} INTEGER,
            ${DownloadedAuthorColumns.lastUpdateTime} INTEGER
          )
        ''');

        // 创建索引
        await db.execute('''
          CREATE INDEX idx_illust_user ON ${DownloadedIllustColumns.tableName}(${DownloadedIllustColumns.userId})
        ''');
        await db.execute('''
          CREATE INDEX idx_image_illust ON ${DownloadedImageColumns.tableName}(${DownloadedImageColumns.illustId})
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          // 添加待下载任务表
          await db.execute('''
            CREATE TABLE IF NOT EXISTS ${PendingDownloadColumns.tableName} (
              ${PendingDownloadColumns.id} TEXT PRIMARY KEY,
              ${PendingDownloadColumns.part} INTEGER NOT NULL,
              ${PendingDownloadColumns.url} TEXT NOT NULL,
              ${PendingDownloadColumns.illustJson} TEXT NOT NULL,
              ${PendingDownloadColumns.createTime} INTEGER NOT NULL,
              ${PendingDownloadColumns.status} TEXT NOT NULL DEFAULT 'pending'
            )
          ''');
        }
        if (oldVersion < 3) {
          // 为图片表添加宽高字段
          await db.execute('''
            ALTER TABLE ${DownloadedImageColumns.tableName} 
            ADD COLUMN ${DownloadedImageColumns.width} INTEGER
          ''');
          await db.execute('''
            ALTER TABLE ${DownloadedImageColumns.tableName} 
            ADD COLUMN ${DownloadedImageColumns.height} INTEGER
          ''');
        }
        if (oldVersion < 4) {
          // 创建作者表
          await db.execute('''
            CREATE TABLE IF NOT EXISTS ${DownloadedAuthorColumns.tableName} (
              ${DownloadedAuthorColumns.userId} INTEGER PRIMARY KEY,
              ${DownloadedAuthorColumns.userName} TEXT NOT NULL,
              ${DownloadedAuthorColumns.profileImageUrl} TEXT,
              ${DownloadedAuthorColumns.illustCount} INTEGER DEFAULT 0,
              ${DownloadedAuthorColumns.totalFileSize} INTEGER DEFAULT 0,
              ${DownloadedAuthorColumns.lastDownloadTime} INTEGER,
              ${DownloadedAuthorColumns.lastUpdateTime} INTEGER
            )
          ''');
          // 从现有数据生成作者表
          await _migrateAuthorsFromIllusts(db);
        }
      },
    );
  }

  // ============ Illusts 操作 ============

  Future<DownloadedIllust> insertIllust(DownloadedIllust illust) async {
    await db.insert(
      DownloadedIllustColumns.tableName,
      illust.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return illust;
  }

  Future<DownloadedIllust?> getIllustByIllustId(int illustId) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illustId],
    );
    if (maps.isNotEmpty) {
      return DownloadedIllust.fromJson(maps.first);
    }
    return null;
  }

  /// 更新插画信息（保留原有的 downloadTime 和 relativePath）
  Future<int> updateIllust(DownloadedIllust illust) async {
    return await db.update(
      DownloadedIllustColumns.tableName,
      illust.toJson(),
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illust.illustId],
    );
  }

  Future<bool> isIllustDownloaded(int illustId) async {
    final result = await getIllustByIllustId(illustId);
    return result != null;
  }

  Future<List<DownloadedIllust>> getAllIllusts({
    int? limit,
    int? offset,
    bool desc = true,
    String? orderBy,
  }) async {
    // 如果按文件大小排序，需要使用 JOIN 查询
    if (orderBy != null && orderBy.contains('total_file_size')) {
      final orderDirection = orderBy.contains('DESC') ? 'DESC' : 'ASC';
      var query = '''
        SELECT di.*, COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
        FROM ${DownloadedIllustColumns.tableName} di
        LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
        GROUP BY di.${DownloadedIllustColumns.id}
        ORDER BY total_file_size $orderDirection
      ''';
      final args = <dynamic>[];
      if (limit != null) {
        query += ' LIMIT ?';
        args.add(limit);
      }
      if (offset != null) {
        query += ' OFFSET ?';
        args.add(offset);
      }
      final maps = await db.rawQuery(query, args);
      return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
    }
    
    final orderByClause = orderBy ?? '${DownloadedIllustColumns.downloadTime} ${desc ? 'DESC' : 'ASC'}';
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      orderBy: orderByClause,
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  Future<List<DownloadedIllust>> getIllustsByUserId(
    int userId, {
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    // 如果按文件大小排序，需要使用 JOIN 查询
    if (orderBy != null && orderBy.contains('total_file_size')) {
      final orderDirection = orderBy.contains('DESC') ? 'DESC' : 'ASC';
      var query = '''
        SELECT di.*, COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
        FROM ${DownloadedIllustColumns.tableName} di
        LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
        WHERE di.${DownloadedIllustColumns.userId} = ?
        GROUP BY di.${DownloadedIllustColumns.id}
        ORDER BY total_file_size $orderDirection
      ''';
      final args = <dynamic>[userId];
      if (limit != null) {
        query += ' LIMIT ?';
        args.add(limit);
      }
      if (offset != null) {
        query += ' OFFSET ?';
        args.add(offset);
      }
      final maps = await db.rawQuery(query, args);
      return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
    }
    
    final orderByClause = orderBy ?? '${DownloadedIllustColumns.downloadTime} DESC';
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where: '${DownloadedIllustColumns.userId} = ?',
      whereArgs: [userId],
      orderBy: orderByClause,
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  Future<List<DownloadedIllust>> searchIllustsByTag(
    String tag, {
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    // 如果按文件大小排序，需要使用 JOIN 查询
    if (orderBy != null && orderBy.contains('total_file_size')) {
      final orderDirection = orderBy.contains('DESC') ? 'DESC' : 'ASC';
      var query = '''
        SELECT di.*, COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
        FROM ${DownloadedIllustColumns.tableName} di
        LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
        WHERE di.${DownloadedIllustColumns.tags} LIKE ?
        GROUP BY di.${DownloadedIllustColumns.id}
        ORDER BY total_file_size $orderDirection
      ''';
      final args = <dynamic>['%$tag%'];
      if (limit != null) {
        query += ' LIMIT ?';
        args.add(limit);
      }
      if (offset != null) {
        query += ' OFFSET ?';
        args.add(offset);
      }
      final maps = await db.rawQuery(query, args);
      return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
    }
    
    final orderByClause = orderBy ?? '${DownloadedIllustColumns.downloadTime} DESC';
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where: '${DownloadedIllustColumns.tags} LIKE ?',
      whereArgs: ['%$tag%'],
      orderBy: orderByClause,
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  Future<List<DownloadedIllust>> searchIllusts(
    String keyword, {
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    // 如果按文件大小排序，需要使用 JOIN 查询
    if (orderBy != null && orderBy.contains('total_file_size')) {
      final orderDirection = orderBy.contains('DESC') ? 'DESC' : 'ASC';
      var query = '''
        SELECT di.*, COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
        FROM ${DownloadedIllustColumns.tableName} di
        LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
        WHERE di.${DownloadedIllustColumns.title} LIKE ? OR di.${DownloadedIllustColumns.userName} LIKE ? OR di.${DownloadedIllustColumns.tags} LIKE ?
        GROUP BY di.${DownloadedIllustColumns.id}
        ORDER BY total_file_size $orderDirection
      ''';
      final args = <dynamic>['%$keyword%', '%$keyword%', '%$keyword%'];
      if (limit != null) {
        query += ' LIMIT ?';
        args.add(limit);
      }
      if (offset != null) {
        query += ' OFFSET ?';
        args.add(offset);
      }
      final maps = await db.rawQuery(query, args);
      return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
    }
    
    final orderByClause = orderBy ?? '${DownloadedIllustColumns.downloadTime} DESC';
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where:
          '${DownloadedIllustColumns.title} LIKE ? OR ${DownloadedIllustColumns.userName} LIKE ? OR ${DownloadedIllustColumns.tags} LIKE ?',
      whereArgs: ['%$keyword%', '%$keyword%', '%$keyword%'],
      orderBy: orderByClause,
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  /// 获取所有未下载完整的作品（下载的图片数量小于 pageCount）
  /// 使用 SQL JOIN 和 HAVING 子句优化查询，避免在应用层逐个检查
  /// 这个查询会扫描所有作品，但使用数据库索引可以大幅提升性能
  Future<List<DownloadedIllust>> getIncompleteIllusts({
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    // 构建基础查询：使用 LEFT JOIN 和 GROUP BY，然后用 HAVING 过滤
    // 注意：SQLite 中 GROUP BY 后可以使用分组列，所以 di.page_count 在 HAVING 中是可用的
    var query = '''
      SELECT di.*, COUNT(img.${DownloadedImageColumns.illustId}) as downloaded_count
      FROM ${DownloadedIllustColumns.tableName} di
      LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
      GROUP BY di.${DownloadedIllustColumns.id}
      HAVING COUNT(img.${DownloadedImageColumns.illustId}) < di.${DownloadedIllustColumns.pageCount}
    ''';
    
    final args = <dynamic>[];
    
    // 处理排序
    if (orderBy != null) {
      if (orderBy.contains('total_file_size')) {
        // 如果按文件大小排序，需要重新构建查询
        final orderDirection = orderBy.contains('DESC') ? 'DESC' : 'ASC';
        query = '''
          SELECT di.*, 
                 COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size,
                 COUNT(img.${DownloadedImageColumns.illustId}) as downloaded_count
          FROM ${DownloadedIllustColumns.tableName} di
          LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
          GROUP BY di.${DownloadedIllustColumns.id}
          HAVING COUNT(img.${DownloadedImageColumns.illustId}) < di.${DownloadedIllustColumns.pageCount}
          ORDER BY total_file_size $orderDirection
        ''';
      } else {
        query += ' ORDER BY $orderBy';
      }
    } else {
      query += ' ORDER BY di.${DownloadedIllustColumns.downloadTime} DESC';
    }
    
    // 添加 LIMIT 和 OFFSET
    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
    }
    if (offset != null) {
      query += ' OFFSET ?';
      args.add(offset);
    }
    
    final maps = await db.rawQuery(query, args);
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  Future<int> deleteIllustByIllustId(int illustId) async {
    // 先删除关联的图片记录
    await db.delete(
      DownloadedImageColumns.tableName,
      where: '${DownloadedImageColumns.illustId} = ?',
      whereArgs: [illustId],
    );
    // 再删除插画记录
    return await db.delete(
      DownloadedIllustColumns.tableName,
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illustId],
    );
  }

  Future<int> getIllustCount() async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DownloadedIllustColumns.tableName}',
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<List<Map<String, dynamic>>> getDistinctUsers() async {
    return await db.rawQuery('''
      SELECT DISTINCT ${DownloadedIllustColumns.userId}, ${DownloadedIllustColumns.userName}, COUNT(*) as count
      FROM ${DownloadedIllustColumns.tableName}
      GROUP BY ${DownloadedIllustColumns.userId}
      ORDER BY count DESC
    ''');
  }

  // ============ Images 操作 ============

  Future<DownloadedImage> insertImage(DownloadedImage image) async {
    await db.insert(
      DownloadedImageColumns.tableName,
      image.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return image;
  }

  Future<DownloadedImage?> getImage(int illustId, int part) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedImageColumns.tableName,
      where:
          '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, part],
    );
    if (maps.isNotEmpty) {
      return DownloadedImage.fromJson(maps.first);
    }
    return null;
  }

  Future<bool> isImageDownloaded(int illustId, int part) async {
    return await getImage(illustId, part) != null;
  }

  /// 批量检查图片是否已下载
  /// 返回一个 Set，包含已下载的 (illustId, part) 组合的 Map
  Future<Set<Map<String, int>>> batchCheckImageDownloaded(List<Map<String, int>> illustParts) async {
    if (illustParts.isEmpty) return {};
    
    final result = <Map<String, int>>{};
    
    // 按 illust_id 分组，减少 OR 条件的数量
    final groupedByIllustId = <int, Set<int>>{};
    for (final item in illustParts) {
      final illustId = item['illustId']!;
      final part = item['part']!;
      groupedByIllustId.putIfAbsent(illustId, () => <int>{}).add(part);
    }
    
    // 分批处理 illust_id，每批最多 50 个 illust_id
    // 这样可以避免单个查询的 OR 条件过多
    const batchSize = 50;
    final illustIds = groupedByIllustId.keys.toList();
    
    for (int i = 0; i < illustIds.length; i += batchSize) {
      final batchIllustIds = illustIds.skip(i).take(batchSize).toList();
      
      // 构建查询：WHERE illust_id IN (?, ?, ...) AND (part IN (?, ?, ...) OR ...)
      // 但这样仍然可能复杂，改用更简单的方式：对每个 illust_id 单独查询其 parts
      for (final illustId in batchIllustIds) {
        final parts = groupedByIllustId[illustId]!.toList();
        
        // 对每个 illust_id 的 parts 也进行分批，每批最多 100 个 part
        const partBatchSize = 100;
        for (int j = 0; j < parts.length; j += partBatchSize) {
          final batchParts = parts.skip(j).take(partBatchSize).toList();
          
          final placeholders = List.filled(batchParts.length, '?').join(',');
          final maps = await db.query(
            DownloadedImageColumns.tableName,
            columns: [DownloadedImageColumns.illustId, DownloadedImageColumns.part],
            where: '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} IN ($placeholders)',
            whereArgs: [illustId, ...batchParts],
          );
          
          result.addAll(
            maps.map((e) => {
              'illustId': e[DownloadedImageColumns.illustId] as int,
              'part': e[DownloadedImageColumns.part] as int,
            }),
          );
        }
      }
    }
    
    return result;
  }

  /// 通过原始URL查询图片记录
  Future<DownloadedImage?> getImageByOriginalUrl(String originalUrl) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedImageColumns.tableName,
      where: '${DownloadedImageColumns.originalUrl} = ?',
      whereArgs: [originalUrl],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return DownloadedImage.fromJson(maps.first);
    }
    return null;
  }

  Future<List<DownloadedImage>> getImagesByIllustId(int illustId) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedImageColumns.tableName,
      where: '${DownloadedImageColumns.illustId} = ?',
      whereArgs: [illustId],
      orderBy: '${DownloadedImageColumns.part} ASC',
    );
    return maps.map((e) => DownloadedImage.fromJson(e)).toList();
  }

  /// 批量获取插画的所有图片信息及其完整路径（自动检测后缀名）
  /// 返回 Map<part, LocalImageInfo>
  Future<Map<int, LocalImageInfo>> getLocalImageInfosByIllustId(int illustId) async {
    final t1 = DateTime.now();
    final images = await getImagesByIllustId(illustId);
    Log.d('getLocalImageInfosByIllustId: ${images.length} images, ${DateTime.now().difference(t1).inMilliseconds}ms');
    
    // 并行处理所有图片，大幅提升性能
    final futures = images.map((image) async {
      final foundPath = await _findImagePathForImage(image);
      if (foundPath != null) {
        return MapEntry(image.part, LocalImageInfo(
          path: foundPath,
          width: image.width,
          height: image.height,
          fileSize: image.fileSize,
        ));
      }
      return null;
    });
    
    final results = await Future.wait(futures);
    final result = <int, LocalImageInfo>{};
    for (final entry in results) {
      if (entry != null) {
        result[entry.key] = entry.value;
      }
    }
    
    return result;
  }

  /// 根据图片记录查找实际存在的文件路径（自动检测后缀名）
  Future<String?> _findImagePathForImage(DownloadedImage image, {bool update = true}) async {
    final basePath = path.join(_basePath!, image.relativePath, image.fileName);

    // 首先尝试数据库中记录的后缀（最常见的情况）
    String fullPath = '$basePath${image.extension}';
    if (await File(fullPath).exists()) {
      return fullPath;
    }

    // 并行检查其他常见后缀，提升性能
    final otherExtensions = kImageExtensions.where((ext) => ext != image.extension).toList();
    final checkFutures = otherExtensions.map((ext) async {
      final testPath = '$basePath$ext';
      if (await File(testPath).exists()) {
        return testPath;
      }
      return null;
    });
    
    final results = await Future.wait(checkFutures);
    for (int i = 0; i < results.length; i++) {
      if (results[i] != null) {
        final foundPath = results[i]!;
        if (update){
          // 更新数据库中的后缀名（异步执行，不阻塞返回）
          updateImageExtension(image.illustId, image.part, otherExtensions[i]).catchError((e) {
            Log.e('Failed to update image extension: $e');
            return 0; // 返回默认值以满足 catchError 的要求
          });
        }
        
        return foundPath;
      }
    }

    return null;
  }

  /// 更新图片的文件大小和宽高信息
  Future<int> updateImageFileSizeAndDimensions(
    int illustId,
    int part,
    int fileSize,
    int width,
    int height,
  ) async {
    return await db.update(
      DownloadedImageColumns.tableName,
      {
        DownloadedImageColumns.fileSize: fileSize,
        DownloadedImageColumns.width: width,
        DownloadedImageColumns.height: height,
      },
      where:
          '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, part],
    );
  }

  Future<int> updateImageExtension(
    int illustId,
    int part,
    String newExtension,
  ) async {
    return await db.update(
      DownloadedImageColumns.tableName,
      {DownloadedImageColumns.extension: newExtension},
      where:
          '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, part],
    );
  }

  /// 更新图片的宽高信息
  Future<int> updateImageDimensions(
    int illustId,
    int part,
    int width,
    int height,
  ) async {
    return await db.update(
      DownloadedImageColumns.tableName,
      {
        DownloadedImageColumns.width: width,
        DownloadedImageColumns.height: height,
      },
      where:
          '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, part],
    );
  }

  /// 获取需要更新宽高的图片列表（宽高为空的记录）
  Future<List<DownloadedImage>> getImagesWithoutDimensions({int? limit}) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedImageColumns.tableName,
      where:
          '${DownloadedImageColumns.width} IS NULL OR ${DownloadedImageColumns.height} IS NULL',
      limit: limit,
    );
    return maps.map((e) => DownloadedImage.fromJson(e)).toList();
  }

  Future<int> deleteImage(int illustId, int part) async {
    return await db.delete(
      DownloadedImageColumns.tableName,
      where:
          '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, part],
    );
  }

  Future<int> getDownloadedImageCount(int illustId) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DownloadedImageColumns.tableName} WHERE ${DownloadedImageColumns.illustId} = ?',
      [illustId],
    );
    return result.first['count'] as int? ?? 0;
  }

  /// 获取插画的图片统计信息（数量和总文件大小）
  /// 返回：已下载图片数量和总文件大小（字节）的记录
  Future<({int count, int totalFileSize})> getIllustImageStats(int illustId) async {
    final result = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as count,
        COALESCE(SUM(${DownloadedImageColumns.fileSize}), 0) as total_file_size
      FROM ${DownloadedImageColumns.tableName}
      WHERE ${DownloadedImageColumns.illustId} = ?
      ''',
      [illustId],
    );
    
    if (result.isNotEmpty) {
      return (
        count: result.first['count'] as int? ?? 0,
        totalFileSize: result.first['total_file_size'] as int? ?? 0,
      );
    }
    return (count: 0, totalFileSize: 0);
  }

  // ============ 路径工具 ============

  /// 生成作者目录名
  static String buildUserDirName(String userName, int userId) {
    return '[${userName.toLegal()}][$userId]';
  }

  /// 生成作品目录名
  static String buildIllustDirName(int illustId, String title) {
    return '[$illustId]${title.toLegal()}';
  }

  /// 生成文件名（不含后缀）
  static String buildFileName(int illustId, int part) {
    return '${illustId}_p$part';
  }

  /// 生成相对路径
  static String buildRelativePath(Illusts illusts) {
    final userDir = buildUserDirName(illusts.user.name, illusts.user.id);
    final illustDir = buildIllustDirName(illusts.id, illusts.title);
    return path.join(userDir, illustDir);
  }

  /// 获取图片的完整文件路径
  Future<String?> getImageFullPath(int illustId, int part) async {
    final image = await getImage(illustId, part);
    if (image == null) return null;

    final fullPath =
        path.join(_basePath!, image.relativePath, image.getFullFileName());
    return fullPath;
  }

  /// 尝试找到图片文件（自动检测后缀名）
  Future<String?> findImagePath(int illustId, int part, {bool update = true}) async {
    final image = await getImage(illustId, part);
    if (image == null) return null;
    return await _findImagePathForImage(image, update: update);
  }

  Future<LocalImageInfo?> getLocalImageInfoByUrl(String url) async {
    final image = await getImageByOriginalUrl(url);
    if (image == null) return null;
    final imagePath = await _findImagePathForImage(image);
    if (imagePath == null) return null;
    return LocalImageInfo(
      path: imagePath,
      width: image.width,
      height: image.height,
    );
  }

  // ============ 数据迁移 ============

  /// 从现有插画数据生成作者表（用于数据库升级）
  static Future<void> _migrateAuthorsFromIllusts(Database db) async {
    try {
      // 获取所有不同的用户及其统计信息
      final users = await db.rawQuery('''
        SELECT 
          ${DownloadedIllustColumns.userId},
          ${DownloadedIllustColumns.userName},
          COUNT(*) as count,
          MAX(${DownloadedIllustColumns.downloadTime}) as last_download_time
        FROM ${DownloadedIllustColumns.tableName}
        GROUP BY ${DownloadedIllustColumns.userId}
      ''');

      for (final user in users) {
        final userId = user[DownloadedIllustColumns.userId] as int;
        final userName = user[DownloadedIllustColumns.userName] as String;
        final count = user['count'] as int;
        final lastDownloadTime = user['last_download_time'] as int? ?? 0;

        // 获取最新插画的 JSON 来解析用户头像
        final latestIllust = await db.query(
          DownloadedIllustColumns.tableName,
          where: '${DownloadedIllustColumns.userId} = ?',
          whereArgs: [userId],
          orderBy: '${DownloadedIllustColumns.downloadTime} DESC',
          limit: 1,
        );

        String? profileImageUrl;
        if (latestIllust.isNotEmpty) {
          try {
            final illustJson = jsonDecode(
                latestIllust.first[DownloadedIllustColumns.illustJson] as String);
            profileImageUrl = illustJson['user']?['profile_image_urls']?['medium'];
          } catch (_) {}
        }

        // 计算总文件大小
        final images = await db.query(
          DownloadedImageColumns.tableName,
          where: '${DownloadedImageColumns.illustId} IN (SELECT ${DownloadedIllustColumns.illustId} FROM ${DownloadedIllustColumns.tableName} WHERE ${DownloadedIllustColumns.userId} = ?)',
          whereArgs: [userId],
        );
        int totalFileSize = 0;
        for (final image in images) {
          totalFileSize += image[DownloadedImageColumns.fileSize] as int? ?? 0;
        }

        // 插入作者记录
        await db.insert(
          DownloadedAuthorColumns.tableName,
          {
            DownloadedAuthorColumns.userId: userId,
            DownloadedAuthorColumns.userName: userName,
            DownloadedAuthorColumns.profileImageUrl: profileImageUrl,
            DownloadedAuthorColumns.illustCount: count,
            DownloadedAuthorColumns.totalFileSize: totalFileSize,
            DownloadedAuthorColumns.lastDownloadTime: lastDownloadTime,
            DownloadedAuthorColumns.lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      Log.e('迁移作者数据失败: $e');
    }
  }

  // ============ Author 操作 ============

  /// 插入或更新作者信息
  Future<void> upsertAuthor(
    int userId,
    String userName,
    String? profileImageUrl,
    int illustCount,
    int totalFileSize,
    int lastDownloadTime,
  ) async {
    await db.insert(
      DownloadedAuthorColumns.tableName,
      {
        DownloadedAuthorColumns.userId: userId,
        DownloadedAuthorColumns.userName: userName,
        DownloadedAuthorColumns.profileImageUrl: profileImageUrl,
        DownloadedAuthorColumns.illustCount: illustCount,
        DownloadedAuthorColumns.totalFileSize: totalFileSize,
        DownloadedAuthorColumns.lastDownloadTime: lastDownloadTime,
        DownloadedAuthorColumns.lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取作者信息
  Future<DownloadedAuthor?> getAuthorByUserId(int userId) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedAuthorColumns.tableName,
      where: '${DownloadedAuthorColumns.userId} = ?',
      whereArgs: [userId],
    );
    if (maps.isNotEmpty) {
      return DownloadedAuthor.fromJson(maps.first);
    }
    return null;
  }

  /// 获取作者列表，支持排序
  /// sortBy: 'last_download_time', 'user_name', 'illust_count'
  Future<List<DownloadedAuthor>> getAuthorsWithStats({
    String sortBy = 'last_download_time',
    bool desc = true,
    int? limit,
    int? offset,
  }) async {
    String orderBy = sortBy;
    if (desc) {
      orderBy += ' DESC';
    } else {
      orderBy += ' ASC';
    }

    List<Map<String, dynamic>> maps = await db.query(
      DownloadedAuthorColumns.tableName,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedAuthor.fromJson(e)).toList();
  }

  /// 更新作者统计信息（从插画表重新计算）
  Future<void> updateAuthorStats(int userId) async {
    // 获取插画数量
    final illustCount = await db.rawQuery('''
      SELECT COUNT(*) as count 
      FROM ${DownloadedIllustColumns.tableName} 
      WHERE ${DownloadedIllustColumns.userId} = ?
    ''', [userId]);
    final count = illustCount.first['count'] as int? ?? 0;

    // 获取最新下载时间
    final latestTime = await db.rawQuery('''
      SELECT MAX(${DownloadedIllustColumns.downloadTime}) as last_time
      FROM ${DownloadedIllustColumns.tableName}
      WHERE ${DownloadedIllustColumns.userId} = ?
    ''', [userId]);
    final lastDownloadTime = latestTime.first['last_time'] as int? ?? 0;

    // 获取最新插画的 JSON 来解析用户名和头像
    final latestIllust = await db.query(
      DownloadedIllustColumns.tableName,
      where: '${DownloadedIllustColumns.userId} = ?',
      whereArgs: [userId],
      orderBy: '${DownloadedIllustColumns.downloadTime} DESC',
      limit: 1,
    );

    String userName = '';
    String? profileImageUrl;
    if (latestIllust.isNotEmpty) {
      try {
        final illustJson = jsonDecode(
            latestIllust.first[DownloadedIllustColumns.illustJson] as String);
        userName = illustJson['user']?['name'] ?? 
                   latestIllust.first[DownloadedIllustColumns.userName] as String;
        profileImageUrl = illustJson['user']?['profile_image_urls']?['medium'];
      } catch (_) {
        userName = latestIllust.first[DownloadedIllustColumns.userName] as String;
      }
    }

    // 计算总文件大小
    final images = await db.rawQuery('''
      SELECT SUM(${DownloadedImageColumns.fileSize}) as total
      FROM ${DownloadedImageColumns.tableName}
      WHERE ${DownloadedImageColumns.illustId} IN (
        SELECT ${DownloadedIllustColumns.illustId} 
        FROM ${DownloadedIllustColumns.tableName} 
        WHERE ${DownloadedIllustColumns.userId} = ?
      )
    ''', [userId]);
    final totalFileSize = images.first['total'] as int? ?? 0;

    // 更新或插入作者记录
    await upsertAuthor(
      userId,
      userName,
      profileImageUrl,
      count,
      totalFileSize,
      lastDownloadTime,
    );
  }

  /// 如果作者没有插画则删除
  Future<void> deleteAuthorIfEmpty(int userId) async {
    final count = await db.rawQuery('''
      SELECT COUNT(*) as count 
      FROM ${DownloadedIllustColumns.tableName} 
      WHERE ${DownloadedIllustColumns.userId} = ?
    ''', [userId]);
    if ((count.first['count'] as int? ?? 0) == 0) {
      await db.delete(
        DownloadedAuthorColumns.tableName,
        where: '${DownloadedAuthorColumns.userId} = ?',
        whereArgs: [userId],
      );
    }
  }

  /// 获取作者的图片统计信息（总图片张数和总文件大小）
  /// 使用优化的SQL查询，一次性获取两个统计值
  Future<Map<String, int>> getAuthorImageStats(int userId) async {
    final result = await db.rawQuery('''
      SELECT 
        COUNT(${DownloadedImageColumns.id}) as total_image_count,
        COALESCE(SUM(${DownloadedImageColumns.fileSize}), 0) as total_file_size
      FROM ${DownloadedImageColumns.tableName}
      WHERE ${DownloadedImageColumns.illustId} IN (
        SELECT ${DownloadedIllustColumns.illustId} 
        FROM ${DownloadedIllustColumns.tableName} 
        WHERE ${DownloadedIllustColumns.userId} = ?
      )
    ''', [userId]);
    
    if (result.isNotEmpty) {
      return {
        'total_image_count': result.first['total_image_count'] as int? ?? 0,
        'total_file_size': result.first['total_file_size'] as int? ?? 0,
      };
    }
    return {'total_image_count': 0, 'total_file_size': 0};
  }

  /// 获取筛选条件下的统计信息
  /// 返回：插画数量、图片数量（实际下载的图片记录数）、文件大小
  /// filterType: 'all', 'user', 'search', 'incomplete'
  Future<Map<String, int>> getFilteredStats({
    String filterType = 'all',
    int? userId,
    String? searchKeyword,
  }) async {
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (filterType == 'user' && userId != null) {
      whereClause = 'WHERE di.${DownloadedIllustColumns.userId} = ?';
      whereArgs.add(userId);
    } else if (filterType == 'search' && searchKeyword != null && searchKeyword.isNotEmpty) {
      whereClause = 'WHERE di.${DownloadedIllustColumns.title} LIKE ? OR di.${DownloadedIllustColumns.userName} LIKE ? OR di.${DownloadedIllustColumns.tags} LIKE ?';
      whereArgs.addAll(['%$searchKeyword%', '%$searchKeyword%', '%$searchKeyword%']);
    } else if (filterType == 'incomplete') {
      // 未下载完整：需要特殊处理，先找出所有未下载完整的作品ID
      final incompleteIllusts = await db.rawQuery('''
        SELECT di.${DownloadedIllustColumns.illustId}, di.${DownloadedIllustColumns.pageCount}
        FROM ${DownloadedIllustColumns.tableName} di
        LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
        GROUP BY di.${DownloadedIllustColumns.id}
        HAVING COUNT(img.${DownloadedImageColumns.illustId}) < di.${DownloadedIllustColumns.pageCount}
      ''');
      
      if (incompleteIllusts.isEmpty) {
        return {'illust_count': 0, 'image_count': 0, 'file_size': 0};
      }
      
      final illustIds = incompleteIllusts.map((e) => e[DownloadedIllustColumns.illustId] as int).toList();
      final placeholders = List.filled(illustIds.length, '?').join(',');
      
      // 统计这些作品的图片数量和文件大小
      final stats = await db.rawQuery('''
        SELECT 
          COUNT(DISTINCT di.${DownloadedIllustColumns.id}) as illust_count,
          COUNT(img.${DownloadedImageColumns.id}) as total_image_count,
          COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
        FROM ${DownloadedIllustColumns.tableName} di
        LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
        WHERE di.${DownloadedIllustColumns.illustId} IN ($placeholders)
      ''', illustIds);
      
      if (stats.isNotEmpty) {
        return {
          'illust_count': stats.first['illust_count'] as int? ?? 0,
          'image_count': stats.first['total_image_count'] as int? ?? 0,
          'file_size': stats.first['total_file_size'] as int? ?? 0,
        };
      }
      return {'illust_count': 0, 'image_count': 0, 'file_size': 0};
    }

    // 对于其他情况，使用标准查询
    // 统计实际下载的图片数量，而不是 pageCount 总和
    final query = '''
      SELECT 
        COUNT(DISTINCT di.${DownloadedIllustColumns.id}) as illust_count,
        COUNT(img.${DownloadedImageColumns.id}) as total_image_count,
        COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
      FROM ${DownloadedIllustColumns.tableName} di
      LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
      $whereClause
    ''';

    final result = await db.rawQuery(query, whereArgs);
    
    if (result.isNotEmpty) {
      return {
        'illust_count': result.first['illust_count'] as int? ?? 0,
        'image_count': result.first['total_image_count'] as int? ?? 0,
        'file_size': result.first['total_file_size'] as int? ?? 0,
      };
    }
    return {'illust_count': 0, 'image_count': 0, 'file_size': 0};
  }

  // ============ PendingDownload 操作 ============

  /// 插入待下载任务
  Future<PendingDownload> insertPendingDownload(PendingDownload pending) async {
    await db.insert(
      PendingDownloadColumns.tableName,
      pending.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return pending;
  }

  /// 获取所有待下载任务
  Future<List<PendingDownload>> getAllPendingDownloads() async {
    List<Map<String, dynamic>> maps = await db.query(
      PendingDownloadColumns.tableName,
      orderBy: '${PendingDownloadColumns.createTime} ASC',
    );
    return maps.map((e) => PendingDownload.fromJson(e)).toList();
  }

  /// 获取指定状态的待下载任务
  Future<List<PendingDownload>> getPendingDownloadsByStatus(List<String> status) async {
    List<Map<String, dynamic>> maps = await db.query(
      PendingDownloadColumns.tableName,
      where: '${PendingDownloadColumns.status} IN (${status.map((e) => '?').join(',')})',
      whereArgs: [...status],
      orderBy: '${PendingDownloadColumns.createTime} ASC',
    );
    return maps.map((e) => PendingDownload.fromJson(e)).toList();
  }

  /// 更新任务状态
  Future<int> updatePendingDownloadStatus(
    String id,
    String status,
  ) async {
    return await db.update(
      PendingDownloadColumns.tableName,
      {PendingDownloadColumns.status: status},
      where: '${PendingDownloadColumns.id} = ?',
      whereArgs: [id],
    );
  }

  /// 删除待下载任务
  Future<int> deletePendingDownload(String id) async {
    return await db.delete(
      PendingDownloadColumns.tableName,
      where: '${PendingDownloadColumns.id} = ?',
      whereArgs: [id],
    );
  }

  /// 删除插画的所有待下载任务
  Future<int> deletePendingDownloadsByIllustId(int illustId) async {
    return await db.delete(
      PendingDownloadColumns.tableName,
      where: '${PendingDownloadColumns.id} LIKE ?',
      whereArgs: ['${illustId}_%'],
    );
  }

  /// 清空所有待下载任务
  Future<int> clearAllPendingDownloads() async {
    return await db.delete(PendingDownloadColumns.tableName);
  }

  /// 检查任务是否存在
  Future<bool> isPendingDownloadExists(String id) async {
    final result = await db.query(
      PendingDownloadColumns.tableName,
      where: '${PendingDownloadColumns.id} = ?',
      whereArgs: [id],
    );
    return result.isNotEmpty;
  }

  /// 获取待下载任务数量
  Future<int> getPendingDownloadCount() async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${PendingDownloadColumns.tableName}',
    );
    return result.first['count'] as int? ?? 0;
  }

  /// 批量插入待下载任务（使用事务优化性能）
  Future<void> batchInsertPendingDownloads(List<PendingDownload> pendings) async {
    if (pendings.isEmpty) return;
    
    final batch = db.batch();
    for (final pending in pendings) {
      batch.insert(
        PendingDownloadColumns.tableName,
        pending.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 批量删除待下载任务（使用事务优化性能）
  Future<void> batchDeletePendingDownloads(List<String> taskKeys) async {
    if (taskKeys.isEmpty) return;
    
    // 分批删除，每批最多 1000 条，避免 SQL 语句过长
    const batchSize = 1000;
    
    for (int i = 0; i < taskKeys.length; i += batchSize) {
      final batch = taskKeys.skip(i).take(batchSize).toList();
      final dbBatch = db.batch();
      
      for (final key in batch) {
        dbBatch.delete(
          PendingDownloadColumns.tableName,
          where: '${PendingDownloadColumns.id} = ?',
          whereArgs: [key],
        );
      }
      
      await dbBatch.commit(noResult: true);
    }
  }

  /// 批量检查并插入插画记录（使用事务优化性能）
  /// 返回已存在的 illustId 集合
  Future<Set<int>> batchInsertIllustsIfNotExists(List<DownloadedIllust> illusts) async {
    if (illusts.isEmpty) return {};
    
    // 先批量查询已存在的 illustId
    final illustIds = illusts.map((e) => e.illustId).toList();
    final existingIds = <int>{};
    
    // 分批查询，每批最多 1000 条
    const batchSize = 1000;
    for (int i = 0; i < illustIds.length; i += batchSize) {
      final batch = illustIds.skip(i).take(batchSize).toList();
      final placeholders = batch.map((_) => '?').join(',');
      final maps = await db.rawQuery(
        'SELECT ${DownloadedIllustColumns.illustId} FROM ${DownloadedIllustColumns.tableName} WHERE ${DownloadedIllustColumns.illustId} IN ($placeholders)',
        batch,
      );
      existingIds.addAll(maps.map((e) => e[DownloadedIllustColumns.illustId] as int));
    }
    
    // 过滤出需要插入的 illusts
    final illustsToInsert = illusts.where((e) => !existingIds.contains(e.illustId)).toList();
    
    if (illustsToInsert.isEmpty) return existingIds;
    
    // 批量插入
    final dbBatch = db.batch();
    for (final illust in illustsToInsert) {
      dbBatch.insert(
        DownloadedIllustColumns.tableName,
        illust.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await dbBatch.commit(noResult: true);
    
    return existingIds;
  }

  /// 执行 VACUUM 命令，回收数据库空间
  Future<void> vacuum() async {
    try {
      await db.execute('VACUUM');
      Log.d('数据库 VACUUM 执行完成');
    } catch (e) {
      Log.e('执行 VACUUM 失败: $e');
      rethrow;
    }
  }
}
