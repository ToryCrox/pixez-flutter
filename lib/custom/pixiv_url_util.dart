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

class PixivUrlUtil {
  PixivUrlUtil._();

  /// Pixiv 图片服务器前缀
  static const String pxImgHost = 'https://i.pximg.net';

  /// 占位符（用于替换 URL 前缀，确保压缩/解压完全匹配）
  static const String pxImgPlaceholder = r'$PX$';

  /// Pixiv 原图 URL 前缀
  static const String pxImgOriginalPrefix =
      'https://i.pximg.net/img-original/img';

  /// 占位符（用于替换 URL 前缀，节约数据库空间）
  static const String pxImgOriginalPlaceholder = r'$PX_IMG$';

  /// 压缩 JSON 字符串，将 Pixiv 图片 URL 前缀替换为占位符
  static String compressPxUrl(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(pxImgHost, pxImgPlaceholder);
  }

  /// 解压缩 JSON 字符串，将占位符还原为 Pixiv 图片 URL 前缀
  static String decompressPxUrl(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(pxImgPlaceholder, pxImgHost);
  }

  /// 压缩原图 URL，将 Pixiv 原图前缀替换为占位符
  static String compressOriginalUrl(String url) {
    if (url.startsWith(pxImgOriginalPrefix)) {
      return url.replaceFirst(pxImgOriginalPrefix, pxImgOriginalPlaceholder);
    }
    return url;
  }

  /// 解压缩原图 URL，将占位符还原为 Pixiv 原图前缀
  static String decompressOriginalUrl(String url) {
    if (url.startsWith(pxImgOriginalPlaceholder)) {
      return url.replaceFirst(pxImgOriginalPlaceholder, pxImgOriginalPrefix);
    }
    return url;
  }

  /// 判断是否为 Pixiv 原图 URL
  static bool isPixivOriginalUrl(String url) {
    return url.startsWith(pxImgOriginalPrefix);
  }
}
