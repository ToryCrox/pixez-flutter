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

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:pixez/custom/pixiv_url_util.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/ugoira_metadata_response.dart';
import 'package:pixez/platform/macos_file_access.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../custom/log.dart';

/// 支持的图片后缀名
const kImageExtensions = ['.webp', '.jpg', '.png', '.gif', '.jpeg'];

// 下载的插画记录
class DownloadedIllust {

  final int illustId;
  final int userId;
  final String userName;
  final String title;
  final String type;
  final String caption;
  final String createDate;
  final int pageCount;
  final int width;
  final int height;
  final int sanityLevel;
  final int xRestrict;
  final int totalView;
  final int totalBookmarks;
  final String tags; // JSON格式存储
  final String relativePath; // 相对目录路径
  final int downloadTime; // 下载时间戳
  final String _illustJson; // 完整Illusts JSON（私有）
  final String imageUrlsJson; // imageUrls 的 JSON 字符串
  final String ugoiraMetadataJson; // UgoiraMetadata 的 JSON 字符串

  // Getter 用于数据库序列化
  String get illustJson => _illustJson;

  /// 判断是否为动图
  bool get isUgoira => type == 'ugoira';

  DownloadedIllust({
    required this.illustId,
    required this.userId,
    required this.userName,
    required this.title,
    required this.type,
    required this.caption,
    required this.createDate,
    required this.pageCount,
    required this.width,
    required this.height,
    required this.sanityLevel,
    required this.xRestrict,
    required this.totalView,
    required this.totalBookmarks,
    required this.tags,
    required this.relativePath,
    required this.downloadTime,
    required String illustJson,
    this.imageUrlsJson = '',
    this.ugoiraMetadataJson = '',
  }) : _illustJson = illustJson;

  /// 从 imageUrlsJson 解析 ImageUrls 对象
  ImageUrls getImageUrls() {
    if (imageUrlsJson.isEmpty) {
      return const ImageUrls();
    }
    return ImageUrls.fromJson(
        TypeUtil.parseMap(PixivUrlUtil.decompressPxUrl(imageUrlsJson)));
  }

  /// 解析 UgoiraMetadata
  UgoiraMetadata? getUgoiraMetadata() {
    if (!isUgoira || ugoiraMetadataJson.isEmpty) return null;
    try {
      final json = TypeUtil.parseMap(PixivUrlUtil.decompressPxUrl(ugoiraMetadataJson));
      return UgoiraMetadata.fromJson(json);
    } catch (e) {
      Log.e('解析 UgoiraMetadata 失败: $e');
      return null;
    }
  }

  /// 获取 frames 列表
  List<Frame>? getUgoiraFrames() {
    return getUgoiraMetadata()?.frames;
  }

  factory DownloadedIllust.fromIllusts(
    Illusts illusts,
    String relativePath, {
    int? downloadTime,
    String? ugoiraMetadataJson,
  }) {
    // 使用 copyWith 将需要移除的字段设置为空/默认值
    final optimizedIllusts = illusts.copyWith(
      id: 0,
      title: '',
      type: '',
      caption: '',
      createDate: '',
      pageCount: 0,
      width: 0,
      height: 0,
      sanityLevel: 0,
      xRestrict: 0,
      totalView: 0,
      totalBookmarks: 0,
      tags: [],
      imageUrls: const ImageUrls(), // 将 imageUrls 设为空，从 illustJson 中移除
      user: illusts.user.copyWith(
        id: 0,
        name: '',
      ),
    );

    // 转换成 Map
    final optimizedJson = optimizedIllusts.toJson();

    // 使用 shrinkMap 移除空值，进一步优化 JSON 大小
    final shrunkJson = TypeUtil.shrinkMap(optimizedJson, copy: false);

    return DownloadedIllust(
      illustId: illusts.id,
      userId: illusts.user.id,
      userName: illusts.user.name,
      title: illusts.title,
      type: illusts.type,
      caption: illusts.caption,
      createDate: illusts.createDate,
      pageCount: illusts.pageCount,
      width: illusts.width,
      height: illusts.height,
      sanityLevel: illusts.sanityLevel,
      xRestrict: illusts.xRestrict,
      totalView: illusts.totalView,
      totalBookmarks: illusts.totalBookmarks,
      tags: TypeUtil.parseJsonString(
          illusts.tags.map((t) => TypeUtil.shrinkMap(t.toJson())).toList()),
      relativePath: relativePath,
      downloadTime: downloadTime ?? DateTime.now().millisecondsSinceEpoch,
      illustJson: PixivUrlUtil.compressPxUrl(TypeUtil.parseJsonString(shrunkJson)),
      imageUrlsJson: PixivUrlUtil.compressPxUrl(
          TypeUtil.parseJsonString(illusts.imageUrls.toJson())),
      ugoiraMetadataJson: ugoiraMetadataJson ?? '',
    );
  }

  factory DownloadedIllust.fromJson(Map<String, dynamic> json) {
    return DownloadedIllust(
      illustId: TypeUtil.parseInt(json[DownloadedIllustColumns.illustId]),
      userId: TypeUtil.parseInt(json[DownloadedIllustColumns.userId]),
      userName: TypeUtil.parseString(json[DownloadedIllustColumns.userName]),
      title: TypeUtil.parseString(json[DownloadedIllustColumns.title]),
      type: TypeUtil.parseString(json[DownloadedIllustColumns.type]),
      caption: TypeUtil.parseString(json[DownloadedIllustColumns.caption]),
      createDate: TypeUtil.parseString(json[DownloadedIllustColumns.createDate]),
      pageCount: TypeUtil.parseInt(json[DownloadedIllustColumns.pageCount]),
      width: TypeUtil.parseInt(json[DownloadedIllustColumns.width]),
      height: TypeUtil.parseInt(json[DownloadedIllustColumns.height]),
      sanityLevel: TypeUtil.parseInt(json[DownloadedIllustColumns.sanityLevel]),
      xRestrict: TypeUtil.parseInt(json[DownloadedIllustColumns.xRestrict]),
      totalView: TypeUtil.parseInt(json[DownloadedIllustColumns.totalView]),
      totalBookmarks:
          TypeUtil.parseInt(json[DownloadedIllustColumns.totalBookmarks]),
      tags: TypeUtil.parseString(json[DownloadedIllustColumns.tags]),
      relativePath:
          TypeUtil.parseString(json[DownloadedIllustColumns.relativePath]),
      downloadTime:
          TypeUtil.parseInt(json[DownloadedIllustColumns.downloadTime]),
      illustJson: TypeUtil.gzipDecodeString(
          TypeUtil.parseString(json[DownloadedIllustColumns.illustJson])),
      imageUrlsJson: TypeUtil.parseString(
          json[DownloadedIllustColumns.imageUrlsJson]), // 兼容旧数据
      ugoiraMetadataJson: TypeUtil.parseString(
          json[DownloadedIllustColumns.ugoiraMetadataJson]), // 兼容旧数据
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data[DownloadedIllustColumns.illustId] = illustId;
    data[DownloadedIllustColumns.userId] = userId;
    data[DownloadedIllustColumns.userName] = userName;
    data[DownloadedIllustColumns.title] = title;
    data[DownloadedIllustColumns.type] = type;
    data[DownloadedIllustColumns.caption] = caption;
    data[DownloadedIllustColumns.createDate] = createDate;
    data[DownloadedIllustColumns.pageCount] = pageCount;
    data[DownloadedIllustColumns.width] = width;
    data[DownloadedIllustColumns.height] = height;
    data[DownloadedIllustColumns.sanityLevel] = sanityLevel;
    data[DownloadedIllustColumns.xRestrict] = xRestrict;
    data[DownloadedIllustColumns.totalView] = totalView;
    data[DownloadedIllustColumns.totalBookmarks] = totalBookmarks;
    data[DownloadedIllustColumns.tags] = tags;
    data[DownloadedIllustColumns.relativePath] = relativePath;
    data[DownloadedIllustColumns.downloadTime] = downloadTime;
    data[DownloadedIllustColumns.illustJson] =
        TypeUtil.gzipEncodeString(illustJson);
    data[DownloadedIllustColumns.imageUrlsJson] = imageUrlsJson;
    data[DownloadedIllustColumns.ugoiraMetadataJson] = ugoiraMetadataJson;
    return data;
  }

  Illusts toIllusts() {
    // 使用 TypeUtil.parseMap 安全地将字符串转换为 Map（先解压 URL 前缀）
    final json = TypeUtil.parseMap(PixivUrlUtil.decompressPxUrl(_illustJson));

    // 先从 illustJson 转换成 Illusts（即使 json 为空也能创建默认对象）
    final baseIllusts = Illusts.fromJson(json);

    // 解析 imageUrls：优先从独立字段读取，兼容旧数据回退到 illustJson
    ImageUrls imageUrls;
    if (imageUrlsJson.isNotEmpty) {
      imageUrls = ImageUrls.fromJson(
          TypeUtil.parseMap(PixivUrlUtil.decompressPxUrl(imageUrlsJson)));
    } else {
      // 兼容旧数据：从 illustJson 中读取
      imageUrls = baseIllusts.imageUrls;
    }

    // 使用 copyWith 从表字段赋值，避免硬编码 map 字段
    // metaPages 和 metaSinglePage 从 baseIllusts 保留（它们已经保存在 illustJson 中）
    return baseIllusts.copyWith(
      id: illustId,
      title: title,
      type: type,
      caption: caption,
      createDate: createDate,
      pageCount: pageCount,
      width: width,
      height: height,
      sanityLevel: sanityLevel,
      xRestrict: xRestrict,
      totalView: totalView,
      totalBookmarks: totalBookmarks,
      tags: getTagsList(),
      imageUrls: imageUrls,
      user: baseIllusts.user.copyWith(
        id: userId,
        name: userName,
      ),
    );
  }

  List<Tags> getTagsList() {
    return TypeUtil.parseList(tags, (e) => Tags.fromMap(TypeUtil.parseMap(e)));
  }
}

/// 本地图片信息，包含路径和宽高
class LocalImageInfo {
  final String path;
  final int? width;
  final int? height;
  final int? fileSize;

  LocalImageInfo({
    required this.path,
    this.width,
    this.height,
    this.fileSize,
  });

  /// 获取宽高比（width / height），如果宽高未知则返回 null
  double? get aspectRatio {
    if (width != null && height != null && height! > 0) {
      return width! / height!;
    }
    return null;
  }

  @override
  String toString() {
    return 'LocalImageInfo{path: $path, width: $width, height: $height, fileSize: $fileSize}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalImageInfo &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          width == other.width &&
          height == other.height &&
          fileSize == other.fileSize;

  @override
  int get hashCode => Object.hash(path, width, height, fileSize);
}

// 下载的图片记录
class DownloadedImage {

  final int illustId;
  final int part;
  final String fileName;
  final String extension;
  final int fileSize;
  final String originalUrl;
  final String relativePath;
  final int? width; // 图片宽度
  final int? height; // 图片高度

  DownloadedImage({
    required this.illustId,
    required this.part,
    required this.fileName,
    required this.extension,
    required this.fileSize,
    required this.originalUrl,
    required this.relativePath,
    this.width,
    this.height,
  });

  factory DownloadedImage.fromJson(Map<String, dynamic> json) {
    // 从数据库读取时解压 URL
    final compressedUrl =
        TypeUtil.parseString(json[DownloadedImageColumns.originalUrl]);
    return DownloadedImage(
      illustId: TypeUtil.parseInt(json[DownloadedImageColumns.illustId]),
      part: TypeUtil.parseInt(json[DownloadedImageColumns.part]),
      fileName: TypeUtil.parseString(json[DownloadedImageColumns.fileName]),
      extension: TypeUtil.parseString(json[DownloadedImageColumns.extension]),
      fileSize: TypeUtil.parseInt(json[DownloadedImageColumns.fileSize]),
      originalUrl: PixivUrlUtil.decompressOriginalUrl(compressedUrl),
      relativePath:
          TypeUtil.parseString(json[DownloadedImageColumns.relativePath]),
      width: TypeUtil.parseInt(json[DownloadedImageColumns.width]),
      height: TypeUtil.parseInt(json[DownloadedImageColumns.height]),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data[DownloadedImageColumns.illustId] = illustId;
    data[DownloadedImageColumns.part] = part;
    data[DownloadedImageColumns.fileName] = fileName;
    data[DownloadedImageColumns.extension] = extension;
    data[DownloadedImageColumns.fileSize] = fileSize;
    // 写入数据库时压缩 URL
    data[DownloadedImageColumns.originalUrl] =
        PixivUrlUtil.compressOriginalUrl(originalUrl);
    data[DownloadedImageColumns.relativePath] = relativePath;
    data[DownloadedImageColumns.width] = width;
    data[DownloadedImageColumns.height] = height;
    return data;
  }

  String getFullFileName() => '$fileName$extension';

  /// 获取图片宽高比（width / height），如果宽高未知则返回 null
  double? get aspectRatio {
    if (width != null && height != null && height! > 0) {
      return width! / height!;
    }
    return null;
  }
}

// 表名和列名常量
class DownloadedIllustColumns {
  static const String tableName = 'downloaded_illusts';
  static const String id = 'id';
  static const String illustId = 'illust_id';
  static const String userId = 'user_id';
  static const String userName = 'user_name';
  static const String title = 'title';
  static const String type = 'type';
  static const String caption = 'caption';
  static const String createDate = 'create_date';
  static const String pageCount = 'page_count';
  static const String width = 'width';
  static const String height = 'height';
  static const String sanityLevel = 'sanity_level';
  static const String xRestrict = 'x_restrict';
  static const String totalView = 'total_view';
  static const String totalBookmarks = 'total_bookmarks';
  static const String tags = 'tags';
  static const String relativePath = 'relative_path';
  static const String downloadTime = 'download_time';
  static const String illustJson = 'illust_json';
  static const String imageUrlsJson = 'image_urls_json'; // 新增：imageUrls JSON
  static const String ugoiraMetadataJson = 'ugoira_metadata_json'; // 新增：UgoiraMetadata JSON
}

class DownloadedImageColumns {
  static const String tableName = 'downloaded_images';
  static const String id = 'id';
  static const String illustId = 'illust_id';
  static const String part = 'part';
  static const String fileName = 'file_name';
  static const String extension = 'extension';
  static const String fileSize = 'file_size';
  static const String originalUrl = 'original_url';
  static const String relativePath = 'relative_path';
  static const String width = 'width';
  static const String height = 'height';
}

// 待下载任务记录
class PendingDownloadColumns {
  static const String tableName = 'pending_downloads';
  static const String id = 'id';
  static const String part = 'part';
  static const String url = 'url';
  static const String illustJson = 'illust_json';
  static const String createTime = 'create_time';
  static const String status = 'status'; // 0=pending, 1=downloading, 2=failed
}

class DownloadedTagsColumns {
  static const String tableName = 'downloaded_tags';
  static const String id = 'id';
  static const String name = 'name';
  static const String translatedName = 'translated_name';
  static const String customTranslatedName = 'custom_translated_name';
  static const String category = 'category';
  static const String isBookmarked = 'is_bookmarked';
  static const String displayOrder = 'display_order';
  static const String lastUsedTime = 'last_used_time';
  static const String count = 'count';
  static const String exampleIllusts = 'example_illusts';
  static const String referencedTagId = 'referenced_tag_id';
}

class DownloadedIllustTagsColumns {
  static const String tableName = 'downloaded_illust_tags';
  static const String illustId = 'illust_id';
  static const String tagId = 'tag_id';
  static const String source = 'source'; // 0:原始, 1:用户添加
}

class DownloadedAuthorColumns {
  static const String tableName = 'downloaded_authors';
  static const String userId = 'user_id';
  static const String userName = 'user_name';
  static const String profileImageUrl = 'profile_image_url';
  static const String illustCount = 'illust_count';
  static const String totalFileSize = 'total_file_size';
  static const String lastDownloadTime = 'last_download_time';
  static const String lastUpdateTime = 'last_update_time';
}

class PendingDownload {
  final String id;
  final int part;
  final String url;
  final String illustJson;
  final int createTime;
  final String status;

