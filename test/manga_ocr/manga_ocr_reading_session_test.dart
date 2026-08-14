import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final translationStarted = StreamController<int>.broadcast();
  Completer<void>? firstPageGate;
  Completer<void>? translationGate;

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

  @override
  Future<MangaPageOcrResult> translateResult(
    MangaPageOcrResult result, {
    required String targetLanguage,
    bool forceTranslation = false,
    MangaOcrProgressCallback? onProgress,
  }) async {
    onProgress?.call(MangaOcrStage.translating, 0, 1, '正在发送 OCR 文本给 AI 翻译');
    translationStarted.add(result.pageIndex);
    if (translationGate != null) await translationGate!.future;
    onProgress?.call(MangaOcrStage.completed, 1, 1, '识别与翻译完成');
    return result;
  }
}

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

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
      pipeline.translationStarted.close();
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
      pipeline.translationStarted.close();
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

  test('下一页进入视口后等待缓存文件可读并立即提前处理', () async {
    final pipeline = _FakePipeline()..firstPageGate = Completer<void>();
    final nextPagePath = Completer<String?>();
    final session = MangaOcrReadingSession(
      pipeline: pipeline,
      resolvePagePath:
          (page) async =>
              page == 1 ? nextPagePath.future : '/tmp/page-$page.jpg',
      resolveTargetLanguage: () => 'zh-CN',
      pageSettleDuration: const Duration(seconds: 1),
    );
    addTearDown(() {
      session.dispose();
      pipeline.started.close();
      pipeline.translationStarted.close();
    });

    session.open(0);
    session.requestCurrent();
    await pipeline.started.stream.firstWhere((page) => page == 0);
    session.requestReadyVisiblePages([0, 1], forward: true);
    pipeline.firstPageGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(pipeline.calls, [0]);
    nextPagePath.complete('/tmp/page-1.jpg');
    await pipeline.started.stream.firstWhere((page) => page == 1);

    expect(session.currentPage, 0);
    expect(pipeline.calls, [0, 1]);
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
      pipeline.translationStarted.close();
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
      pipeline.translationStarted.close();
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

  testWidgets('检测框悬浮提示优先显示译文', (tester) async {
    final result = MangaPageOcrResult(
      imageSha256: 'image',
      pageIndex: 0,
      imageWidth: 100,
      imageHeight: 100,
      preprocessorId: mangaOcrPreprocessorId,
      preprocessorVersion: mangaOcrPreprocessorVersion,
      detectorId: mangaOcrDefaultDetectorId,
      detectorVersion: 'test',
      recognizerId: mangaOcrDefaultRecognizerId,
      recognizerVersion: 'test',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      blocks: const [
        MangaTextBlock(
          id: 'block',
          bounds: MangaNormalizedRect(
            left: 0.1,
            top: 0.1,
            right: 0.5,
            bottom: 0.5,
          ),
          sourceText: 'こんにちは',
          translatedText: '你好',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.square(
          dimension: 400,
          child: MangaOcrOverlay(
            result: result,
            selectedBlockId: null,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, '你好');
    expect(tooltip.waitDuration, const Duration(milliseconds: 150));
  });

  testWidgets('翻译阶段显示 AI 翻译状态而不是扫描文字', (tester) async {
    final pipeline = _FakePipeline()..translationGate = Completer<void>();
    final controller = MangaOcrController(pipeline);
    addTearDown(() {
      controller.dispose();
      pipeline.started.close();
      pipeline.translationStarted.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 420,
          child: MangaOcrSidePanel(
            controller: controller,
            onClose: () {},
            onRetryTranslation: () {},
            onForceOcr: () {},
          ),
        ),
      ),
    );

    unawaited(
      controller.analyze(
        imagePath: '/tmp/page.jpg',
        pageIndex: 0,
        targetLanguage: 'zh-CN',
      ),
    );
    await tester.pump();

    expect(find.text('正在将 OCR 文本发送给 AI 翻译…'), findsOneWidget);
    expect(find.text('正在扫描文字区域…'), findsNothing);
    pipeline.translationGate!.complete();
    await tester.pumpAndSettle();
  });

  test('AI 翻译进行时不会阻塞下一页本地 OCR', () async {
    final pipeline = _FakePipeline()..translationGate = Completer<void>();
    final session = MangaOcrReadingSession(
      pipeline: pipeline,
      resolvePagePath: (page) async => '/tmp/page-$page.jpg',
      resolveTargetLanguage: () => 'zh-CN',
    );
    addTearDown(() async {
      pipeline.translationGate!.complete();
      session.dispose();
      await pipeline.started.close();
      await pipeline.translationStarted.close();
    });

    session.open(0);
    session.requestCurrent();
    await pipeline.started.stream.firstWhere((page) => page == 0);
    await pipeline.translationStarted.stream.firstWhere((page) => page == 0);

    session.requestPage(1);
    await pipeline.started.stream.firstWhere((page) => page == 1);

    expect(pipeline.calls, [0, 1]);
    expect(session.controllerFor(0).stage, MangaOcrStage.translating);
  });
}
