import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path/path.dart' as p;
import 'package:pixez/custom/log.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/original_image.dart';
import 'package:pixez/models/original_image_repository.dart';
import 'package:pixez/utils/image_utils.dart';

const _supportedOriginalExtensions = {
  '.webp',
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.bmp',
  '.avif',
};

enum OriginalImportMode { author, single, update }

enum OriginalImportJobStatus { active, completed, cancelled, failed }

enum OriginalImportItemState {
  pending,
  copying,
  validated,
  finalizing,
  committed,
  failed,
}

enum OriginalImportFileState { pending, copied, validated }

class OriginalAuthorImportSelection {
  final String sourceDirectory;
  final int targetIllustId;
  final String editionName;

  const OriginalAuthorImportSelection({
    required this.sourceDirectory,
    required this.targetIllustId,
    this.editionName = '默认版',
  });
}

class OriginalImportProgress {
  final String jobId;
  final String itemId;
  final int copiedBytes;
  final int totalBytes;

  const OriginalImportProgress({
    required this.jobId,
    required this.itemId,
    required this.copiedBytes,
    required this.totalBytes,
  });

  double get fraction => totalBytes == 0 ? 0 : copiedBytes / totalBytes;
}

class OriginalImportFileManifest {
  final String sourceRelativePath;
  final String destinationName;
  final int sourceOrder;
  int fileSize;
  String sha256Value;
  String perceptualHash;
  int? width;
  int? height;
  OriginalImportFileState state;

  OriginalImportFileManifest({
    required this.sourceRelativePath,
    required this.destinationName,
    required this.sourceOrder,
    this.fileSize = 0,
    this.sha256Value = '',
    this.perceptualHash = '',
    this.width,
    this.height,
    this.state = OriginalImportFileState.pending,
  });

  factory OriginalImportFileManifest.fromJson(Map<String, dynamic> json) =>
      OriginalImportFileManifest(
        sourceRelativePath: json['source_relative_path'] as String? ?? '',
        destinationName: json['destination_name'] as String? ?? '',
        sourceOrder: json['source_order'] as int? ?? 0,
        fileSize: json['file_size'] as int? ?? 0,
        sha256Value: json['sha256'] as String? ?? '',
        perceptualHash: json['perceptual_hash'] as String? ?? '',
        width: json['width'] as int?,
        height: json['height'] as int?,
        state: OriginalImportFileState.values.byName(
          json['state'] as String? ?? OriginalImportFileState.pending.name,
        ),
      );

  Map<String, dynamic> toJson() => {
    'source_relative_path': sourceRelativePath,
    'destination_name': destinationName,
    'source_order': sourceOrder,
    'file_size': fileSize,
    'sha256': sha256Value,
    'perceptual_hash': perceptualHash,
    'width': width,
    'height': height,
    'state': state.name,
  };
}

class OriginalImportMappingManifest {
  int displayOrder;
  int? downloadedPart;
  int? originalSourceOrder;
  OriginalRelationType relationType;
  bool manuallyAdjusted;

  OriginalImportMappingManifest({
    required this.displayOrder,
    this.downloadedPart,
    this.originalSourceOrder,
    required this.relationType,
    this.manuallyAdjusted = false,
  });

  factory OriginalImportMappingManifest.fromJson(Map<String, dynamic> json) =>
      OriginalImportMappingManifest(
        displayOrder: json['display_order'] as int? ?? 0,
        downloadedPart: json['downloaded_part'] as int?,
        originalSourceOrder: json['original_source_order'] as int?,
        relationType: OriginalRelationType.fromValue(
          json['relation_type'] as String? ?? '',
        ),
        manuallyAdjusted: json['manually_adjusted'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'display_order': displayOrder,
    'downloaded_part': downloadedPart,
    'original_source_order': originalSourceOrder,
    'relation_type': relationType.value,
    'manually_adjusted': manuallyAdjusted,
  };
}

class OriginalImportItemManifest {
  final String itemId;
  OriginalImportItemState state;
  final String sourceDirectory;
  final int targetIllustId;
  final String targetSourceType;
  String editionName;
  final String storageKey;
  final String stagingRelativePath;
  final String finalRelativePath;
  final int? existingSetId;
  String directoryFingerprint;
  final List<OriginalImportFileManifest> files;
  List<OriginalImportMappingManifest> pageMappings;
  String? error;

  OriginalImportItemManifest({
    required this.itemId,
    this.state = OriginalImportItemState.pending,
    required this.sourceDirectory,
    required this.targetIllustId,
    required this.targetSourceType,
    required this.editionName,
    required this.storageKey,
    required this.stagingRelativePath,
    required this.finalRelativePath,
    this.existingSetId,
    this.directoryFingerprint = '',
    required this.files,
    this.pageMappings = const [],
    this.error,
  });

