import 'dart:convert';

import 'package:pixez/ai/ai_client.dart';
import 'package:pixez/ai/bangumi_tag_lookup.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/ai/ai_result_cache.dart';
import 'package:pixez/ai/ai_settings_store.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/ai/html_tag_protector.dart';
import 'package:pixez/manga_ocr/manga_translation_segments.dart';

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
  final AiResultCache cache;
  final BangumiLookupService bangumiLookup;
  final Map<int, IllustTranslation> _illustTranslations = {};
  final Map<String, Future<String>> _inFlightCachedTranslations = {};

  AiTranslationService({
    required this.settings,
    required this.client,
    AiResultCache? cache,
    BangumiLookupService? bangumiLookup,
  }) : cache = cache ?? AiResultCache(),
       bangumiLookup = bangumiLookup ?? BangumiApiLookupService();

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
    final protection = HtmlTagProtection.protect(
      html,
      preserveLineBreaks: true,
    );
    final translated = await translate(
      AiPromptScenes.illustCaption,
      {'text': protection.protectedText},
      systemSuffix:
          '\n\n输入中形如 ⟪PXEZ_HTML_TAG_0000⟫ 的文本是不可变 HTML 标签或换行分隔符占位符。必须让每个占位符恰好出现一次、字符完全一致且顺序不变；只翻译占位符之外的可见文本。不要输出 Markdown 代码块。',
    );
    final restored = protection.restore(_stripCodeFence(translated));
    final current = _illustTranslations[illustId] ?? const IllustTranslation();
    _illustTranslations[illustId] = current.copyWith(caption: restored);
    return restored;
  }

  Future<String> translateTag({
    required String tagName,
    required String officialTranslation,
  }) async {
    final normalizedTagName = tagName.trim();
    final normalizedOfficialTranslation = officialTranslation.trim();
    final variables = {
      'tag_name': normalizedTagName,
      'official_translation':
          normalizedOfficialTranslation.isEmpty
              ? '（无）'
              : normalizedOfficialTranslation,
    };

    final triageResponse = await translate(
      AiPromptScenes.tagTranslationTriage,
      variables,
    );
    final decision = _parseTagTranslationDecision(triageResponse);
    final fallback = _tagTranslationFallback(
      decision,
      normalizedOfficialTranslation,
      normalizedTagName,
    );

    switch (decision.action) {
      case AiTagTranslationAction.directTranslate:
      case AiTagTranslationAction.keepOriginal:
        return fallback;
      case AiTagTranslationAction.lookupSubject:
      case AiTagTranslationAction.lookupCharacter:
        break;
    }

    final queries = _buildBangumiQueries(
      tagName: normalizedTagName,
      officialTranslation: normalizedOfficialTranslation,
      decision: decision,
    );
    if (queries.isEmpty) return fallback;

    final lookupType =
        decision.action == AiTagTranslationAction.lookupCharacter
            ? BangumiLookupType.character
            : BangumiLookupType.subject;
    try {
      final lookup = await bangumiLookup.lookup(
        type: lookupType,
        queries: queries,
      );
      if (!lookup.hasCandidates) return fallback;

      final finalResponse = await translate(
        AiPromptScenes.tagTranslation,
        variables,
        systemSuffix: _bangumiTranslationContext(
          decision: decision,
          queries: queries,
          lookup: lookup,
          fallback: fallback,
        ),
      );
      final translated = _stripCodeFence(finalResponse).trim();
      return translated.isEmpty ? fallback : translated;
    } catch (_) {
      return fallback;
    }
  }

  AiTagTranslationDecision _parseTagTranslationDecision(String response) {
    final cleaned = _stripCodeFence(response);
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const AiRequestException('AI 标签初判结果不是有效 JSON');
    }
    try {
      final decoded = jsonDecode(cleaned.substring(start, end + 1));
      if (decoded is! Map) {
        throw const FormatException('根节点不是对象');
      }
      return AiTagTranslationDecision.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } on AiRequestException {
      rethrow;
    } on Object catch (error) {
      throw AiRequestException('AI 标签初判结果无效：$error');
    }
  }

  String _tagTranslationFallback(
    AiTagTranslationDecision decision,
    String officialTranslation,
    String tagName,
  ) {
    if (decision.translation.isNotEmpty) return decision.translation;
    if (officialTranslation.isNotEmpty) return officialTranslation;
    return tagName;
  }

  List<String> _buildBangumiQueries({
    required String tagName,
    required String officialTranslation,
    required AiTagTranslationDecision decision,
  }) {
    final queries = <String>[];
    void add(String value) {
      final query = value.trim();
      if (query.isEmpty || queries.contains(query) || queries.length == 3) {
        return;
      }
      queries.add(query);
    }

    add(tagName);
    for (final query in decision.queries) {
      add(query);
    }
    add(officialTranslation);
    return queries;
  }

  String _bangumiTranslationContext({
    required AiTagTranslationDecision decision,
    required List<String> queries,
    required BangumiLookupResult lookup,
    required String fallback,
  }) =>
      '\n\n'
      '这是 Bangumi 查询得到的参考资料，不代表一定匹配。\n'
      '第一次 AI 判断：${decision.action.value}\n'
      '第一次 AI 初译：$fallback\n'
      '实际查询词：${queries.join('、')}\n'
      'Bangumi 候选：\n${lookup.toPromptText()}\n\n'
      '请综合原始标签、Pixiv 官方翻译和全部候选；只有明确匹配时才采用 Bangumi 名称。候选冲突或无法确认时使用第一次 AI 初译。只输出一个最终中文标签译名，不要解释。';

  Future<String> translateComment({
    required String resourceKey,
    required String text,
    bool forceRefresh = false,
  }) => translateCached(
    sceneId: AiPromptScenes.commentTranslation,
    resourceKey: resourceKey,
    sourceText: text,
    variables: {'text': text},
    forceRefresh: forceRefresh,
  );

  Future<String> translateAuthorIntroduction({
    required int userId,
    required String html,
    bool forceRefresh = false,
  }) async {
    final protection = HtmlTagProtection.protect(html);
    final translated = await translateCached(
      sceneId: AiPromptScenes.authorIntroductionTranslation,
      resourceKey: 'user:$userId:introduction',
      sourceText: protection.protectedText,
      variables: {'text': protection.protectedText},
      systemSuffix:
          '\n\n输入中形如 ⟪PXEZ_HTML_TAG_0000⟫ 的文本是不可变 HTML 标签占位符。必须让每个占位符恰好出现一次、字符完全一致且顺序不变；只翻译占位符之外的可见文本。不要输出 Markdown 代码块。',
      forceRefresh: forceRefresh,
    );
    return protection.restore(_stripCodeFence(translated));
  }

  Future<String?> cachedAuthorIntroduction({
    required int userId,
    required String html,
  }) async {
    final protection = HtmlTagProtection.protect(html);
    final cached = await _readCachedResult(
      sceneId: AiPromptScenes.authorIntroductionTranslation,
      resourceKey: 'user:$userId:introduction',
      sourceText: protection.protectedText,
    );
    return cached == null ? null : protection.restore(_stripCodeFence(cached));
  }

  Future<void> ensureSceneReady(String sceneId) async {
    if (!settings.initialized) await settings.init();
    settings.requireActivePrompt(sceneId);
  }

  Future<String> translateNovelPart({
    required int novelId,
    required String partKey,
    required String contentType,
    required String targetLanguage,
    required String sourceText,
    bool preserveHtml = false,
  }) async {
    final resourceKey = 'novel:$novelId:$targetLanguage:$partKey';
    if (!preserveHtml) {
      return translateCached(
        sceneId: AiPromptScenes.novelTranslation,
        resourceKey: resourceKey,
        sourceText: sourceText,
        variables: {
          'text': sourceText,
          'content_type': contentType,
          'target_language': targetLanguage,
        },
      );
    }

    final protection = HtmlTagProtection.protect(sourceText);
    final translated = await translateCached(
      sceneId: AiPromptScenes.novelTranslation,
      resourceKey: resourceKey,
      sourceText: sourceText,
      variables: {
        'text': protection.protectedText,
        'content_type': contentType,
        'target_language': targetLanguage,
      },
      systemSuffix:
          '\n\n输入中形如 ⟪PXEZ_HTML_TAG_0000⟫ 的文本是不可变 HTML 标签占位符。必须让每个占位符恰好出现一次、字符完全一致且顺序不变；只翻译占位符之外的可见文本。不要输出 Markdown 代码块。',
    );
    return protection.restore(_stripCodeFence(translated));
  }

  Future<List<String>> translateNovelBodyBatch({
    required int novelId,
    required String batchKey,
    required String targetLanguage,
    required List<String> sourceTexts,
  }) async {
    final markers = List.generate(
      sourceTexts.length,
      (index) => '⟪PXEZ_NOVEL_SEGMENT_${index.toString().padLeft(4, '0')}⟫',
    );
    final sourceText = List.generate(
      sourceTexts.length,
      (index) => '${markers[index]}${sourceTexts[index]}',
    ).join('\n');
    final translated = await translateCached(
      sceneId: AiPromptScenes.novelTranslation,
      resourceKey: 'novel:$novelId:$targetLanguage:body-batch:$batchKey',
      sourceText: sourceText,
      variables: {
        'text': sourceText,
        'content_type': '小说正文',
        'target_language': targetLanguage,
      },
      systemSuffix:
          '\n\n输入由形如 ⟪PXEZ_NOVEL_SEGMENT_0000⟫ 的不可变分段标记和正文构成。每个标记必须恰好保留一次，字符和顺序完全不变；每个标记后的内容只翻译对应的一行正文。不要合并、删除、添加或移动标记，不要输出 Markdown 代码块或解释。',
    );
    return _restoreNovelBatch(_stripCodeFence(translated), markers);
  }

  /// 批量翻译漫画整页文字。每个块使用稳定 ID 标记；模型漏掉的块会单独补译。
  Future<Map<String, String>> translateMangaPage({
    required String imageSha256,
    required int pageIndex,
    required String targetLanguage,
    required Map<String, String> blocks,
    bool forceRefresh = false,
  }) async {
    if (blocks.isEmpty) return const {};
    final batch = MangaTranslationBatch.fromBlocks(blocks);
    final sourceText = batch.sourceText;
    final translated = await translateCached(
      sceneId: AiPromptScenes.mangaPageTranslation,
      resourceKey: 'manga:$imageSha256:$pageIndex:$targetLanguage:page-batch',
      sourceText: sourceText,
      variables: {'text': sourceText, 'target_language': targetLanguage},
      systemSuffix:
          '\n\n形如 ⟪PXEZ_MANGA_BLOCK_ID⟫ 的文本是不可变分段标记。每个标记必须恰好保留一次、字符完全一致且顺序不变；只翻译标记后的对应文字。不要输出 Markdown 代码块或解释。',
      forceRefresh: forceRefresh,
    );
    final result = batch.restore(_stripCodeFence(translated));
    for (final entry in blocks.entries) {
      if ((result[entry.key] ?? '').trim().isNotEmpty) continue;
      result[entry.key] = await translateCached(
        sceneId: AiPromptScenes.mangaPageTranslation,
        resourceKey:
            'manga:$imageSha256:$pageIndex:$targetLanguage:block:${entry.key}',
        sourceText: entry.value,
        variables: {'text': entry.value, 'target_language': targetLanguage},
        forceRefresh: forceRefresh,
      );
    }
    return result;
  }

  /// 读取已完成的小说片段翻译，不会发起新的 AI 请求。
  Future<String?> cachedNovelPart({
    required int novelId,
    required String partKey,
    required String targetLanguage,
    required String sourceText,
    bool preserveHtml = false,
  }) async {
    final cacheSource =
        preserveHtml
            ? HtmlTagProtection.protect(sourceText).protectedText
            : sourceText;
    final cached = await _readCachedResult(
      sceneId: AiPromptScenes.novelTranslation,
      resourceKey: 'novel:$novelId:$targetLanguage:$partKey',
      sourceText: cacheSource,
    );
    if (cached == null || !preserveHtml) return cached;
    return HtmlTagProtection.protect(
      sourceText,
    ).restore(_stripCodeFence(cached));
  }

  /// 读取已完成的一批正文翻译，不会发起新的 AI 请求。
  Future<List<String>?> cachedNovelBodyBatch({
    required int novelId,
    required String batchKey,
    required String targetLanguage,
    required List<String> sourceTexts,
  }) async {
    final markers = List.generate(
      sourceTexts.length,
      (index) => '⟪PXEZ_NOVEL_SEGMENT_${index.toString().padLeft(4, '0')}⟫',
    );
    final sourceText = List.generate(
      sourceTexts.length,
      (index) => '${markers[index]}${sourceTexts[index]}',
    ).join('\n');
    final cached = await _readCachedResult(
      sceneId: AiPromptScenes.novelTranslation,
      resourceKey: 'novel:$novelId:$targetLanguage:body-batch:$batchKey',
      sourceText: sourceText,
    );
    if (cached == null) return null;
    return _restoreNovelBatch(_stripCodeFence(cached), markers);
  }

  Future<String?> cachedComment({
    required String resourceKey,
    required String text,
  }) => _readCachedResult(
    sceneId: AiPromptScenes.commentTranslation,
    resourceKey: resourceKey,
    sourceText: text,
  );

  Future<String> translateCached({
    required String sceneId,
    required String resourceKey,
    required String sourceText,
    required Map<String, String> variables,
    String systemSuffix = '',
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _readCachedResult(
        sceneId: sceneId,
        resourceKey: resourceKey,
        sourceText: sourceText,
      );
      if (cached != null) return cached;
    }

    final inFlightKey =
        '$sceneId|$resourceKey|${AiResultCache.hashSource(sourceText)}';
    final inFlight = _inFlightCachedTranslations[inFlightKey];
    if (inFlight != null) return inFlight;

    late final Future<String> request;
    request = _completeAndCache(
      sceneId: sceneId,
      resourceKey: resourceKey,
      sourceText: sourceText,
      variables: variables,
      systemSuffix: systemSuffix,
    ).whenComplete(() {
      if (identical(_inFlightCachedTranslations[inFlightKey], request)) {
        _inFlightCachedTranslations.remove(inFlightKey);
      }
    });
    _inFlightCachedTranslations[inFlightKey] = request;
    return request;
  }

  Future<String> _completeAndCache({
    required String sceneId,
    required String resourceKey,
    required String sourceText,
    required Map<String, String> variables,
    required String systemSuffix,
  }) async {
    if (!settings.initialized) await settings.init();
    final resolved = settings.requireActivePrompt(sceneId);
    final result = await _complete(
      provider: resolved.provider,
      prompt: resolved.prompt,
      variables: variables,
      systemSuffix: systemSuffix,
    );
    try {
      await cache.put(
        sceneId: sceneId,
        resourceKey: resourceKey,
        sourceText: sourceText,
        resultText: result,
        metadata: {
          'prompt_id': resolved.prompt.id,
          'provider_id': resolved.provider.id,
          'model': resolved.provider.model,
        },
      );
    } catch (error, stackTrace) {
      Log.w('保存 AI 结果缓存失败', error: error, stackTrace: stackTrace);
    }
    return result;
  }

  Future<String?> _readCachedResult({
    required String sceneId,
    required String resourceKey,
    required String sourceText,
  }) async {
    try {
      final cached = await cache.get(
        sceneId: sceneId,
        resourceKey: resourceKey,
        sourceText: sourceText,
      );
      return cached?.resultText;
    } catch (error, stackTrace) {
      Log.w('读取 AI 结果缓存失败', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  Future<String> translate(
    String sceneId,
    Map<String, String> variables, {
    String systemSuffix = '',
  }) async {
    if (!settings.initialized) await settings.init();
    final resolved = settings.requireActivePrompt(sceneId);
    return _complete(
      provider: resolved.provider,
      prompt: resolved.prompt,
      variables: variables,
      systemSuffix: systemSuffix,
    );
  }

  Future<String> _complete({
    required AiProviderConfig provider,
    required AiPromptPreset prompt,
    required Map<String, String> variables,
    required String systemSuffix,
  }) => client.complete(
    provider,
    AiCompletionInput(
      systemPrompt:
          AiTemplateRenderer.render(prompt.systemPrompt, variables) +
          systemSuffix,
      userPrompt: AiTemplateRenderer.render(prompt.userTemplate, variables),
    ),
  );

  String _stripCodeFence(String value) {
    final trimmed = value.trim();
    final match = RegExp(
      r'^```(?:html)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    return match?.group(1) ?? trimmed;
  }

  List<String> _restoreNovelBatch(String translated, List<String> markers) {
    final found =
        RegExp(
          r'⟪PXEZ_NOVEL_SEGMENT_\d{4}⟫',
        ).allMatches(translated).map((match) => match.group(0)!).toList();
    if (found.length != markers.length ||
        !List.generate(
          markers.length,
          (index) => index,
        ).every((index) => found[index] == markers[index])) {
      throw const AiRequestException('AI 未能完整保留正文分段标记，请重新翻译');
    }
    final result = <String>[];
    for (var index = 0; index < markers.length; index++) {
      final start = translated.indexOf(markers[index]) + markers[index].length;
      final end =
          index == markers.length - 1
              ? translated.length
              : translated.indexOf(markers[index + 1]);
      result.add(translated.substring(start, end).trim());
    }
    return result;
  }
}
