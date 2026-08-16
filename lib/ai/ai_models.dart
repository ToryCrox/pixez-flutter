import 'dart:convert';

enum AiProtocolType {
  openAiChatCompletions('openai_chat_completions', 'OpenAI Chat Completions'),
  openAiResponses('openai_responses', 'OpenAI Responses');

  final String value;
  final String label;
  const AiProtocolType(this.value, this.label);

  static AiProtocolType fromValue(String? value) =>
      AiProtocolType.values.where((item) => item.value == value).firstOrNull ??
      AiProtocolType.openAiChatCompletions;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class AiProviderConfig {
  final String id;
  final String name;
  final AiProtocolType protocol;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String? reasoningEffort;
  final int maxRetries;

  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.reasoningEffort,
    this.maxRetries = 3,
  });

  AiProviderConfig copyWith({
    String? id,
    String? name,
    AiProtocolType? protocol,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? reasoningEffort,
    int? maxRetries,
    bool clearReasoningEffort = false,
  }) => AiProviderConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    protocol: protocol ?? this.protocol,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    reasoningEffort:
        clearReasoningEffort ? null : reasoningEffort ?? this.reasoningEffort,
    maxRetries: maxRetries ?? this.maxRetries,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.value,
    'base_url': baseUrl,
    'api_key': apiKey,
    'model': model,
    'reasoning_effort': reasoningEffort,
    'max_retries': maxRetries,
  };

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) =>
      AiProviderConfig(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        protocol: AiProtocolType.fromValue(json['protocol'] as String?),
        baseUrl: json['base_url'] as String? ?? '',
        apiKey: json['api_key'] as String? ?? '',
        model: json['model'] as String? ?? '',
        reasoningEffort: json['reasoning_effort'] as String?,
        maxRetries:
            ((json['max_retries'] as num?)?.toInt() ?? 3).clamp(0, 10).toInt(),
      );
}

class AiPromptPreset {
  final String id;
  final String name;
  final String sceneId;
  final String providerId;
  final bool useDefaultProvider;
  final String systemPrompt;
  final String userTemplate;
  final bool isActive;

  const AiPromptPreset({
    required this.id,
    required this.name,
    required this.sceneId,
    required this.providerId,
    this.useDefaultProvider = false,
    required this.systemPrompt,
    required this.userTemplate,
    required this.isActive,
  });

  AiPromptPreset copyWith({
    String? id,
    String? name,
    String? sceneId,
    String? providerId,
    bool? useDefaultProvider,
    String? systemPrompt,
    String? userTemplate,
    bool? isActive,
  }) => AiPromptPreset(
    id: id ?? this.id,
    name: name ?? this.name,
    sceneId: sceneId ?? this.sceneId,
    providerId: providerId ?? this.providerId,
    useDefaultProvider: useDefaultProvider ?? this.useDefaultProvider,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    userTemplate: userTemplate ?? this.userTemplate,
    isActive: isActive ?? this.isActive,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'scene_id': sceneId,
    'provider_id': providerId,
    'use_default_provider': useDefaultProvider,
    'system_prompt': systemPrompt,
    'user_template': userTemplate,
    'is_active': isActive,
  };

  factory AiPromptPreset.fromJson(Map<String, dynamic> json) => AiPromptPreset(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    sceneId: json['scene_id'] as String? ?? '',
    providerId: json['provider_id'] as String? ?? '',
    useDefaultProvider: json['use_default_provider'] as bool? ?? false,
    systemPrompt: json['system_prompt'] as String? ?? '',
    userTemplate: json['user_template'] as String? ?? '',
    isActive: json['is_active'] as bool? ?? false,
  );
}

class AiPromptScenes {
  static const illustTitle = 'illust_title';
  static const illustCaption = 'illust_caption';
  static const tagTranslation = 'tag_translation';
  static const commentTranslation = 'comment_translation';
  static const authorIntroductionTranslation =
      'author_introduction_translation';
  static const novelTranslation = 'novel_translation';
  static const mangaPageTranslation = 'manga_page_translation';

