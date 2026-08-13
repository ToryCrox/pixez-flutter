import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pixez/ai/ai_translation_service.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/manga_ocr/manga_image_preprocessor.dart';
import 'package:pixez/manga_ocr/manga_ocr_cache.dart';
import 'package:pixez/manga_ocr/manga_ocr_engines.dart';
import 'package:pixez/manga_ocr/manga_ocr_model_manager.dart';
import 'package:pixez/manga_ocr/manga_ocr_models.dart';
import 'package:pixez/manga_ocr/manga_ocr_runtime.dart';

typedef MangaOcrProgressCallback =
    void Function(
      MangaOcrStage stage,
      int completed,
      int total,
      String message,
    );

class MangaOcrPipeline {
  final MangaImagePreprocessor preprocessor;
  final MangaOcrEngineRegistry registry;
  final MangaOcrRuntime runtime;
  final MangaOcrModelManager modelManager;
  final MangaOcrCache cache;
  final AiTranslationService? translationService;

  MangaOcrPipeline({
    MangaImagePreprocessor? preprocessor,
    MangaOcrEngineRegistry? registry,
    MangaOcrRuntime? runtime,
    MangaOcrModelManager? modelManager,
    MangaOcrCache? cache,
    this.translationService,
  }) : preprocessor = preprocessor ?? AdaptivePagePreprocessor(),
       registry = registry ?? MangaOcrEngineRegistry.instance,
       runtime = runtime ?? MangaOcrProcessRuntime(),
       modelManager = modelManager ?? MangaOcrModelManager(),
       cache = cache ?? MangaOcrCache();

