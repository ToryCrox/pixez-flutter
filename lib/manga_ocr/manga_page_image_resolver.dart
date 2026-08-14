import 'dart:io';

import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/custom/log.dart';

abstract interface class MangaPageImageResolver {
  Future<String?> resolve({String? localPath, required String imageUrl});
}

/// 将页面当前使用的本地文件或 Pixiv 图片缓存解析为 helper 可读取的路径。
class PixivMangaPageImageResolver implements MangaPageImageResolver {
  const PixivMangaPageImageResolver();

  @override
  Future<String?> resolve({String? localPath, required String imageUrl}) async {
    if (localPath != null && await File(localPath).exists()) {
      Log.d(() => '漫画 OCR 使用本地图片: $localPath');
      return localPath;
    }
    if (imageUrl.isEmpty) {
      Log.w('漫画 OCR 无法解析图片：图片 URL 为空');
      return null;
    }

    final cached = await pixivCacheManager.getFileFromCache(imageUrl);
    if (cached != null && await cached.file.exists()) {
      Log.d(() => '漫画 OCR 使用图片缓存: ${cached.file.path}');
      return cached.file.path;
    }

    try {
      Log.i('漫画 OCR 图片缓存未命中，开始下载当前页');
      final downloaded = await pixivCacheManager.getSingleFile(
        imageUrl,
        headers: Hoster.header(url: imageUrl),
      );
      if (await downloaded.exists()) return downloaded.path;
      Log.w('漫画 OCR 图片下载后文件不存在');
      return null;
    } catch (error, stackTrace) {
      Log.e('漫画 OCR 图片解析失败', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }
}
