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

import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/models/ugoira_metadata_response.dart';
import 'package:pixez/network/api_client.dart';

/// Ugoira 下载结果
///
/// 包含元数据和解压后的序列帧文件
class UgoiraDownloadResult {
  final UgoiraMetadataResponse metadata;
  final List<File> frameFiles;

  UgoiraDownloadResult({
    required this.metadata,
    required this.frameFiles,
  });
}

/// Ugoira 下载工具类
///
/// 提供动图下载、解压的公共方法，供 download_store 和 ugoira_store 共用
class UgoiraDownloader {
  final ApiClient apiClient;
  final String downloadPath;

  UgoiraDownloader({
    required this.apiClient,
    required this.downloadPath,
  });

  /// 获取动图元数据、下载并解压序列帧
  ///
  /// 封装了获取元数据、下载 ZIP、解压的完整流程
  /// 如果临时目录已有完整的帧文件，则直接使用，避免重复下载解压
  /// 解压完成后 ZIP 文件由 pixivCacheManager 管理，不再手动删除
  ///
  /// 返回 [UgoiraDownloadResult] 包含元数据和解压后的帧文件列表
  Future<UgoiraDownloadResult> fetchMetadataAndExtractFrames(
    int illustId,
  ) async {
    // 1. 获取元数据
    final metadata = await fetchMetadata(illustId);

    // 2. 清理临时目录（确保从干净状态开始）
    final extractDir = Directory(getTempExtractPath(illustId));
    if (await extractDir.exists()) {
      await extractDir.delete(recursive: true);
    }

    // 3. 下载并解压到临时目录
    final zipUrl = metadata.ugoiraMetadata.zipUrls.medium;
    final zipFile = await pixivCacheManager.getSingleFile(
      zipUrl,
      headers: Hoster.header(url: zipUrl),
    );

    // 4. 创建临时目录
    await extractDir.create(recursive: true);

    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final frameFiles = <File>[];
    for (final file in archive) {
      final filePath = path.join(extractDir.path, file.name);
      if (file.isFile) {
        final outputFile = File(filePath);
        await outputFile.create(recursive: true);
        await outputFile.writeAsBytes(file.content as List<int>);
        frameFiles.add(outputFile);
      }
    }

    // 5. 按文件名排序
    frameFiles.sort((a, b) => a.path.compareTo(b.path));

    return UgoiraDownloadResult(
      metadata: metadata,
      frameFiles: frameFiles,
    );
  }

  /// 获取动图元数据
  Future<UgoiraMetadataResponse> fetchMetadata(int illustId) async {
    return await apiClient.getUgoiraMetadata(illustId);
  }

  /// 删除临时解压目录
  ///
  /// ZIP 文件由 pixivCacheManager 管理，无需手动删除
  Future<void> cleanupTempExtractDir(int illustId) async {
    final extractPath = getTempExtractPath(illustId);
    if (await Directory(extractPath).exists()) {
      await Directory(extractPath).delete(recursive: true);
    }
  }

  /// 获取临时解压目录路径
  String getTempExtractPath(int illustId) {
    return path.join(downloadPath, 'ugoira', '$illustId');
  }

  /// 检查临时解压目录是否存在
  Future<bool> hasTempExtract(int illustId) async {
    return await Directory(getTempExtractPath(illustId)).exists();
  }

  /// 获取临时解压目录中的所有文件
  Future<List<File>> getExtractedFiles(int illustId) async {
    final extractPath = getTempExtractPath(illustId);
    final dir = Directory(extractPath);
    if (!await dir.exists()) {
      return [];
    }

    final entities = await dir.list().toList();
    final files = <File>[];
    for (final entity in entities) {
      if (entity is File) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }
}
