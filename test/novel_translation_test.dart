import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pixez/ai/ai_client.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/ai/ai_result_cache.dart';
import 'package:pixez/ai/ai_settings_store.dart';
import 'package:pixez/ai/ai_translation_service.dart';
import 'package:pixez/models/novel_web_response.dart';
import 'package:pixez/page/novel/viewer/image_text.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );
  });

  group('NovelSpansGenerator content blocks', () {
    test('merges short paragraphs and keeps chapter and page boundaries', () {
      final response = _response(
        '一。\n\n二。\n\n三。\n\n[chapter:下一章]\n短句。\n\n[newpage]\n尾段。',
      );
      final blocks = NovelSpansGenerator().buildContentBlocks(response);

      expect(blocks.where((block) => block.isTranslatable), hasLength(6));
      expect(blocks.first.translationSource, '一。');
      expect(
        blocks.any(
          (block) =>
              block.spans.any((span) => span.type == NovelSpansType.chapter),
        ),
        isTrue,
      );
      expect(
        blocks.any(
          (block) =>
              block.spans.any((span) => span.type == NovelSpansType.newPage),
        ),
        isTrue,
      );
    });

    test('splits a long paragraph without exceeding the request limit', () {
      final response = _response('${'甲。' * 650}');
      final blocks = NovelSpansGenerator().buildContentBlocks(response);

      expect(blocks, isNotEmpty);
      expect(
        blocks.where((block) => block.isTranslatable),
        everyElement(
          predicate<NovelContentBlock>(
            (block) => block.translationSource.length <= 1200,
          ),
        ),
      );
    });

    test('keeps Pixiv links as renderable text inside a text block', () {
      final response = _response(
        '请查看 [[jumpuri:链接 ＞ https://www.pixiv.net/novel/show.php?id=1]]。',
      );
      final blocks = NovelSpansGenerator().buildContentBlocks(response);

      expect(blocks.single.isTranslatable, isTrue);
      expect(
        blocks.single.translationSource,
        contains('https://www.pixiv.net'),
      );
      expect(
        blocks.single.spans.any((span) => span.type == NovelSpansType.jumpUri),
        isTrue,
      );
    });

    test('keeps embedded images as non-translatable hard boundaries', () {
      final response = _response(
        '[uploadedimage:image-1]\n[pixivimage:123-0]',
        images: {
          'image-1': NovelImage(
            novelImageId: 'image-1',
            sl: '',
            urls: NovelUrls(
              the240Mw: null,
              the480Mw: null,
              the1200X1200: null,
              the128X128: null,
              original: 'https://example.com/image.jpg',
            ),
          ),
        },
        illusts: {
          '123-0': NovelIllusts(
            illust: NovelIllust(
              images: NovelIllustImages(
                small: null,
                medium: 'https://example.com/illust.jpg',
                original: null,
              ),
            ),
          ),
        },
      );
      final blocks = NovelSpansGenerator().buildContentBlocks(response);

      expect(
        blocks.any(
          (block) => block.spans.any(
            (span) => span.type == NovelSpansType.uploadedImage,
          ),
        ),
        isTrue,
      );
      expect(
        blocks.any(
          (block) =>
              block.spans.any((span) => span.type == NovelSpansType.pixivImage),
        ),
        isTrue,
      );
      expect(
        blocks
            .where(
              (block) => block.spans.any(
                (span) =>
                    span.type == NovelSpansType.uploadedImage ||
                    span.type == NovelSpansType.pixivImage,
              ),
            )
            .every((block) => !block.isTranslatable),
        isTrue,
      );
    });
  });

  test(
    'novel translations deduplicate concurrent identical requests',
    () async {
      final adapter = _CountingAdapter();
      final service = AiTranslationService(
        settings: _FakeSettings(),
        client: AiClient(adapters: [adapter]),
        cache: AiResultCache(databasePath: inMemoryDatabasePath),
      );
      addTearDown(service.cache.close);

      final first = service.translateNovelPart(
        novelId: 1,
        partKey: 'body:block-0',
        contentType: '小说正文',
        targetLanguage: 'zh-CN',
        sourceText: 'こんにちは',
      );
      final second = service.translateNovelPart(
        novelId: 1,
        partKey: 'body:block-0',
        contentType: '小说正文',
        targetLanguage: 'zh-CN',
        sourceText: 'こんにちは',
      );
      adapter.completeRequest('你好');

      expect(await first, '你好');
      expect(await second, '你好');
      expect(adapter.requestCount, 1);
    },
  );

  test('novel body batch restores one translation per source line', () async {
    final adapter = _CountingAdapter();
    final service = AiTranslationService(
      settings: _FakeSettings(),
      client: AiClient(adapters: [adapter]),
      cache: AiResultCache(databasePath: inMemoryDatabasePath),
    );
    addTearDown(service.cache.close);

    final request = service.translateNovelBodyBatch(
      novelId: 1,
      batchKey: 'block-0-block-1',
      targetLanguage: 'zh-CN',
      sourceTexts: const ['第一行', '第二行'],
    );
    adapter.completeRequest(
      '⟪PXEZ_NOVEL_SEGMENT_0000⟫Line one\n'
      '⟪PXEZ_NOVEL_SEGMENT_0001⟫Line two',
    );

    expect(await request, ['Line one', 'Line two']);
    expect(adapter.requestCount, 1);
  });
}

NovelWebResponse _response(
  String text, {
  Map<String, NovelImage>? images,
  Map<String, NovelIllusts?>? illusts,
}) => NovelWebResponse(
  id: '1',
  title: '',
  seriesId: null,
  seriesTitle: null,
  seriesIsWatched: null,
  userId: '1',
  coverUrl: '',
  tags: const [],
  caption: '',
  cdate: '',
  rating: NovelRating(like: 0, bookmark: 0, view: 0),
  text: text,
  marker: null,
  illusts: illusts,
  images: images,
  seriesNavigation: null,
  glossaryItems: null,
  replaceableItemIds: null,
  aiType: null,
  isOriginal: null,
);

class _FakeSettings extends AiSettingsStore {
  static const _provider = AiProviderConfig(
    id: 'provider',
    name: 'test',
    protocol: AiProtocolType.openAiChatCompletions,
    baseUrl: 'https://example.com/v1',
    apiKey: '',
    model: 'test',
  );
  static const _prompt = AiPromptPreset(
    id: 'prompt',
    name: 'test',
    sceneId: AiPromptScenes.novelTranslation,
    providerId: 'provider',
    systemPrompt: '{{content_type}} {{target_language}}',
    userTemplate: '{{text}}',
    isActive: true,
  );

  @override
  bool get initialized => true;

  @override
  ({AiProviderConfig provider, AiPromptPreset prompt}) requireActivePrompt(
    String sceneId,
  ) {
    expect(sceneId, AiPromptScenes.novelTranslation);
    return (provider: _provider, prompt: _prompt);
  }
}

class _CountingAdapter implements AiProtocolAdapter {
  final completer = Completer<String>();
  int requestCount = 0;

  @override
  AiProtocolType get protocol => AiProtocolType.openAiChatCompletions;

  @override
  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  ) {
    requestCount++;
    return completer.future;
  }

  void completeRequest(String value) => completer.complete(value);
}
