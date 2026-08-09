import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/er/prefer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiSettingsStore extends ChangeNotifier {
  static const _storageKey = 'ai_settings_v1';
  final Random _random = Random.secure();
  SharedPreferences? _preferences;
  bool _initialized = false;
  List<AiProviderConfig> _providers = [];
  List<AiPromptPreset> _prompts = [];

  bool get initialized => _initialized;
  List<AiProviderConfig> get providers => List.unmodifiable(_providers);
  List<AiPromptPreset> get prompts => List.unmodifiable(_prompts);

  Future<void> init() async {
    if (_initialized) return;
    _preferences = await Prefer.getInstance();
    final raw = _preferences!.getString(_storageKey);
    try {
      if (raw != null && raw.isNotEmpty) {
        final document = AiSettingsDocument.decode(raw);
        _providers = document.providers;
        _prompts = document.prompts;
      }
    } catch (_) {
      _providers = [];
      _prompts = [];
    }
    _restoreMissingDefaults(notify: false);
    _initialized = true;
    await _persist();
    notifyListeners();
  }

  AiProviderConfig? providerById(String id) {
    for (final provider in _providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  AiPromptPreset? activePrompt(String sceneId) {
    for (final prompt in _prompts) {
      if (prompt.sceneId == sceneId && prompt.isActive) return prompt;
    }
    return null;
  }

  ({AiProviderConfig provider, AiPromptPreset prompt}) requireActivePrompt(
    String sceneId,
  ) {
    final prompt = activePrompt(sceneId);
    if (prompt == null) throw const AiConfigurationException('该场景没有启用的 AI 提示词');
    if (prompt.providerId.isEmpty) {
      throw const AiConfigurationException('该提示词尚未绑定 AI 服务，请前往 AI 设置完成配置');
    }
    final provider = providerById(prompt.providerId);
    if (provider == null)
      throw const AiConfigurationException('提示词绑定的 AI 服务不存在');
    return (provider: provider, prompt: prompt);
  }

  Future<void> upsertProvider(AiProviderConfig provider) async {
    _validateProvider(provider);
    final isNew = !_providers.any((item) => item.id == provider.id);
    if (isNew) {
      _providers = [..._providers, provider];
      if (_providers.length == 1) {
        _prompts =
            _prompts
                .map(
                  (item) =>
                      item.providerId.isEmpty
                          ? item.copyWith(providerId: provider.id)
                          : item,
                )
                .toList();
      }
    } else {
      _providers =
          _providers
              .map((item) => item.id == provider.id ? provider : item)
              .toList();
    }
    await _saveAndNotify();
  }

  Future<void> deleteProvider(String providerId) async {
    if (_prompts.any((item) => item.providerId == providerId)) {
      throw const AiConfigurationException('该服务仍被提示词引用，请先重新绑定提示词');
    }
    _providers = _providers.where((item) => item.id != providerId).toList();
    await _saveAndNotify();
  }

  Future<void> upsertPrompt(AiPromptPreset prompt) async {
    final validation = AiTemplateRenderer.validate(prompt);
    if (validation != null) throw AiConfigurationException(validation);
    if (prompt.providerId.isNotEmpty &&
        providerById(prompt.providerId) == null) {
      throw const AiConfigurationException('请选择有效的 AI 服务');
    }
    var next = _prompts.where((item) => item.id != prompt.id).toList();
    if (prompt.isActive) {
      next =
          next
              .map(
                (item) =>
                    item.sceneId == prompt.sceneId
                        ? item.copyWith(isActive: false)
                        : item,
              )
              .toList();
    }
    _prompts = [...next, prompt];
    await _saveAndNotify();
  }

  Future<void> setPromptActive(String promptId) async {
    final target = _prompts.where((item) => item.id == promptId).firstOrNull;
    if (target == null) return;
    _prompts =
        _prompts
            .map(
              (item) =>
                  item.sceneId == target.sceneId
                      ? item.copyWith(isActive: item.id == target.id)
                      : item,
            )
            .toList();
    await _saveAndNotify();
  }

  Future<void> deletePrompt(String promptId) async {
    _prompts = _prompts.where((item) => item.id != promptId).toList();
    await _saveAndNotify();
  }

  Future<void> restoreDefaultPrompts() async {
    _restoreMissingDefaults(notify: true);
    await _persist();
  }

  String newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  void _restoreMissingDefaults({required bool notify}) {
    final ids = _prompts.map((item) => item.id).toSet();
    final additions = AiDefaultPrompts.create().where(
      (item) => !ids.contains(item.id),
    );
    _prompts = [..._prompts, ...additions];
    if (notify) notifyListeners();
  }

  Future<void> _saveAndNotify() async {
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    _preferences ??= await Prefer.getInstance();
    await _preferences!.setString(
      _storageKey,
      AiSettingsDocument(providers: _providers, prompts: _prompts).encode(),
    );
  }

  void _validateProvider(AiProviderConfig provider) {
    if (provider.name.trim().isEmpty)
      throw const AiConfigurationException('请输入服务名称');
    final uri = Uri.tryParse(provider.baseUrl.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const AiConfigurationException('请输入有效的 http 或 https Base URL');
    }
    if (provider.model.trim().isEmpty)
      throw const AiConfigurationException('请输入模型名称');
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
