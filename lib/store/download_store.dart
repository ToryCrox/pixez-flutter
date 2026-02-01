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
import 'dart:collection';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:collection/collection.dart';

import 'package:flutter/material.dart';
import 'package:pixez/utils/image_utils.dart';
import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as path hide context;
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/constants.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/custom/pixiv_url_util.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/ugoira_metadata_response.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:pixez/utils/ugoira_downloader.dart';
import 'package:pixez/utils/webp_encoder.dart';
import 'package:pixez/store/account_store.dart';
import 'package:pixez/network/api_client.dart';

part 'download_store.g.dart';

enum DownloadTaskStatus {
  /// 等待下载
  pending,

  /// 下载中
  downloading,

  /// 下载完成
  completed,

  /// 下载失败
  failed,

  /// 暂停
  paused,

  /// 已删除
  deleted;

  /// 下载失败和暂停都是
}

// 下载任务
class DownloadTask {
  final Illusts illusts;
  final int part;
  String url;
  final int createTime;
  DownloadTaskStatus status;
  int received;
  int total;
  String? error;
  int bookmark;

  DownloadTask({
    required this.illusts,
    required this.part,
    required this.url,
    required this.createTime,
    this.status = DownloadTaskStatus.pending,
    this.received = 0,
    this.total = 0,
    this.error,
    this.bookmark = 0,
  });

  String get taskKey => '${illusts.id}_$part';

  // 下载进度 (0.0 - 1.0)
  double get progress => total > 0 ? received / total : 0;

  /// 是否可以重试
  bool get isCanRetry {
    return status == DownloadTaskStatus.failed ||
        status == DownloadTaskStatus.paused ||
        status == DownloadTaskStatus.deleted;
  }

  PendingDownload toPendingDownload() {
    return PendingDownload(
      id: taskKey,
      illustJson: jsonEncode(illusts.toJson()),
      part: part,
      url: url,
      status: status.name,
      createTime: createTime,
      bookmark: bookmark,
    );
  }

  factory DownloadTask.fromPendingDownload(PendingDownload pendingDownload) {
    return DownloadTask(
      illusts: Illusts.fromJson(jsonDecode(pendingDownload.illustJson)),
      part: pendingDownload.part,
      url: pendingDownload.url,
      createTime: pendingDownload.createTime,
      status: DownloadTaskStatus.values
              .firstWhereOrNull((e) => e.name == pendingDownload.status) ??
          DownloadTaskStatus.pending,
      received: 0,
      total: 0,
      error: null,
      bookmark: pendingDownload.bookmark,
    );
  }
}

/// Illust 级别的下载状态
class IllustDownloadStatus {
  final DownloadTaskStatus status;
  final DownloadedIllust illusts;
  final int totalCount;
  final int completedCount;
  final int fileSize; // 文件大小（字节）

  IllustDownloadStatus({
    required this.status,
    required this.illusts,
    required this.totalCount,
    required this.completedCount,
    this.fileSize = 0,
  });

  bool get isAllDownloaded {
    // 对于动图，只要状态是 completed 且有至少一条记录就认为下载完成
    // 因为动图的 pageCount 是帧数，而数据库中只存储预览图和帧文件记录，数量可能不匹配
    if (illusts.isUgoira) {
      return status == DownloadTaskStatus.completed && completedCount > 0;
    }
    // 对于普通插画，检查是否所有页面都已下载
    return totalCount > 0 && totalCount == completedCount;
  }

  @override
  String toString() {
    return 'IllustDownloadStatus{status: $status, illusts: $illusts, totalCount: $totalCount, completedCount: $completedCount, fileSize: $fileSize}';
  }
}

class DownloadStore = _DownloadStoreBase with _$DownloadStore;

abstract class _DownloadStoreBase with Store {
  final DownloadDatabaseProvider _dbProvider = DownloadDatabaseProvider();

  // 暴露数据库 provider 供 downloader 使用
  DownloadDatabaseProvider get dbProvider => _dbProvider;

  // Account Store for user info
  late AccountStore accountStore;

  // 下载进度流
  final StreamController<DownloadTask> _progressController =
      StreamController<DownloadTask>.broadcast();

  Stream<DownloadTask> get progressStream => _progressController.stream;

  final StreamController<IllustDownloadStatus> _illustDownloadStatusController =
      StreamController<IllustDownloadStatus>.broadcast();

  Stream<IllustDownloadStatus> get illustDownloadStatusStream =>
      _illustDownloadStatusController.stream;

  /// 正在下载illust id
  final Set<int> _downloadProgressIllustIdBuffer = {};

  // 正在下载的任务
  @observable
  ObservableMap<String, DownloadTask> downloadingTasks =
      ObservableMap<String, DownloadTask>();

  // 下载队列
  final Queue<DownloadTask> _pendingQueue = Queue<DownloadTask>();

  // 下载任务缓冲区
  final List<DownloadTask> _downloadTaskBuffer = [];

  // 正在运行的下载
  final Set<String> _runningTask = {};

  // 最大并发数
  int _maxConcurrent = 3;

  set maxConcurrent(int value) {
    _maxConcurrent = value;
    _processQueue();
  }


  bool get isInitialized => _dbProvider.downloadPath.isNotEmpty;

  @observable
  int totalDownloaded = 0;

  /// 初始化完成
  bool _isInit = false;

  Timer? _debounceTimer;

