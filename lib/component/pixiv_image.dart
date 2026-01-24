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

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:dio_compatibility_layer/dio_compatibility_layer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file/local.dart';
import 'package:pixez/constants.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_cache_manager_dio/flutter_cache_manager_dio.dart';
import 'package:image/image.dart' as img;
import 'package:pixez/models/download_record.dart';
import 'package:pixez/utils/webp_encoder.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:pixez/custom/pixiv_url_util.dart';
import 'package:path/path.dart' as path;

import 'package:pixez/er/hoster.dart';
import 'package:pixez/main.dart';
import 'package:pixez/network/network_speed_interceptor.dart';
import 'package:rhttp/rhttp.dart' as r;

import '../custom/log.dart';

// 从 hoster.dart 导出常量，保持向后兼容
export 'package:pixez/er/hoster.dart' show ImageHost, ImageCatHost, ImageSHost;

// 注意，stable的http_interceptor这里是无效的，因为实现send是todo
// 实现CacheManager和混入ImageCacheManager缺一不可
// 如果你恰好看到这个实现方法实例，且对你有些帮助或者启发：
// 听一首Mili-Salt, Pepper, Birds, And the Thought Police吧 🎵

PixivCacheManager pixivCacheManager = PixivCacheManager.instance;

/// 自定义缓存管理器，支持设置最大缓存数量
class PixivCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'pixivCache';
  static const int maxCacheObjects = 5000;

  static late final PixivCacheManager _instance;

  static PixivCacheManager get instance => _instance;

  static void initialize(Dio dio) {
    _instance = PixivCacheManager._(dio);
  }

  PixivCacheManager._(Dio dio)
    : super(
        Config(
          key,
          maxNrOfCacheObjects: maxCacheObjects,
          stalePeriod: Duration(days: 365),
          fileService: DioHttpFileService(dio),
        ),
      );

  Future<FileInfo?> _fileInfoFromIoFile(String filePath, String url) async {
    final ioFile = io.File(filePath);
    // 转换为 file 包的 File 类型
    const fs = LocalFileSystem();
    if (await ioFile.exists()) {
      // 返回 FileInfo，使用 FileSource.cache 表示本地缓存文件
      return FileInfo(
        fs.file(filePath),
        FileSource.Cache,
        DateTime.now().add(const Duration(days: 365)),
        url,
      );
    }
    return null;
  }

  /// 尝试加载或下载封面
  /// 只对已下载的插画进行本地封面缓存
  /// 如果本地存在则返回本地文件，否则从网络下载并缓存
  /// 如果图片已被删除（URL 含 limit_unknown_360.png），则从本地第一张图压缩生成封面
  Future<FileInfo?> _tryLoadOrDownloadCover(
    String url,
    int illustId, {
    String quality = Constants.qualityMedium,
  }) async {
    // 1. 如果请求的是 origin 质量，直接从下载目录读取，不经过 cover 目录
    if (quality == Constants.qualityOriginal) {
      final localPath = await downloadStore.getLocalImagePath(illustId, 0);
      if (localPath != null && await io.File(localPath).exists()) {
        Log.d(() => '封面请求(origin)命中本地原图: $illustId');
        return _fileInfoFromIoFile(localPath, url);
      }
      return null; // origin 质量不下载到封面目录
    }

    final coverPath = downloadStore.getCoverCachePath(
      illustId,
      quality: quality,
    );

    // 2. 本地封面缓存存在则直接返回
    if (await io.File(coverPath).exists()) {
      Log.d(
        () => '加载本地封面缓存: $illustId, quality: $quality, url: $url, $coverPath',
      );
      return _fileInfoFromIoFile(coverPath, url);
    }

    // 3. 检查是否存在旧的 JPG 缓存并尝试迁移
    final oldJpgPath = path.setExtension(coverPath, '.jpg');
    if (await io.File(oldJpgPath).exists()) {
      Log.d(() => '发现旧的 JPG 封面缓存，尝试迁移到 WebP: $oldJpgPath');
      final startTime = DateTime.now();
      final oldSize = await io.File(oldJpgPath).length();

      final migrationSuccess = await workerManager.execute(
        () => _migrateJpgToWebp({
          'jpgPath': oldJpgPath,
          'webpPath': coverPath,
          'quality': quality,
        }),
      );

      if (migrationSuccess) {
        Log.d(() {
          final newSize = io.File(coverPath).lengthSync();
          final duration = DateTime.now().difference(startTime);
          return '封面迁移成功: $illustId, 耗时: ${duration.inMilliseconds}ms, 大小: ${oldSize ~/ 1024}KB -> ${newSize ~/ 1024}KB (减少: ${(oldSize - newSize) * 100 / oldSize}% )';
        });
        return _fileInfoFromIoFile(coverPath, url);
      }
    }

    // 4. 检查该插画是否已下载，未下载则返回 null，走正常网络加载流程
    final isDownloaded = await downloadStore.isIllustDownloaded(illustId);
    if (!isDownloaded) {
      return null;
    }

    // 4. 对于其他质量等级（medium, large 等），如果已下载且非正方形，直接读取下载的原图或对应的缩略图
    // 这里我们先走正常的生成/下载逻辑，以保证 Waterfall 模式下的性能优化（使用压缩后的 medium/large 而非原图）。
    // 只有 origin 质量才绕过封面目录。

    // 5. 检查是否为已删除图片（limit_unknown_360.png）
    if (url.contains('limit_unknown_360.png')) {
      Log.d(() => '图片已删除，尝试从本地第一张图生成封面: $illustId');
      return await _generateCoverFromLocalImage(
        illustId,
        coverPath,
        url,
        quality: quality,
      );
    }

    // 6. 从网络下载并保存
    try {
      // 确保目录存在
      final dir = io.Directory(path.dirname(coverPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 检查下载后的文件名是否为占位图（以防 URL 未包含但实际返回了占位图）
      if (url.contains('limit_unknown')) {
        Log.d(() => '下载到占位图，尝试从本地第一张图生成封面: $illustId');
        return await _generateCoverFromLocalImage(
          illustId,
          coverPath,
          url,
          quality: quality,
        );
      }

      // 下载文件（需要 headers 才能访问 Pixiv）
      final file = await getSingleFile(url, headers: Hoster.header(url: url));

      // 无论下载的是什么格式，都进行压缩处理并存为 WebP
      final startTime = DateTime.now();
      final oldSize = await file.length();

      final success = await workerManager.execute(
        () => _processCoverImage({
          'sourcePath': file.path,
          'targetPath': coverPath,
          'quality': quality,
          'isLocalOriginal': false, // 下载的封面
        }),
      );

      if (success) {
        Log.d(() {
          final newSize = io.File(coverPath).lengthSync();
          final duration = DateTime.now().difference(startTime);
          return '下载并压缩封面成功: $illustId, 耗时: ${duration.inMilliseconds}ms, 大小: ${oldSize ~/ 1024}KB -> ${newSize ~/ 1024}KB (减少: ${(oldSize - newSize) * 100 / oldSize}% )';
        });
        return _fileInfoFromIoFile(coverPath, url);
      } else {
        // 如果处理失败，作为兜底直接复制
        await file.copy(coverPath);
        Log.w('压缩封面处理失败，执行降级逻辑直接复制: $illustId');
        return _fileInfoFromIoFile(coverPath, url);
      }
    } catch (e) {
      Log.e('下载封面失败: $illustId, $e');
      // 下载失败时也尝试从本地生成
      return await _generateCoverFromLocalImage(
        illustId,
        coverPath,
        url,
        quality: quality,
      );
    }
  }

  /// 从本地第一张图生成封面
  Future<FileInfo?> _generateCoverFromLocalImage(
    int illustId,
    String coverPath,
    String url, {
    String quality = Constants.qualityMedium,
  }) async {
    try {
      // 获取本地第一张图路径
      final firstImagePath = await downloadStore.getLocalImagePath(illustId, 0);
      if (firstImagePath == null) {
        Log.e('无法生成封面：本地第一张图不存在: $illustId');
        return null;
      }

      // 确保封面目录存在
      final dir = io.Directory(path.dirname(coverPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 根据质量决定处理方式
      // 如果请求的是 Original，且本地有原图，则直接复制（虽然这种情况在 _tryLoadOrDownloadCover 已处理，但作为兜底）
      if (quality == Constants.qualityOriginal) {
        await io.File(firstImagePath).copy(coverPath);
        return _fileInfoFromIoFile(coverPath, url);
      }

      // 使用 workerManager 在后台线程处理图片（裁剪/压缩）
      final success = await workerManager.execute(
        () => _processCoverImage({
          'sourcePath': firstImagePath,
          'targetPath': coverPath,
          'quality': quality,
          'isLocalOriginal': true, // 本地原图需缩放
        }),
      );

      if (success) {
        Log.d(() => '从本地图生成封面成功: $illustId, quality: $quality');
        return _fileInfoFromIoFile(coverPath, url);
      }
      return null;
    } catch (e) {
      Log.e('从本地图生成封面失败: $illustId, $e');
      return null;
    }
  }

  /// 迁移 JPG 到 WebP
  static Future<bool> _migrateJpgToWebp(Map<String, String> params) async {
    try {
      final jpgPath = params['jpgPath']!;
      final webpPath = params['webpPath']!;
      final quality = params['quality'] ?? Constants.qualityMedium;

      // 优化：直接使用文件路径进行编码，避免解码
      return await _encodeToWebp(
        targetPath: webpPath,
        quality: quality,
        sourcePath: jpgPath,
        deleteSource: true, // 迁移场景需要删除原 JPG
      );
    } catch (e) {
      Log.e('迁移封面失败: $e');
      return false;
    }
  }

  /// 内部 WebP 编码方法（封装 WebPEncoder）
  static Future<bool> _encodeToWebp({
    img.Image? image,
    String? sourcePath,
    required String targetPath,
    required String quality,
    bool deleteSource = false,
  }) async {
    // 根据质量决定参数
    int webpQuality = 75;
    if (quality == Constants.qualityLarge) {
      webpQuality = 90;
    }

    // 1. 如果是桌面端，尝试使用 WebPEncoder
    if (io.Platform.isWindows) {
      try {
        String? inputPath = sourcePath;
        bool isTemp = false;

        // 如果没有提供路径，则存为临时的 jpg
        if (inputPath == null && image != null) {
          inputPath = '$targetPath.temp.jpg';
          await io.File(inputPath).writeAsBytes(img.encodeJpg(image));
          isTemp = true;
        }

        if (inputPath != null) {
          final result = await WebPEncoder.encode(
            framesPaths: [inputPath],
            delays: [100],
            outputPath: targetPath,
            quality: webpQuality,
          );

          // 如果是临时文件，清理它
          if (isTemp) {
            await io.File(inputPath).delete();
          }

          if (result != null) {
            // 只有在明确要求且不是原地替换时才删除
            if (deleteSource && sourcePath != null && sourcePath != targetPath) {
              final sourceFile = io.File(sourcePath);
              if (await sourceFile.exists()) {
                await sourceFile.delete();
              }
            }
            return true;
          }
        }
      } catch (e) {
        Log.e('WebPEncoder 编码失败，尝试回退: $e');
      }
    }

    // 2. 兜底方案：保存为 JPG (虽然以后缀名 .webp 保存，但这显然不理想，但目前 image 库限制如此)
    // 如果没有 image 对象（仅有 sourcePath），则需要先读取
    img.Image? fallbackImage = image;
    if (fallbackImage == null && sourcePath != null) {
      final bytes = await io.File(sourcePath).readAsBytes();
      fallbackImage = img.decodeImage(bytes);
    }

    if (fallbackImage == null) return false;

    Log.w('无法使用 WebPEncoder，回退到 JPG 格式存储 (文件名仍为 .webp)');
    final jpgBytes = img.encodeJpg(fallbackImage, quality: webpQuality);
    await io.File(targetPath).writeAsBytes(jpgBytes);

    // 只有在明确要求且不是原地替换时才删除
    if (deleteSource && sourcePath != null && sourcePath != targetPath) {
      final sourceFile = io.File(sourcePath);
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }
    }
    return true;
  }

  /// 后台线程处理封面图片（居中裁剪(仅限 square_medium) + 缩放 + 编码）
  static Future<bool> _processCoverImage(Map<String, dynamic> params) async {
    try {
      final String sourcePath = params['sourcePath']!;
      final String targetPath = params['targetPath']!;
      final String quality = params['quality'] ?? Constants.qualityMedium;
      final bool isLocalOriginal = params['isLocalOriginal'] ?? false;

      // 优化：如果在 Windows 平台且不需要裁剪（Waterfall 模式），且不是处理本地原图
      // 我们信任 Pixiv 下载回来的封面尺寸已经是合适的（medium 为 540，large 为 1200），直接转码
      if (!isLocalOriginal ) {
        return await _encodeToWebp(
          targetPath: targetPath,
          quality: quality,
          sourcePath: sourcePath,
        );
      }

      // 读取原图
      final bytes = await io.File(sourcePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return false;

      img.Image processed;
      if (quality == Constants.qualitySquareMedium) {
        // 仅在 square_medium 模式下裁剪为正方形
        final size = image.width < image.height ? image.width : image.height;
        processed = img.copyCrop(
          image,
          x: (image.width - size) ~/ 2,
          y: (image.height - size) ~/ 2,
          width: size,
          height: size,
        );
      } else {
        // 其他（Waterfall）模式保持原始比例
        processed = image;
      }

      // 根据质量确定宽高限制
      int? maxWidth;
      int? maxHeight;
      int? maxSideSize;

      if (quality == Constants.qualityLarge) {
        maxWidth = 600;
        maxHeight = 1200;
      } else {
        maxSideSize = 540;
      }

      // 缩放图片（维持比例）
      img.Image resized;
      bool needResize = false;
      if (maxSideSize != null) {
        if (processed.width > maxSideSize || processed.height > maxSideSize) {
          needResize = true;
          if (processed.width > processed.height) {
            maxWidth = maxSideSize;
            maxHeight = null;
          } else {
            maxWidth = null;
            maxHeight = maxSideSize;
          }
        }
      } else if (maxWidth != null && maxHeight != null) {
        if (processed.width > maxWidth || processed.height > maxHeight) {
          needResize = true;
          // 计算缩放比例，选择更小的比例以确保都在限制内
          double widthRatio = maxWidth / processed.width;
          double heightRatio = maxHeight / processed.height;
          if (widthRatio < heightRatio) {
            maxHeight = null; // 由 width 决定
          } else {
            maxWidth = null; // 由 height 决定
          }
        }
      }

      if (needResize) {
        resized = img.copyResize(processed, width: maxWidth, height: maxHeight);
      } else {
        resized = processed;
      }

      // 统一调用编码方法
      return await _encodeToWebp(
        image: resized,
        targetPath: targetPath,
        quality: quality,
        // 如果没有经过修改，透传原图路径，避免生成临时 JPG
        sourcePath: resized == image ? sourcePath : null,
      );
    } catch (e) {
      Log.e('处理封面图片异常: $e');
      return false;
    }
  }

  /// 后台线程处理头像图片（压缩为 WebP，保持原尺寸）
  static Future<bool> _processAvatarImage(Map<String, String> params) async {
    try {
      final sourcePath = params['sourcePath']!;
      final targetPath = params['targetPath']!;

      // 头像不需要缩放，直接调用 _encodeToWebp。
      // _encodeToWebp 内部会自动处理 Windows 平台的路径编码以及非 Windows 平台的解码兜底。
      return await _encodeToWebp(
        targetPath: targetPath,
        quality: Constants.qualityMedium,
        sourcePath: sourcePath,
      );
    } catch (e) {
      Log.e('处理头像图片异常: $e');
      return false;
    }
  }

  /// 尝试加载或下载作者头像
  /// 只对已下载作品的作者进行本地缓存
  Future<FileInfo?> _tryLoadOrDownloadAvatar(String url, int userId) async {
    // 1. 检查是否为已下载作品的作者
    final author = await downloadStore.dbProvider.getAuthorByUserId(userId);
    if (author == null) return null; // 非已下载作者，走网络

    final avatarPath = downloadStore.getAvatarCachePath(userId);
    final avatarFile = io.File(avatarPath);
    final dbProfileUrl = author.profileImageUrl;

    // 2. 比对 URL 判断是否需要更新
    final needUpdate = dbProfileUrl != url;

    // 3. 本地缓存存在且 URL 未变化，直接返回
    if (!needUpdate && await avatarFile.exists()) {
      Log.d(() => '加载本地头像缓存: $userId');
      return _fileInfoFromIoFile(avatarPath, url);
    }

    // 4. 下载头像
    try {
      final dir = io.Directory(path.dirname(avatarPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final file = await getSingleFile(url, headers: Hoster.header(url: url));

      // 压缩并保存为 WebP
      final success = await workerManager.execute(
        () => _processAvatarImage({
          'sourcePath': file.path,
          'targetPath': avatarPath,
        }),
      );

      if (success) {
        // 更新数据库中的头像 URL
        if (needUpdate) {
          await downloadStore.dbProvider.updateAuthorProfileUrl(userId, url);
        }
        Log.d(() => '下载并缓存头像成功: $userId');
        return _fileInfoFromIoFile(avatarPath, url);
      }
    } catch (e) {
      Log.e('下载头像失败: $userId, $e');
    }

    return null;
  }

  @override
  Stream<FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) async* {
    // 1. 判断是否是 file:// 开头的本地文件路径
    if (url.startsWith('file://')) {
      try {
        final uri = Uri.tryParse(url);
        final filePath = uri?.toFilePath();
        if (filePath == null) {
          Log.e('filePath is null: $url');
          throw Exception('filePath is null: $url');
        }
        final response = await _fileInfoFromIoFile(filePath, url);
        Log.d(() => '加载本地文件成功: $url, ${response?.file.path}');
        if (response != null) {
          yield response;
          return;
        }
      } catch (e) {
        Log.e('读取本地文件失败: $url, $e');
      }
      // 文件不存在，直接报错
      throw Exception('getImageFile file not found: $url');
    }

    // 2. 检查 header 中的 cover 参数（封面请求）
    final illustIdStr = headers?['cover'];
    if (illustIdStr != null && downloadStore.isInitialized) {
      final illustId = int.tryParse(illustIdStr);
      if (illustId != null) {
        try {
          final quality = headers?['quality'] ?? Constants.qualitySquareMedium;
          final coverResult = await _tryLoadOrDownloadCover(
            url,
            illustId,
            quality: quality,
          );
          if (coverResult != null) {
            yield coverResult;
            return;
          }
        } catch (e) {
          Log.e('加载封面失败: $url, $e');
        }
      }
    }

    // 3. 检查 header 中的 avatar 参数（作者头像请求）
    final avatarUserIdStr = headers?['avatar'];
    if (avatarUserIdStr != null && downloadStore.isInitialized) {
      final userId = int.tryParse(avatarUserIdStr);
      if (userId != null) {
        try {
          final avatarResult = await _tryLoadOrDownloadAvatar(url, userId);
          if (avatarResult != null) {
            yield avatarResult;
            return;
          }
        } catch (e) {
          Log.e('加载头像失败: $url, $e');
        }
      }
    }

    // 4. 从下载目录中查询
    if (downloadStore.isInitialized && PixivUrlUtil.isPixivOriginalUrl(url)) {
      try {
        final imageInfo = await downloadStore.getLocalImageInfoByUrl(url);
        if (imageInfo != null) {
          Log.d(() => '加载下载文件成功: $url, ${imageInfo.path}');
          final response = await _fileInfoFromIoFile(imageInfo.path, url);
          if (response != null) {
            yield response;
            return;
          }
        }
      } catch (e) {
        Log.e('从下载目录查询图片失败: $url, $e');
      }
    }

    yield* super.getImageFile(
      url,
      key: key,
      headers: headers,
      withProgress: withProgress,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
    );
  }
}

class PixivImage extends StatefulWidget {
  final String url;
  final LocalImageInfo? localImageInfo; // 本地图片信息（包含路径和宽高）
  final Widget? placeWidget;
  final bool fade;
  final BoxFit? fit;
  final bool? enableMemoryCache;
  final double? height;
  final double? width;
  final String? host;
  final Map<String, String>? httpHeaders; // 自定义 HTTP 头（用于封面标识）
  final int? memCacheWidth;
  final int? memCacheHeight;

  PixivImage(
    this.url, {
    this.localImageInfo,
    this.placeWidget,
    this.fade = true,
    this.fit,
    this.enableMemoryCache,
    this.height,
    this.host,
    this.width,
    this.httpHeaders,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  _PixivImageState createState() => _PixivImageState();

  static Future<void> generatePixivCache() async {
    final dio = Dio();
    final client = await r.RhttpCompatibleClient.createSync(
      settings:
          (userSetting.disableBypassSni ||
                  userSetting.pictureSource != ImageHost)
              ? null
              : Hoster.createImageClientSettings(),
    );
    dio.httpClientAdapter = ConversionLayerAdapter(client);
    // 添加网络速度监控拦截器
    dio.interceptors.add(NetworkSpeedInterceptor());
    PixivCacheManager.initialize(dio);
  }
}

class _PixivImageState extends State<PixivImage> {
  late String url;
  bool already = false;
  bool? enableMemoryCache;
  double? width;
  double? height;
  BoxFit? fit;
  bool fade = true;
  Widget? placeWidget;

  @override
  void initState() {
    url = widget.url;
    enableMemoryCache = widget.enableMemoryCache ?? true;
    width = widget.width;
    height = widget.height;
    fit = widget.fit;
    fade = widget.fade;
    placeWidget = widget.placeWidget;
    super.initState();
  }

  @override
  void didUpdateWidget(covariant PixivImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.height != widget.height ||
        oldWidget.width != widget.width ||
        oldWidget.memCacheWidth != widget.memCacheWidth ||
        oldWidget.memCacheHeight != widget.memCacheHeight ||
        oldWidget.localImageInfo != widget.localImageInfo) {
      Log.d(
        "url: ${oldWidget.url} -> ${widget.url}, localImageInfo: ${oldWidget.localImageInfo} => ${widget.localImageInfo}",
      );
      setState(() {
        url = widget.url;
        width = widget.width;
        height = widget.height;
        fit = widget.fit;
        fade = widget.fade;
        placeWidget = widget.placeWidget;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果提供了本地图片信息，优先使用本地文件
    final localInfo = widget.localImageInfo;
    if (localInfo != null && localInfo.path.isNotEmpty) {
      return _buildLocalImage(context, localInfo);
    }

    // 没有本地图片信息，使用网络图片
    return _buildNetworkImage();
  }

  Widget _buildLocalImage(BuildContext context, LocalImageInfo localInfo) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用 LayoutBuilder 获取实际容器宽度
        final containerWidth =
            constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : (width ?? MediaQuery.of(context).size.width);

        // 计算显示尺寸
        double? displayWidth;
        double? displayHeight;
        BoxFit displayFit = fit ?? BoxFit.fitWidth;

        if (localInfo.width != null && localInfo.height != null) {
          final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
          final imageWidth = localInfo.width!.toDouble() / devicePixelRatio;
          final imageHeight = localInfo.height!.toDouble() / devicePixelRatio;
          final aspectRatio = imageWidth / imageHeight;

          // 计算基于容器宽度的高度
          final heightByWidth = containerWidth / aspectRatio;

          // 如果图片比容器小，显示原始尺寸；否则撑满容器宽度
          if (imageWidth <= containerWidth) {
            displayWidth = imageWidth;
            displayHeight = imageHeight;
            displayFit = BoxFit.contain;
          } else {
            displayWidth = containerWidth;
            displayHeight = heightByWidth;
            displayFit = BoxFit.fitWidth;
          }
        } else {
          // 没有宽高信息时，使用默认行为
          displayWidth = containerWidth;
        }
        Log.d(() => 'display local image $displayWidth x $displayHeight');
        return CachedNetworkImage(
          placeholder:
              (context, url) => SizedBox(width: displayWidth, height: displayHeight, child: widget.placeWidget ?? Container(height: height),),
          errorWidget:
              (context, url, _) => Container(
                height: height,
                child: Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() {});
                    },
                    child: Text(":("),
                  ),
                ),
              ),
          fadeOutDuration: const Duration(milliseconds: 200),
          fadeInDuration: Duration(milliseconds: 200),
          //imageUrl: 'file://${localInfo.path}',
          imageUrl: Uri.file(localInfo.path).toString(),
          cacheManager: pixivCacheManager,
          height: displayHeight,
          width: displayWidth,
          fit: displayFit,
        );

        // 使用自定义的 FadeInLocalImage 组件实现淡入效果
        // return FadeInLocalImage(
        //   filePath: localInfo.path,
        //   fit: displayFit,
        //   width: displayWidth,
        //   height: displayHeight,
        //   fade: fade,
        //   placeholder: placeWidget ?? Container(height: displayHeight),
        //   onError: () {
        //     // 本地文件加载失败，回退到网络图片
        //     if (mounted) {
        //       setState(() {});
        //     }
        //   },
        // );
      },
    );
  }

  Widget _buildNetworkImage() {
    final int? effectiveMemCacheWidth = widget.memCacheWidth;
    final int? effectiveMemCacheHeight = widget.memCacheHeight;

    return CachedNetworkImage(
      placeholder:
          (context, url) => widget.placeWidget ?? Container(height: height),
      errorWidget:
          (context, url, _) => Container(
            height: height,
            child: Center(
              child: TextButton(
                onPressed: () {
                  setState(() {});
                },
                child: Text(":("),
              ),
            ),
          ),
      fadeOutDuration: widget.fade ? const Duration(milliseconds: 300) : null,
      memCacheWidth:
          effectiveMemCacheWidth != null
              ? (effectiveMemCacheWidth *
                      MediaQuery.devicePixelRatioOf(context))
                  .toInt()
              : null,
      memCacheHeight:
          effectiveMemCacheHeight != null
              ? (effectiveMemCacheHeight *
                      MediaQuery.devicePixelRatioOf(context))
                  .toInt()
              : null,
      imageUrl: url,
      cacheManager: pixivCacheManager,
      height: height,
      width: width,
      fit: fit ?? BoxFit.fitWidth,
      httpHeaders: {
        ...Hoster.header(url: url),
        ...?widget.httpHeaders, // 合并自定义 headers
      },
    );
  }
}

class PixivProvider {
  static ImageProvider url(String url, {String? preUrl}) {
    return CachedNetworkImageProvider(
      url,
      headers: Hoster.header(url: preUrl),
      cacheManager: pixivCacheManager,
    );
  }
}