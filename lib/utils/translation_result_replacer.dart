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
  final String resultDirectory;
  final List<TranslationReplacementPair> pairs;
  final List<TranslationUnmatchedFile> unmatched;

  const TranslationReplacementPlan({
    required this.illust,
    required this.workDirectory,
    required this.resultDirectory,
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
  final bool intermediateDirectoriesCleaned;

  const TranslationReplacementSummary({
    required this.results,
    required this.intermediateDirectoriesCleaned,
  });

  int get successCount => results.where((result) => result.isSuccess).length;
  int get failureCount => results.length - successCount;
}

/// 将作品目录下 result/ 中的翻译图片安全替换到下载图片中。
class TranslationResultReplacer {
  static const resultDirectoryName = 'result';
  static const _intermediateDirectoryNames = ['inpainted', 'mask'];

  final DownloadDatabaseProvider databaseProvider;

  const TranslationResultReplacer(this.databaseProvider);

  /// 快速判断 result/ 中是否有可能对应当前作品的译图，用于决定是否显示菜单项。
  Future<bool> hasReplacementCandidate(DownloadedIllust illust) async {
    try {
      if (illust.isUgoira) return false;
      final workDirectory = databaseProvider.getIllustAbsolutePath(
        illust.relativePath,
      );
      final resultDir = Directory(
        path.join(workDirectory, resultDirectoryName),
      );
      if (!await resultDir.exists()) return false;
      final images = await databaseProvider.getImagesByIllustId(
        illust.illustId,
      );
      final originalBaseNames =
          images
              .where((image) => image.part != DownloadedImage.partUgoiraWebP)
              .map((image) => image.fileName.toLowerCase())
              .toSet();
      if (originalBaseNames.isEmpty) return false;
      await for (final entity in resultDir.list(followLinks: false)) {
        if (entity is! File) continue;
        if (!kImageExtensions.contains(
          path.extension(entity.path).toLowerCase(),
        )) {
          continue;
        }
        if (originalBaseNames.contains(
          path.basenameWithoutExtension(entity.path).toLowerCase(),
        )) {
          return true;
        }
      }
      return false;
    } catch (e, stackTrace) {
      Log.e('检查翻译结果目录失败', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  Future<TranslationReplacementPlan> prepare(DownloadedIllust illust) async {
    final workDirectory = databaseProvider.getIllustAbsolutePath(
      illust.relativePath,
    );
    final resultDirectory = path.join(workDirectory, resultDirectoryName);
    final resultDir = Directory(resultDirectory);
    if (!await resultDir.exists()) {
      return TranslationReplacementPlan(
        illust: illust,
        workDirectory: workDirectory,
        resultDirectory: resultDirectory,
        pairs: const [],
        unmatched: const [],
      );
    }

    final unmatched = <TranslationUnmatchedFile>[];
    final originalByBaseName = <String, List<(DownloadedImage, String)>>{};
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
      final key = path.basenameWithoutExtension(imagePath).toLowerCase();
      originalByBaseName.putIfAbsent(key, () => []).add((image, imagePath));
    }

    final translatedByBaseName = <String, List<String>>{};
    await for (final entity in resultDir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!kImageExtensions.contains(
        path.extension(entity.path).toLowerCase(),
      )) {
        continue;
      }
      final key = path.basenameWithoutExtension(entity.path).toLowerCase();
      translatedByBaseName.putIfAbsent(key, () => []).add(entity.path);
    }

    final pairs = <TranslationReplacementPair>[];
    final allKeys = <String>{
      ...originalByBaseName.keys,
      ...translatedByBaseName.keys,
    };
    for (final key in allKeys) {
      final originals = originalByBaseName[key] ?? const [];
      final translations = translatedByBaseName[key] ?? const [];
      if (originals.length == 1 && translations.length == 1) {
        final (image, originalPath) = originals.single;
        final translatedPath = translations.single;
        pairs.add(
          TranslationReplacementPair(
            image: image,
            originalPath: originalPath,
            translatedPath: translatedPath,
            originalSize: await File(originalPath).length(),
            translatedSize: await File(translatedPath).length(),
            originalDimensions: await ImageUtils.parseImageSize(originalPath),
            translatedDimensions: await ImageUtils.parseImageSize(
              translatedPath,
            ),
          ),
        );
        continue;
      }

      final duplicateOriginal = originals.length > 1;
      final duplicateTranslation = translations.length > 1;
      for (final (_, originalPath) in originals) {
        unmatched.add(
          TranslationUnmatchedFile(
            path: originalPath,
            isOriginal: true,
            reason: duplicateOriginal ? '存在同名原图，无法确定替换目标' : 'result 中没有同名译图',
          ),
        );
      }
      for (final translatedPath in translations) {
        unmatched.add(
          TranslationUnmatchedFile(
            path: translatedPath,
            isOriginal: false,
            reason: duplicateTranslation ? 'result 中存在同名译图，无法确定替换目标' : '没有同名原图',
          ),
        );
      }
    }

    pairs.sort((a, b) => a.image.part.compareTo(b.image.part));
    return TranslationReplacementPlan(
      illust: illust,
      workDirectory: workDirectory,
      resultDirectory: resultDirectory,
      pairs: pairs,
      unmatched: unmatched,
    );
  }

  Future<TranslationReplacementSummary> apply(
    TranslationReplacementPlan plan,
  ) async {
    final results = <TranslationReplacementResult>[];
    for (final pair in plan.pairs) {
      results.add(await _replaceOne(plan.illust, pair));
    }

    final allSucceeded =
        results.isNotEmpty && results.every((result) => result.isSuccess);
    // 未匹配原图代表该页没有生成翻译结果，不应阻止已完成替换的
    // 翻译任务清理其临时目录；未匹配译图则仍需保留，方便后续排查。
    final hasUnmatchedTranslation = plan.unmatched.any(
      (item) => !item.isOriginal,
    );
    var intermediateDirectoriesCleaned = false;
    await _removeEmptyResultDirectory(plan.resultDirectory);
    if (allSucceeded && !hasUnmatchedTranslation) {
      for (final name in _intermediateDirectoryNames) {
        await _deleteDirectoryIfExists(path.join(plan.workDirectory, name));
      }
      intermediateDirectoriesCleaned = true;
    }
    return TranslationReplacementSummary(
      results: results,
      intermediateDirectoriesCleaned: intermediateDirectoriesCleaned,
    );
  }

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

  Future<void> _removeEmptyResultDirectory(String resultDirectory) async {
    final directory = Directory(resultDirectory);
    if (!await directory.exists()) return;
    try {
      if (await directory.list(followLinks: false).isEmpty) {
        await directory.delete();
      }
    } catch (e, stackTrace) {
      Log.e('清理空 result 目录失败', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _deleteDirectoryIfExists(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return;
    try {
      await directory.delete(recursive: true);
    } catch (e, stackTrace) {
      Log.e('清理翻译中间目录失败: $directoryPath', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _deleteFileIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}
