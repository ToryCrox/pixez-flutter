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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:dio_compatibility_layer/dio_compatibility_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_cache_manager_dio/flutter_cache_manager_dio.dart';

import 'package:pixez/er/hoster.dart';
import 'package:pixez/main.dart';
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
  final String? localPath; // 新增：本地文件路径
  final Widget? placeWidget;
  final bool fade;
  final BoxFit? fit;
  final bool? enableMemoryCache;
  final double? height;
  final double? width;
  final String? host;

  PixivImage(
    this.url, {
    this.localPath, // 新增参数
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
    // 如果提供了本地路径，优先使用本地文件
    if (widget.localPath != null && widget.localPath!.isNotEmpty) {
      final localFile = File(widget.localPath!);
      Log.d("Using local file: ${localFile.path}, width: $width, height: $height");
      return Image.file(
        localFile,
        fit: fit ?? BoxFit.fitWidth,
        height: height,
        width: width,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) {
            return child;
          }
          if (frame != null) {
            return child;
          }
          return widget.placeWidget ?? Container(height: height);
        },
        errorBuilder: (context, error, stackTrace) {
          // 本地文件加载失败，回退到网络图片
          return _buildNetworkImage();
        },
      );
      ;
    }

    // 没有本地路径，使用网络图片
    return _buildNetworkImage();
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

// class RubyProvider extends ImageProvider{
//   @override
//   ImageStreamCompleter load(Object key, Future<Codec> Function(Uint8List bytes, {bool allowUpscaling, int cacheHeight, int cacheWidth}) decode) {
//     // TODO: implement load
//     throw UnimplementedError();
//   }
//
//   @override
//   Future<Object> obtainKey(ImageConfiguration configuration) {
//     // TODO: implement obtainKey
//     throw UnimplementedError();
//   }
// }
