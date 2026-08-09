import 'package:pixez/ai/ai_client.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/ai/ai_settings_store.dart';
import 'package:pixez/ai/html_tag_protector.dart';

class IllustTranslation {
  final String title;
  final String caption;

  const IllustTranslation({this.title = '', this.caption = ''});

  IllustTranslation copyWith({String? title, String? caption}) =>
      IllustTranslation(
        title: title ?? this.title,
        caption: caption ?? this.caption,
      );
}

class AiTranslationService {
  final AiSettingsStore settings;
  final AiClient client;
  final Map<int, IllustTranslation> _illustTranslations = {};

  AiTranslationService({required this.settings, required this.client});

  IllustTranslation? cachedIllustTranslation(int illustId) =>
      _illustTranslations[illustId];

  void hydrateIllustTranslation(
    int illustId, {
    String title = '',
    String caption = '',
  }) {
    final current = _illustTranslations[illustId] ?? const IllustTranslation();
    _illustTranslations[illustId] = current.copyWith(
      title: current.title.isNotEmpty ? current.title : title,
      caption: current.caption.isNotEmpty ? current.caption : caption,
    );
  }

  void clearIllustTitle(int illustId) {
    final current = _illustTranslations[illustId] ?? const IllustTranslation();
    _illustTranslations[illustId] = current.copyWith(title: '');
  }

  void clearIllustCaption(int illustId) {
    final current = _illustTranslations[illustId] ?? const IllustTranslation();
    _illustTranslations[illustId] = current.copyWith(caption: '');
  }

  Future<String> translateIllustTitle(int illustId, String title) async {
    final translated = await translate(AiPromptScenes.illustTitle, {
      'text': title,
    });
    final current = _illustTranslations[illustId] ?? const IllustTranslation();
    _illustTranslations[illustId] = current.copyWith(title: translated);
    return translated;
  }

  Future<String> translateIllustCaption(int illustId, String html) async {
    final protection = HtmlTagProtection.protect(html);
    final translated = await translate(
      AiPromptScenes.illustCaption,
      {'text': protection.protectedText},
      systemSuffix:
          '\n\n输入中形如 ⟪PXEZ_HTML_TAG_0000⟫ 的文本是不可变 HTML 标签占位符。必须让每个占位符恰好出现一次、字符完全一致且顺序不变；只翻译占位符之外的可见文本。不要输出 Markdown 代码块。',
    );
    final restored = protection.restore(_stripCodeFence(translated));
    final current = _illustTranslations[illustId] ?? const IllustTranslation();
    _illustTranslations[illustId] = current.copyWith(caption: restored);
    return restored;
  }

  Future<String> translateTag({
    required String tagName,
    required String officialTranslation,
  }) => translate(AiPromptScenes.tagTranslation, {
    'tag_name': tagName,
    'official_translation':
        officialTranslation.isEmpty ? '（无）' : officialTranslation,
  });

  Future<String> translate(
    String sceneId,
    Map<String, String> variables, {
    String systemSuffix = '',
  }) async {
    if (!settings.initialized) await settings.init();
    final resolved = settings.requireActivePrompt(sceneId);
    return client.complete(
      resolved.provider,
      AiCompletionInput(
        systemPrompt:
            AiTemplateRenderer.render(resolved.prompt.systemPrompt, variables) +
            systemSuffix,
        userPrompt: AiTemplateRenderer.render(
          resolved.prompt.userTemplate,
          variables,
        ),
      ),
    );
  }

  String _stripCodeFence(String value) {
    final trimmed = value.trim();
    final match = RegExp(
      r'^```(?:html)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    return match?.group(1) ?? trimmed;
  }
}
