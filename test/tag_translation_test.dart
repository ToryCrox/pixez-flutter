import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/ai/ai_client.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/ai/ai_result_cache.dart';
import 'package:pixez/ai/ai_settings_store.dart';
import 'package:pixez/ai/ai_translation_service.dart';
import 'package:pixez/ai/bangumi_tag_lookup.dart';
import 'package:pixez/debug/network_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('普通标签第一次初判后直接返回，不请求 Bangumi', () async {
    final adapter = _TagTranslationAdapter(
      triageResponse: _decisionJson(
        action: AiTagTranslationAction.directTranslate,
        translation: '水着',
      ),
      finalResponse: '不应调用',
    );
    final bangumi = _FakeBangumiLookup(
      const BangumiLookupResult(type: BangumiLookupType.subject, queries: []),
    );
    final service = _createService(adapter, bangumi);

    expect(
      await service.translateTag(tagName: '水着', officialTranslation: '泳装'),
      '水着',
    );
    expect(adapter.requestCount, 1);
    expect(bangumi.calls, 0);
  });

  test('作品标签使用多个查询词并把全部候选交给第二次 AI', () async {
    final adapter = _TagTranslationAdapter(
      triageResponse: _decisionJson(
        action: AiTagTranslationAction.lookupSubject,
        translation: '鸟之诗',
        queries: ['AIR', '鸟之诗'],
      ),
      finalResponse: '鸟之诗',
    );
    final bangumi = _FakeBangumiLookup(
      const BangumiLookupResult(
        type: BangumiLookupType.subject,
        queries: ['AIR', '鸟之诗'],
        subjects: [
          BangumiSubjectCandidate(
            id: 1,
            name: 'AIR',
            nameCn: '鸟之诗',
            type: 2,
            matchedQueries: ['AIR'],
          ),
          BangumiSubjectCandidate(
            id: 2,
            name: 'Air Gear',
            nameCn: '飞轮少年',
            type: 2,
            matchedQueries: ['AIR'],
          ),
        ],
      ),
    );
    final service = _createService(adapter, bangumi);

    expect(
      await service.translateTag(tagName: 'AIR', officialTranslation: '鸟之诗'),
      '鸟之诗',
    );
    expect(adapter.requestCount, 2);
    expect(bangumi.calls, 1);
    expect(bangumi.receivedQueries, ['AIR', '鸟之诗']);
    expect(adapter.systemPrompts.last, contains('Air Gear / 飞轮少年'));
    expect(adapter.systemPrompts.last, contains('AIR / 鸟之诗'));
  });

  test('角色标签包含多个角色候选及关联作品', () async {
    final adapter = _TagTranslationAdapter(
      triageResponse: _decisionJson(
        action: AiTagTranslationAction.lookupCharacter,
        translation: '神尾观铃',
        queries: ['神尾観鈴', '神尾观铃'],
      ),
      finalResponse: '神尾观铃',
    );
    final bangumi = _FakeBangumiLookup(
      const BangumiLookupResult(
        type: BangumiLookupType.character,
        queries: ['神尾観鈴', '神尾观铃'],
        characters: [
          BangumiCharacterCandidate(
            id: 10,
            name: '神尾観鈴',
            nameCn: '神尾观铃',
            matchedQueries: ['神尾観鈴'],
            subjects: [
              BangumiSubjectCandidate(
                id: 20,
                name: 'AIR',
                nameCn: '鸟之诗',
                type: 2,
                matchedQueries: [],
              ),
            ],
          ),
          BangumiCharacterCandidate(
            id: 11,
            name: '其他角色',
            nameCn: '',
            matchedQueries: ['神尾观铃'],
            subjects: [],
          ),
        ],
      ),
    );
    final service = _createService(adapter, bangumi);

    expect(
      await service.translateTag(tagName: '神尾観鈴', officialTranslation: ''),
      '神尾观铃',
    );
    expect(adapter.requestCount, 2);
    expect(adapter.systemPrompts.last, contains('角色候选'));
    expect(adapter.systemPrompts.last, contains('AIR / 鸟之诗'));
  });

  test('Bangumi 失败时回退到第一次初译', () async {
    final adapter = _TagTranslationAdapter(
      triageResponse: _decisionJson(
        action: AiTagTranslationAction.lookupSubject,
        translation: '鸟之诗',
        queries: ['AIR'],
      ),
      finalResponse: '不应调用',
    );
    final bangumi = _FakeBangumiLookup.failure();
    final service = _createService(adapter, bangumi);

    expect(
      await service.translateTag(tagName: 'AIR', officialTranslation: '鸟之诗'),
      '鸟之诗',
    );
    expect(adapter.requestCount, 1);
  });

  test('Bangumi 多次查询会合并并按 ID 去重', () async {
    final transport = _FakeBangumiTransport();
    final service = BangumiApiLookupService(
      transport: transport,
      requestDelay: Duration.zero,
    );

    final result = await service.lookup(
      type: BangumiLookupType.subject,
      queries: ['AIR', '鸟之诗', 'AIR'],
    );

    expect(transport.postPaths, hasLength(2));
    expect(result.subjects, hasLength(2));
    expect(result.subjects.first.id, 1);
    expect(result.subjects.first.matchedQueries, ['AIR', '鸟之诗']);

    await service.lookup(
      type: BangumiLookupType.subject,
      queries: ['AIR', '鸟之诗'],
    );
    expect(transport.postPaths, hasLength(2));
  });

  test('Bangumi 角色查询合并候选并读取关联作品', () async {
    final transport = _FakeCharacterBangumiTransport();
    final service = BangumiApiLookupService(
      transport: transport,
      requestDelay: Duration.zero,
    );

    final result = await service.lookup(
      type: BangumiLookupType.character,
      queries: ['神尾観鈴', '神尾观铃'],
    );

    expect(transport.characterSearchCount, 2);
    expect(transport.relatedSubjectPaths, hasLength(2));
    expect(result.characters, hasLength(2));
    expect(result.characters.first.subjects.single.nameCn, '鸟之诗');
    expect(result.toPromptText(), contains('AIR / 鸟之诗'));
  });

  test('初判 JSON 无法解析时抛出统一 AI 请求异常', () async {
    final adapter = _TagTranslationAdapter(
      triageResponse: '这不是 JSON',
      finalResponse: '',
    );
    final service = _createService(adapter, _FakeBangumiLookup.empty());

    expect(
      () => service.translateTag(tagName: '水着', officialTranslation: ''),
      throwsA(isA<AiRequestException>()),
    );
  });

  test('默认 Bangumi Dio 接入统一网络日志拦截器', () {
    final transport = DioBangumiApiTransport();

    expect(
      transport.dio.interceptors.whereType<NetworkLogInterceptor>(),
      hasLength(1),
    );
  });
}

