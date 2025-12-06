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
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as path hide context;
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/er/toaster.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/illust.dart';

part 'download_store.g.dart';

// 下载进度信息
class DownloadProgress {
  final int illustId;
  final int part;
  final int received;
  final int total;
  final DownloadTaskStatus status;
  final String? error;

  DownloadProgress({
    required this.illustId,
    required this.part,
    required this.received,
    required this.total,
    required this.status,
    this.error,
  });

  double get progress => total > 0 ? received / total : 0;
}

enum DownloadTaskStatus {
  pending,
  downloading,
  completed,
  failed;
}

// 下载任务
class DownloadTask {
  final Illusts illusts;
  final int part;
  final String url;
  DownloadTaskStatus status;
  int received;
  int total;
  String? error;

  DownloadTask({
    required this.illusts,
    required this.part,
    required this.url,
    this.status = DownloadTaskStatus.pending,
    this.received = 0,
    this.total = 0,
    this.error,
  });

  String get taskKey => '${illusts.id}_$part';

  PendingDownload toPendingDownload() {
    return PendingDownload(
      id: taskKey,
      illustJson: jsonEncode(illusts),
      part: part,
      url: url,
      status: status.name,
      createTime: DateTime.now().millisecondsSinceEpoch,
    );
  }

  DownloadTask fromPendingDownload(PendingDownload pendingDownload) {
    return DownloadTask(
      illusts: Illusts.fromJson(jsonDecode(pendingDownload.illustJson)),
      part: pendingDownload.part,
      url: pendingDownload.url,
      status: DownloadTaskStatus.values
              .firstWhereOrNull((e) => e.name == pendingDownload.status) ??
          DownloadTaskStatus.pending,
      received: 0,
      total: 0,
      error: null,
    );
  }
}

const kImageExtensions = ['.webp', '.jpg', '.png', '.gif', '.jpeg'];

class DownloadStore = _DownloadStoreBase with _$DownloadStore;

abstract class _DownloadStoreBase with Store {
  final DownloadDatabaseProvider _dbProvider = DownloadDatabaseProvider();

  // 暴露数据库 provider 供 downloader 使用
  DownloadDatabaseProvider get dbProvider => _dbProvider;

  // 下载进度流
  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();

  Stream<DownloadProgress> get progressStream => _progressController.stream;

  // 正在下载的任务
  @observable
  ObservableMap<String, DownloadTask> downloadingTasks =
      ObservableMap<String, DownloadTask>();

  // 下载队列
  final Queue<DownloadTask> _pendingQueue = Queue<DownloadTask>();

  // 正在运行的下载
  final Set<String> _runningUrls = {};

  // 最大并发数
  int _maxConcurrent = 3;

  // 下载目录
  String? _downloadPath;

  String get downloadPath => _downloadPath ?? '';

  bool get isInitialized => _downloadPath != null;

  @observable
  int totalDownloaded = 0;

  // 初始化
  Future<void> init(String downloadPath, {int maxConcurrent = 3}) async {
    _downloadPath = downloadPath;
    _maxConcurrent = maxConcurrent;
    Log.d('DownloadStore downloadPath: $downloadPath');
    await _dbProvider.open(downloadPath);
    await refreshCount();
  }

  @action
  Future<void> refreshCount() async {
    totalDownloaded = await _dbProvider.getIllustCount();
  }

  void dispose() {
    _progressController.close();
  }

  // ============ 查询接口 ============

  Future<bool> isIllustDownloaded(int illustId) async {
    return await _dbProvider.isIllustDownloaded(illustId);
  }

  Future<DownloadedIllust?> getDownloadedIllust(int illustId) async {
    return await _dbProvider.getIllustByIllustId(illustId);
  }

  Future<String?> getLocalImagePath(int illustId, int part) async {
    return await _dbProvider.findImagePath(illustId, part);
  }

  Future<List<DownloadedIllust>> getAllDownloaded({
    int? limit,
    int? offset,
    bool desc = true,
  }) async {
    return await _dbProvider.getAllIllusts(
      limit: limit,
      offset: offset,
      desc: desc,
    );
  }

  Future<List<DownloadedIllust>> getDownloadedByUser(
    int userId, {
    int? limit,
    int? offset,
  }) async {
    return await _dbProvider.getIllustsByUserId(userId,
        limit: limit, offset: offset);
  }

  Future<List<DownloadedIllust>> searchDownloadedByTag(
    String tag, {
    int? limit,
    int? offset,
  }) async {
    return await _dbProvider.searchIllustsByTag(tag,
        limit: limit, offset: offset);
  }

