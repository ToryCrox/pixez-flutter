import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/ai/ai_client.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/ai/html_tag_protector.dart';

void main() {
  test('default prompts contain all required variables', () {
    final prompts = AiDefaultPrompts.create();
    expect(prompts, hasLength(AiPromptScenes.labels.length));
    for (final prompt in prompts) {
      expect(AiTemplateRenderer.validate(prompt), isNull);
    }
  });

  test('template validation rejects unknown and missing variables', () {
    final prompt = AiDefaultPrompts.create().first.copyWith(
      userTemplate: 'translate {{unknown}}',
    );
    expect(AiTemplateRenderer.validate(prompt), contains('未知变量'));
  });

  test('HTML tag protection restores exact original tags', () {
    const html = '<p>Hello <a href="https://example.com">world</a><br>!</p>';
    final protection = HtmlTagProtection.protect(html);
    final translated = protection.protectedText
        .replaceAll('Hello', '你好')
        .replaceAll('world', '世界');
    expect(
      protection.restore(translated),
      '<p>你好 <a href="https://example.com">世界</a><br>!</p>',
    );
  });

  test('HTML tag protection rejects reordered tokens', () {
    final protection = HtmlTagProtection.protect('<b>a</b>');
    final tokens =
        RegExp(r'⟪PXEZ_HTML_TAG_\d{4}⟫')
            .allMatches(protection.protectedText)
            .map((match) => match.group(0)!)
            .toList();
    expect(
      () => protection.restore('${tokens.last}a${tokens.first}'),
      throwsA(isA<AiRequestException>()),
    );
  });

  test('endpoint accepts a full endpoint and trims trailing slash', () {
    expect(
      AiClient.endpoint('https://api.openai.com/v1/', 'responses'),
      'https://api.openai.com/v1/responses',
    );
    expect(
      AiClient.endpoint('https://api.openai.com/v1/responses', 'responses'),
      'https://api.openai.com/v1/responses',
    );
  });

  test(
    'provider retry setting defaults to three and survives serialization',
    () {
      final legacy = AiProviderConfig.fromJson(const {
        'id': 'legacy',
        'name': 'Legacy',
        'base_url': 'https://example.com/v1',
        'model': 'model',
      });
      expect(legacy.maxRetries, 3);
      expect(legacy.copyWith(maxRetries: 5).toJson()['max_retries'], 5);
    },
  );

  test('AI client retries transient errors with exponential backoff', () async {
    final adapter = _FlakyAdapter(failures: 3, statusCode: 503);
    final delays = <Duration>[];
    final client = AiClient(
      adapters: [adapter],
      retryDelay: (duration) async => delays.add(duration),
      retryLogger: (_) {},
    );

    final result = await client.complete(
      _provider,
      const AiCompletionInput(systemPrompt: 'system', userPrompt: 'user'),
    );

    expect(result, 'OK');
    expect(adapter.calls, 4);
    expect(delays, const [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
    ]);
  });

  test('AI client does not retry non-transient HTTP errors', () async {
    final adapter = _FlakyAdapter(failures: 1, statusCode: 400);
    final client = AiClient(
      adapters: [adapter],
      retryDelay: (_) async {},
      retryLogger: (_) {},
    );

    await expectLater(
      client.complete(
        _provider,
        const AiCompletionInput(systemPrompt: 'system', userPrompt: 'user'),
      ),
      throwsA(isA<AiRequestException>()),
    );
    expect(adapter.calls, 1);
  });
}

const _provider = AiProviderConfig(
  id: 'provider',
  name: 'Provider',
  protocol: AiProtocolType.openAiChatCompletions,
  baseUrl: 'https://example.com/v1',
  apiKey: '',
  model: 'model',
  maxRetries: 3,
);

class _FlakyAdapter implements AiProtocolAdapter {
  final int failures;
  final int statusCode;
  int calls = 0;

  _FlakyAdapter({required this.failures, required this.statusCode});

  @override
  AiProtocolType get protocol => AiProtocolType.openAiChatCompletions;

  @override
  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  ) async {
    calls++;
    if (calls <= failures) {
      final request = RequestOptions(path: config.baseUrl);
      throw DioException(
        requestOptions: request,
        response: Response<void>(
          requestOptions: request,
          statusCode: statusCode,
        ),
        type: DioExceptionType.badResponse,
      );
    }
    return 'OK';
  }
}
