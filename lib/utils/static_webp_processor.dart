import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as path;
import 'package:pixez/custom/log.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/utils/cwebp_tool.dart';
import 'package:pixez/utils/image_utils.dart';
import 'package:pixez/utils/webp_processing_options.dart';

export 'cwebp_tool.dart';
export 'webp_processing_options.dart';

class WebpProcessingInput {
  final int illustId;
  final int part;
  final int userId;
  final String sourcePath;
  final bool isUgoira;

  const WebpProcessingInput({
    required this.illustId,
    required this.part,
    required this.userId,
    required this.sourcePath,
    required this.isUgoira,
  });
}

class WebpProcessingResult {
  final WebpProcessingInput input;
  final int originalSize;
  final WebpTargetSize? originalDimensions;
  final String? outputPath;
  final int? outputSize;
  final WebpTargetSize? outputDimensions;
  final String? error;

  const WebpProcessingResult({
    required this.input,
    required this.originalSize,
    this.originalDimensions,
    this.outputPath,
    this.outputSize,
    this.outputDimensions,
    this.error,
  });

  bool get isSuccess =>
      outputPath != null && outputSize != null && error == null;

  int? get sizeDelta => isSuccess ? outputSize! - originalSize : null;
}

class WebpReplacementResult {
  final WebpProcessingResult processingResult;
  final String? error;

  const WebpReplacementResult({required this.processingResult, this.error});

  bool get isSuccess => error == null;
}

/// 使用应用随附 cwebp 工具处理静态图片。
class StaticWebpProcessor {
  static const defaultConcurrency = 3;
  static const maxConcurrency = 16;

