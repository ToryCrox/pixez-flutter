part of 'download_record.dart';

/// 支持的图片后缀名
const kImageExtensions = ['.webp', '.jpg', '.png', '.gif', '.jpeg'];

/// Tag变更类型
enum TagChangeType {
  illustAdded, // 插画被添加到此tag的关联
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
    this.tagId = 0,
    this.tagName = '',
    this.type = TagChangeType.illustAdded,
    this.illustId = 0,
    this.squareMediumUrl,
    this.newCount = 0,
    List<int> newExampleIllustIds = const [],
  }) : newExampleIllustIds = [...newExampleIllustIds];

  factory TagChangeEvent.fromMap(Map<String, dynamic> map) {
    final rawType = map['type'];
    final type = rawType is String
        ? TagChangeType.values.firstWhere(
            (value) => value.name == rawType,
            orElse: () => TagChangeType.illustAdded,
          )
        : TagChangeType.illustAdded;
    return TagChangeEvent(
      tagId: TypeUtil.parseInt(map['tag_id']),
      tagName: TypeUtil.parseString(map['tag_name']),
      type: type,
      illustId: TypeUtil.parseInt(map['illust_id']),
      squareMediumUrl: TypeUtil.parseNullableString(map['square_medium_url']),
      newCount: TypeUtil.parseInt(map['new_count']),
      newExampleIllustIds: TypeUtil.parseIntList(map['new_example_illust_ids']),
    );
  }

  factory TagChangeEvent.fromJson(Map<String, dynamic> json) =>
      TagChangeEvent.fromMap(json);

  Map<String, dynamic> toMap() => {
        'tag_id': tagId,
        'tag_name': tagName,
        'type': type.name,
        'illust_id': illustId,
        'square_medium_url': squareMediumUrl,
        'new_count': newCount,
        'new_example_illust_ids': [...newExampleIllustIds],
      };

  Map<String, dynamic> toJson() => toMap();

  bool get isEmpty =>
      TypeUtil.isEmpty(tagId) &&
      TypeUtil.isEmpty(tagName) &&
      type == TagChangeType.illustAdded &&
      TypeUtil.isEmpty(illustId) &&
      TypeUtil.isEmpty(squareMediumUrl) &&
      TypeUtil.isEmpty(newCount) &&
      newExampleIllustIds.isEmpty;

  TagChangeEvent copyWith({
    int? tagId,
    String? tagName,
    TagChangeType? type,
    int? illustId,
    Object? squareMediumUrl = TypeUtil.unset,
    int? newCount,
    List<int>? newExampleIllustIds,
  }) => TagChangeEvent(
        tagId: tagId ?? this.tagId,
        tagName: tagName ?? this.tagName,
        type: type ?? this.type,
        illustId: illustId ?? this.illustId,
        squareMediumUrl: identical(squareMediumUrl, TypeUtil.unset)
            ? this.squareMediumUrl
            : squareMediumUrl as String?,
        newCount: newCount ?? this.newCount,
        newExampleIllustIds:
            newExampleIllustIds ?? [...this.newExampleIllustIds],
      );

  @override
  bool operator ==(Object other) =>
      other is TagChangeEvent && TypeUtil.equal(toMap(), other.toMap());

  @override
  int get hashCode => TypeUtil.hash(toMap());

  @override
  String toString() => 'TagChangeEvent(${toMap()})';
}

// 下载的插画记录
class DownloadedIllust {
  static const String sourcePixiv = 'pixiv';
  static const String sourceLocal = 'local';

  final int? id;
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
  final int bookmark;
  final String translatedTitle;
  final String translatedCaption;
  final bool isTranslated;
  final String sourceType;
  final int? downloadRemovedAt;

  // imageUrlsJson 只在首次访问时解析，避免列表滚动/重建时重复解压和 JSON 解析。
  late final ImageUrls _imageUrlsCache = _parseImageUrls();
  // UgoiraMetadata 只在首次访问时解析，避免动图卡片重建时重复解压和 JSON 解析。
  late final UgoiraMetadata? _ugoiraMetadataCache = _parseUgoiraMetadata();

  // Getter 用于数据库序列化
  String get illustJson => _illustJson;

  /// 判断是否为动图
  bool get isUgoira => type == 'ugoira';

