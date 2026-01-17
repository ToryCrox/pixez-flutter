part of 'download_record.dart';

/// 支持的图片后缀名
const kImageExtensions = ['.webp', '.jpg', '.png', '.gif', '.jpeg'];

/// Tag变更类型
enum TagChangeType {
  illustAdded,   // 插画被添加到此tag的关联
  illustRemoved, // 插画从此tag的关联中移除
}

/// Tag变更事件
class TagChangeEvent {
  final int tagId;
  final String tagName;
  final TagChangeType type;

  // 发生变化的插画信息
  final int illustId;
  final String? squareMediumUrl; // 用于更新 previewIllusts（添加时需要）

  // 更新后的统计信息
  final int newCount;
  final List<int> newExampleIllustIds;

  TagChangeEvent({
    required this.tagId,
    required this.tagName,
    required this.type,
    required this.illustId,
    this.squareMediumUrl,
    required this.newCount,
    required this.newExampleIllustIds,
  });
}

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
  // 统计字段（物化）
  final int downloadedImageCount; // 已下载图片数量
  final int totalFileSize; // 总文件大小（字节）

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
    this.downloadedImageCount = 0,
    this.totalFileSize = 0,
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
    int? downloadedImageCount,
    int? totalFileSize,
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
      // 如果传入了统计信息则使用，否则默认为 0
      downloadedImageCount: downloadedImageCount ?? 0,
      totalFileSize: totalFileSize ?? 0,
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
      downloadedImageCount: TypeUtil.parseInt(json[DownloadedIllustColumns.downloadedImageCount]),
      totalFileSize: TypeUtil.parseInt(json[DownloadedIllustColumns.totalFileSize]),
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
    data[DownloadedIllustColumns.downloadedImageCount] = downloadedImageCount;
    data[DownloadedIllustColumns.totalFileSize] = totalFileSize;
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
  static const String imageUrlsJson = 'image_urls_json';
  static const String ugoiraMetadataJson = 'ugoira_metadata_json';
  // 统计字段（物化）
  static const String downloadedImageCount = 'downloaded_image_count';
  static const String totalFileSize = 'total_file_size';
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
  final int referencedTagId;

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
    this.referencedTagId = 0,
  });


  String get displayName =>
      (customTranslatedName != null && customTranslatedName!.isNotEmpty)
          ? customTranslatedName!
          : (translatedName.isNotEmpty)
              ? translatedName
              : name;

  /// 翻译的名字
  String get displayTranslatedName =>
      (customTranslatedName != null && customTranslatedName!.isNotEmpty)
          ? customTranslatedName!
          : (translatedName.isNotEmpty)
              ? translatedName
              : '';

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
      referencedTagId: TypeUtil.parseInt(json[DownloadedTagsColumns.referencedTagId]),
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
      DownloadedTagsColumns.referencedTagId: referencedTagId == 0 ? null : referencedTagId,
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

    TagDisplayData copyWith({
      DownloadedTag? tag,
      List<IllustPreviewData>? previewIllusts,
      bool? hasEquivalentTags,
    }) {
      return TagDisplayData(
        tag: tag ?? this.tag,
        previewIllusts: previewIllusts ?? this.previewIllusts,
        hasEquivalentTags: hasEquivalentTags ?? this.hasEquivalentTags,
      );
    }
}