  static const _supportedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.tif',
    '.tiff',
    '.webp',
  };

  final String? executablePath;

  const StaticWebpProcessor({this.executablePath});

  static Future<WebpToolCheck> checkAvailability() =>
      CwebpTool.checkAvailability();

  static Future<Directory> createSessionDirectory(
    Directory temporaryDirectory,
  ) async {
    final root = Directory(
      path.join(temporaryDirectory.path, 'pixez_webp_processing'),
    );
    await root.create(recursive: true);
    final session = Directory(
      path.join(
        root.path,
        '${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 32)}',
      ),
    );
    await session.create(recursive: true);
    return session;
  }

  static Future<void> cleanupStaleSessions(Directory temporaryDirectory) async {
    final root = Directory(
      path.join(temporaryDirectory.path, 'pixez_webp_processing'),
    );
    if (!await root.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      try {
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete(recursive: true);
        }
      } catch (e, stackTrace) {
        Log.w(() => '清理遗留 WebP 临时文件失败: $entity');
        Log.e('清理遗留 WebP 临时文件异常', error: e, stackTrace: stackTrace);
      }
    }
  }

  Future<List<WebpProcessingResult>> processAll({
    required List<WebpProcessingInput> inputs,
    required WebpProcessingOptions options,
    required Directory sessionDirectory,
    int concurrency = defaultConcurrency,
    void Function(int completed, int total)? onProgress,
  }) async {
    final error = options.validate();
    if (error != null) throw ArgumentError(error);
    if (concurrency < 1) {
      throw ArgumentError.value(concurrency, 'concurrency', '必须大于等于 1');
    }
    final tool = await CwebpTool.resolve(preferredPath: executablePath);
    if (tool == null) throw StateError('未找到随应用提供的 cwebp 工具');

    if (inputs.isEmpty) return const [];

    final results = List<WebpProcessingResult?>.filled(inputs.length, null);
    var nextIndex = 0;
    var completed = 0;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= inputs.length) return;
        results[index] = await _processOne(
          input: inputs[index],
          options: options,
          tool: tool,
          outputPath: path.join(
            sessionDirectory.path,
            '${index.toString().padLeft(4, '0')}.webp',
          ),
        );
        completed++;
        onProgress?.call(completed, inputs.length);
      }
    }

    final workerCount = math.min(concurrency, inputs.length).toInt();
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return List.generate(inputs.length, (index) => results[index]!);
  }

  Future<WebpProcessingResult> _processOne({
    required WebpProcessingInput input,
    required WebpProcessingOptions options,
    required CwebpTool tool,
    required String outputPath,
  }) async {
    final source = File(input.sourcePath);
    var originalSize = 0;
    try {
      if (input.isUgoira || input.part == DownloadedImage.partUgoiraWebP) {
        return WebpProcessingResult(
          input: input,
          originalSize: 0,
          error: '动图不支持格式处理',
        );
      }
      if (!_supportedExtensions.contains(
        path.extension(input.sourcePath).toLowerCase(),
      )) {
        return WebpProcessingResult(
          input: input,
          originalSize: 0,
          error: '不支持的图片格式',
        );
      }
      if (!await source.exists()) {
        return WebpProcessingResult(
          input: input,
          originalSize: 0,
          error: '源文件不存在',
        );
      }
      originalSize = await source.length();
      if (await _isAnimatedWebp(source)) {
        return WebpProcessingResult(
          input: input,
          originalSize: originalSize,
          error: '动画 WebP 不支持格式处理',
        );
      }
      final sourceSize = await ImageUtils.parseImageSize(input.sourcePath);
      if (sourceSize == null ||
          sourceSize.width <= 0 ||
          sourceSize.height <= 0) {
        return WebpProcessingResult(
          input: input,
          originalSize: originalSize,
          error: '无法读取图片尺寸',
        );
      }
      final originalDimensions = WebpTargetSize(
        width: sourceSize.width.round(),
        height: sourceSize.height.round(),
      );
      final target = options.targetSizeFor(
        originalDimensions.width,
        originalDimensions.height,
      );
      final arguments = <String>[
        '-q',
        options.quality.toString(),
        '-m',
        '4',
        '-mt',
        '-metadata',
        'all',
        if (target != originalDimensions) ...[
          '-resize',
          target.width.toString(),
          target.height.toString(),
        ],
        '-o',
        outputPath,
        '--',
        input.sourcePath,
      ];
      final result = await tool.run(arguments);
      final output = File(outputPath);
      if (result.exitCode != 0 || !await output.exists()) {
        if (await output.exists()) await output.delete();
        final reason = result.stderr.toString().trim();
        return WebpProcessingResult(
          input: input,
          originalSize: originalSize,
          originalDimensions: originalDimensions,
          error: reason.isEmpty ? 'cwebp 处理失败（退出码 ${result.exitCode}）' : reason,
        );
      }
      final outputSize = await output.length();
      final outputImageSize = await ImageUtils.parseImageSize(outputPath);
      final outputDimensions =
          outputImageSize == null
              ? target
              : WebpTargetSize(
                width: outputImageSize.width.round(),
                height: outputImageSize.height.round(),
              );
      return WebpProcessingResult(
        input: input,
        originalSize: originalSize,
        originalDimensions: originalDimensions,
        outputPath: outputPath,
        outputSize: outputSize,
        outputDimensions: outputDimensions,
      );
    } catch (e, stackTrace) {
      Log.e(
        '处理 WebP 图片失败: ${input.sourcePath}',
        error: e,
        stackTrace: stackTrace,
      );
      final output = File(outputPath);
      if (await output.exists()) await output.delete();
      return WebpProcessingResult(
        input: input,
        originalSize: originalSize,
        error: '处理失败：$e',
      );
    }
  }

  Future<bool> _isAnimatedWebp(File file) async {
    if (path.extension(file.path).toLowerCase() != '.webp') return false;
    final reader = await file.open(mode: FileMode.read);
    try {
      final header = await reader.read(21);
      if (header.length < 21) return false;
      final isWebp =
          String.fromCharCodes(header.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(header.sublist(8, 12)) == 'WEBP';
      final hasExtendedHeader =
          String.fromCharCodes(header.sublist(12, 16)) == 'VP8X';
      // VP8X 的 bit 1 为动画标记；动画 WebP 必须包含 VP8X 块。
      return isWebp && hasExtendedHeader && (header[20] & 0x02) != 0;
    } finally {
      await reader.close();
    }
  }

  Future<List<WebpReplacementResult>> replaceAll({
    required List<WebpProcessingResult> results,
    required DownloadDatabaseProvider databaseProvider,
  }) async {
    final replacementResults = <WebpReplacementResult>[];
    for (final result in results.where((result) => result.isSuccess)) {
      replacementResults.add(
        await _replaceOne(result: result, databaseProvider: databaseProvider),
      );
    }
    return replacementResults;
  }

  Future<WebpReplacementResult> _replaceOne({
    required WebpProcessingResult result,
    required DownloadDatabaseProvider databaseProvider,
  }) async {
    final source = File(result.input.sourcePath);
    final output = File(result.outputPath!);
    final destinationPath = path.join(
      source.parent.path,
      '${path.basenameWithoutExtension(source.path)}.webp',
    );
    final destination = File(destinationPath);
    final samePath = path.equals(source.path, destination.path);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final stage = File(
      path.join(
        source.parent.path,
        '.${path.basename(destination.path)}.pixez-stage-$stamp',
      ),
    );
    final backup = File(
      path.join(
        source.parent.path,
        '.${path.basename(source.path)}.pixez-backup-$stamp',
      ),
    );
    var sourceMoved = false;
    var destinationWritten = false;
    var databaseCommitted = false;

    try {
      if (!await source.exists()) throw StateError('源文件不存在');
      if (!await output.exists()) throw StateError('处理后的临时文件不存在');
      if (!samePath && await destination.exists()) {
        throw StateError('目标文件已存在：${path.basename(destination.path)}');
      }

      await output.copy(stage.path);
      await source.rename(backup.path);
      sourceMoved = true;
      await stage.rename(destination.path);
      destinationWritten = true;

      await databaseProvider.replaceImageWithWebpRecord(
        illustId: result.input.illustId,
        part: result.input.part,
        userId: result.input.userId,
        fileSize: result.outputSize!,
        width: result.outputDimensions!.width,
        height: result.outputDimensions!.height,
      );
      databaseCommitted = true;

      try {
        await backup.delete();
      } catch (e, stackTrace) {
        Log.e('清理 WebP 源文件备份失败', error: e, stackTrace: stackTrace);
      }
      try {
        if (await output.exists()) await output.delete();
      } catch (e, stackTrace) {
        Log.e('清理 WebP 临时输出失败', error: e, stackTrace: stackTrace);
      }
      return WebpReplacementResult(processingResult: result);
    } catch (e, stackTrace) {
      Log.e('替换 WebP 原图失败: ${source.path}', error: e, stackTrace: stackTrace);
      if (!databaseCommitted) {
        try {
          if (destinationWritten && await destination.exists()) {
            await destination.delete();
          }
          if (sourceMoved && await backup.exists()) {
            await backup.rename(source.path);
          }
          if (await stage.exists()) await stage.delete();
        } catch (rollbackError, rollbackStackTrace) {
          Log.e(
            '回滚 WebP 文件替换失败',
            error: rollbackError,
            stackTrace: rollbackStackTrace,
          );
        }
      }
      return WebpReplacementResult(
        processingResult: result,
        error: e.toString(),
      );
    }
  }

  static Future<void> cleanupSession(Directory? sessionDirectory) async {
    if (sessionDirectory == null || !await sessionDirectory.exists()) return;
    try {
      await sessionDirectory.delete(recursive: true);
    } catch (e, stackTrace) {
      Log.e('删除 WebP 临时文件失败', error: e, stackTrace: stackTrace);
    }
  }
}