  Future<List<DownloadedIllust>> searchDownloaded(
    String keyword, {
    int? limit,
    int? offset,
  }) async {
    return await _dbProvider.searchIllusts(keyword,
        limit: limit, offset: offset);
  }

  Future<List<Map<String, dynamic>>> getDistinctUsers() async {
    return await _dbProvider.getDistinctUsers();
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

  // ============ 下载接口 ============

  @action
  Future<void> downloadIllust(Illusts illusts, {int? part}) async {
    if (!isInitialized) {
      throw Exception('DownloadStore not initialized');
    }

    Toaster.showText('开始下载插画 ${illusts.id}');
    if (part != null) {
      // 下载单页
      await _addDownloadTask(illusts, part);
    } else {
      // 下载所有页
      if (illusts.pageCount == 1) {
        await _addDownloadTask(illusts, 0);
      } else {
        for (int i = 0; i < illusts.metaPages.length; i++) {
          await _addDownloadTask(illusts, i);
        }
      }
    }
  }

  String _getDownloadTaskFileName(DownloadTask task) {
    final illusts = task.illusts;
    final part = task.part;
    final relativePath = DownloadDatabaseProvider.buildRelativePath(illusts);
    final fileName = DownloadDatabaseProvider.buildFileName(illusts.id, part);
    final extension = path.extension(task.url);
    return path.join(_downloadPath!, relativePath, '$fileName$extension');
  }

  Future<String?> _tryFindExistingImageFile(DownloadTask task) async {
    final relativePath =
        DownloadDatabaseProvider.buildRelativePath(task.illusts);
    final fileName =
        DownloadDatabaseProvider.buildFileName(task.illusts.id, task.part);
    for (final ext in kImageExtensions) {
      final fullPath = path.join(_downloadPath!, relativePath, '$fileName$ext');
      if (await File(fullPath).exists()) {
        return fullPath;
      }
    }
    return null;
  }

  Future<void> _addDownloadTask(Illusts illusts, int part) async {
    final taskKey = '${illusts.id}_$part';

    // 检查是否已在下载队列中
    if (downloadingTasks.containsKey(taskKey)) {
      final task = downloadingTasks[taskKey];
      Log.d(
          'DownloadStore task $taskKey already exists, ${task?.error}, ${task?.status}');
      return;
    }

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
    );

    // 检查目标文件是否已存在
    final targetPath = await _tryFindExistingImageFile(task);

    if (targetPath != null) {
      // 文件已存在，直接记录到数据库
      await _recordDownload(illusts, part, url, targetPath);
      return;
    }

    downloadingTasks[taskKey] = task;
    _pendingQueue.add(task);
    // 添加到pending数据库中
    await _dbProvider.insertPendingDownload(task.toPendingDownload());
    Log.d("添加下载任务: $taskKey");

    // 尝试处理队列
    _processQueue();
  }

  void _processQueue() {
    while (_pendingQueue.isNotEmpty && _runningUrls.length < _maxConcurrent) {
      final task = _pendingQueue.removeFirst();
      if (!downloadingTasks.containsKey(task.taskKey)) {
        // 任务已被取消
        continue;
      }
      _runningUrls.add(task.url);
      _startDownload(task);
    }
  }

  Future<void> _startDownload(DownloadTask task) async {
    task.status = DownloadTaskStatus.downloading;
    _notifyProgress(task);

    try {
      final targetPath = _getDownloadTaskFileName(task);
      final targetFile = File(targetPath);
      final targetDir = targetFile.parent;

      // 确保目标目录存在
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      // 1. 尝试从缓存获取
      final cached = await pixivCacheManager.getFileFromCache(task.url);
      if (cached != null && await cached.file.exists()) {
        // 从缓存复制到目标目录
        await cached.file.copy(targetPath);
        await _onDownloadSuccess(task, targetPath);
        return;
      }

      // 2. 使用pixivCacheManager下载
      final fileInfo = await pixivCacheManager.downloadFile(
        task.url,
        authHeaders: Hoster.header(url: task.url),
      );

      // 3. 复制到目标目录
      await fileInfo.file.copy(targetPath);

      // 5. 清理任务
      await _onDownloadSuccess(task, targetPath);
    } catch (e) {
      _onDownloadFailed(task, e.toString());
    }
  }