  PendingDownload({
    required this.id,
    required this.part,
    required this.url,
    required this.illustJson,
    required this.createTime,
    required this.status,
  });

  factory PendingDownload.fromJson(Map<String, dynamic> json) {
    return PendingDownload(
      id: TypeUtil.parseString(json[PendingDownloadColumns.id]),
      part: TypeUtil.parseInt(json[PendingDownloadColumns.part]),
      url: TypeUtil.parseString(json[PendingDownloadColumns.url]),
      illustJson: TypeUtil.parseString(json[PendingDownloadColumns.illustJson]),
      createTime: TypeUtil.parseInt(json[PendingDownloadColumns.createTime]),
      status: TypeUtil.parseString(json[PendingDownloadColumns.status], 'pending'),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data[PendingDownloadColumns.id] = id;
    data[PendingDownloadColumns.part] = part;
    data[PendingDownloadColumns.url] = url;
    data[PendingDownloadColumns.illustJson] = illustJson;
    data[PendingDownloadColumns.createTime] = createTime;
    data[PendingDownloadColumns.status] = status;
    return data;
  }
}

// 下载的作者记录
class DownloadedAuthor {
  int userId;
  String userName;
  String? profileImageUrl;
  int illustCount;
  int totalFileSize;
  int lastDownloadTime;
  int lastUpdateTime;

  DownloadedAuthor({
    required this.userId,
    required this.userName,
    this.profileImageUrl,
    required this.illustCount,
    required this.totalFileSize,
    required this.lastDownloadTime,
    required this.lastUpdateTime,
  });

  factory DownloadedAuthor.fromJson(Map<String, dynamic> json) {
    return DownloadedAuthor(
      userId: TypeUtil.parseInt(json[DownloadedAuthorColumns.userId]),
      userName: TypeUtil.parseString(json[DownloadedAuthorColumns.userName]),
      profileImageUrl: PixivUrlUtil.decompressPxUrl(
          TypeUtil.parseString(json[DownloadedAuthorColumns.profileImageUrl])),
      illustCount:
          TypeUtil.parseInt(json[DownloadedAuthorColumns.illustCount]),
      totalFileSize:
          TypeUtil.parseInt(json[DownloadedAuthorColumns.totalFileSize]),
      lastDownloadTime:
          TypeUtil.parseInt(json[DownloadedAuthorColumns.lastDownloadTime]),
      lastUpdateTime:
          TypeUtil.parseInt(json[DownloadedAuthorColumns.lastUpdateTime]),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data[DownloadedAuthorColumns.userId] = userId;
    data[DownloadedAuthorColumns.userName] = userName;
    if (profileImageUrl != null) {
      data[DownloadedAuthorColumns.profileImageUrl] =
          PixivUrlUtil.compressPxUrl(profileImageUrl!);
    }
    data[DownloadedAuthorColumns.illustCount] = illustCount;
    data[DownloadedAuthorColumns.totalFileSize] = totalFileSize;
    data[DownloadedAuthorColumns.lastDownloadTime] = lastDownloadTime;
    data[DownloadedAuthorColumns.lastUpdateTime] = lastUpdateTime;
    return data;
  }
}

enum TagCategory {
  uncategorized(0, '未分类', null),
  work(1, '作品', Colors.blue),
  character(2, '角色', Colors.pink),
  feature(6, '特点', Colors.green),
  general(4, '通用', null),
  meta(5, '元数据', Colors.purple);

  final int value;
  final String label;
  final Color? color;

  const TagCategory(this.value, this.label, this.color);

  static TagCategory fromValue(int value) {
    return TagCategory.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TagCategory.uncategorized,
    );
  }
}

class DownloadedTag {
  final int id;
  final String name;
  final String translatedName;
  final int category;
  final String? customTranslatedName;
  final int count;
  final bool isBookmarked;
  final int displayOrder;
  final int? lastUsedTime;
  final String exampleIllusts;
  final int? referencedTagId;

  DownloadedTag({
    required this.id,
    required this.name,
    this.translatedName = '',
    this.category = 0,
    this.customTranslatedName,
    this.count = 0,
    this.isBookmarked = false,
    this.displayOrder = 0,
    this.lastUsedTime,
    this.exampleIllusts = '',
    this.referencedTagId,
  });

  String get displayName =>
      (customTranslatedName != null && customTranslatedName!.isNotEmpty)
          ? customTranslatedName!
          : (translatedName.isNotEmpty)
              ? translatedName
              : name;

  TagCategory get categoryEnum => TagCategory.fromValue(category);
  
  List<int> get exampleIllustIds {
    if (exampleIllusts.isEmpty) return [];
    return exampleIllusts.split(',').map((e) => int.tryParse(e)).whereType<int>().toList();
  }
  
  factory DownloadedTag.fromJson(Map<String, dynamic> json) {
    return DownloadedTag(
      id: TypeUtil.parseInt(json[DownloadedTagsColumns.id]),
      name: TypeUtil.parseString(json[DownloadedTagsColumns.name]),
      translatedName:
          TypeUtil.parseString(json[DownloadedTagsColumns.translatedName]),
      customTranslatedName:
          json[DownloadedTagsColumns.customTranslatedName] as String?,
      category: TypeUtil.parseInt(json[DownloadedTagsColumns.category]),
      isBookmarked:
          TypeUtil.parseInt(json[DownloadedTagsColumns.isBookmarked]) == 1,
      displayOrder: TypeUtil.parseInt(json[DownloadedTagsColumns.displayOrder]),
      lastUsedTime: json[DownloadedTagsColumns.lastUsedTime] as int?,
      count: TypeUtil.parseInt(json[DownloadedTagsColumns.count]),
      exampleIllusts: TypeUtil.parseString(json[DownloadedTagsColumns.exampleIllusts]),
      referencedTagId: json[DownloadedTagsColumns.referencedTagId] != null 
        ? TypeUtil.parseInt(json[DownloadedTagsColumns.referencedTagId]) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      DownloadedTagsColumns.id: id,
      DownloadedTagsColumns.name: name,
      DownloadedTagsColumns.translatedName: translatedName,
      DownloadedTagsColumns.category: category,
      DownloadedTagsColumns.customTranslatedName: customTranslatedName,
      DownloadedTagsColumns.count: count,
      DownloadedTagsColumns.isBookmarked: isBookmarked ? 1 : 0,
      DownloadedTagsColumns.displayOrder: displayOrder,
      DownloadedTagsColumns.lastUsedTime: lastUsedTime,
      DownloadedTagsColumns.exampleIllusts: exampleIllusts,
      DownloadedTagsColumns.referencedTagId: referencedTagId,
    };
  }

  DownloadedTag copyWith({
    int? id,
    String? name,
    String? translatedName,
    int? category,
    String? customTranslatedName,
    int? count,
    bool? isBookmarked,
    int? displayOrder,
    int? lastUsedTime,
    String? exampleIllusts,
    int? referencedTagId,
  }) {
    return DownloadedTag(
      id: id ?? this.id,
      name: name ?? this.name,
      translatedName: translatedName ?? this.translatedName,
      category: category ?? this.category,
      customTranslatedName: customTranslatedName ?? this.customTranslatedName,
      count: count ?? this.count,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      displayOrder: displayOrder ?? this.displayOrder,
      lastUsedTime: lastUsedTime ?? this.lastUsedTime,
      exampleIllusts: exampleIllusts ?? this.exampleIllusts,
      referencedTagId: referencedTagId ?? this.referencedTagId,
    );
  }
}

class IllustPreviewData {
  final int illustId;
  final String squareMediumUrl;

  const IllustPreviewData({required this.illustId, required this.squareMediumUrl});
}

class TagDisplayData {
    final DownloadedTag tag;
    final List<IllustPreviewData> previewIllusts;
    final bool hasEquivalentTags;
    
    TagDisplayData({
      required this.tag, 
      required this.previewIllusts, 
      this.hasEquivalentTags = false,
    });
}

// 数据库Provider
class DownloadDatabaseProvider {
  late Database db;
  /// 下载目录
  String? _downloadPath;
  String? _basePath;
  String? _coverPath;
  String? _ugoiraTempPath;
  String? _dbPath;

  String get downloadPath => _downloadPath ?? '';

  String get dbPathStr => _dbPath ?? '';

  String get coverPath => _coverPath ?? '';

  String get ugoiraTempPath => _ugoiraTempPath ?? '';

