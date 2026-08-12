import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/ai/ai_client.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/ai/ai_result_cache.dart';
import 'package:pixez/ai/ai_settings_store.dart';
import 'package:pixez/ai/ai_translation_error_handler.dart';
import 'package:pixez/ai/ai_translation_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('作者简介翻译保留 HTML 标签并缓存结果', () async {
    final adapter = _AuthorIntroductionAdapter(
      '⟪PXEZ_HTML_TAG_0000⟫你好⟪PXEZ_HTML_TAG_0001⟫',
    );
    final service = AiTranslationService(
      settings: _AuthorIntroductionSettings(),
      client: AiClient(adapters: [adapter]),
      cache: AiResultCache(databasePath: inMemoryDatabasePath),
    );
    addTearDown(service.cache.close);

    const source = '<a href="https://example.com">hello</a>';
    expect(
      await service.translateAuthorIntroduction(userId: 42, html: source),
      '<a href="https://example.com">你好</a>',
    );
    expect(
      await service.cachedAuthorIntroduction(userId: 42, html: source),
      '<a href="https://example.com">你好</a>',
    );
    expect(adapter.requestCount, 1);
  });

  test('AI 配置错误会使用统一的设置引导', () {
    expect(
      isAiTranslationConfigurationError(
        const AiConfigurationException('该场景没有启用的 AI 提示词'),
      ),
      isTrue,
    );
    expect(isAiTranslationConfigurationError(Exception('网络错误')), isFalse);
  });
}

class _AuthorIntroductionSettings extends AiSettingsStore {
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
    sceneId: AiPromptScenes.authorIntroductionTranslation,
    providerId: 'provider',
    systemPrompt: '{{text}}',
    userTemplate: '{{text}}',
    isActive: true,
  );

  @override
  bool get initialized => true;

  @override
  ({AiProviderConfig provider, AiPromptPreset prompt}) requireActivePrompt(
    String sceneId,
  ) {
    expect(sceneId, AiPromptScenes.authorIntroductionTranslation);
    return (provider: _provider, prompt: _prompt);
  }
}

class _AuthorIntroductionAdapter implements AiProtocolAdapter {
  final String response;
  int requestCount = 0;

  _AuthorIntroductionAdapter(this.response);

  @override
  AiProtocolType get protocol => AiProtocolType.openAiChatCompletions;

  @override
  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  ) async {
    requestCount++;
    return response;
  }
}
