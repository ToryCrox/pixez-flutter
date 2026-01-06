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
import 'package:archive/archive.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pixez/er/lprinter.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/ugoira_metadata_response.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/saf_plugin.dart';
import 'package:pixez/store/download_store.dart';
import 'package:pixez/utils/ugoira_downloader.dart';

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
      LPrinter.d('动图 $id 开始下载，清空当前帧列表');
      // 下载开始时，清空当前帧列表，避免使用即将被删除的临时文件
      drawPool = [];
      // 如果当前不是进度状态，设置为进度状态
      if (this.status != UgoiraStatus.progress) {
        this.status = UgoiraStatus.progress;
      }
    } else if (status.status == DownloadTaskStatus.completed) {
      LPrinter.d('动图 $id 下载完成，重新加载本地文件');
      // 下载完成时，重新从已下载目录加载
      _loadFromDownloadDirectory();
    } else if (status.status == DownloadTaskStatus.failed) {
      LPrinter.d('动图 $id 下载失败');
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

  List<FileSystemEntity> drawPool = [];
  UgoiraMetadataResponse? ugoiraMetadataResponse;

  export() async {
    try {
      // ZIP 文件已在统一的下载目录中
      String fullPath = downloadStore.getUgoiraZipPath(id);
      File fullPathFile = File(fullPath);
      if (fullPathFile.existsSync()) {
        final data = fullPathFile.readAsBytesSync();
        if (Platform.isAndroid) {
          try {
            String? uriString =
                await SAFPlugin.createFile("${id}.zip", "application/zip");
            uriString!;
            await SAFPlugin.writeUri(uriString, data);
            BotToast.showText(text: "export success");
            return;
          } catch (e) {}
        }
        Directory? directory = await getExternalStorageDirectory();
        Directory zipFolder = Directory("${directory!.path}/ugoira_zip/");
        if (!zipFolder.existsSync()) {
          zipFolder.createSync(recursive: true);
        }
        File targetFile = File("${zipFolder.path}/${id}.zip");
        fullPathFile.copySync(targetFile.path);
        BotToast.showText(text: "export ${targetFile.path} success");
      }
    } catch (e) {
      LPrinter.d(e);
    }
  }

  @action
  unZip() async {
    String fullPath = downloadStore.getUgoiraZipPath(id);
    File fullPathFile = File(fullPath);
    try {
      // Read the Zip file from disk.
      final bytes = fullPathFile.readAsBytesSync();

      // Decode the Zip file
      final archive = ZipDecoder().decodeBytes(bytes);

      // Extract the contents of the Zip archive to disk.
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          File('${downloadStore.getUgoiraExtractPath(id)}/' + filename)
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory('${downloadStore.getUgoiraExtractPath(id)}/' + filename)..create(recursive: true);
        }
      }
      Directory zipDirectory = Directory(downloadStore.getUgoiraExtractPath(id));
      var listSync = zipDirectory.listSync();
      listSync.sort((l, r) => l.path.compareTo(r.path));
      drawPool = listSync;
      status = UgoiraStatus.play;
    } catch (e) {
      if (fullPathFile.existsSync()) fullPathFile.deleteSync();
      final extractPath = downloadStore.getUgoiraExtractPath(id);
      if (Directory(extractPath).existsSync()) {
        Directory(extractPath).deleteSync(recursive: true);
      }
      status = UgoiraStatus.pre;
    }
  }

  @action
  downloadAndUnzip() async {
    status = UgoiraStatus.progress;

    // 1. 首先检查是否已经下载到统一下载目录
    final isDownloaded = await downloadStore.dbProvider.isIllustDownloaded(id);
    LPrinter.d('动图 $id 下载状态检查: isDownloaded=$isDownloaded');
    if (isDownloaded) {
      await _loadFromDownloadDirectory();
      return;
    }

    // 2. 如果没有下载，使用临时下载流程
    LPrinter.d('动图 $id 未下载，使用临时下载流程');
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
        LPrinter.d('动图 $id 数据库记录不存在，回退到下载流程');
        await _fetchAndUnzip();
        return;
      }

      // 解析 UgoiraMetadata
      final metadata = downloadedIllust.getUgoiraMetadata();
      if (metadata == null || metadata.frames.isEmpty) {
        // 元数据损坏，回退到下载流程
        LPrinter.d('动图 $id 元数据为空，回退到下载流程');
        await _fetchAndUnzip();
        return;
      }

      ugoiraMetadataResponse = UgoiraMetadataResponse(ugoiraMetadata: metadata);

      // 使用 dbProvider 的方法获取动图帧目录
      final frameDirPath = downloadStore.dbProvider.getUgoiraFrameDirPath(downloadedIllust.relativePath);
      LPrinter.d('动图 $id 帧目录路径: $frameDirPath, relativePath: ${downloadedIllust.relativePath}');
      final frameDir = Directory(frameDirPath);

      if (!await frameDir.exists()) {
        // 目录不存在，回退到下载流程
        LPrinter.d('动图 $id 帧目录不存在: ${frameDir.path}，回退到下载流程');
        await _fetchAndUnzip();
        return;
      }

      // 加载目录中的所有图片文件（兼容文件名变化：压缩、重命名、修改后缀等）
      final entities = await frameDir.list().toList();
      final frameFiles = <File>[];

      LPrinter.d('动图 $id 扫描帧目录，找到 ${entities.length} 个文件');

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

      LPrinter.d('动图 $id 过滤后有 ${frameFiles.length} 个图片文件');

      if (frameFiles.isEmpty) {
        // 帧文件不存在，回退到下载流程
        LPrinter.d('动图 $id 没有找到帧文件，回退到下载流程');
        await _fetchAndUnzip();
        return;
      }

      // 按文件名排序（假设文件名包含序号信息）
      frameFiles.sort((a, b) => a.path.compareTo(b.path));

      // 验证文件数量（仅警告，不阻塞播放）
      if (frameFiles.length != metadata.frames.length) {
        LPrinter.d(
          '动图 $id 帧文件数量不匹配: 期望 ${metadata.frames.length}, 实际 ${frameFiles.length}'
        );
        // 继续播放，让用户体验实际可用的帧
      }

      LPrinter.d('动图 $id 成功加载 ${frameFiles.length} 个帧文件');
      drawPool = frameFiles;
      status = UgoiraStatus.play;
    } catch (e) {
      LPrinter.d('动图 $id 加载本地动图失败: $e');
      // 加载失败，回退到下载流程
      await _fetchAndUnzip();
    }
  }

  /// 获取元数据并解压序列帧（用于在线播放）
  @action
  Future<void> _fetchAndUnzip() async {
    final downloader = UgoiraDownloader(
      apiClient: apiClient,
      downloadPath: downloadStore.downloadPath,
    );

    try {
      // 使用统一的下载方法获取元数据和帧文件
      final result = await downloader.fetchMetadataAndExtractFrames(id);
      ugoiraMetadataResponse = result.metadata;
      drawPool = result.frameFiles;
      status = UgoiraStatus.play;
    } catch (e) {
      LPrinter.d('下载动图失败: $e');
      // 清理临时解压目录（ZIP 由 pixivCacheManager 管理）
      await downloader.cleanupTempExtractDir(id);
      status = UgoiraStatus.pre;
    }
  }
}