  DownloadedIllust({
    this.id,
    this.illustId = 0,
    this.userId = 0,
    this.userName = '',
    this.title = '',
    this.type = '',
    this.caption = '',
    this.createDate = '',
    this.pageCount = 0,
    this.width = 0,
    this.height = 0,
    this.sanityLevel = 0,
    this.xRestrict = 0,
    this.totalView = 0,
    this.totalBookmarks = 0,
    this.tags = '',
    this.relativePath = '',
    this.downloadTime = 0,
    String illustJson = '',
    this.imageUrlsJson = '',
    this.ugoiraMetadataJson = '',
    this.downloadedImageCount = 0,
    this.totalFileSize = 0,
    this.bookmark = 0,
    this.translatedTitle = '',
    this.translatedCaption = '',
    this.isTranslated = false,
    this.sourceType = sourcePixiv,
    this.downloadRemovedAt,
  }) : _illustJson = illustJson;

  bool get isLocal => sourceType == sourceLocal;

  bool get hasDownloadResources =>
      downloadedImageCount > 0 && downloadRemovedAt == null;

  /// 从 imageUrlsJson 解析 ImageUrls 对象
  ImageUrls getImageUrls() => _imageUrlsCache;

  ImageUrls _parseImageUrls() {
    if (imageUrlsJson.isEmpty) {
      return const ImageUrls();
    }
    return ImageUrls.fromJson(
      TypeUtil.parseMap(PixivUrlUtil.decompressPxUrl(imageUrlsJson)),
    );
  }

  /// 解析 UgoiraMetadata
  UgoiraMetadata? getUgoiraMetadata() => _ugoiraMetadataCache;

