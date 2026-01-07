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
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_cache_manager_dio/flutter_cache_manager_dio.dart';
import 'package:image/image.dart' as img;
import 'package:pixez/models/download_record.dart';
import 'package:pixez/custom/pixiv_url_util.dart';
import 'package:path/path.dart' as path;

import 'package:pixez/er/hoster.dart';
import 'package:pixez/main.dart';
import 'package:pixez/network/network_speed_interceptor.dart';
import 'package:rhttp/rhttp.dart' as r;

import '../custom/log.dart';

const ImageHost = "i.pximg.net";
const ImageCatHost = "i.pixiv.re";
const ImageSHost = "s.pximg.net";

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
      : super(Config(
          key,
          maxNrOfCacheObjects: maxCacheObjects,
          stalePeriod: Duration(days: 365),
          fileService: DioHttpFileService(dio),
        ));

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
  Future<FileInfo?> _tryLoadOrDownloadCover(String url, int illustId) async {
    final coverPath = downloadStore.getCoverCachePath(illustId);

    // 1. 本地封面缓存存在则直接返回
    if (await io.File(coverPath).exists()) {
      Log.d(() => '加载本地封面缓存: $illustId, url: $url, $coverPath');
      return _fileInfoFromIoFile(coverPath, url);
    }

    // 2. 检查该插画是否已下载，未下载则返回 null，走正常网络加载流程
    final isDownloaded = await downloadStore.isIllustDownloaded(illustId);
    if (!isDownloaded) {
      return null;
    }

    // 3. 检查是否为已删除图片（limit_unknown_360.png）
    if (url.contains('limit_unknown_360.png')) {
      Log.d(() => '图片已删除，尝试从本地第一张图生成封面: $illustId');
      return await _generateCoverFromLocalImage(illustId, coverPath, url);
    }

    // 4. 从网络下载并保存
    try {
      // 确保目录存在
      final dir = io.Directory(path.dirname(coverPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 下载文件（需要 headers 才能访问 Pixiv）
      final file = await getSingleFile(url, headers: Hoster.header(url: url));

      // 检查下载后的文件名是否为占位图（以防 URL 未包含但实际返回了占位图）
      if (file.path.contains('limit_unknown')) {
        Log.d(() => '下载到占位图，尝试从本地第一张图生成封面: $illustId');
        return await _generateCoverFromLocalImage(illustId, coverPath, url);
      }

      // 复制到封面目录
      await file.copy(coverPath);
      Log.d(() => '下载封面成功: $illustId, url: $url');
      return _fileInfoFromIoFile(coverPath, url);
    } catch (e) {
      Log.e('下载封面失败: $illustId, $e');
      // 下载失败时也尝试从本地生成
      return await _generateCoverFromLocalImage(illustId, coverPath, url);
    }
  }

  /// 从本地第一张图生成封面（居中裁剪 + 压缩到 360x360）
  Future<FileInfo?> _generateCoverFromLocalImage(
      int illustId, String coverPath, String url) async {
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

      // 使用 compute 在后台线程处理图片
      final success = await compute(_processCoverImage, {
        'sourcePath': firstImagePath,
        'targetPath': coverPath,
      });

      if (success) {
        Log.d(() => '从本地图生成封面成功: $illustId');
        return _fileInfoFromIoFile(coverPath, url);
      }
      return null;
    } catch (e) {
      Log.e('从本地图生成封面失败: $illustId, $e');
      return null;
    }
  }

  /// 后台线程处理封面图片（居中裁剪 + 缩放到 360x360 + JPEG 70%）
  static Future<bool> _processCoverImage(Map<String, String> params) async {
    try {
      final sourcePath = params['sourcePath']!;
      final targetPath = params['targetPath']!;

      // 读取原图
      final bytes = await io.File(sourcePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return false;

      // 居中裁剪为正方形
      final size = image.width < image.height ? image.width : image.height;
      final x = (image.width - size) ~/ 2;
      final y = (image.height - size) ~/ 2;
      final cropped =
          img.copyCrop(image, x: x, y: y, width: size, height: size);

      // 缩放到 360x360
      final resized = img.copyResize(cropped, width: 360, height: 360);

      // 保存为 JPEG，质量 70%
      final jpegBytes = img.encodeJpg(resized, quality: 70);
      await io.File(targetPath).writeAsBytes(jpegBytes);

      return true;
    } catch (e) {
      return false;
    }
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
          final coverResult = await _tryLoadOrDownloadCover(url, illustId);
          if (coverResult != null) {
            yield coverResult;
            return;
          }
        } catch (e) {
          Log.e('加载封面失败: $url, $e');
        }
      }
    }

    // 3. 从下载目录中查询
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
  });

  @override
  _PixivImageState createState() => _PixivImageState();

  static Future<void> generatePixivCache() async {
    final dio = Dio();
    final client = await r.RhttpCompatibleClient.createSync(
        settings: (userSetting.disableBypassSni ||
                userSetting.pictureSource != ImageHost)
            ? null
            : Hoster.createImageClientSettings());
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
        oldWidget.localImageInfo != widget.localImageInfo) {
      Log.d(
          "url: ${oldWidget.url} -> ${widget.url}, localImageInfo: ${oldWidget.localImageInfo} => ${widget.localImageInfo}");
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
        final containerWidth = constraints.maxWidth.isFinite
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
        return CachedNetworkImage(
          placeholder: (context, url) =>
              widget.placeWidget ?? Container(height: height),
          errorWidget: (context, url, _) => Container(
            height: height,
            child: Center(
              child: TextButton(
                  onPressed: () {
                    setState(() {});
                  },
                  child: Text(":(")),
            ),
          ),
          fadeOutDuration: const Duration(milliseconds: 200),
          fadeInDuration: Duration(milliseconds: 200),
          // memCacheWidth: width?.toInt(),
          // memCacheHeight: height?.toInt(),
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
    return CachedNetworkImage(
      placeholder: (context, url) =>
          widget.placeWidget ?? Container(height: height),
      errorWidget: (context, url, _) => Container(
        height: height,
        child: Center(
          child: TextButton(
              onPressed: () {
                setState(() {});
              },
              child: Text(":(")),
        ),
      ),
      fadeOutDuration: widget.fade ? const Duration(milliseconds: 300) : null,
      // memCacheWidth: width?.toInt(),
      // memCacheHeight: height?.toInt(),
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
    return CachedNetworkImageProvider(url,
        headers: Hoster.header(url: preUrl), cacheManager: pixivCacheManager);
  }
}

/// 自定义本地文件 ImageProvider，支持异步加载本地图片
class LocalFileImageProvider extends ImageProvider<LocalFileImageProvider> {
  final String filePath;
  final double scale;

  const LocalFileImageProvider(this.filePath, {this.scale = 1.0});

  @override
  Future<LocalFileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<LocalFileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
      LocalFileImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.filePath,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<LocalFileImageProvider>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
      LocalFileImageProvider key, ImageDecoderCallback decode) async {
    final file = io.File(key.filePath);
    final bytes = await file.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is LocalFileImageProvider &&
        other.filePath == filePath &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(filePath, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'LocalFileImageProvider')}("$filePath", scale: $scale)';
}

