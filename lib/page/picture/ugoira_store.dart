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

import 'dart:async';
import 'dart:io';
import 'package:bot_toast/bot_toast.dart';
import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as path;
import 'package:pixez/custom/log.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/ugoira_metadata_response.dart';
import 'package:pixez/store/download_store.dart';
import 'package:pixez/utils/ugoira_downloader.dart';
import 'package:pixez/custom/pixiv_url_util.dart';
import 'package:pixez/custom/type_util.dart';

part 'ugoira_store.g.dart';

enum UgoiraStatus { pre, progress, play }

class UgoiraStore = _UgoiraStoreBase with _$UgoiraStore;

abstract class _UgoiraStoreBase with Store {
  final int id;
  StreamSubscription<IllustDownloadStatus>? _downloadStatusSubscription;

  _UgoiraStoreBase(this.id) {
    _initDownloadStatusListener();
  }

  /// 销毁 Store
  void dispose() {
    _downloadStatusSubscription?.cancel();
    _downloadStatusSubscription = null;
  }

  /// 初始化下载状态监听
  void _initDownloadStatusListener() {
    _downloadStatusSubscription = downloadStore.illustDownloadStatusStream
        .listen((status) {
      if (status.illusts.illustId == id) {
        _onDownloadStatusChanged(status);
      }
    });
  }

  /// 处理下载状态变化
  @action
  void _onDownloadStatusChanged(IllustDownloadStatus status) {
    if (status.status == DownloadTaskStatus.downloading ||
        status.status == DownloadTaskStatus.pending) {
      Log.d(() =>'动图 $id 开始下载，清空当前帧列表');
      // 下载开始时，清空当前帧列表，避免使用即将被删除的临时文件
      drawPool = [];
      // 如果当前不是进度状态，设置为进度状态
      if (this.status != UgoiraStatus.progress) {
        this.status = UgoiraStatus.progress;
      }
    } else if (status.status == DownloadTaskStatus.completed) {
      Log.d(() =>'动图 $id 下载完成，重新加载本地文件');
      // 下载完成时，重新从已下载目录加载
      _loadFromDownloadDirectory();
    } else if (status.status == DownloadTaskStatus.failed) {
      Log.d(() =>'动图 $id 下载失败');
      // 下载失败时，恢复到初始状态
      this.status = UgoiraStatus.pre;
    }
  }

  @observable
  UgoiraStatus? status;
  @observable
  int count = 0;
  @observable
  int total = 1;

  /// WebP动图文件路径（如果已转换）
  @observable
  String? webpPath;

  /// WebP动图宽度
  @observable
  int? webpWidth;

  /// WebP动图高度
  @observable
  int? webpHeight;

  /// 是否正在使用WebP播放
  bool get isPlayingWebP => webpPath != null && webpPath!.isNotEmpty;

  List<FileSystemEntity> drawPool = [];

  @observable
  UgoiraMetadataResponse? ugoiraMetadataResponse;

  export() async {

  }

  @action
  unZip() async {

  }

  @action
  downloadAndUnzip() async {
    status = UgoiraStatus.progress;

    // 1. 首先检查是否已经下载到统一下载目录
    final isDownloaded = await downloadStore.dbProvider.isIllustDownloaded(id);
    Log.d(() => '动图 $id 下载状态检查: isDownloaded=$isDownloaded');
    if (isDownloaded) {
      await _loadFromDownloadDirectory();
      return;
    }

    // 2. 如果没有下载，使用临时下载流程
    Log.d(() => '动图 $id 未下载，使用临时下载流程');
    await _fetchAndUnzip();
  }