  factory OriginalImportItemManifest.fromJson(Map<String, dynamic> json) =>
      OriginalImportItemManifest(
        itemId: json['item_id'] as String? ?? '',
        state: OriginalImportItemState.values.byName(
          json['state'] as String? ?? OriginalImportItemState.pending.name,
        ),
        sourceDirectory: json['source_directory'] as String? ?? '',
        targetIllustId: json['target_illust_id'] as int? ?? 0,
        targetSourceType: json['target_source_type'] as String? ?? 'pixiv',
        editionName: json['edition_name'] as String? ?? '默认版',
        storageKey: json['storage_key'] as String? ?? '',
        stagingRelativePath: json['staging_relative_path'] as String? ?? '',
        finalRelativePath: json['final_relative_path'] as String? ?? '',
        existingSetId: json['existing_set_id'] as int?,
        directoryFingerprint: json['directory_fingerprint'] as String? ?? '',
        files:
            (json['files'] as List<dynamic>? ?? const [])
                .map(
                  (item) => OriginalImportFileManifest.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ),
                )
                .toList(),
        pageMappings:
            (json['page_mappings'] as List<dynamic>? ?? const [])
                .map(
                  (item) => OriginalImportMappingManifest.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ),
                )
                .toList(),
        error: json['error'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'state': state.name,
    'source_directory': sourceDirectory,
    'target_illust_id': targetIllustId,
    'target_source_type': targetSourceType,
    'edition_name': editionName,
    'storage_key': storageKey,
    'staging_relative_path': stagingRelativePath,
    'final_relative_path': finalRelativePath,
    'existing_set_id': existingSetId,
    'directory_fingerprint': directoryFingerprint,
    'files': files.map((item) => item.toJson()).toList(),
    'page_mappings': pageMappings.map((item) => item.toJson()).toList(),
    'error': error,
  };
}

class OriginalImportManifest {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String jobId;
  final OriginalImportMode mode;
  OriginalImportJobStatus status;
  final String sourceRoot;
  final int createdAt;
  int updatedAt;
  final List<OriginalImportItemManifest> items;

  OriginalImportManifest({
    this.schemaVersion = currentSchemaVersion,
    required this.jobId,
    required this.mode,
    this.status = OriginalImportJobStatus.active,
    required this.sourceRoot,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
  });

  factory OriginalImportManifest.fromJson(Map<String, dynamic> json) =>
      OriginalImportManifest(
        schemaVersion: json['schema_version'] as int? ?? 0,
        jobId: json['job_id'] as String? ?? '',
        mode: OriginalImportMode.values.byName(
          json['mode'] as String? ?? OriginalImportMode.single.name,
        ),
        status: OriginalImportJobStatus.values.byName(
          json['status'] as String? ?? OriginalImportJobStatus.active.name,
        ),
        sourceRoot: json['source_root'] as String? ?? '',
        createdAt: json['created_at'] as int? ?? 0,
        updatedAt: json['updated_at'] as int? ?? 0,
        items:
            (json['items'] as List<dynamic>? ?? const [])
                .map(
                  (item) => OriginalImportItemManifest.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ),
                )
                .toList(),
      );

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'job_id': jobId,
    'mode': mode.name,
    'status': status.name,
    'source_root': sourceRoot,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'items': items.map((item) => item.toJson()).toList(),
  };
}

class OriginalImportService {
  final DownloadDatabaseProvider provider;
  final OriginalImageRepository repository;
  final Random _random = Random.secure();

  OriginalImportService(this.provider)
    : repository = OriginalImageRepository(provider);

  String get _stagingRoot => p.join(provider.originalPath, '.staging');

