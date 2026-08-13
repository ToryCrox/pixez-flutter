import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pixez/manga_ocr/manga_ocr_models.dart';
import 'package:pixez/manga_ocr/manga_ocr_pipeline.dart';

class MangaOcrController extends ChangeNotifier {
  final MangaOcrPipeline pipeline;

  MangaOcrController(this.pipeline);

  MangaOcrStage stage = MangaOcrStage.idle;
  MangaPageOcrResult? result;
  String message = '';
  String? error;
  int completed = 0;
  int total = 0;
  String? selectedBlockId;
  int _generation = 0;

  bool get isRunning => switch (stage) {
    MangaOcrStage.preparing ||
    MangaOcrStage.tiling ||
    MangaOcrStage.detecting ||
    MangaOcrStage.recognizing ||
    MangaOcrStage.translating => true,
    _ => false,
  };

  bool get isOcrRunning => switch (stage) {
    MangaOcrStage.preparing ||
    MangaOcrStage.tiling ||
    MangaOcrStage.detecting ||
    MangaOcrStage.recognizing => true,
    _ => false,
  };

  double? get progress => total <= 0 ? null : completed / total;

  Future<void> analyze({
    required String imagePath,
    required int pageIndex,
    required String targetLanguage,
    bool forceOcr = false,
    bool forceTranslation = false,
    String detectorId = mangaOcrDefaultDetectorId,
    String recognizerId = mangaOcrDefaultRecognizerId,
    MangaOcrOptions options = const MangaOcrOptions(),
  }) async {
    final generation = ++_generation;
    error = null;
    selectedBlockId = null;
    _update(MangaOcrStage.preparing, 0, 1, '准备图片');
    try {
      final value = await pipeline.analyze(
        imagePath: imagePath,
        pageIndex: pageIndex,
        targetLanguage: targetLanguage,
        forceOcr: forceOcr,
        translate: false,
        detectorId: detectorId,
        recognizerId: recognizerId,
        options: options,
        onProgress: (nextStage, nextCompleted, nextTotal, nextMessage) {
          if (generation != _generation) return;
          _update(nextStage, nextCompleted, nextTotal, nextMessage);
        },
      );
      if (generation != _generation) return;
      result = value;
      _update(MangaOcrStage.translating, 0, 1, '等待 AI 翻译队列');
      unawaited(
        _translate(
          value,
          generation: generation,
          targetLanguage: targetLanguage,
          forceTranslation: forceTranslation,
        ),
      );
    } catch (exception) {
      if (generation != _generation) return;
      error = exception.toString();
      _update(MangaOcrStage.failed, 0, 1, '处理失败');
    }
  }

  Future<void> cancel() async {
    _generation++;
    if (isOcrRunning) await pipeline.cancel();
    _update(MangaOcrStage.cancelled, 0, 1, '已取消');
  }

  Future<void> _translate(
    MangaPageOcrResult ocrResult, {
    required int generation,
    required String targetLanguage,
    required bool forceTranslation,
  }) async {
    try {
      final translated = await pipeline.translateResult(
        ocrResult,
        targetLanguage: targetLanguage,
        forceTranslation: forceTranslation,
        onProgress: (nextStage, nextCompleted, nextTotal, nextMessage) {
          if (generation != _generation) return;
          _update(nextStage, nextCompleted, nextTotal, nextMessage);
        },
      );
      if (generation != _generation) return;
      result = translated;
      if (stage != MangaOcrStage.completed) {
        _update(MangaOcrStage.completed, 1, 1, message);
      }
    } catch (exception) {
      if (generation != _generation) return;
      error = exception.toString();
      _update(MangaOcrStage.failed, 0, 1, '翻译失败');
    }
  }

  void selectBlock(String? id) {
    selectedBlockId = id;
    notifyListeners();
  }

  void clearForPageChange() {
    if (isRunning) unawaited(cancel());
    result = null;
    error = null;
    selectedBlockId = null;
    _update(MangaOcrStage.idle, 0, 0, '');
  }

  void markQueued() {
    error = null;
    _update(MangaOcrStage.preparing, 0, 1, '等待处理当前页');
  }

  void markCancelled() {
    _generation++;
    _update(MangaOcrStage.cancelled, 0, 1, '已取消');
  }

  void failExternally(String reason) {
    error = reason;
    _update(MangaOcrStage.failed, 0, 1, '处理失败');
  }

  void _update(
    MangaOcrStage nextStage,
    int nextCompleted,
    int nextTotal,
    String nextMessage,
  ) {
    stage = nextStage;
    completed = nextCompleted;
    total = nextTotal;
    message = nextMessage;
    notifyListeners();
  }

  @override
  void dispose() {
    // AI 请求无法可靠地从客户端中止；递增代次可阻止迟到响应回写已关闭页面。
    _generation++;
    super.dispose();
  }
}