AiTranslationService _createService(
  _TagTranslationAdapter adapter,
  BangumiLookupService bangumi,
) => AiTranslationService(
  settings: _TagTranslationSettings(),
  client: AiClient(adapters: [adapter]),
  bangumiLookup: bangumi,
  cache: AiResultCache(databasePath: inMemoryDatabasePath),
);

String _decisionJson({
  required AiTagTranslationAction action,
  required String translation,
  List<String> queries = const [],
}) =>
    '{"action":"${action.value}","translation":"$translation",'
    '"queries":${queries.map((query) => '"$query"').toList()},'
    '"confidence":0.9}';

class _TagTranslationSettings extends AiSettingsStore {
  static const provider = AiProviderConfig(
    id: 'provider',
    name: 'test',
    protocol: AiProtocolType.openAiChatCompletions,
    baseUrl: 'https://example.com/v1',
    apiKey: '',
    model: 'test',
  );

  static const triagePrompt = AiPromptPreset(
    id: 'triage',
    name: 'triage',
    sceneId: AiPromptScenes.tagTranslationTriage,
    providerId: 'provider',
    systemPrompt: 'triage',
    userTemplate: '初判：{{tag_name}}/{{official_translation}}',
    isActive: true,
  );

  static const finalPrompt = AiPromptPreset(
    id: 'final',
    name: 'final',
    sceneId: AiPromptScenes.tagTranslation,
    providerId: 'provider',
    systemPrompt: 'final',
    userTemplate: '最终：{{tag_name}}/{{official_translation}}',
    isActive: true,
  );

