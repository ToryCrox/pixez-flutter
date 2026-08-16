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
  final bool intermediateDirectoriesCleaned;

  const TranslationReplacementSummary({
    required this.results,
    required this.intermediateDirectoriesCleaned,
  });

  int get successCount => results.where((result) => result.isSuccess).length;
  int get failureCount => results.length - successCount;
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
  static const _intermediateDirectoryNames = [
    'inpainted',
    'mask',
    'manga_translator_work',
  ];

  final DownloadDatabaseProvider databaseProvider;

  const TranslationResultReplacer(this.databaseProvider);

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
    for (final resultDirectory in plan.resultDirectories) {
      await _removeEmptyDirectory(resultDirectory);
    }
    if (allSucceeded && !hasUnmatchedTranslation) {
      for (final name in _intermediateDirectoryNames) {
        await _deleteDirectoryIfExists(path.join(plan.workDirectory, name));
      }
      if (plan.externalComicDirectory != null) {
        await _removeEmptyDirectoryTree(
          Directory(plan.externalComicDirectory!),
        );
      }
      intermediateDirectoriesCleaned = true;
    }
    return TranslationReplacementSummary(
      results: results,
      intermediateDirectoriesCleaned: intermediateDirectoriesCleaned,
    );
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

  Future<void> _removeEmptyDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return;
    try {
      if (await directory.list(followLinks: false).isEmpty) {
        await directory.delete();
      }
    } catch (e, stackTrace) {
      Log.e('清理空翻译结果目录失败: $directoryPath', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _removeEmptyDirectoryTree(Directory directory) async {
    if (!await directory.exists()) return;
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is Directory) {
          await _removeEmptyDirectoryTree(entity);
        }
      }
      if (await directory.list(followLinks: false).isEmpty) {
        await directory.delete();
      }
    } catch (e, stackTrace) {
      Log.e(
        '清理空翻译结果目录树失败: ${directory.path}',
        error: e,
        stackTrace: stackTrace,
      );
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