  /// 从已下载的目录加载动图
  @action
  Future<void> _loadFromDownloadDirectory() async {
    try {
      // 从数据库获取已下载的插画信息
      final downloadedIllust = await downloadStore.dbProvider.getIllustByIllustId(id);
      if (downloadedIllust == null) {
        // 数据库记录不存在，回退到下载流程
        Log.d(() =>'动图 $id 数据库记录不存在，回退到下载流程');
        await _fetchAndUnzip();
        return;
      }

      // 解析 UgoiraMetadata
      var metadata = downloadedIllust.getUgoiraMetadata();
      if (metadata == null || metadata.frames.isEmpty) {
        // 元数据损坏，尝试从网络获取并更新到数据库
        Log.w('动图 $id 元数据为空，尝试从网络获取');
        try {
          final response = await ugoiraDownloader.fetchMetadata(id);
          metadata = response.ugoiraMetadata;
          
          // 更新到数据库
          final metadataJson = PixivUrlUtil.compressPxUrl(
            TypeUtil.parseJsonString(metadata.toJson())
          );
          await downloadStore.dbProvider.updateUgoiraMetadata(id, metadataJson);
          Log.d('动图 $id 元数据已从网络获取并更新到数据库');
        } catch (e) {
          // 获取失败，回退到下载流程
          Log.e('动图 $id 获取元数据失败: $e，回退到下载流程');
          BotToast.showText(text: '动图 $id 元数据获取失败，回退到下载流程');
          await _fetchAndUnzip();
          return;
        }
      }

      ugoiraMetadataResponse = UgoiraMetadataResponse(ugoiraMetadata: metadata);

      // 优先检测是否存在WebP动图（part=-1）
      final webpImage = await downloadStore.dbProvider.getWebPImage(id);
      if (webpImage != null) {
        final existingWebPPath = await downloadStore.getUgoiraWebPPath(id);
        if (existingWebPPath != null && await File(existingWebPPath).exists()) {
          Log.d('动图 $id 发现已转换的WebP文件: $existingWebPPath');
          webpPath = existingWebPPath;
          webpWidth = webpImage.width;
          webpHeight = webpImage.height;
          status = UgoiraStatus.play;
          return;
        }
      }

      // WebP不存在，使用序列帧播放

      // 使用 dbProvider 的方法获取动图帧目录
      final frameDirPath = downloadStore.dbProvider.getUgoiraFrameDirPath(downloadedIllust.relativePath);
      Log.d('动图 $id 帧目录路径: $frameDirPath, relativePath: ${downloadedIllust.relativePath}');
      final frameDir = Directory(frameDirPath);

      if (!await frameDir.exists()) {
        // 目录不存在，回退到下载流程
        Log.d('动图 $id 帧目录不存在: ${frameDir.path}，回退到下载流程');
        await _fetchAndUnzip();
        return;
      }

      // 加载目录中的所有图片文件（兼容文件名变化：压缩、重命名、修改后缀等）
      final entities = await frameDir.list().toList();
      final frameFiles = <File>[];

      Log.d('动图 $id 扫描帧目录，找到 ${entities.length} 个文件');

      // 支持的图片文件扩展名
      const supportedExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];

      for (final entity in entities) {
        if (entity is File) {
          final extension = path.extension(entity.path).toLowerCase();
          // 只接受支持的图片文件
          if (supportedExtensions.contains(extension)) {
            frameFiles.add(entity);
          }
        }
      }

      Log.d('动图 $id 过滤后有 ${frameFiles.length} 个图片文件');

      if (frameFiles.isEmpty) {
        // 帧文件不存在，回退到下载流程
        Log.d('动图 $id 没有找到帧文件，回退到下载流程');
        await _fetchAndUnzip();
        return;
      }

      // 按文件名排序（假设文件名包含序号信息）
      frameFiles.sort((a, b) => a.path.compareTo(b.path));

      // 验证文件数量（仅警告，不阻塞播放）
      if (frameFiles.length != metadata.frames.length) {
        Log.d(
          '动图 $id 帧文件数量不匹配: 期望 ${metadata.frames.length}, 实际 ${frameFiles.length}'
        );
        // 继续播放，让用户体验实际可用的帧
      }

      Log.d('动图 $id 成功加载 ${frameFiles.length} 个帧文件');
      drawPool = frameFiles;
      status = UgoiraStatus.play;
    } catch (e) {
      Log.d(() =>'动图 $id 加载本地动图失败: $e');
      // 加载失败，回退到下载流程
      await _fetchAndUnzip();
    }
  }

  /// 获取元数据并解压序列帧（用于在线播放）
  @action
  Future<void> _fetchAndUnzip() async {

    try {
      // 使用统一的下载方法获取元数据和帧文件
      final result = await ugoiraDownloader.fetchMetadataAndExtractFrames(id);
      Log.d(() => '动图 $id 下载元数据和解压序列帧成功: ${result.metadata}, ${result.frameFiles}');
      ugoiraMetadataResponse = result.metadata;
      drawPool = result.frameFiles;
      status = UgoiraStatus.play;
    } catch (e) {
      Log.d(() =>'下载动图失败: $e');
      // 清理临时解压目录（ZIP 由 pixivCacheManager 管理）
      await ugoiraDownloader.cleanupTempExtractDir(id);
      status = UgoiraStatus.pre;
    }
  }
}