  @override
  bool get initialized => true;

  @override
  ({AiProviderConfig provider, AiPromptPreset prompt}) requireActivePrompt(
    String sceneId,
  ) {
    return (
      provider: provider,
      prompt:
          sceneId == AiPromptScenes.tagTranslationTriage
              ? triagePrompt
              : finalPrompt,
    );
  }
}

class _TagTranslationAdapter implements AiProtocolAdapter {
  final String triageResponse;
  final String finalResponse;
  final List<String> systemPrompts = [];
  int requestCount = 0;

  _TagTranslationAdapter({
    required this.triageResponse,
    required this.finalResponse,
  });

  @override
  AiProtocolType get protocol => AiProtocolType.openAiChatCompletions;

  @override
  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  ) async {
    requestCount++;
    systemPrompts.add(input.systemPrompt);
    return input.userPrompt.startsWith('初判：') ? triageResponse : finalResponse;
  }
}

class _FakeBangumiLookup implements BangumiLookupService {
  final BangumiLookupResult? result;
  final Object? error;
  int calls = 0;
  List<String> receivedQueries = const [];

  _FakeBangumiLookup(this.result) : error = null;

  _FakeBangumiLookup.failure()
    : result = null,
      error = const BangumiLookupException('test failure');

  _FakeBangumiLookup.empty()
    : result = const BangumiLookupResult(
        type: BangumiLookupType.subject,
        queries: [],
      ),
      error = null;

  @override
  Future<BangumiLookupResult> lookup({
    required BangumiLookupType type,
    required List<String> queries,
  }) async {
    calls++;
    receivedQueries = List.unmodifiable(queries);
    if (error != null) throw error!;
    return result!;
  }
}

class _FakeBangumiTransport implements BangumiApiTransport {
  final List<String> postPaths = [];

  @override
  Future<dynamic> post(
    String path, {
    required Map<String, dynamic> queryParameters,
    required Object data,
  }) async {
    postPaths.add(path);
    final keyword = (data as Map<String, dynamic>)['keyword'];
    if (keyword == '鸟之诗') {
      return {
        'data': [
          {'id': 1, 'name': 'AIR', 'name_cn': '鸟之诗', 'type': 2},
          {'id': 2, 'name': 'Air Gear', 'name_cn': '飞轮少年', 'type': 2},
        ],
      };
    }
    return {
      'data': [
        {'id': 1, 'name': 'AIR', 'name_cn': '鸟之诗', 'type': 2},
      ],
    };
  }

  @override
  Future<dynamic> get(String path) async => {'data': const []};
}

class _FakeCharacterBangumiTransport implements BangumiApiTransport {
  int characterSearchCount = 0;
  final List<String> relatedSubjectPaths = [];

  @override
  Future<dynamic> post(
    String path, {
    required Map<String, dynamic> queryParameters,
    required Object data,
  }) async {
    if (path != '/v0/search/characters') return {'data': const []};
    characterSearchCount++;
    final keyword = (data as Map<String, dynamic>)['keyword'];
    if (keyword == '神尾观铃') {
      return {
        'data': [
          {'id': 2, 'name': '其他角色'},
        ],
      };
    }
    return {
      'data': [
        {'id': 1, 'name': '神尾観鈴', 'name_cn': '神尾观铃'},
      ],
    };
  }

  @override
  Future<dynamic> get(String path) async {
    relatedSubjectPaths.add(path);
    if (path.endsWith('/1/subjects')) {
      return {
        'data': [
          {'id': 20, 'name': 'AIR', 'name_cn': '鸟之诗', 'type': 2},
        ],
      };
    }
    return {'data': const []};
  }
}
