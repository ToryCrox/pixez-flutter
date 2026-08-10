import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/original_image.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class OriginalImageDraft {
  final int sourceOrder;
  final String fileName;
  final String relativePath;
  final String extension;
  final int fileSize;
  final int? width;
  final int? height;
  final String sha256;
  final String perceptualHash;

  const OriginalImageDraft({
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
}

class OriginalMappingDraft {
  final int displayOrder;
  final int? downloadedPart;
  final int? originalSourceOrder;
  final OriginalRelationType relationType;
  final bool manuallyAdjusted;

  const OriginalMappingDraft({
    required this.displayOrder,
    this.downloadedPart,
    this.originalSourceOrder,
    required this.relationType,
    this.manuallyAdjusted = false,
  });
}

class OriginalImageRepository {
  final DownloadDatabaseProvider provider;

  const OriginalImageRepository(this.provider);

  Database get _db => provider.db;

  Future<List<OriginalImageSet>> getSetsForIllust(int illustId) async {
    final rows = await _db.query(
      'original_image_sets',
      where: 'illust_id = ?',
      whereArgs: [illustId],
      orderBy: 'is_default DESC, created_at ASC',
    );
    return rows.map(OriginalImageSet.fromMap).toList();
  }

  Future<OriginalImageSet?> getSet(int setId) async {
    final rows = await _db.query(
      'original_image_sets',
      where: 'id = ?',
      whereArgs: [setId],
      limit: 1,
    );
    return rows.isEmpty ? null : OriginalImageSet.fromMap(rows.first);
  }

  Future<OriginalImageSet?> getDefaultSet(int illustId) async {
    final rows = await _db.query(
      'original_image_sets',
      where: 'illust_id = ?',
      whereArgs: [illustId],
      orderBy: 'is_default DESC, created_at ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : OriginalImageSet.fromMap(rows.first);
  }

  Future<bool> hasOriginal(int illustId) async {
    final result = await _db.rawQuery(
      'SELECT 1 FROM original_image_sets WHERE illust_id = ? LIMIT 1',
      [illustId],
    );
    return result.isNotEmpty;
  }

  Future<bool> hasStorageKey(String storageKey) async {
    final result = await _db.rawQuery(
      'SELECT 1 FROM original_image_sets WHERE storage_key = ? LIMIT 1',
      [storageKey],
    );
    return result.isNotEmpty;
  }

  Future<Set<String>> getImportedSourcePathsForUser(int userId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT DISTINCT original_image_sets.last_source_path AS source_path
      FROM original_image_sets
      INNER JOIN ${DownloadedIllustColumns.tableName} AS downloaded_illusts
        ON downloaded_illusts.${DownloadedIllustColumns.illustId} =
           original_image_sets.illust_id
      WHERE downloaded_illusts.${DownloadedIllustColumns.userId} = ?
        AND original_image_sets.last_source_path != ''
      ''',
      [userId],
    );
    return rows.map((row) => row['source_path']).whereType<String>().toSet();
  }

  Future<OriginalSetBundle?> getBundle(int setId) async {
    final set = await getSet(setId);
    if (set == null) return null;
    final imageRows = await _db.query(
      'original_images',
      where: 'set_id = ?',
      whereArgs: [setId],
      orderBy: 'source_order ASC',
    );
    final mappingRows = await _db.query(
      'original_page_mappings',
      where: 'set_id = ?',
      whereArgs: [setId],
      orderBy: 'display_order ASC',
    );
    return OriginalSetBundle(
      set: set,
      images: imageRows.map(OriginalImage.fromMap).toList(),
      mappings: mappingRows.map(OriginalPageMapping.fromMap).toList(),
    );
  }

  Future<int> insertSetWithContent({
    required OriginalImageSet set,
    required List<OriginalImageDraft> images,
    required List<OriginalMappingDraft> mappings,
  }) async {
    return _db.transaction((txn) async {
      if (set.isDefault) {
        await txn.update(
          'original_image_sets',
          {'is_default': 0},
          where: 'illust_id = ?',
          whereArgs: [set.illustId],
        );
      }
      final setId = await txn.insert('original_image_sets', set.toMap());
      final imageIds = <int, int>{};
      for (final image in images) {
        final id = await txn.insert('original_images', {
          'set_id': setId,
          'source_order': image.sourceOrder,
          'file_name': image.fileName,
          'relative_path': image.relativePath,
          'extension': image.extension,
          'file_size': image.fileSize,
          'width': image.width,
          'height': image.height,
          'sha256': image.sha256,
          'perceptual_hash': image.perceptualHash,
        });
        imageIds[image.sourceOrder] = id;
      }
      for (final mapping in mappings) {
        await txn.insert('original_page_mappings', {
          'set_id': setId,
          'display_order': mapping.displayOrder,
          'downloaded_part': mapping.downloadedPart,
          'original_image_id':
              mapping.originalSourceOrder == null
                  ? null
                  : imageIds[mapping.originalSourceOrder],
          'relation_type': mapping.relationType.value,
          'manually_adjusted': mapping.manuallyAdjusted ? 1 : 0,
        });
      }
      return setId;
    });
  }

  Future<void> replaceMappings(
    int setId,
    List<OriginalMappingDraft> mappings,
  ) async {
    await _db.transaction((txn) async {
      final imageRows = await txn.query(
        'original_images',
        columns: ['id', 'source_order'],
        where: 'set_id = ?',
        whereArgs: [setId],
      );
      final ids = {
        for (final row in imageRows)
          row['source_order'] as int: row['id'] as int,
      };
      await txn.delete(
        'original_page_mappings',
        where: 'set_id = ?',
        whereArgs: [setId],
      );
      for (final mapping in mappings) {
        await txn.insert('original_page_mappings', {
          'set_id': setId,
          'display_order': mapping.displayOrder,
          'downloaded_part': mapping.downloadedPart,
          'original_image_id':
              mapping.originalSourceOrder == null
                  ? null
                  : ids[mapping.originalSourceOrder],
          'relation_type': mapping.relationType.value,
          'manually_adjusted': mapping.manuallyAdjusted ? 1 : 0,
        });
      }
      await txn.update(
        'original_image_sets',
        {
          'enhanced_page_count': mappings.length,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [setId],
      );
    });
  }

  Future<void> updateSetWithContent({
    required int setId,
    required String lastSourcePath,
    required String sourceFolderName,
    required String directoryFingerprint,
    required List<OriginalImageDraft> images,
    required List<OriginalMappingDraft> mappings,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'original_page_mappings',
        where: 'set_id = ?',
        whereArgs: [setId],
      );
      await txn.delete(
        'original_images',
        where: 'set_id = ?',
        whereArgs: [setId],
      );
      final imageIds = <int, int>{};
      for (final image in images) {
        final id = await txn.insert('original_images', {
          'set_id': setId,
          'source_order': image.sourceOrder,
          'file_name': image.fileName,
          'relative_path': image.relativePath,
          'extension': image.extension,
          'file_size': image.fileSize,
          'width': image.width,
          'height': image.height,
          'sha256': image.sha256,
          'perceptual_hash': image.perceptualHash,
        });
        imageIds[image.sourceOrder] = id;
      }
      for (final mapping in mappings) {
        await txn.insert('original_page_mappings', {
          'set_id': setId,
          'display_order': mapping.displayOrder,
          'downloaded_part': mapping.downloadedPart,
          'original_image_id':
              mapping.originalSourceOrder == null
                  ? null
                  : imageIds[mapping.originalSourceOrder],
          'relation_type': mapping.relationType.value,
          'manually_adjusted': mapping.manuallyAdjusted ? 1 : 0,
        });
      }
      await txn.update(
        'original_image_sets',
        {
          'last_source_path': lastSourcePath,
          'source_folder_name': sourceFolderName,
          'directory_fingerprint': directoryFingerprint,
          'image_count': images.length,
          'total_file_size': images.fold<int>(
            0,
            (sum, image) => sum + image.fileSize,
          ),
          'enhanced_page_count': mappings.length,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [setId],
      );
    });
  }

  Future<void> setDefault(int setId) async {
    final set = await getSet(setId);
    if (set == null) return;
    await _db.transaction((txn) async {
      await txn.update(
        'original_image_sets',
        {'is_default': 0},
        where: 'illust_id = ?',
        whereArgs: [set.illustId],
      );
      await txn.update(
        'original_image_sets',
        {'is_default': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [setId],
      );
    });
  }

  /// 重命名版本；若名称已被同一作品使用，会自动追加序号。
  Future<String> renameSet(int setId, String requestedName) async {
    final requested = requestedName.trim();
    if (requested.isEmpty) throw StateError('版本名称不能为空');
    return _db.transaction((txn) async {
      final rows = await txn.query(
        'original_image_sets',
        columns: ['illust_id'],
        where: 'id = ?',
        whereArgs: [setId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('原图版本不存在');
      final illustId = rows.first['illust_id'] as int;
      final nameRows = await txn.query(
        'original_image_sets',
        columns: ['edition_name'],
        where: 'illust_id = ? AND id != ?',
        whereArgs: [illustId, setId],
      );
      final used = nameRows.map((row) => row['edition_name'] as String).toSet();
      var resolved = requested;
      var suffix = 2;
      while (used.contains(resolved)) {
        resolved = '$requested ($suffix)';
        suffix++;
      }
      await txn.update(
        'original_image_sets',
        {
          'edition_name': resolved,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [setId],
      );
      return resolved;
    });
  }

  Future<void> deleteSetRecord(int setId) async {
    await _db.delete(
      'original_image_sets',
      where: 'id = ?',
      whereArgs: [setId],
    );
  }

  /// 先移入原图回收目录，再提交数据库删除；失败时恢复文件。
  Future<void> removeSetSafely(int setId) async {
    final set = await getSet(setId);
    if (set == null) return;
    final source = Directory(p.join(provider.originalPath, set.relativePath));
    final operationId =
        '${DateTime.now().millisecondsSinceEpoch}_${set.storageKey}';
    final trash = Directory(
      p.join(provider.originalPath, '.trash', operationId),
    );
    if (await source.exists()) {
      await trash.parent.create(recursive: true);
      await source.rename(trash.path);
    }
    try {
      await _db.transaction((txn) async {
        await txn.delete(
          'original_image_sets',
          where: 'id = ?',
          whereArgs: [setId],
        );
        final remainingRows = await txn.rawQuery(
          'SELECT COUNT(*) AS count FROM original_image_sets WHERE illust_id = ?',
          [set.illustId],
        );
        final remaining = remainingRows.first['count'] as int? ?? 0;
        if (remaining > 0 && set.isDefault) {
          final next = await txn.query(
            'original_image_sets',
            columns: ['id'],
            where: 'illust_id = ?',
            whereArgs: [set.illustId],
            orderBy: 'created_at ASC',
            limit: 1,
          );
          if (next.isNotEmpty) {
            await txn.update(
              'original_image_sets',
              {'is_default': 1},
              where: 'id = ?',
              whereArgs: [next.first['id']],
            );
          }
        }
        final illust = await txn.query(
          DownloadedIllustColumns.tableName,
          columns: [DownloadedIllustColumns.sourceType],
          where: '${DownloadedIllustColumns.illustId} = ?',
          whereArgs: [set.illustId],
          limit: 1,
        );
        if (remaining == 0 &&
            illust.isNotEmpty &&
            illust.first[DownloadedIllustColumns.sourceType] ==
                DownloadedIllust.sourceLocal) {
          await txn.delete(
            DownloadedIllustColumns.tableName,
            where: '${DownloadedIllustColumns.illustId} = ?',
            whereArgs: [set.illustId],
          );
        }
      });
    } catch (_) {
      if (await trash.exists() && !await source.exists()) {
        await source.parent.create(recursive: true);
        await trash.rename(source.path);
      }
      rethrow;
    }
    if (await trash.exists()) await trash.delete(recursive: true);
  }

  /// 将本地占位作品的所有原图版本关联到已有 Pixiv 作品。
  Future<void> linkLocalToPixiv(
    int localIllustId,
    int pixivIllustId, {
    Map<int, List<OriginalMappingDraft>> mappingsBySet = const {},
  }) async {
    if (localIllustId >= 0 || pixivIllustId <= 0) {
      throw ArgumentError('本地作品 ID 必须为负数，Pixiv 作品 ID 必须为正数');
    }
    await _db.transaction((txn) async {
      final target = await txn.query(
        DownloadedIllustColumns.tableName,
        where: '${DownloadedIllustColumns.illustId} = ?',
        whereArgs: [pixivIllustId],
        limit: 1,
      );
      if (target.isEmpty) throw StateError('目标 Pixiv 作品不存在');
      final sourceSets = await txn.query(
        'original_image_sets',
        where: 'illust_id = ?',
        whereArgs: [localIllustId],
        orderBy: 'created_at ASC',
      );
      final targetSets = await txn.query(
        'original_image_sets',
        columns: ['edition_name', 'is_default'],
        where: 'illust_id = ?',
        whereArgs: [pixivIllustId],
      );
      final names =
          targetSets.map((row) => row['edition_name'] as String).toSet();
      final targetHasDefault = targetSets.any((row) => row['is_default'] == 1);
      var defaultMigrated = false;
      for (final row in sourceSets) {
        final id = row['id'] as int;
        final originalName = row['edition_name'] as String;
        var editionName = originalName;
        var suffix = 2;
        while (names.contains(editionName)) {
          editionName = '$originalName ($suffix)';
          suffix++;
        }
        names.add(editionName);
        final wasDefault = row['is_default'] == 1;
        final useDefault = !targetHasDefault && !defaultMigrated && wasDefault;
        if (useDefault) defaultMigrated = true;
        final mappings = mappingsBySet[id];
        if (mappings != null) {
          final imageRows = await txn.query(
            'original_images',
            columns: ['id', 'source_order'],
            where: 'set_id = ?',
            whereArgs: [id],
          );
          final imageIds = {
            for (final image in imageRows)
              image['source_order'] as int: image['id'] as int,
          };
          await txn.delete(
            'original_page_mappings',
            where: 'set_id = ?',
            whereArgs: [id],
          );
          for (final mapping in mappings) {
            await txn.insert('original_page_mappings', {
              'set_id': id,
              'display_order': mapping.displayOrder,
              'downloaded_part': mapping.downloadedPart,
              'original_image_id':
                  mapping.originalSourceOrder == null
                      ? null
                      : imageIds[mapping.originalSourceOrder],
              'relation_type': mapping.relationType.value,
              'manually_adjusted': mapping.manuallyAdjusted ? 1 : 0,
            });
          }
        }
        await txn.update(
          'original_image_sets',
          {
            'illust_id': pixivIllustId,
            'edition_name': editionName,
            'is_default': useDefault ? 1 : 0,
            if (mappings != null) 'enhanced_page_count': mappings.length,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await txn.delete(
        DownloadedIllustColumns.tableName,
        where: '${DownloadedIllustColumns.illustId} = ?',
        whereArgs: [localIllustId],
      );
    });
  }

  Future<Map<String, int>> getStats({int? illustId, int? userId}) async {
    final args = <Object?>[];
    var join = '';
    var where = '';
    if (illustId != null) {
      where = 'WHERE original_image_sets.illust_id = ?';
      args.add(illustId);
    } else if (userId != null) {
      join =
          'INNER JOIN ${DownloadedIllustColumns.tableName} di '
          'ON di.${DownloadedIllustColumns.illustId} = original_image_sets.illust_id';
      where = 'WHERE di.${DownloadedIllustColumns.userId} = ?';
      args.add(userId);
    }
    final result = await _db.rawQuery('''
      SELECT COUNT(*) AS set_count,
             COUNT(DISTINCT original_image_sets.illust_id) AS illust_count,
             COALESCE(SUM(image_count), 0) AS image_count,
             COALESCE(SUM(original_image_sets.total_file_size), 0) AS total_file_size
      FROM original_image_sets $join $where
    ''', args);
    final row = result.first;
    return {
      'set_count': row['set_count'] as int? ?? 0,
      'illust_count': row['illust_count'] as int? ?? 0,
      'image_count': row['image_count'] as int? ?? 0,
      'total_file_size': row['total_file_size'] as int? ?? 0,
    };
  }

  Future<DisplayManifest> buildDisplayManifest(
    int illustId, {
    int? setId,
    OriginalDisplayMode mode = OriginalDisplayMode.originalPreferred,
  }) async {
    final downloaded = await provider.getLocalImageInfosByIllustId(illustId);
    if (mode == OriginalDisplayMode.downloaded) {
      final parts = downloaded.keys.toList()..sort();
      return DisplayManifest(
        illustId: illustId,
        mode: mode,
        pages: [
          for (var index = 0; index < parts.length; index++)
            DisplayManifestPage(
              displayOrder: index,
              downloadedPart: parts[index],
              downloadedImage: downloaded[parts[index]],
              relationType: OriginalRelationType.downloadFallback,
            ),
        ],
      );
    }

    final set =
        setId == null ? await getDefaultSet(illustId) : await getSet(setId);
    if (set == null) {
      return buildDisplayManifest(
        illustId,
        mode: OriginalDisplayMode.downloaded,
      );
    }
    final bundle = await getBundle(set.id!);
    if (bundle == null) {
      return const DisplayManifest(
        illustId: 0,
        mode: OriginalDisplayMode.originalPreferred,
        pages: [],
      );
    }
    final imageById = {for (final image in bundle.images) image.id: image};
    final pages = <DisplayManifestPage>[];
    final mappings =
        bundle.mappings.isEmpty
            ? [
              for (var i = 0; i < bundle.images.length; i++)
                OriginalPageMapping(
                  setId: set.id!,
                  displayOrder: i,
                  originalImageId: bundle.images[i].id,
                  relationType: OriginalRelationType.originalOnly,
                ),
            ]
            : bundle.mappings;
    for (final mapping in mappings) {
      final original = imageById[mapping.originalImageId];
      LocalImageInfo? originalInfo;
      if (original != null) {
        final filePath = p.join(provider.originalPath, original.relativePath);
        if (await File(filePath).exists()) {
          originalInfo = LocalImageInfo(
            path: filePath,
            width: original.width,
            height: original.height,
            fileSize: original.fileSize,
          );
        }
      }
      final downloadedInfo =
          mapping.downloadedPart == null
              ? null
              : downloaded[mapping.downloadedPart];
      if (originalInfo == null && downloadedInfo == null) continue;
      pages.add(
        DisplayManifestPage(
          displayOrder: pages.length,
          downloadedPart: mapping.downloadedPart,
          originalImage: original,
          originalImageInfo: originalInfo,
          downloadedImage: downloadedInfo,
          relationType: mapping.relationType,
        ),
      );
    }
    return DisplayManifest(
      illustId: illustId,
      edition: set,
      mode: mode,
      pages: pages,
    );
  }

  Future<int> allocateLocalIllustId() async {
    return _db.transaction((txn) async {
      final result = await txn.rawQuery('''
        SELECT MIN(illust_id) AS min_id FROM downloaded_illusts
        WHERE illust_id < 0
      ''');
      final minId = result.first['min_id'] as int?;
      return minId == null ? -1 : minId - 1;
    });
  }

  Future<DownloadedIllust> createLocalIllust({
    required int userId,
    required String userName,
    required String title,
    required DateTime createDate,
  }) async {
    return _db.transaction((txn) async {
      final result = await txn.rawQuery('''
        SELECT MIN(illust_id) AS min_id FROM downloaded_illusts
        WHERE illust_id < 0
      ''');
      final minId = result.first['min_id'] as int?;
      final illustId = minId == null ? -1 : minId - 1;
      final data = Illusts(
        id: illustId,
        title: title,
        type: 'manga',
        user: User(id: userId, name: userName),
        createDate: createDate.toIso8601String(),
        pageCount: 0,
        visible: true,
      );
      final record = DownloadedIllust.fromIllusts(
        data,
        '',
        sourceType: DownloadedIllust.sourceLocal,
        downloadRemovedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await txn.insert(DownloadedIllustColumns.tableName, record.toJson());
      return record;
    });
  }

  Future<void> markDownloadResourcesRemoved(int illustId) async {
    await _db.update(
      DownloadedIllustColumns.tableName,
      {
        DownloadedIllustColumns.downloadedImageCount: 0,
        DownloadedIllustColumns.totalFileSize: 0,
        DownloadedIllustColumns.downloadRemovedAt:
            DateTime.now().millisecondsSinceEpoch,
      },
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illustId],
    );
  }

  Future<void> clearDownloadResourcesRemoved(int illustId) async {
    await _db.update(
      DownloadedIllustColumns.tableName,
      {DownloadedIllustColumns.downloadRemovedAt: null},
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illustId],
    );
  }

  Future<DownloadedIllust> updateLocalMetadata({
    required int illustId,
    required String title,
    required DateTime createDate,
  }) async {
    final existing = await provider.getIllustByIllustId(illustId);
    if (existing == null || !existing.isLocal) {
      throw StateError('本地作品不存在');
    }
    final updatedData = existing.toIllusts().copyWith(
      title: title,
      createDate: createDate.toIso8601String(),
    );
    final updated = DownloadedIllust.fromIllusts(
      updatedData,
      existing.relativePath,
      downloadTime: existing.downloadTime,
      downloadedImageCount: 0,
      totalFileSize: 0,
      sourceType: DownloadedIllust.sourceLocal,
      downloadRemovedAt: existing.downloadRemovedAt,
    );
    await _db.update(
      DownloadedIllustColumns.tableName,
      updated.toJson(),
      where: '${DownloadedIllustColumns.illustId} = ?',
      whereArgs: [illustId],
    );
    return updated;
  }
}