/// 自定义图片组件，支持传入 ImageProvider（类似 CachedNetworkImage，不使用 Image 控件）
class CustomImage extends StatefulWidget {
  final ImageProvider imageProvider;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final bool fade;
  final Widget? placeholder;
  final Widget? errorWidget;
  final VoidCallback? onError;

  const CustomImage({
    Key? key,
    required this.imageProvider,
    this.fit,
    this.width,
    this.height,
    this.fade = true,
    this.placeholder,
    this.errorWidget,
    this.onError,
  }) : super(key: key);

  @override
  State<CustomImage> createState() => _CustomImageState();
}

class _CustomImageState extends State<CustomImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  ui.Image? _image;
  bool _isLoading = true;
  bool _hasError = false;
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _loadImage();
  }

  void _loadImage() {
    final ImageConfiguration config = ImageConfiguration(
      size: widget.width != null || widget.height != null
          ? Size(
              widget.width ?? double.infinity, widget.height ?? double.infinity)
          : null,
    );

    _imageStream = widget.imageProvider.resolve(config);
    _imageStreamListener = ImageStreamListener(
      (ImageInfo imageInfo, bool synchronousCall) {
        if (mounted) {
          setState(() {
            _image = imageInfo.image;
            _isLoading = false;
          });

          // 开始淡入动画
          if (widget.fade) {
            _controller.forward();
          }
        }
      },
      onError: (exception, stackTrace) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _isLoading = false;
          });
          widget.onError?.call();
        }
      },
    );

    _imageStream!.addListener(_imageStreamListener!);
  }

  @override
  void didUpdateWidget(CustomImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      // 图片提供者改变，重新加载
      _imageStream?.removeListener(_imageStreamListener!);
      _image?.dispose();
      setState(() {
        _image = null;
        _isLoading = true;
        _hasError = false;
        _controller.reset();
      });
      _loadImage();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _image?.dispose();
    _imageStream?.removeListener(_imageStreamListener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.errorWidget ?? widget.placeholder ?? Container();
    }

    if (_isLoading || _image == null) {
      return widget.placeholder ?? Container();
    }

    // 使用 RawImage 直接渲染 ui.Image，不使用 Image 控件
    Widget imageWidget = RawImage(
      image: _image,
      fit: widget.fit ?? BoxFit.fitWidth,
      width: widget.width,
      height: widget.height,
    );

    // 应用淡入效果
    if (widget.fade) {
      imageWidget = FadeTransition(
        opacity: _animation,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}

/// 自定义本地图片组件，支持淡入效果（使用 CustomImage 和 LocalFileImageProvider）
class FadeInLocalImage extends StatelessWidget {
  final String filePath;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final bool fade;
  final Widget? placeholder;
  final VoidCallback? onError;

  const FadeInLocalImage({
    Key? key,
    required this.filePath,
    this.fit,
    this.width,
    this.height,
    this.fade = true,
    this.placeholder,
    this.onError,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomImage(
      imageProvider: LocalFileImageProvider(filePath),
      fit: fit,
      width: width,
      height: height,
      fade: fade,
      placeholder: placeholder,
      onError: onError,
    );
  }
}
