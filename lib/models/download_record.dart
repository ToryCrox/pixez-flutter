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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:pixez/custom/pixiv_url_util.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/ugoira_metadata_response.dart';
import 'package:pixez/platform/macos_file_access.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../custom/log.dart';

part 'download_record_const.dart';

// 数据库Provider
class DownloadDatabaseProvider {
  late Database db;
  /// 下载目录
  String? _downloadPath;
  String? _basePath;
  String? _coverPath;
  String? _avatarPath;
  String? _ugoiraTempPath;
  String? _dbPath;

  /// Tag变更事件流
  final _tagChangesController = StreamController<List<TagChangeEvent>>.broadcast();

  // 缓存：作品 ID -> 相对路径
  final Map<int, String> _illustRelPathCache = {};
  // 缓存：作者 ID -> 作者目录名
  final Map<int, String> _authorDirCache = {};

  Stream<List<TagChangeEvent>> get tagChanges => _tagChangesController.stream;

  String get downloadPath => _downloadPath ?? '';

  String get dbPathStr => _dbPath ?? '';

  String get coverPath => _coverPath ?? '';

  String get avatarPath => _avatarPath ?? '';

  String get ugoiraTempPath => _ugoiraTempPath ?? '';

  Future<void> open(String basePath) async {
    /// 创建下载目录
    _basePath = basePath;
    _downloadPath = path.join(basePath, 'download');
    _coverPath = path.join(basePath, 'covers');
    _avatarPath = path.join(basePath, 'avatars');
    _ugoiraTempPath = path.join(basePath, 'ugoira');
    _dbPath = path.join(basePath, 'download.db');
    String dbPath = _dbPath!;

    try {
      // macOS: 检查并请求外部存储访问权限
      if (Platform.isMacOS && MacOSFileAccessManager.isExternalVolume(downloadPath)) {
        Log.d(() => '🔐 检测到外部存储卷: $downloadPath');
        Log.d(() => '正在检查访问权限...');

        // 检查是否已有 bookmark（支持下载路径本身或其任意父目录）
        bool hasBookmark = await MacOSFileAccessManager.hasBookmark(downloadPath);

        if (!hasBookmark) {
          Log.w(() => '⚠️  未找到访问权限，需要用户授权');
          Log.i(() => '提示: 请在文件选择器中选择下载目录或其父目录');
          Log.i(() => '     例如选择: $downloadPath');
          Log.i(() => '     或选择: ${MacOSFileAccessManager.getRootPath(downloadPath)}');

          final (success, selectedPath) = await MacOSFileAccessManager.requestDirectoryAccess();
          if (!success || selectedPath == null) {
            throw Exception('用户取消授权或授权失败');
          }

          // 验证选择的路径是下载路径的父目录
          if (!downloadPath.startsWith(selectedPath)) {
            throw Exception('选择的目录无效：必须是 $downloadPath 的父目录或本身');
          }

          Log.i(() => '✅ 用户已授权访问: $selectedPath');
        }

        // 开始访问外部存储（Swift 端会自动查找最匹配的父目录 bookmark）
        final accessGranted = await MacOSFileAccessManager.startAccessingPath(downloadPath);
        if (!accessGranted) {
          throw Exception('无法获取外部存储访问权限，请重新授权');
        }

        Log.i(() => '✅ 已获取外部存储访问权限');
      }
      
      // 确保目录存在
      final dir = Directory(downloadPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 确保下载目录存在
      final downloadDir = Directory(_downloadPath!);
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      // 检查数据库文件访问权限
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        // 尝试读取文件以验证访问权限
        try {
          await dbFile.open(mode: FileMode.read).then((f) => f.close());
        } catch (e) {
          Log.e(() => 'ERROR: 无法访问数据库文件 $dbPath', error: e);

          if (Platform.isMacOS && MacOSFileAccessManager.isExternalVolume(downloadPath)) {
            Log.e(() => '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
            Log.e(() => '⚠️  外部存储访问失败');
            Log.e(() => '可能的原因:');
            Log.e(() => '1. Security-Scoped Bookmark 已失效，需要重新授权');
            Log.e(() => '2. 外部存储卷已被卸载或路径变化');
            Log.e(() => '3. 文件系统权限不足');
            Log.e(() => '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

            // 尝试清除旧的 bookmark 并重新请求
            await MacOSFileAccessManager.clearBookmark(downloadPath);
            throw Exception('外部存储访问失败，请重新启动应用并重新授权');
          }

          rethrow;
        }
      }


      db = await openDatabase(
        dbPath,
        version: 16,
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
            ${DownloadedIllustColumns.illustJson} TEXT NOT NULL,
            ${DownloadedIllustColumns.imageUrlsJson} TEXT NOT NULL DEFAULT '',
            ${DownloadedIllustColumns.ugoiraMetadataJson} TEXT NOT NULL DEFAULT '',
            ${DownloadedIllustColumns.downloadedImageCount} INTEGER DEFAULT 0,
            ${DownloadedIllustColumns.totalFileSize} INTEGER DEFAULT 0,
            ${DownloadedIllustColumns.bookmark} INTEGER DEFAULT 0
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
            ${PendingDownloadColumns.status} TEXT NOT NULL DEFAULT 'pending',
            ${PendingDownloadColumns.bookmark} INTEGER DEFAULT 0
          )
        ''');

        // 创建作者表
        await db.execute('''
          CREATE TABLE ${DownloadedAuthorColumns.tableName} (
            ${DownloadedAuthorColumns.userId} INTEGER PRIMARY KEY,
            ${DownloadedAuthorColumns.userName} TEXT NOT NULL,
            ${DownloadedAuthorColumns.profileImageUrl} TEXT,
            ${DownloadedAuthorColumns.illustCount} INTEGER DEFAULT 0,
            ${DownloadedAuthorColumns.totalImageCount} INTEGER DEFAULT 0,
            ${DownloadedAuthorColumns.totalFileSize} INTEGER DEFAULT 0,
            ${DownloadedAuthorColumns.lastDownloadTime} INTEGER,
            ${DownloadedAuthorColumns.lastUpdateTime} INTEGER,
            ${DownloadedAuthorColumns.bookmark} INTEGER DEFAULT 0
          )
        ''');

        // 创建标签管理表
        await db.execute('''
          CREATE TABLE ${DownloadedTagsColumns.tableName} (
             ${DownloadedTagsColumns.id} INTEGER PRIMARY KEY AUTOINCREMENT,
             ${DownloadedTagsColumns.name} TEXT NOT NULL UNIQUE,
             ${DownloadedTagsColumns.translatedName} TEXT,
             ${DownloadedTagsColumns.customTranslatedName} TEXT,
             ${DownloadedTagsColumns.category} INTEGER DEFAULT 0,
             ${DownloadedTagsColumns.isBookmarked} INTEGER DEFAULT 0,
             ${DownloadedTagsColumns.displayOrder} INTEGER DEFAULT 0,
             ${DownloadedTagsColumns.lastUsedTime} INTEGER,
             ${DownloadedTagsColumns.count} INTEGER DEFAULT 0,
             ${DownloadedTagsColumns.exampleIllusts} TEXT,
             ${DownloadedTagsColumns.referencedTagId} INTEGER,
             ${DownloadedTagsColumns.parentId} INTEGER
          )
        ''');

        // 创建标签-作品关联表
        await db.execute('''
          CREATE TABLE ${DownloadedIllustTagsColumns.tableName} (
             ${DownloadedIllustTagsColumns.illustId} INTEGER NOT NULL,
             ${DownloadedIllustTagsColumns.tagId} INTEGER NOT NULL,
             ${DownloadedIllustTagsColumns.source} INTEGER DEFAULT 0,
             PRIMARY KEY (${DownloadedIllustTagsColumns.illustId}, ${DownloadedIllustTagsColumns.tagId})
          )
        ''');

        // 创建索引
        await db.execute('''
          CREATE INDEX idx_illust_user ON ${DownloadedIllustColumns.tableName}(${DownloadedIllustColumns.userId})
        ''');
        await db.execute('''
          CREATE INDEX idx_image_illust ON ${DownloadedImageColumns.tableName}(${DownloadedImageColumns.illustId})
        ''');
        // 排序字段索引
        await db.execute('''
          CREATE INDEX idx_illust_download_time ON ${DownloadedIllustColumns.tableName}(${DownloadedIllustColumns.downloadTime})
        ''');
        await db.execute('''
          CREATE INDEX idx_illust_create_date ON ${DownloadedIllustColumns.tableName}(${DownloadedIllustColumns.createDate})
        ''');
        // 作者表排序字段索引
        await db.execute('''
          CREATE INDEX idx_author_last_download_time ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.lastDownloadTime})
        ''');
        await db.execute('''
          CREATE INDEX idx_author_user_name ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.userName})
        ''');
        await db.execute('''
          CREATE INDEX idx_author_illust_count ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.illustCount})
        ''');
        await db.execute('''
          CREATE INDEX idx_author_total_image_count ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.totalImageCount})
        ''');
        await db.execute('''
          CREATE INDEX idx_author_total_file_size ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.totalFileSize})
        ''');
        // 收藏字段索引
        await db.execute('''
          CREATE INDEX idx_author_bookmark ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.bookmark})
        ''');
        await db.execute('''
          CREATE INDEX idx_illust_bookmark ON ${DownloadedIllustColumns.tableName}(${DownloadedIllustColumns.bookmark})
        ''');
        // 标签表索引
        await db.execute('''
          CREATE INDEX idx_tags_category ON ${DownloadedTagsColumns.tableName}(${DownloadedTagsColumns.category})
        ''');
        await db.execute('''
          CREATE INDEX idx_tags_display_order ON ${DownloadedTagsColumns.tableName}(${DownloadedTagsColumns.displayOrder})
        ''');
        await db.execute('''
          CREATE INDEX idx_tags_referenced_tag ON ${DownloadedTagsColumns.tableName}(${DownloadedTagsColumns.referencedTagId})
        ''');
        await db.execute('''
          CREATE INDEX idx_tags_parent ON ${DownloadedTagsColumns.tableName}(${DownloadedTagsColumns.parentId})
        ''');
        // 关联表索引
        await db.execute('''
          CREATE INDEX idx_illust_tags_tag ON ${DownloadedIllustTagsColumns.tableName}(${DownloadedIllustTagsColumns.tagId})
        ''');
        await db.execute('''
          CREATE INDEX idx_illust_tags_illust ON ${DownloadedIllustTagsColumns.tableName}(${DownloadedIllustTagsColumns.illustId})
        ''');
        // 统计字段索引
        await db.execute('''
          CREATE INDEX idx_illust_total_file_size ON ${DownloadedIllustColumns.tableName}(${DownloadedIllustColumns.totalFileSize})
        ''');
        await db.execute('''
          CREATE INDEX idx_illust_downloaded_count ON ${DownloadedIllustColumns.tableName}(${DownloadedIllustColumns.downloadedImageCount})
        ''');

      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        Log.i(() => '升级数据库 $oldVersion -> $newVersion');

        // v15 -> v16: 添加 bookmark 字段到 pending_downloads
        if (oldVersion < 16) {
          Log.i(() => '添加 bookmark 字段到 pending_downloads 表');
          await db.execute('ALTER TABLE ${PendingDownloadColumns.tableName} ADD COLUMN ${PendingDownloadColumns.bookmark} INTEGER DEFAULT 0');
        }
      }
    );
    } catch (e, stackTrace) {
      Log.e(() => '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Log.e(() => '数据库打开失败');
      Log.e(() => '数据库路径: $dbPath', error: e, stackTrace: stackTrace);
      Log.e(() => '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // 如果是外部存储卷，给出特别提示
      if (downloadPath.startsWith('/Volumes/')) {
        Log.w(() => '⚠️  检测到数据库位于外部存储卷');
        Log.w(() => '可能的解决方案:');
        Log.w(() => '1. 确保外部存储卷已正确挂载并可访问');
        Log.w(() => '2. 检查macOS应用权限设置，确保应用有访问外部存储的权限');
        Log.w(() => '3. 尝试将下载路径更改到应用目录或用户目录下');
        Log.w(() => '4. 如果问题持续，请尝试重新创建数据库');
        Log.w(() => '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      }

      rethrow;
    }
  }

  // ============ Illusts 操作 ============

  Future<DownloadedIllust> insertIllust(DownloadedIllust illust) async {
    await db.insert(
      DownloadedIllustColumns.tableName,
      illust.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Sync tags
    updateTagsRelations(illust);
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
    final result = await db.update(
      DownloadedIllustColumns.tableName,
      illust.toJson(),
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illust.illustId],
    );
    // Sync tags
    updateTagsRelations(illust);
    return result;
  }

  /// 更新插画收藏/优先级
  Future<void> updateIllustBookmark(int illustId, int bookmark) async {
    await db.update(
      DownloadedIllustColumns.tableName,
      {DownloadedIllustColumns.bookmark: bookmark},
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illustId],
    );
  }


  
  /// 更新插画的标签关联信息
  Future<void> updateTagsRelations(DownloadedIllust illust) async {
    try {
      final illustsObj = illust.toIllusts();
      final illustId = illust.illustId;
      final newTags = illustsObj.tags;
      final squareMediumUrl = illustsObj.imageUrls.squareMedium;
      
      final events = <TagChangeEvent>[];
      
      await db.transaction((txn) async {
        // 1. 获取现有tag关联
        final existingTagIds = await _getExistingTagIds(txn, illustId);
        
        // 2. 确保新tags存在于数据库
        await _ensureTagsExist(txn, newTags);
        
        // 3. 获取新tags的ID
        final newTagsData = await _queryTagsByNames(txn, newTags.map((t) => t.name).toList());
        final newTagIds = newTagsData.keys.toSet();
        
        // 4. 计算需要新增和删除的tag
        final toAdd = newTagIds.difference(existingTagIds);
        final toRemove = existingTagIds.difference(newTagIds);
        
        // 5. 处理新增
        for (final tagId in toAdd) {
          final tag = newTagsData[tagId]!;
          await _addTagRelation(txn, illustId, tagId);
          final event = await _updateTagStats(
            txn: txn,
            tagId: tagId,
            tag: tag,
            illustId: illustId,
            changeType: TagChangeType.illustAdded,
            squareMediumUrl: squareMediumUrl,
          );
          events.add(event);
        }
        
        // 6. 处理删除
        if (toRemove.isNotEmpty) {
          final removeTagsData = await _queryTagsByIds(txn, toRemove.toList());
          for (final tagId in toRemove) {
            final tag = removeTagsData[tagId]!;
            await _removeTagRelation(txn, illustId, tagId);
            final event = await _updateTagStats(
              txn: txn,
              tagId: tagId,
              tag: tag,
              illustId: illustId,
              changeType: TagChangeType.illustRemoved,
            );
            events.add(event);
          }
        }
      });
      
      // 7. 发送事件通知
      if (events.isNotEmpty) {
        _tagChangesController.add(events);
      }
    } catch (e, s) {
      Log.e('Updated tags relations failed: $e', stackTrace: s);
    }
  }

  /// 获取插画现有的tag ID集合(仅原始tag)
  Future<Set<int>> _getExistingTagIds(Transaction txn, int illustId) async {
    final relations = await txn.query(
      DownloadedIllustTagsColumns.tableName,
      columns: [DownloadedIllustTagsColumns.tagId],
      where: '${DownloadedIllustTagsColumns.illustId} = ? AND ${DownloadedIllustTagsColumns.source} = ?',
      whereArgs: [illustId, 0],
    );
    return relations.map((r) => TypeUtil.parseInt(r[DownloadedIllustTagsColumns.tagId])).toSet();
  }

  /// 确保tags存在于数据库中
  Future<void> _ensureTagsExist(Transaction txn, List<Tags> tags) async {
    for (final tag in tags) {
      await txn.insert(
        DownloadedTagsColumns.tableName,
        {
          DownloadedTagsColumns.name: tag.name,
          DownloadedTagsColumns.translatedName: tag.translatedName ?? '',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// 根据tag名称批量查询tag数据
  Future<Map<int, DownloadedTag>> _queryTagsByNames(Transaction txn, List<String> names) async {
    if (names.isEmpty) return {};
    
    final placeholders = List.filled(names.length, '?').join(',');
    final rows = await txn.query(
      DownloadedTagsColumns.tableName,
      where: '${DownloadedTagsColumns.name} IN ($placeholders)',
      whereArgs: names,
    );
    
    return {for (var row in rows) TypeUtil.parseInt(row[DownloadedTagsColumns.id]): DownloadedTag.fromJson(row)};
  }

  /// 根据tag ID批量查询tag数据
  Future<Map<int, DownloadedTag>> _queryTagsByIds(Transaction txn, List<int> ids) async {
    if (ids.isEmpty) return {};
    
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await txn.query(
      DownloadedTagsColumns.tableName,
      where: '${DownloadedTagsColumns.id} IN ($placeholders)',
      whereArgs: ids,
    );
    
    return {for (var row in rows) TypeUtil.parseInt(row[DownloadedTagsColumns.id]): DownloadedTag.fromJson(row)};
  }

  /// 添加tag关联
  Future<void> _addTagRelation(Transaction txn, int illustId, int tagId) async {
    await txn.insert(
      DownloadedIllustTagsColumns.tableName,
      {
        DownloadedIllustTagsColumns.illustId: illustId,
        DownloadedIllustTagsColumns.tagId: tagId,
        DownloadedIllustTagsColumns.source: 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 删除tag关联
  Future<void> _removeTagRelation(Transaction txn, int illustId, int tagId) async {
    await txn.delete(
      DownloadedIllustTagsColumns.tableName,
      where: '${DownloadedIllustTagsColumns.illustId} = ? AND ${DownloadedIllustTagsColumns.tagId} = ?',
      whereArgs: [illustId, tagId],
    );
  }

  /// 更新tag统计信息并返回事件
  Future<TagChangeEvent> _updateTagStats({
    required Transaction txn,
    required int tagId,
    required DownloadedTag tag,
    required int illustId,
    required TagChangeType changeType,
    String? squareMediumUrl,
  }) async {
    final tagName = tag.name;
    final examplesStr = tag.exampleIllusts;
    
    // 更新示例插画列表
    final examples = examplesStr.isEmpty ? <String>[] : examplesStr.split(',');
    final illustIdStr = illustId.toString();
    
    // 根据变更类型更新 examples
    if (changeType == TagChangeType.illustAdded) {
      if (examples.length < 3 && !examples.contains(illustIdStr)) {
        examples.add(illustIdStr);
      }
    } else {
      examples.remove(illustIdStr);
    }

    // 重新计算作品总数 (Recalculate count from DB to ensure accuracy)
    final countResult = await txn.rawQuery(
      'SELECT COUNT(*) as count FROM ${DownloadedIllustTagsColumns.tableName} WHERE ${DownloadedIllustTagsColumns.tagId} = ?',
      [tagId],
    );
    final int newCount = countResult.first['count'] as int? ?? 0;
    
    // 更新数据库
    final updateData = {
      DownloadedTagsColumns.count: newCount,
      DownloadedTagsColumns.exampleIllusts: examples.join(','),
    };
    
    // 仅在新增时更新 lastUsedTime
    if (changeType == TagChangeType.illustAdded) {
      updateData[DownloadedTagsColumns.lastUsedTime] = DateTime.now().millisecondsSinceEpoch;
    }
    
    await txn.update(
      DownloadedTagsColumns.tableName,
      updateData,
      where: '${DownloadedTagsColumns.id} = ?',
      whereArgs: [tagId],
    );
    
    return TagChangeEvent(
      tagId: tagId,
      tagName: tagName,
      type: changeType,
      illustId: illustId,
      squareMediumUrl: squareMediumUrl,
      newCount: newCount,
      newExampleIllustIds: examples.map(int.parse).toList(),
    );
  }

  /// 更新动图元数据（用于修复损坏或丢失的元数据）
  Future<int> updateUgoiraMetadata(int illustId, String ugoiraMetadataJson) async {
    return await db.update(
      DownloadedIllustColumns.tableName,
      {DownloadedIllustColumns.ugoiraMetadataJson: ugoiraMetadataJson},
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illustId],
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
    bool filterBookmarks = false,
  }) async {
    // total_file_size 已物化到表中，无需 JOIN 查询
    String orderByClause = orderBy ??
        '${DownloadedIllustColumns.downloadTime} ${desc ? 'DESC' : 'ASC'}';
    if (filterBookmarks) {
      orderByClause = '${DownloadedIllustColumns.bookmark} DESC, $orderByClause';
    }

    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where: filterBookmarks ? '${DownloadedIllustColumns.bookmark} > 0' : null,
      orderBy: orderByClause,
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  /// 获取包含非 WebP 图片的插画（排除动图）
  Future<List<DownloadedIllust>> getIllustsWithNonWebPImages({
    int? limit,
    int? offset,
    String? orderBy,
    bool filterBookmarks = false,
  }) async {
    String orderByClause = orderBy ??
        'di.${DownloadedIllustColumns.downloadTime} DESC';
    if (filterBookmarks) {
      orderByClause = 'di.${DownloadedIllustColumns.bookmark} DESC, $orderByClause';
    }

    final bookmarkCondition = filterBookmarks ? 'AND di.${DownloadedIllustColumns.bookmark} > 0' : '';

    // 查询包含非 .webp 后缀图片的普通插画 (ugoira 除外)
    // 使用 EXISTS 子查询避免重复记录
    var query = '''
      SELECT di.*
      FROM ${DownloadedIllustColumns.tableName} di
      WHERE di.${DownloadedIllustColumns.type} != 'ugoira'
      $bookmarkCondition
      AND EXISTS (
        SELECT 1 
        FROM ${DownloadedImageColumns.tableName} dim 
        WHERE dim.${DownloadedImageColumns.illustId} = di.${DownloadedIllustColumns.illustId}
        AND dim.${DownloadedImageColumns.extension} != '.webp'
      )
      ORDER BY $orderByClause
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

  Future<List<DownloadedIllust>> getIllustsByUserId(
    int userId, {
    int? limit,
    int? offset,
    String? orderBy,
    bool filterBookmarks = false,
  }) async {
    // total_file_size 已物化到表中，无需 JOIN 查询
    String orderByClause =
        orderBy ?? '${DownloadedIllustColumns.downloadTime} DESC';
    if (filterBookmarks) {
      orderByClause = '${DownloadedIllustColumns.bookmark} DESC, $orderByClause';
    }

    final whereConditions = ['${DownloadedIllustColumns.userId} = ?'];
    if (filterBookmarks) {
      whereConditions.add('${DownloadedIllustColumns.bookmark} > 0');
    }

    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where: whereConditions.join(' AND '),
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
    bool filterBookmarks = false,
  }) async {
    // 1. Find tag ID first
    final tagResults = await db.query(
      DownloadedTagsColumns.tableName,
      columns: [DownloadedTagsColumns.id],
      where: '${DownloadedTagsColumns.name} = ?',
      whereArgs: [tag],
    );
    
    if (tagResults.isEmpty) return [];
    
    final tagId = tagResults.first[DownloadedTagsColumns.id] as int;
    return await searchIllustsByTagId(tagId,
        limit: limit,
        offset: offset,
        orderBy: orderBy,
        filterBookmarks: filterBookmarks);
  }

  Future<List<DownloadedIllust>> searchIllustsByTagId(
    int tagId, {
    int? limit,
    int? offset,
    String? orderBy,
    List<int>? exampleIllustIds,
    bool filterBookmarks = false,
  }) async {
    final exampleCase = (exampleIllustIds != null && exampleIllustIds.isNotEmpty)
        ? 'CASE WHEN di.${DownloadedIllustColumns.illustId} IN (${exampleIllustIds.join(',')}) THEN 0 ELSE 1 END ASC,'
        : '';

    // 等价类查询逻辑：
    // 1. 找到该标签关联的主标签ID (可能是它自己，也可能是它引用的 referencedTagId)
    // 2. 找到所有引用该主标签的标签ID (包括主标签本身)
    // 3. 查询这些标签关联的作品，并按插画 ID 分组去重
    
    String orderByClause =
        orderBy ?? 'di.${DownloadedIllustColumns.downloadTime} DESC';
    if (filterBookmarks) {
      orderByClause = 'di.${DownloadedIllustColumns.bookmark} DESC, $orderByClause';
    }

    final whereConditions = <String>[];
    if (filterBookmarks) {
      whereConditions.add('di.${DownloadedIllustColumns.bookmark} > 0');
    }
    final String whereClause = whereConditions.isNotEmpty ? 'WHERE ${whereConditions.join(' AND ')}' : '';

    var query = '''
      WITH TargetGroup AS (
        SELECT id, COALESCE(referenced_tag_id, id) as main_id 
        FROM ${DownloadedTagsColumns.tableName} 
        WHERE ${DownloadedTagsColumns.id} = ?
      ),
      RelevantTags AS (
        SELECT id FROM ${DownloadedTagsColumns.tableName}
        WHERE id = (SELECT main_id FROM TargetGroup)
        OR ${DownloadedTagsColumns.referencedTagId} = (SELECT main_id FROM TargetGroup)
        OR ${DownloadedTagsColumns.parentId} = (SELECT main_id FROM TargetGroup)
      ),
      MatchingIds AS (
        SELECT DISTINCT ${DownloadedIllustTagsColumns.illustId}
        FROM ${DownloadedIllustTagsColumns.tableName}
        WHERE ${DownloadedIllustTagsColumns.tagId} IN (SELECT id FROM RelevantTags)
      )
      SELECT di.* 
      FROM ${DownloadedIllustColumns.tableName} di
      INNER JOIN MatchingIds m ON di.${DownloadedIllustColumns.illustId} = m.${DownloadedIllustTagsColumns.illustId}
      $whereClause
      ORDER BY $exampleCase $orderByClause
    ''';
    
    final args = <dynamic>[tagId];
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

  /// 查找与指定标签共同出现频率最高的“作品”标签
  Future<List<DownloadedTag>> getCoOccurringWorkTags(int tagId, {int limit = 5}) async {
    // 使用 CTE 确保能够找全关联作品（包含等价标签的情况）
    final query = '''
      WITH TargetGroup AS (
        SELECT id, COALESCE(referenced_tag_id, id) as main_id 
        FROM ${DownloadedTagsColumns.tableName} 
        WHERE ${DownloadedTagsColumns.id} = ?
      ),
      TargetIllusts AS (
        SELECT DISTINCT dit.${DownloadedIllustTagsColumns.illustId} 
        FROM ${DownloadedIllustTagsColumns.tableName} dit
        JOIN ${DownloadedTagsColumns.tableName} t ON dit.${DownloadedIllustTagsColumns.tagId} = t.${DownloadedTagsColumns.id}
        WHERE t.${DownloadedTagsColumns.id} = (SELECT main_id FROM TargetGroup)
        OR t.${DownloadedTagsColumns.referencedTagId} = (SELECT main_id FROM TargetGroup)
      )
      SELECT t.*, COUNT(*) as co_count
      FROM ${DownloadedTagsColumns.tableName} t
      JOIN ${DownloadedIllustTagsColumns.tableName} dit ON t.${DownloadedTagsColumns.id} = dit.${DownloadedIllustTagsColumns.tagId}
      WHERE dit.${DownloadedIllustTagsColumns.illustId} IN (SELECT illust_id FROM TargetIllusts)
      AND t.${DownloadedTagsColumns.category} = ${TagCategory.work.value} -- TagCategory.work
      AND t.${DownloadedTagsColumns.id} != (SELECT main_id FROM TargetGroup)
      GROUP BY t.${DownloadedTagsColumns.id}
      ORDER BY co_count DESC
      LIMIT ?
    ''';
    
    final maps = await db.rawQuery(query, [tagId, limit]);
    return maps.map((e) => DownloadedTag.fromJson(e)).toList();
  }

  /// 批量获取所有潜在的标签共现关联建议
  /// 仅针对当前没有父标签且类别为 角色/未分类/特点 的标签
  Future<List<Map<String, dynamic>>> getGlobalCoOccurrenceProposals({int limit = 100}) async {
    final query = '''
      SELECT 
        dit_child.${DownloadedIllustTagsColumns.tagId} AS child_id, 
        dit_parent.${DownloadedIllustTagsColumns.tagId} AS parent_id, 
        COUNT(*) AS co_count
      FROM ${DownloadedIllustTagsColumns.tableName} AS dit_child
      JOIN ${DownloadedIllustTagsColumns.tableName} AS dit_parent 
        ON dit_child.${DownloadedIllustTagsColumns.illustId} = dit_parent.${DownloadedIllustTagsColumns.illustId}
      JOIN ${DownloadedTagsColumns.tableName} AS t_child 
        ON dit_child.${DownloadedIllustTagsColumns.tagId} = t_child.${DownloadedTagsColumns.id}
      JOIN ${DownloadedTagsColumns.tableName} AS t_parent 
        ON dit_parent.${DownloadedIllustTagsColumns.tagId} = t_parent.${DownloadedTagsColumns.id}
      WHERE t_child.${DownloadedTagsColumns.parentId} = 0 
        AND t_child.${DownloadedTagsColumns.category} IN (
          ${TagCategory.uncategorized.value}, 
          ${TagCategory.character.value}, 
          ${TagCategory.feature.value}
        )
        AND t_parent.${DownloadedTagsColumns.category} = ${TagCategory.work.value}      -- 目标是 作品
        AND dit_child.${DownloadedIllustTagsColumns.tagId} != dit_parent.${DownloadedIllustTagsColumns.tagId}
      GROUP BY dit_child.${DownloadedIllustTagsColumns.tagId}, dit_parent.${DownloadedIllustTagsColumns.tagId}
      HAVING co_count > 1 
      ORDER BY co_count DESC
      LIMIT ?
    ''';
    
    return await db.rawQuery(query, [limit]);
  }

  /// 更新标签的示例插画
  Future<void> updateTagExampleIllusts(int tagId, List<int> illustIds) async {
    await db.update(
      DownloadedTagsColumns.tableName,
      {DownloadedTagsColumns.exampleIllusts: illustIds.join(',')},
      where: '${DownloadedTagsColumns.id} = ?',
      whereArgs: [tagId],
    );
  }


  /// 获取包含该标签在内的完整等价组
  Future<List<DownloadedTag>> getEquivalenceGroup(int tagId) async {
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      WITH TargetGroup AS (
        SELECT id, COALESCE(referenced_tag_id, id) as main_id 
        FROM ${DownloadedTagsColumns.tableName} 
        WHERE id = ?
      )
      SELECT * FROM ${DownloadedTagsColumns.tableName}
      WHERE id = (SELECT main_id FROM TargetGroup)
      OR referenced_tag_id = (SELECT main_id FROM TargetGroup)
    ''', [tagId]);
    return maps.map((e) => DownloadedTag.fromJson(e)).toList();
  }


  /// 更新等价组内的主标签及成员关系
  Future<void> updateEquivalenceGroup(
    int newPrimaryId,
    List<int> allTagIds, [
    List<int>? removedIds,
  ]) async {
    await db.transaction((txn) async {
      // 0. 如果有被移除的标签,先清除它们的引用关系
      if (removedIds != null && removedIds.isNotEmpty) {
        final removedPlaceholders = List.filled(removedIds.length, '?').join(',');
        await txn.update(
          DownloadedTagsColumns.tableName,
          {DownloadedTagsColumns.referencedTagId: null},
          where: 'id IN ($removedPlaceholders)',
          whereArgs: removedIds,
        );
      }

      // 1. 先将组内所有成员的引用置空
      final placeholders = List.filled(allTagIds.length, '?').join(',');
      await txn.update(
        DownloadedTagsColumns.tableName,
        {DownloadedTagsColumns.referencedTagId: null},
        where: 'id IN ($placeholders)',
        whereArgs: allTagIds,
      );

      // 2. 将非主标签的成员指向新的主标签
      final aliasIds = allTagIds.where((id) => id != newPrimaryId).toList();
      if (aliasIds.isNotEmpty) {
        final aliasPlaceholders = List.filled(aliasIds.length, '?').join(',');
        await txn.update(
          DownloadedTagsColumns.tableName,
          {DownloadedTagsColumns.referencedTagId: newPrimaryId},
          where: 'id IN ($aliasPlaceholders)',
          whereArgs: aliasIds,
        );

        // 3. 将非主标签成员的子标签的 parentId 更新为主标签
        // 例如 B 是 A 的别名，B 原有子标签 D，则 D.parentId 应更新为 A
        await txn.update(
          DownloadedTagsColumns.tableName,
          {DownloadedTagsColumns.parentId: newPrimaryId},
          where: '${DownloadedTagsColumns.parentId} IN ($aliasPlaceholders)',
          whereArgs: aliasIds,
        );
      }
    });
  }

  Future<DownloadedTag?> getTagByName(String name) async {
    final maps = await db.query(
      DownloadedTagsColumns.tableName,
      where: '${DownloadedTagsColumns.name} = ?',
      whereArgs: [name],
    );
    if (maps.isNotEmpty) {
      return DownloadedTag.fromJson(maps.first);
    }
    return null;
  }

  Future<List<DownloadedIllust>> searchIllusts(
    String keyword, {
    int? limit,
    int? offset,
    String? orderBy,
    bool filterBookmarks = false,
  }) async {
    // total_file_size 已物化到表中，无需 JOIN 查询
    String orderByClause =
        orderBy ?? '${DownloadedIllustColumns.downloadTime} DESC';
    if (filterBookmarks) {
      orderByClause = '${DownloadedIllustColumns.bookmark} DESC, $orderByClause';
    }

    final whereConditions = [
      '(${DownloadedIllustColumns.title} LIKE ? OR ${DownloadedIllustColumns.userName} LIKE ? OR ${DownloadedIllustColumns.tags} LIKE ?)'
    ];
    if (filterBookmarks) {
      whereConditions.add('${DownloadedIllustColumns.bookmark} > 0');
    }

    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where: whereConditions.join(' AND '),
      whereArgs: ['%$keyword%', '%$keyword%', '%$keyword%'],
      orderBy: orderByClause,
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  /// 获取所有未下载完整的作品（下载的图片数量小于 pageCount）
  /// 使用物化字段 downloaded_image_count 进行查询，无需 JOIN
  Future<List<DownloadedIllust>> getIncompleteIllusts({
    int? limit,
    int? offset,
    String? orderBy,
    bool filterBookmarks = false,
  }) async {
    // 使用物化字段 downloaded_image_count 直接过滤
    String orderByClause = orderBy ?? '${DownloadedIllustColumns.downloadTime} DESC';
    if (filterBookmarks) {
      orderByClause = '${DownloadedIllustColumns.bookmark} DESC, $orderByClause';
    }

    final whereConditions = [
      '${DownloadedIllustColumns.downloadedImageCount} < ${DownloadedIllustColumns.pageCount}'
    ];
    if (filterBookmarks) {
      whereConditions.add('${DownloadedIllustColumns.bookmark} > 0');
    }

    var query = '''
      SELECT *
      FROM ${DownloadedIllustColumns.tableName}
      WHERE ${whereConditions.join(' AND ')}
      ORDER BY $orderByClause
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

  Future<int> deleteIllustByIllustId(int illustId) async {
    final events = <TagChangeEvent>[];
    int result = 0;

    await db.transaction((txn) async {
      // 1. 获取该插画关联的所有 tag ID (包含原始和用户添加的)
      final tagRelations = await txn.query(
        DownloadedIllustTagsColumns.tableName,
        columns: [DownloadedIllustTagsColumns.tagId],
        where: '${DownloadedIllustTagsColumns.illustId} = ?',
        whereArgs: [illustId],
      );
      final affectedTagIds = tagRelations
          .map((r) => TypeUtil.parseInt(r[DownloadedIllustTagsColumns.tagId]))
          .toList();

      // 2. 先删除关联的图片记录
      await txn.delete(
        DownloadedImageColumns.tableName,
        where: '${DownloadedImageColumns.illustId} = ?',
        whereArgs: [illustId],
      );

      // 3. 删除插画与标签的关联关系
      await txn.delete(
        DownloadedIllustTagsColumns.tableName,
        where: '${DownloadedIllustTagsColumns.illustId} = ?',
        whereArgs: [illustId],
      );

      // 4. 更新每一个受影响标签的统计信息
      if (affectedTagIds.isNotEmpty) {
        final tagsData = await _queryTagsByIds(txn, affectedTagIds);
        for (final tagId in affectedTagIds) {
          final tag = tagsData[tagId];
          if (tag == null) continue;

          final event = await _updateTagStats(
            txn: txn,
            tagId: tagId,
            tag: tag,
            illustId: illustId,
            changeType: TagChangeType.illustRemoved,
          );
          events.add(event);
        }
      }

      // 5. 最后删除插画主表记录
      result = await txn.delete(
        DownloadedIllustColumns.tableName,
        where: '${DownloadedIllustColumns.illustId} = ?',
        whereArgs: [illustId],
      );
    });

    // 6. 发送事件通知
    if (events.isNotEmpty) {
      _tagChangesController.add(events);
    }

    return result;
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

  /// 重新计算并更新插画的统计信息
  /// 通过查询 downloaded_images 表来确保数据一致性
  Future<void> recalculateIllustStats(int illustId, {Transaction? txn}) async {
    final database = txn ?? db;
    
    // 查询该插画的所有图片记录
    final images = await database.query(
      DownloadedImageColumns.tableName,
      where: '${DownloadedImageColumns.illustId} = ?',
      whereArgs: [illustId],
    );
    
    // 计算统计信息
    final imageCount = images.length;
    final totalSize = images.fold<int>(
      0,
      (sum, img) => sum + (TypeUtil.parseInt(img[DownloadedImageColumns.fileSize])),
    );
    
    // 更新插画表
    await database.update(
      DownloadedIllustColumns.tableName,
      {
        DownloadedIllustColumns.downloadedImageCount: imageCount,
        DownloadedIllustColumns.totalFileSize: totalSize,
      },
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illustId],
    );
  }

  /// 批量重新计算多个插画的统计信息
  /// 用于 UpdateIllustInfoDialog 扫描完成后批量更新
  Future<void> batchRecalculateIllustStats(List<int> illustIds) async {
    await db.transaction((txn) async {
      for (final illustId in illustIds) {
        await recalculateIllustStats(illustId, txn: txn);
      }
    });
  }

  Future<DownloadedImage> insertImage(DownloadedImage image) async {
    await db.transaction((txn) async {
      await txn.insert(
        DownloadedImageColumns.tableName,
        image.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // 重新计算统计信息（确保数据一致）
      await recalculateIllustStats(image.illustId, txn: txn);
    });
    return image;
  }

  /// 删除单张图片（会自动更新插画统计信息）
  Future<void> deleteImage(int illustId, int part) async {
    await db.transaction((txn) async {
      await txn.delete(
        DownloadedImageColumns.tableName,
        where: '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
        whereArgs: [illustId, part],
      );
      // 重新计算统计信息（确保数据一致）
      await recalculateIllustStats(illustId, txn: txn);
    });
  }

  /// 删除单张图片（不自动更新统计信息）
  /// 用于批量删除场景，调用方应在批量删除完成后调用 batchRecalculateIllustStats
  Future<void> deleteImageWithoutStats(int illustId, int part) async {
    await db.delete(
      DownloadedImageColumns.tableName,
      where: '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, part],
    );
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
  Future<Set<Map<String, int>>> batchCheckImageDownloaded(
      List<Map<String, int>> illustParts) async {
    if (illustParts.isEmpty) return {};

    final result = <Map<String, int>>{};

    // 按 illust_id 分组，减少 OR 条件的数量
    final groupedByIllustId = <int, Set<int>>{};
    for (final item in illustParts) {
      final illustId = item['illustId'];
      final part = item['part'];
      if (illustId != null && part != null) {
        groupedByIllustId.putIfAbsent(illustId, () => <int>{}).add(part);
      }
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
            columns: [
              DownloadedImageColumns.illustId,
              DownloadedImageColumns.part
            ],
            where:
                '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} IN ($placeholders)',
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
    // 查询时需要使用压缩后的 URL 格式（与数据库存储格式一致）
    final compressedUrl = PixivUrlUtil.compressOriginalUrl(originalUrl);
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedImageColumns.tableName,
      where: '${DownloadedImageColumns.originalUrl} = ?',
      whereArgs: [compressedUrl],
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
  ///
  /// 注意：对于动图(ugoira)类型，只返回预览图(part=0)，不返回帧文件
  /// 帧文件仅用于文件大小统计和动图播放，不应作为独立页面显示
  Future<Map<int, LocalImageInfo>> getLocalImageInfosByIllustId(
    int illustId, {
    bool includeUgoiraFrames = false,
  }) async {
    final t1 = DateTime.now();
    final images = await getImagesByIllustId(illustId);

    // 检查是否为动图类型
    final illust = await getIllustByIllustId(illustId);
    final isUgoira = illust?.isUgoira;

    // 对于动图，默认只处理预览图(part=0)，过滤掉所有帧文件(part>=1)
    // 如果 includeUgoiraFrames 为 true，则包含所有帧文件
    final filteredImages = (isUgoira == true && !includeUgoiraFrames)
        ? images.where((img) => img.part == 0).toList()
        : images;

    Log.d(
        'getLocalImageInfosByIllustId: ${images.length} total images, ${filteredImages.length} filtered (isUgoira: $isUgoira, includeUgoiraFrames: $includeUgoiraFrames), ${DateTime.now().difference(t1).inMilliseconds}ms');

    // 并行处理所有图片，大幅提升性能
    final futures = filteredImages.map((image) async {
      final foundPath = await findImagePathForImage(image);
      if (foundPath != null) {
        return MapEntry(
            image.part,
            LocalImageInfo(
              path: foundPath,
              width: image.width,
              height: image.height,
              fileSize: image.fileSize,
            ));
      } else {
        Log.w('未找到图片: ${image.illustId}-${image.part}, $_downloadPath, ${image.relativePath}, ${image.fileName}');
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
  Future<String?> findImagePathForImage(DownloadedImage image,
      {bool update = true}) async {
    // 使用标准的相对路径和文件名构建路径（对动图帧文件也适用，因为 relativePath 已包含 ugoira 子目录）
    final basePath = getAbsolutePath(
      image.relativePath.replaceAll('\\', '/'),
      image.fileName
    );

    // 首先尝试数据库中记录的后缀（最常见的情况）
    String fullPath = '$basePath${image.extension}';
    if (await File(fullPath).exists()) {
      return fullPath;
    }

    // 并行检查其他常见后缀，提升性能
    final otherExtensions =
        kImageExtensions.where((ext) => ext != image.extension).toList();
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
        if (update) {
          // 更新数据库中的后缀名（异步执行，不阻塞返回）
          updateImageExtension(image.illustId, image.part, otherExtensions[i])
              .catchError((e) {
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

  /// 更新图片记录的多个字段（不自动更新插画统计信息）
  /// 用于批量更新场景，调用方应在批量更新完成后调用 batchRecalculateIllustStats
  Future<int> updateImageRecord(
    int illustId,
    int part,
    Map<String, dynamic> updateData,
  ) async {
    return await db.update(
      DownloadedImageColumns.tableName,
      updateData,
      where:
          '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, part],
    );
  }

  /// 获取插画已下载的图片数量
  /// @deprecated 使用物化字段 DownloadedIllust.downloadedImageCount 替代
  @Deprecated('使用物化字段 DownloadedIllust.downloadedImageCount 替代')



  // ============ 路径工具 ============


  /// 生成作者目录名
  static String _buildUserDirName(String userName, int userId) {
    return '[${userName.toLegal()}][$userId]';
  }

  /// 生成作品目录名
  static String _buildIllustDirName(int illustId, String title) {
    return '[$illustId]${title.toLegal()}';
  }

  /// 生成文件名（不含后缀）
  static String buildFileName(int illustId, int part) {
    return '${illustId}_p$part';
  }


  /// 智能解析相对路径（处理改名情况）
  /// 优先使用数据库或磁盘中已存在的路径
  Future<String> resolveRelativePath(Illusts illusts) async {
    final illustId = illusts.id;
    final userId = illusts.user.id;

    // 1. 检查缓存
    if (_illustRelPathCache.containsKey(illustId)) {
      return _illustRelPathCache[illustId]!;
    }

    // 2. 检查当前作品是否已在数据库中
    final existingIllust = await getIllustByIllustId(illustId);
    if (existingIllust != null) {
      final path = existingIllust.relativePath;
      _illustRelPathCache[illustId] = path;
      return path;
    }

    // 3. 获取作者目录（复用逻辑）
    final authorDir = await resolveAuthorDirectoryPath(userId, illusts.user.name);

    // 4. 在作者目录下查找作品目录（处理作品改标题情况）
    // 只有当作者目录确实存在（无论是找到的还是新建的，但如果是新建的肯定没有子目录，所以只需在找到各种情况下搜索）
    String? foundIllustDirName;
    if (_downloadPath != null) {
      final absoluteAuthorDir = Directory(path.join(_downloadPath!, authorDir));
      if (await absoluteAuthorDir.exists()) {
        try {
          // 扫描匹配 [illustId]* 的目录
          final entities = absoluteAuthorDir.list(followLinks: false);
          await for (final entity in entities) {
            if (entity is Directory) {
              final name = path.basename(entity.path);
              if (name.startsWith('[$illustId]')) {
                foundIllustDirName = name;
                break;
              }
            }
          }
        } catch (e) {
          Log.e('扫描作品目录失败: $e');
        }
      }
    }

    final illustDir = foundIllustDirName ?? _buildIllustDirName(illustId, illusts.title);
    final relativePath = path.join(authorDir, illustDir);
    
    // 写入缓存
    _illustRelPathCache[illustId] = relativePath;
    return relativePath;
  }

  /// 智能解析作者目录路径（处理改名情况）
  Future<String> resolveAuthorDirectoryPath(int userId, String userName) async {
    // 1. 检查缓存
    if (_authorDirCache.containsKey(userId)) {
      return _authorDirCache[userId]!;
    }

    // 2. 检查数据库中是否有同作者的其他作品（快速获取作者目录）
    final sameAuthorIllusts = await db.query(
      DownloadedIllustColumns.tableName,
      columns: [DownloadedIllustColumns.relativePath],
      where: '${DownloadedIllustColumns.userId} = ?',
      whereArgs: [userId],
      limit: 1,
    );

    String? foundAuthorDirName;

    if (sameAuthorIllusts.isNotEmpty) {
      final relativePath = sameAuthorIllusts.first[DownloadedIllustColumns.relativePath] as String;
      // relativePath 格式通常为: AuthorDir/IllustDir 或 AuthorDir\IllustDir
      // 使用正则同时匹配 / 和 \ 以兼容跨平台数据库
      final parts = relativePath.split(RegExp(r'[/\\]'));
      if (parts.isNotEmpty) {
        foundAuthorDirName = parts.first;
      }
    }

    // 3. 如果数据库没找到作者目录，尝试扫描文件系统
    if (foundAuthorDirName == null && _downloadPath != null) {
      final downloadDir = Directory(_downloadPath!);
      if (await downloadDir.exists()) {
        try {
          // 扫描匹配 *[userId] 的目录
          final entities = downloadDir.list(followLinks: false);
          await for (final entity in entities) {
            if (entity is Directory) {
              final name = path.basename(entity.path);
              if (name.endsWith('[$userId]')) {
                foundAuthorDirName = name;
                break;
              }
            }
          }
        } catch (e) {
          Log.e('扫描作者目录失败: $e');
        }
      }
    }

    // 如果还没找到作者目录，使用默认生成规则
    final authorDir = foundAuthorDirName ?? _buildUserDirName(userName, userId);

    // 写入缓存
    _authorDirCache[userId] = authorDir;
    return authorDir;
  }


  /// 根据相对路径获取插画目录的绝对路径
  String getIllustAbsolutePath(String relativePath) {
    return path.join(_downloadPath!, relativePath);
  }

  /// 通用方法：根据相对路径和可选的文件名获取完整的绝对路径
  /// 如果提供了 fileName，返回 basePath/relativePath/fileName
  /// 如果未提供 fileName，返回 basePath/relativePath
  String getAbsolutePath(String relativePath, [String? fileName]) {
    if (fileName != null) {
      return path.join(_downloadPath!, relativePath, fileName);
    }
    return path.join(_downloadPath!, relativePath);
  }

  /// 获取动图帧目录的绝对路径
  String getUgoiraFrameDirPath(String relativePath) {
    return getAbsolutePath(relativePath, 'ugoira');
  }


  /// 尝试找到图片文件（自动检测后缀名）
  Future<String?> findImagePath(int illustId, int part,
      {bool update = true}) async {
    return (await getLocalImageInfoByPart(illustId, part, update: update))?.path;
  }

  /// 获取指定页面的本地图片信息（路径和宽高）
  /// 用于快速加载首帧图片，避免等待全部图片加载
  Future<LocalImageInfo?> getLocalImageInfoByPart(
    int illustId,
    int part, {
    bool update = true,
  }) async {
    final image = await getImage(illustId, part);
    if (image == null) return null;
    final imagePath = await findImagePathForImage(image);
    if (imagePath == null) return null;
    return LocalImageInfo(
      path: imagePath,
      width: image.width,
      height: image.height,
      fileSize: image.fileSize,
    );
  }

  Future<LocalImageInfo?> getLocalImageInfoByUrl(String url) async {
    final image = await getImageByOriginalUrl(url);
    if (image == null) return null;
    final imagePath = await findImagePathForImage(image);
    if (imagePath == null) return null;
    return LocalImageInfo(
      path: imagePath,
      width: image.width,
      height: image.height,
    );
  }
  // ============ Author 操作 ============

  /// 插入或更新作者信息
  Future<void> upsertAuthor(
    int userId,
    String? userName,
    String? profileImageUrl,
    int illustCount,
    int totalImageCount,
    int totalFileSize,
    int lastDownloadTime,
  ) async {
    // 获取现有的 bookmark 值，避免被覆盖
    int bookmark = 0;
    try {
      final existing = await db.query(
        DownloadedAuthorColumns.tableName,
        columns: [DownloadedAuthorColumns.bookmark],
        where: '${DownloadedAuthorColumns.userId} = ?',
        whereArgs: [userId],
      );
      if (existing.isNotEmpty) {
        bookmark = existing.first[DownloadedAuthorColumns.bookmark] as int? ?? 0;
      }
    } catch (e) {
      Log.w('获取旧作者 bookmark 失败: $e');
    }

    await db.insert(
      DownloadedAuthorColumns.tableName,
      {
        DownloadedAuthorColumns.userId: userId,
        if (userName != null) DownloadedAuthorColumns.userName: userName,
        if (profileImageUrl != null)
          DownloadedAuthorColumns.profileImageUrl:
              PixivUrlUtil.compressPxUrl(profileImageUrl),
        DownloadedAuthorColumns.illustCount: illustCount,
        DownloadedAuthorColumns.totalImageCount: totalImageCount,
        DownloadedAuthorColumns.totalFileSize: totalFileSize,
        DownloadedAuthorColumns.lastDownloadTime: lastDownloadTime,
        DownloadedAuthorColumns.lastUpdateTime:
            DateTime.now().millisecondsSinceEpoch,
        DownloadedAuthorColumns.bookmark: bookmark,
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

  /// 更新作者头像 URL
  Future<void> updateAuthorProfileUrl(int userId, String newUrl) async {
    await db.update(
      DownloadedAuthorColumns.tableName,
      {DownloadedAuthorColumns.profileImageUrl: PixivUrlUtil.compressPxUrl(newUrl)},
      where: '${DownloadedAuthorColumns.userId} = ?',
      whereArgs: [userId],
    );
  }

  /// 更新作者收藏/优先级
  Future<void> updateAuthorBookmark(int userId, int bookmark) async {
    await db.update(
      DownloadedAuthorColumns.tableName,
      {DownloadedAuthorColumns.bookmark: bookmark},
      where: '${DownloadedAuthorColumns.userId} = ?',
      whereArgs: [userId],
    );
  }

  /// 获取作者列表，支持排序和搜索
  /// sortBy: 'last_download_time', 'user_name', 'illust_count'
  /// searchKeyword: 搜索关键词，支持作者名模糊匹配和用户ID精确匹配
  /// filterUserIds: 指定要查询的作者 ID 列表（用于批量过滤）
  Future<List<DownloadedAuthor>> getAuthorsWithStats({
    String sortBy = 'last_download_time',
    bool desc = true,
    int? limit,
    int? offset,
    String? searchKeyword,
    bool filterBookmarks = false,
    List<int>? filterUserIds,
  }) async {
    String orderBy = '$sortBy ${desc ? 'DESC' : 'ASC'}';
    if (filterBookmarks) {
      // 筛选收藏时，优先按收藏值倒序，然后按用户选择的排序方式
      orderBy = '${DownloadedAuthorColumns.bookmark} DESC, $orderBy';
    }

    final whereConditions = <String>[];
    final whereArgs = <Object?>[];

    // 筛选收藏
    if (filterBookmarks) {
      whereConditions.add('${DownloadedAuthorColumns.bookmark} > 0');
    }

    // 批量过滤指定的作者 ID
    if (filterUserIds != null && filterUserIds.isNotEmpty) {
      final placeholders = List.filled(filterUserIds.length, '?').join(',');
      whereConditions.add('${DownloadedAuthorColumns.userId} IN ($placeholders)');
      whereArgs.addAll(filterUserIds);
    }

    // 搜索关键词
    if (searchKeyword != null && searchKeyword.trim().isNotEmpty) {
      final keyword = searchKeyword.trim();
      final userId = int.tryParse(keyword);

      if (userId != null) {
        whereConditions.add(
            '(${DownloadedAuthorColumns.userId} = ? OR ${DownloadedAuthorColumns.userName} LIKE ?)');
        whereArgs.addAll([userId, '%$keyword%']);
      } else {
        whereConditions.add('${DownloadedAuthorColumns.userName} LIKE ?');
        whereArgs.add('%$keyword%');
      }
    }

    final String? where = whereConditions.isNotEmpty ? whereConditions.join(' AND ') : null;

    List<Map<String, dynamic>> maps = await db.query(
      DownloadedAuthorColumns.tableName,
      where: where,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedAuthor.fromJson(e)).toList();
  }

  /// 获取作者总数，支持收藏和作者 ID 列表筛选
  /// filterUserIds: 指定要查询的作者 ID 列表（用于批量过滤）
  Future<int> getAuthorsCount({
    bool filterBookmarks = false,
    List<int>? filterUserIds,
  }) async {
    final whereConditions = <String>[];
    final whereArgs = <Object?>[];

    // 筛选收藏
    if (filterBookmarks) {
      whereConditions.add('${DownloadedAuthorColumns.bookmark} > 0');
    }

    // 批量过滤指定的作者 ID
    if (filterUserIds != null && filterUserIds.isNotEmpty) {
      final placeholders = List.filled(filterUserIds.length, '?').join(',');
      whereConditions.add('${DownloadedAuthorColumns.userId} IN ($placeholders)');
      whereArgs.addAll(filterUserIds);
    }

    final String? where = whereConditions.isNotEmpty ? whereConditions.join(' AND ') : null;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DownloadedAuthorColumns.tableName}${where != null ? ' WHERE $where' : ''}',
      whereArgs.isNotEmpty ? whereArgs : null,
    );

    return result.first['count'] as int? ?? 0;
  }

  /// 获取包含非 WebP 图片的作者 ID 集合
  /// [userIds] 可选参数，指定要查询的作者 ID 列表。为 null 时查询所有作者
  Future<Set<int>> getAuthorsWithNonWebpImages([List<int>? userIds]) async {
    // 构建 WHERE 条件
    String whereClause;
    List<dynamic> whereArgs;
    
    if (userIds != null && userIds.isNotEmpty) {
      final placeholders = List.filled(userIds.length, '?').join(',');
      whereClause = 'WHERE T1.${DownloadedIllustColumns.userId} IN ($placeholders)';
      whereArgs = userIds;
    } else {
      // 查询所有作者
      whereClause = 'WHERE 1=1';
      whereArgs = [];
    }
    
    // 查询条件：
    // 1. 图片后缀不是 .webp
    // 2. 作品类型不是 ugoira (动图通常是 zip，单独处理)
    // 3. part >= 0 (排除可能的特殊占位符)
    final result = await db.rawQuery('''
      SELECT DISTINCT T1.${DownloadedIllustColumns.userId}
      FROM ${DownloadedIllustColumns.tableName} AS T1
      INNER JOIN ${DownloadedImageColumns.tableName} AS T2 
        ON T1.${DownloadedIllustColumns.illustId} = T2.${DownloadedImageColumns.illustId}
      $whereClause
        AND T2.${DownloadedImageColumns.extension} != '.webp'
        AND T1.${DownloadedIllustColumns.type} != 'ugoira'
        AND T2.${DownloadedImageColumns.part} >= 0
    ''', whereArgs);

    return result.map((e) => e[DownloadedIllustColumns.userId] as int).toSet();
  }

  /// 获取包含非 WebP 图片的插画 ID 集合
  Future<Set<int>> getIllustsWithNonWebpImages(List<int> illustIds) async {
    if (illustIds.isEmpty) return {};

    final placeholders = List.filled(illustIds.length, '?').join(',');
    
    // 查询条件：
    // 1. 指定的插画列表
    // 2. 图片后缀不是 .webp
    // 3. 作品类型不是 ugoira (动图通常是 zip，单独处理)
    // 4. part >= 0
    final result = await db.rawQuery('''
      SELECT DISTINCT T1.${DownloadedIllustColumns.illustId}
      FROM ${DownloadedIllustColumns.tableName} AS T1
      INNER JOIN ${DownloadedImageColumns.tableName} AS T2 
        ON T1.${DownloadedIllustColumns.illustId} = T2.${DownloadedImageColumns.illustId}
      WHERE T1.${DownloadedIllustColumns.illustId} IN ($placeholders)
        AND T2.${DownloadedImageColumns.extension} != '.webp'
        AND T1.${DownloadedIllustColumns.type} != 'ugoira'
        AND T2.${DownloadedImageColumns.part} >= 0
    ''', illustIds);

    return result.map((e) => e[DownloadedIllustColumns.illustId] as int).toSet();
  }

  /// 获取所有作者（不分页）
  Future<List<DownloadedAuthor>> getAllAuthors() async {
    final List<Map<String, dynamic>> maps = await db.query(
      DownloadedAuthorColumns.tableName,
      orderBy: '${DownloadedAuthorColumns.lastDownloadTime} DESC',
    );
    return maps.map((map) => DownloadedAuthor.fromJson(map)).toList();
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

    String? userName;
    String? profileImageUrl;
    if (latestIllust.isNotEmpty) {
      try {
        // 使用 fromJson 获取 DownloadedIllust 对象
        final downloadedIllust = DownloadedIllust.fromJson(latestIllust.first);
        // 转换为 Illusts 对象以获取完整的用户信息
        final illusts = downloadedIllust.toIllusts();
        userName = illusts.user.name;
        profileImageUrl = illusts.user.profileImageUrls.medium;
      } catch (e) {
        // 异常时回退到表字段
        Log.e('获取作者信息失败: $e');
      }
    }

    // 计算总图片数量和总文件大小（使用物化字段）
    final statsResult = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(${DownloadedIllustColumns.downloadedImageCount}), 0) as total_image_count,
        COALESCE(SUM(${DownloadedIllustColumns.totalFileSize}), 0) as total_file_size
      FROM ${DownloadedIllustColumns.tableName}
      WHERE ${DownloadedIllustColumns.userId} = ?
    ''', [userId]);
    final totalImageCount = statsResult.first['total_image_count'] as int? ?? 0;
    final totalFileSize = statsResult.first['total_file_size'] as int? ?? 0;

    // 更新或插入作者记录
    await upsertAuthor(
      userId,
      userName,
      profileImageUrl,
      count,
      totalImageCount,
      totalFileSize,
      lastDownloadTime,
    );
  }

  /// 更新作者统计信息，如果作者没有插画则删除作者记录
  /// 这个方法应该在删除插画后调用，用于维护作者表的正确状态
  Future<void> deleteAuthorIfEmpty(int userId) async {
    final count = await db.rawQuery('''
      SELECT COUNT(*) as count 
      FROM ${DownloadedIllustColumns.tableName} 
      WHERE ${DownloadedIllustColumns.userId} = ?
    ''', [userId]);
    final illustCount = count.first['count'] as int? ?? 0;
    
    if (illustCount == 0) {
      // 没有插画，删除作者记录
      await db.delete(
        DownloadedAuthorColumns.tableName,
        where: '${DownloadedAuthorColumns.userId} = ?',
        whereArgs: [userId],
      );
    } else {
      // 还有插画，更新统计信息
      await updateAuthorStats(userId);
    }
  }

  /// 获取作者的图片统计信息（总图片张数和总文件大小）
  /// 使用物化字段优化查询
  Future<Map<String, int>> getAuthorImageStats(int userId) async {
    final result = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(${DownloadedIllustColumns.downloadedImageCount}), 0) as total_image_count,
        COALESCE(SUM(${DownloadedIllustColumns.totalFileSize}), 0) as total_file_size
      FROM ${DownloadedIllustColumns.tableName}
      WHERE ${DownloadedIllustColumns.userId} = ?
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
    String? tagName,
    bool filterBookmarks = false,
  }) async {
    String whereClause = '';
    final whereArgs = <dynamic>[];

    if (filterBookmarks) {
      whereClause = 'WHERE di.${DownloadedIllustColumns.bookmark} > 0';
    }

    if (filterType == 'user' && userId != null) {
      if (whereClause.isEmpty) {
        whereClause = 'WHERE di.${DownloadedIllustColumns.userId} = ?';
      } else {
        whereClause += ' AND di.${DownloadedIllustColumns.userId} = ?';
      }
      whereArgs.add(userId);
    } else if (filterType == 'tag' && tagName != null && tagName.isNotEmpty) {
      final tag = await getTagByName(tagName);
      if (tag != null) {
        // 使用 CTE 找到等价组的所有标签 ID
        final bookmarkCondition = filterBookmarks ? 'AND di.${DownloadedIllustColumns.bookmark} > 0' : '';
        final query = '''
          WITH TargetGroup AS (
            SELECT ${DownloadedTagsColumns.id} as id, COALESCE(${DownloadedTagsColumns.referencedTagId}, ${DownloadedTagsColumns.id}) as main_id 
            FROM ${DownloadedTagsColumns.tableName} 
            WHERE ${DownloadedTagsColumns.id} = ?
          ),
          GroupIds AS (
            SELECT id FROM ${DownloadedTagsColumns.tableName}
            WHERE id = (SELECT main_id FROM TargetGroup)
            OR ${DownloadedTagsColumns.referencedTagId} = (SELECT main_id FROM TargetGroup)
          ),
          MatchingIds AS (
            SELECT DISTINCT ${DownloadedIllustTagsColumns.illustId}
            FROM ${DownloadedIllustTagsColumns.tableName}
            WHERE ${DownloadedIllustTagsColumns.tagId} IN (SELECT id FROM GroupIds)
          )
          SELECT 
            COUNT(di.${DownloadedIllustColumns.illustId}) as illust_count,
            COALESCE(SUM(di.${DownloadedIllustColumns.downloadedImageCount}), 0) as total_image_count,
            COALESCE(SUM(di.${DownloadedIllustColumns.totalFileSize}), 0) as total_file_size
          FROM ${DownloadedIllustColumns.tableName} di
          INNER JOIN MatchingIds m ON di.${DownloadedIllustColumns.illustId} = m.${DownloadedIllustTagsColumns.illustId}
          WHERE 1=1 $bookmarkCondition
        ''';
        final result = await db.rawQuery(query, [tag.id]);
        if (result.isNotEmpty) {
          return {
            'illust_count': result.first['illust_count'] as int? ?? 0,
            'image_count': result.first['total_image_count'] as int? ?? 0,
            'file_size': result.first['total_file_size'] as int? ?? 0,
          };
        }
        return {'illust_count': 0, 'image_count': 0, 'file_size': 0};
      } else {
        return {'illust_count': 0, 'image_count': 0, 'file_size': 0};
      }
    } else if (filterType == 'search' &&
        searchKeyword != null &&
        searchKeyword.isNotEmpty) {
      final searchCondition = 'di.${DownloadedIllustColumns.title} LIKE ? OR di.${DownloadedIllustColumns.userName} LIKE ? OR di.${DownloadedIllustColumns.tags} LIKE ?';
      if (whereClause.isEmpty) {
        whereClause = 'WHERE ($searchCondition)';
      } else {
        whereClause += ' AND ($searchCondition)';
      }
      whereArgs
          .addAll(['%$searchKeyword%', '%$searchKeyword%', '%$searchKeyword%']);
    } else if (filterType == 'incomplete') {
      // 未下载完整：使用物化字段过滤，无需 JOIN
      final incompleteCondition = '${DownloadedIllustColumns.downloadedImageCount} < ${DownloadedIllustColumns.pageCount}';
      if (whereClause.isEmpty) {
        whereClause = 'WHERE $incompleteCondition';
      } else {
        whereClause += ' AND $incompleteCondition';
      }
    }

    // 对于其他情况（all, user, search），使用物化字段统计
    final query = '''
      SELECT 
        COUNT(*) as illust_count,
        COALESCE(SUM(di.${DownloadedIllustColumns.downloadedImageCount}), 0) as total_image_count,
        COALESCE(SUM(di.${DownloadedIllustColumns.totalFileSize}), 0) as total_file_size
      FROM ${DownloadedIllustColumns.tableName} di
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
  Future<List<PendingDownload>> getPendingDownloadsByStatus(
      List<String> status) async {
    List<Map<String, dynamic>> maps = await db.query(
      PendingDownloadColumns.tableName,
      where:
          '${PendingDownloadColumns.status} IN (${status.map((e) => '?').join(',')})',
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


  /// 获取待下载任务数量
  Future<int> getPendingDownloadCount() async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${PendingDownloadColumns.tableName}',
    );
    return result.first['count'] as int? ?? 0;
  }

  /// 批量插入待下载任务（使用事务优化性能）
  Future<void> batchInsertPendingDownloads(
      List<PendingDownload> pendings) async {
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
  Future<Set<int>> batchInsertIllustsIfNotExists(
      List<DownloadedIllust> illusts) async {
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
      existingIds
          .addAll(maps.map((e) => e[DownloadedIllustColumns.illustId] as int));
    }

    // 过滤出需要插入的 illusts
    final illustsToInsert =
        illusts.where((e) => !existingIds.contains(e.illustId)).toList();

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

  /// 获取数据库文件大小（字节）
  Future<int> getDatabaseSize() async {
    if (_dbPath == null) return 0;
    final file = File(_dbPath!);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  // ============ WebP 动图相关操作 ============

  /// 将动图序列帧记录替换为WebP动图记录
  /// 
  /// 在事务中执行：
  /// 1. 删除 part > 0 的序列帧记录（保留 part=0 预览图）
  /// 2. 插入 part=-1 的 WebP 动图记录
  /// 
  /// [illustId]: 插画ID
  /// [relativePath]: 相对路径
  /// [fileSize]: WebP文件大小
  /// [width]: WebP动图宽度（可选）
  /// [height]: WebP动图高度（可选）
  Future<void> replaceUgoiraFramesWithWebP({
    required int illustId,
    required String relativePath,
    required int fileSize,
    int? width,
    int? height,
  }) async {
    await db.transaction((txn) async {
      // 1. 删除序列帧记录（保留 part=0 的预览图）
      await txn.delete(
        DownloadedImageColumns.tableName,
        where: '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} > 0',
        whereArgs: [illustId],
      );

      // 2. 插入WebP动图记录（part=-1）
      await txn.insert(
        DownloadedImageColumns.tableName,
        DownloadedImage(
          illustId: illustId,
          part: -1, // WebP动图标识
          fileName: '$illustId',
          extension: '.webp',
          fileSize: fileSize,
          originalUrl: '', // 本地生成，无原始URL
          relativePath: relativePath,
          width: width,
          height: height,
        ).toJson(),
      );
    });
  }

  /// 更新动图WebP的宽高信息
  Future<void> updateWebPDimensions(int illustId, int width, int height) async {
    await db.update(
      DownloadedImageColumns.tableName,
      {
        DownloadedImageColumns.width: width,
        DownloadedImageColumns.height: height,
      },
      where: '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, -1],
    );
  }

  /// 获取WebP动图记录（part=-1）
  Future<DownloadedImage?> getWebPImage(int illustId) async {
    return await getImage(illustId, -1);
  }

  // ============ Tag 操作 ============

  Future<void> updateTag(DownloadedTag tag) async {
    // Try to update specific columns first
    int count = await db.update(
      DownloadedTagsColumns.tableName,
      {
        DownloadedTagsColumns.customTranslatedName: tag.customTranslatedName,
        DownloadedTagsColumns.category: tag.category,
        DownloadedTagsColumns.isBookmarked: tag.isBookmarked ? 1 : 0,
        DownloadedTagsColumns.displayOrder: tag.displayOrder,
        DownloadedTagsColumns.parentId: tag.parentId,
      },
      where: '${DownloadedTagsColumns.name} = ?',
      whereArgs: [tag.name],
    );

    // If no row was updated, it means the tag doesn't exist, so insert it.
    if (count == 0) {
      await db.insert(
        DownloadedTagsColumns.tableName,
        tag.toJson(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> batchUpdateTagCategory(List<int> tagIds, int category) async {
    if (tagIds.isEmpty) return;
    
    // Batch update using WHERE IN
    const batchSize = 500;
    for (int i = 0; i < tagIds.length; i += batchSize) {
      final end = (i + batchSize < tagIds.length) ? i + batchSize : tagIds.length;
      final batchIds = tagIds.sublist(i, end);
      final placeholders = List.filled(batchIds.length, '?').join(',');
      
      await db.update(
        DownloadedTagsColumns.tableName,
        {DownloadedTagsColumns.category: category},
        where: '${DownloadedTagsColumns.id} IN ($placeholders)',
        whereArgs: batchIds,
      );
    }
  }

  Future<void> addCustomTagToIllust(int illustId, String tagName) async {
    // 1. Ensure tag exists in downloaded_tags
    await db.rawInsert('''
      INSERT OR IGNORE INTO ${DownloadedTagsColumns.tableName} 
      (${DownloadedTagsColumns.name})
      VALUES (?)
    ''', [tagName]);
    
    // 2. Get ID
    final List<Map<String, dynamic>> res = await db.query(
      DownloadedTagsColumns.tableName,
      columns: [DownloadedTagsColumns.id],
      where: '${DownloadedTagsColumns.name} = ?',
      whereArgs: [tagName],
    );
    if (res.isEmpty) return; // Should not happen
    final tagId = res.first[DownloadedTagsColumns.id] as int;

    // 3. Add link with source=1
    await db.insert(
      DownloadedIllustTagsColumns.tableName,
      {
        DownloadedIllustTagsColumns.illustId: illustId,
        DownloadedIllustTagsColumns.tagId: tagId,
        DownloadedIllustTagsColumns.source: 1, // Custom tag
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeCustomTagFromIllust(int illustId, String tagName) async {
     final List<Map<String, dynamic>> res = await db.query(
      DownloadedTagsColumns.tableName,
      columns: [DownloadedTagsColumns.id],
      where: '${DownloadedTagsColumns.name} = ?',
      whereArgs: [tagName],
    );
    if (res.isEmpty) return;
    final tagId = res.first[DownloadedTagsColumns.id] as int;

     await db.delete(
       DownloadedIllustTagsColumns.tableName,
       where: '${DownloadedIllustTagsColumns.illustId} = ? AND ${DownloadedIllustTagsColumns.tagId} = ? AND ${DownloadedIllustTagsColumns.source} = ?',
       whereArgs: [illustId, tagId, 1],
     );
  }

  Future<List<String>> getTagsForIllust(int illustId) async {
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT t.${DownloadedTagsColumns.name}
      FROM ${DownloadedIllustTagsColumns.tableName} it
      JOIN ${DownloadedTagsColumns.tableName} t ON it.${DownloadedIllustTagsColumns.tagId} = t.${DownloadedTagsColumns.id}
      WHERE it.${DownloadedIllustTagsColumns.illustId} = ?
    ''', [illustId]);
    return maps.map((e) => e[DownloadedTagsColumns.name] as String).toList();
  }

  Future<List<TagDisplayData>> getTags() async {
      // Fetch all tags. Sorting and filtering are handled by the frontend store.
      final List<Map<String, dynamic>> maps = await db.query(
        DownloadedTagsColumns.tableName,
      );
      
      List<TagDisplayData> result = [];
      Set<int> allIllustIds = {};

      // First pass: create entities and collect IDs
      List<DownloadedTag> tagEntities = [];
      for (var map in maps) {
        var entity = DownloadedTag.fromJson(map);
        tagEntities.add(entity);
        allIllustIds.addAll(entity.exampleIllustIds);
      }

      // Batch query illusts
      Map<int, IllustPreviewData> illustMap = {};
      if (allIllustIds.isNotEmpty) {
        final List<int> idsList = allIllustIds.toList();
        // Batch size of 200 to be safe (SQLite usually limits params to ~999)
        const int batchSize = 200;
        for (var i = 0; i < idsList.length; i += batchSize) {
           var end = (i + batchSize < idsList.length) ? i + batchSize : idsList.length;
           var batchIds = idsList.sublist(i, end);
           
           final placeholders = List.filled(batchIds.length, '?').join(',');
           
           final List<Map<String, dynamic>> illustMaps = await db.query(
             DownloadedIllustColumns.tableName,
             columns: [
                DownloadedIllustColumns.illustId,
                DownloadedIllustColumns.imageUrlsJson,
             ],
             where: '${DownloadedIllustColumns.illustId} IN ($placeholders)',
             whereArgs: batchIds,
           );
           for (var m in illustMaps) {
             final illustId = m[DownloadedIllustColumns.illustId] as int;
             final imageUrlsJson = m[DownloadedIllustColumns.imageUrlsJson] as String;

             String squareMedium = '';
             if (imageUrlsJson.isNotEmpty) {
               final map = TypeUtil.parseMap(PixivUrlUtil.decompressPxUrl(imageUrlsJson));
                 squareMedium = TypeUtil.parseString(map['square_medium']);
             }
             
             illustMap[illustId] = IllustPreviewData(
               illustId: illustId,
               squareMediumUrl: squareMedium,
             );
           }
        }
      }

      // Pre-collect all referencedTagIds to determine which tags have equivalent relationships
      final List<Map<String, dynamic>> refMaps = await db.query(
        DownloadedTagsColumns.tableName,
        columns: [DownloadedTagsColumns.referencedTagId],
        where: '${DownloadedTagsColumns.referencedTagId} IS NOT NULL'
      );
      final Set<int> allReferencedIds = refMaps.map((m) => m[DownloadedTagsColumns.referencedTagId] as int).toSet();
      
      // Second pass: associate illusts and determine hasEquivalentTags
      for (var entity in tagEntities) {
        List<IllustPreviewData> previewIllusts = [];
        for (var illustId in entity.exampleIllustIds) {
          if (illustMap.containsKey(illustId)) {
            previewIllusts.add(illustMap[illustId]!);
          }
        }
        // Since we don't have createDate in the lean object, we'll rely on the order of exampleIllustIds 
        // which was already sorted by date when saved to DB during syncTags.
        
        // A tag has equivalent tags if:
        // 1. It is an alias (points to someone else)
        // 2. It is a primary tag (someone else points to it)
        bool hasEquivalentTags = entity.referencedTagId != 0 || allReferencedIds.contains(entity.id);
        
        result.add(TagDisplayData(
          tag: entity, 
          previewIllusts: previewIllusts,
          hasEquivalentTags: hasEquivalentTags,
        ));
      }

      return result;
  }

  Future<void> syncTags({Function(String status)? onStatus}) async {
    if (onStatus != null) onStatus('正在准备...');
      
    // 1. Get all downloaded illusts
    if (onStatus != null) onStatus('正在读取作品列表...');
    final List<Map<String, dynamic>> illustsMaps = await db.query(
      DownloadedIllustColumns.tableName,
      columns: [DownloadedIllustColumns.illustId, DownloadedIllustColumns.tags],
    );

    if (onStatus != null) onStatus('正在建立索引...');

    // In-memory aggregation
    Map<String, Set<int>> tagToIllusts = {};
    Map<String, String> tagTranslations = {};
    int count = 0;
    
    for (var map in illustsMaps) {
      int illustId = map[DownloadedIllustColumns.illustId];
      String tagsJson = map[DownloadedIllustColumns.tags];
      try {
          List<Tags> illustTags = TypeUtil.parseList(tagsJson, (e) => Tags.fromMap(TypeUtil.parseMap(e)));
          
          for (var tag in illustTags) {
            String tagName = tag.name;
            if (processTags(tagName)) {
               tagToIllusts.putIfAbsent(tagName, () => {});
               tagToIllusts[tagName]!.add(illustId);
               tagTranslations[tagName] = tag.translatedName ?? '';
            }
          }
      } catch (e) {
        // ignore parsing error
      }
      
      count++;
      if (count % 200 == 0) {
          if (onStatus != null) onStatus('已分析 $count / ${illustsMaps.length}...');
      }
    }

    if (onStatus != null) onStatus('正在写入数据库...');
    
    await db.transaction((txn) async {
       // Clear automatic links and reset counts
       await txn.delete(
        DownloadedIllustTagsColumns.tableName,
        where: '${DownloadedIllustTagsColumns.source} = ?',
        whereArgs: [0],
      );
      
      // Update DB
      int currentTag = 0;
      int totalTags = tagToIllusts.length;
      
      for (var entry in tagToIllusts.entries) {
        String tagName = entry.key;
        Set<int> illustIds = entry.value;
        String translation = tagTranslations[tagName] ?? '';
        
        // 1. Insert or Ignore Tag
        await txn.rawInsert('''
          INSERT OR IGNORE INTO ${DownloadedTagsColumns.tableName} 
          (${DownloadedTagsColumns.name}, ${DownloadedTagsColumns.translatedName})
          VALUES (?, ?)
        ''', [tagName, translation]);
        
        // 2. Prepare metadata
        List<int> sortedIllusts = illustIds.toList()..sort((a, b) => b.compareTo(a)); // Descending ID roughly means descending date
        String exampleIllusts = sortedIllusts.take(3).join(',');
        
        // 3. Update Tag Metadata
        await txn.update(
          DownloadedTagsColumns.tableName,
          {
            DownloadedTagsColumns.count: illustIds.length,
            DownloadedTagsColumns.exampleIllusts: exampleIllusts,
          },
          where: '${DownloadedTagsColumns.name} = ?',
          whereArgs: [tagName],
        );
        
        // 4. Get Tag ID
        final tagRows = await txn.query(
          DownloadedTagsColumns.tableName,
          columns: [DownloadedTagsColumns.id],
          where: '${DownloadedTagsColumns.name} = ?',
          whereArgs: [tagName],
        );
        
        if (tagRows.isNotEmpty) {
           int tagId = tagRows.first[DownloadedTagsColumns.id] as int;
           
           // 5. Insert Relations (Batch)
           Batch batch = txn.batch();
           for (int iId in illustIds) {
             batch.insert(
               DownloadedIllustTagsColumns.tableName,
               {
                 DownloadedIllustTagsColumns.illustId: iId,
                 DownloadedIllustTagsColumns.tagId: tagId,
                 DownloadedIllustTagsColumns.source: 0,
               },
               conflictAlgorithm: ConflictAlgorithm.ignore,
             );
           }
           await batch.commit(noResult: true);
        }
        
        currentTag++;
        if (currentTag % 50 == 0 && onStatus != null) {
          onStatus('正在同步标签 $currentTag / $totalTags...');
        }
      }
    });
  }
  
  bool processTags(String tag) {
    return true;
  }
}