  static const labels = <String, String>{
    illustTitle: '插画标题',
    illustCaption: '插画介绍',
    tagTranslation: '标签翻译',
    commentTranslation: '用户评论翻译',
    authorIntroductionTranslation: '作者简介翻译',
    novelTranslation: '小说翻译',
    mangaPageTranslation: '漫画整页翻译',
  };

  static const requiredVariables = <String, Set<String>>{
    illustTitle: {'text'},
    illustCaption: {'text'},
    tagTranslation: {'tag_name', 'official_translation'},
    commentTranslation: {'text'},
    authorIntroductionTranslation: {'text'},
    novelTranslation: {'text', 'content_type', 'target_language'},
    mangaPageTranslation: {'text', 'target_language'},
  };
}

class AiTemplateRenderer {
  static final _variablePattern = RegExp(r'\{\{\s*([a-z_]+)\s*\}\}');

  static Set<String> variablesIn(String template) =>
      _variablePattern
          .allMatches(template)
          .map((match) => match.group(1)!)
          .toSet();

  static String? validate(AiPromptPreset preset) {
    if (!AiPromptScenes.labels.containsKey(preset.sceneId)) {
      return '不支持的提示词场景';
    }
    if (preset.name.trim().isEmpty) return '请输入提示词名称';
    if (preset.systemPrompt.trim().isEmpty) return '请输入 System 提示词';
    if (preset.userTemplate.trim().isEmpty) return '请输入 User 模板';
    final variables = variablesIn(
      '${preset.systemPrompt}\n${preset.userTemplate}',
    );
    final required = AiPromptScenes.requiredVariables[preset.sceneId]!;
    final unknown = variables.difference(required);
    if (unknown.isNotEmpty) return '存在未知变量：${unknown.join(', ')}';
    final missing = required.difference(variables);
    if (missing.isNotEmpty) return '缺少必需变量：${missing.join(', ')}';
    return null;
  }

  static String render(String template, Map<String, String> variables) {
    return template.replaceAllMapped(_variablePattern, (match) {
      final key = match.group(1)!;
      final value = variables[key];
      if (value == null) throw AiConfigurationException('提示词缺少变量：$key');
      return value;
    });
  }
}

