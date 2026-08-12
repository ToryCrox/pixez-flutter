import 'dart:io';

import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/er/hoster.dart';

abstract interface class MangaPageImageResolver {
  Future<String?> resolve({String? localPath, required String imageUrl});
}

/// 将页面当前使用的本地文件或 Pixiv 图片缓存解析为 helper 可读取的路径。
class PixivMangaPageImageResolver implements MangaPageImageResolver {
  const PixivMangaPageImageResolver();

  @override
  Future<String?> resolve({String? localPath, required String imageUrl}) async {
    if (localPath != null && await File(localPath).exists()) {
      return localPath;
    }
    if (imageUrl.isEmpty) return null;

    final cached = await pixivCacheManager.getFileFromCache(imageUrl);
    if (cached != null && await cached.file.exists()) return cached.file.path;

    final downloaded = await pixivCacheManager.getSingleFile(
      imageUrl,
      headers: Hoster.header(url: imageUrl),
    );
    return await downloaded.exists() ? downloaded.path : null;
  }
}
