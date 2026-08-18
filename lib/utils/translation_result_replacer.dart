import 'dart:io';
import 'dart:ui';

import 'package:path/path.dart' as path;
import 'package:pixez/custom/log.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/utils/image_utils.dart';

/// 一个可由外部翻译工具生成并替换的图片对。
class TranslationReplacementPair {
  final DownloadedImage image;
  final String originalPath;
  final String translatedPath;
  final int originalSize;
  final int translatedSize;
  final Size? originalDimensions;
  final Size? translatedDimensions;

  const TranslationReplacementPair({
    required this.image,
    required this.originalPath,
    required this.translatedPath,
    required this.originalSize,
    required this.translatedSize,
    required this.originalDimensions,
    required this.translatedDimensions,
  });

  String get baseName => path.basenameWithoutExtension(originalPath);

  String get destinationPath => path.join(
    path.dirname(originalPath),
    '$baseName${path.extension(translatedPath).toLowerCase()}',
  );
}

class TranslationUnmatchedFile {
  final String path;
  final bool isOriginal;
  final String reason;

  const TranslationUnmatchedFile({
    required this.path,
    required this.isOriginal,
    required this.reason,
  });
}

class TranslationReplacementPlan {
  final DownloadedIllust illust;
  final String workDirectory;
  final List<String> resultDirectories;
  final String? externalComicDirectory;
  final List<TranslationReplacementPair> pairs;
  final List<TranslationUnmatchedFile> unmatched;

  const TranslationReplacementPlan({
    required this.illust,
    required this.workDirectory,
    required this.resultDirectories,
    required this.externalComicDirectory,
    required this.pairs,
    required this.unmatched,
  });

  int get originalTotalSize =>
      pairs.fold(0, (sum, pair) => sum + pair.originalSize);
  int get translatedTotalSize =>
      pairs.fold(0, (sum, pair) => sum + pair.translatedSize);
}

class TranslationReplacementResult {
  final TranslationReplacementPair pair;
  final String? error;

  const TranslationReplacementResult({required this.pair, this.error});

  bool get isSuccess => error == null;
}

class TranslationReplacementSummary {
  final List<TranslationReplacementResult> results;
  final int skippedCount;
  final bool translationResultDirectoriesCleaned;
  final bool intermediateDirectoriesCleaned;

  const TranslationReplacementSummary({
    required this.results,
    required this.skippedCount,
    required this.translationResultDirectoriesCleaned,
    required this.intermediateDirectoriesCleaned,
  });

  int get successCount => results.where((result) => result.isSuccess).length;
  int get failureCount => results.length - successCount;
}

/// 多个作品的翻译结果替换计划。
class TranslationReplacementBatchPlan {
  final int selectedCount;
  final List<TranslationReplacementPlan> plans;

  const TranslationReplacementBatchPlan({
    required this.selectedCount,
    required this.plans,
  });

  int get noResultCount => selectedCount - plans.length;
  int get pairCount =>
      plans.fold(0, (total, plan) => total + plan.pairs.length);
  int get unmatchedCount =>
      plans.fold(0, (total, plan) => total + plan.unmatched.length);
  int get originalTotalSize =>
      plans.fold(0, (total, plan) => total + plan.originalTotalSize);
  int get translatedTotalSize =>
      plans.fold(0, (total, plan) => total + plan.translatedTotalSize);
}

/// 单个作品在批量替换中的结果，允许某个作品失败而继续处理其他作品。
class TranslationReplacementBatchItemSummary {
  final TranslationReplacementPlan plan;
  final TranslationReplacementSummary? summary;
  final String? error;

  const TranslationReplacementBatchItemSummary({
    required this.plan,
    this.summary,
    this.error,
  });

  int get successCount => summary?.successCount ?? 0;
  int get failureCount => summary?.failureCount ?? 0;
  int get skippedCount => summary?.skippedCount ?? 0;
  bool get isSuccess => error == null && summary != null;
  bool get translationResultDirectoriesCleaned =>
      summary?.translationResultDirectoriesCleaned ?? false;
}

/// 多个作品的翻译结果替换汇总。
class TranslationReplacementBatchSummary {
  final List<TranslationReplacementBatchItemSummary> items;

  const TranslationReplacementBatchSummary({required this.items});

