import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/manga_ocr/manga_ocr_controller.dart';
import 'package:pixez/manga_ocr/manga_ocr_models.dart';
import 'package:pixez/manga_ocr/manga_ocr_pipeline.dart';
import 'package:pixez/manga_ocr/manga_ocr_reading_session.dart';
import 'package:pixez/manga_ocr/manga_ocr_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePipeline extends MangaOcrPipeline {
  final calls = <int>[];
  final started = StreamController<int>.broadcast();
  Completer<void>? firstPageGate;

  @override
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
    calls.add(pageIndex);
    started.add(pageIndex);
    if (pageIndex == 0 && firstPageGate != null) {
      await firstPageGate!.future;
    }
    return MangaPageOcrResult(
      imageSha256: 'page-$pageIndex',
      pageIndex: pageIndex,
      imageWidth: 100,
      imageHeight: 200,
      preprocessorId: mangaOcrPreprocessorId,
      preprocessorVersion: mangaOcrPreprocessorVersion,
      detectorId: detectorId,
      detectorVersion: 'test',
      recognizerId: recognizerId,
      recognizerVersion: 'test',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      blocks: const [],
    );
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('打开面板不会开始 OCR，面板内确认后才处理', () async {
    final pipeline = _FakePipeline();
    final session = MangaOcrReadingSession(
      pipeline: pipeline,
      resolvePagePath: (page) async => '/tmp/page-$page.jpg',
      resolveTargetLanguage: () => 'zh-CN',
      pageSettleDuration: const Duration(milliseconds: 10),
    );
    addTearDown(() {
      session.dispose();
      pipeline.started.close();
    });

    session.open(0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(pipeline.calls, isEmpty);
    expect(session.hasStarted, isFalse);

    session.requestCurrent();
    await pipeline.started.stream.first;
    expect(pipeline.calls, [0]);
    expect(session.hasStarted, isTrue);
  });

  test('快速翻页只保留最新稳定页面', () async {
    final pipeline = _FakePipeline()..firstPageGate = Completer<void>();
    final session = MangaOcrReadingSession(
      pipeline: pipeline,
      resolvePagePath: (page) async => '/tmp/page-$page.jpg',
      resolveTargetLanguage: () => 'zh-CN',
      pageSettleDuration: const Duration(milliseconds: 10),
    );
    addTearDown(() {
      session.dispose();
      pipeline.started.close();
    });

    session.open(0);
    session.requestCurrent();
    await pipeline.started.stream.firstWhere((page) => page == 0);
    session.setCurrentPage(1);
    session.setCurrentPage(2);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    pipeline.firstPageGate!.complete();
    await pipeline.started.stream.firstWhere((page) => page == 2);

    expect(pipeline.calls, [0, 2]);
    expect(session.controllerFor(1).stage, MangaOcrStage.idle);
  });

  test('关闭面板后切页不会自动处理', () async {
    final pipeline = _FakePipeline();
    final session = MangaOcrReadingSession(
      pipeline: pipeline,
      resolvePagePath: (page) async => '/tmp/page-$page.jpg',
      resolveTargetLanguage: () => 'zh-CN',
      pageSettleDuration: const Duration(milliseconds: 10),
    );
    addTearDown(() {
      session.dispose();
      pipeline.started.close();
    });

    session.open(0);
    session.requestCurrent();
    await pipeline.started.stream.first;
    await Future<void>.delayed(Duration.zero);
    session.close();
    session.setCurrentPage(1);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(pipeline.calls, [0]);
    expect(session.hasStarted, isFalse);
  });

  testWidgets('面板未确认时显示开始按钮', (tester) async {
    final pipeline = _FakePipeline();
    final controller = MangaOcrController(pipeline);
    var started = false;
    addTearDown(() {
      controller.dispose();
      pipeline.started.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 420,
          child: MangaOcrSidePanel(
            controller: controller,
            recognitionStarted: false,
            onStart: () => started = true,
            onClose: () {},
            onRetryTranslation: () {},
            onForceOcr: () {},
          ),
        ),
      ),
    );

    expect(find.text('开始识别并翻译'), findsOneWidget);
    await tester.tap(find.text('开始识别并翻译'));
    expect(started, isTrue);
  });
}