  Future<void> open(String basePath) async {
    /// 创建下载目录
    _basePath = basePath;
    _downloadPath = path.join(basePath, 'download');
    _coverPath = path.join(basePath, 'covers');
    _ugoiraTempPath = path.join(basePath, 'ugoira');
    _dbPath = path.join(basePath, 'download.db');
    String dbPath = _dbPath!;

    try {
      // macOS: 检查并请求外部存储访问权限
      if (Platform.isMacOS && MacOSFileAccessManager.isExternalVolume(downloadPath)) {
        Log.d(() => '🔐 检测到外部存储卷: $downloadPath');
        Log.d(() => '正在检查访问权限...');

        // 检查是否已有 bookmark（支持下载路径本身或其任意父目录）
        bool hasBookmark = await MacOSFileAccessManager.hasBookmark(downloadPath);

        if (!hasBookmark) {
          Log.w(() => '⚠️  未找到访问权限，需要用户授权');
          Log.i(() => '提示: 请在文件选择器中选择下载目录或其父目录');
          Log.i(() => '     例如选择: $downloadPath');
          Log.i(() => '     或选择: ${MacOSFileAccessManager.getRootPath(downloadPath)}');

          final (success, selectedPath) = await MacOSFileAccessManager.requestDirectoryAccess();
          if (!success || selectedPath == null) {
            throw Exception('用户取消授权或授权失败');
          }

          // 验证选择的路径是下载路径的父目录
          if (!downloadPath.startsWith(selectedPath)) {
            throw Exception('选择的目录无效：必须是 $downloadPath 的父目录或本身');
          }

          Log.i(() => '✅ 用户已授权访问: $selectedPath');
        }

        // 开始访问外部存储（Swift 端会自动查找最匹配的父目录 bookmark）
        final accessGranted = await MacOSFileAccessManager.startAccessingPath(downloadPath);
        if (!accessGranted) {
          throw Exception('无法获取外部存储访问权限，请重新授权');
        }

        Log.i(() => '✅ 已获取外部存储访问权限');
      }
      
      // 确保目录存在
      final dir = Directory(downloadPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 确保下载目录存在
      final downloadDir = Directory(_downloadPath!);
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      // 检查数据库文件访问权限
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        // 尝试读取文件以验证访问权限
        try {
          await dbFile.open(mode: FileMode.read).then((f) => f.close());
        } catch (e) {
          Log.e(() => 'ERROR: 无法访问数据库文件 $dbPath', error: e);

          if (Platform.isMacOS && MacOSFileAccessManager.isExternalVolume(downloadPath)) {
            Log.e(() => '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
            Log.e(() => '⚠️  外部存储访问失败');
            Log.e(() => '可能的原因:');
            Log.e(() => '1. Security-Scoped Bookmark 已失效，需要重新授权');
            Log.e(() => '2. 外部存储卷已被卸载或路径变化');
            Log.e(() => '3. 文件系统权限不足');
            Log.e(() => '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

            // 尝试清除旧的 bookmark 并重新请求
            await MacOSFileAccessManager.clearBookmark(downloadPath);
            throw Exception('外部存储访问失败，请重新启动应用并重新授权');
          }

          rethrow;
        }
      }


      db = await openDatabase(
        dbPath,
        version: 11,
        onCreate: (Database db, int version) async {
          await db.execute('''
          CREATE TABLE ${DownloadedIllustColumns.tableName} (
            ${DownloadedIllustColumns.id} INTEGER PRIMARY KEY AUTOINCREMENT,
            ${DownloadedIllustColumns.illustId} INTEGER NOT NULL UNIQUE,
            ${DownloadedIllustColumns.userId} INTEGER NOT NULL,
            ${DownloadedIllustColumns.userName} TEXT NOT NULL,
            ${DownloadedIllustColumns.title} TEXT NOT NULL,
            ${DownloadedIllustColumns.type} TEXT NOT NULL,
            ${DownloadedIllustColumns.caption} TEXT,
            ${DownloadedIllustColumns.createDate} TEXT NOT NULL,
            ${DownloadedIllustColumns.pageCount} INTEGER NOT NULL,
            ${DownloadedIllustColumns.width} INTEGER NOT NULL,
            ${DownloadedIllustColumns.height} INTEGER NOT NULL,
            ${DownloadedIllustColumns.sanityLevel} INTEGER NOT NULL,
            ${DownloadedIllustColumns.xRestrict} INTEGER NOT NULL,
            ${DownloadedIllustColumns.totalView} INTEGER NOT NULL,
            ${DownloadedIllustColumns.totalBookmarks} INTEGER NOT NULL,
            ${DownloadedIllustColumns.tags} TEXT NOT NULL,
            ${DownloadedIllustColumns.relativePath} TEXT NOT NULL,
            ${DownloadedIllustColumns.downloadTime} INTEGER NOT NULL,
            ${DownloadedIllustColumns.illustJson} TEXT NOT NULL,
            ${DownloadedIllustColumns.imageUrlsJson} TEXT NOT NULL DEFAULT '',
            ${DownloadedIllustColumns.ugoiraMetadataJson} TEXT NOT NULL DEFAULT ''
          )
        ''');

        await db.execute('''
          CREATE TABLE ${DownloadedImageColumns.tableName} (
            ${DownloadedImageColumns.id} INTEGER PRIMARY KEY AUTOINCREMENT,
            ${DownloadedImageColumns.illustId} INTEGER NOT NULL,
            ${DownloadedImageColumns.part} INTEGER NOT NULL,
            ${DownloadedImageColumns.fileName} TEXT NOT NULL,
            ${DownloadedImageColumns.extension} TEXT NOT NULL,
            ${DownloadedImageColumns.fileSize} INTEGER NOT NULL,
            ${DownloadedImageColumns.originalUrl} TEXT NOT NULL,
            ${DownloadedImageColumns.relativePath} TEXT NOT NULL,
            ${DownloadedImageColumns.width} INTEGER,
            ${DownloadedImageColumns.height} INTEGER,
            UNIQUE(${DownloadedImageColumns.illustId}, ${DownloadedImageColumns.part})
          )
        ''');

        // 创建待下载任务表
        await db.execute('''
          CREATE TABLE ${PendingDownloadColumns.tableName} (
            ${PendingDownloadColumns.id} TEXT PRIMARY KEY,
            ${PendingDownloadColumns.part} INTEGER NOT NULL,
            ${PendingDownloadColumns.url} TEXT NOT NULL,
            ${PendingDownloadColumns.illustJson} TEXT NOT NULL,
            ${PendingDownloadColumns.createTime} INTEGER NOT NULL,
            ${PendingDownloadColumns.status} TEXT NOT NULL DEFAULT 'pending'
          )
        ''');

        // 创建作者表
        await db.execute('''
          CREATE TABLE ${DownloadedAuthorColumns.tableName} (
            ${DownloadedAuthorColumns.userId} INTEGER PRIMARY KEY,
            ${DownloadedAuthorColumns.userName} TEXT NOT NULL,
            ${DownloadedAuthorColumns.profileImageUrl} TEXT,
            ${DownloadedAuthorColumns.illustCount} INTEGER DEFAULT 0,
            ${DownloadedAuthorColumns.totalFileSize} INTEGER DEFAULT 0,
            ${DownloadedAuthorColumns.lastDownloadTime} INTEGER,
            ${DownloadedAuthorColumns.lastUpdateTime} INTEGER
          )
        ''');

        // 创建标签管理表
        await db.execute('''
          CREATE TABLE ${DownloadedTagsColumns.tableName} (
             ${DownloadedTagsColumns.id} INTEGER PRIMARY KEY AUTOINCREMENT,
             ${DownloadedTagsColumns.name} TEXT NOT NULL UNIQUE,
             ${DownloadedTagsColumns.translatedName} TEXT,
             ${DownloadedTagsColumns.customTranslatedName} TEXT,
             ${DownloadedTagsColumns.category} INTEGER DEFAULT 0,
             ${DownloadedTagsColumns.isBookmarked} INTEGER DEFAULT 0,
             ${DownloadedTagsColumns.displayOrder} INTEGER DEFAULT 0,
             ${DownloadedTagsColumns.lastUsedTime} INTEGER,
             ${DownloadedTagsColumns.count} INTEGER DEFAULT 0,
             ${DownloadedTagsColumns.exampleIllusts} TEXT,
             ${DownloadedTagsColumns.referencedTagId} INTEGER
          )
        ''');

        // 创建标签-作品关联表
        await db.execute('''
          CREATE TABLE ${DownloadedIllustTagsColumns.tableName} (
             ${DownloadedIllustTagsColumns.illustId} INTEGER NOT NULL,
             ${DownloadedIllustTagsColumns.tagId} INTEGER NOT NULL,
             ${DownloadedIllustTagsColumns.source} INTEGER DEFAULT 0,
             PRIMARY KEY (${DownloadedIllustTagsColumns.illustId}, ${DownloadedIllustTagsColumns.tagId})
          )
        ''');

        // 创建索引
        await db.execute('''
          CREATE INDEX idx_illust_user ON ${DownloadedIllustColumns.tableName}(${DownloadedIllustColumns.userId})
        ''');
        await db.execute('''
          CREATE INDEX idx_image_illust ON ${DownloadedImageColumns.tableName}(${DownloadedImageColumns.illustId})
        ''');
        // 排序字段索引
        await db.execute('''
          CREATE INDEX idx_illust_download_time ON ${DownloadedIllustColumns.tableName}(${DownloadedIllustColumns.downloadTime})
        ''');
        await db.execute('''
          CREATE INDEX idx_illust_create_date ON ${DownloadedIllustColumns.tableName}(${DownloadedIllustColumns.createDate})
        ''');
        // 作者表排序字段索引
        await db.execute('''
          CREATE INDEX idx_author_last_download_time ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.lastDownloadTime})
        ''');
        await db.execute('''
          CREATE INDEX idx_author_user_name ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.userName})
        ''');
        await db.execute('''
          CREATE INDEX idx_author_illust_count ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.illustCount})
        ''');
        await db.execute('''
          CREATE INDEX idx_author_total_file_size ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.totalFileSize})
        ''');
        // 标签表索引
        await db.execute('''
          CREATE INDEX idx_tags_category ON ${DownloadedTagsColumns.tableName}(${DownloadedTagsColumns.category})
        ''');
        await db.execute('''
          CREATE INDEX idx_tags_display_order ON ${DownloadedTagsColumns.tableName}(${DownloadedTagsColumns.displayOrder})
        ''');
        await db.execute('''
          CREATE INDEX idx_tags_referenced_tag ON ${DownloadedTagsColumns.tableName}(${DownloadedTagsColumns.referencedTagId})
        ''');
        // 关联表索引
        await db.execute('''
          CREATE INDEX idx_illust_tags_tag ON ${DownloadedIllustTagsColumns.tableName}(${DownloadedIllustTagsColumns.tagId})
        ''');
        await db.execute('''
          CREATE INDEX idx_illust_tags_illust ON ${DownloadedIllustTagsColumns.tableName}(${DownloadedIllustTagsColumns.illustId})
        ''');

      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          // 添加待下载任务表
          await db.execute('''
            CREATE TABLE IF NOT EXISTS ${PendingDownloadColumns.tableName} (
              ${PendingDownloadColumns.id} TEXT PRIMARY KEY,
              ${PendingDownloadColumns.part} INTEGER NOT NULL,
              ${PendingDownloadColumns.url} TEXT NOT NULL,
              ${PendingDownloadColumns.illustJson} TEXT NOT NULL,
              ${PendingDownloadColumns.createTime} INTEGER NOT NULL,
              ${PendingDownloadColumns.status} TEXT NOT NULL DEFAULT 'pending'
            )
          ''');
        }
        if (oldVersion < 3) {
          // 为图片表添加宽高字段
          await db.execute('''
            ALTER TABLE ${DownloadedImageColumns.tableName} 
            ADD COLUMN ${DownloadedImageColumns.width} INTEGER
          ''');
          await db.execute('''
            ALTER TABLE ${DownloadedImageColumns.tableName} 
            ADD COLUMN ${DownloadedImageColumns.height} INTEGER
          ''');
        }
        if (oldVersion < 4) {
          // 创建作者表
          await db.execute('''
            CREATE TABLE IF NOT EXISTS ${DownloadedAuthorColumns.tableName} (
              ${DownloadedAuthorColumns.userId} INTEGER PRIMARY KEY,
              ${DownloadedAuthorColumns.userName} TEXT NOT NULL,
              ${DownloadedAuthorColumns.profileImageUrl} TEXT,
              ${DownloadedAuthorColumns.illustCount} INTEGER DEFAULT 0,
              ${DownloadedAuthorColumns.totalFileSize} INTEGER DEFAULT 0,
              ${DownloadedAuthorColumns.lastDownloadTime} INTEGER,
              ${DownloadedAuthorColumns.lastUpdateTime} INTEGER
            )
          ''');
          // 从现有数据生成作者表
          await _migrateAuthorsFromIllusts(db);
        }
        if (oldVersion < 5) {
          // 添加 image_urls_json 列
          await db.execute('''
            ALTER TABLE ${DownloadedIllustColumns.tableName}
            ADD COLUMN ${DownloadedIllustColumns.imageUrlsJson} TEXT NOT NULL DEFAULT ''
          ''');
        }
        if (oldVersion < 6) {
          // 添加排序字段索引以优化查询性能
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_illust_download_time ON ${DownloadedIllustColumns.tableName}(${DownloadedIllustColumns.downloadTime})
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_illust_create_date ON ${DownloadedIllustColumns.tableName}(${DownloadedIllustColumns.createDate})
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_author_total_file_size ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.totalFileSize})
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_author_user_name ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.userName})
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_author_illust_count ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.illustCount})
          ''');
        }
        if (oldVersion < 7) {
          // 添加 ugoira_metadata_json 列用于存储动图元数据
          await db.execute('''
            ALTER TABLE ${DownloadedIllustColumns.tableName}
            ADD COLUMN ${DownloadedIllustColumns.ugoiraMetadataJson} TEXT NOT NULL DEFAULT ''
          ''');
        }
        if (oldVersion < 8) {
          // 添加 total_file_size 索引以优化作者列表排序性能
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_author_total_file_size ON ${DownloadedAuthorColumns.tableName}(${DownloadedAuthorColumns.totalFileSize})
          ''');
        }
        if (oldVersion < 9) {
          // 创建标签管理表
          await db.execute('''
            CREATE TABLE IF NOT EXISTS ${DownloadedTagsColumns.tableName} (
               ${DownloadedTagsColumns.name} TEXT PRIMARY KEY,
               ${DownloadedTagsColumns.translatedName} TEXT,
               ${DownloadedTagsColumns.customTranslatedName} TEXT,
               ${DownloadedTagsColumns.category} INTEGER DEFAULT 0,
               ${DownloadedTagsColumns.isBookmarked} INTEGER DEFAULT 0,
               ${DownloadedTagsColumns.displayOrder} INTEGER DEFAULT 0,
               ${DownloadedTagsColumns.lastUsedTime} INTEGER
            )
          ''');

          // 创建标签-作品关联表
          await db.execute('''
            CREATE TABLE IF NOT EXISTS ${DownloadedIllustTagsColumns.tableName} (
               ${DownloadedIllustTagsColumns.illustId} INTEGER NOT NULL,
               'tag_name' TEXT NOT NULL,
               ${DownloadedIllustTagsColumns.source} INTEGER DEFAULT 0,
               PRIMARY KEY (${DownloadedIllustTagsColumns.illustId}, 'tag_name')
            )
          ''');

          // 标签表索引
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_tags_category ON ${DownloadedTagsColumns.tableName}(${DownloadedTagsColumns.category})
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_tags_display_order ON ${DownloadedTagsColumns.tableName}(${DownloadedTagsColumns.displayOrder})
          ''');
          // 关联表索引
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_illust_tags_tag ON ${DownloadedIllustTagsColumns.tableName}('tag_name')
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_illust_tags_illust ON ${DownloadedIllustTagsColumns.tableName}(${DownloadedIllustTagsColumns.illustId})
          ''');
        }
        if (oldVersion < 10) {
          // 重新创建标签相关表以更新结构
          await db.execute('DROP TABLE IF EXISTS ${DownloadedTagsColumns.tableName}');
          await db.execute('DROP TABLE IF EXISTS ${DownloadedIllustTagsColumns.tableName}');

          // 1. 创建新标签表
          await db.execute('''
            CREATE TABLE ${DownloadedTagsColumns.tableName} (
               ${DownloadedTagsColumns.id} INTEGER PRIMARY KEY AUTOINCREMENT,
               ${DownloadedTagsColumns.name} TEXT NOT NULL UNIQUE,
               ${DownloadedTagsColumns.translatedName} TEXT,
               ${DownloadedTagsColumns.customTranslatedName} TEXT,
               ${DownloadedTagsColumns.category} INTEGER DEFAULT 0,
               ${DownloadedTagsColumns.isBookmarked} INTEGER DEFAULT 0,
               ${DownloadedTagsColumns.displayOrder} INTEGER DEFAULT 0,
               ${DownloadedTagsColumns.lastUsedTime} INTEGER,
               ${DownloadedTagsColumns.count} INTEGER DEFAULT 0,
               ${DownloadedTagsColumns.exampleIllusts} TEXT DEFAULT ''
            )
          ''');

          // 2. 创建新关联表
          await db.execute('''
            CREATE TABLE ${DownloadedIllustTagsColumns.tableName} (
               ${DownloadedIllustTagsColumns.illustId} INTEGER NOT NULL,
               ${DownloadedIllustTagsColumns.tagId} INTEGER NOT NULL,
               ${DownloadedIllustTagsColumns.source} INTEGER DEFAULT 0,
               PRIMARY KEY (${DownloadedIllustTagsColumns.illustId}, ${DownloadedIllustTagsColumns.tagId})
            )
          ''');

          // 3. 创建索引
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_tags_category ON ${DownloadedTagsColumns.tableName}(${DownloadedTagsColumns.category})
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_tags_display_order ON ${DownloadedTagsColumns.tableName}(${DownloadedTagsColumns.displayOrder})
          ''');
          
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_illust_tags_tag ON ${DownloadedIllustTagsColumns.tableName}(${DownloadedIllustTagsColumns.tagId})
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_illust_tags_illust ON ${DownloadedIllustTagsColumns.tableName}(${DownloadedIllustTagsColumns.illustId})
          ''');
        }
        if (oldVersion < 11) {
          // 为标签表添加关联字段
          await db.execute('''
            ALTER TABLE ${DownloadedTagsColumns.tableName}
            ADD COLUMN ${DownloadedTagsColumns.referencedTagId} INTEGER
          ''');
          // 添加关联字段索引
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_tags_referenced_tag ON ${DownloadedTagsColumns.tableName}(${DownloadedTagsColumns.referencedTagId})
          ''');
        }
      },
    );
    } catch (e, stackTrace) {
      Log.e(() => '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Log.e(() => '数据库打开失败');
      Log.e(() => '数据库路径: $dbPath', error: e, stackTrace: stackTrace);
      Log.e(() => '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // 如果是外部存储卷，给出特别提示
      if (downloadPath.startsWith('/Volumes/')) {
        Log.w(() => '⚠️  检测到数据库位于外部存储卷');
        Log.w(() => '可能的解决方案:');
        Log.w(() => '1. 确保外部存储卷已正确挂载并可访问');
        Log.w(() => '2. 检查macOS应用权限设置，确保应用有访问外部存储的权限');
        Log.w(() => '3. 尝试将下载路径更改到应用目录或用户目录下');
        Log.w(() => '4. 如果问题持续，请尝试重新创建数据库');
        Log.w(() => '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      }

      rethrow;
    }
  }

  // ============ Illusts 操作 ============

  Future<DownloadedIllust> insertIllust(DownloadedIllust illust) async {
    await db.insert(
      DownloadedIllustColumns.tableName,
      illust.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Sync tags
    updateTagsRelations(illust);
    return illust;
  }

  Future<DownloadedIllust?> getIllustByIllustId(int illustId) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illustId],
    );
    if (maps.isNotEmpty) {
      return DownloadedIllust.fromJson(maps.first);
    }
    return null;
  }

  /// 更新插画信息（保留原有的 downloadTime 和 relativePath）
  Future<int> updateIllust(DownloadedIllust illust) async {
    final result = await db.update(
      DownloadedIllustColumns.tableName,
      illust.toJson(),
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illust.illustId],
    );
    // Sync tags
    updateTagsRelations(illust);
    return result;
  }
  
  /// 更新插画的标签关联信息
  Future<void> updateTagsRelations(DownloadedIllust illust) async {
    try {
      final illustsObj = illust.toIllusts();
      if (illustsObj.tags.isEmpty) return;

      final illustId = illust.illustId;
      final newTags = illustsObj.tags; // List<Tag>

      await db.transaction((txn) async {
        for (final tag in newTags) {
          // 1. 插入或获取 Tag ID
          // 尝试插入，IGNORE 如果已存在
          await txn.insert(
            DownloadedTagsColumns.tableName,
            {
              DownloadedTagsColumns.name: tag.name,
              DownloadedTagsColumns.translatedName: tag.translatedName,
              // 其他字段默认
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          
          // 查询获取 ID
          final List<Map<String, dynamic>> tagRows = await txn.query(
            DownloadedTagsColumns.tableName,
            columns: [DownloadedTagsColumns.id, DownloadedTagsColumns.count, DownloadedTagsColumns.exampleIllusts],
            where: '${DownloadedTagsColumns.name} = ?',
            whereArgs: [tag.name],
          );
          
          if (tagRows.isEmpty) continue; // Should not happen
          
          final tagId = tagRows.first[DownloadedTagsColumns.id] as int;
          final currentCount = tagRows.first[DownloadedTagsColumns.count] as int? ?? 0;
          final currentExamplesStr = tagRows.first[DownloadedTagsColumns.exampleIllusts] as String? ?? '';

          // 2. 插入关联关系
           // 检查是否已存在关联
          final existingRelation = await txn.query(
            DownloadedIllustTagsColumns.tableName,
            where: '${DownloadedIllustTagsColumns.illustId} = ? AND ${DownloadedIllustTagsColumns.tagId} = ?',
            whereArgs: [illustId, tagId],
          );

          if (existingRelation.isEmpty) {
            // 不存在则插入
            await txn.insert(
              DownloadedIllustTagsColumns.tableName,
              {
                DownloadedIllustTagsColumns.illustId: illustId,
                DownloadedIllustTagsColumns.tagId: tagId,
                DownloadedIllustTagsColumns.source: 0,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            
            // 3. 更新 Tag 的 count 和 exampleIllusts
            // 解析当前的 examples
            List<String> examples = currentExamplesStr.isNotEmpty 
                ? currentExamplesStr.split(',') 
                : [];
            
            // 如果不足3个，且当前ID不在列表中，则添加
            if (examples.length < 3 && !examples.contains(illustId.toString())) {
               examples.add(illustId.toString());
            }
            
            await txn.update(
              DownloadedTagsColumns.tableName,
              {
                DownloadedTagsColumns.count: currentCount + 1,
                DownloadedTagsColumns.exampleIllusts: examples.join(','),
                DownloadedTagsColumns.lastUsedTime: DateTime.now().millisecondsSinceEpoch,
              },
              where: '${DownloadedTagsColumns.id} = ?',
              whereArgs: [tagId],
            );
          } else {
             // 关联已存在，仅更新 lastUsedTime
             await txn.update(
              DownloadedTagsColumns.tableName,
              {
                DownloadedTagsColumns.lastUsedTime: DateTime.now().millisecondsSinceEpoch,
              },
              where: '${DownloadedTagsColumns.id} = ?',
              whereArgs: [tagId],
            );
          }
        }
      });
      
    } catch (e, s) {
      Log.e('Updated tags relations failed: $e', stackTrace: s);
    }
  }

  /// 更新动图元数据（用于修复损坏或丢失的元数据）
  Future<int> updateUgoiraMetadata(int illustId, String ugoiraMetadataJson) async {
    return await db.update(
      DownloadedIllustColumns.tableName,
      {DownloadedIllustColumns.ugoiraMetadataJson: ugoiraMetadataJson},
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illustId],
    );
  }

  Future<bool> isIllustDownloaded(int illustId) async {
    final result = await getIllustByIllustId(illustId);
    return result != null;
  }

  Future<List<DownloadedIllust>> getAllIllusts({
    int? limit,
    int? offset,
    bool desc = true,
    String? orderBy,
  }) async {
    // 如果按文件大小排序，需要使用 JOIN 查询
    if (orderBy != null && orderBy.contains('total_file_size')) {
      final orderDirection = orderBy.contains('DESC') ? 'DESC' : 'ASC';
      var query = '''
        SELECT di.*, COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
        FROM ${DownloadedIllustColumns.tableName} di
        LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
        GROUP BY di.${DownloadedIllustColumns.id}
        ORDER BY $orderBy
      ''';
      final args = <dynamic>[];
      if (limit != null) {
        query += ' LIMIT ?';
        args.add(limit);
      }
      if (offset != null) {
        query += ' OFFSET ?';
        args.add(offset);
      }
      final maps = await db.rawQuery(query, args);
      return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
    }

    final orderByClause = orderBy ??
        '${DownloadedIllustColumns.downloadTime} ${desc ? 'DESC' : 'ASC'}';
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      orderBy: orderByClause,
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  Future<List<DownloadedIllust>> getIllustsByUserId(
    int userId, {
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    // 如果按文件大小排序，需要使用 JOIN 查询
    if (orderBy != null && orderBy.contains('total_file_size')) {
      final orderDirection = orderBy.contains('DESC') ? 'DESC' : 'ASC';
      var query = '''
        SELECT di.*, COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
        FROM ${DownloadedIllustColumns.tableName} di
        LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
        WHERE di.${DownloadedIllustColumns.userId} = ?
        GROUP BY di.${DownloadedIllustColumns.id}
        ORDER BY $orderBy
      ''';
      final args = <dynamic>[userId];
      if (limit != null) {
        query += ' LIMIT ?';
        args.add(limit);
      }
      if (offset != null) {
        query += ' OFFSET ?';
        args.add(offset);
      }
      final maps = await db.rawQuery(query, args);
      return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
    }

    final orderByClause =
        orderBy ?? '${DownloadedIllustColumns.downloadTime} DESC';
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where: '${DownloadedIllustColumns.userId} = ?',
      whereArgs: [userId],
      orderBy: orderByClause,
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  Future<List<DownloadedIllust>> searchIllustsByTag(
    String tag, {
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    // 1. Find tag ID first
    final tagResults = await db.query(
      DownloadedTagsColumns.tableName,
      columns: [DownloadedTagsColumns.id],
      where: '${DownloadedTagsColumns.name} = ?',
      whereArgs: [tag],
    );
    
    if (tagResults.isEmpty) return [];
    
    final tagId = tagResults.first[DownloadedTagsColumns.id] as int;
    return await searchIllustsByTagId(tagId, limit: limit, offset: offset, orderBy: orderBy);
  }

  Future<List<DownloadedIllust>> searchIllustsByTagId(
    int tagId, {
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    // 如果按文件大小排序，需要使用 JOIN 查询
    if (orderBy != null && orderBy.contains('total_file_size')) {
      final orderDirection = orderBy.contains('DESC') ? 'DESC' : 'ASC';
      var query = '''
        SELECT di.*, COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
        FROM ${DownloadedIllustColumns.tableName} di
        LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedImageColumns.illustId} = img.${DownloadedImageColumns.illustId}
        INNER JOIN ${DownloadedIllustTagsColumns.tableName} dit ON di.${DownloadedIllustColumns.illustId} = dit.${DownloadedIllustTagsColumns.illustId}
        WHERE dit.${DownloadedIllustTagsColumns.tagId} = ?
        GROUP BY di.${DownloadedIllustColumns.id}
        ORDER BY total_file_size $orderDirection
      ''';
      final args = <dynamic>[tagId];
      if (limit != null) {
        query += ' LIMIT ?';
        args.add(limit);
      }
      if (offset != null) {
        query += ' OFFSET ?';
        args.add(offset);
      }
      final maps = await db.rawQuery(query, args);
      return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
    }

    final orderByClause =
        orderBy ?? 'di.${DownloadedIllustColumns.downloadTime} DESC';
    
    // 等价类查询逻辑：
    // 1. 找到该标签关联的主标签ID (可能是它自己，也可能是它引用的 referencedTagId)
    // 2. 找到所有引用该主标签的标签ID (包括主标签本身)
    // 3. 查询这些标签关联的作品
    var query = '''
      WITH TargetGroup AS (
        SELECT id, COALESCE(referenced_tag_id, id) as main_id 
        FROM ${DownloadedTagsColumns.tableName} 
        WHERE ${DownloadedTagsColumns.id} = ?
      )
      SELECT di.* 
      FROM ${DownloadedIllustColumns.tableName} di
      INNER JOIN ${DownloadedIllustTagsColumns.tableName} dit ON di.${DownloadedIllustColumns.illustId} = dit.${DownloadedIllustTagsColumns.illustId}
      WHERE dit.${DownloadedIllustTagsColumns.tagId} IN (
        SELECT id FROM ${DownloadedTagsColumns.tableName}
        WHERE id = (SELECT main_id FROM TargetGroup)
        OR ${DownloadedTagsColumns.referencedTagId} = (SELECT main_id FROM TargetGroup)
      )
      ORDER BY $orderByClause
    ''';
    
    final args = <dynamic>[tagId];
    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
    }
    if (offset != null) {
       query += ' OFFSET ?';
       args.add(offset);
    }
    
    final maps = await db.rawQuery(query, args);
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  /// 建立标签关联关系（等价标签）
  Future<void> associateTags(int primaryTagId, List<int> aliasTagIds) async {
    await db.transaction((txn) async {
      // 1. 更新所有别名标签，将其 referenced_tag_id 设为主标签 ID
      // 注意：如果被选作别名的标签本身已经是某些标签的主标签，暂时不处理深层嵌套，仅支持一级关联
      final placeholders = List.filled(aliasTagIds.length, '?').join(',');
      await txn.update(
        DownloadedTagsColumns.tableName,
        {DownloadedTagsColumns.referencedTagId: primaryTagId},
        where: '${DownloadedTagsColumns.id} IN ($placeholders)',
        whereArgs: aliasTagIds,
      );
      
      // 2. 将主标签的 referenced_tag_id 设为 NULL (确保其为主标签)
      await txn.update(
        DownloadedTagsColumns.tableName,
        {DownloadedTagsColumns.referencedTagId: null},
        where: '${DownloadedTagsColumns.id} = ?',
        whereArgs: [primaryTagId],
      );
    });
  }

  /// 解除标签关联关系
  Future<void> dissociateTags(List<int> tagIds) async {
    final placeholders = List.filled(tagIds.length, '?').join(',');
    await db.update(
      DownloadedTagsColumns.tableName,
      {DownloadedTagsColumns.referencedTagId: null},
      where: '${DownloadedTagsColumns.id} IN ($placeholders)',
      whereArgs: tagIds,
    );
  }

  /// 获取包含该标签在内的完整等价组
  Future<List<DownloadedTag>> getEquivalenceGroup(int tagId) async {
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      WITH TargetGroup AS (
        SELECT id, COALESCE(referenced_tag_id, id) as main_id 
        FROM ${DownloadedTagsColumns.tableName} 
        WHERE id = ?
      )
      SELECT * FROM ${DownloadedTagsColumns.tableName}
      WHERE id = (SELECT main_id FROM TargetGroup)
      OR referenced_tag_id = (SELECT main_id FROM TargetGroup)
    ''', [tagId]);
    return maps.map((e) => DownloadedTag.fromJson(e)).toList();
  }

  /// 获取一组标签及其各自所属等价组的所有成员（全组闭包查询）
  Future<List<DownloadedTag>> getExpandedTags(List<int> ids) async {
    if (ids.isEmpty) return [];
    final placeholders = List.filled(ids.length, '?').join(',');
    
    // 逻辑：
    // 1. 找到所有选中标签的“最终根节点” (Root Primary)
    // 2. 找到所有指向这些根节点的别名，以及根节点本身
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      WITH Roots AS (
        SELECT DISTINCT COALESCE(referenced_tag_id, id) as root_id 
        FROM ${DownloadedTagsColumns.tableName} 
        WHERE id IN ($placeholders)
      )
      SELECT * FROM ${DownloadedTagsColumns.tableName}
      WHERE id IN (SELECT root_id FROM Roots)
      OR referenced_tag_id IN (SELECT root_id FROM Roots)
    ''', ids);
    
    return maps.map((e) => DownloadedTag.fromJson(e)).toList();
  }

  /// 更新等价组内的主标签及成员关系
  Future<void> updateEquivalenceGroup(int newPrimaryId, List<int> allTagIds) async {
    await db.transaction((txn) async {
      // 1. 先将组内所有成员的引用置空
      final placeholders = List.filled(allTagIds.length, '?').join(',');
      await txn.update(
        DownloadedTagsColumns.tableName,
        {DownloadedTagsColumns.referencedTagId: null},
        where: 'id IN ($placeholders)',
        whereArgs: allTagIds,
      );
      
      // 2. 将非主标签的成员指向新的主标签
      final aliasIds = allTagIds.where((id) => id != newPrimaryId).toList();
      if (aliasIds.isNotEmpty) {
        final aliasPlaceholders = List.filled(aliasIds.length, '?').join(',');
        await txn.update(
          DownloadedTagsColumns.tableName,
          {DownloadedTagsColumns.referencedTagId: newPrimaryId},
          where: 'id IN ($aliasPlaceholders)',
          whereArgs: aliasIds,
        );
      }
    });
  }

  Future<DownloadedTag?> getTagByName(String name) async {
    final maps = await db.query(
      DownloadedTagsColumns.tableName,
      where: '${DownloadedTagsColumns.name} = ?',
      whereArgs: [name],
    );
    if (maps.isNotEmpty) {
      return DownloadedTag.fromJson(maps.first);
    }
    return null;
  }

  Future<List<DownloadedIllust>> searchIllusts(
    String keyword, {
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    // 如果按文件大小排序，需要使用 JOIN 查询
    if (orderBy != null && orderBy.contains('total_file_size')) {
      final orderDirection = orderBy.contains('DESC') ? 'DESC' : 'ASC';
      var query = '''
        SELECT di.*, COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
        FROM ${DownloadedIllustColumns.tableName} di
        LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
        WHERE di.${DownloadedIllustColumns.title} LIKE ? OR di.${DownloadedIllustColumns.userName} LIKE ? OR di.${DownloadedIllustColumns.tags} LIKE ?
        GROUP BY di.${DownloadedIllustColumns.id}
        ORDER BY total_file_size $orderDirection
      ''';
      final args = <dynamic>['%$keyword%', '%$keyword%', '%$keyword%'];
      if (limit != null) {
        query += ' LIMIT ?';
        args.add(limit);
      }
      if (offset != null) {
        query += ' OFFSET ?';
        args.add(offset);
      }
      final maps = await db.rawQuery(query, args);
      return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
    }

    final orderByClause =
        orderBy ?? '${DownloadedIllustColumns.downloadTime} DESC';
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedIllustColumns.tableName,
      where:
          '${DownloadedIllustColumns.title} LIKE ? OR ${DownloadedIllustColumns.userName} LIKE ? OR ${DownloadedIllustColumns.tags} LIKE ?',
      whereArgs: ['%$keyword%', '%$keyword%', '%$keyword%'],
      orderBy: orderByClause,
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  /// 获取所有未下载完整的作品（下载的图片数量小于 pageCount）
  /// 使用 SQL JOIN 和 HAVING 子句优化查询，避免在应用层逐个检查
  /// 这个查询会扫描所有作品，但使用数据库索引可以大幅提升性能
  Future<List<DownloadedIllust>> getIncompleteIllusts({
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    // 构建基础查询：使用 LEFT JOIN 和 GROUP BY，然后用 HAVING 过滤
    // 注意：SQLite 中 GROUP BY 后可以使用分组列，所以 di.page_count 在 HAVING 中是可用的
    var query = '''
      SELECT di.*, COUNT(img.${DownloadedImageColumns.illustId}) as downloaded_count
      FROM ${DownloadedIllustColumns.tableName} di
      LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
      GROUP BY di.${DownloadedIllustColumns.id}
      HAVING COUNT(img.${DownloadedImageColumns.illustId}) < di.${DownloadedIllustColumns.pageCount}
    ''';

    final args = <dynamic>[];

    // 处理排序
    if (orderBy != null) {
      if (orderBy.contains('total_file_size')) {
        // 如果按文件大小或平均文件大小排序，需要重新构建查询
        query = '''
          SELECT di.*, 
                 COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size,
                 COUNT(img.${DownloadedImageColumns.illustId}) as downloaded_count
          FROM ${DownloadedIllustColumns.tableName} di
          LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
          GROUP BY di.${DownloadedIllustColumns.id}
          HAVING COUNT(img.${DownloadedImageColumns.illustId}) < di.${DownloadedIllustColumns.pageCount}
          ORDER BY $orderBy
        ''';
      } else {
        query += ' ORDER BY $orderBy';
      }
    } else {
      query += ' ORDER BY di.${DownloadedIllustColumns.downloadTime} DESC';
    }

    // 添加 LIMIT 和 OFFSET
    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
    }
    if (offset != null) {
      query += ' OFFSET ?';
      args.add(offset);
    }

    final maps = await db.rawQuery(query, args);
    return maps.map((e) => DownloadedIllust.fromJson(e)).toList();
  }

  Future<int> deleteIllustByIllustId(int illustId) async {
    // 先删除关联的图片记录
    await db.delete(
      DownloadedImageColumns.tableName,
      where: '${DownloadedImageColumns.illustId} = ?',
      whereArgs: [illustId],
    );
    // 再删除插画记录
    return await db.delete(
      DownloadedIllustColumns.tableName,
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illustId],
    );
  }

  Future<int> getIllustCount() async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DownloadedIllustColumns.tableName}',
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<List<Map<String, dynamic>>> getDistinctUsers() async {
    return await db.rawQuery('''
      SELECT DISTINCT ${DownloadedIllustColumns.userId}, ${DownloadedIllustColumns.userName}, COUNT(*) as count
      FROM ${DownloadedIllustColumns.tableName}
      GROUP BY ${DownloadedIllustColumns.userId}
      ORDER BY count DESC
    ''');
  }

  // ============ Images 操作 ============

  Future<DownloadedImage> insertImage(DownloadedImage image) async {
    await db.insert(
      DownloadedImageColumns.tableName,
      image.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return image;
  }

  Future<DownloadedImage?> getImage(int illustId, int part) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedImageColumns.tableName,
      where:
          '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, part],
    );
    if (maps.isNotEmpty) {
      return DownloadedImage.fromJson(maps.first);
    }
    return null;
  }

  Future<bool> isImageDownloaded(int illustId, int part) async {
    return await getImage(illustId, part) != null;
  }

  /// 批量检查图片是否已下载
  /// 返回一个 Set，包含已下载的 (illustId, part) 组合的 Map
  Future<Set<Map<String, int>>> batchCheckImageDownloaded(
      List<Map<String, int>> illustParts) async {
    if (illustParts.isEmpty) return {};

    final result = <Map<String, int>>{};

    // 按 illust_id 分组，减少 OR 条件的数量
    final groupedByIllustId = <int, Set<int>>{};
    for (final item in illustParts) {
      final illustId = item['illustId'];
      final part = item['part'];
      if (illustId != null && part != null) {
        groupedByIllustId.putIfAbsent(illustId, () => <int>{}).add(part);
      }
    }

    // 分批处理 illust_id，每批最多 50 个 illust_id
    // 这样可以避免单个查询的 OR 条件过多
    const batchSize = 50;
    final illustIds = groupedByIllustId.keys.toList();

    for (int i = 0; i < illustIds.length; i += batchSize) {
      final batchIllustIds = illustIds.skip(i).take(batchSize).toList();

      // 构建查询：WHERE illust_id IN (?, ?, ...) AND (part IN (?, ?, ...) OR ...)
      // 但这样仍然可能复杂，改用更简单的方式：对每个 illust_id 单独查询其 parts
      for (final illustId in batchIllustIds) {
        final parts = groupedByIllustId[illustId]!.toList();

        // 对每个 illust_id 的 parts 也进行分批，每批最多 100 个 part
        const partBatchSize = 100;
        for (int j = 0; j < parts.length; j += partBatchSize) {
          final batchParts = parts.skip(j).take(partBatchSize).toList();

          final placeholders = List.filled(batchParts.length, '?').join(',');
          final maps = await db.query(
            DownloadedImageColumns.tableName,
            columns: [
              DownloadedImageColumns.illustId,
              DownloadedImageColumns.part
            ],
            where:
                '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} IN ($placeholders)',
            whereArgs: [illustId, ...batchParts],
          );

          result.addAll(
            maps.map((e) => {
                  'illustId': e[DownloadedImageColumns.illustId] as int,
                  'part': e[DownloadedImageColumns.part] as int,
                }),
          );
        }
      }
    }

    return result;
  }

  /// 通过原始URL查询图片记录
  Future<DownloadedImage?> getImageByOriginalUrl(String originalUrl) async {
    // 查询时需要使用压缩后的 URL 格式（与数据库存储格式一致）
    final compressedUrl = PixivUrlUtil.compressOriginalUrl(originalUrl);
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedImageColumns.tableName,
      where: '${DownloadedImageColumns.originalUrl} = ?',
      whereArgs: [compressedUrl],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return DownloadedImage.fromJson(maps.first);
    }
    return null;
  }

  Future<List<DownloadedImage>> getImagesByIllustId(int illustId) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedImageColumns.tableName,
      where: '${DownloadedImageColumns.illustId} = ?',
      whereArgs: [illustId],
      orderBy: '${DownloadedImageColumns.part} ASC',
    );
    return maps.map((e) => DownloadedImage.fromJson(e)).toList();
  }

  /// 批量获取插画的所有图片信息及其完整路径（自动检测后缀名）
  /// 返回 Map<part, LocalImageInfo>
  ///
  /// 注意：对于动图(ugoira)类型，只返回预览图(part=0)，不返回帧文件
  /// 帧文件仅用于文件大小统计和动图播放，不应作为独立页面显示
  Future<Map<int, LocalImageInfo>> getLocalImageInfosByIllustId(
    int illustId, {
    bool includeUgoiraFrames = false,
  }) async {
    final t1 = DateTime.now();
    final images = await getImagesByIllustId(illustId);

    // 检查是否为动图类型
    final illust = await getIllustByIllustId(illustId);
    final isUgoira = illust?.isUgoira;

    // 对于动图，默认只处理预览图(part=0)，过滤掉所有帧文件(part>=1)
    // 如果 includeUgoiraFrames 为 true，则包含所有帧文件
    final filteredImages = (isUgoira == true && !includeUgoiraFrames)
        ? images.where((img) => img.part == 0).toList()
        : images;

    Log.d(
        'getLocalImageInfosByIllustId: ${images.length} total images, ${filteredImages.length} filtered (isUgoira: $isUgoira, includeUgoiraFrames: $includeUgoiraFrames), ${DateTime.now().difference(t1).inMilliseconds}ms');

    // 并行处理所有图片，大幅提升性能
    final futures = filteredImages.map((image) async {
      final foundPath = await _findImagePathForImage(image);
      if (foundPath != null) {
        return MapEntry(
            image.part,
            LocalImageInfo(
              path: foundPath,
              width: image.width,
              height: image.height,
              fileSize: image.fileSize,
            ));
      } else {
        Log.w('未找到图片: ${image.illustId}-${image.part}, $_downloadPath, ${image.relativePath}, ${image.fileName}');
      }
      return null;
    });

    final results = await Future.wait(futures);
    final result = <int, LocalImageInfo>{};
    for (final entry in results) {
      if (entry != null) {
        result[entry.key] = entry.value;
      }
    }

    return result;
  }

  /// 根据图片记录查找实际存在的文件路径（自动检测后缀名）
  Future<String?> _findImagePathForImage(DownloadedImage image,
      {bool update = true}) async {
    // 使用标准的相对路径和文件名构建路径（对动图帧文件也适用，因为 relativePath 已包含 ugoira 子目录）
    final basePath = getAbsolutePath(
      image.relativePath.replaceAll('\\', '/'),
      image.fileName
    );

    // 首先尝试数据库中记录的后缀（最常见的情况）
    String fullPath = '$basePath${image.extension}';
    if (await File(fullPath).exists()) {
      return fullPath;
    }

    // 并行检查其他常见后缀，提升性能
    final otherExtensions =
        kImageExtensions.where((ext) => ext != image.extension).toList();
    final checkFutures = otherExtensions.map((ext) async {
      final testPath = '$basePath$ext';
      if (await File(testPath).exists()) {
        return testPath;
      }
      return null;
    });

    final results = await Future.wait(checkFutures);
    for (int i = 0; i < results.length; i++) {
      if (results[i] != null) {
        final foundPath = results[i]!;
        if (update) {
          // 更新数据库中的后缀名（异步执行，不阻塞返回）
          updateImageExtension(image.illustId, image.part, otherExtensions[i])
              .catchError((e) {
            Log.e('Failed to update image extension: $e');
            return 0; // 返回默认值以满足 catchError 的要求
          });
        }

        return foundPath;
      }
    }

    return null;
  }

  /// 更新图片的文件大小和宽高信息
  Future<int> updateImageFileSizeAndDimensions(
    int illustId,
    int part,
    int fileSize,
    int width,
    int height,
  ) async {
    return await db.update(
      DownloadedImageColumns.tableName,
      {
        DownloadedImageColumns.fileSize: fileSize,
        DownloadedImageColumns.width: width,
        DownloadedImageColumns.height: height,
      },
      where:
          '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, part],
    );
  }

  Future<int> updateImageExtension(
    int illustId,
    int part,
    String newExtension,
  ) async {
    return await db.update(
      DownloadedImageColumns.tableName,
      {DownloadedImageColumns.extension: newExtension},
      where:
          '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, part],
    );
  }

  /// 更新图片的宽高信息
  Future<int> updateImageDimensions(
    int illustId,
    int part,
    int width,
    int height,
  ) async {
    return await db.update(
      DownloadedImageColumns.tableName,
      {
        DownloadedImageColumns.width: width,
        DownloadedImageColumns.height: height,
      },
      where:
          '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, part],
    );
  }

  /// 获取需要更新宽高的图片列表（宽高为空的记录）
  Future<List<DownloadedImage>> getImagesWithoutDimensions({int? limit}) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedImageColumns.tableName,
      where:
          '${DownloadedImageColumns.width} IS NULL OR ${DownloadedImageColumns.height} IS NULL',
      limit: limit,
    );
    return maps.map((e) => DownloadedImage.fromJson(e)).toList();
  }

  Future<int> deleteImage(int illustId, int part) async {
    return await db.delete(
      DownloadedImageColumns.tableName,
      where:
          '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, part],
    );
  }

  Future<int> getDownloadedImageCount(int illustId) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${DownloadedImageColumns.tableName} WHERE ${DownloadedImageColumns.illustId} = ?',
      [illustId],
    );
    return result.first['count'] as int? ?? 0;
  }

  /// 获取插画的图片统计信息（数量和总文件大小）
  /// 返回：已下载图片数量和总文件大小（字节）的记录
  Future<({int count, int totalFileSize})> getIllustImageStats(
      int illustId) async {
    final result = await db.rawQuery(
      '''
      SELECT 
        COUNT(*) as count,
        COALESCE(SUM(${DownloadedImageColumns.fileSize}), 0) as total_file_size
      FROM ${DownloadedImageColumns.tableName}
      WHERE ${DownloadedImageColumns.illustId} = ?
      ''',
      [illustId],
    );

    if (result.isNotEmpty) {
      return (
        count: result.first['count'] as int? ?? 0,
        totalFileSize: result.first['total_file_size'] as int? ?? 0,
      );
    }
    return (count: 0, totalFileSize: 0);
  }

  /// 优化 downloaded_images 表的 original_url 字段
  /// 将完整 URL 前缀替换为占位符以节约存储空间
  /// 返回 (优化记录数, 节省字节数)
  Future<({int optimizedCount, int savedBytes})> optimizeImageOriginalUrls() async {
    const prefix = 'https://i.pximg.net/img-original/img';
    const placeholder = r'$PX_IMG$';

    // 首先获取需要优化的记录数和总字符长度
    final beforeStats = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        COALESCE(SUM(LENGTH(${DownloadedImageColumns.originalUrl})), 0) as total_length
      FROM ${DownloadedImageColumns.tableName}
      WHERE ${DownloadedImageColumns.originalUrl} LIKE '$prefix%'
    ''');

    final countToOptimize = beforeStats.first['count'] as int? ?? 0;

    if (countToOptimize == 0) {
      return (optimizedCount: 0, savedBytes: 0);
    }

    // 使用 SQL REPLACE 函数批量更新（效率最高）
    await db.execute('''
      UPDATE ${DownloadedImageColumns.tableName}
      SET ${DownloadedImageColumns.originalUrl} = REPLACE(
        ${DownloadedImageColumns.originalUrl}, 
        '$prefix', 
        '$placeholder'
      )
      WHERE ${DownloadedImageColumns.originalUrl} LIKE '$prefix%'
    ''');

    // 计算节省的字节数
    // 每条记录节省：前缀长度 - 占位符长度 = 41 - 8 = 33 字节
    final savedBytesPerRecord = prefix.length - placeholder.length;
    final totalSavedBytes = countToOptimize * savedBytesPerRecord;

    Log.d('optimizeImageOriginalUrls: 优化了 $countToOptimize 条记录，节省 $totalSavedBytes 字节');

    return (optimizedCount: countToOptimize, savedBytes: totalSavedBytes);
  }

  // ============ 路径工具 ============


  /// 生成作者目录名
  static String buildUserDirName(String userName, int userId) {
    return '[${userName.toLegal()}][$userId]';
  }

  /// 生成作品目录名
  static String buildIllustDirName(int illustId, String title) {
    return '[$illustId]${title.toLegal()}';
  }

  /// 生成文件名（不含后缀）
  static String buildFileName(int illustId, int part) {
    return '${illustId}_p$part';
  }

  /// 生成相对路径
  static String buildRelativePath(Illusts illusts) {
    final userDir = buildUserDirName(illusts.user.name, illusts.user.id);
    final illustDir = buildIllustDirName(illusts.id, illusts.title);
    return path.join(userDir, illustDir);
  }

  /// 根据相对路径获取插画目录的绝对路径
  String getIllustAbsolutePath(String relativePath) {
    return path.join(_downloadPath!, relativePath);
  }

  /// 通用方法：根据相对路径和可选的文件名获取完整的绝对路径
  /// 如果提供了 fileName，返回 basePath/relativePath/fileName
  /// 如果未提供 fileName，返回 basePath/relativePath
  String getAbsolutePath(String relativePath, [String? fileName]) {
    if (fileName != null) {
      return path.join(_downloadPath!, relativePath, fileName);
    }
    return path.join(_downloadPath!, relativePath);
  }

  /// 获取动图帧目录的绝对路径
  String getUgoiraFrameDirPath(String relativePath) {
    return getAbsolutePath(relativePath, 'ugoira');
  }

  /// 获取图片的完整文件路径
  Future<String?> getImageFullPath(int illustId, int part) async {
    final image = await getImage(illustId, part);
    if (image == null) return null;

    return getAbsolutePath(image.relativePath, image.getFullFileName());
  }

  /// 尝试找到图片文件（自动检测后缀名）
  Future<String?> findImagePath(int illustId, int part,
      {bool update = true}) async {
    final image = await getImage(illustId, part);
    if (image == null) return null;
    return await _findImagePathForImage(image, update: update);
  }

  Future<LocalImageInfo?> getLocalImageInfoByUrl(String url) async {
    final image = await getImageByOriginalUrl(url);
    if (image == null) return null;
    final imagePath = await _findImagePathForImage(image);
    if (imagePath == null) return null;
    return LocalImageInfo(
      path: imagePath,
      width: image.width,
      height: image.height,
    );
  }

  // ============ 数据迁移 ============

  /// 从现有插画数据生成作者表（用于数据库升级）
  static Future<void> _migrateAuthorsFromIllusts(Database db) async {
    try {
      // 获取所有不同的用户及其统计信息
      final users = await db.rawQuery('''
        SELECT 
          ${DownloadedIllustColumns.userId},
          ${DownloadedIllustColumns.userName},
          COUNT(*) as count,
          MAX(${DownloadedIllustColumns.downloadTime}) as last_download_time
        FROM ${DownloadedIllustColumns.tableName}
        GROUP BY ${DownloadedIllustColumns.userId}
      ''');

      for (final user in users) {
        final userId = user[DownloadedIllustColumns.userId] as int;
        final userName = user[DownloadedIllustColumns.userName] as String;
        final count = user['count'] as int;
        final lastDownloadTime = user['last_download_time'] as int? ?? 0;

        // 获取最新插画的 JSON 来解析用户头像
        final latestIllust = await db.query(
          DownloadedIllustColumns.tableName,
          where: '${DownloadedIllustColumns.userId} = ?',
          whereArgs: [userId],
          orderBy: '${DownloadedIllustColumns.downloadTime} DESC',
          limit: 1,
        );

        String? profileImageUrl;
        if (latestIllust.isNotEmpty) {
          try {
            final illustJsonStr =
                latestIllust.first[DownloadedIllustColumns.illustJson]
                    as String;
            final illustJson = PixivUrlUtil.decompressPxUrl(illustJsonStr);
            profileImageUrl =
                TypeUtil.parseMap(illustJson)['user']?['profile_image_urls']?['medium'];
          } catch (_) {}
        }

        // 计算总文件大小
        final images = await db.query(
          DownloadedImageColumns.tableName,
          where:
              '${DownloadedImageColumns.illustId} IN (SELECT ${DownloadedIllustColumns.illustId} FROM ${DownloadedIllustColumns.tableName} WHERE ${DownloadedIllustColumns.userId} = ?)',
          whereArgs: [userId],
        );
        int totalFileSize = 0;
        for (final image in images) {
          totalFileSize += image[DownloadedImageColumns.fileSize] as int? ?? 0;
        }

        // 插入作者记录
        await db.insert(
          DownloadedAuthorColumns.tableName,
          {
            DownloadedAuthorColumns.userId: userId,
            DownloadedAuthorColumns.userName: userName,
            DownloadedAuthorColumns.profileImageUrl: profileImageUrl,
            DownloadedAuthorColumns.illustCount: count,
            DownloadedAuthorColumns.totalFileSize: totalFileSize,
            DownloadedAuthorColumns.lastDownloadTime: lastDownloadTime,
            DownloadedAuthorColumns.lastUpdateTime:
                DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      Log.e('迁移作者数据失败: $e');
    }
  }

  // ============ Author 操作 ============

  /// 插入或更新作者信息
  Future<void> upsertAuthor(
    int userId,
    String? userName,
    String? profileImageUrl,
    int illustCount,
    int totalFileSize,
    int lastDownloadTime,
  ) async {
    await db.insert(
      DownloadedAuthorColumns.tableName,
      {
        DownloadedAuthorColumns.userId: userId,
        if (userName != null) DownloadedAuthorColumns.userName: userName,
        if (profileImageUrl != null)
          DownloadedAuthorColumns.profileImageUrl:
              PixivUrlUtil.compressPxUrl(profileImageUrl),
        DownloadedAuthorColumns.illustCount: illustCount,
        DownloadedAuthorColumns.totalFileSize: totalFileSize,
        DownloadedAuthorColumns.lastDownloadTime: lastDownloadTime,
        DownloadedAuthorColumns.lastUpdateTime:
            DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取作者信息
  Future<DownloadedAuthor?> getAuthorByUserId(int userId) async {
    List<Map<String, dynamic>> maps = await db.query(
      DownloadedAuthorColumns.tableName,
      where: '${DownloadedAuthorColumns.userId} = ?',
      whereArgs: [userId],
    );
    if (maps.isNotEmpty) {
      return DownloadedAuthor.fromJson(maps.first);
    }
    return null;
  }

  /// 获取作者列表，支持排序和搜索
  /// sortBy: 'last_download_time', 'user_name', 'illust_count'
  /// searchKeyword: 搜索关键词，支持作者名模糊匹配和用户ID精确匹配
  Future<List<DownloadedAuthor>> getAuthorsWithStats({
    String sortBy = 'last_download_time',
    bool desc = true,
    int? limit,
    int? offset,
    String? searchKeyword,
  }) async {
    String orderBy = sortBy;
    if (desc) {
      orderBy += ' DESC';
    } else {
      orderBy += ' ASC';
    }

    String? where;
    List<Object?>? whereArgs;

    // 如果有搜索关键词，添加搜索条件
    if (searchKeyword != null && searchKeyword.trim().isNotEmpty) {
      final keyword = searchKeyword.trim();
      // 尝试将关键词解析为数字（用户ID）
      final userId = int.tryParse(keyword);

      if (userId != null) {
        // 如果是数字，同时搜索用户ID和用户名
        where =
            '(${DownloadedAuthorColumns.userId} = ? OR ${DownloadedAuthorColumns.userName} LIKE ?)';
        whereArgs = [userId, '%$keyword%'];
      } else {
        // 如果不是数字，只搜索用户名
        where = '${DownloadedAuthorColumns.userName} LIKE ?';
        whereArgs = ['%$keyword%'];
      }
    }

    List<Map<String, dynamic>> maps = await db.query(
      DownloadedAuthorColumns.tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return maps.map((e) => DownloadedAuthor.fromJson(e)).toList();
  }

  /// 更新作者统计信息（从插画表重新计算）
  Future<void> updateAuthorStats(int userId) async {
    // 获取插画数量
    final illustCount = await db.rawQuery('''
      SELECT COUNT(*) as count 
      FROM ${DownloadedIllustColumns.tableName} 
      WHERE ${DownloadedIllustColumns.userId} = ?
    ''', [userId]);
    final count = illustCount.first['count'] as int? ?? 0;

    // 获取最新下载时间
    final latestTime = await db.rawQuery('''
      SELECT MAX(${DownloadedIllustColumns.downloadTime}) as last_time
      FROM ${DownloadedIllustColumns.tableName}
      WHERE ${DownloadedIllustColumns.userId} = ?
    ''', [userId]);
    final lastDownloadTime = latestTime.first['last_time'] as int? ?? 0;

    // 获取最新插画的 JSON 来解析用户名和头像
    final latestIllust = await db.query(
      DownloadedIllustColumns.tableName,
      where: '${DownloadedIllustColumns.userId} = ?',
      whereArgs: [userId],
      orderBy: '${DownloadedIllustColumns.downloadTime} DESC',
      limit: 1,
    );

    String? userName;
    String? profileImageUrl;
    if (latestIllust.isNotEmpty) {
      try {
        // 使用 fromJson 获取 DownloadedIllust 对象
        final downloadedIllust = DownloadedIllust.fromJson(latestIllust.first);
        // 转换为 Illusts 对象以获取完整的用户信息
        final illusts = downloadedIllust.toIllusts();
        userName = illusts.user.name;
        profileImageUrl = illusts.user.profileImageUrls.medium;
      } catch (e) {
        // 异常时回退到表字段
        Log.e('获取作者信息失败: $e');
      }
    }

    // 计算总文件大小
    final images = await db.rawQuery('''
      SELECT SUM(${DownloadedImageColumns.fileSize}) as total
      FROM ${DownloadedImageColumns.tableName}
      WHERE ${DownloadedImageColumns.illustId} IN (
        SELECT ${DownloadedIllustColumns.illustId} 
        FROM ${DownloadedIllustColumns.tableName} 
        WHERE ${DownloadedIllustColumns.userId} = ?
      )
    ''', [userId]);
    final totalFileSize = images.first['total'] as int? ?? 0;

    // 更新或插入作者记录
    await upsertAuthor(
      userId,
      userName,
      profileImageUrl,
      count,
      totalFileSize,
      lastDownloadTime,
    );
  }

  /// 更新作者统计信息，如果作者没有插画则删除作者记录
  /// 这个方法应该在删除插画后调用，用于维护作者表的正确状态
  Future<void> deleteAuthorIfEmpty(int userId) async {
    final count = await db.rawQuery('''
      SELECT COUNT(*) as count 
      FROM ${DownloadedIllustColumns.tableName} 
      WHERE ${DownloadedIllustColumns.userId} = ?
    ''', [userId]);
    final illustCount = count.first['count'] as int? ?? 0;
    
    if (illustCount == 0) {
      // 没有插画，删除作者记录
      await db.delete(
        DownloadedAuthorColumns.tableName,
        where: '${DownloadedAuthorColumns.userId} = ?',
        whereArgs: [userId],
      );
    } else {
      // 还有插画，更新统计信息
      await updateAuthorStats(userId);
    }
  }

  /// 获取作者的图片统计信息（总图片张数和总文件大小）
  /// 使用优化的SQL查询，一次性获取两个统计值
  Future<Map<String, int>> getAuthorImageStats(int userId) async {
    final result = await db.rawQuery('''
      SELECT 
        COUNT(${DownloadedImageColumns.id}) as total_image_count,
        COALESCE(SUM(${DownloadedImageColumns.fileSize}), 0) as total_file_size
      FROM ${DownloadedImageColumns.tableName}
      WHERE ${DownloadedImageColumns.illustId} IN (
        SELECT ${DownloadedIllustColumns.illustId} 
        FROM ${DownloadedIllustColumns.tableName} 
        WHERE ${DownloadedIllustColumns.userId} = ?
      )
    ''', [userId]);

    if (result.isNotEmpty) {
      return {
        'total_image_count': result.first['total_image_count'] as int? ?? 0,
        'total_file_size': result.first['total_file_size'] as int? ?? 0,
      };
    }
    return {'total_image_count': 0, 'total_file_size': 0};
  }

  /// 获取筛选条件下的统计信息
  /// 返回：插画数量、图片数量（实际下载的图片记录数）、文件大小
  /// filterType: 'all', 'user', 'search', 'incomplete'
  Future<Map<String, int>> getFilteredStats({
    String filterType = 'all',
    int? userId,
    String? searchKeyword,
    String? tagName,
  }) async {
    String joinClause =
        'LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}';
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (filterType == 'user' && userId != null) {
      whereClause = 'WHERE di.${DownloadedIllustColumns.userId} = ?';
      whereArgs.add(userId);
    } else if (filterType == 'tag' && tagName != null && tagName.isNotEmpty) {
      final tag = await getTagByName(tagName);
      if (tag != null) {
        // 使用 CTE 找到等价组的所有标签 ID，确保统计与 searchIllustsByTagId 一致
        final query = '''
          WITH TargetGroup AS (
            SELECT ${DownloadedTagsColumns.id} as id, COALESCE(${DownloadedTagsColumns.referencedTagId}, ${DownloadedTagsColumns.id}) as main_id 
            FROM ${DownloadedTagsColumns.tableName} 
            WHERE ${DownloadedTagsColumns.id} = ?
          ),
          GroupIds AS (
            SELECT id FROM ${DownloadedTagsColumns.tableName}
            WHERE id = (SELECT main_id FROM TargetGroup)
            OR ${DownloadedTagsColumns.referencedTagId} = (SELECT main_id FROM TargetGroup)
          )
          SELECT 
            COUNT(DISTINCT di.${DownloadedIllustColumns.id}) as illust_count,
            COUNT(img.${DownloadedImageColumns.id}) as total_image_count,
            COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
          FROM ${DownloadedIllustColumns.tableName} di
          INNER JOIN ${DownloadedIllustTagsColumns.tableName} dit ON di.${DownloadedIllustColumns.illustId} = dit.${DownloadedIllustTagsColumns.illustId}
          LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
          WHERE dit.${DownloadedIllustTagsColumns.tagId} IN (SELECT id FROM GroupIds)
        ''';
        final result = await db.rawQuery(query, [tag.id]);
        if (result.isNotEmpty) {
          return {
            'illust_count': result.first['illust_count'] as int? ?? 0,
            'image_count': result.first['total_image_count'] as int? ?? 0,
            'file_size': result.first['total_file_size'] as int? ?? 0,
          };
        }
        return {'illust_count': 0, 'image_count': 0, 'file_size': 0};
      } else {
        return {'illust_count': 0, 'image_count': 0, 'file_size': 0};
      }
    } else if (filterType == 'search' &&
        searchKeyword != null &&
        searchKeyword.isNotEmpty) {
      whereClause =
          'WHERE di.${DownloadedIllustColumns.title} LIKE ? OR di.${DownloadedIllustColumns.userName} LIKE ? OR di.${DownloadedIllustColumns.tags} LIKE ?';
      whereArgs
          .addAll(['%$searchKeyword%', '%$searchKeyword%', '%$searchKeyword%']);
    } else if (filterType == 'incomplete') {
      // 未下载完整：需要特殊处理，先找出所有未下载完整的作品ID
      final incompleteIllusts = await db.rawQuery('''
        SELECT di.${DownloadedIllustColumns.illustId}, di.${DownloadedIllustColumns.pageCount}
        FROM ${DownloadedIllustColumns.tableName} di
        LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
        GROUP BY di.${DownloadedIllustColumns.id}
        HAVING COUNT(img.${DownloadedImageColumns.illustId}) < di.${DownloadedIllustColumns.pageCount}
      ''');

      if (incompleteIllusts.isEmpty) {
        return {'illust_count': 0, 'image_count': 0, 'file_size': 0};
      }

      final illustIds = incompleteIllusts
          .map((e) => e[DownloadedIllustColumns.illustId] as int)
          .toList();
      final placeholders = List.filled(illustIds.length, '?').join(',');

      // 统计这些作品的图片数量和文件大小
      final stats = await db.rawQuery('''
        SELECT 
          COUNT(DISTINCT di.${DownloadedIllustColumns.id}) as illust_count,
          COUNT(img.${DownloadedImageColumns.id}) as total_image_count,
          COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
        FROM ${DownloadedIllustColumns.tableName} di
        LEFT JOIN ${DownloadedImageColumns.tableName} img ON di.${DownloadedIllustColumns.illustId} = img.${DownloadedImageColumns.illustId}
        WHERE di.${DownloadedIllustColumns.illustId} IN ($placeholders)
      ''', illustIds);

      if (stats.isNotEmpty) {
        return {
          'illust_count': stats.first['illust_count'] as int? ?? 0,
          'image_count': stats.first['total_image_count'] as int? ?? 0,
          'file_size': stats.first['total_file_size'] as int? ?? 0,
        };
      }
      return {'illust_count': 0, 'image_count': 0, 'file_size': 0};
    }

    // 对于其他情况，使用标准查询
    // 统计实际下载的图片数量，而不是 pageCount 总和
    final query = '''
      SELECT 
        COUNT(DISTINCT di.${DownloadedIllustColumns.id}) as illust_count,
        COUNT(img.${DownloadedImageColumns.id}) as total_image_count,
        COALESCE(SUM(img.${DownloadedImageColumns.fileSize}), 0) as total_file_size
      FROM ${DownloadedIllustColumns.tableName} di
      $joinClause
      $whereClause
    ''';

    final result = await db.rawQuery(query, whereArgs);

    if (result.isNotEmpty) {
      return {
        'illust_count': result.first['illust_count'] as int? ?? 0,
        'image_count': result.first['total_image_count'] as int? ?? 0,
        'file_size': result.first['total_file_size'] as int? ?? 0,
      };
    }
    return {'illust_count': 0, 'image_count': 0, 'file_size': 0};
  }

  // ============ PendingDownload 操作 ============

  /// 插入待下载任务
  Future<PendingDownload> insertPendingDownload(PendingDownload pending) async {
    await db.insert(
      PendingDownloadColumns.tableName,
      pending.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return pending;
  }

  /// 获取所有待下载任务
  Future<List<PendingDownload>> getAllPendingDownloads() async {
    List<Map<String, dynamic>> maps = await db.query(
      PendingDownloadColumns.tableName,
      orderBy: '${PendingDownloadColumns.createTime} ASC',
    );
    return maps.map((e) => PendingDownload.fromJson(e)).toList();
  }

  /// 获取指定状态的待下载任务
  Future<List<PendingDownload>> getPendingDownloadsByStatus(
      List<String> status) async {
    List<Map<String, dynamic>> maps = await db.query(
      PendingDownloadColumns.tableName,
      where:
          '${PendingDownloadColumns.status} IN (${status.map((e) => '?').join(',')})',
      whereArgs: [...status],
      orderBy: '${PendingDownloadColumns.createTime} ASC',
    );
    return maps.map((e) => PendingDownload.fromJson(e)).toList();
  }

  /// 更新任务状态
  Future<int> updatePendingDownloadStatus(
    String id,
    String status,
  ) async {
    return await db.update(
      PendingDownloadColumns.tableName,
      {PendingDownloadColumns.status: status},
      where: '${PendingDownloadColumns.id} = ?',
      whereArgs: [id],
    );
  }

  /// 删除待下载任务
  Future<int> deletePendingDownload(String id) async {
    return await db.delete(
      PendingDownloadColumns.tableName,
      where: '${PendingDownloadColumns.id} = ?',
      whereArgs: [id],
    );
  }

  /// 删除插画的所有待下载任务
  Future<int> deletePendingDownloadsByIllustId(int illustId) async {
    return await db.delete(
      PendingDownloadColumns.tableName,
      where: '${PendingDownloadColumns.id} LIKE ?',
      whereArgs: ['${illustId}_%'],
    );
  }

  /// 清空所有待下载任务
  Future<int> clearAllPendingDownloads() async {
    return await db.delete(PendingDownloadColumns.tableName);
  }

  /// 检查任务是否存在
  Future<bool> isPendingDownloadExists(String id) async {
    final result = await db.query(
      PendingDownloadColumns.tableName,
      where: '${PendingDownloadColumns.id} = ?',
      whereArgs: [id],
    );
    return result.isNotEmpty;
  }

  /// 获取待下载任务数量
  Future<int> getPendingDownloadCount() async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${PendingDownloadColumns.tableName}',
    );
    return result.first['count'] as int? ?? 0;
  }

  /// 批量插入待下载任务（使用事务优化性能）
  Future<void> batchInsertPendingDownloads(
      List<PendingDownload> pendings) async {
    if (pendings.isEmpty) return;

    final batch = db.batch();
    for (final pending in pendings) {
      batch.insert(
        PendingDownloadColumns.tableName,
        pending.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 批量删除待下载任务（使用事务优化性能）
  Future<void> batchDeletePendingDownloads(List<String> taskKeys) async {
    if (taskKeys.isEmpty) return;

    // 分批删除，每批最多 1000 条，避免 SQL 语句过长
    const batchSize = 1000;

    for (int i = 0; i < taskKeys.length; i += batchSize) {
      final batch = taskKeys.skip(i).take(batchSize).toList();
      final dbBatch = db.batch();

      for (final key in batch) {
        dbBatch.delete(
          PendingDownloadColumns.tableName,
          where: '${PendingDownloadColumns.id} = ?',
          whereArgs: [key],
        );
      }

      await dbBatch.commit(noResult: true);
    }
  }

  /// 批量检查并插入插画记录（使用事务优化性能）
  /// 返回已存在的 illustId 集合
  Future<Set<int>> batchInsertIllustsIfNotExists(
      List<DownloadedIllust> illusts) async {
    if (illusts.isEmpty) return {};

    // 先批量查询已存在的 illustId
    final illustIds = illusts.map((e) => e.illustId).toList();
    final existingIds = <int>{};

    // 分批查询，每批最多 1000 条
    const batchSize = 1000;
    for (int i = 0; i < illustIds.length; i += batchSize) {
      final batch = illustIds.skip(i).take(batchSize).toList();
      final placeholders = batch.map((_) => '?').join(',');
      final maps = await db.rawQuery(
        'SELECT ${DownloadedIllustColumns.illustId} FROM ${DownloadedIllustColumns.tableName} WHERE ${DownloadedIllustColumns.illustId} IN ($placeholders)',
        batch,
      );
      existingIds
          .addAll(maps.map((e) => e[DownloadedIllustColumns.illustId] as int));
    }

    // 过滤出需要插入的 illusts
    final illustsToInsert =
        illusts.where((e) => !existingIds.contains(e.illustId)).toList();

    if (illustsToInsert.isEmpty) return existingIds;

    // 批量插入
    final dbBatch = db.batch();
    for (final illust in illustsToInsert) {
      dbBatch.insert(
        DownloadedIllustColumns.tableName,
        illust.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await dbBatch.commit(noResult: true);

    return existingIds;
  }

  /// 执行 VACUUM 命令，回收数据库空间
  Future<void> vacuum() async {
    try {
      await db.execute('VACUUM');
      Log.d('数据库 VACUUM 执行完成');
    } catch (e) {
      Log.e('执行 VACUUM 失败: $e');
      rethrow;
    }
  }

  /// 获取数据库文件大小（字节）
  Future<int> getDatabaseSize() async {
    if (_dbPath == null) return 0;
    final file = File(_dbPath!);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  // ============ WebP 动图相关操作 ============

  /// 将动图序列帧记录替换为WebP动图记录
  /// 
  /// 在事务中执行：
  /// 1. 删除 part > 0 的序列帧记录（保留 part=0 预览图）
  /// 2. 插入 part=-1 的 WebP 动图记录
  /// 
  /// [illustId]: 插画ID
  /// [relativePath]: 相对路径
  /// [fileSize]: WebP文件大小
  /// [width]: WebP动图宽度（可选）
  /// [height]: WebP动图高度（可选）
  Future<void> replaceUgoiraFramesWithWebP({
    required int illustId,
    required String relativePath,
    required int fileSize,
    int? width,
    int? height,
  }) async {
    await db.transaction((txn) async {
      // 1. 删除序列帧记录（保留 part=0 的预览图）
      await txn.delete(
        DownloadedImageColumns.tableName,
        where: '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} > 0',
        whereArgs: [illustId],
      );

      // 2. 插入WebP动图记录（part=-1）
      await txn.insert(
        DownloadedImageColumns.tableName,
        DownloadedImage(
          illustId: illustId,
          part: -1, // WebP动图标识
          fileName: '$illustId',
          extension: '.webp',
          fileSize: fileSize,
          originalUrl: '', // 本地生成，无原始URL
          relativePath: relativePath,
          width: width,
          height: height,
        ).toJson(),
      );
    });
  }

  /// 更新动图WebP的宽高信息
  Future<void> updateWebPDimensions(int illustId, int width, int height) async {
    await db.update(
      DownloadedImageColumns.tableName,
      {
        DownloadedImageColumns.width: width,
        DownloadedImageColumns.height: height,
      },
      where: '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
      whereArgs: [illustId, -1],
    );
  }

  /// 获取WebP动图记录（part=-1）
  Future<DownloadedImage?> getWebPImage(int illustId) async {
    return await getImage(illustId, -1);
  }

  // ============ Tag 操作 ============

  Future<void> updateTag(DownloadedTag tag) async {
    // Only update specific columns
    await db.update(
      DownloadedTagsColumns.tableName,
      {
        DownloadedTagsColumns.customTranslatedName: tag.customTranslatedName,
        DownloadedTagsColumns.category: tag.category,
        DownloadedTagsColumns.isBookmarked: tag.isBookmarked ? 1 : 0,
        DownloadedTagsColumns.displayOrder: tag.displayOrder,
      },
      where: '${DownloadedTagsColumns.name} = ?',
      whereArgs: [tag.name],
    );
  }

  Future<void> batchUpdateTagCategory(List<int> tagIds, int category) async {
    if (tagIds.isEmpty) return;
    
    // Batch update using WHERE IN
    const batchSize = 500;
    for (int i = 0; i < tagIds.length; i += batchSize) {
      final end = (i + batchSize < tagIds.length) ? i + batchSize : tagIds.length;
      final batchIds = tagIds.sublist(i, end);
      final placeholders = List.filled(batchIds.length, '?').join(',');
      
      await db.update(
        DownloadedTagsColumns.tableName,
        {DownloadedTagsColumns.category: category},
        where: '${DownloadedTagsColumns.id} IN ($placeholders)',
        whereArgs: batchIds,
      );
    }
  }

  Future<void> addCustomTagToIllust(int illustId, String tagName) async {
    // 1. Ensure tag exists in downloaded_tags
    await db.rawInsert('''
      INSERT OR IGNORE INTO ${DownloadedTagsColumns.tableName} 
      (${DownloadedTagsColumns.name})
      VALUES (?)
    ''', [tagName]);
    
    // 2. Get ID
    final List<Map<String, dynamic>> res = await db.query(
      DownloadedTagsColumns.tableName,
      columns: [DownloadedTagsColumns.id],
      where: '${DownloadedTagsColumns.name} = ?',
      whereArgs: [tagName],
    );
    if (res.isEmpty) return; // Should not happen
    final tagId = res.first[DownloadedTagsColumns.id] as int;

    // 3. Add link with source=1
    await db.insert(
      DownloadedIllustTagsColumns.tableName,
      {
        DownloadedIllustTagsColumns.illustId: illustId,
        DownloadedIllustTagsColumns.tagId: tagId,
        DownloadedIllustTagsColumns.source: 1, // Custom tag
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeCustomTagFromIllust(int illustId, String tagName) async {
     final List<Map<String, dynamic>> res = await db.query(
      DownloadedTagsColumns.tableName,
      columns: [DownloadedTagsColumns.id],
      where: '${DownloadedTagsColumns.name} = ?',
      whereArgs: [tagName],
    );
    if (res.isEmpty) return;
    final tagId = res.first[DownloadedTagsColumns.id] as int;

     await db.delete(
       DownloadedIllustTagsColumns.tableName,
       where: '${DownloadedIllustTagsColumns.illustId} = ? AND ${DownloadedIllustTagsColumns.tagId} = ? AND ${DownloadedIllustTagsColumns.source} = ?',
       whereArgs: [illustId, tagId, 1],
     );
  }

  Future<List<String>> getTagsForIllust(int illustId) async {
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT t.${DownloadedTagsColumns.name}
      FROM ${DownloadedIllustTagsColumns.tableName} it
      JOIN ${DownloadedTagsColumns.tableName} t ON it.${DownloadedIllustTagsColumns.tagId} = t.${DownloadedTagsColumns.id}
      WHERE it.${DownloadedIllustTagsColumns.illustId} = ?
    ''', [illustId]);
    return maps.map((e) => e[DownloadedTagsColumns.name] as String).toList();
  }

  Future<List<TagDisplayData>> getTags() async {
      // Fetch all tags. Sorting and filtering are handled by the frontend store.
      final List<Map<String, dynamic>> maps = await db.query(
        DownloadedTagsColumns.tableName,
      );
      
      List<TagDisplayData> result = [];
      Set<int> allIllustIds = {};

      // First pass: create entities and collect IDs
      List<DownloadedTag> tagEntities = [];
      for (var map in maps) {
        var entity = DownloadedTag.fromJson(map);
        tagEntities.add(entity);
        allIllustIds.addAll(entity.exampleIllustIds);
      }

      // Batch query illusts
      Map<int, IllustPreviewData> illustMap = {};
      if (allIllustIds.isNotEmpty) {
        final List<int> idsList = allIllustIds.toList();
        // Batch size of 200 to be safe (SQLite usually limits params to ~999)
        const int batchSize = 200;
        for (var i = 0; i < idsList.length; i += batchSize) {
           var end = (i + batchSize < idsList.length) ? i + batchSize : idsList.length;
           var batchIds = idsList.sublist(i, end);
           
           final placeholders = List.filled(batchIds.length, '?').join(',');
           
           final List<Map<String, dynamic>> illustMaps = await db.query(
             DownloadedIllustColumns.tableName,
             columns: [
                DownloadedIllustColumns.illustId,
                DownloadedIllustColumns.imageUrlsJson,
             ],
             where: '${DownloadedIllustColumns.illustId} IN ($placeholders)',
             whereArgs: batchIds,
           );
           for (var m in illustMaps) {
             final illustId = m[DownloadedIllustColumns.illustId] as int;
             final imageUrlsJson = m[DownloadedIllustColumns.imageUrlsJson] as String;

             String squareMedium = '';
             if (imageUrlsJson.isNotEmpty) {
               final map = TypeUtil.parseMap(PixivUrlUtil.decompressPxUrl(imageUrlsJson));
                 squareMedium = TypeUtil.parseString(map['square_medium']);
             }
             
             illustMap[illustId] = IllustPreviewData(
               illustId: illustId,
               squareMediumUrl: squareMedium,
             );
           }
        }
      }

      // Pre-collect all referencedTagIds to determine which tags have equivalent relationships
      final List<Map<String, dynamic>> refMaps = await db.query(
        DownloadedTagsColumns.tableName,
        columns: [DownloadedTagsColumns.referencedTagId],
        where: '${DownloadedTagsColumns.referencedTagId} IS NOT NULL'
      );
      final Set<int> allReferencedIds = refMaps.map((m) => m[DownloadedTagsColumns.referencedTagId] as int).toSet();
      
      // Second pass: associate illusts and determine hasEquivalentTags
      for (var entity in tagEntities) {
        List<IllustPreviewData> previewIllusts = [];
        for (var illustId in entity.exampleIllustIds) {
          if (illustMap.containsKey(illustId)) {
            previewIllusts.add(illustMap[illustId]!);
          }
        }
        // Since we don't have createDate in the lean object, we'll rely on the order of exampleIllustIds 
        // which was already sorted by date when saved to DB during syncTags.
        
        // A tag has equivalent tags if:
        // 1. It is an alias (points to someone else)
        // 2. It is a primary tag (someone else points to it)
        bool hasEquivalentTags = entity.referencedTagId != null || allReferencedIds.contains(entity.id);
        
        result.add(TagDisplayData(
          tag: entity, 
          previewIllusts: previewIllusts,
          hasEquivalentTags: hasEquivalentTags,
        ));
      }

      return result;
  }

  Future<void> syncTags({Function(String status)? onStatus}) async {
    if (onStatus != null) onStatus('正在准备...');
      
    // 1. Get all downloaded illusts
    if (onStatus != null) onStatus('正在读取作品列表...');
    final List<Map<String, dynamic>> illustsMaps = await db.query(
      DownloadedIllustColumns.tableName,
      columns: [DownloadedIllustColumns.illustId, DownloadedIllustColumns.tags],
    );

    if (onStatus != null) onStatus('正在建立索引...');

    // In-memory aggregation
    Map<String, Set<int>> tagToIllusts = {};
    Map<String, String> tagTranslations = {};
    int count = 0;
    
    for (var map in illustsMaps) {
      int illustId = map[DownloadedIllustColumns.illustId];
      String tagsJson = map[DownloadedIllustColumns.tags];
      try {
          List<Tags> illustTags = TypeUtil.parseList(tagsJson, (e) => Tags.fromMap(TypeUtil.parseMap(e)));
          
          for (var tag in illustTags) {
            String tagName = tag.name;
            if (processTags(tagName)) {
               tagToIllusts.putIfAbsent(tagName, () => {});
               tagToIllusts[tagName]!.add(illustId);
               tagTranslations[tagName] = tag.translatedName ?? '';
            }
          }
      } catch (e) {
        // ignore parsing error
      }
      
      count++;
      if (count % 200 == 0) {
          if (onStatus != null) onStatus('已分析 $count / ${illustsMaps.length}...');
      }
    }

    if (onStatus != null) onStatus('正在写入数据库...');
    
    await db.transaction((txn) async {
       // Clear automatic links and reset counts
       await txn.delete(
        DownloadedIllustTagsColumns.tableName,
        where: '${DownloadedIllustTagsColumns.source} = ?',
        whereArgs: [0],
      );
      
      // Update DB
      int currentTag = 0;
      int totalTags = tagToIllusts.length;
      
      for (var entry in tagToIllusts.entries) {
        String tagName = entry.key;
        Set<int> illustIds = entry.value;
        String translation = tagTranslations[tagName] ?? '';
        
        // 1. Insert or Ignore Tag
        await txn.rawInsert('''
          INSERT OR IGNORE INTO ${DownloadedTagsColumns.tableName} 
          (${DownloadedTagsColumns.name}, ${DownloadedTagsColumns.translatedName})
          VALUES (?, ?)
        ''', [tagName, translation]);
        
        // 2. Prepare metadata
        List<int> sortedIllusts = illustIds.toList()..sort((a, b) => b.compareTo(a)); // Descending ID roughly means descending date
        String exampleIllusts = sortedIllusts.take(3).join(',');
        
        // 3. Update Tag Metadata
        await txn.update(
          DownloadedTagsColumns.tableName,
          {
            DownloadedTagsColumns.count: illustIds.length,
            DownloadedTagsColumns.exampleIllusts: exampleIllusts,
          },
          where: '${DownloadedTagsColumns.name} = ?',
          whereArgs: [tagName],
        );
        
        // 4. Get Tag ID
        final tagRows = await txn.query(
          DownloadedTagsColumns.tableName,
          columns: [DownloadedTagsColumns.id],
          where: '${DownloadedTagsColumns.name} = ?',
          whereArgs: [tagName],
        );
        
        if (tagRows.isNotEmpty) {
           int tagId = tagRows.first[DownloadedTagsColumns.id] as int;
           
           // 5. Insert Relations (Batch)
           Batch batch = txn.batch();
           for (int iId in illustIds) {
             batch.insert(
               DownloadedIllustTagsColumns.tableName,
               {
                 DownloadedIllustTagsColumns.illustId: iId,
                 DownloadedIllustTagsColumns.tagId: tagId,
                 DownloadedIllustTagsColumns.source: 0,
               },
               conflictAlgorithm: ConflictAlgorithm.ignore,
             );
           }
           await batch.commit(noResult: true);
        }
        
        currentTag++;
        if (currentTag % 50 == 0 && onStatus != null) {
          onStatus('正在同步标签 $currentTag / $totalTags...');
        }
      }
    });
  }
  
  bool processTags(String tag) {
    return true;
  }
}