class AiDefaultPrompts {
  static List<AiPromptPreset> create() => const [
    AiPromptPreset(
      id: 'builtin_illust_title_zh_cn',
      name: '插画标题（简体中文）',
      sceneId: AiPromptScenes.illustTitle,
      providerId: '',
      useDefaultProvider: true,
      isActive: true,
      systemPrompt:
          '你是 Pixiv 插画元数据翻译助手。请准确、自然地翻译为简体中文；保留人名、作品名、型号、颜文字、Emoji、特殊符号和原有语气。不要解释、不要加引号，只输出译文。',
      userTemplate: '请翻译以下插画标题：\n\n{{text}}',
    ),
    AiPromptPreset(
      id: 'builtin_illust_caption_zh_cn',
      name: '插画介绍（简体中文）',
      sceneId: AiPromptScenes.illustCaption,
      providerId: '',
      useDefaultProvider: true,
      isActive: true,
      systemPrompt:
          '你是 Pixiv 插画介绍翻译助手。请将可见文案准确、自然地翻译为简体中文；保留专有名词、Emoji、换行和原有语气。不要补充或删减信息，不要解释，只输出译文。',
      userTemplate: '请翻译以下插画介绍：\n\n{{text}}',
    ),
    AiPromptPreset(
      id: 'builtin_tag_translation_zh_cn',
      name: '标签翻译（简体中文）',
      sceneId: AiPromptScenes.tagTranslation,
      providerId: '',
      useDefaultProvider: true,
      isActive: true,
      systemPrompt:
          '你是 Pixiv 标签本地化助手。请结合标签原名和官方翻译，输出最常用、简洁、准确的简体中文标签。优先使用作品、角色和术语已有的官方中文名；不要解释、不要加引号，只输出一个标签译名。',
      userTemplate:
          '标签原名：{{tag_name}}\n官方翻译：{{official_translation}}\n\n请给出简体中文标签译名。',
    ),
    AiPromptPreset(
      id: 'builtin_comment_translation_zh_cn',
      name: '用户评论翻译（简体中文）',
      sceneId: AiPromptScenes.commentTranslation,
      providerId: '',
      useDefaultProvider: true,
      isActive: true,
      systemPrompt:
          '你是 Pixiv 用户评论翻译助手。请判断原文语言并将评论准确、自然地翻译为简体中文；保留用户名、作品名、角色名、网络用语、颜文字、Emoji、换行和原有语气；对于俚语、省略和口语表达，优先传达其真实含义。不要补充、删减、审查或解释内容。若原文已经是简体中文，请原样输出。不要加引号，只输出译文。',
      userTemplate: '请翻译以下用户评论：\n\n{{text}}',
    ),
    AiPromptPreset(
      id: 'builtin_author_introduction_translation_zh_cn',
      name: '作者简介翻译（简体中文）',
      sceneId: AiPromptScenes.authorIntroductionTranslation,
      providerId: '',
      useDefaultProvider: true,
      isActive: true,
      systemPrompt:
          '你是 Pixiv 作者简介翻译助手。请判断原文语言并将简介准确、自然地翻译为简体中文；保留作者名、作品名、角色名、URL、Emoji、颜文字、换行和原有语气。不要补充、删减、审查或解释内容。若原文已经是简体中文，请原样输出。不要加引号，只输出译文。',
      userTemplate: '请翻译以下作者简介：\n\n{{text}}',
    ),
    AiPromptPreset(
      id: 'builtin_novel_translation',
      name: '小说翻译（跟随应用语言）',
      sceneId: AiPromptScenes.novelTranslation,
      providerId: '',
      useDefaultProvider: true,
      isActive: true,
      systemPrompt:
          '你是 Pixiv 小说翻译助手。请将{{content_type}}准确、自然地翻译为 {{target_language}}；保留人名、作品名、术语、Emoji、颜文字、换行、URL 和原有语气。不要补充、删减、审查或解释内容，不要加引号，只输出译文。',
      userTemplate: '请翻译以下{{content_type}}：\n\n{{text}}',
    ),
    AiPromptPreset(
      id: 'builtin_manga_page_translation',
      name: '漫画整页翻译（跟随应用语言）',
      sceneId: AiPromptScenes.mangaPageTranslation,
      providerId: '',
      useDefaultProvider: true,
      isActive: true,
      systemPrompt:
          '你是漫画对白翻译助手。请结合整页上下文，将每个分段准确、自然地翻译为 {{target_language}}；保留角色名、语气、拟声词、Emoji 和标点风格。不要审查、解释、合并或移动分段。',
      userTemplate: '请翻译以下带不可变分段标记的漫画文字：\n\n{{text}}',
    ),
  ];
}

class AiSettingsDocument {
  final List<AiProviderConfig> providers;
  final List<AiPromptPreset> prompts;
  final String? defaultProviderId;

  const AiSettingsDocument({
    required this.providers,
    required this.prompts,
    this.defaultProviderId,
  });

  Map<String, dynamic> toJson() => {
    'version': 2,
    'default_provider_id': defaultProviderId,
    'providers': providers.map((item) => item.toJson()).toList(),
    'prompts': prompts.map((item) => item.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());

  factory AiSettingsDocument.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final providerJson =
        (json['providers'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>();
    final promptJson =
        (json['prompts'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>();
    return AiSettingsDocument(
      providers: providerJson.map(AiProviderConfig.fromJson).toList(),
      prompts: promptJson.map(AiPromptPreset.fromJson).toList(),
      defaultProviderId: json['default_provider_id'] as String?,
    );
  }
}

class AiConfigurationException implements Exception {
  final String message;
  const AiConfigurationException(this.message);

  @override
  String toString() => message;
}
