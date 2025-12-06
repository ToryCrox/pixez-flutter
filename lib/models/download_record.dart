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
import 'package:pixez/exts.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/store/download_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// 下载的插画记录
class DownloadedIllust {
  int? id;
  int illustId;
  int userId;
  String userName;
  String title;
  String type;
  String caption;
  String createDate;
  int pageCount;
  int width;
  int height;
  int sanityLevel;
  int xRestrict;
  int totalView;
  int totalBookmarks;
  String tags; // JSON格式存储
  String relativePath; // 相对目录路径
  int downloadTime; // 下载时间戳
  String illustJson; // 完整Illusts JSON

  DownloadedIllust({
    this.id,
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
    required this.illustJson,
  });

  factory DownloadedIllust.fromIllusts(Illusts illusts, String relativePath) {
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
      downloadTime: DateTime.now().millisecondsSinceEpoch,
      illustJson: jsonEncode(illusts.toJson()),
    );
  }

  factory DownloadedIllust.fromJson(Map<String, dynamic> json) {
    return DownloadedIllust(
      id: json[DownloadedIllustColumns.id],
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
    if (id != null) data[DownloadedIllustColumns.id] = id;
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
    return Illusts.fromJson(jsonDecode(illustJson));
  }

  List<Tags> getTagsList() {
    final List<dynamic> tagList = jsonDecode(tags);
    return tagList.map((t) => Tags.fromJson(t)).toList();
  }
}

// 下载的图片记录
class DownloadedImage {
  int? id;
  int illustId;
  int part;
  String fileName;
  String extension;
  int fileSize;
  String originalUrl;
  String relativePath;

  DownloadedImage({
    this.id,
    required this.illustId,
    required this.part,
    required this.fileName,
    required this.extension,
    required this.fileSize,
    required this.originalUrl,
    required this.relativePath,
  });

  factory DownloadedImage.fromJson(Map<String, dynamic> json) {
    return DownloadedImage(
      id: json[DownloadedImageColumns.id],
      illustId: json[DownloadedImageColumns.illustId],
      part: json[DownloadedImageColumns.part],
      fileName: json[DownloadedImageColumns.fileName],
      extension: json[DownloadedImageColumns.extension],
      fileSize: json[DownloadedImageColumns.fileSize],
      originalUrl: json[DownloadedImageColumns.originalUrl],
      relativePath: json[DownloadedImageColumns.relativePath],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (id != null) data[DownloadedImageColumns.id] = id;
    data[DownloadedImageColumns.illustId] = illustId;
    data[DownloadedImageColumns.part] = part;
    data[DownloadedImageColumns.fileName] = fileName;
    data[DownloadedImageColumns.extension] = extension;
    data[DownloadedImageColumns.fileSize] = fileSize;
    data[DownloadedImageColumns.originalUrl] = originalUrl;
    data[DownloadedImageColumns.relativePath] = relativePath;
    return data;
  }

  String getFullFileName() => '$fileName$extension';
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

// 数据库Provider
class DownloadDatabaseProvider {
  late Database db;
  String? _basePath;

  String get basePath => _basePath ?? '';

  Future<void> open(String downloadPath) async {
    _basePath = downloadPath;
    String dbPath = path.join(downloadPath, 'download.db');

    // 确保目录存在
    final dir = Directory(downloadPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    db = await openDatabase(
      dbPath,
      version: 2,
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
      },
    );
  }

  // ============ Illusts 操作 ============

  Future<DownloadedIllust> insertIllust(DownloadedIllust illust) async {
    illust.id = await db.insert(
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

  Future<bool> isIllustDownloaded(int illustId) async {
    final result = await getIllustByIllustId(illustId);
    return result != null;
  }

  Future<List<DownloadedIllust>> getAllIllusts({
    int? limit,
    int? offset,
    bool desc = true,
  }) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      orderBy:
          '${DownloadedIllustColumns.downloadTime} ${desc ? 'DESC' : 'ASC'}',
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  Future<List<DownloadedIllust>> getIllustsByUserId(
    int userId, {
    int? limit,
    int? offset,
  }) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where: '${DownloadedIllustColumns.userId} = ?',
      whereArgs: [userId],
      orderBy: '${DownloadedIllustColumns.downloadTime} DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  Future<List<DownloadedIllust>> searchIllustsByTag(
    String tag, {
    int? limit,
    int? offset,
  }) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where: '${DownloadedIllustColumns.tags} LIKE ?',
      whereArgs: ['%$tag%'],
      orderBy: '${DownloadedIllustColumns.downloadTime} DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  Future<List<DownloadedIllust>> searchIllusts(
    String keyword, {
    int? limit,
    int? offset,
  }) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where:
          '${DownloadedIllustColumns.title} LIKE ? OR ${DownloadedIllustColumns.userName} LIKE ? OR ${DownloadedIllustColumns.tags} LIKE ?',
      whereArgs: ['%$keyword%', '%$keyword%', '%$keyword%'],
      orderBy: '${DownloadedIllustColumns.downloadTime} DESC',
      limit: limit,
      offset: offset,
    );
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
    image.id = await db.insert(
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

  Future<List<DownloadedImage>> getImagesByIllustId(int illustId) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedImageColumns.tableName,
      where: '${DownloadedImageColumns.illustId} = ?',
      whereArgs: [illustId],
      orderBy: '${DownloadedImageColumns.part} ASC',
    );
    return maps.map((e) => DownloadedImage.fromJson(e)).toList();
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
  Future<String?> findImagePath(int illustId, int part) async {
    final image = await getImage(illustId, part);
    if (image == null) return null;

    final basePath = path.join(_basePath!, image.relativePath, image.fileName);

    // 首先尝试数据库中记录的后缀
    String fullPath = '$basePath${image.extension}';
    if (await File(fullPath).exists()) {
      return fullPath;
    }

    // 尝试其他常见后缀
    for (final ext in kImageExtensions) {
      if (ext == image.extension) continue;
      fullPath = '$basePath$ext';
      if (await File(fullPath).exists()) {
        // 更新数据库中的后缀名
        await updateImageExtension(illustId, part, ext);
        return fullPath;
      }
    }

    return null;
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
      where: '${PendingDownloadColumns.id} = ?',
      whereArgs: [illustId],
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
}