  int get successCount =>
      items.fold(0, (total, item) => total + item.successCount);
  int get failureCount =>
      items.fold(0, (total, item) => total + item.failureCount);
  int get skippedCount =>
      items.fold(0, (total, item) => total + item.skippedCount);
  int get failedPlanCount => items.where((item) => !item.isSuccess).length;
  bool get translationResultDirectoriesCleaned =>
      items.every((item) => item.translationResultDirectoriesCleaned);
}

class _TranslationResultDirectoryEntry {
  const _TranslationResultDirectoryEntry({
    required this.translationDirectory,
    required this.originalDirectory,
  });

  final Directory translationDirectory;
  final Directory originalDirectory;
}

/// 将作品目录下或外部目录中的翻译图片安全替换到下载图片中。
class TranslationResultReplacer {
  static const resultDirectoryName = 'result';
  static final _translationDirectoryIdPattern = RegExp(r'^\[(\d+)\]');
  static const _intermediateDirectoryNames = [
    'inpainted',
    'mask',
    'manga_translator_work',
  ];

  final DownloadDatabaseProvider databaseProvider;

  const TranslationResultReplacer(this.databaseProvider);

  /// 一次扫描外部翻译结果根目录，按插画目录 basename 中的 `[illustId]`
  /// 建立可替换作品集合。
  ///
  /// 自动标记场景只扫描外部根目录的第一层，并且只检查插画目录根层的
  /// 图片；下载目录没有章节目录，因此不递归扫描每个插画目录。
  Future<Set<int>> scanExternalTranslationResults(
    String translationResultRootDirectory,
  ) async {
    final rootPath = translationResultRootDirectory.trim();
    if (rootPath.isEmpty) return <int>{};

    final rootDirectory = Directory(rootPath);
    if (!await rootDirectory.exists()) return <int>{};

    final result = <int>{};
    await for (final entity in rootDirectory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final match = _translationDirectoryIdPattern.firstMatch(
        path.basename(entity.path),
      );
      final illustId = int.tryParse(match?.group(1) ?? '');
      if (illustId == null) continue;
      if (await _containsImages(entity)) result.add(illustId);
    }
    return result;
  }