  Future<OriginalImportManifest> prepareSingleImport({
    required String sourceDirectory,
    required int targetIllustId,
    String editionName = '默认版',
    OriginalImportMode mode = OriginalImportMode.single,
    void Function(OriginalImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('原图导入首版仅支持 Windows');
    }
    final target = await provider.getIllustByIllustId(targetIllustId);
    if (target == null) throw StateError('目标作品不存在: $targetIllustId');
    final source = Directory(sourceDirectory);
    if (!await source.exists()) throw StateError('原图目录不存在');

    final imageFiles = await _listImages(source);
    if (imageFiles.isEmpty) throw StateError('所选目录中没有支持的图片');
    final directSubdirectories =
        await source
            .list(followLinks: false)
            .where((entity) => entity is Directory)
            .cast<Directory>()
            .toList();
    if (directSubdirectories.isNotEmpty) {
      var imageSubdirectoryCount = 0;
      for (final directory in directSubdirectories) {
        if ((await _listImages(directory)).isNotEmpty) imageSubdirectoryCount++;
      }
      if (imageSubdirectoryCount > 1) {
        throw StateError('检测到多个作品子目录，请使用作者批量导入');
      }
    }

    final jobId = _newStorageKey();
    final itemId = _newStorageKey();
    final existingSets = await repository.getSetsForIllust(targetIllustId);
    OriginalImageSet? existingSet;
    if (mode == OriginalImportMode.update) {
      for (final set in existingSets) {
        if (set.editionName == editionName) {
          existingSet = set;
          break;
        }
      }
    }
    final storageKey = existingSet?.storageKey ?? _newStorageKey();
    final resolvedEditionName =
        existingSet?.editionName ??
        await _uniqueEditionName(targetIllustId, editionName);
    final safeTitle = _sanitizePathPart(target.title);
    final workKey =
        target.isLocal
            ? 'local_${target.illustId.abs()}'
            : target.illustId.toString();
    final authorDir =
        '[${_sanitizePathPart(target.userName)}][${target.userId}]';
    final workDir = '[$workKey]$safeTitle';
    final versionDir = '[$storageKey]${_sanitizePathPart(resolvedEditionName)}';
    final finalRelativePath =
        existingSet?.relativePath ?? p.join(authorDir, workDir, versionDir);
    final item = OriginalImportItemManifest(
      itemId: itemId,
      sourceDirectory: source.absolute.path,
      targetIllustId: targetIllustId,
      targetSourceType: target.sourceType,
      editionName: resolvedEditionName,
      storageKey: storageKey,
      stagingRelativePath: p.join('items', itemId, 'files'),
      finalRelativePath: finalRelativePath,
      existingSetId: existingSet?.id,
      files: [
        for (var i = 0; i < imageFiles.length; i++)
          OriginalImportFileManifest(
            sourceRelativePath: p.relative(
              imageFiles[i].path,
              from: source.absolute.path,
            ),
            destinationName:
                '${existingSet == null ? '' : 'update_${itemId}_'}${(i + 1).toString().padLeft(6, '0')}${p.extension(imageFiles[i].path).toLowerCase()}',
            sourceOrder: i,
          ),
      ],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final manifest = OriginalImportManifest(
      jobId: jobId,
      mode: mode,
      sourceRoot: source.absolute.path,
      createdAt: now,
      updatedAt: now,
      items: [item],
    );
    await Directory(p.join(_stagingRoot, jobId)).create(recursive: true);
    try {
      await _scanItem(
        manifest,
        item,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } catch (_) {
      final jobDirectory = Directory(p.join(_stagingRoot, jobId));
      if (await jobDirectory.exists()) {
        await jobDirectory.delete(recursive: true);
      }
      rethrow;
    }
    if (existingSets.any(
      (set) => set.directoryFingerprint == item.directoryFingerprint,
    )) {
      await cancel(manifest);
      throw StateError('该目录内容已经导入，无需重复导入');
    }
    await writeManifest(manifest);
    return manifest;
  }

  Future<OriginalImportManifest> prepareAuthorImport({
    required String sourceRoot,
    required List<OriginalAuthorImportSelection> selections,
    void Function(OriginalImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('原图导入首版仅支持 Windows');
    }
    if (selections.isEmpty) throw StateError('没有选中可导入的作品');
    final jobId = _newStorageKey();
    final now = DateTime.now().millisecondsSinceEpoch;
    final manifest = OriginalImportManifest(
      jobId: jobId,
      mode: OriginalImportMode.author,
      sourceRoot: Directory(sourceRoot).absolute.path,
      createdAt: now,
      updatedAt: now,
      items: [],
    );
    await Directory(p.join(_stagingRoot, jobId)).create(recursive: true);
    try {
      for (final selection in selections) {
        final target = await provider.getIllustByIllustId(
          selection.targetIllustId,
        );
        if (target == null) continue;
        final source = Directory(selection.sourceDirectory);
        final imageFiles = await _listImages(source);
        if (imageFiles.isEmpty) continue;
        final itemId = _newStorageKey();
        final storageKey = _newStorageKey();
        final editionName = await _uniqueEditionName(
          target.illustId,
          selection.editionName,
        );
        final workKey =
            target.isLocal
                ? 'local_${target.illustId.abs()}'
                : target.illustId.toString();
        final item = OriginalImportItemManifest(
          itemId: itemId,
          sourceDirectory: source.absolute.path,
          targetIllustId: target.illustId,
          targetSourceType: target.sourceType,
          editionName: editionName,
          storageKey: storageKey,
          stagingRelativePath: p.join('items', itemId, 'files'),
          finalRelativePath: p.join(
            '[${_sanitizePathPart(target.userName)}][${target.userId}]',
            '[$workKey]${_sanitizePathPart(target.title)}',
            '[$storageKey]${_sanitizePathPart(editionName)}',
          ),
          files: [
            for (var i = 0; i < imageFiles.length; i++)
              OriginalImportFileManifest(
                sourceRelativePath: p.relative(
                  imageFiles[i].path,
                  from: source.absolute.path,
                ),
                destinationName:
                    '${(i + 1).toString().padLeft(6, '0')}${p.extension(imageFiles[i].path).toLowerCase()}',
                sourceOrder: i,
              ),
          ],
        );
        await _scanItem(
          manifest,
          item,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
        final existingSets = await repository.getSetsForIllust(target.illustId);
        if (existingSets.any(
          (set) => set.directoryFingerprint == item.directoryFingerprint,
        )) {
          continue;
        }
        manifest.items.add(item);
        await writeManifest(manifest);
      }
      if (manifest.items.isEmpty) {
        await cancel(manifest);
        throw StateError('所选目录均已导入或没有可导入图片');
      }
      await writeManifest(manifest);
      return manifest;
    } catch (_) {
      final jobDirectory = Directory(p.join(_stagingRoot, jobId));
      if (await jobDirectory.exists()) {
        await jobDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<Map<int, List<OriginalMappingDraft>>> previewLocalLink({
    required int localIllustId,
    required int targetPixivIllustId,
  }) async {
    final local = await provider.getIllustByIllustId(localIllustId);
    final target = await provider.getIllustByIllustId(targetPixivIllustId);
    if (local?.isLocal != true) throw StateError('来源不是本地作品');
    if (target == null || target.isLocal) throw StateError('目标 Pixiv 作品不存在');
    final result = <int, List<OriginalMappingDraft>>{};
    final sets = await repository.getSetsForIllust(localIllustId);
    for (final set in sets) {
      final bundle = await repository.getBundle(set.id!);
      if (bundle == null) continue;
      final item = OriginalImportItemManifest(
        itemId: 'link_preview_${set.id}',
        sourceDirectory: '',
        targetIllustId: targetPixivIllustId,
        targetSourceType: DownloadedIllust.sourcePixiv,
        editionName: set.editionName,
        storageKey: set.storageKey,
        stagingRelativePath: '',
        finalRelativePath: set.relativePath,
        files: [
          for (final image in bundle.images)
            OriginalImportFileManifest(
              sourceRelativePath: image.relativePath,
              destinationName: image.fileName + image.extension,
              sourceOrder: image.sourceOrder,
              fileSize: image.fileSize,
              sha256Value: image.sha256,
              perceptualHash: image.perceptualHash,
              width: image.width,
              height: image.height,
              state: OriginalImportFileState.validated,
            ),
        ],
      );
      final mappings = await _alignPages(item);
      result[set.id!] = [
        for (final mapping in mappings)
          OriginalMappingDraft(
            displayOrder: mapping.displayOrder,
            downloadedPart: mapping.downloadedPart,
            originalSourceOrder: mapping.originalSourceOrder,
            relationType: mapping.relationType,
            manuallyAdjusted: mapping.manuallyAdjusted,
          ),
      ];
    }
    return result;
  }

  Future<List<FileSystemEntity>> discoverAuthorWorkDirectories(
    String authorRoot,
  ) async {
    final root = Directory(authorRoot);
    if (!await root.exists()) return [];
    final result = <FileSystemEntity>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! Directory) continue;
      final images = await _listImages(entity, recursive: false);
      if (images.isNotEmpty) result.add(entity);
    }
    result.sort((a, b) => _naturalCompare(a.path, b.path));
    return result;
  }

  Future<void> _scanItem(
    OriginalImportManifest manifest,
    OriginalImportItemManifest item, {
    void Function(OriginalImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final fingerprintParts = <String>[];
    for (final file in item.files) {
      file.fileSize =
          await File(
            p.join(item.sourceDirectory, file.sourceRelativePath),
          ).length();
    }
    final totalBytes = item.files.fold<int>(
      0,
      (sum, file) => sum + file.fileSize,
    );
    var scannedBytes = 0;
    for (final file in item.files) {
      if (isCancelled?.call() == true) throw StateError('用户已取消导入');
      final sourcePath = p.join(item.sourceDirectory, file.sourceRelativePath);
      final source = File(sourcePath);
      file.sha256Value = await _sha256File(source);
      file.perceptualHash = await _dHash(source);
      final size = await ImageUtils.parseImageSize(source.path);
      file.width = size?.width.toInt();
      file.height = size?.height.toInt();
      fingerprintParts.add(
        '${file.sourceOrder}|${file.fileSize}|${file.sha256Value}',
      );
      scannedBytes += file.fileSize;
      onProgress?.call(
        OriginalImportProgress(
          jobId: manifest.jobId,
          itemId: item.itemId,
          copiedBytes: scannedBytes,
          totalBytes: totalBytes,
        ),
      );
    }
    item.directoryFingerprint =
        sha256.convert(utf8.encode(fingerprintParts.join('\n'))).toString();
    item.pageMappings = await _alignPages(item);
    manifest.updatedAt = DateTime.now().millisecondsSinceEpoch;
  }

  Future<List<OriginalImportMappingManifest>> _alignPages(
    OriginalImportItemManifest item,
  ) async {
    final downloadedRecords = await provider.getImagesByIllustId(
      item.targetIllustId,
    );
    final downloadedHashes = <int, String>{};
    final downloadedSha256 = <int, String>{};
    for (final record in downloadedRecords.where((image) => image.part >= 0)) {
      final path = await provider.findImagePathForImage(
        record,
        isUgoira: false,
        update: false,
      );
      if (path != null) {
        downloadedHashes[record.part] = await _dHash(File(path));
        downloadedSha256[record.part] = await _sha256File(File(path));
      }
    }
    final parts = downloadedHashes.keys.toList()..sort();
    final sources = item.files;
    final n = sources.length;
    final m = parts.length;
    const gap = -12;
    final score = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    final action = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 1; i <= n; i++) {
      score[i][0] = i * gap;
      action[i][0] = 1;
    }
    for (var j = 1; j <= m; j++) {
      score[0][j] = j * gap;
      action[0][j] = 2;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final distance = _hamming(
          sources[i - 1].perceptualHash,
          downloadedHashes[parts[j - 1]] ?? '',
        );
        final exact =
            sources[i - 1].sha256Value == downloadedSha256[parts[j - 1]];
        final matchScore =
            exact ? 200 : (distance <= 10 ? 100 - distance * 5 : -50);
        final candidates = [
          score[i - 1][j - 1] + matchScore,
          score[i - 1][j] + gap,
          score[i][j - 1] + gap,
        ];
        var best = 0;
        for (var k = 1; k < candidates.length; k++) {
          if (candidates[k] > candidates[best]) best = k;
        }
        score[i][j] = candidates[best];
        action[i][j] = best;
      }
    }

    var i = n;
    var j = m;
    final reversed = <OriginalImportMappingManifest>[];
    while (i > 0 || j > 0) {
      final next = action[i][j];
      if (i > 0 && j > 0 && next == 0) {
        final distance = _hamming(
          sources[i - 1].perceptualHash,
          downloadedHashes[parts[j - 1]] ?? '',
        );
        final exact =
            sources[i - 1].sha256Value == downloadedSha256[parts[j - 1]];
        if (exact || distance <= 10) {
          reversed.add(
            OriginalImportMappingManifest(
              displayOrder: 0,
              downloadedPart: parts[j - 1],
              originalSourceOrder: sources[i - 1].sourceOrder,
              relationType: OriginalRelationType.replacement,
            ),
          );
          i--;
          j--;
        } else {
          reversed.add(
            OriginalImportMappingManifest(
              displayOrder: 0,
              originalSourceOrder: sources[i - 1].sourceOrder,
              relationType: OriginalRelationType.originalOnly,
            ),
          );
          i--;
        }
      } else if (i > 0 && (j == 0 || next == 1)) {
        reversed.add(
          OriginalImportMappingManifest(
            displayOrder: 0,
            originalSourceOrder: sources[i - 1].sourceOrder,
            relationType: OriginalRelationType.originalOnly,
          ),
        );
        i--;
      } else {
        reversed.add(
          OriginalImportMappingManifest(
            displayOrder: 0,
            downloadedPart: parts[j - 1],
            relationType: OriginalRelationType.downloadFallback,
          ),
        );
        j--;
      }
    }
    final result = reversed.reversed.toList();
    for (var index = 0; index < result.length; index++) {
      result[index].displayOrder = index;
    }
    return result;
  }

  Future<void> execute(
    OriginalImportManifest manifest, {
    void Function(OriginalImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    Object? firstError;
    for (final item in manifest.items) {
      if (item.state == OriginalImportItemState.committed) continue;
      try {
        await _copyAndValidate(
          manifest,
          item,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
        await _finalizeItem(manifest, item);
      } catch (e, stackTrace) {
        item.state = OriginalImportItemState.failed;
        item.error = e.toString();
        manifest.status = OriginalImportJobStatus.failed;
        await writeManifest(manifest);
        Log.e('原图导入失败', error: e, stackTrace: stackTrace);
        firstError ??= e;
        if (isCancelled?.call() == true) break;
      }
    }
    if (firstError != null) {
      manifest.status = OriginalImportJobStatus.failed;
      await writeManifest(manifest);
      throw StateError('部分作品导入失败，可从中断任务管理中重试：$firstError');
    }
    manifest.status = OriginalImportJobStatus.completed;
    manifest.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await writeManifest(manifest);
    await _cleanupCompletedJob(manifest);
  }

  Future<void> executeItem(
    OriginalImportManifest manifest,
    String itemId, {
    void Function(OriginalImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final item = manifest.items.firstWhere((entry) => entry.itemId == itemId);
    if (item.state == OriginalImportItemState.committed) return;
    try {
      await _copyAndValidate(
        manifest,
        item,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      await _finalizeItem(manifest, item);
    } catch (e, stackTrace) {
      item.state = OriginalImportItemState.failed;
      item.error = e.toString();
      manifest.status = OriginalImportJobStatus.failed;
      await writeManifest(manifest);
      Log.e('单项原图导入失败', error: e, stackTrace: stackTrace);
      rethrow;
    }
    if (manifest.items.every(
      (entry) => entry.state == OriginalImportItemState.committed,
    )) {
      manifest.status = OriginalImportJobStatus.completed;
      await writeManifest(manifest);
      await _cleanupCompletedJob(manifest);
    } else {
      manifest.status = OriginalImportJobStatus.active;
      await writeManifest(manifest);
    }
  }

  Future<void> _copyAndValidate(
    OriginalImportManifest manifest,
    OriginalImportItemManifest item, {
    void Function(OriginalImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    item.state = OriginalImportItemState.copying;
    await writeManifest(manifest);
    final stagingDirectory = Directory(
      p.join(_stagingRoot, manifest.jobId, item.stagingRelativePath),
    );
    await stagingDirectory.create(recursive: true);
    var sinceWrite = 0;
    final totalBytes = item.files.fold<int>(
      0,
      (sum, file) => sum + file.fileSize,
    );
    var copiedBytes = 0;
    for (final file in item.files) {
      if (isCancelled?.call() == true) throw StateError('用户已取消导入');
      final target = File(p.join(stagingDirectory.path, file.destinationName));
      if (file.state != OriginalImportFileState.pending &&
          await target.exists()) {
        final hash = await _sha256File(target);
        if (hash == file.sha256Value) {
          copiedBytes += file.fileSize;
          onProgress?.call(
            OriginalImportProgress(
              jobId: manifest.jobId,
              itemId: item.itemId,
              copiedBytes: copiedBytes,
              totalBytes: totalBytes,
            ),
          );
          continue;
        }
      }
      final source = File(
        p.join(item.sourceDirectory, file.sourceRelativePath),
      );
      await source.copy(target.path);
      file.state = OriginalImportFileState.copied;
      copiedBytes += file.fileSize;
      onProgress?.call(
        OriginalImportProgress(
          jobId: manifest.jobId,
          itemId: item.itemId,
          copiedBytes: copiedBytes,
          totalBytes: totalBytes,
        ),
      );
      sinceWrite++;
      if (sinceWrite >= 10) {
        await writeManifest(manifest);
        sinceWrite = 0;
      }
    }
    for (final file in item.files) {
      if (isCancelled?.call() == true) throw StateError('用户已取消导入');
      final target = File(p.join(stagingDirectory.path, file.destinationName));
      if (!await target.exists() || await target.length() != file.fileSize) {
        throw StateError('复制校验失败: ${file.destinationName}');
      }
      if (await _sha256File(target) != file.sha256Value) {
        throw StateError('文件哈希不一致: ${file.destinationName}');
      }
      file.state = OriginalImportFileState.validated;
    }
    item.state = OriginalImportItemState.validated;
    await writeManifest(manifest);
  }

  Future<void> _finalizeItem(
    OriginalImportManifest manifest,
    OriginalImportItemManifest item,
  ) async {
    if (item.existingSetId != null) {
      await _finalizeUpdateItem(manifest, item);
      return;
    }
    final stagingDirectory = Directory(
      p.join(_stagingRoot, manifest.jobId, item.stagingRelativePath),
    );
    final finalDirectory = Directory(
      p.join(provider.originalPath, item.finalRelativePath),
    );
    item.state = OriginalImportItemState.finalizing;
    await writeManifest(manifest);
    await finalDirectory.parent.create(recursive: true);
    if (await finalDirectory.exists()) {
      throw StateError('原图目标目录已存在: ${finalDirectory.path}');
    }
    await stagingDirectory.rename(finalDirectory.path);
    try {
      final existingSets = await repository.getSetsForIllust(
        item.targetIllustId,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final relativeFiles = <OriginalImageDraft>[];
      for (final file in item.files) {
        relativeFiles.add(
          OriginalImageDraft(
            sourceOrder: file.sourceOrder,
            fileName: p.basenameWithoutExtension(file.destinationName),
            relativePath: p.join(item.finalRelativePath, file.destinationName),
            extension: p.extension(file.destinationName),
            fileSize: file.fileSize,
            width: file.width,
            height: file.height,
            sha256: file.sha256Value,
            perceptualHash: file.perceptualHash,
          ),
        );
      }
      await repository.insertSetWithContent(
        set: OriginalImageSet(
          illustId: item.targetIllustId,
          editionName: item.editionName,
          storageKey: item.storageKey,
          relativePath: item.finalRelativePath,
          lastSourcePath: item.sourceDirectory,
          sourceFolderName: p.basename(item.sourceDirectory),
          directoryFingerprint: item.directoryFingerprint,
          imageCount: item.files.length,
          totalFileSize: item.files.fold(0, (sum, file) => sum + file.fileSize),
          enhancedPageCount: item.pageMappings.length,
          isDefault: existingSets.isEmpty,
          createdAt: now,
          updatedAt: now,
        ),
        images: relativeFiles,
        mappings: [
          for (final mapping in item.pageMappings)
            OriginalMappingDraft(
              displayOrder: mapping.displayOrder,
              downloadedPart: mapping.downloadedPart,
              originalSourceOrder: mapping.originalSourceOrder,
              relationType: mapping.relationType,
              manuallyAdjusted: mapping.manuallyAdjusted,
            ),
        ],
      );
    } catch (_) {
      await finalDirectory.rename(stagingDirectory.path);
      item.state = OriginalImportItemState.validated;
      await writeManifest(manifest);
      rethrow;
    }
    item.state = OriginalImportItemState.committed;
    item.error = null;
    await writeManifest(manifest);
  }

  Future<void> _finalizeUpdateItem(
    OriginalImportManifest manifest,
    OriginalImportItemManifest item,
  ) async {
    final setId = item.existingSetId!;
    final bundle = await repository.getBundle(setId);
    if (bundle == null) throw StateError('需要更新的原图版本不存在');
    final stagingDirectory = Directory(
      p.join(_stagingRoot, manifest.jobId, item.stagingRelativePath),
    );
    final finalDirectory = Directory(
      p.join(provider.originalPath, item.finalRelativePath),
    );
    item.state = OriginalImportItemState.finalizing;
    await writeManifest(manifest);
    await finalDirectory.create(recursive: true);

    final remainingByHash = <String, List<OriginalImage>>{};
    for (final image in bundle.images) {
      remainingByHash.putIfAbsent(image.sha256, () => []).add(image);
    }
    final drafts = <OriginalImageDraft>[];
    final oldIdToNewOrder = <int, int>{};
    final newSourceOrders = <int>{};
    final createdFiles = <File>[];
    for (final file in item.files) {
      final matches = remainingByHash[file.sha256Value];
      final existing =
          matches == null || matches.isEmpty ? null : matches.removeAt(0);
      final sourceOrder = drafts.length;
      if (existing != null) {
        oldIdToNewOrder[existing.id!] = sourceOrder;
        drafts.add(
          OriginalImageDraft(
            sourceOrder: sourceOrder,
            fileName: existing.fileName,
            relativePath: existing.relativePath,
            extension: existing.extension,
            fileSize: existing.fileSize,
            width: existing.width,
            height: existing.height,
            sha256: existing.sha256,
            perceptualHash: existing.perceptualHash,
          ),
        );
      } else {
        final target = File(p.join(finalDirectory.path, file.destinationName));
        final existedBefore = await target.exists();
        if (!existedBefore) {
          await File(
            p.join(stagingDirectory.path, file.destinationName),
          ).copy(target.path);
          createdFiles.add(target);
        } else if (await _sha256File(target) != file.sha256Value) {
          throw StateError('增量更新目标文件冲突: ${target.path}');
        }
        drafts.add(
          OriginalImageDraft(
            sourceOrder: sourceOrder,
            fileName: p.basenameWithoutExtension(file.destinationName),
            relativePath: p.join(item.finalRelativePath, file.destinationName),
            extension: p.extension(file.destinationName),
            fileSize: file.fileSize,
            width: file.width,
            height: file.height,
            sha256: file.sha256Value,
            perceptualHash: file.perceptualHash,
          ),
        );
        newSourceOrders.add(sourceOrder);
      }
    }
    final retainedOldOrders = <int>[];
    for (final images in remainingByHash.values) {
      for (final image in images) {
        final sourceOrder = drafts.length;
        oldIdToNewOrder[image.id!] = sourceOrder;
        retainedOldOrders.add(sourceOrder);
        drafts.add(
          OriginalImageDraft(
            sourceOrder: sourceOrder,
            fileName: image.fileName,
            relativePath: image.relativePath,
            extension: image.extension,
            fileSize: image.fileSize,
            width: image.width,
            height: image.height,
            sha256: image.sha256,
            perceptualHash: image.perceptualHash,
          ),
        );
      }
    }

    final mappings = <OriginalMappingDraft>[];
    if (bundle.mappings.any((mapping) => mapping.manuallyAdjusted)) {
      for (final mapping in bundle.mappings) {
        final newOrder = oldIdToNewOrder[mapping.originalImageId];
        if (newOrder == null && mapping.downloadedPart == null) continue;
        mappings.add(
          OriginalMappingDraft(
            displayOrder: mappings.length,
            downloadedPart: mapping.downloadedPart,
            originalSourceOrder: newOrder,
            relationType: mapping.relationType,
            manuallyAdjusted: mapping.manuallyAdjusted,
          ),
        );
      }
      final represented =
          mappings
              .map((mapping) => mapping.originalSourceOrder)
              .whereType<int>()
              .toSet();
      for (final sourceOrder in newSourceOrders.where(
        (order) => !represented.contains(order),
      )) {
        mappings.add(
          OriginalMappingDraft(
            displayOrder: mappings.length,
            originalSourceOrder: sourceOrder,
            relationType: OriginalRelationType.originalOnly,
          ),
        );
      }
    } else {
      mappings.addAll([
        for (final mapping in item.pageMappings)
          OriginalMappingDraft(
            displayOrder: mapping.displayOrder,
            downloadedPart: mapping.downloadedPart,
            originalSourceOrder: mapping.originalSourceOrder,
            relationType: mapping.relationType,
            manuallyAdjusted: mapping.manuallyAdjusted,
          ),
      ]);
      for (final sourceOrder in retainedOldOrders) {
        mappings.add(
          OriginalMappingDraft(
            displayOrder: mappings.length,
            originalSourceOrder: sourceOrder,
            relationType: OriginalRelationType.originalOnly,
          ),
        );
      }
    }

    try {
      await repository.updateSetWithContent(
        setId: setId,
        lastSourcePath: item.sourceDirectory,
        sourceFolderName: p.basename(item.sourceDirectory),
        directoryFingerprint: item.directoryFingerprint,
        images: drafts,
        mappings: mappings,
      );
    } catch (_) {
      for (final file in createdFiles) {
        if (await file.exists()) await file.delete();
      }
      item.state = OriginalImportItemState.validated;
      await writeManifest(manifest);
      rethrow;
    }
    item.state = OriginalImportItemState.committed;
    item.error = null;
    await writeManifest(manifest);
    if (await stagingDirectory.exists()) {
      await stagingDirectory.delete(recursive: true);
    }
  }

  Future<List<OriginalImportManifest>> findRecoverableJobs() async {
    final root = Directory(_stagingRoot);
    if (!await root.exists()) return [];
    final jobs = <OriginalImportManifest>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      await _recoverManifestSwap(entity);
      final file = File(p.join(entity.path, 'manifest.json'));
      if (!await file.exists()) continue;
      try {
        final manifest = await readManifest(file.path);
        await _reconcileFinalizingItems(manifest);
        if (manifest.status != OriginalImportJobStatus.completed &&
            manifest.status != OriginalImportJobStatus.cancelled) {
          jobs.add(manifest);
        }
      } catch (e, stackTrace) {
        Log.e('无法读取原图导入任务: ${file.path}', error: e, stackTrace: stackTrace);
      }
    }
    return jobs;
  }

  Future<List<String>> findBrokenJobDirectories() async {
    final root = Directory(_stagingRoot);
    if (!await root.exists()) return [];
    final broken = <String>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      await _recoverManifestSwap(entity);
      final file = File(p.join(entity.path, 'manifest.json'));
      if (!await file.exists()) {
        broken.add(entity.path);
        continue;
      }
      try {
        await readManifest(file.path);
      } catch (_) {
        broken.add(entity.path);
      }
    }
    return broken;
  }

  Future<void> _reconcileFinalizingItems(
    OriginalImportManifest manifest,
  ) async {
    var changed = false;
    for (final item in manifest.items) {
      if (item.state != OriginalImportItemState.finalizing) continue;
      if (item.existingSetId != null) {
        final set = await repository.getSet(item.existingSetId!);
        item.state =
            set?.directoryFingerprint == item.directoryFingerprint
                ? OriginalImportItemState.committed
                : OriginalImportItemState.validated;
        changed = true;
        continue;
      }
      if (await repository.hasStorageKey(item.storageKey)) {
        item.state = OriginalImportItemState.committed;
        changed = true;
        continue;
      }
      final finalDirectory = Directory(
        p.join(provider.originalPath, item.finalRelativePath),
      );
      final stagingDirectory = Directory(
        p.join(_stagingRoot, manifest.jobId, item.stagingRelativePath),
      );
      if (await finalDirectory.exists() && !await stagingDirectory.exists()) {
        await stagingDirectory.parent.create(recursive: true);
        await finalDirectory.rename(stagingDirectory.path);
        item.state = OriginalImportItemState.validated;
      } else if (!await finalDirectory.exists() &&
          !await stagingDirectory.exists()) {
        item.state = OriginalImportItemState.failed;
        item.error = '暂存目录和正式目录均不存在';
      }
      changed = true;
    }
    if (changed) await writeManifest(manifest);
  }

  Future<void> cancel(OriginalImportManifest manifest) async {
    manifest.status = OriginalImportJobStatus.cancelled;
    await writeManifest(manifest);
    final jobDirectory = Directory(p.join(_stagingRoot, manifest.jobId));
    if (await jobDirectory.exists()) await jobDirectory.delete(recursive: true);
  }

  Future<void> _cleanupCompletedJob(OriginalImportManifest manifest) async {
    final directory = Directory(p.join(_stagingRoot, manifest.jobId));
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<OriginalImportManifest> readManifest(String manifestPath) async {
    final json = jsonDecode(await File(manifestPath).readAsString());
    final manifest = OriginalImportManifest.fromJson(
      Map<String, dynamic>.from(json as Map),
    );
    if (manifest.schemaVersion != OriginalImportManifest.currentSchemaVersion) {
      throw FormatException('不支持的 Manifest 版本: ${manifest.schemaVersion}');
    }
    return manifest;
  }

  Future<void> writeManifest(OriginalImportManifest manifest) async {
    manifest.updatedAt = DateTime.now().millisecondsSinceEpoch;
    final directory = Directory(p.join(_stagingRoot, manifest.jobId));
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, 'manifest.json'));
    final temporary = File('${target.path}.tmp');
    final previous = File('${target.path}.previous');
    final sink = temporary.openWrite(mode: FileMode.writeOnly);
    sink.write(const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
    await sink.flush();
    await sink.close();
    if (await previous.exists()) await previous.delete();
    if (await target.exists()) await target.rename(previous.path);
    try {
      await temporary.rename(target.path);
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      if (!await target.exists() && await previous.exists()) {
        await previous.rename(target.path);
      }
      rethrow;
    }
  }

  Future<void> _recoverManifestSwap(Directory directory) async {
    final target = File(p.join(directory.path, 'manifest.json'));
    if (await target.exists()) return;
    final temporary = File('${target.path}.tmp');
    final previous = File('${target.path}.previous');
    if (await temporary.exists()) {
      await temporary.rename(target.path);
      if (await previous.exists()) await previous.delete();
    } else if (await previous.exists()) {
      await previous.rename(target.path);
    }
  }

  Future<List<File>> _listImages(
    Directory directory, {
    bool recursive = false,
  }) async {
    final files = <File>[];
    await for (final entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entity is File &&
          _supportedOriginalExtensions.contains(
            p.extension(entity.path).toLowerCase(),
          )) {
        files.add(entity);
      }
    }
    files.sort((a, b) => _naturalCompare(a.path, b.path));
    return files;
  }

  Future<String> _uniqueEditionName(int illustId, String requested) async {
    final sets = await repository.getSetsForIllust(illustId);
    final used = sets.map((set) => set.editionName).toSet();
    if (!used.contains(requested)) return requested;
    var index = 2;
    while (used.contains('$requested ($index)')) {
      index++;
    }
    return '$requested ($index)';
  }

  String _newStorageKey() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  String _sanitizePathPart(String value) {
    final sanitized = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '');
    final trimmed = sanitized.trim().replaceAll(RegExp(r'[. ]+$'), '');
    return trimmed.isEmpty
        ? '未命名'
        : trimmed.substring(0, min(80, trimmed.length));
  }

  int _naturalCompare(String left, String right) {
    final pattern = RegExp(r'(\d+)|(\D+)');
    final leftParts =
        pattern.allMatches(left.toLowerCase()).map((m) => m[0]!).toList();
    final rightParts =
        pattern.allMatches(right.toLowerCase()).map((m) => m[0]!).toList();
    for (var i = 0; i < min(leftParts.length, rightParts.length); i++) {
      final leftNumber = int.tryParse(leftParts[i]);
      final rightNumber = int.tryParse(rightParts[i]);
      final compare =
          leftNumber != null && rightNumber != null
              ? leftNumber.compareTo(rightNumber)
              : leftParts[i].compareTo(rightParts[i]);
      if (compare != 0) return compare;
    }
    return leftParts.length.compareTo(rightParts.length);
  }

  Future<String> _sha256File(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<String> _dHash(File file) async {
    final bytes = await file.readAsBytes();
    final decoded = image_lib.decodeImage(bytes);
    if (decoded == null) return '';
    final resized = image_lib.copyResize(decoded, width: 9, height: 8);
    var hash = BigInt.zero;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final left = resized.getPixel(x, y).luminanceNormalized;
        final right = resized.getPixel(x + 1, y).luminanceNormalized;
        hash = (hash << 1) | (left > right ? BigInt.one : BigInt.zero);
      }
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  int _hamming(String left, String right) {
    if (left.isEmpty || right.isEmpty) return 64;
    var value = BigInt.parse(left, radix: 16) ^ BigInt.parse(right, radix: 16);
    var count = 0;
    while (value > BigInt.zero) {
      count += (value & BigInt.one).toInt();
      value >>= 1;
    }
    return count;
  }
}
