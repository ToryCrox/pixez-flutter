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
import 'dart:io' as io;
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/ugoira_metadata_response.dart';
import 'package:pixez/network/api_client.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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

  @override
  String toString() {
    return 'UgoiraDownloadResult{metadata: $metadata, frameFiles: $frameFiles}';
  }


}

final ugoiraDownloader = UgoiraDownloader._();

/// Ugoira 下载进度回调
typedef UgoiraProgressCallback = void Function(int received, int total);

/// Ugoira 下载工具类
///
/// 提供动图下载、解压的公共方法，供 download_store 和 ugoira_store 共用
class UgoiraDownloader {

  UgoiraDownloader._();

  /// 获取动图元数据、下载并解压序列帧
  ///
  /// 下载进度回调 [onProgress] 会在下载过程中被调用
  ///
  /// 下载优先级：
  /// 1. 方法二：逐帧下载原始图片（最高质量）-> {id}_frames
  /// 2. 方法一：下载高清 ZIP (1920x1080) -> {id}_original
  /// 3. 现有方法：下载 medium ZIP (600x600) -> {id}_medium
  ///
  /// 返回 [UgoiraDownloadResult] 包含元数据和解压后的帧文件列表
  Future<UgoiraDownloadResult> fetchMetadataAndExtractFrames(
    int illustId, {
    UgoiraProgressCallback? onProgress,
  }) async {
    // 1. 获取元数据
    final metadata = await fetchMetadata(illustId);
    final mediumUrl = metadata.ugoiraMetadata.zipUrls.medium;
    final frames = metadata.ugoiraMetadata.frames;

    // 准备三种方法的目录路径
    final framesDir = Directory(_getMethodPath(illustId, 'frames'));
    final originalDir = Directory(_getMethodPath(illustId, 'original'));
    final mediumDir = Directory(_getMethodPath(illustId, 'medium'));

    List<File>? frameFiles;
    Directory? successDir;

    // 2. 尝试方法二：逐帧下载原始图片
    Log.d(() => 'Ugoira $illustId: 尝试方法二 - 逐帧下载原始图片');
      frameFiles = await _tryDownloadOriginalFrames(
        illustId: illustId,
        mediumUrl: mediumUrl,
        frames: frames,
        extractDir: framesDir,
        onProgress: onProgress,
      );
      if (frameFiles != null) successDir = framesDir;

      // 3. 尝试方法一：下载高清 ZIP
      if (frameFiles == null) {
        Log.d(() => 'Ugoira $illustId: 尝试方法一 - 下载高清 ZIP');
        final originalUrl = getOriginalZipUrl(mediumUrl);
        if (originalUrl != null) {
          frameFiles = await _tryDownloadAndExtractZip(originalUrl, originalDir, onProgress: onProgress);
          if (frameFiles != null) successDir = originalDir;
        }
      }

      // 4. 使用现有方法：下载 medium ZIP
      if (frameFiles == null) {
        Log.d(() => 'Ugoira $illustId: 使用 medium ZIP');
        frameFiles = await _tryDownloadAndExtractZip(mediumUrl, mediumDir, onProgress: onProgress);
        if (frameFiles != null) successDir = mediumDir;
      }

    // 5. 如果全部失败，抛出异常
    if (frameFiles == null || frameFiles.isEmpty) {
      throw Exception('所有下载方法均失败');
    }

    // 6. 清理其他方法的目录
    await _cleanupOtherDirs(successDir!, [framesDir, originalDir, mediumDir]);

    return UgoiraDownloadResult(
      metadata: metadata,
      frameFiles: frameFiles,
    );
  }

  /// 获取指定方法的目录路径
  String _getMethodPath(int illustId, String method) {
    return path.join(downloadStore.dbProvider.ugoiraTempPath, '${illustId}_$method');
  }