  UgoiraMetadata? _parseUgoiraMetadata() {
    if (!isUgoira || ugoiraMetadataJson.isEmpty) return null;
    try {
      final json = TypeUtil.parseMap(
        PixivUrlUtil.decompressPxUrl(ugoiraMetadataJson),
      );
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
    int? bookmark,
    String? translatedTitle,
    String? translatedCaption,
    bool? isTranslated,
    String sourceType = sourcePixiv,
    int? downloadRemovedAt,
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
      user: illusts.user.copyWith(id: 0, name: ''),
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
        illusts.tags.map((t) => TypeUtil.shrinkMap(t.toJson())).toList(),
      ),
      relativePath: relativePath,
      downloadTime: downloadTime ?? DateTime.now().millisecondsSinceEpoch,
      illustJson: PixivUrlUtil.compressPxUrl(
        TypeUtil.parseJsonString(shrunkJson),
      ),
      imageUrlsJson: PixivUrlUtil.compressPxUrl(
        TypeUtil.parseJsonString(illusts.imageUrls.toJson()),
      ),
      ugoiraMetadataJson: ugoiraMetadataJson ?? '',
      // 如果传入了统计信息则使用，否则默认为 0
      downloadedImageCount: downloadedImageCount ?? 0,
      totalFileSize: totalFileSize ?? 0,
      bookmark: bookmark ?? 0,
      translatedTitle: translatedTitle ?? '',
      translatedCaption: translatedCaption ?? '',
      isTranslated: isTranslated ?? false,
      sourceType: sourceType,
      downloadRemovedAt: downloadRemovedAt,
    );
  }

  DownloadedIllust copyWith({
    Object? id = TypeUtil.unset,
    int? downloadedImageCount,
    int? totalFileSize,
    int? bookmark,
    String? translatedTitle,
    String? translatedCaption,
    bool? isTranslated,
    String? sourceType,
    Object? downloadRemovedAt = TypeUtil.unset,
    bool clearDownloadRemovedAt = false,
  }) {
    return DownloadedIllust(
      id: identical(id, TypeUtil.unset) ? this.id : id as int?,
      illustId: illustId,
      userId: userId,
      userName: userName,
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
      tags: tags,
      relativePath: relativePath,
      downloadTime: downloadTime,
      illustJson: _illustJson,
      imageUrlsJson: imageUrlsJson,
      ugoiraMetadataJson: ugoiraMetadataJson,
      downloadedImageCount: downloadedImageCount ?? this.downloadedImageCount,
      totalFileSize: totalFileSize ?? this.totalFileSize,
      bookmark: bookmark ?? this.bookmark,
      translatedTitle: translatedTitle ?? this.translatedTitle,
      translatedCaption: translatedCaption ?? this.translatedCaption,
      isTranslated: isTranslated ?? this.isTranslated,
      sourceType: sourceType ?? this.sourceType,
      downloadRemovedAt: clearDownloadRemovedAt
          ? null
          : identical(downloadRemovedAt, TypeUtil.unset)
              ? this.downloadRemovedAt
              : downloadRemovedAt as int?,
    );
  }

  factory DownloadedIllust.fromJson(Map<String, dynamic> json) {
    return DownloadedIllust(
      id: TypeUtil.parseNullableInt(json[DownloadedIllustColumns.id]),
      illustId: TypeUtil.parseInt(json[DownloadedIllustColumns.illustId]),
      userId: TypeUtil.parseInt(json[DownloadedIllustColumns.userId]),
      userName: TypeUtil.parseString(json[DownloadedIllustColumns.userName]),
      title: TypeUtil.parseString(json[DownloadedIllustColumns.title]),
      type: TypeUtil.parseString(json[DownloadedIllustColumns.type]),
      caption: TypeUtil.parseString(json[DownloadedIllustColumns.caption]),
      createDate: TypeUtil.parseString(
        json[DownloadedIllustColumns.createDate],
      ),
      pageCount: TypeUtil.parseInt(json[DownloadedIllustColumns.pageCount]),
      width: TypeUtil.parseInt(json[DownloadedIllustColumns.width]),
      height: TypeUtil.parseInt(json[DownloadedIllustColumns.height]),
      sanityLevel: TypeUtil.parseInt(json[DownloadedIllustColumns.sanityLevel]),
      xRestrict: TypeUtil.parseInt(json[DownloadedIllustColumns.xRestrict]),
      totalView: TypeUtil.parseInt(json[DownloadedIllustColumns.totalView]),
      totalBookmarks: TypeUtil.parseInt(
        json[DownloadedIllustColumns.totalBookmarks],
      ),
      tags: TypeUtil.parseString(json[DownloadedIllustColumns.tags]),
      relativePath: TypeUtil.parseString(
        json[DownloadedIllustColumns.relativePath],
      ),
      downloadTime: TypeUtil.parseInt(
        json[DownloadedIllustColumns.downloadTime],
      ),
      illustJson: TypeUtil.gzipDecodeString(
        TypeUtil.parseString(json[DownloadedIllustColumns.illustJson]),
      ),
      imageUrlsJson: TypeUtil.parseString(
        json[DownloadedIllustColumns.imageUrlsJson],
      ), // 兼容旧数据
      ugoiraMetadataJson: TypeUtil.parseString(
        json[DownloadedIllustColumns.ugoiraMetadataJson],
      ), // 兼容旧数据
      downloadedImageCount: TypeUtil.parseInt(
        json[DownloadedIllustColumns.downloadedImageCount],
      ),
      totalFileSize: TypeUtil.parseInt(
        json[DownloadedIllustColumns.totalFileSize],
      ),
      bookmark: TypeUtil.parseInt(json[DownloadedIllustColumns.bookmark]),
      translatedTitle: TypeUtil.parseString(
        json[DownloadedIllustColumns.translatedTitle],
      ),
      translatedCaption: TypeUtil.parseString(
        json[DownloadedIllustColumns.translatedCaption],
      ),
      isTranslated:
          TypeUtil.parseInt(json[DownloadedIllustColumns.isTranslated]) != 0,
      sourceType:
          TypeUtil.parseString(json[DownloadedIllustColumns.sourceType]).isEmpty
              ? sourcePixiv
              : TypeUtil.parseString(json[DownloadedIllustColumns.sourceType]),
      downloadRemovedAt:
          json[DownloadedIllustColumns.downloadRemovedAt] == null
              ? null
              : TypeUtil.parseInt(
                json[DownloadedIllustColumns.downloadRemovedAt],
              ),
    );
  }

  factory DownloadedIllust.fromMap(Map<String, dynamic> map) =>
      DownloadedIllust.fromJson(map);

  Map<String, dynamic> toJson({bool includeId = false}) {
    final Map<String, dynamic> data = {};
    if (includeId && id != null) data[DownloadedIllustColumns.id] = id;
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
    data[DownloadedIllustColumns.illustJson] = TypeUtil.gzipEncodeString(
      illustJson,
    );
    data[DownloadedIllustColumns.imageUrlsJson] = imageUrlsJson;
    data[DownloadedIllustColumns.ugoiraMetadataJson] = ugoiraMetadataJson;
    data[DownloadedIllustColumns.downloadedImageCount] = downloadedImageCount;
    data[DownloadedIllustColumns.totalFileSize] = totalFileSize;
    data[DownloadedIllustColumns.bookmark] = bookmark;
    data[DownloadedIllustColumns.translatedTitle] = translatedTitle;
    data[DownloadedIllustColumns.translatedCaption] = translatedCaption;
    data[DownloadedIllustColumns.isTranslated] = isTranslated ? 1 : 0;
    data[DownloadedIllustColumns.sourceType] = sourceType;
    data[DownloadedIllustColumns.downloadRemovedAt] = downloadRemovedAt;
    return data;
  }

  Map<String, dynamic> toMap({bool includeId = false}) =>
      toJson(includeId: includeId);

  bool get isEmpty =>
      (id == null || id == 0) &&
      illustId == 0 &&
      userId == 0 &&
      userName.isEmpty &&
      title.isEmpty &&
      type.isEmpty &&
      caption.isEmpty &&
      createDate.isEmpty &&
      pageCount == 0 &&
      width == 0 &&
      height == 0 &&
      sanityLevel == 0 &&
      xRestrict == 0 &&
      totalView == 0 &&
      totalBookmarks == 0 &&
      tags.isEmpty &&
      relativePath.isEmpty &&
      downloadTime == 0 &&
      _illustJson.isEmpty &&
      imageUrlsJson.isEmpty &&
      ugoiraMetadataJson.isEmpty &&
      downloadedImageCount == 0 &&
      totalFileSize == 0 &&
      bookmark == 0 &&
      translatedTitle.isEmpty &&
      translatedCaption.isEmpty &&
      !isTranslated &&
      sourceType == sourcePixiv &&
      downloadRemovedAt == null;

  @override
  bool operator ==(Object other) =>
      other is DownloadedIllust &&
      TypeUtil.equal(toMap(includeId: true), other.toMap(includeId: true));

  @override
  int get hashCode => TypeUtil.hash(toMap(includeId: true));

  @override
  String toString() => 'DownloadedIllust(${toMap(includeId: true)})';

  // 缓存 Illusts 对象，避免重复解析
  late final Illusts _illustsCache = _parseIllusts();

  Illusts toIllusts() => _illustsCache;

  Illusts _parseIllusts() {
    // 使用 TypeUtil.parseMap 安全地将字符串转换为 Map（先解压 URL 前缀）
    final json = TypeUtil.parseMap(PixivUrlUtil.decompressPxUrl(_illustJson));

    // 先从 illustJson 转换成 Illusts（即使 json 为空也能创建默认对象）
    final baseIllusts = Illusts.fromJson(json);

    // 解析 imageUrls：优先从独立字段读取，兼容旧数据回退到 illustJson
    ImageUrls imageUrls;
    if (imageUrlsJson.isNotEmpty) {
      imageUrls = ImageUrls.fromJson(
        TypeUtil.parseMap(PixivUrlUtil.decompressPxUrl(imageUrlsJson)),
      );
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
      user: baseIllusts.user.copyWith(id: userId, name: userName),
      isBookmarked: bookmark > 0,
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

  const LocalImageInfo({
    this.path = '',
    this.width,
    this.height,
    this.fileSize,
  });

  factory LocalImageInfo.fromMap(Map<String, dynamic> map) => LocalImageInfo(
        path: TypeUtil.parseString(map['path']),
        width: TypeUtil.parseNullableInt(map['width']),
        height: TypeUtil.parseNullableInt(map['height']),
        fileSize: TypeUtil.parseNullableInt(map['file_size']),
      );

  factory LocalImageInfo.fromJson(Map<String, dynamic> json) =>
      LocalImageInfo.fromMap(json);

  Map<String, dynamic> toMap() => {
        'path': path,
        'width': width,
        'height': height,
        'file_size': fileSize,
      };

  Map<String, dynamic> toJson() => toMap();

  bool get isEmpty =>
      path.isEmpty && width == null && height == null && fileSize == null;

  LocalImageInfo copyWith({
    String? path,
    Object? width = TypeUtil.unset,
    Object? height = TypeUtil.unset,
    Object? fileSize = TypeUtil.unset,
  }) => LocalImageInfo(
        path: path ?? this.path,
        width: identical(width, TypeUtil.unset) ? this.width : width as int?,
        height:
            identical(height, TypeUtil.unset) ? this.height : height as int?,
        fileSize: identical(fileSize, TypeUtil.unset)
            ? this.fileSize
            : fileSize as int?,
      );

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
  /// 动图合并后的 WebP 文件标识
  static const int partUgoiraWebP = -1;

  final int? id;
  final int illustId;
  final int part;
  final String fileName;
  final String extension;
  final int fileSize;
  final String originalUrl;
  final int? width; // 图片宽度
  final int? height; // 图片高度

  const DownloadedImage({
    this.id,
    this.illustId = 0,
    this.part = 0,
    this.fileName = '',
    this.extension = '',
    this.fileSize = 0,
    this.originalUrl = '',
    this.width,
    this.height,
  });

  factory DownloadedImage.fromJson(Map<String, dynamic> json) {
    // 从数据库读取时解压 URL
    final compressedUrl = TypeUtil.parseString(
      json[DownloadedImageColumns.originalUrl],
    );
    return DownloadedImage(
      id: TypeUtil.parseNullableInt(json[DownloadedImageColumns.id]),
      illustId: TypeUtil.parseInt(json[DownloadedImageColumns.illustId]),
      part: TypeUtil.parseInt(json[DownloadedImageColumns.part]),
      fileName: TypeUtil.parseString(json[DownloadedImageColumns.fileName]),
      extension: TypeUtil.parseString(json[DownloadedImageColumns.extension]),
      fileSize: TypeUtil.parseInt(json[DownloadedImageColumns.fileSize]),
      originalUrl: PixivUrlUtil.decompressOriginalUrl(compressedUrl),
      width: TypeUtil.parseNullableInt(json[DownloadedImageColumns.width]),
      height: TypeUtil.parseNullableInt(json[DownloadedImageColumns.height]),
    );
  }

  factory DownloadedImage.fromMap(Map<String, dynamic> map) =>
      DownloadedImage.fromJson(map);

  Map<String, dynamic> toJson({bool includeId = false}) {
    final Map<String, dynamic> data = {};
    if (includeId && id != null) data[DownloadedImageColumns.id] = id;
    data[DownloadedImageColumns.illustId] = illustId;
    data[DownloadedImageColumns.part] = part;
    data[DownloadedImageColumns.fileName] = fileName;
    data[DownloadedImageColumns.extension] = extension;
    data[DownloadedImageColumns.fileSize] = fileSize;
    // 写入数据库时压缩 URL
    data[DownloadedImageColumns.originalUrl] = PixivUrlUtil.compressOriginalUrl(
      originalUrl,
    );
    data[DownloadedImageColumns.width] = width;
    data[DownloadedImageColumns.height] = height;
    return data;
  }

  Map<String, dynamic> toMap({bool includeId = false}) =>
      toJson(includeId: includeId);

  bool get isEmpty =>
      (id == null || id == 0) &&
      illustId == 0 &&
      part == 0 &&
      fileName.isEmpty &&
      extension.isEmpty &&
      fileSize == 0 &&
      originalUrl.isEmpty &&
      width == null &&
      height == null;

  String getFullFileName() => '$fileName$extension';

  /// 获取图片宽高比（width / height），如果宽高未知则返回 null
  double? get aspectRatio {
    if (width != null && height != null && height! > 0) {
      return width! / height!;
    }
    return null;
  }

  DownloadedImage copyWith({
    Object? id = TypeUtil.unset,
    int? illustId,
    int? part,
    String? fileName,
    String? extension,
    int? fileSize,
    String? originalUrl,
    Object? width = TypeUtil.unset,
    Object? height = TypeUtil.unset,
  }) {
    return DownloadedImage(
      id: identical(id, TypeUtil.unset) ? this.id : id as int?,
      illustId: illustId ?? this.illustId,
      part: part ?? this.part,
      fileName: fileName ?? this.fileName,
      extension: extension ?? this.extension,
      fileSize: fileSize ?? this.fileSize,
      originalUrl: originalUrl ?? this.originalUrl,
      width: identical(width, TypeUtil.unset) ? this.width : width as int?,
      height:
          identical(height, TypeUtil.unset) ? this.height : height as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DownloadedImage &&
      TypeUtil.equal(toMap(includeId: true), other.toMap(includeId: true));

  @override
  int get hashCode => TypeUtil.hash(toMap(includeId: true));

  @override
  String toString() => 'DownloadedImage(${toMap(includeId: true)})';
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
  static const String bookmark = 'bookmark';
  static const String translatedTitle = 'translated_title';
  static const String translatedCaption = 'translated_caption';
  static const String isTranslated = 'is_translated';
  static const String sourceType = 'source_type';
  static const String downloadRemovedAt = 'download_removed_at';
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
  static const String bookmark = 'bookmark';
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
  static const String parentId = 'parent_id';
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
  static const String totalImageCount = 'total_image_count';
  static const String totalFileSize = 'total_file_size';
  static const String lastDownloadTime = 'last_download_time';
  static const String lastUpdateTime = 'last_update_time';
  static const String bookmark = 'bookmark';
}

class PendingDownload {
  final String id;
  final int part;
  final String url;
  final String illustJson;
  final int createTime;
  final String status;
  final int bookmark;

  const PendingDownload({
    this.id = '',
    this.part = 0,
    this.url = '',
    this.illustJson = '',
    this.createTime = 0,
    this.status = 'pending',
    this.bookmark = 0,
  });

  factory PendingDownload.fromJson(Map<String, dynamic> json) {
    return PendingDownload(
      id: TypeUtil.parseString(json[PendingDownloadColumns.id]),
      part: TypeUtil.parseInt(json[PendingDownloadColumns.part]),
      url: TypeUtil.parseString(json[PendingDownloadColumns.url]),
      illustJson: TypeUtil.parseString(json[PendingDownloadColumns.illustJson]),
      createTime: TypeUtil.parseInt(json[PendingDownloadColumns.createTime]),
      status: TypeUtil.parseString(
        json[PendingDownloadColumns.status],
        'pending',
      ),
      bookmark: TypeUtil.parseInt(json[PendingDownloadColumns.bookmark]),
    );
  }

  factory PendingDownload.fromMap(Map<String, dynamic> map) =>
      PendingDownload.fromJson(map);

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data[PendingDownloadColumns.id] = id;
    data[PendingDownloadColumns.part] = part;
    data[PendingDownloadColumns.url] = url;
    data[PendingDownloadColumns.illustJson] = illustJson;
    data[PendingDownloadColumns.createTime] = createTime;
    data[PendingDownloadColumns.status] = status;
    data[PendingDownloadColumns.bookmark] = bookmark;
    return data;
  }

  Map<String, dynamic> toMap() => toJson();

  bool get isEmpty =>
      id.isEmpty &&
      part == 0 &&
      url.isEmpty &&
      illustJson.isEmpty &&
      createTime == 0 &&
      status == 'pending' &&
      bookmark == 0;

  PendingDownload copyWith({
    String? id,
    int? part,
    String? url,
    String? illustJson,
    int? createTime,
    String? status,
    int? bookmark,
  }) => PendingDownload(
        id: id ?? this.id,
        part: part ?? this.part,
        url: url ?? this.url,
        illustJson: illustJson ?? this.illustJson,
        createTime: createTime ?? this.createTime,
        status: status ?? this.status,
        bookmark: bookmark ?? this.bookmark,
      );

  @override
  bool operator ==(Object other) =>
      other is PendingDownload && TypeUtil.equal(toMap(), other.toMap());

  @override
  int get hashCode => TypeUtil.hash(toMap());

  @override
  String toString() => 'PendingDownload(${toMap()})';
}

// 下载的作者记录
class DownloadedAuthor {
  final int userId;
  final String userName;
  final String? profileImageUrl;
  final int illustCount;
  final int totalImageCount;
  final int totalFileSize;
  final int lastDownloadTime;
  final int lastUpdateTime;
  final int bookmark;

  const DownloadedAuthor({
    this.userId = 0,
    this.userName = '',
    this.profileImageUrl,
    this.illustCount = 0,
    this.totalImageCount = 0,
    this.totalFileSize = 0,
    this.lastDownloadTime = 0,
    this.lastUpdateTime = 0,
    this.bookmark = 0,
  });

  factory DownloadedAuthor.fromJson(Map<String, dynamic> json) {
    final profileImageUrl = TypeUtil.parseNullableString(
      json[DownloadedAuthorColumns.profileImageUrl],
    );
    return DownloadedAuthor(
      userId: TypeUtil.parseInt(json[DownloadedAuthorColumns.userId]),
      userName: TypeUtil.parseString(json[DownloadedAuthorColumns.userName]),
      profileImageUrl: profileImageUrl == null
          ? null
          : PixivUrlUtil.decompressPxUrl(profileImageUrl),
      illustCount: TypeUtil.parseInt(json[DownloadedAuthorColumns.illustCount]),
      totalImageCount: TypeUtil.parseInt(
        json[DownloadedAuthorColumns.totalImageCount],
      ),
      totalFileSize: TypeUtil.parseInt(
        json[DownloadedAuthorColumns.totalFileSize],
      ),
      lastDownloadTime: TypeUtil.parseInt(
        json[DownloadedAuthorColumns.lastDownloadTime],
      ),
      lastUpdateTime: TypeUtil.parseInt(
        json[DownloadedAuthorColumns.lastUpdateTime],
      ),
      bookmark: TypeUtil.parseInt(json[DownloadedAuthorColumns.bookmark]),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data[DownloadedAuthorColumns.userId] = userId;
    data[DownloadedAuthorColumns.userName] = userName;
    if (profileImageUrl != null) {
      data[DownloadedAuthorColumns
          .profileImageUrl] = PixivUrlUtil.compressPxUrl(profileImageUrl!);
    }
    data[DownloadedAuthorColumns.illustCount] = illustCount;
    data[DownloadedAuthorColumns.totalImageCount] = totalImageCount;
    data[DownloadedAuthorColumns.totalFileSize] = totalFileSize;
    data[DownloadedAuthorColumns.lastDownloadTime] = lastDownloadTime;
    data[DownloadedAuthorColumns.lastUpdateTime] = lastUpdateTime;
    data[DownloadedAuthorColumns.bookmark] = bookmark;
    return data;
  }

  factory DownloadedAuthor.fromMap(Map<String, dynamic> map) =>
      DownloadedAuthor.fromJson(map);

  Map<String, dynamic> toMap() => toJson();

  bool get isEmpty =>
      userId == 0 &&
      userName.isEmpty &&
      profileImageUrl == null &&
      illustCount == 0 &&
      totalImageCount == 0 &&
      totalFileSize == 0 &&
      lastDownloadTime == 0 &&
      lastUpdateTime == 0 &&
      bookmark == 0;

  DownloadedAuthor copyWith({
    int? userId,
    String? userName,
    Object? profileImageUrl = TypeUtil.unset,
    int? illustCount,
    int? totalImageCount,
    int? totalFileSize,
    int? lastDownloadTime,
    int? lastUpdateTime,
    int? bookmark,
  }) => DownloadedAuthor(
        userId: userId ?? this.userId,
        userName: userName ?? this.userName,
        profileImageUrl: identical(profileImageUrl, TypeUtil.unset)
            ? this.profileImageUrl
            : profileImageUrl as String?,
        illustCount: illustCount ?? this.illustCount,
        totalImageCount: totalImageCount ?? this.totalImageCount,
        totalFileSize: totalFileSize ?? this.totalFileSize,
        lastDownloadTime: lastDownloadTime ?? this.lastDownloadTime,
        lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
        bookmark: bookmark ?? this.bookmark,
      );

  @override
  bool operator ==(Object other) =>
      other is DownloadedAuthor && TypeUtil.equal(toMap(), other.toMap());

  @override
  int get hashCode => TypeUtil.hash(toMap());

  @override
  String toString() => 'DownloadedAuthor(${toMap()})';
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
  final int parentId;

  const DownloadedTag({
    this.id = 0,
    this.name = '',
    this.translatedName = '',
    this.category = 0,
    this.customTranslatedName,
    this.count = 0,
    this.isBookmarked = false,
    this.displayOrder = 0,
    this.lastUsedTime,
    this.exampleIllusts = '',
    this.referencedTagId = 0,
    this.parentId = 0,
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

  bool get isCustomTranslatedName => customTranslatedName?.isNotEmpty == true;

  TagCategory get categoryEnum => TagCategory.fromValue(category);

  List<int> get exampleIllustIds {
    if (exampleIllusts.isEmpty) return [];
    return exampleIllusts
        .split(',')
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .toList();
  }

  factory DownloadedTag.fromJson(Map<String, dynamic> json) {
    return DownloadedTag(
      id: TypeUtil.parseInt(json[DownloadedTagsColumns.id]),
      name: TypeUtil.parseString(json[DownloadedTagsColumns.name]),
      translatedName: TypeUtil.parseString(
        json[DownloadedTagsColumns.translatedName],
      ),
      customTranslatedName: TypeUtil.parseNullableString(
        json[DownloadedTagsColumns.customTranslatedName],
      ),
      category: TypeUtil.parseInt(json[DownloadedTagsColumns.category]),
      isBookmarked:
          TypeUtil.parseInt(json[DownloadedTagsColumns.isBookmarked]) == 1,
      displayOrder: TypeUtil.parseInt(json[DownloadedTagsColumns.displayOrder]),
      lastUsedTime: TypeUtil.parseNullableInt(
        json[DownloadedTagsColumns.lastUsedTime],
      ),
      count: TypeUtil.parseInt(json[DownloadedTagsColumns.count]),
      exampleIllusts: TypeUtil.parseString(
        json[DownloadedTagsColumns.exampleIllusts],
      ),
      referencedTagId: TypeUtil.parseInt(
        json[DownloadedTagsColumns.referencedTagId],
      ),
      parentId: TypeUtil.parseInt(json[DownloadedTagsColumns.parentId]),
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
      DownloadedTagsColumns.referencedTagId:
          referencedTagId == 0 ? null : referencedTagId,
      DownloadedTagsColumns.parentId: parentId == 0 ? null : parentId,
    };
  }

  factory DownloadedTag.fromMap(Map<String, dynamic> map) =>
      DownloadedTag.fromJson(map);

  Map<String, dynamic> toMap() => toJson();

  bool get isEmpty =>
      id == 0 &&
      name.isEmpty &&
      translatedName.isEmpty &&
      customTranslatedName == null &&
      category == 0 &&
      count == 0 &&
      !isBookmarked &&
      displayOrder == 0 &&
      lastUsedTime == null &&
      exampleIllusts.isEmpty &&
      referencedTagId == 0 &&
      parentId == 0;

  DownloadedTag copyWith({
    int? id,
    String? name,
    String? translatedName,
    int? category,
    Object? customTranslatedName = TypeUtil.unset,
    int? count,
    bool? isBookmarked,
    int? displayOrder,
    Object? lastUsedTime = TypeUtil.unset,
    String? exampleIllusts,
    int? referencedTagId,
    int? parentId,
  }) {
    return DownloadedTag(
      id: id ?? this.id,
      name: name ?? this.name,
      translatedName: translatedName ?? this.translatedName,
      category: category ?? this.category,
      customTranslatedName: identical(customTranslatedName, TypeUtil.unset)
          ? this.customTranslatedName
          : customTranslatedName as String?,
      count: count ?? this.count,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      displayOrder: displayOrder ?? this.displayOrder,
      lastUsedTime: identical(lastUsedTime, TypeUtil.unset)
          ? this.lastUsedTime
          : lastUsedTime as int?,
      exampleIllusts: exampleIllusts ?? this.exampleIllusts,
      referencedTagId: referencedTagId ?? this.referencedTagId,
      parentId: parentId ?? this.parentId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DownloadedTag && TypeUtil.equal(toMap(), other.toMap());

  @override
  int get hashCode => TypeUtil.hash(toMap());

  @override
  String toString() => 'DownloadedTag(${toMap()})';
}

class IllustPreviewData {
  final int illustId;
  final String squareMediumUrl;

  const IllustPreviewData({
    this.illustId = 0,
    this.squareMediumUrl = '',
  });

  factory IllustPreviewData.fromMap(Map<String, dynamic> map) =>
      IllustPreviewData(
        illustId: TypeUtil.parseInt(map['illust_id']),
        squareMediumUrl: TypeUtil.parseString(map['square_medium_url']),
      );

  factory IllustPreviewData.fromJson(Map<String, dynamic> json) =>
      IllustPreviewData.fromMap(json);

  Map<String, dynamic> toMap() => {
        'illust_id': illustId,
        'square_medium_url': squareMediumUrl,
      };

  Map<String, dynamic> toJson() => toMap();

  bool get isEmpty => illustId == 0 && squareMediumUrl.isEmpty;

  IllustPreviewData copyWith({int? illustId, String? squareMediumUrl}) =>
      IllustPreviewData(
        illustId: illustId ?? this.illustId,
        squareMediumUrl: squareMediumUrl ?? this.squareMediumUrl,
      );

  @override
  bool operator ==(Object other) =>
      other is IllustPreviewData && TypeUtil.equal(toMap(), other.toMap());

  @override
  int get hashCode => TypeUtil.hash(toMap());

  @override
  String toString() => 'IllustPreviewData(${toMap()})';
}

class TagDisplayData {
  final DownloadedTag tag;
  final List<IllustPreviewData> previewIllusts;
  final bool hasEquivalentTags;
  final int indentLevel;

  TagDisplayData({
    this.tag = const DownloadedTag(),
    List<IllustPreviewData> previewIllusts = const [],
    this.hasEquivalentTags = false,
    this.indentLevel = 0,
  }) : previewIllusts = [...previewIllusts];

  factory TagDisplayData.fromMap(Map<String, dynamic> map) => TagDisplayData(
        tag: DownloadedTag.fromMap(TypeUtil.parseMap(map['tag'])),
        previewIllusts: TypeUtil.parseList(
          map['preview_illusts'],
          (value) => IllustPreviewData.fromMap(TypeUtil.parseMap(value)),
        ),
        hasEquivalentTags: TypeUtil.parseBool(map['has_equivalent_tags']),
        indentLevel: TypeUtil.parseInt(map['indent_level']),
      );

  factory TagDisplayData.fromJson(Map<String, dynamic> json) =>
      TagDisplayData.fromMap(json);

  Map<String, dynamic> toMap() => {
        'tag': tag.toMap(),
        'preview_illusts': previewIllusts.map((e) => e.toMap()).toList(),
        'has_equivalent_tags': hasEquivalentTags,
        'indent_level': indentLevel,
      };

  Map<String, dynamic> toJson() => toMap();

  bool get isEmpty =>
      tag.isEmpty &&
      previewIllusts.isEmpty &&
      !hasEquivalentTags &&
      indentLevel == 0;

  TagDisplayData copyWith({
    DownloadedTag? tag,
    List<IllustPreviewData>? previewIllusts,
    bool? hasEquivalentTags,
    int? indentLevel,
  }) {
    return TagDisplayData(
      tag: tag ?? this.tag,
      previewIllusts: previewIllusts ?? [...this.previewIllusts],
      hasEquivalentTags: hasEquivalentTags ?? this.hasEquivalentTags,
      indentLevel: indentLevel ?? this.indentLevel,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TagDisplayData && TypeUtil.equal(toMap(), other.toMap());

  @override
  int get hashCode => TypeUtil.hash(toMap());

  @override
  String toString() => 'TagDisplayData(${toMap()})';
}