  /// 快速判断是否有可能对应当前作品的译图，用于决定是否显示菜单项。
  Future<bool> hasReplacementCandidate(
    DownloadedIllust illust, {
    String? translationResultRootDirectory,
  }) async {
    try {
      if (illust.isUgoira) return false;
      final plan = await prepare(
        illust,
        translationResultRootDirectory: translationResultRootDirectory,
        includeDimensions: false,
      );
      return plan.pairs.isNotEmpty;
    } catch (e, stackTrace) {
      Log.e('检查翻译结果目录失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  Future<TranslationReplacementPlan> prepare(
    DownloadedIllust illust, {
    String? translationResultRootDirectory,
    bool includeDimensions = true,
  }) async {
    final workDirectory = databaseProvider.getIllustAbsolutePath(
      illust.relativePath,
    );
    final rootDirectory = Directory(workDirectory);
    final entries = <_TranslationResultDirectoryEntry>[];
    final legacyDirectories = await _findLegacyResultDirectories(rootDirectory);
    entries.addAll(
      legacyDirectories.map(
        (directory) => _TranslationResultDirectoryEntry(
          translationDirectory: directory,
          originalDirectory: directory.parent,
        ),
      ),
    );

    String? externalComicDirectory;
    final customRoot = translationResultRootDirectory?.trim() ?? '';
    if (customRoot.isNotEmpty) {
      final customComic = Directory(
        path.join(customRoot, path.basename(path.normalize(workDirectory))),
      );
      if (await customComic.exists()) {
        externalComicDirectory = customComic.path;
        final customEntries = await _findMirroredResultDirectories(
          customComic,
          rootDirectory,
        );
        final existingPaths =
            entries
                .map((entry) => path.normalize(entry.translationDirectory.path))
                .toSet();
        entries.addAll(
          customEntries.where(
            (entry) =>
                !existingPaths.contains(
                  path.normalize(entry.translationDirectory.path),
                ),
          ),
        );
      }
    }

    final resultDirectories =
        entries
            .map((entry) => entry.translationDirectory.path)
            .toSet()
            .toList();
    if (entries.isEmpty) {
      return TranslationReplacementPlan(
        illust: illust,
        workDirectory: workDirectory,
        resultDirectories: resultDirectories,
        externalComicDirectory: externalComicDirectory,
        pairs: const [],
        unmatched: const [],
      );
    }

    final unmatched = <TranslationUnmatchedFile>[];
    final originalByKey = <String, List<(DownloadedImage, String)>>{};
    final images = await databaseProvider.getImagesByIllustId(illust.illustId);
    for (final image in images) {
      if (illust.isUgoira || image.part == DownloadedImage.partUgoiraWebP) {
        continue;
      }
      final imagePath = await databaseProvider.findImagePathForImage(
        image,
        relativePath: illust.relativePath,
        isUgoira: false,
        update: false,
      );
      if (imagePath == null) {
        unmatched.add(
          TranslationUnmatchedFile(
            path: image.getFullFileName(),
            isOriginal: true,
            reason: '未找到原图文件',
          ),
        );
        continue;
      }
      final key = _imageKey(
        workDirectory,
        path.dirname(imagePath),
        path.basenameWithoutExtension(imagePath),
      );
      originalByKey.putIfAbsent(key, () => []).add((image, imagePath));
    }

    final pairs = <TranslationReplacementPair>[];
    final matchedOriginalPaths = <String>{};
    final matchedTranslationPaths = <String>{};
    for (final entry in entries) {
      final translatedByKey = <String, List<String>>{};
      for (final file in await _readImages(entry.translationDirectory)) {
        final key = _imageKey(
          workDirectory,
          entry.originalDirectory.path,
          path.basenameWithoutExtension(file.path),
        );
        translatedByKey.putIfAbsent(key, () => []).add(file.path);
      }

      final keys = translatedByKey.keys.toSet();
      final originalDirectoryKey = _relativeDirectoryKey(
        workDirectory,
        entry.originalDirectory.path,
      );
      keys.addAll(
        originalByKey.keys.where(
          (key) =>
              originalDirectoryKey.isEmpty
                  ? !key.contains('/')
                  : key.startsWith('$originalDirectoryKey/'),
        ),
      );
      for (final key in keys) {
        final originals = originalByKey[key] ?? const [];
        final translations = translatedByKey[key] ?? const [];
        if (originals.length == 1 && translations.length == 1) {
          final (image, originalPath) = originals.single;
          final translatedPath = translations.single;
          if (matchedOriginalPaths.contains(originalPath) ||
              matchedTranslationPaths.contains(translatedPath)) {
            continue;
          }
          matchedOriginalPaths.add(originalPath);
          matchedTranslationPaths.add(translatedPath);
          pairs.add(
            TranslationReplacementPair(
              image: image,
              originalPath: originalPath,
              translatedPath: translatedPath,
              originalSize: await File(originalPath).length(),
              translatedSize: await File(translatedPath).length(),
              originalDimensions:
                  includeDimensions
                      ? await ImageUtils.parseImageSize(originalPath)
                      : null,
              translatedDimensions:
                  includeDimensions
                      ? await ImageUtils.parseImageSize(translatedPath)
                      : null,
            ),
          );
          continue;
        }

        final duplicateOriginal = originals.length > 1;
        final duplicateTranslation = translations.length > 1;
        for (final (_, originalPath) in originals) {
          if (matchedOriginalPaths.contains(originalPath)) continue;
          unmatched.add(
            TranslationUnmatchedFile(
              path: originalPath,
              isOriginal: true,
              reason: duplicateOriginal ? '存在同名原图，无法确定替换目标' : '翻译结果目录中没有同名译图',
            ),
          );
        }
        for (final translatedPath in translations) {
          if (matchedTranslationPaths.contains(translatedPath)) continue;
          unmatched.add(
            TranslationUnmatchedFile(
              path: translatedPath,
              isOriginal: false,
              reason:
                  duplicateTranslation ? '翻译结果目录中存在同名译图，无法确定替换目标' : '没有同名原图',
            ),
          );
        }
      }
    }

    pairs.sort((a, b) => a.image.part.compareTo(b.image.part));
    return TranslationReplacementPlan(
      illust: illust,
      workDirectory: workDirectory,
      resultDirectories: resultDirectories,
      externalComicDirectory: externalComicDirectory,
      pairs: pairs,
      unmatched: unmatched,
    );
  }

  /// 为多个作品生成批量替换计划。
  ///
  /// 没有匹配译图的作品会从 [plans] 中排除，但 [selectedCount] 仍保留
  /// 原始选中数量，以便界面提示有多少作品没有可替换结果。
  Future<TranslationReplacementBatchPlan> prepareBatch(
    Iterable<DownloadedIllust> illusts, {
    String? translationResultRootDirectory,
    bool includeDimensions = true,
  }) async {
    final selectedIllusts = illusts.toList(growable: false);
    final preparedPlans = await Future.wait(
      selectedIllusts.map((illust) async {
        try {
          return await prepare(
            illust,
            translationResultRootDirectory: translationResultRootDirectory,
            includeDimensions: includeDimensions,
          );
        } catch (e, stackTrace) {
          Log.e(
            '读取批量翻译结果失败: ${illust.illustId}',
            error: e,
            stackTrace: stackTrace,
          );
          return null;
        }
      }),
    );
    return TranslationReplacementBatchPlan(
      selectedCount: selectedIllusts.length,
      plans:
          preparedPlans
              .whereType<TranslationReplacementPlan>()
              .where((plan) => plan.pairs.isNotEmpty)
              .toList(),
    );
  }

  Future<TranslationReplacementSummary> apply(
    TranslationReplacementPlan plan, {
    Set<String> skippedOriginalPaths = const <String>{},
  }) async {
    final skippedPathSet = skippedOriginalPaths.map(path.normalize).toSet();
    final skippedPairs =
        plan.pairs
            .where(
              (pair) =>
                  skippedPathSet.contains(path.normalize(pair.originalPath)),
            )
            .toList();
    final replacementPairs =
        plan.pairs.where((pair) => !skippedPairs.contains(pair)).toList();
    final results = <TranslationReplacementResult>[];
    for (final pair in replacementPairs) {
      results.add(await _replaceOne(plan.illust, pair));
    }

    // 只要本次至少成功替换一张图片，就将作品标记为已翻译；跳过的页面不影响标记。
    if (results.any((result) => result.isSuccess)) {
      await databaseProvider.updateIllustTranslationStatus(
        plan.illust.illustId,
        true,
      );
    }

    var skippedFilesCleaned = true;
    for (final pair in skippedPairs) {
      try {
        await _deleteFileIfExists(File(pair.translatedPath));
      } catch (e, stackTrace) {
        skippedFilesCleaned = false;
        Log.e(
          '清理跳过的翻译图片失败: ${pair.translatedPath}',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    final replacementsSucceeded =
        replacementPairs.isNotEmpty &&
        results.every((result) => result.isSuccess);
    final allSkipped =
        plan.pairs.isNotEmpty &&
        replacementPairs.isEmpty &&
        skippedFilesCleaned;
    var intermediateDirectoriesCleaned = false;
    var translationResultDirectoriesCleaned = false;
    if ((replacementsSucceeded && skippedFilesCleaned) || allSkipped) {
      translationResultDirectoriesCleaned =
          await _deletePlannedResultDirectories(plan);
      if (translationResultDirectoriesCleaned) {
        var intermediatesCleaned = true;
        for (final name in _intermediateDirectoryNames) {
          final currentCleaned = await _deleteDirectoryIfExists(
            path.join(plan.workDirectory, name),
          );
          intermediatesCleaned = currentCleaned && intermediatesCleaned;
        }
        if (plan.externalComicDirectory != null) {
          await _removeEmptyDirectory(plan.externalComicDirectory!);
        }
        intermediateDirectoriesCleaned = intermediatesCleaned;
      }
    }
    return TranslationReplacementSummary(
      results: results,
      skippedCount: skippedPairs.length,
      translationResultDirectoriesCleaned: translationResultDirectoriesCleaned,
      intermediateDirectoriesCleaned: intermediateDirectoriesCleaned,
    );
  }

  /// 批量应用多个作品的替换计划。
  ///
  /// 每个作品独立执行。单个作品发生未预期异常时会记录错误并继续处理
  /// 后续作品；图片级异常仍由 [apply] 负责回滚并保留失败文件。
  Future<TranslationReplacementBatchSummary> applyBatch(
    TranslationReplacementBatchPlan batchPlan, {
    Set<String> skippedOriginalPaths = const <String>{},
  }) async {
    final items = <TranslationReplacementBatchItemSummary>[];
    for (final plan in batchPlan.plans) {
      try {
        final summary = await apply(
          plan,
          skippedOriginalPaths: skippedOriginalPaths,
        );
        items.add(
          TranslationReplacementBatchItemSummary(plan: plan, summary: summary),
        );
      } catch (e, stackTrace) {
        Log.e(
          '批量替换作品失败: ${plan.illust.illustId}',
          error: e,
          stackTrace: stackTrace,
        );
        items.add(
          TranslationReplacementBatchItemSummary(
            plan: plan,
            error: e.toString(),
          ),
        );
      }
    }
    return TranslationReplacementBatchSummary(items: items);
  }

  String _imageKey(
    String workDirectory,
    String imageDirectory,
    String baseName,
  ) {
    final directoryKey = _relativeDirectoryKey(workDirectory, imageDirectory);
    return directoryKey.isEmpty
        ? baseName.toLowerCase()
        : '$directoryKey/${baseName.toLowerCase()}';
  }

  String _relativeDirectoryKey(String rootDirectory, String directory) {
    final relative = path.relative(
      path.normalize(directory),
      from: path.normalize(rootDirectory),
    );
    if (relative == '.') return '';
    return path.normalize(relative).replaceAll('\\', '/').toLowerCase();
  }

  Future<List<Directory>> _findLegacyResultDirectories(
    Directory rootDirectory,
  ) async {
    final result = <Directory>[];
    Future<void> visit(Directory directory) async {
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = path.basename(entity.path).toLowerCase();
        if (_isIgnoredDirectoryName(name)) continue;
        if (name == resultDirectoryName) result.add(entity);
        await visit(entity);
      }
    }

    await visit(rootDirectory);
    return result;
  }

  Future<List<_TranslationResultDirectoryEntry>> _findMirroredResultDirectories(
    Directory translationRoot,
    Directory originalRoot,
  ) async {
    final entries = <_TranslationResultDirectoryEntry>[];
    Future<void> visit(Directory directory) async {
      if (!await directory.exists()) return;
      if (await _containsImages(directory)) {
        final relativePath = path.relative(
          directory.path,
          from: translationRoot.path,
        );
        final originalPath =
            relativePath == '.'
                ? originalRoot.path
                : path.join(originalRoot.path, relativePath);
        entries.add(
          _TranslationResultDirectoryEntry(
            translationDirectory: directory,
            originalDirectory: Directory(originalPath),
          ),
        );
      }
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is Directory &&
            !_isIgnoredDirectoryName(
              path.basename(entity.path).toLowerCase(),
            )) {
          await visit(entity);
        }
      }
    }

    await visit(translationRoot);
    return entries;
  }

  Future<bool> _containsImages(Directory directory) async {
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isTranslationImage(entity.path)) return true;
    }
    return false;
  }

