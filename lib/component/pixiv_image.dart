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
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:dio_compatibility_layer/dio_compatibility_layer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_cache_manager_dio/flutter_cache_manager_dio.dart';
import 'package:pixez/models/download_record.dart';

import 'package:pixez/er/hoster.dart';
import 'package:pixez/main.dart';
import 'package:rhttp/rhttp.dart' as r;

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
  static const int maxCacheObjects = 2000;

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
  });

  @override
  _PixivImageState createState() => _PixivImageState();

  static Future<void> generatePixivCache() async {
    final dio = Dio();
    final client = await r.RhttpCompatibleClient.createSync(
        settings: (userSetting.disableBypassSni ||
                userSetting.pictureSource != ImageHost)
            ? null
            : r.ClientSettings(
                tlsSettings:
                    r.TlsSettings(verifyCertificates: false, sni: false),
                dnsSettings: r.DnsSettings.dynamic(
                  resolver: (host) async {
                    if (host == 'i.pximg.net') {
                      return [Hoster.iPximgNet()];
                    }
                    if (host == 's.pximg.net') {
                      return [Hoster.sPximgNet()];
                    }
                    return await InternetAddress.lookup(host)
                        .then((value) => value.map((e) => e.address).toList());
                  },
                )));
    dio.httpClientAdapter = ConversionLayerAdapter(client);
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
    if (oldWidget.url != widget.url) {
      setState(() {
        url = widget.url;
        width = widget.width;
        height = widget.height;
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

        // 使用自定义的本地文件 ImageProvider 配合 Image 组件实现淡入效果
        return Image(
          image: LocalFileImageProvider(localInfo.path),
          fit: displayFit,
          height: displayHeight,
          width: displayWidth,
          frameBuilder: fade
              ? (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) {
                    return child;
                  }
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    child: child,
                  );
                }
              : null,
          errorBuilder: (context, error, stackTrace) {
            // 本地文件加载失败，回退到网络图片
            return _buildNetworkImage();
          },
        );
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
        fadeOutDuration:
            widget.fade ? const Duration(milliseconds: 1000) : null,
        // memCacheWidth: width?.toInt(),
        // memCacheHeight: height?.toInt(),
        imageUrl: url,
        cacheManager: pixivCacheManager,
        height: height,
        width: width,
        fit: fit ?? BoxFit.fitWidth,
        httpHeaders: Hoster.header(url: url));
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
    final file = File(key.filePath);
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