  Future<MangaPageOcrResult> analyze({
    required String imagePath,
    required int pageIndex,
    required String targetLanguage,
    String detectorId = mangaOcrDefaultDetectorId,
    String recognizerId = mangaOcrDefaultRecognizerId,
    MangaOcrOptions options = const MangaOcrOptions(),
    bool forceOcr = false,
    bool translate = true,
    bool forceTranslation = false,
    MangaOcrProgressCallback? onProgress,
  }) async {
    onProgress?.call(MangaOcrStage.preparing, 0, 1, '计算图片指纹');
    final imageHash = await MangaOcrCache.hashFile(imagePath);
    final detector = registry.detector(detectorId);
    final recognizer = registry.recognizer(recognizerId);
    final key = MangaOcrCacheKey(
      imageSha256: imageHash,
      pageIndex: pageIndex,
      preprocessorId: preprocessor.id,
      preprocessorVersion: preprocessor.version,
      detectorId: detector.id,
      detectorVersion: detector.version,
      recognizerId: recognizer.id,
      recognizerVersion: recognizer.version,
      options: options,
    );

    MangaPageOcrResult? result;
    if (!forceOcr) result = await cache.get(key);
    if (result == null) {
      await _ensureModels([detector.id, recognizer.id], onProgress: onProgress);
      final modelDirectory = await modelManager.modelDirectory();
      await runtime.loadModels(
        modelDirectory: modelDirectory,
        detector: detector.runtimeConfiguration,
        recognizer: recognizer.runtimeConfiguration,
      );
      onProgress?.call(MangaOcrStage.detecting, 0, 1, '自动检测整页文字');
      final response = await runtime.analyzePage({
        'imagePath': imagePath,
        'imageSha256': imageHash,
        'pageIndex': pageIndex,
        'preprocessor': {
          'id': preprocessor.id,
          'version': preprocessor.version,
          ...options.toJson(),
        },
        'detector': detector.runtimeConfiguration,
        'recognizer': recognizer.runtimeConfiguration,
      });
      final blocks = _normalizeAndSort(
        (response['blocks'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  MangaTextBlock.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
        imageHash: imageHash,
        options: options,
      );
      result = MangaPageOcrResult(
        imageSha256: imageHash,
        pageIndex: pageIndex,
        imageWidth: response['imageWidth'] as int? ?? 0,
        imageHeight: response['imageHeight'] as int? ?? 0,
        preprocessorId: preprocessor.id,
        preprocessorVersion: preprocessor.version,
        detectorId: detector.id,
        detectorVersion: detector.version,
        recognizerId: recognizer.id,
        recognizerVersion: recognizer.version,
        createdAt: DateTime.now(),
        blocks: blocks,
      );
      await cache.put(key, result);
    } else {
      onProgress?.call(MangaOcrStage.recognizing, 1, 1, '已载入本地 OCR 缓存');
    }

    if (!translate || result.blocks.every((item) => item.sourceText.isEmpty)) {
      onProgress?.call(MangaOcrStage.completed, 1, 1, 'OCR 完成');
      return result;
    }
    final service = translationService;
    if (service == null) {
      onProgress?.call(MangaOcrStage.completed, 1, 1, 'OCR 完成，未配置翻译服务');
      return result;
    }
    onProgress?.call(MangaOcrStage.translating, 0, 1, '正在发送 OCR 文本给 AI 翻译');
    try {
      final translations = await service.translateMangaPage(
        imageSha256: result.imageSha256,
        pageIndex: pageIndex,
        targetLanguage: targetLanguage,
        blocks: {
          for (final block in result.blocks)
            if (block.sourceText.trim().isNotEmpty) block.id: block.sourceText,
        },
        forceRefresh: forceTranslation,
      );
      result = result.copyWith(
        blocks:
            result.blocks
                .map(
                  (block) => block.copyWith(
                    translatedText: translations[block.id] ?? '',
                  ),
                )
                .toList(),
      );
      onProgress?.call(MangaOcrStage.completed, 1, 1, '识别与翻译完成');
    } catch (error, stackTrace) {
      Log.w('漫画 OCR 翻译失败，保留原文', error: error, stackTrace: stackTrace);
      onProgress?.call(MangaOcrStage.completed, 1, 1, 'OCR 完成，翻译暂不可用');
    }
    return result!;
  }

  Future<void> cancel() => runtime.shutdown();

  Future<void> _ensureModels(
    List<String> engineIds, {
    MangaOcrProgressCallback? onProgress,
  }) async {
    for (var index = 0; index < engineIds.length; index++) {
      final engineId = engineIds[index];
      if (await modelManager.isInstalled(engineId)) continue;
      onProgress?.call(
        MangaOcrStage.preparing,
        index,
        engineIds.length,
        '下载本地模型：$engineId',
      );
      await modelManager.install(
        engineId,
        onProgress: (progress) {
          onProgress?.call(
            MangaOcrStage.preparing,
            progress.received,
            progress.total,
            '下载 ${progress.fileName}',
          );
        },
      );
    }
  }

  List<MangaTextBlock> _normalizeAndSort(
    List<MangaTextBlock> blocks, {
    required String imageHash,
    required MangaOcrOptions options,
  }) {
    final withIds = <MangaTextBlock>[];
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      final rect = block.bounds.clamp();
      final id =
          block.id.isNotEmpty
              ? block.id
              : sha256
                  .convert(
                    utf8.encode(
                      '$imageHash|${rect.left.toStringAsFixed(6)}|'
                      '${rect.top.toStringAsFixed(6)}|'
                      '${rect.right.toStringAsFixed(6)}|'
                      '${rect.bottom.toStringAsFixed(6)}',
                    ),
                  )
                  .toString()
                  .substring(0, 16);
      withIds.add(
        MangaTextBlock(
          id: id,
          bounds: rect,
          sourceText: block.sourceText,
          translatedText: block.translatedText,
          language: block.language,
          direction: block.direction,
          detectionConfidence: block.detectionConfidence,
          recognitionConfidence: block.recognitionConfidence,
          usedHighResolutionRetry: block.usedHighResolutionRetry,
          warning:
              block.sourceText.trim().isEmpty ? '识别失败/低置信度' : block.warning,
        ),
      );
    }
    final merged =
        preprocessor is AdaptivePagePreprocessor
            ? (preprocessor as AdaptivePagePreprocessor).mergeDuplicates(
              withIds,
              iouThreshold: options.duplicateIouThreshold,
            )
            : withIds;
    final verticalCount =
        merged
            .where((item) => item.direction == MangaTextDirection.vertical)
            .length;
    final effectiveOrder =
        options.readingOrder == MangaReadingOrder.automatic
            ? (verticalCount > merged.length / 2
                ? MangaReadingOrder.mangaRtl
                : MangaReadingOrder.leftToRight)
            : options.readingOrder;
    final sorted = sortBlocks(merged, effectiveOrder);
    return [
      for (var index = 0; index < sorted.length; index++)
        sorted[index].copyWith(order: index),
    ];
  }

  static List<MangaTextBlock> sortBlocks(
    Iterable<MangaTextBlock> blocks,
    MangaReadingOrder readingOrder,
  ) {
    final sorted = blocks.toList();
    final rtl = readingOrder == MangaReadingOrder.mangaRtl;
    sorted.sort((a, b) => _compareBlocks(a, b, rtl: rtl));
    return sorted;
  }

  static int _compareBlocks(
    MangaTextBlock a,
    MangaTextBlock b, {
    required bool rtl,
  }) {
    if (rtl) {
      final sameColumn =
          (a.bounds.centerX - b.bounds.centerX).abs() <
          (a.bounds.width + b.bounds.width) * 0.35;
      if (sameColumn) return a.bounds.top.compareTo(b.bounds.top);
      return b.bounds.centerX.compareTo(a.bounds.centerX);
    }
    final sameRow =
        (a.bounds.centerY - b.bounds.centerY).abs() <
        (a.bounds.height + b.bounds.height) * 0.35;
    if (sameRow) return a.bounds.left.compareTo(b.bounds.left);
    return a.bounds.top.compareTo(b.bounds.top);
  }
}