  Future<List<File>> _readImages(Directory directory) async {
    final files = <File>[];
    if (!await directory.exists()) return files;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isTranslationImage(entity.path)) {
        files.add(entity);
      }
    }
    return files;
  }

  bool _isTranslationImage(String filePath) {
    final fileName = path.basename(filePath).toLowerCase();
    if (fileName == 'cover.jpg' ||
        fileName == 'cover.jpeg' ||
        fileName == 'cover.png' ||
        fileName == 'cover.webp') {
      return false;
    }
    return kImageExtensions.contains(path.extension(fileName));
  }

  bool _isIgnoredDirectoryName(String name) =>
      _intermediateDirectoryNames.contains(name);

  Future<TranslationReplacementResult> _replaceOne(
    DownloadedIllust illust,
    TranslationReplacementPair pair,
  ) async {
    final original = File(pair.originalPath);
    final translated = File(pair.translatedPath);
    final extension = path.extension(translated.path).toLowerCase();
    final destination = File(pair.destinationPath);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final stage = File(
      path.join(
        original.parent.path,
        '.${path.basename(destination.path)}.translation-stage-$stamp',
      ),
    );
    final backup = File(
      path.join(
        original.parent.path,
        '.${path.basename(original.path)}.translation-backup-$stamp',
      ),
    );
    var originalMoved = false;
    var destinationWritten = false;
    var databaseCommitted = false;

    try {
      if (!await original.exists()) throw StateError('原图已不存在');
      if (!await translated.exists()) throw StateError('译图已不存在');
      if (await destination.exists() &&
          !path.equals(destination.path, original.path)) {
        throw StateError('目标文件已存在：${path.basename(destination.path)}');
      }
      final dimensions = await ImageUtils.parseImageSize(translated.path);
      if (dimensions == null ||
          dimensions.width <= 0 ||
          dimensions.height <= 0) {
        throw StateError('无法读取译图尺寸');
      }

      await translated.copy(stage.path);
      await original.rename(backup.path);
      originalMoved = true;
      await stage.rename(destination.path);
      destinationWritten = true;

      await databaseProvider.replaceImageWithTranslationRecord(
        illustId: pair.image.illustId,
        part: pair.image.part,
        userId: illust.userId,
        extension: extension,
        fileSize: await destination.length(),
        width: dimensions.width.round(),
        height: dimensions.height.round(),
      );
      databaseCommitted = true;

      try {
        await _deleteFileIfExists(backup);
      } catch (e, stackTrace) {
        Log.e('清理原图备份失败', error: e, stackTrace: stackTrace);
      }
      try {
        await _deleteFileIfExists(translated);
      } catch (e, stackTrace) {
        Log.e('清理已使用译图失败', error: e, stackTrace: stackTrace);
      }
      return TranslationReplacementResult(pair: pair);
    } catch (e, stackTrace) {
      Log.e('替换翻译图片失败: ${pair.originalPath}', error: e, stackTrace: stackTrace);
      if (!databaseCommitted) {
        try {
          if (destinationWritten && await destination.exists()) {
            await destination.delete();
          }
          if (originalMoved && await backup.exists()) {
            await backup.rename(original.path);
          }
          await _deleteFileIfExists(stage);
        } catch (rollbackError, rollbackStackTrace) {
          Log.e(
            '回滚翻译图片替换失败',
            error: rollbackError,
            stackTrace: rollbackStackTrace,
          );
        }
      }
      return TranslationReplacementResult(pair: pair, error: e.toString());
    }
  }

  Future<bool> _deletePlannedResultDirectories(
    TranslationReplacementPlan plan,
  ) async {
    if (plan.resultDirectories.isEmpty) return false;

    final plannedPaths = plan.resultDirectories.map(path.normalize).toSet();
    var cleaned = true;
    for (final resultDirectory in plannedPaths) {
      if (!_isResultDirectoryInPlan(resultDirectory, plan)) {
        Log.w('跳过计划外翻译结果目录清理: $resultDirectory');
        cleaned = false;
        continue;
      }
      final currentCleaned = await _clearPlannedDirectory(
        Directory(resultDirectory),
        plannedPaths,
      );
      cleaned = currentCleaned && cleaned;
    }
    return cleaned;
  }

  bool _isResultDirectoryInPlan(
    String resultDirectory,
    TranslationReplacementPlan plan,
  ) {
    final normalized = path.normalize(resultDirectory);
    if (_isPathWithin(normalized, path.normalize(plan.workDirectory))) {
      return true;
    }
    final externalComicDirectory = plan.externalComicDirectory;
    return externalComicDirectory != null &&
        _isPathWithin(normalized, path.normalize(externalComicDirectory));
  }

  bool _isPathWithin(String target, String parent) {
    return path.equals(target, parent) || path.isWithin(parent, target);
  }

  Future<bool> _clearPlannedDirectory(
    Directory directory,
    Set<String> plannedPaths,
  ) async {
    if (!await directory.exists()) return true;
    var cleaned = true;
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (e, stackTrace) {
            cleaned = false;
            Log.e(
              '清理翻译结果文件失败: ${entity.path}',
              error: e,
              stackTrace: stackTrace,
            );
          }
          continue;
        }
        if (entity is Directory) {
          final childPath = path.normalize(entity.path);
          if (!plannedPaths.contains(childPath)) {
            // 未纳入本次计划的子目录可能属于其他翻译任务，必须保留。
            continue;
          }
          final childCleaned = await _clearPlannedDirectory(
            entity,
            plannedPaths,
          );
          cleaned = childCleaned && cleaned;
          if (childCleaned && await entity.exists()) {
            try {
              if (await entity.list(followLinks: false).isEmpty) {
                await entity.delete();
              }
            } catch (e, stackTrace) {
              cleaned = false;
              Log.e(
                '删除翻译结果目录失败: ${entity.path}',
                error: e,
                stackTrace: stackTrace,
              );
            }
          }
        }
      }
      if (cleaned && await directory.exists()) {
        if (await directory.list(followLinks: false).isEmpty) {
          await directory.delete();
        }
      }
    } catch (e, stackTrace) {
      cleaned = false;
      Log.e('清理翻译结果目录失败: ${directory.path}', error: e, stackTrace: stackTrace);
    }
    return cleaned;
  }

  Future<bool> _removeEmptyDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return true;
    try {
      if (await directory.list(followLinks: false).isEmpty) {
        await directory.delete();
      }
      return true;
    } catch (e, stackTrace) {
      Log.e('清理空翻译结果目录失败: $directoryPath', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  Future<bool> _deleteDirectoryIfExists(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return true;
    try {
      await directory.delete(recursive: true);
      return true;
    } catch (e, stackTrace) {
      Log.e('清理翻译中间目录失败: $directoryPath', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> _deleteFileIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}
