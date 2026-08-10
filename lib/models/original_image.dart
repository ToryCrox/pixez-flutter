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
    required this.illustId,
    required this.editionName,
    required this.storageKey,
    required this.relativePath,
    this.lastSourcePath = '',
    this.sourceFolderName = '',
    this.directoryFingerprint = '',
    this.imageCount = 0,
    this.totalFileSize = 0,
    this.enhancedPageCount = 0,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OriginalImageSet.fromMap(Map<String, Object?> map) =>
      OriginalImageSet(
        id: TypeUtil.parseInt(map['id']),
        illustId: TypeUtil.parseInt(map['illust_id']),
        editionName: TypeUtil.parseString(map['edition_name']),
        storageKey: TypeUtil.parseString(map['storage_key']),
        relativePath: TypeUtil.parseString(map['relative_path']),
        lastSourcePath: TypeUtil.parseString(map['last_source_path']),
        sourceFolderName: TypeUtil.parseString(map['source_folder_name']),
        directoryFingerprint: TypeUtil.parseString(
          map['directory_fingerprint'],
        ),
        imageCount: TypeUtil.parseInt(map['image_count']),
        totalFileSize: TypeUtil.parseInt(map['total_file_size']),
        enhancedPageCount: TypeUtil.parseInt(map['enhanced_page_count']),
        isDefault: TypeUtil.parseInt(map['is_default']) == 1,
        createdAt: TypeUtil.parseInt(map['created_at']),
        updatedAt: TypeUtil.parseInt(map['updated_at']),
      );

  Map<String, Object?> toMap({bool includeId = false}) => {
    if (includeId && id != null) 'id': id,
    'illust_id': illustId,
    'edition_name': editionName,
    'storage_key': storageKey,
    'relative_path': relativePath,
    'last_source_path': lastSourcePath,
    'source_folder_name': sourceFolderName,
    'directory_fingerprint': directoryFingerprint,
    'image_count': imageCount,
    'total_file_size': totalFileSize,
    'enhanced_page_count': enhancedPageCount,
    'is_default': isDefault ? 1 : 0,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
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
    required this.setId,
    required this.sourceOrder,
    required this.fileName,
    required this.relativePath,
    required this.extension,
    required this.fileSize,
    this.width,
    this.height,
    required this.sha256,
    this.perceptualHash = '',
  });

  factory OriginalImage.fromMap(Map<String, Object?> map) => OriginalImage(
    id: TypeUtil.parseInt(map['id']),
    setId: TypeUtil.parseInt(map['set_id']),
    sourceOrder: TypeUtil.parseInt(map['source_order']),
    fileName: TypeUtil.parseString(map['file_name']),
    relativePath: TypeUtil.parseString(map['relative_path']),
    extension: TypeUtil.parseString(map['extension']),
    fileSize: TypeUtil.parseInt(map['file_size']),
    width: map['width'] == null ? null : TypeUtil.parseInt(map['width']),
    height: map['height'] == null ? null : TypeUtil.parseInt(map['height']),
    sha256: TypeUtil.parseString(map['sha256']),
    perceptualHash: TypeUtil.parseString(map['perceptual_hash']),
  );

  Map<String, Object?> toMap({bool includeId = false}) => {
    if (includeId && id != null) 'id': id,
    'set_id': setId,
    'source_order': sourceOrder,
    'file_name': fileName,
    'relative_path': relativePath,
    'extension': extension,
    'file_size': fileSize,
    'width': width,
    'height': height,
    'sha256': sha256,
    'perceptual_hash': perceptualHash,
  };
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
    required this.setId,
    required this.displayOrder,
    this.downloadedPart,
    this.originalImageId,
    required this.relationType,
    this.manuallyAdjusted = false,
  });

  factory OriginalPageMapping.fromMap(Map<String, Object?> map) =>
      OriginalPageMapping(
        id: TypeUtil.parseInt(map['id']),
        setId: TypeUtil.parseInt(map['set_id']),
        displayOrder: TypeUtil.parseInt(map['display_order']),
        downloadedPart:
            map['downloaded_part'] == null
                ? null
                : TypeUtil.parseInt(map['downloaded_part']),
        originalImageId:
            map['original_image_id'] == null
                ? null
                : TypeUtil.parseInt(map['original_image_id']),
        relationType: OriginalRelationType.fromValue(
          TypeUtil.parseString(map['relation_type']),
        ),
        manuallyAdjusted: TypeUtil.parseInt(map['manually_adjusted']) == 1,
      );

  Map<String, Object?> toMap({bool includeId = false}) => {
    if (includeId && id != null) 'id': id,
    'set_id': setId,
    'display_order': displayOrder,
    'downloaded_part': downloadedPart,
    'original_image_id': originalImageId,
    'relation_type': relationType.value,
    'manually_adjusted': manuallyAdjusted ? 1 : 0,
  };
}

class OriginalSetBundle {
  final OriginalImageSet set;
  final List<OriginalImage> images;
  final List<OriginalPageMapping> mappings;

  const OriginalSetBundle({
    required this.set,
    required this.images,
    required this.mappings,
  });
}

class DisplayManifestPage {
  final int displayOrder;
  final int? downloadedPart;
  final OriginalImage? originalImage;
  final LocalImageInfo? downloadedImage;
  final LocalImageInfo? originalImageInfo;
  final OriginalRelationType relationType;

  const DisplayManifestPage({
    required this.displayOrder,
    this.downloadedPart,
    this.originalImage,
    this.downloadedImage,
    this.originalImageInfo,
    required this.relationType,
  });

  LocalImageInfo? resolve(OriginalDisplayMode mode) => switch (mode) {
    OriginalDisplayMode.originalPreferred =>
      originalImageInfo ?? downloadedImage,
    OriginalDisplayMode.downloaded => downloadedImage,
  };
}

class DisplayManifest {
  final int illustId;
  final OriginalImageSet? edition;
  final OriginalDisplayMode mode;
  final List<DisplayManifestPage> pages;

  const DisplayManifest({
    required this.illustId,
    this.edition,
    required this.mode,
    required this.pages,
  });

  int get pageCount => pages.length;
  bool get hasOriginal => edition != null;
}
