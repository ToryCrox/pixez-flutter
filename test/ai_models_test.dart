import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/ai/ai_client.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/ai/html_tag_protector.dart';

void main() {
  test('default prompts contain all required variables', () {
    final prompts = AiDefaultPrompts.create();
    expect(prompts, hasLength(5));
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
}