  Future<void> _onDownloadSuccess(DownloadTask task, String targetPath) async {
    task.status = DownloadTaskStatus.completed;
    await _recordDownload(task.illusts, task.part, task.url, targetPath);
    downloadingTasks.remove(task.taskKey);
    _notifyProgress(task);
    _runningUrls.remove(task.url);
    _dbProvider.updatePendingDownloadStatus(task.taskKey, task.status.name);
    _processQueue();
    await refreshCount();
  }

  void _onDownloadFailed(DownloadTask task, String error) {
    task.status = DownloadTaskStatus.failed;
    task.error = error;
    _notifyProgress(task);
    _runningUrls.remove(task.url);
    _dbProvider.updatePendingDownloadStatus(task.taskKey, task.status.name);
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

  // 由 Downloader 调用，报告完成
  @action
  Future<void> onDownloadComplete(
    String taskKey,
    String filePath,
    int fileSize,
  ) async {
    final task = downloadingTasks[taskKey];
    if (task == null) return;

    task.status = DownloadTaskStatus.completed;
    _notifyProgress(task);

    // 记录到数据库
    await _recordDownload(task.illusts, task.part, task.url, filePath);

    // 清理
    downloadingTasks.remove(taskKey);
    _runningUrls.remove(task.url);

    await refreshCount();

    // 继续处理队列
    _processQueue();
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
    _runningUrls.remove(task.url);
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
      _runningUrls.remove(task.url);
      _pendingQueue.removeWhere((t) => t.taskKey == taskKey);
      downloadingTasks.remove(taskKey);
      _dbProvider.deletePendingDownload(taskKey);
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

  void _notifyProgress(DownloadTask task) {
    _progressController.add(DownloadProgress(
      illustId: task.illusts.id,
      part: task.part,
      received: task.received,
      total: task.total,
      status: task.status,
      error: task.error,
    ));
  }

  // 记录下载完成
  Future<void> _recordDownload(
    Illusts illusts,
    int part,
    String url,
    String filePath,
  ) async {
    final relativePath = DownloadDatabaseProvider.buildRelativePath(illusts);
    final fileName = DownloadDatabaseProvider.buildFileName(illusts.id, part);
    final extension = url.contains('.png') ? '.png' : '.jpg';

    // 检查是否已有该插画记录
    final existingIllust = await _dbProvider.getIllustByIllustId(illusts.id);
    if (existingIllust == null) {
      // 创建插画记录
      final downloadedIllust =
          DownloadedIllust.fromIllusts(illusts, relativePath);
      await _dbProvider.insertIllust(downloadedIllust);
    }

    // 获取文件大小
    int fileSize = 0;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        fileSize = await file.length();
      }
    } catch (_) {}

    // 创建图片记录
    final downloadedImage = DownloadedImage(
      illustId: illusts.id,
      part: part,
      fileName: fileName,
      extension: extension,
      fileSize: fileSize,
      originalUrl: url,
      relativePath: relativePath,
    );
    await _dbProvider.insertImage(downloadedImage);
  }

  // ============ 删除接口 ============

  @action
  Future<void> deleteDownloadedIllust(int illustId) async {
    // 获取插画信息
    final illust = await _dbProvider.getIllustByIllustId(illustId);
    if (illust == null) return;

    // 获取所有图片记录
    final images = await _dbProvider.getImagesByIllustId(illustId);

    // 删除文件
    for (final image in images) {
      final filePath = path.join(
        _downloadPath!,
        image.relativePath,
        image.getFullFileName(),
      );
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e, s) {
        Log.e('删除文件失败: $filePath', stackTrace: s);
      }
    }

    // 尝试删除空目录
    final illustDir = path.join(_downloadPath!, illust.relativePath);
    try {
      final dir = Directory(illustDir);
      if (await dir.exists()) {
        final contents = await dir.list().toList();
        if (contents.isEmpty) {
          await dir.delete();
        }
      }
    } catch (e, s) {
      Log.e('删除目录失败: ${illustDir}', stackTrace: s);
    }

    // 从数据库删除
    await _dbProvider.deleteIllustByIllustId(illustId);

    await refreshCount();
  }

  // ============ 文件存在性检查 ============

  /// 检查插画的所有图片是否都已下载
  Future<bool> isIllustFullyDownloaded(int illustId) async {
    final illust = await _dbProvider.getIllustByIllustId(illustId);
    if (illust == null) return false;

    final downloadedCount = await _dbProvider.getDownloadedImageCount(illustId);
    return downloadedCount >= illust.pageCount;
  }

  /// 获取插画已下载的页数
  Future<int> getDownloadedPageCount(int illustId) async {
    return await _dbProvider.getDownloadedImageCount(illustId);
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
}
