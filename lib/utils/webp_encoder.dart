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

import 'dart:io';
import 'package:path/path.dart' as path;
import '../custom/log.dart';

/// WebP动图编码器
/// 
/// 使用Google官方img2webp命令行工具将序列帧转换为WebP动图
/// 目前仅支持Windows平台
class WebPEncoder {
  /// 动图标识的part值
  static const int animatedWebPPart = -1;

  /// 检查当前平台是否支持WebP编码
  static bool get isSupported => Platform.isWindows;

  /// 获取img2webp.exe的路径
  /// 
  /// 工具应放置在应用目录的data/flutter_assets/assets/executables/下
  static Future<String?> _getImg2WebpPath() async {
    if (!Platform.isWindows) {
      Log.w('WebPEncoder: 当前平台不支持img2webp');
      return null;
    }

    // 获取应用程序所在目录
    final exeDir = path.dirname(Platform.resolvedExecutable);
    
    // 尝试多个可能的路径
    final possiblePaths = [
      // 打包后的路径
      path.join(exeDir, 'data', 'flutter_assets', 'assets', 'executables', 'img2webp.exe'),
      // 开发时的路径
      path.join(exeDir, 'assets', 'executables', 'img2webp.exe'),
      // 项目根目录（开发调试用）
      path.join(Directory.current.path, 'assets', 'executables', 'img2webp.exe'),
    ];

    for (final p in possiblePaths) {
      if (await File(p).exists()) {
        Log.d('WebPEncoder: 找到img2webp: $p');
        return p;
      }
    }

    Log.e('WebPEncoder: 未找到img2webp.exe');
    return null;
  }

  /// 将序列帧转换为WebP动图
  /// 
  /// [framesPaths]: 序列帧图片路径列表（按顺序）
  /// [delays]: 每帧的延迟时间列表（毫秒），长度应与framesPaths相同
  /// [outputPath]: 输出的WebP文件路径
  /// [quality]: 压缩质量（0-100），默认80
  /// [loop]: 循环次数（0表示无限循环），默认0
  /// 
  /// 返回生成的WebP文件路径，失败返回null
  static Future<String?> encode({
    required List<String> framesPaths,
    required List<int> delays,
    required String outputPath,
    int quality = 80,
    int loop = 0,
  }) async {
    if (framesPaths.isEmpty) {
      Log.e('WebPEncoder: 序列帧列表为空');
      return null;
    }

    if (framesPaths.length != delays.length) {
      Log.w('WebPEncoder: 帧数(${framesPaths.length})与延迟数(${delays.length})不匹配，使用第一个延迟值');
    }

    final img2webpPath = await _getImg2WebpPath();
    if (img2webpPath == null) {
      return null;
    }

    try {
      // 确保输出目录存在
      final outputDir = Directory(path.dirname(outputPath));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // 构建命令参数
      // img2webp格式: img2webp -o output.webp -q 80 -loop 0 -d delay1 frame1.png -d delay2 frame2.png ...
      final arguments = <String>[
        '-o', outputPath,
        '-q', quality.toString(),
        '-loop', loop.toString(),
      ];

      // 添加每一帧及其延迟
      for (int i = 0; i < framesPaths.length; i++) {
        final delay = i < delays.length ? delays[i] : delays.first;
        arguments.add('-d');
        arguments.add(delay.toString());
        arguments.add(framesPaths[i]);
      }

      Log.d('WebPEncoder: 开始转换, 帧数: ${framesPaths.length}');
      
      // 执行命令
      final result = await Process.run(
        img2webpPath,
        arguments,
        runInShell: false,
      );

      if (result.exitCode == 0) {
        // 验证输出文件是否存在
        if (await File(outputPath).exists()) {
          final fileSize = await File(outputPath).length();
          Log.d('WebPEncoder: 转换成功, 输出: $outputPath, 大小: ${fileSize ~/ 1024}KB');
          return outputPath;
        } else {
          Log.e('WebPEncoder: 转换完成但输出文件不存在');
          return null;
        }
      } else {
        Log.e('WebPEncoder: img2webp执行失败');
        Log.e('Exit code: ${result.exitCode}');
        Log.e('Stdout: ${result.stdout}');
        Log.e('Stderr: ${result.stderr}');
        return null;
      }
    } catch (e, stackTrace) {
      Log.e('WebPEncoder: 转换异常: $e');
      Log.e('StackTrace: $stackTrace');
      return null;
    }
  }

  /// 从Ugoira帧目录生成WebP动图
  /// 
  /// [framesDir]: 序列帧所在目录
  /// [delays]: 每帧延迟时间列表（毫秒）
  /// [outputPath]: 输出WebP文件路径
  /// [quality]: 压缩质量（0-100）
  static Future<String?> encodeFromDirectory({
    required String framesDir,
    required List<int> delays,
    required String outputPath,
    int quality = 80,
  }) async {
    try {
      final dir = Directory(framesDir);
      if (!await dir.exists()) {
        Log.e('WebPEncoder: 帧目录不存在: $framesDir');
        return null;
      }

      // 获取所有图片文件
      final entities = await dir.list().toList();
      final frameFiles = <String>[];

      // 支持的图片扩展名
      const supportedExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.bmp'];

      for (final entity in entities) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (supportedExtensions.contains(ext)) {
            frameFiles.add(entity.path);
          }
        }
      }

      if (frameFiles.isEmpty) {
        Log.e('WebPEncoder: 目录中没有找到图片文件: $framesDir');
        return null;
      }

      // 按文件名排序（确保帧顺序正确）
      frameFiles.sort();

      Log.d('WebPEncoder: 从目录加载 ${frameFiles.length} 帧');

      return await encode(
        framesPaths: frameFiles,
        delays: delays,
        outputPath: outputPath,
        quality: quality,
      );
    } catch (e) {
      Log.e('WebPEncoder: 从目录编码失败: $e');
      return null;
    }
  }

  /// 检查img2webp工具是否可用
  static Future<bool> checkAvailability() async {
    final img2webpPath = await _getImg2WebpPath();
    return img2webpPath != null;
  }
}