  // 初始化
  Future<void> init(String downloadPath, {int maxConcurrent = 3}) async {
    if (_isInit) return;
    _isInit = true;
    _maxConcurrent = maxConcurrent;
    await _dbProvider.open(downloadPath);
    Log.d('DownloadStore downloadPath: ${_dbProvider.downloadPath}');
    await refreshCount();
    
    progressStream.listen((e) {
      _downloadProgressIllustIdBuffer.add(e.illusts.id);
      if (_debounceTimer?.isActive ?? false) return;
      _debounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (_downloadProgressIllustIdBuffer.isNotEmpty) {
          final idList = _downloadProgressIllustIdBuffer.toList();
          _downloadProgressIllustIdBuffer.clear();
          for (final illustId in idList) {
            _handleIllustDownloadStatus(illustId);
          }
        }
      });
    });

    // 注册到数据库管理中心
    DatabaseRegistry.instance.register(
      '下载数据库',
      _dbProvider.dbPathStr,
      () async => _dbProvider.db,
    );
  }

  /// 更新下载路径（关闭旧数据库并重新打开新路径的数据库）
  /// 注意：调用此方法前，用户需要手动将数据库文件和下载文件迁移到新路径
  Future<void> updateDownloadPath(String newDownloadPath) async {
    if (!_isInit) {
      throw Exception('DownloadStore not initialized');
    }

    // 1. 关闭当前数据库连接
    await _dbProvider.db.close();
    Log.d('DownloadStore: 已关闭旧数据库连接');

    // 2. 重新打开数据库（新路径）
    await _dbProvider.open(newDownloadPath);
    Log.d('DownloadStore: 更新下载路径到 ${_dbProvider.downloadPath}');
    // 3. 刷新统计
    await refreshCount();
  }

  Future<void> _handleIllustDownloadStatus(int illustId) async {
    final illustDownloadStatus = await getIllustDownloadStatus(illustId);
    Log.d(() => 'handleIllustDownloadStatus $illustId: $illustDownloadStatus');
    if (illustDownloadStatus != null && illustDownloadStatus.isAllDownloaded) {
      BotToast.showText(
          text: '下载完成${illustId}：${illustDownloadStatus.illusts.title}');
    }
    if (illustDownloadStatus != null) {
      _illustDownloadStatusController.add(illustDownloadStatus);
    }
  }

  /// 通知插画下载状态更新（公开方法，供外部调用）
  Future<void> notifyIllustDownloadStatus(int illustId) async {
    await _handleIllustDownloadStatus(illustId);
  }

  /// 获取待确认的下载任务(不自动添加到下载队列)
  @action
  Future<List<DownloadTask>> loadPendingTasks() async {
    final pendingDownloads = await _dbProvider.getPendingDownloadsByStatus(
      DownloadTaskStatus.values
          .whereNot((e) => e == DownloadTaskStatus.completed)
          .map((e) => e.name)
          .toList(),
    );
    return pendingDownloads.map((e) {
      return DownloadTask.fromPendingDownload(e);
    }).toList();
  }

  /// 添加如暂停的任务
  Future<void> addPausedTasks(List<DownloadTask> tasks) async {
    for (final task in tasks) {
      task.status = DownloadTaskStatus.paused;
      downloadingTasks[task.taskKey] = task;
    }
  }

  /// 清除指定的待下载任务
  Future<void> clearPendingTasks(List<String> taskKeys) async {
    for (final taskKey in taskKeys) {
      await _dbProvider.deletePendingDownload(taskKey);
    }
  }

  @action
  Future<void> refreshCount() async {
    totalDownloaded = await _dbProvider.getIllustCount();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _progressController.close();
  }

  // ============ 查询接口 ============

  Future<bool> isIllustDownloaded(int illustId) async {
    return await _dbProvider.isIllustDownloaded(illustId);
  }

  Future<DownloadedIllust?> getDownloadedIllust(int illustId) async {
    return await _dbProvider.getIllustByIllustId(illustId);
  }

  Future<String?> getLocalImagePath(int illustId, int part,
      {bool update = true}) async {
    return await _dbProvider.findImagePath(illustId, part, update: update);
  }

  Future<String?> getLocalImagePathFromImage(DownloadedImage image,
      {bool update = true}) async {
    return await _dbProvider.findImagePathForImage(image, update: update);
  }

  /// 获取封面缓存路径（分质量目录存储格式）
  /// 路径格式：databasePath/covers/{quality}/{illustId}.webp
  String getCoverCachePath(int illustId, {String quality = Constants.qualitySquareMedium}) {
    return path.join(_dbProvider.coverPath, quality, '$illustId.webp');
  }

  /// 获取头像缓存路径
  /// 路径格式：databasePath/avatars/{userId}.webp
  String getAvatarCachePath(int userId) {
    return path.join(_dbProvider.avatarPath, '$userId.webp');
  }

  /// 获取本地图片信息（包含宽高）
  Future<DownloadedImage?> getLocalImage(int illustId, int part) async {
    return await _dbProvider.getImage(illustId, part);
  }

  /// 批量获取插画的所有本地图片信息
  Future<Map<int, LocalImageInfo>> getLocalImageInfos(int illustId) async {
    return await _dbProvider.getLocalImageInfosByIllustId(illustId);
  }

  /// 更新图片信息并返回新的 LocalImageInfo
  Future<LocalImageInfo?> updateAndGetLocalImageInfo(
    int illustId,
    int part,
    String filePath,
    int currentFileSize,
  ) async {
    final size = await getImageSize(filePath);
    if (size != null && size.width > 0 && size.height > 0) {
      await _dbProvider.updateImageFileSizeAndDimensions(
        illustId,
        part,
        currentFileSize,
        size.width.toInt(),
        size.height.toInt(),
      );
      return LocalImageInfo(
        path: filePath,
        width: size.width.toInt(),
        height: size.height.toInt(),
        fileSize: currentFileSize,
      );
    }
    return LocalImageInfo(path: filePath, fileSize: currentFileSize);
  }

  /// 获取本地图片的宽高比，如果没有宽高信息则尝试解析并更新
  Future<double?> getLocalImageAspectRatio(int illustId, int part) async {
    final image = await _dbProvider.getImage(illustId, part);
    if (image == null) return null;

    // 如果已有宽高信息，直接返回
    if (image.aspectRatio != null) {
      return image.aspectRatio;
    }

    // 尝试解析图片宽高并更新数据库
    final filePath = await _dbProvider.findImagePath(illustId, part);
    if (filePath == null) return null;

    final size = await getImageSize(filePath);
    if (size != null && size.width > 0 && size.height > 0) {
      await _dbProvider.updateImageDimensions(
        illustId,
        part,
        size.width.toInt(),
        size.height.toInt(),
      );
      return size.width / size.height;
    }

    return null;
  }

  Future<List<DownloadedIllust>> getAllDownloaded({
    int? limit,
    int? offset,
    bool desc = true,
    String? orderBy,
    bool filterBookmarks = false,
  }) async {
    return await _dbProvider.getAllIllusts(
      limit: limit,
      offset: offset,
      desc: desc,
      orderBy: orderBy,
      filterBookmarks: filterBookmarks,
    );
  }

  Future<List<DownloadedIllust>> getDownloadedByUser(
    int userId, {
    int? limit,
    int? offset,
    String? orderBy,
    bool filterBookmarks = false,
  }) async {
    return await _dbProvider.getIllustsByUserId(userId,
        limit: limit, offset: offset, orderBy: orderBy, filterBookmarks: filterBookmarks);
  }

  Future<List<DownloadedIllust>> searchDownloadedByTagId(
    int tagId, {
    int? limit,
    int? offset,
    String? orderBy,
    List<int>? exampleIllustIds,
    bool filterBookmarks = false,
  }) async {
    return await _dbProvider.searchIllustsByTagId(tagId,
        limit: limit,
        offset: offset,
        orderBy: orderBy,
        exampleIllustIds: exampleIllustIds,
        filterBookmarks: filterBookmarks);
  }

  Future<List<DownloadedIllust>> searchDownloadedByTagName(
    String tagName, {
    int? limit,
    int? offset,
    String? orderBy,
    List<int>? exampleIllustIds,
    bool filterBookmarks = false,
  }) async {
    // 先获取标签 ID，再调用按 ID 搜索的方法
    final tag = await _dbProvider.getTagByName(tagName);
    if (tag == null) return [];
    return await searchDownloadedByTagId(tag.id,
        limit: limit,
        offset: offset,
        orderBy: orderBy,
        exampleIllustIds: exampleIllustIds,
        filterBookmarks: filterBookmarks);
  }

  Future<List<DownloadedIllust>> searchDownloaded(
    String keyword, {
    int? limit,
    int? offset,
    String? orderBy,
    bool filterBookmarks = false,
  }) async {
    return await _dbProvider.searchIllusts(keyword,
        limit: limit, offset: offset, orderBy: orderBy, filterBookmarks: filterBookmarks);
  }

  /// 获取包含非 WebP 图片的插画（排除动图）
  Future<List<DownloadedIllust>> getDownloadedWithNonWebPImages({
    int? limit,
    int? offset,
    String? orderBy,
    bool filterBookmarks = false,
  }) async {
    return await _dbProvider.getIllustsWithNonWebPImages(
      limit: limit,
      offset: offset,
      orderBy: orderBy,
      filterBookmarks: filterBookmarks,
    );
  }

  /// 获取所有未下载完整的作品（下载的图片数量小于 pageCount）
  /// 使用优化的数据库查询，避免在应用层逐个检查
  Future<List<DownloadedIllust>> getIncompleteDownloaded({
    int? limit,
    int? offset,
    String? orderBy,
    bool filterBookmarks = false,
  }) async {
    return await _dbProvider.getIncompleteIllusts(
      limit: limit,
      offset: offset,
      orderBy: orderBy,
      filterBookmarks: filterBookmarks,
    );
  }

  Future<List<Map<String, dynamic>>> getDistinctUsers() async {
    return await _dbProvider.getDistinctUsers();
  }

  /// 获取下载的作者列表，支持排序和搜索
  Future<List<DownloadedAuthor>> getDownloadedAuthors({
    String sortBy = 'last_download_time',
    bool desc = true,
    int? limit,
    int? offset,
    String? searchKeyword,
    bool filterBookmarks = false,
  }) async {
    return await _dbProvider.getAuthorsWithStats(
      sortBy: sortBy,
      desc: desc,
      limit: limit,
      offset: offset,
      searchKeyword: searchKeyword,
      filterBookmarks: filterBookmarks,
    );
  }

  /// 获取单个作者信息
  Future<DownloadedAuthor?> getAuthorByUserId(int userId) async {
    return await _dbProvider.getAuthorByUserId(userId);
  }

  /// 获取作者最新下载的插画
  Future<List<DownloadedIllust>> getAuthorLatestIllusts(
    int userId, {
    int limit = 3,
  }) async {
    return await _dbProvider.getIllustsByUserId(
      userId,
      limit: limit,
      offset: 0,
    );
  }

  /// 获取作者最新发布的插画（按createDate排序）
  Future<List<DownloadedIllust>> getAuthorLatestPublishedIllusts(
    int userId, {
    int limit = 3,
  }) async {
    return await _dbProvider.getIllustsByUserId(
      userId,
      limit: limit,
      offset: 0,
      orderBy: 'create_date DESC',
    );
  }

  /// 获取作者的图片统计信息（总图片张数和总文件大小）
  Future<Map<String, int>> getAuthorImageStats(int userId) async {
    return await _dbProvider.getAuthorImageStats(userId);
  }

  /// 获取筛选条件下的统计信息
  /// 返回：插画数量、图片数量（pageCount总和）、文件大小
  Future<Map<String, int>> getFilteredStats({
    String filterType = 'all',
    int? userId,
    String? searchKeyword,
    String? tagName,
    bool filterBookmarks = false,
  }) async {
    return await _dbProvider.getFilteredStats(
      filterType: filterType,
      userId: userId,
      searchKeyword: searchKeyword,
      tagName: tagName,
      filterBookmarks: filterBookmarks,
    );
  }

  Future<int> getDownloadedCount() async {
    return await _dbProvider.getIllustCount();
  }

  // ============ 状态查询 ============

  bool isDownloading(int illustId) {
    return downloadingTasks.keys.any((key) => key.startsWith('${illustId}_'));
  }

  bool isImageDownloading(int illustId, int part) {
    return downloadingTasks.containsKey('${illustId}_$part');
  }

  DownloadTask? getDownloadTask(int illustId, int part) {
    return downloadingTasks['${illustId}_$part'];
  }

  // 获取插画的下载进度（所有页面的平均进度）
  double getIllustDownloadProgress(int illustId) {
    final tasks =
        downloadingTasks.values.where((t) => t.illusts.id == illustId).toList();
    if (tasks.isEmpty) return 0;

    int totalReceived = 0;
    int totalBytes = 0;
    for (final task in tasks) {
      totalReceived += task.received;
      totalBytes += task.total;
    }
    return totalBytes > 0 ? totalReceived / totalBytes : 0;
  }

  /// 获取插画的下载状态
  /// [downloadedIllust] 可选参数，如果已经有 DownloadedIllust 对象则直接传入，避免重复查询数据库
  Future<IllustDownloadStatus?> getIllustDownloadStatus(
    int illustId, {
    DownloadedIllust? downloadedIllust,
  }) async {
    final illust = downloadedIllust ?? await getDownloadedIllust(illustId);
    if (illust == null) {
      return null;
    }
    final totalCount = illust.pageCount;

    // 使用物化字段，无需查询数据库
    final completedCount = illust.downloadedImageCount;
    final fileSize = illust.totalFileSize;

    // 优化状态判断：单次遍历，按优先级确定状态
    DownloadTaskStatus status;
    if (completedCount >= totalCount) {
      // 已完成或超额完成
      status = DownloadTaskStatus.completed;
    } else {
      // 查找相关任务，单次遍历按优先级判断状态
      final tasks = downloadingTasks.values
          .where((t) => t.illusts.id == illustId)
          .toList();

      if (tasks.isEmpty) {
        status = DownloadTaskStatus.completed;
      } else {
        // 按优先级顺序检查：downloading > pending > failed > paused
        final priorities = [
          DownloadTaskStatus.downloading,
          DownloadTaskStatus.pending,
          DownloadTaskStatus.failed,
          DownloadTaskStatus.paused,
        ];

        status = priorities.firstWhere(
          (priority) => tasks.any((t) => t.status == priority),
          orElse: () => DownloadTaskStatus.completed,
        );
      }
    }

    return IllustDownloadStatus(
      illusts: illust,
      status: status,
      totalCount: totalCount,
      completedCount: completedCount,
      fileSize: fileSize,
    );
  }

  /// 暂停插画的所有下载任务
  @action
  Future<void> pauseIllustDownload(int illustId) async {
    final tasksToRemove =
        downloadingTasks.values.where((t) => t.illusts.id == illustId).toList();
    for (final task in tasksToRemove) {
      if ((task.status == DownloadTaskStatus.downloading ||
          task.status == DownloadTaskStatus.pending)) {
        _runningTask.remove(task.taskKey);
        _pendingQueue.removeWhere((t) => t.taskKey == task.taskKey);
        task.status = DownloadTaskStatus.paused;
        await _dbProvider.updatePendingDownloadStatus(
            task.taskKey, task.status.name);
        _notifyProgress(task);
      }
    }
  }

  /// 恢复插画的所有暂停任务
  @action
  Future<void> resumeIllustDownload(int illustId) async {
    final tasks = downloadingTasks.values
        .where((t) =>
            t.illusts.id == illustId &&
            (t.status == DownloadTaskStatus.paused ||
                t.status == DownloadTaskStatus.failed))
        .toList();
    for (final task in tasks) {
      task.status = DownloadTaskStatus.pending;
      task.error = null;
      task.received = 0;
      await _dbProvider.updatePendingDownloadStatus(
          task.taskKey, task.status.name);
      _pendingQueue.add(task);
      _notifyProgress(task);
    }
    _processQueue();
  }

  /// 重启插画的所有失败任务
  @action
  void retryIllustDownload(int illustId) {
    final tasks = downloadingTasks.values
        .where((t) =>
            t.illusts.id == illustId && t.status == DownloadTaskStatus.failed)
        .toList();
    for (final task in tasks) {
      task.status = DownloadTaskStatus.pending;
      task.error = null;
      task.received = 0;
      _pendingQueue.add(task);
      _notifyProgress(task);
    }
    _processQueue();
  }

  // ============ 下载接口 ============

  @action
  Future<void> downloadIllust(Illusts illusts, {int? part, int bookmark = 0}) async {
    if (!isInitialized) {
      throw Exception('DownloadStore not initialized');
    }

    // 动图下载分流
    if (illusts.type == 'ugoira') {
      await downloadUgoira(illusts, bookmark: bookmark);
      return;
    }

    if (part != null) {
      // 下载单页
      _downloadTaskBuffer.add(createDownloadTask(illusts, part, bookmark: bookmark));
    } else {
      // 下载所有页
      if (illusts.pageCount == 1) {
        _downloadTaskBuffer.add(createDownloadTask(illusts, 0, bookmark: bookmark));
      } else {
        for (int i = 0; i < illusts.metaPages.length; i++) {
          _downloadTaskBuffer.add(createDownloadTask(illusts, i, bookmark: bookmark));
        }
      }
    }
    Future.delayed(const Duration(milliseconds: 100), () async {
      if (_downloadTaskBuffer.isEmpty) return;
      final list = List.of(_downloadTaskBuffer);
      _downloadTaskBuffer.clear();
      addDownloadTasks(list);
    });
  }

  /// 下载动图
  @action
  Future<void> downloadUgoira(Illusts illusts, {int bookmark = 0}) async {
    final illustId = illusts.id;

    // 先检查任务是否已存在（优先检查，避免重复创建任务）
    final taskKey = '${illusts.id}_0';
    if (downloadingTasks.containsKey(taskKey)) {
      final existingTask = downloadingTasks[taskKey]!;
      if (!existingTask.isCanRetry) {
        BotToast.showText(text: '动图已在下载队列中');
        return;
      }
    }

    // 检查是否已真正下载完成（使用物化字段）
    // 注意：不能只检查 DownloadedIllust 记录，因为记录会在下载开始时插入
    // 需要检查物化字段 downloadedImageCount 是否大于 0
    final existingIllust = await _dbProvider.getIllustByIllustId(illustId);
    if (existingIllust != null && existingIllust.downloadedImageCount > 0) {
      // 有图片记录，说明已下载完成
      BotToast.showText(text: '动图已下载');
      return;
    }

    // 先插入作品记录到数据库（与普通图片下载保持一致）
    await _insertIllustIfNotExists(illusts, bookmark: bookmark);
    
    // 创建动图下载任务（part=0 表示整个动图）
    final task = createDownloadTask(illusts, 0, bookmark: bookmark);
    task.url = ''; // 稍后从元数据获取
    
    await _addDownloadTask(task);
  }



  Future<({String fullPath, String relativePath})?> _tryFindExistingImageFile(DownloadTask task) async {
    final relativePath = await _dbProvider.resolveRelativePath(task.illusts);
    final fileName =
        DownloadDatabaseProvider.buildFileName(task.illusts.id, task.part);
    for (final ext in kImageExtensions) {
      final fullPath = _dbProvider.getAbsolutePath(relativePath, '$fileName$ext');
      if (await File(fullPath).exists()) {
        return (fullPath: fullPath, relativePath: relativePath);
      }
    }
    return null;
  }

  /// 创建下载任务
  DownloadTask createDownloadTask(Illusts illusts, int part, {int bookmark = 0}) {
    // 获取下载URL
    String url;
    if (illusts.pageCount == 1) {
      url = illusts.metaSinglePage!.originalImageUrl!;
    } else {
      url = illusts.metaPages[part].imageUrls!.original;
    }

    // 创建下载任务
    final task = DownloadTask(
      illusts: illusts,
      part: part,
      url: url,
      status: DownloadTaskStatus.pending,
      createTime: DateTime.now().millisecondsSinceEpoch,
      bookmark: bookmark,
    );
    return task;
  }

  /// 加入下载（优化版本，支持批量处理）
  Future<void> addDownloadTasks(List<DownloadTask> tasks,
      {bool batchMode = false}) async {
    if (tasks.isEmpty) return;

    // 过滤掉已存在的任务
    final needAddTasks = <DownloadTask>[];
    final existingTaskKeys = <String>{};

    for (final task in tasks) {
      final taskKey = task.taskKey;
      if (downloadingTasks.containsKey(taskKey)) {
        final existingTask = downloadingTasks[taskKey]!;
        if (!existingTask.isCanRetry) {
          Log.d(
              'DownloadStore task $taskKey already exists, ${existingTask.error}, ${existingTask.status}');
          continue;
        }
      }
      needAddTasks.add(task);
      existingTaskKeys.add(taskKey);
    }

    if (needAddTasks.isEmpty) {
      BotToast.showText(text: '所有图片都已下载');
      return;
    }

    // 批量模式：使用批量检查已下载状态
    if (batchMode && needAddTasks.length > 50) {
      await _addDownloadTasksBatch(needAddTasks);
    } else {
      // 普通模式：逐个检查
      await _addDownloadTasksNormal(needAddTasks);
    }
  }

  /// 批量添加下载任务（优化版本）
  Future<void> _addDownloadTasksBatch(List<DownloadTask> tasks) async {
    // 1. 批量检查已下载状态
    final illustParts = tasks
        .map((t) => {
              'illustId': t.illusts.id,
              'part': t.part,
            })
        .toList();
    final downloadedResults =
        await _dbProvider.batchCheckImageDownloaded(illustParts);

    // 组装成字符串键集合，方便后续查找
    final downloadedTaskKeys =
        downloadedResults.map((e) => '${e['illustId']}_${e['part']}').toSet();

    // 2. 过滤掉已下载的任务
    final tasksToAdd = <DownloadTask>[];
    final taskKeysToDelete = <String>[];

    for (final task in tasks) {
      final key = '${task.illusts.id}_${task.part}';
      if (downloadedTaskKeys.contains(key)) {
        taskKeysToDelete.add(task.taskKey);
        continue;
      }
      tasksToAdd.add(task);
    }

    // 批量删除已下载任务的 pending 记录（使用批量删除优化性能）
    if (taskKeysToDelete.isNotEmpty) {
      Log.d(() =>
          'DownloadStore delete ${taskKeysToDelete.length} pending downloads');
      await _dbProvider.batchDeletePendingDownloads(taskKeysToDelete);
    }

    if (tasksToAdd.isEmpty) {
      Log.d(() => 'DownloadStore all tasks already downloaded');
      BotToast.showText(text: '所有图片都已下载');
      return;
    }

    // 3. 批量插入 illust 记录（去重并批量插入）
    final illustIds = <int>{};
    final illustsToInsert = <DownloadedIllust>[];
    for (final task in tasksToAdd) {
      if (!illustIds.contains(task.illusts.id)) {
        illustIds.add(task.illusts.id);
        illustsToInsert.add(DownloadedIllust.fromIllusts(
          task.illusts,
          await _dbProvider.resolveRelativePath(task.illusts),
          bookmark: task.bookmark,
        ));
      }
    }
  

    // 批量检查并插入 illust（使用批量操作优化性能）
    await _dbProvider.batchInsertIllustsIfNotExists(illustsToInsert);

    // 4. 批量添加到内存和数据库
    final pendingDownloads = <PendingDownload>[];
    final tasksToNotify = <DownloadTask>[];
    final tasksToQueue = <DownloadTask>[];

    // 分批检查文件是否存在（避免一次性创建太多并发任务）
    const batchSize = 100;
    for (int i = 0; i < tasksToAdd.length; i += batchSize) {
      final batch = tasksToAdd.skip(i).take(batchSize).toList();
      await Future.wait(batch.map((task) async {
        try {
          final result = await _tryFindExistingImageFile(task);
          if (result != null) {
            // 文件已存在，直接记录
            final url = task.illusts.pageCount == 1
                ? task.illusts.metaSinglePage!.originalImageUrl!
                : task.illusts.metaPages[task.part].imageUrls!.original;
            await _recordDownload(
              task.illusts,
              relativePath: result.relativePath,
              part: task.part,
              url: url,
              filePath: result.fullPath,
              bookmark: task.bookmark,
            );
            task.status = DownloadTaskStatus.completed;
            tasksToNotify.add(task);
          } else {
            // 需要下载，添加到队列
            tasksToQueue.add(task);
          }
        } catch (e) {
          // 单个任务失败不影响其他任务，记录错误并添加到下载队列
          Log.e('检查文件存在性失败: ${task.taskKey}, $e');
          tasksToQueue.add(task);
        }
      }));
    }

    // 5. 先批量插入 pending 记录到数据库（保证数据一致性）
    if (tasksToQueue.isNotEmpty) {
      for (final task in tasksToQueue) {
        pendingDownloads.add(task.toPendingDownload());
      }
      await _dbProvider.batchInsertPendingDownloads(pendingDownloads);
    }

    // 6. 数据库插入成功后再更新内存（保证数据一致性）
    runInAction(() {
      for (final task in tasksToQueue) {
        downloadingTasks[task.taskKey] = task;
        _pendingQueue.add(task);
      }
    });

    // 7. 批量通知（减少 MobX 更新频率）
    if (tasksToNotify.isNotEmpty || tasksToQueue.isNotEmpty) {
      // 延迟通知，避免频繁更新 UI
      Future.microtask(() {
        for (final task in tasksToNotify) {
          _notifyProgress(task);
        }
        // 只通知新添加的待下载任务（分批通知，避免一次性通知太多）
        const notifyBatchSize = 50;
        for (int i = 0; i < tasksToQueue.length; i += notifyBatchSize) {
          Future.delayed(Duration(milliseconds: i ~/ notifyBatchSize * 10), () {
            final batch = tasksToQueue.skip(i).take(notifyBatchSize).toList();
            for (final task in batch) {
              _notifyProgress(task);
            }
          });
        }
      });
    }

    // 处理队列
    _processQueue();

    BotToast.showText(text: '添加 ${tasksToAdd.length} 个下载任务');
  }

  /// 普通模式添加下载任务（保持原有逻辑）
  Future<void> _addDownloadTasksNormal(List<DownloadTask> tasks) async {
    final ids = <int>{};
    int addedCount = 0;
    for (final task in tasks) {
      final taskKey = task.taskKey;
      final isDownloaded =
          await _dbProvider.isImageDownloaded(task.illusts.id, task.part);
      if (isDownloaded) {
        Log.d('DownloadStore task $taskKey already downloaded');
        await _dbProvider.deletePendingDownload(task.taskKey);
        continue;
      }

      final illusts = task.illusts;
      if (!ids.contains(illusts.id)) {
        ids.add(illusts.id);
        await _insertIllustIfNotExists(illusts, bookmark: task.bookmark);
      }
      await _addDownloadTask(task);
      addedCount++;
    }

    if (addedCount > 0) {
      BotToast.showText(text: '添加 $addedCount 个下载任务');
    } else if (tasks.isNotEmpty) {
      BotToast.showText(text: '所有图片都已下载');
    }
  }

  Future<void> _addDownloadTask(DownloadTask task) async {
    if (!task.illusts.isUgoira) {
      // 获取下载URL
      String url;
      if (task.illusts.pageCount == 1) {
        url = task.illusts.metaSinglePage!.originalImageUrl!;
      } else {
        url = task.illusts.metaPages[task.part].imageUrls!.original;
      }

      // 检查目标文件是否已存在
      final result = await _tryFindExistingImageFile(task);

      if (result != null) {
        // 文件已存在，直接记录到数据库
        await _recordDownload(
          task.illusts,
          relativePath: result.relativePath,
          part: task.part,
          url: url,
          filePath: result.fullPath,
          bookmark: task.bookmark,
        );
        task.status = DownloadTaskStatus.completed;
        _notifyProgress(task);
        return;
      }
    }

    downloadingTasks[task.taskKey] = task;
    _pendingQueue.add(task);
    // 添加到pending数据库中
    await _dbProvider.insertPendingDownload(task.toPendingDownload());
    Log.d("添加下载任务: ${task.taskKey}");

    // 通知 pending 状态
    _notifyProgress(task);

    // 尝试处理队列
    _processQueue();
  }

  void _processQueue() {
    while (_pendingQueue.isNotEmpty && _runningTask.length < _maxConcurrent) {
      final task = _pendingQueue.removeFirst();
      if (!downloadingTasks.containsKey(task.taskKey)) {
        // 任务已被取消
        continue;
      }
      _runningTask.add(task.taskKey);
      _startDownload(task);
    }
  }

  Future<void> _startDownload(DownloadTask task) async {
    task.status = DownloadTaskStatus.downloading;
    _notifyProgress(task);

    try {
      // 判断是否为动图任务
      if (task.illusts.type == 'ugoira') {
        await _downloadUgoiraTask(task);
      } else {
        await _downloadNormalImage(task);
      }
    } catch (e) {
      _onDownloadFailed(task, e.toString());
    }
  }

  /// 下载普通图片
  Future<void> _downloadNormalImage(DownloadTask task) async {
    final relativePath = await _dbProvider.resolveRelativePath(task.illusts);
    final fileName = DownloadDatabaseProvider.buildFileName(task.illusts.id, task.part);
    final extension = path.extension(task.url);
    final targetPath = _dbProvider.getAbsolutePath(relativePath, '$fileName$extension');

    final targetFile = File(targetPath);
    final targetDir = targetFile.parent;

    // 确保目标目录存在
    if (!await targetDir.exists()) {
      try {
        await targetDir.create(recursive: true);
      } catch (e) {
        // 如果目录创建失败，可能是路径中包含非法字符
        Log.e('创建目录失败: ${targetDir.path}, 错误: $e');
        throw Exception(
            '无法创建目录: ${targetDir.path}。可能包含Windows不支持的字符（如emoji）。请检查路径设置。');
      }
    }

    // 1. 尝试从缓存获取
    final cached = await pixivCacheManager.getFileFromCache(task.url);
    if (cached != null && await cached.file.exists()) {
      // 从缓存复制到目标目录
      await cached.file.copy(targetPath);
      await _onDownloadSuccess(task, targetPath, relativePath);
      return;
    }

    // 2. 使用pixivCacheManager下载
    final fileInfo = await pixivCacheManager.downloadFile(
      task.url,
      authHeaders: Hoster.header(url: task.url),
    );

    // 3. 复制到目标目录
    await fileInfo.file.copy(targetPath);

    // 4. 清理任务
    await _onDownloadSuccess(task, targetPath, relativePath);
  }

  /// 下载动图任务
  Future<void> _downloadUgoiraTask(DownloadTask task) async {
    final illusts = task.illusts;
    final illustId = illusts.id;

    // 创建 Ugoira 下载器
    final downloader = ugoiraDownloader;

    try {
      // 0. 再次检查是否已下载（使用物化字段，防止并发下载）
      // 检查物化字段 downloadedImageCount 是否大于 0
      final existingIllust = await _dbProvider.getIllustByIllustId(illustId);
      if (existingIllust != null && existingIllust.downloadedImageCount > 0) {
        // 有图片记录，说明已真正下载完成
        // 这里没有relativePath，但既然已经下载完成，理论上不需要再调用_onDownloadSuccess进行完整记录
        // 但为了保持接口一致，这里尝试获取一下，或者传递空字符串（如果下面不用的话）
        // 实际上 _onDownloadSuccess 会调用 _recordDownload，所以需要 relativePath
        // 既然已经存在，可以直接从 existingIllust 获取
        await _onDownloadSuccess(task, '', existingIllust.relativePath);
        return;
      }

      // 1. 使用统一的下载方法获取元数据和帧文件
      final result = await downloader.fetchMetadataAndExtractFrames(illustId);
      final metadata = result.metadata;
      final tempFrameFiles = result.frameFiles;

      // 2. 移动帧图片到目标目录
      final relativePath = await _dbProvider.resolveRelativePath(illusts);
      final targetDir = Directory(_dbProvider.getUgoiraFrameDirPath(relativePath));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      for (final frameFile in tempFrameFiles) {
        final destPath = path.join(targetDir.path, path.basename(frameFile.path));
        await frameFile.copy(destPath);
      }

      // 3. 下载预览图
      final previewUrl = illusts.metaSinglePage?.originalImageUrl ??
                         illusts.imageUrls.large;
      final previewFileName = DownloadDatabaseProvider.buildFileName(illustId, 0);
      final previewExtension = path.extension(previewUrl);
      final previewPath = _dbProvider.getAbsolutePath(
        relativePath,
        '$previewFileName$previewExtension'
      );

      final previewFile = await pixivCacheManager.getSingleFile(
        previewUrl,
        headers: Hoster.header(url: previewUrl),
      );
      await previewFile.copy(previewPath);

      // 4. 保存数据库记录（传递帧文件列表）
      await _recordUgoiraDownload(
        illusts,
        metadata,
        tempFrameFiles,
        previewPath,
        previewUrl,
        relativePath,
      );

      // 5. 清理临时解压目录（ZIP 由 pixivCacheManager 管理）
      await downloader.cleanupTempExtractDir(illustId);

      // 6. 完成下载
      await _onDownloadSuccess(task, previewPath, relativePath);
    } catch (e) {
      // 失败时清理临时解压目录
      try {
        await downloader.cleanupTempExtractDir(illustId);
      } catch (_) {}
      rethrow;
    }
  }

  /// 记录动图下载到数据库
  Future<void> _recordUgoiraDownload(
    Illusts illusts,
    UgoiraMetadataResponse metadata,
    List<File> frameFiles,
    String previewPath,
    String previewUrl,
    String relativePath, {
    int bookmark = 0,
  }) async {

    // 1. 插入插画记录（包含完整 UgoiraMetadata）
    final metadataJson = PixivUrlUtil.compressPxUrl(
      TypeUtil.parseJsonString(metadata.ugoiraMetadata.toJson())
    );

    final downloadedIllust = DownloadedIllust.fromIllusts(
      illusts,
      relativePath,
      ugoiraMetadataJson: metadataJson,
      bookmark: bookmark,
    );

    await _dbProvider.insertIllust(downloadedIllust);

    // 2. 插入预览图记录（part=0）
    final previewFile = File(previewPath);
    final previewFileSize = await previewFile.length();

    final downloadedImage = DownloadedImage(
      illustId: illusts.id,
      part: 0,
      fileName: DownloadDatabaseProvider.buildFileName(illusts.id, 0),
      extension: path.extension(previewPath),
      fileSize: previewFileSize,
      originalUrl: previewUrl,
      relativePath: relativePath,
    );

    await _dbProvider.insertImage(downloadedImage);

    // 3. 插入动图帧记录（part=1, 2, 3...）
    // 只读取第一帧的宽高，因为所有帧图片尺寸相同
    int? frameWidth;
    int? frameHeight;

    if (frameFiles.isNotEmpty) {
      try {
        final firstFrameSize = await getImageSize(frameFiles[0].path);
        if (firstFrameSize != null) {
          frameWidth = firstFrameSize.width.toInt();
          frameHeight = firstFrameSize.height.toInt();
        }
      } catch (e) {
        Log.e('解析动图帧图片宽高失败: ${illusts.id}, $e');
      }
    }

    for (int i = 0; i < frameFiles.length; i++) {
      final frameFile = frameFiles[i];

      if (await frameFile.exists()) {
        final fileSize = await frameFile.length();
        final fileNameWithoutExtension = path.basenameWithoutExtension(frameFile.path);
        final extension = path.extension(frameFile.path);

        final frameRelativePath = path.join(relativePath, 'ugoira'); // 帧文件在 ugoira 子目录中

        final downloadedFrame = DownloadedImage(
          illustId: illusts.id,
          part: i + 1, // part 从 1 开始（0 是预览图）
          fileName: fileNameWithoutExtension,
          extension: extension,
          fileSize: fileSize,
          originalUrl: '', // 帧文件没有原始 URL
          relativePath: frameRelativePath,
          width: frameWidth,
          height: frameHeight,
        );

        await _dbProvider.insertImage(downloadedFrame);
      }
    }

    // 4. 更新作者统计
    await _dbProvider.updateAuthorStats(illusts.user.id);
  }

  Future<void> _onDownloadSuccess(DownloadTask task, String targetPath, String relativePath) async {
    Log.d(() => "下载成功: ${task.taskKey}, $targetPath");

    // 检查任务是否已被取消（例如用户删除了该插画）
    if (!downloadingTasks.containsKey(task.taskKey)) {
      Log.d(() => "任务已被取消，跳过记录: ${task.taskKey}");
      _runningTask.remove(task.taskKey);
      // 删除已下载的文件
      try {
        final file = File(targetPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        Log.e('删除已取消任务的文件失败: $targetPath');
      }
      _processQueue();
      return;
    }

    task.status = DownloadTaskStatus.completed;
    task.status = DownloadTaskStatus.completed;
    await _recordDownload(
      task.illusts,
      relativePath: relativePath,
      part: task.part,
      url: task.url,
      filePath: targetPath,
      bookmark: task.bookmark,
    );
    await _dbProvider.deletePendingDownload(task.taskKey);
    downloadingTasks.remove(task.taskKey);
    _notifyProgress(task);
    _runningTask.remove(task.taskKey);
    _processQueue();
    await refreshCount();
    pixivCacheManager.removeFile(task.url);
  }

  Future<void> _onDownloadFailed(DownloadTask task, String error) async {
    Log.e(() => "下载失败: ${task.taskKey}, $error");
    task.status = DownloadTaskStatus.failed;
    task.error = error;
    _runningTask.remove(task.taskKey);
    // 任务失败后不从downloadingTasks中移除，这样后续可以继续尝试
    //downloadingTasks.remove(task.taskKey);
    await _dbProvider.updatePendingDownloadStatus(
        task.taskKey, task.status.name);
    _notifyProgress(task);
    _processQueue();
  }

  // 由 Downloader 调用，报告进度
  @action
  void updateProgress(String taskKey, int received, int total) {
    final task = downloadingTasks[taskKey];
    if (task != null) {
      task.received = received;
      task.total = total;
      _notifyProgress(task);
    }
  }

  // 由 Downloader 调用，报告失败
  @action
  void onDownloadFailed(String taskKey, String error) {
    final task = downloadingTasks[taskKey];
    if (task == null) return;

    task.status = DownloadTaskStatus.failed;
    task.error = error;
    _notifyProgress(task);

    // 不从 downloadingTasks 中移除，允许重试
    _runningTask.remove(task.url);
    _processQueue();
  }

  // 重试失败的任务
  @action
  void retryTask(String taskKey) {
    final task = downloadingTasks[taskKey];
    if (task != null && task.status == DownloadTaskStatus.failed) {
      task.status = DownloadTaskStatus.pending;
      task.error = null;
      task.received = 0;
      _pendingQueue.add(task);
      _processQueue();
    }
  }

  // 取消下载任务
  @action
  void cancelTask(String taskKey) {
    final task = downloadingTasks[taskKey];
    if (task != null) {
      _runningTask.remove(task.taskKey);
      _pendingQueue.removeWhere((t) => t.taskKey == taskKey);
      downloadingTasks.remove(taskKey);
      _dbProvider.deletePendingDownload(taskKey);
    }
  }

  // 取消下载任务（内部使用，可选是否删除 pending 记录）
  void _cancelTaskInternal(String taskKey, {bool deletePending = true}) {
    final task = downloadingTasks[taskKey];
    if (task != null) {
      _runningTask.remove(task.taskKey);
      _pendingQueue.removeWhere((t) => t.taskKey == taskKey);
      downloadingTasks.remove(taskKey);
      if (deletePending) {
        _dbProvider.deletePendingDownload(taskKey);
      }
    }
  }

  // 取消插画的所有下载任务
  @action
  void cancelIllustDownload(int illustId) {
    final keysToRemove = downloadingTasks.keys
        .where((key) => key.startsWith('${illustId}_'))
        .toList();
    for (final key in keysToRemove) {
      cancelTask(key);
    }
  }

  // 取消插画的所有下载任务（内部使用，可选是否删除 pending 记录）
  void _cancelIllustDownloadInternal(int illustId,
      {bool deletePending = true}) {
    final keysToRemove = downloadingTasks.keys
        .where((key) => key.startsWith('${illustId}_'))
        .toList();
    for (final key in keysToRemove) {
      _cancelTaskInternal(key, deletePending: deletePending);
    }
  }

  void _notifyProgress(DownloadTask task) {
    _progressController.add(task);
  }

  /// 插入插画信息
  Future<void> _insertIllustIfNotExists(Illusts illusts, {int bookmark = 0}) async {
    final existingIllust = await _dbProvider.getIllustByIllustId(illusts.id);
    if (existingIllust == null) {
      // 插画不存在，插入数据库
      final downloadedIllust = DownloadedIllust.fromIllusts(
          illusts, await _dbProvider.resolveRelativePath(illusts), bookmark: bookmark);
      await _dbProvider.insertIllust(downloadedIllust);
    }
  }

  /// 更新已下载的插画信息
  Future<bool> updateDownloadedIllust(Illusts illusts) async {
    if (!isInitialized) return false;

    try {
      final existingIllust = await _dbProvider.getIllustByIllustId(illusts.id);
      if (existingIllust == null) {
        return false;
      }
      Log.d(() => "更新已下载的插画信息: ${illusts.id}");

      // 使用 fromIllusts 方法创建优化后的 DownloadedIllust（保留原有的 relativePath 和 downloadTime）
      final updatedIllust = DownloadedIllust.fromIllusts(
        illusts,
        existingIllust.relativePath,
        downloadTime: existingIllust.downloadTime,
        ugoiraMetadataJson: existingIllust.ugoiraMetadataJson,
        downloadedImageCount: existingIllust.downloadedImageCount,
        totalFileSize: existingIllust.totalFileSize,
        bookmark: existingIllust.bookmark,
      );

      await _dbProvider.updateIllust(updatedIllust);
      return true;
    } catch (e) {
      Log.e('更新已下载的插画信息失败: $e');
      return false;
    }
  }

  /// 优化现有数据库中的 illustJson 字段（移除重复存储的字段）
  /// 返回优化后的记录数和节省的字节数
  Future<Map<String, int>> optimizeIllustJson({
    Function(int current, int total, int savedBytes)? onProgress,
    bool Function()? shouldCancel,
    Function()? onVacuumStart,
  }) async {
    if (!isInitialized) {
      throw Exception('DownloadStore not initialized');
    }

    Log.d('开始优化 illustJson 字段...');

    int optimizedCount = 0;
    int initialSize = await _dbProvider.getDatabaseSize();
    
    // 1. 第一步：备份数据库
    try {
      final dbPath = _dbProvider.dbPathStr;
      if (dbPath.isNotEmpty) {
        final dbFile = File(dbPath);
        if (await dbFile.exists()) {
          // 轮转备份：最多保留3份 (.bak, .bak.1, .bak.2)
          for (int i = 2; i >= 0; i--) {
            final suffix = i == 0 ? '.bak' : '.bak.$i';
            final currentBak = File('$dbPath$suffix');
            if (await currentBak.exists()) {
              if (i == 2) {
                await currentBak.delete();
              } else {
                await currentBak.rename('$dbPath.bak.${i + 1}');
              }
            }
          }

          Log.d('正在备份数据库到 $dbPath.bak ...');
          await dbFile.copy('$dbPath.bak');
          Log.d('备份完成');
        }
      }
    } catch (e) {
      Log.e('备份数据库失败: $e');
      // 备份失败是否继续？通常建议继续，或者抛出异常让用户确认
    }

    try {
      // 记录优化过程中的估算节省空间（用于进度显示）
      int initialSavedBytes = 0;

      // 先获取所有插画的ID和原始illustJson（直接从数据库查询，不经过fromJson处理）
      final rawData = await _dbProvider.db.query(
        DownloadedIllustColumns.tableName,
        columns: [
          DownloadedIllustColumns.illustId,
          DownloadedIllustColumns.illustJson,
        ],
      );

      // 创建一个Map，存储每个illustId对应的原始illustJson长度（数据库中实际存储的blob大小）
      final originalSizes = <int, int>{};
      for (final row in rawData) {
        final illustId = row[DownloadedIllustColumns.illustId] as int;
        final rawIllustJson = row[DownloadedIllustColumns.illustJson];
        // 计算原始存储的大小（可能是blob或string）
        final size = rawIllustJson is String
            ? rawIllustJson.length
            : (rawIllustJson as List<int>).length;
        originalSizes[illustId] = size;
      }

      // 获取所有插画记录（经过fromJson处理）
      final allIllusts = await _dbProvider.getAllIllusts();
      final total = allIllusts.length;

      Log.d('找到 $total 条记录需要优化');

      // 分批处理，每批 50 条
      const batchSize = 50;
      for (int i = 0; i < allIllusts.length; i += batchSize) {
        // 检查是否应该取消
        if (shouldCancel != null && shouldCancel()) {
          Log.d(
              '优化已取消: 已优化 $optimizedCount 条记录');
          throw Exception('优化已取消');
        }

        final batch = allIllusts.skip(i).take(batchSize).toList();

        for (final existingIllust in batch) {
          // 在处理每条记录前也检查取消标志
        if (shouldCancel != null && shouldCancel()) {
          Log.d(
              '优化已取消: 已优化 $optimizedCount 条记录');
          throw Exception('优化已取消');
        }

          try {
            // 尝试从 illustJson 反序列化为 Illusts
            final illusts = existingIllust.toIllusts();

            // 使用 fromIllusts 重新创建优化后的记录
            final optimizedIllust = DownloadedIllust.fromIllusts(
              illusts,
              existingIllust.relativePath,
              downloadTime: existingIllust.downloadTime,
              ugoiraMetadataJson: existingIllust.ugoiraMetadataJson,
              downloadedImageCount: existingIllust.downloadedImageCount,
              totalFileSize: existingIllust.totalFileSize,
              bookmark: existingIllust.bookmark,
            );

            // 估算节省的字节数（用于进度条显示）
            final oldSize = originalSizes[existingIllust.illustId] ?? 0;
            final newCompressedJson = optimizedIllust.toJson()[DownloadedIllustColumns.illustJson] as String;
            final newSize = newCompressedJson.length;
            final saved = oldSize - newSize;

            // 如果节省了空间，或者 imageUrlsJson 字段为空（需要迁移），则更新
            if (saved > 0 || existingIllust.imageUrlsJson.isEmpty) {
              // 更新数据库
              await _dbProvider.updateIllust(optimizedIllust);
              optimizedCount++;
              initialSavedBytes += saved > 0 ? saved : 0;
            }
          } catch (e) {
            // 如果反序列化失败，可能是数据损坏，跳过
            Log.e('优化记录失败 (illustId: ${existingIllust.illustId}): $e');
          }
        }

        // 报告进度（包含已节省的字节数）
        if (onProgress != null) {
          onProgress(i + batch.length, total, initialSavedBytes);
        }
      }

      Log.d(
          '优化完成: 优化了 $optimizedCount 条记录');

      // 检查是否应该取消
      if (shouldCancel != null && shouldCancel()) {
        Log.d('优化已取消（在 URL 优化前）');
        throw Exception('优化已取消');
      }

      // 优化 downloaded_images 表的 original_url 字段
      Log.d('开始优化 downloaded_images 表的 original_url 字段...');
      try {
        await _dbProvider.optimizeImageOriginalUrls();
        Log.d('original_url 优化完成');
      } catch (e) {
        Log.e('优化 original_url 失败: $e');
        // 不影响整体结果，继续执行
      }

      // 执行 VACUUM 回收数据库空间
      //if (optimizedCount > 0) {
      Log.d('开始执行 VACUUM 回收数据库空间...');
      if (onVacuumStart != null) {
        onVacuumStart();
      }
      try {
        await _dbProvider.vacuum();
        Log.d('VACUUM 执行完成，数据库空间已回收');
      } catch (e) {
        Log.e('执行 VACUUM 失败: $e');
        // VACUUM 失败不影响优化结果，只记录错误
      }
      //}

      // 7. 计算最终节省的物理空间
      final finalSize = await _dbProvider.getDatabaseSize();
      final actualSavedBytes = initialSize - finalSize;
      Log.d('物理大小改变: $initialSize -> $finalSize, 节省: $actualSavedBytes');

      return {
        'optimized_count': optimizedCount,
        'saved_bytes': actualSavedBytes > 0 ? actualSavedBytes : 0,
      };
    } catch (e) {
      Log.e('优化 illustJson 失败: $e');
      rethrow;
    }
  }

  // 记录下载完成
  Future<void> _recordDownload(
    Illusts illusts, {
    required String relativePath,
    required int part,
    required String url,
    required String filePath,
    int bookmark = 0,
  }) async {
    final fileName = path.basenameWithoutExtension(filePath);
    final extension = path.extension(filePath);
    await _insertIllustIfNotExists(illusts, bookmark: bookmark);

    // 获取文件大小
    int fileSize = 0;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        fileSize = await file.length();
      }
    } catch (_) {}

    // 解析图片宽高
    int? imageWidth;
    int? imageHeight;
    try {
      final size = await getImageSize(filePath);
      if (size != null) {
        imageWidth = size.width.toInt();
        imageHeight = size.height.toInt();
      }
    } catch (e) {
      Log.e('解析图片宽高失败: $filePath, $e');
    }

    // 创建图片记录
    final downloadedImage = DownloadedImage(
      illustId: illusts.id,
      part: part,
      fileName: fileName,
      extension: extension,
      fileSize: fileSize,
      originalUrl: url,
      relativePath: relativePath,
      width: imageWidth,
      height: imageHeight,
    );
    await _dbProvider.insertImage(downloadedImage);

    // 更新作者表统计信息
    await _dbProvider.updateAuthorStats(illusts.user.id);
  }

  /// 使用 image_size_getter 解析图片宽高
  Future<Size?> getImageSize(String filePath) async {
    return await ImageUtils.parseImageSize(filePath);
  }

  // ============ 删除接口 ============

  @action
  Future<void> deleteDownloadedIllust(int illustId) async {
    // 1. 先取消所有正在进行的下载任务（不单独删除 pending，后面统一删除）
    _cancelIllustDownloadInternal(illustId, deletePending: false);

    // 2. 删除数据库中的 pending 下载记录（统一删除，包括内存中没有的遗留记录）
    await _dbProvider.deletePendingDownloadsByIllustId(illustId);

    // 获取插画信息
    final illust = await _dbProvider.getIllustByIllustId(illustId);
    if (illust == null) return;

    // 获取所有图片信息（包含完整路径，动图包含序列帧）
    final imageInfos = await _dbProvider.getLocalImageInfosByIllustId(
      illustId,
      includeUgoiraFrames: true,
    );

    // 删除文件
    for (final imageInfo in imageInfos.values) {
      try {
        final file = File(imageInfo.path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e, s) {
        Log.e('删除文件失败: ${imageInfo.path}', stackTrace: s);
      }
    }

    // 尝试删除空目录（递归删除空子目录）
    final illustDir = _dbProvider.getIllustAbsolutePath(illust.relativePath);
    try {
      await _deleteEmptyDirectory(Directory(illustDir));
    } catch (e, s) {
      Log.e('删除目录失败: ${illustDir}', stackTrace: s);
    }

    // 从数据库删除
    final userId = illust.userId;
    await _dbProvider.deleteIllustByIllustId(illustId);

    // 更新或删除作者记录（根据是否还有插画）
    await _dbProvider.deleteAuthorIfEmpty(userId);

    // 通知删除状态
    _illustDownloadStatusController.add(IllustDownloadStatus(
      status: DownloadTaskStatus.deleted,
      illusts: illust,
      totalCount: illust.pageCount,
      completedCount: 0,
      fileSize: 0,
    ));

    await refreshCount();
  }

  /// 递归删除空目录
  /// 如果目录为空（包括子目录），则删除该目录
  Future<void> _deleteEmptyDirectory(Directory dir) async {
    if (!await dir.exists()) return;

    try {
      // 先递归处理子目录
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          await _deleteEmptyDirectory(entity);
        }
      }

      // 检查目录是否为空
      final contents = await dir.list().toList();
      if (contents.isEmpty) {
        await dir.delete();
        Log.d('删除空目录: ${dir.path}');
      }
    } catch (e) {
      Log.w('_deleteEmptyDirectory 失败: ${dir.path}, $e');
    }
  }

  // ============ 文件存在性检查 ============

  /// 检查插画的所有图片是否都已下载（使用物化字段）
  Future<bool> isIllustFullyDownloaded(int illustId) async {
    final illust = await _dbProvider.getIllustByIllustId(illustId);
    if (illust == null) return false;
    return illust.downloadedImageCount >= illust.pageCount;
  }

  /// 获取插画已下载的页数（使用物化字段）
  Future<int> getDownloadedPageCount(int illustId) async {
    final illust = await _dbProvider.getIllustByIllustId(illustId);
    return illust?.downloadedImageCount ?? 0;
  }

  /// 获取插画的总文件大小（使用物化字段）
  Future<int> getIllustTotalFileSize(int illustId) async {
    final illust = await _dbProvider.getIllustByIllustId(illustId);
    return illust?.totalFileSize ?? 0;
  }


  /// 获取插画的下载目录路径（从 Illusts 对象构建）
  Future<String?> getIllustDownloadDirectory(Illusts illusts) async {
    if (!isInitialized) {
      return null;
    }
    final relativePath = await _dbProvider.resolveRelativePath(illusts);
    return _dbProvider.getIllustAbsolutePath(relativePath);
  }

  /// 获取已下载插画的目录绝对路径（从 DownloadedIllust 对象）
  String? getIllustDirectoryPath(DownloadedIllust illust) {
    if (!isInitialized) {
      return null;
    }
    return _dbProvider.getIllustAbsolutePath(illust.relativePath);
  }

  /// 获取作者的下载目录路径
  /// 路径格式：downloadPath/[userName][userId]
  Future<String?> getAuthorDirectoryPath(DownloadedAuthor author) async {
    if (!isInitialized) {
      return null;
    }
    final userDirName = await _dbProvider.resolveAuthorDirectoryPath(
      author.userId,
      author.userName,
    );
    return path.join(_dbProvider.downloadPath, userDirName);
  }


  /// 检查插画的下载目录是否存在
  Future<bool> isIllustDirectoryExists(Illusts illusts) async {
    final dirPath = await getIllustDownloadDirectory(illusts);
    if (dirPath == null) {
      return false;
    }
    final dir = Directory(dirPath);
    return await dir.exists();
  }

  /// 检查并修复数据库（移除不存在的文件记录）
  Future<void> verifyAndCleanup() async {
    final illusts = await _dbProvider.getAllIllusts();
    for (final illust in illusts) {
      final images = await _dbProvider.getImagesByIllustId(illust.illustId);
      bool hasValidImage = false;

      for (final image in images) {
        final filePath =
            await _dbProvider.findImagePath(image.illustId, image.part);
        if (filePath == null) {
          // 文件不存在，删除记录
          await _dbProvider.deleteImage(image.illustId, image.part);
        } else {
          hasValidImage = true;
        }
      }

      // 如果没有有效图片，删除插画记录
      if (!hasValidImage) {
        await _dbProvider.deleteIllustByIllustId(illust.illustId);
      }
    }

    await refreshCount();
  }

  Future<LocalImageInfo?> getLocalImageInfoByUrl(String url) =>
      _dbProvider.getLocalImageInfoByUrl(url);

  // ============ 动图转换 ============

  /// 将已下载的动图序列帧转换为WebP动图
  /// 
  /// 转换流程：
  /// 1. 检查是否为动图且已下载序列帧
  /// 2. 调用WebPEncoder进行转换
  /// 3. 删除序列帧文件和数据库记录（保留part=0预览图）
  /// 4. 添加WebP动图记录（part=-1）
  /// 
  /// 返回转换后的WebP文件路径，失败返回null
  Future<String?> convertUgoiraToWebP(int illustId, {int quality = 80}) async {
    // 检查平台支持
    if (!WebPEncoder.isSupported) {
      Log.e('convertUgoiraToWebP: 当前平台不支持WebP转换');
      return null;
    }

    // 1. 获取插画信息
    final illust = await _dbProvider.getIllustByIllustId(illustId);
    if (illust == null) {
      Log.e('convertUgoiraToWebP: 未找到插画记录 $illustId');
      return null;
    }

    if (!illust.isUgoira) {
      Log.e('convertUgoiraToWebP: 不是动图类型 $illustId');
      return null;
    }

    // 2. 检查是否已有WebP动图（part=-1）
    final existingWebP = await _dbProvider.getImage(illustId, -1);
    if (existingWebP != null) {
      final webpPath = await _dbProvider.findImagePath(illustId, -1);
      if (webpPath != null && await File(webpPath).exists()) {
        Log.d('convertUgoiraToWebP: 已存在WebP动图 $webpPath');
        return webpPath;
      }
    }

    // 3. 获取元数据和帧延迟
    final metadata = illust.getUgoiraMetadata();
    if (metadata == null || metadata.frames.isEmpty) {
      Log.e('convertUgoiraToWebP: 无法获取动图元数据 $illustId, ${illust.ugoiraMetadataJson}');
      return null;
    }

    final delays = metadata.frames.map((f) => f.delay).toList();

    // 4. 获取序列帧目录
    final frameDir = Directory(_dbProvider.getUgoiraFrameDirPath(illust.relativePath));
    if (!await frameDir.exists()) {
      Log.e('convertUgoiraToWebP: 序列帧目录不存在 ${frameDir.path}');
      return null;
    }

    // 5. 构建输出路径
    final outputPath = path.join(
      _dbProvider.getIllustAbsolutePath(illust.relativePath),
      '$illustId.webp',
    );

    // 6. 调用WebPEncoder进行转换
    Log.d('convertUgoiraToWebP: 开始转换 $illustId');
    final result = await WebPEncoder.encodeFromDirectory(
      framesDir: frameDir.path,
      delays: delays,
      outputPath: outputPath,
      quality: quality,
    );

    if (result == null) {
      Log.e('convertUgoiraToWebP: 转换失败 $illustId');
      return null;
    }

    // 7. 获取WebP文件信息，尺寸从第一帧获取
    final webpFile = File(result);
    final webpFileSize = await webpFile.length();
    
    // 从第一帧图片获取尺寸（动图所有帧尺寸相同）
    // 获取WebP尺寸
    final size = await getImageSize(result);
    final webpWidth = size?.width.toInt();
    final webpHeight = size?.height.toInt();
    if (size != null) {
      Log.d('convertUgoiraToWebP: WebP尺寸 ${webpWidth}x$webpHeight');
    }

    // 8. 使用dbProvider进行数据库操作
    await _dbProvider.replaceUgoiraFramesWithWebP(
      illustId: illustId,
      relativePath: illust.relativePath,
      fileSize: webpFileSize.toInt(),
      width: webpWidth,
      height: webpHeight,
    );

    // 9. 删除序列帧文件（保留目录，因为可能还有其他文件）
    try {
      final entities = await frameDir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          await entity.delete();
        }
      }
      // 尝试删除空目录
      if ((await frameDir.list().toList()).isEmpty) {
        await frameDir.delete();
      }
    } catch (e) {
      Log.w('convertUgoiraToWebP: 清理序列帧文件失败: $e');
    }

    Log.d('convertUgoiraToWebP: 转换完成 $illustId -> $result');

    // 10. 通知状态更新
    await notifyIllustDownloadStatus(illustId);

    return result;
  }

  /// 检查动图是否已转换为WebP
  Future<bool> hasUgoiraWebP(int illustId) async {
    final webpImage = await _dbProvider.getImage(illustId, -1);
    if (webpImage == null) return false;
    
    final webpPath = await _dbProvider.findImagePath(illustId, -1);
    return webpPath != null && await File(webpPath).exists();
  }

  /// 获取动图WebP文件路径（如果存在）
  Future<String?> getUgoiraWebPPath(int illustId) async {
    final hasWebP = await hasUgoiraWebP(illustId);
    if (!hasWebP) return null;
    return await _dbProvider.findImagePath(illustId, -1);
  }
  Future<void> updateTagExampleIllusts(int tagId, List<int> illustIds) async {
    await _dbProvider.updateTagExampleIllusts(tagId, illustIds);
  }

  /// 更新插画收藏/优先级
  Future<void> updateIllustBookmark(int illustId, int bookmark) async {
    await _dbProvider.updateIllustBookmark(illustId, bookmark);
  }
  // ============ 同步功能 ============

  /// 分页获取在线收藏
  /// [userId] 用户ID
  /// [restrict] public 或 private
  /// [nextUrl] 下一页链接，如果为null则请求第一页
  /// 返回：{'illusts': List<Illusts>, 'nextUrl': String?}
  Future<Map<String, dynamic>> fetchOnlineBookmarksPage(
      int userId, String restrict, {String? nextUrl}) async {
    final result = <String, dynamic>{
      'illusts': <Illusts>[],
      'nextUrl': null,
    };

    try {
      final Response res;
      if (nextUrl != null && nextUrl.isNotEmpty) {
         res = await apiClient.getNext(nextUrl);
      } else {
         res = await apiClient.getBookmarksIllustsOffset(
          userId,
          restrict,
          null, // tag
          0,
        );
      }

      if (res.data != null) {
        final illustsList = res.data['illusts'] as List?;
        if (illustsList != null) {
          result['illusts'] =
              illustsList.map((e) => Illusts.fromJson(e)).toList();
        }

        final nextUrl = res.data['next_url'] as String?;
        if (nextUrl != null) {
            result['nextUrl'] = nextUrl;
        }
      }
    } catch (e) {
      Log.e('Failed to fetch bookmarks page', error: e);
      rethrow;
    }

    return result;
  }
}