  /// 清理其他方法的目录
  Future<void> _cleanupOtherDirs(Directory successDir, List<Directory> allDirs) async {
    for (final dir in allDirs) {
      if (dir.path != successDir.path && await dir.exists()) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// 获取目录中已存在的图片文件
  Future<List<File>> _getExistingImageFiles(Directory dir) async {
    if (!await dir.exists()) {
      return [];
    }
    
    final entities = await dir.list().toList();
    final files = <File>[];
    for (final entity in entities) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        if (ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.gif') {
          files.add(entity);
        }
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// 尝试逐帧下载原始图片（方法二）
  /// 
  /// 返回帧文件列表，如果失败返回 null
  Future<List<File>?> _tryDownloadOriginalFrames({
    required int illustId,
    required String mediumUrl,
    required List<Frame> frames,
    required Directory extractDir,
    UgoiraProgressCallback? onProgress,
  }) async {
    try {
      // 检查目录是否已有图片，已有则直接返回
      final existingFiles = await _getExistingImageFiles(extractDir);
      if (existingFiles.isNotEmpty && existingFiles.length >= frames.length / 2) {
        Log.d(() => 'Ugoira $illustId: 方法二目录已有 ${existingFiles.length} 帧，跳过下载');
        return existingFiles;
      }

      final timestamp = parseTimestampFromUrl(mediumUrl);
      if (timestamp == null) {
        Log.d(() => 'Ugoira $illustId: 无法解析时间戳');
        return null;
      }

      final extension = parseExtensionFromFrame(frames.first.file);
      
      // 确保目录存在
      if (!await extractDir.exists()) {
        await extractDir.create(recursive: true);
      }
      
      final frameFiles = <File>[];
      int totalReceived = 0;
      int failCount = 0;

      for (int i = 0; i < frames.length; i++) {
        final frameUrl = buildOriginalFrameUrl(timestamp, illustId, i, extension);
        final fileName = '${i.toString().padLeft(6, '0')}.$extension';
        final filePath = path.join(extractDir.path, fileName);

        try {
          final file = await pixivCacheManager.getSingleFile(
            frameUrl,
            headers: Hoster.header(url: frameUrl),
          );
          final bytes = await file.readAsBytes();
          await File(filePath).writeAsBytes(bytes);
          frameFiles.add(File(filePath));
          
          totalReceived += bytes.length;
          
          // 基于当前已下载帧的平均大小动态估算总大小，这样会比仅用第一张估算更准
          final currentEstimatedTotal = (totalReceived / frameFiles.length * frames.length).toInt();
          
          // 回传进度：以累计字节数作为进度
          onProgress?.call(totalReceived, currentEstimatedTotal);
        } catch (e) {
          failCount++;
          // 如果前3帧都失败，认为方法二不可用
          if (failCount >= 3 && frameFiles.isEmpty) {
            Log.d(() => 'Ugoira $illustId: 方法二连续失败，放弃');
            // 清理已下载的文件
            for (final f in frameFiles) {
              if (await f.exists()) await f.delete();
            }
            return null;
          }
        }
      }

      // 如果成功率太低（低于50%），认为失败
      if (frameFiles.length < frames.length / 2) {
        Log.d(() => 'Ugoira $illustId: 方法二成功率过低 ${frameFiles.length}/${frames.length}');
        for (final f in frameFiles) {
          if (await f.exists()) await f.delete();
        }
        return null;
      }

      frameFiles.sort((a, b) => a.path.compareTo(b.path));
      Log.d(() => 'Ugoira $illustId: 方法二成功 ${frameFiles.length}/${frames.length}');
      return frameFiles;
    } catch (e) {
      Log.e(() => 'Ugoira $illustId: 方法二异常: $e');
      return null;
    }
  }

  /// 尝试下载并解压 ZIP 文件
  /// 
  /// 返回帧文件列表，如果失败返回 null
  Future<List<File>?> _tryDownloadAndExtractZip(
    String zipUrl,
    Directory extractDir, {
    UgoiraProgressCallback? onProgress,
  }) async {
    try {
      // 检查目录是否已有图片，已有则直接返回
      final existingFiles = await _getExistingImageFiles(extractDir);
      if (existingFiles.isNotEmpty) {
        Log.d(() => 'Ugoira ZIP 目录已有 ${existingFiles.length} 帧，跳过下载');
        return existingFiles;
      }

      if (!await extractDir.exists()) {
        await extractDir.create(recursive: true);
      }

      // 改为流式下载以获取进度
      io.File? zipFile;
      await for (final response in pixivCacheManager.getFileStream(
        zipUrl,
        headers: Hoster.header(url: zipUrl),
        withProgress: true,
      )) {
        if (response is DownloadProgress) {
          onProgress?.call(response.downloaded, response.totalSize ?? 0);
        } else if (response is FileInfo) {
          zipFile = response.file as io.File;
        }
      }

      if (zipFile == null) {
        throw Exception('ZIP 下载失败');
      }

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

      frameFiles.sort((a, b) => a.path.compareTo(b.path));
      Log.d(() => 'Ugoira ZIP 解压成功: ${frameFiles.length} 帧');
      return frameFiles;
    } catch (e) {
      Log.e(() => 'Ugoira ZIP 下载/解压失败: $e');
      return null;
    }
  }

  /// 获取动图元数据
  Future<UgoiraMetadataResponse> fetchMetadata(int illustId) async {
    return await apiClient.getUgoiraMetadata(illustId);
  }

  /// 删除临时解压目录（所有可能的目录）
  ///
  /// ZIP 文件由 pixivCacheManager 管理，无需手动删除
  Future<void> cleanupTempExtractDir(int illustId) async {
    final methods = ['frames', 'original', 'medium'];
    for (final method in methods) {
      final dir = Directory(_getMethodPath(illustId, method));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  }

  /// 获取临时解压目录路径（返回第一个存在的目录）
  /// 
  /// 优先级：frames > original > medium
  String? getTempExtractPath(int illustId) {
    final methods = ['frames', 'original', 'medium'];
    for (final method in methods) {
      final dirPath = _getMethodPath(illustId, method);
      if (Directory(dirPath).existsSync()) {
        return dirPath;
      }
    }
    return null;
  }

  /// 检查临时解压目录是否存在（任一目录存在即返回 true）
  Future<bool> hasTempExtract(int illustId) async {
    final methods = ['frames', 'original', 'medium'];
    for (final method in methods) {
      final dir = Directory(_getMethodPath(illustId, method));
      if (await dir.exists()) {
        return true;
      }
    }
    return false;
  }

  /// 获取临时解压目录中的所有文件（从存在的目录获取）
  Future<List<File>> getExtractedFiles(int illustId) async {
    final extractPath = getTempExtractPath(illustId);
    if (extractPath == null) {
      return [];
    }
    
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


  /// 将 medium URL 转换为高清 URL
  /// 
  /// medium URL 格式: https://i.pximg.net/img-zip-ugoira/img/.../xxx_ugoira600x600.zip
  /// 高清 URL 格式: https://i.pximg.net/img-zip-ugoira/img/.../xxx_ugoira1920x1080.zip
  String? getOriginalZipUrl(String mediumUrl) {
    // 替换 ugoira600x600 为 ugoira1920x1080
    if (mediumUrl.contains('ugoira600x600')) {
      return mediumUrl.replaceAll('ugoira600x600', 'ugoira1920x1080');
    }
    return null;
  }

  /// 测试下载高清版本的动图
  /// 
  /// 尝试下载高清版本 (1920x1080)，如果失败则回退到 medium 版本
  /// 返回包含下载信息的字符串，用于测试展示
  Future<String> testDownloadOriginalUgoira(int illustId) async {
    final stopwatch = Stopwatch()..start();
    final log = StringBuffer();
    
    try {
      // 1. 获取元数据
      log.writeln('1. 获取元数据...');
      final metadata = await fetchMetadata(illustId);
      final mediumUrl = metadata.ugoiraMetadata.zipUrls.medium;
      log.writeln('   Medium URL: $mediumUrl');
      
      // 2. 构建高清 URL
      final originalUrl = getOriginalZipUrl(mediumUrl);
      log.writeln('   Original URL: $originalUrl');
      
      if (originalUrl == null) {
        log.writeln('   ⚠️ 无法构建高清 URL');
        return log.toString();
      }
      
      // 3. 准备临时目录（与正式下载目录一致）
      final extractDir = Directory(_getMethodPath(illustId, 'original'));
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);
      log.writeln('2. 临时目录: ${extractDir.path}');
      
      // 4. 尝试下载高清版本
      log.writeln('3. 尝试下载高清版本...');
      File? zipFile;
      bool isOriginal = false;
      
      try {
        zipFile = await pixivCacheManager.getSingleFile(
          originalUrl,
          headers: Hoster.header(url: originalUrl),
        );
        isOriginal = true;
        log.writeln('   ✅ 高清版本下载成功!');
      } catch (e) {
        log.writeln('   ❌ 高清版本下载失败: $e');
        log.writeln('   回退到 Medium 版本...');
        zipFile = await pixivCacheManager.getSingleFile(
          mediumUrl,
          headers: Hoster.header(url: mediumUrl),
        );
        log.writeln('   ✅ Medium 版本下载成功');
      }
      
      // 5. 获取文件信息
      final zipSize = await zipFile.length();
      log.writeln('4. ZIP 文件大小: ${(zipSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // 6. 解压文件
      log.writeln('5. 解压文件...');
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      int totalFrameSize = 0;
      for (final file in archive) {
        final filePath = path.join(extractDir.path, file.name);
        if (file.isFile) {
          final outputFile = File(filePath);
          await outputFile.create(recursive: true);
          await outputFile.writeAsBytes(file.content as List<int>);
          totalFrameSize += (file.content as List<int>).length;
        }
      }
      
      log.writeln('   帧数量: ${archive.length}');
      log.writeln('   帧总大小: ${(totalFrameSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // 7. 获取第一帧信息
      final firstFrame = archive.firstWhere((f) => f.isFile);
      log.writeln('   第一帧: ${firstFrame.name}');
      
      stopwatch.stop();
      log.writeln('');
      log.writeln('========== 结果 ==========');
      log.writeln('版本: ${isOriginal ? "高清 (1920x1080)" : "Medium (600x600)"}');
      log.writeln('耗时: ${stopwatch.elapsedMilliseconds} ms');
      log.writeln('保存位置: ${extractDir.path}');
      
      return log.toString();
    } catch (e, stack) {
      stopwatch.stop();
      log.writeln('');
      log.writeln('❌ 错误: $e');
      log.writeln('堆栈: $stack');
      return log.toString();
    }
  }

  /// 从 medium URL 解析时间戳路径
  /// 
  /// medium URL 格式: https://i.pximg.net/img-zip-ugoira/img/2020/01/15/12/30/45/12345678_ugoira600x600.zip
  /// 返回: 2020/01/15/12/30/45
  String? parseTimestampFromUrl(String mediumUrl) {
    // 匹配 img/YYYY/MM/DD/HH/MM/SS/ 格式
    final regex = RegExp(r'img/(\d{4}/\d{2}/\d{2}/\d{2}/\d{2}/\d{2})/');
    final match = regex.firstMatch(mediumUrl);
    if (match != null) {
      return match.group(1);
    }
    return null;
  }

  /// 从帧文件名解析扩展名
  /// 
  /// 帧文件名格式: 000000.jpg 或 000000.png
  String parseExtensionFromFrame(String frameName) {
    final dotIndex = frameName.lastIndexOf('.');
    if (dotIndex != -1) {
      return frameName.substring(dotIndex + 1);
    }
    return 'jpg'; // 默认 jpg
  }

  /// 构建原始帧 URL
  /// 
  /// 原始帧 URL 格式: https://i.pximg.net/img-original/img/YYYY/MM/DD/HH/MM/SS/{illust_id}_ugoira{frame_number}.{extension}
  String buildOriginalFrameUrl(String timestamp, int illustId, int frameIndex, String extension) {
    return 'https://i.pximg.net/img-original/img/$timestamp/${illustId}_ugoira$frameIndex.$extension';
  }

  /// 测试方案二：逐帧下载原始图片
  /// 
  /// 通过解析 medium URL 获取时间戳，构建每帧的原始 URL 并下载
  /// 返回包含下载信息的字符串，用于测试展示
  Future<String> testDownloadOriginalFrames(int illustId) async {
    final stopwatch = Stopwatch()..start();
    final log = StringBuffer();
    
    try {
      // 1. 获取元数据
      log.writeln('1. 获取元数据...');
      final metadata = await fetchMetadata(illustId);
      final mediumUrl = metadata.ugoiraMetadata.zipUrls.medium;
      final frames = metadata.ugoiraMetadata.frames;
      log.writeln('   Medium URL: $mediumUrl');
      log.writeln('   帧数量: ${frames.length}');
      
      // 2. 解析时间戳
      final timestamp = parseTimestampFromUrl(mediumUrl);
      log.writeln('2. 解析时间戳: $timestamp');
      
      if (timestamp == null) {
        log.writeln('   ⚠️ 无法解析时间戳');
        return log.toString();
      }
      
      // 3. 解析扩展名（从第一帧）
      final extension = parseExtensionFromFrame(frames.first.file);
      log.writeln('   文件扩展名: $extension');
      
      // 4. 准备临时目录（与正式下载目录一致）
      final extractDir = Directory(_getMethodPath(illustId, 'frames'));
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);
      log.writeln('3. 临时目录: ${extractDir.path}');
      
      // 5. 逐帧下载
      log.writeln('4. 开始逐帧下载...');
      int successCount = 0;
      int failCount = 0;
      int totalSize = 0;
      
      for (int i = 0; i < frames.length; i++) {
        final frameUrl = buildOriginalFrameUrl(timestamp, illustId, i, extension);
        final fileName = '${i.toString().padLeft(6, '0')}.$extension';
        final filePath = path.join(extractDir.path, fileName);
        
        try {
          final file = await pixivCacheManager.getSingleFile(
            frameUrl,
            headers: Hoster.header(url: frameUrl),
          );
          
          // 复制到目标目录
          final bytes = await file.readAsBytes();
          await File(filePath).writeAsBytes(bytes);
          totalSize += bytes.length;
          successCount++;
          
          // 输出前3帧和最后1帧的详情
          if (i < 3 || i == frames.length - 1) {
            log.writeln('   帧 $i: ${(bytes.length / 1024).toStringAsFixed(1)} KB ✅');
          } else if (i == 3) {
            log.writeln('   ... (省略中间帧)');
          }
        } catch (e) {
          failCount++;
          if (failCount <= 3) {
            log.writeln('   帧 $i: 下载失败 - $e ❌');
          }
          
          // 如果前几帧都失败，可能是 URL 格式不对，提前终止
          if (failCount >= 3 && successCount == 0) {
            log.writeln('   ⚠️ 连续失败，终止下载');
            break;
          }
        }
      }
      
      stopwatch.stop();
      log.writeln('');
      log.writeln('========== 结果 ==========');
      log.writeln('成功: $successCount / ${frames.length}');
      log.writeln('失败: $failCount');
      log.writeln('总大小: ${(totalSize / 1024 / 1024).toStringAsFixed(2)} MB');
      log.writeln('耗时: ${stopwatch.elapsedMilliseconds} ms');
      log.writeln('保存位置: ${extractDir.path}');
      
      // 如果有成功的，输出第一帧的 URL 作为参考
      if (successCount > 0) {
        log.writeln('');
        log.writeln('示例 URL:');
        log.writeln(buildOriginalFrameUrl(timestamp, illustId, 0, extension));
      }
      
      return log.toString();
    } catch (e, stack) {
      stopwatch.stop();
      log.writeln('');
      log.writeln('❌ 错误: $e');
      log.writeln('堆栈: $stack');
      return log.toString();
    }
  }
}
