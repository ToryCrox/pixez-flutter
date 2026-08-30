import 'package:pixez/custom/type_util.dart';
import 'package:pixez/models/download_record.dart';

enum OriginalRelationType {
  replacement('replacement'),
  originalOnly('original_only'),
  downloadFallback('download_fallback');

  final String value;
  const OriginalRelationType(this.value);

  static OriginalRelationType fromValue(String value) {
    for (final item in values) {
      if (item.value == value) return item;
    }
    return originalOnly;
  }
}

enum OriginalDisplayMode { originalPreferred, downloaded }

class OriginalImageSet {
  final int? id;
  final int illustId;
  final String editionName;
  final String storageKey;
  final String relativePath;
  final String lastSourcePath;
  final String sourceFolderName;
  final String directoryFingerprint;
  final int imageCount;
  final int totalFileSize;
  final int enhancedPageCount;
  final bool isDefault;
  final int createdAt;
  final int updatedAt;

  const OriginalImageSet({
    this.id,
    this.illustId = 0,
    this.editionName = '',
    this.storageKey = '',
    this.relativePath = '',
    this.lastSourcePath = '',
    this.sourceFolderName = '',
    this.directoryFingerprint = '',
    this.imageCount = 0,
    this.totalFileSize = 0,
    this.enhancedPageCount = 0,
    this.isDefault = false,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  factory OriginalImageSet.fromMap(Map<String, Object?> map) => OriginalImageSet(
        id: TypeUtil.parseNullableInt(map['id']),
        illustId: TypeUtil.parseInt(map['illust_id']),
        editionName: TypeUtil.parseString(map['edition_name']),
        storageKey: TypeUtil.parseString(map['storage_key']),
        relativePath: TypeUtil.parseString(map['relative_path']),
        lastSourcePath: TypeUtil.parseString(map['last_source_path']),
        sourceFolderName: TypeUtil.parseString(map['source_folder_name']),
        directoryFingerprint: TypeUtil.parseString(map['directory_fingerprint']),
        imageCount: TypeUtil.parseInt(map['image_count']),
        totalFileSize: TypeUtil.parseInt(map['total_file_size']),
        enhancedPageCount: TypeUtil.parseInt(map['enhanced_page_count']),
        isDefault: TypeUtil.parseBool(map['is_default']),
        createdAt: TypeUtil.parseInt(map['created_at']),
        updatedAt: TypeUtil.parseInt(map['updated_at']),
      );
  factory OriginalImageSet.fromJson(Map<String, dynamic> json) => OriginalImageSet.fromMap(json);
  Map<String, Object?> toMap({bool includeId = false}) => {
        if (includeId && id != null) 'id': id,
        'illust_id': illustId, 'edition_name': editionName, 'storage_key': storageKey,
        'relative_path': relativePath, 'last_source_path': lastSourcePath,
        'source_folder_name': sourceFolderName, 'directory_fingerprint': directoryFingerprint,
        'image_count': imageCount, 'total_file_size': totalFileSize,
        'enhanced_page_count': enhancedPageCount, 'is_default': isDefault ? 1 : 0,
        'created_at': createdAt, 'updated_at': updatedAt,
      };
  Map<String, Object?> toJson({bool includeId = false}) => toMap(includeId: includeId);
  bool get isEmpty => (id == null || id == 0) && illustId == 0 && editionName.isEmpty &&
      storageKey.isEmpty && relativePath.isEmpty && lastSourcePath.isEmpty &&
      sourceFolderName.isEmpty && directoryFingerprint.isEmpty && imageCount == 0 &&
      totalFileSize == 0 && enhancedPageCount == 0 && !isDefault &&
      createdAt == 0 && updatedAt == 0;
  OriginalImageSet copyWith({
    Object? id = TypeUtil.unset, int? illustId, String? editionName,
    String? storageKey, String? relativePath, String? lastSourcePath,
    String? sourceFolderName, String? directoryFingerprint, int? imageCount,
    int? totalFileSize, int? enhancedPageCount, bool? isDefault, int? createdAt,
    int? updatedAt,
  }) => OriginalImageSet(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        illustId: illustId ?? this.illustId, editionName: editionName ?? this.editionName,
        storageKey: storageKey ?? this.storageKey, relativePath: relativePath ?? this.relativePath,
        lastSourcePath: lastSourcePath ?? this.lastSourcePath,
        sourceFolderName: sourceFolderName ?? this.sourceFolderName,
        directoryFingerprint: directoryFingerprint ?? this.directoryFingerprint,
        imageCount: imageCount ?? this.imageCount, totalFileSize: totalFileSize ?? this.totalFileSize,
        enhancedPageCount: enhancedPageCount ?? this.enhancedPageCount,
        isDefault: isDefault ?? this.isDefault, createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  @override
  bool operator ==(Object other) => other is OriginalImageSet && TypeUtil.equal(toMap(includeId: true), other.toMap(includeId: true));
  @override
  int get hashCode => TypeUtil.hash(toMap(includeId: true));
  @override
  String toString() => 'OriginalImageSet(${toMap(includeId: true)})';
}

class OriginalImage {
  final int? id;
  final int setId;
  final int sourceOrder;
  final String fileName;
  final String relativePath;
  final String extension;
  final int fileSize;
  final int? width;
  final int? height;
  final String sha256;
  final String perceptualHash;

  const OriginalImage({
    this.id,
    this.setId = 0,
    this.sourceOrder = 0,
    this.fileName = '',
    this.relativePath = '',
    this.extension = '',
    this.fileSize = 0,
    this.width,
    this.height,
    this.sha256 = '',
    this.perceptualHash = '',
  });
  factory OriginalImage.fromMap(Map<String, Object?> map) => OriginalImage(
        id: TypeUtil.parseNullableInt(map['id']), setId: TypeUtil.parseInt(map['set_id']),
        sourceOrder: TypeUtil.parseInt(map['source_order']), fileName: TypeUtil.parseString(map['file_name']),
        relativePath: TypeUtil.parseString(map['relative_path']), extension: TypeUtil.parseString(map['extension']),
        fileSize: TypeUtil.parseInt(map['file_size']), width: TypeUtil.parseNullableInt(map['width']),
        height: TypeUtil.parseNullableInt(map['height']), sha256: TypeUtil.parseString(map['sha256']),
        perceptualHash: TypeUtil.parseString(map['perceptual_hash']),
      );
  factory OriginalImage.fromJson(Map<String, dynamic> json) => OriginalImage.fromMap(json);
  Map<String, Object?> toMap({bool includeId = false}) => {
        if (includeId && id != null) 'id': id,
        'set_id': setId, 'source_order': sourceOrder, 'file_name': fileName,
        'relative_path': relativePath, 'extension': extension, 'file_size': fileSize,
        'width': width, 'height': height, 'sha256': sha256, 'perceptual_hash': perceptualHash,
      };
  Map<String, Object?> toJson({bool includeId = false}) => toMap(includeId: includeId);
  bool get isEmpty => (id == null || id == 0) && setId == 0 && sourceOrder == 0 &&
      fileName.isEmpty && relativePath.isEmpty && extension.isEmpty && fileSize == 0 &&
      width == null && height == null && sha256.isEmpty && perceptualHash.isEmpty;
  OriginalImage copyWith({
    Object? id = TypeUtil.unset, int? setId, int? sourceOrder, String? fileName,
    String? relativePath, String? extension, int? fileSize,
    Object? width = TypeUtil.unset, Object? height = TypeUtil.unset,
    String? sha256, String? perceptualHash,
  }) => OriginalImage(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        setId: setId ?? this.setId, sourceOrder: sourceOrder ?? this.sourceOrder,
        fileName: fileName ?? this.fileName, relativePath: relativePath ?? this.relativePath,
        extension: extension ?? this.extension, fileSize: fileSize ?? this.fileSize,
        width: identical(width, TypeUtil.unset) ? this.width : width as int?,
        height: identical(height, TypeUtil.unset) ? this.height : height as int?,
        sha256: sha256 ?? this.sha256, perceptualHash: perceptualHash ?? this.perceptualHash,
      );
  @override
  bool operator ==(Object other) => other is OriginalImage && TypeUtil.equal(toMap(includeId: true), other.toMap(includeId: true));
  @override
  int get hashCode => TypeUtil.hash(toMap(includeId: true));
  @override
  String toString() => 'OriginalImage(${toMap(includeId: true)})';
}

class OriginalPageMapping {
  final int? id;
  final int setId;
  final int displayOrder;
  final int? downloadedPart;
  final int? originalImageId;
  final OriginalRelationType relationType;
  final bool manuallyAdjusted;

  const OriginalPageMapping({
    this.id,
    this.setId = 0,
    this.displayOrder = 0,
    this.downloadedPart,
    this.originalImageId,
    this.relationType = OriginalRelationType.originalOnly,
    this.manuallyAdjusted = false,
  });
  factory OriginalPageMapping.fromMap(Map<String, Object?> map) => OriginalPageMapping(
        id: TypeUtil.parseNullableInt(map['id']), setId: TypeUtil.parseInt(map['set_id']),
        displayOrder: TypeUtil.parseInt(map['display_order']),
        downloadedPart: TypeUtil.parseNullableInt(map['downloaded_part']),
        originalImageId: TypeUtil.parseNullableInt(map['original_image_id']),
        relationType: OriginalRelationType.fromValue(TypeUtil.parseString(map['relation_type'])),
        manuallyAdjusted: TypeUtil.parseBool(map['manually_adjusted']),
      );
  factory OriginalPageMapping.fromJson(Map<String, dynamic> json) => OriginalPageMapping.fromMap(json);
  Map<String, Object?> toMap({bool includeId = false}) => {
        if (includeId && id != null) 'id': id,
        'set_id': setId, 'display_order': displayOrder, 'downloaded_part': downloadedPart,
        'original_image_id': originalImageId, 'relation_type': relationType.value,
        'manually_adjusted': manuallyAdjusted ? 1 : 0,
      };
  Map<String, Object?> toJson({bool includeId = false}) => toMap(includeId: includeId);
  bool get isEmpty => (id == null || id == 0) && setId == 0 && displayOrder == 0 &&
      downloadedPart == null && originalImageId == null &&
      relationType == OriginalRelationType.originalOnly && !manuallyAdjusted;
  OriginalPageMapping copyWith({
    Object? id = TypeUtil.unset, int? setId, int? displayOrder,
    Object? downloadedPart = TypeUtil.unset, Object? originalImageId = TypeUtil.unset,
    OriginalRelationType? relationType, bool? manuallyAdjusted,
  }) => OriginalPageMapping(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        setId: setId ?? this.setId, displayOrder: displayOrder ?? this.displayOrder,
        downloadedPart: identical(downloadedPart, TypeUtil.unset) ? this.downloadedPart : downloadedPart as int?,
        originalImageId: identical(originalImageId, TypeUtil.unset) ? this.originalImageId : originalImageId as int?,
        relationType: relationType ?? this.relationType,
        manuallyAdjusted: manuallyAdjusted ?? this.manuallyAdjusted,
      );
  @override
  bool operator ==(Object other) => other is OriginalPageMapping && TypeUtil.equal(toMap(includeId: true), other.toMap(includeId: true));
  @override
  int get hashCode => TypeUtil.hash(toMap(includeId: true));
  @override
  String toString() => 'OriginalPageMapping(${toMap(includeId: true)})';
}

class OriginalSetBundle {
  final OriginalImageSet set;
  final List<OriginalImage> images;
  final List<OriginalPageMapping> mappings;
  const OriginalSetBundle({this.set = const OriginalImageSet(), this.images = const [], this.mappings = const []});

  factory OriginalSetBundle.fromMap(Map<String, dynamic> map) => OriginalSetBundle(
        set: OriginalImageSet.fromMap(TypeUtil.parseMap(map['set'])),
        images: [
          ...TypeUtil.parseList(
            map['images'],
            (value) => OriginalImage.fromMap(TypeUtil.parseMap(value)),
          ),
        ],
        mappings: [
          ...TypeUtil.parseList(
            map['mappings'],
            (value) => OriginalPageMapping.fromMap(TypeUtil.parseMap(value)),
          ),
        ],
      );

  factory OriginalSetBundle.fromJson(Map<String, dynamic> json) =>
      OriginalSetBundle.fromMap(json);

  Map<String, dynamic> toMap() => {
        'set': set.toMap(includeId: true),
        'images': images.map((image) => image.toMap(includeId: true)).toList(),
        'mappings': mappings
            .map((mapping) => mapping.toMap(includeId: true))
            .toList(),
      };

  Map<String, dynamic> toJson() => toMap();

  bool get isEmpty => set.isEmpty && images.isEmpty && mappings.isEmpty;
  OriginalSetBundle copyWith({OriginalImageSet? set, List<OriginalImage>? images, List<OriginalPageMapping>? mappings}) => OriginalSetBundle(
        set: set ?? this.set, images: images == null ? [...this.images] : [...images], mappings: mappings == null ? [...this.mappings] : [...mappings]);
  @override
  bool operator ==(Object other) => other is OriginalSetBundle && TypeUtil.equal([set, images, mappings], [other.set, other.images, other.mappings]);
  @override
  int get hashCode => TypeUtil.hash([set, images, mappings]);
  @override
  String toString() => 'OriginalSetBundle(set: $set, images: $images, mappings: $mappings)';
}

class DisplayManifestPage {
  final int displayOrder;
  final int? downloadedPart;
  final OriginalImage? originalImage;
  final LocalImageInfo? downloadedImage;
  final LocalImageInfo? originalImageInfo;
  final OriginalRelationType relationType;
  const DisplayManifestPage({
    this.displayOrder = 0, this.downloadedPart, this.originalImage,
    this.downloadedImage, this.originalImageInfo,
    this.relationType = OriginalRelationType.originalOnly,
  });

  factory DisplayManifestPage.fromMap(Map<String, dynamic> map) =>
      DisplayManifestPage(
        displayOrder: TypeUtil.parseInt(map['display_order']),
        downloadedPart: TypeUtil.parseNullableInt(map['downloaded_part']),
        originalImage: map['original_image'] == null
            ? null
            : OriginalImage.fromMap(TypeUtil.parseMap(map['original_image'])),
        downloadedImage: map['downloaded_image'] == null
            ? null
            : LocalImageInfo.fromMap(
                TypeUtil.parseMap(map['downloaded_image']),
              ),
        originalImageInfo: map['original_image_info'] == null
            ? null
            : LocalImageInfo.fromMap(
                TypeUtil.parseMap(map['original_image_info']),
              ),
        relationType: OriginalRelationType.fromValue(
          TypeUtil.parseString(map['relation_type']),
        ),
      );

  factory DisplayManifestPage.fromJson(Map<String, dynamic> json) =>
      DisplayManifestPage.fromMap(json);

  Map<String, dynamic> toMap() => {
        'display_order': displayOrder,
        'downloaded_part': downloadedPart,
        'original_image': originalImage?.toMap(includeId: true),
        'downloaded_image': downloadedImage?.toMap(),
        'original_image_info': originalImageInfo?.toMap(),
        'relation_type': relationType.value,
      };

  Map<String, dynamic> toJson() => toMap();

  LocalImageInfo? resolve(OriginalDisplayMode mode) => switch (mode) {
    OriginalDisplayMode.originalPreferred => originalImageInfo ?? downloadedImage,
    OriginalDisplayMode.downloaded => downloadedImage,
  };
  bool get isEmpty => displayOrder == 0 && downloadedPart == null &&
      (originalImage == null || originalImage!.isEmpty) &&
      (downloadedImage == null || downloadedImage!.isEmpty) &&
      (originalImageInfo == null || originalImageInfo!.isEmpty) &&
      relationType == OriginalRelationType.originalOnly;
  DisplayManifestPage copyWith({
    int? displayOrder, Object? downloadedPart = TypeUtil.unset,
    Object? originalImage = TypeUtil.unset, Object? downloadedImage = TypeUtil.unset,
    Object? originalImageInfo = TypeUtil.unset, OriginalRelationType? relationType,
  }) => DisplayManifestPage(
        displayOrder: displayOrder ?? this.displayOrder,
        downloadedPart: identical(downloadedPart, TypeUtil.unset) ? this.downloadedPart : downloadedPart as int?,
        originalImage: identical(originalImage, TypeUtil.unset) ? this.originalImage : originalImage as OriginalImage?,
        downloadedImage: identical(downloadedImage, TypeUtil.unset) ? this.downloadedImage : downloadedImage as LocalImageInfo?,
        originalImageInfo: identical(originalImageInfo, TypeUtil.unset) ? this.originalImageInfo : originalImageInfo as LocalImageInfo?,
        relationType: relationType ?? this.relationType,
      );
  @override
  bool operator ==(Object other) => other is DisplayManifestPage && TypeUtil.equal([
    displayOrder, downloadedPart, originalImage, downloadedImage, originalImageInfo, relationType
  ], [other.displayOrder, other.downloadedPart, other.originalImage, other.downloadedImage, other.originalImageInfo, other.relationType]);
  @override
  int get hashCode => TypeUtil.hash([displayOrder, downloadedPart, originalImage, downloadedImage, originalImageInfo, relationType]);
  @override
  String toString() => 'DisplayManifestPage(${displayOrder}, ${relationType.value})';
}

class DisplayManifest {
  final int illustId;
  final OriginalImageSet? edition;
  final OriginalDisplayMode mode;
  final List<DisplayManifestPage> pages;
  const DisplayManifest({this.illustId = 0, this.edition, this.mode = OriginalDisplayMode.downloaded, this.pages = const []});

  factory DisplayManifest.fromMap(Map<String, dynamic> map) {
    final rawMode = TypeUtil.parseString(map['mode']);
    final mode = OriginalDisplayMode.values.firstWhere(
      (value) => value.name == rawMode,
      orElse: () => OriginalDisplayMode.downloaded,
    );
    return DisplayManifest(
      illustId: TypeUtil.parseInt(map['illust_id']),
      edition: map['edition'] == null
          ? null
          : OriginalImageSet.fromMap(TypeUtil.parseMap(map['edition'])),
      mode: mode,
      pages: [
        ...TypeUtil.parseList(
          map['pages'],
          (value) => DisplayManifestPage.fromMap(TypeUtil.parseMap(value)),
        ),
      ],
    );
  }

  factory DisplayManifest.fromJson(Map<String, dynamic> json) =>
      DisplayManifest.fromMap(json);

  int get pageCount => pages.length;
  bool get hasOriginal => edition != null;
  bool get isEmpty => illustId == 0 && (edition == null || edition!.isEmpty) &&
      pages.isEmpty;
  DisplayManifest copyWith({int? illustId, Object? edition = TypeUtil.unset, OriginalDisplayMode? mode, List<DisplayManifestPage>? pages}) => DisplayManifest(
        illustId: illustId ?? this.illustId,
        edition: identical(edition, TypeUtil.unset) ? this.edition : edition as OriginalImageSet?,
        mode: mode ?? this.mode, pages: pages == null ? [...this.pages] : [...pages]);
  @override
  bool operator ==(Object other) => other is DisplayManifest && TypeUtil.equal([illustId, edition, mode, pages], [other.illustId, other.edition, other.mode, other.pages]);
  @override
  int get hashCode => TypeUtil.hash([illustId, edition, mode, pages]);
  @override
  String toString() => 'DisplayManifest(${toMap()})';
  Map<String, dynamic> toMap() => {
        'illust_id': illustId, 'edition': edition?.toMap(), 'mode': mode.name,
        'pages': pages.map((e) => e.toMap()).toList(),
      };
  Map<String, dynamic> toJson() => toMap();
}
