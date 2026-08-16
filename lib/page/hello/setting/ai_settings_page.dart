import 'package:flutter/material.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/main.dart';

const _defaultProviderBinding = '__default_provider__';
const _unboundProviderBinding = '__unbound_provider__';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: aiSettings,
      builder: (context, _) {
        if (!aiSettings.initialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('AI 设置'),
            bottom: TabBar(
              controller: _tabs,
              tabs: const [Tab(text: '服务配置'), Tab(text: '提示词')],
            ),
          ),
          floatingActionButton: AnimatedBuilder(
            animation: _tabs,
            builder:
                (context, _) => FloatingActionButton.extended(
                  onPressed: _tabs.index == 0 ? _editProvider : _editPrompt,
                  icon: const Icon(Icons.add),
                  label: Text(_tabs.index == 0 ? '添加服务' : '添加提示词'),
                ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [_buildProviders(), _buildPrompts()],
          ),
        );
      },
    );
  }

  Widget _buildProviders() {
    final providers = aiSettings.providers;
    if (providers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '还没有 AI 服务配置。添加 OpenAI 或兼容服务后，即可绑定默认提示词。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '选择一个服务作为默认服务，提示词选择“使用默认服务”后会跟随此设置。\n'
            'API Key 将以明文保存在本机应用偏好设置中，请仅在可信设备上使用。',
            style: TextStyle(color: Colors.orange),
          ),
        ),
        for (final provider in providers)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: ListTile(
              leading: Radio<String>(
                value: provider.id,
                groupValue: aiSettings.defaultProviderId,
                onChanged: (_) => _setDefaultProvider(provider.id),
              ),
              title: Text(provider.name),
              subtitle: Text(
                '${aiSettings.defaultProviderId == provider.id ? '默认服务 · ' : ''}'
                '${provider.protocol.label}\n${provider.model} · ${provider.baseUrl}'
                '${provider.ignoreCertificateErrors ? '\n⚠️ 已忽略 HTTPS 证书校验（诊断）' : ''}'
                '${provider.bypassSni ? '\n⚠️ 已启用 SNI 绕过（仅此服务）' : ''}',
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (value) => _handleProviderAction(value, provider),
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(value: 'test', child: Text('测试连接')),
                      PopupMenuItem(value: 'copy', child: Text('复制')),
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
              ),
              onTap: () => _editProvider(provider),
            ),
          ),
      ],
    );
  }

  Widget _buildPrompts() {
    final prompts = aiSettings.prompts;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Expanded(child: Text('每个场景同时只会使用一条已启用提示词。')),
              TextButton(
                onPressed: aiSettings.restoreDefaultPrompts,
                child: const Text('恢复默认'),
              ),
            ],
          ),
        ),
        for (final prompt in prompts)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: ListTile(
              leading: Radio<String>(
                value: prompt.id,
                groupValue: aiSettings.activePrompt(prompt.sceneId)?.id,
                onChanged: (_) => aiSettings.setPromptActive(prompt.id),
              ),
              title: Text(prompt.name),
              subtitle: Text(
                '${AiPromptScenes.labels[prompt.sceneId] ?? prompt.sceneId} · '
                '${_promptBindingLabel(prompt)}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => _handlePromptAction(value, prompt),
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(value: 'copy', child: Text('复制')),
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
              ),
              onTap: () => _editPrompt(prompt),
            ),
          ),
      ],
    );
  }

  String _promptBindingLabel(AiPromptPreset prompt) {
    if (prompt.useDefaultProvider) {
      final provider = aiSettings.defaultProvider;
      return provider == null ? '使用默认服务（未设置）' : '使用默认服务：${provider.name}';
    }
    if (prompt.providerId.isEmpty) return '暂不绑定服务';
    return aiSettings.providerById(prompt.providerId)?.name ?? '服务不存在';
  }

  Future<void> _setDefaultProvider(String providerId) async {
    try {
      await aiSettings.setDefaultProvider(providerId);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _handleProviderAction(
    String action,
    AiProviderConfig provider,
  ) async {
    switch (action) {
      case 'test':
        await _testProvider(provider);
      case 'copy':
        await _editProvider(
          provider.copyWith(
            id: aiSettings.newId('provider'),
            name: '${provider.name} 副本',
          ),
        );
      case 'edit':
        await _editProvider(provider);
      case 'delete':
        try {
          await aiSettings.deleteProvider(provider.id);
        } catch (error) {
          _showError(error);
        }
    }
  }

  Future<void> _handlePromptAction(String action, AiPromptPreset prompt) async {
    switch (action) {
      case 'copy':
        await _editPrompt(
          prompt.copyWith(
            id: aiSettings.newId('prompt'),
            name: '${prompt.name} 副本',
            isActive: false,
          ),
        );
      case 'edit':
        await _editPrompt(prompt);
      case 'delete':
        await aiSettings.deletePrompt(prompt.id);
    }
  }

  Future<void> _editProvider([AiProviderConfig? source]) async {
    final result = await showDialog<AiProviderConfig>(
      context: context,
      builder:
          (_) => _ProviderEditorDialog(
            provider:
                source ??
                AiProviderConfig(
                  id: aiSettings.newId('provider'),
                  name: '',
                  protocol: AiProtocolType.openAiChatCompletions,
                  baseUrl: 'https://api.openai.com/v1',
                  apiKey: '',
                  model: '',
                ),
          ),
    );
    if (result == null) return;
    try {
      await aiSettings.upsertProvider(result);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editPrompt([AiPromptPreset? source]) async {
    final result = await showDialog<AiPromptPreset>(
      context: context,
      builder:
          (_) => _PromptEditorDialog(
            prompt:
                source ??
                AiPromptPreset(
                  id: aiSettings.newId('prompt'),
                  name: '',
                  sceneId: AiPromptScenes.illustTitle,
                  providerId: '',
                  useDefaultProvider: true,
                  systemPrompt: '',
                  userTemplate: '请翻译：{{text}}',
                  isActive: false,
                ),
          ),
    );
    if (result == null) return;
    try {
      await aiSettings.upsertPrompt(result);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _testProvider(AiProviderConfig provider) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正在测试 AI 服务连接…')));
    try {
      await aiClient.testConfig(provider);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('连接成功')));
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

class _ProviderEditorDialog extends StatefulWidget {
  final AiProviderConfig provider;
  const _ProviderEditorDialog({required this.provider});

  @override
  State<_ProviderEditorDialog> createState() => _ProviderEditorDialogState();
}

class _ProviderEditorDialogState extends State<_ProviderEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late AiProtocolType _protocol;
  String? _reasoningEffort;
  late int _maxRetries;
  late bool _ignoreCertificateErrors;
  late bool _bypassSni;
  late final FocusNode _modelFocusNode;
  List<String> _models = const [];
  bool _loadingModels = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.provider.name);
    _baseUrl = TextEditingController(text: widget.provider.baseUrl);
    _apiKey = TextEditingController(text: widget.provider.apiKey);
    _model = TextEditingController(text: widget.provider.model);
    _protocol = widget.provider.protocol;
    _reasoningEffort = widget.provider.reasoningEffort;
    _maxRetries = widget.provider.maxRetries;
    _ignoreCertificateErrors = widget.provider.ignoreCertificateErrors;
    _bypassSni = widget.provider.bypassSni;
    _modelFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _modelFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.provider.name.isEmpty ? '添加 AI 服务' : '编辑 AI 服务'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_name, '名称'),
              DropdownButtonFormField<AiProtocolType>(
                value: _protocol,
                decoration: const InputDecoration(labelText: '协议'),
                items:
                    AiProtocolType.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.label),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setState(() => _protocol = value!),
              ),
              _field(_baseUrl, 'Base URL', hint: 'https://api.openai.com/v1'),
              _field(
                _apiKey,
                'API Key（可留空）',
                obscureText: _obscureKey,
                suffix: IconButton(
                  icon: Icon(
                    _obscureKey ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                ),
                title: const Text('忽略 HTTPS 证书校验（仅诊断）'),
                subtitle: const Text(
                  '仅用于排查 TLS 握手问题。开启后会关闭该服务的证书安全校验，确认结果后请关闭。',
                ),
                value: _ignoreCertificateErrors,
                onChanged:
                    (value) => setState(() => _ignoreCertificateErrors = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.alt_route),
                title: const Text('绕过 SNI（仅当前服务）'),
                subtitle: const Text(
                  '不向该服务发送目标域名 SNI，并使用兼容模式连接。仅用于异常 TLS 服务，默认关闭。',
                ),
                value: _bypassSni,
                onChanged: (value) => setState(() => _bypassSni = value),
              ),
              _modelField(),
              DropdownButtonFormField<String?>(
                value: _reasoningEffort,
                decoration: const InputDecoration(labelText: '思考强度'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('默认（不发送）')),
                  DropdownMenuItem(value: 'none', child: Text('none')),
                  DropdownMenuItem(value: 'minimal', child: Text('minimal')),
                  DropdownMenuItem(value: 'low', child: Text('low')),
                  DropdownMenuItem(value: 'medium', child: Text('medium')),
                  DropdownMenuItem(value: 'high', child: Text('high')),
                  DropdownMenuItem(value: 'xhigh', child: Text('xhigh')),
                  DropdownMenuItem(value: 'max', child: Text('max')),
                ],
                onChanged: (value) => setState(() => _reasoningEffort = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _maxRetries,
                decoration: const InputDecoration(
                  labelText: '失败重试次数',
                  helperText: '仅重试超时、连接失败、限流和服务端错误，并使用指数退避',
                ),
                items: [
                  for (var count = 0; count <= 10; count++)
                    DropdownMenuItem(
                      value: count,
                      child: Text(count == 0 ? '不重试' : '$count 次'),
                    ),
                ],
                onChanged: (value) => setState(() => _maxRetries = value ?? 3),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscureText = false,
    Widget? suffix,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
      ),
    ),
  );

  Widget _modelField() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: RawAutocomplete<String>(
      textEditingController: _model,
      focusNode: _modelFocusNode,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return _models;
        return _models.where((model) => model.toLowerCase().contains(query));
      },
      onSelected: (value) => _model.text = value,
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(option),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: '模型',
            hintText: 'gpt-4o-mini',
            suffixIcon: IconButton(
              tooltip: '从上游获取模型',
              icon:
                  _loadingModels
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.refresh),
              onPressed: _loadingModels ? null : _fetchModels,
            ),
          ),
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
    ),
  );

  Future<void> _fetchModels() async {
    setState(() => _loadingModels = true);
    try {
      final models = await aiClient.fetchModels(
        AiProviderConfig(
          id: widget.provider.id,
          name: _name.text.trim(),
          protocol: _protocol,
          baseUrl: _baseUrl.text.trim(),
          apiKey: _apiKey.text.trim(),
          model: _model.text.trim(),
          reasoningEffort: _reasoningEffort,
          maxRetries: _maxRetries,
          ignoreCertificateErrors: _ignoreCertificateErrors,
          bypassSni: _bypassSni,
        ),
      );
      if (!mounted) return;
      setState(() => _models = models);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            models.isEmpty ? '上游没有返回可用模型' : '已获取 ${models.length} 个模型',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  void _save() => Navigator.pop(
    context,
    widget.provider.copyWith(
      name: _name.text.trim(),
      protocol: _protocol,
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      model: _model.text.trim(),
      reasoningEffort: _reasoningEffort,
      maxRetries: _maxRetries,
      ignoreCertificateErrors: _ignoreCertificateErrors,
      bypassSni: _bypassSni,
      clearReasoningEffort: _reasoningEffort == null,
    ),
  );
}

class _PromptEditorDialog extends StatefulWidget {
  final AiPromptPreset prompt;
  const _PromptEditorDialog({required this.prompt});

  @override
  State<_PromptEditorDialog> createState() => _PromptEditorDialogState();
}

class _PromptEditorDialogState extends State<_PromptEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _system;
  late final TextEditingController _user;
  late String _scene;
  late String _providerId;
  late bool _useDefaultProvider;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.prompt.name);
    _system = TextEditingController(text: widget.prompt.systemPrompt);
    _user = TextEditingController(text: widget.prompt.userTemplate);
    _scene = widget.prompt.sceneId;
    _providerId = widget.prompt.providerId;
    _useDefaultProvider = widget.prompt.useDefaultProvider;
    _active = widget.prompt.isActive;
  }

  @override
  void dispose() {
    _name.dispose();
    _system.dispose();
    _user.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final variables = AiPromptScenes.requiredVariables[_scene]!
        .map((item) => '{{$item}}')
        .join('、');
    return AlertDialog(
      title: const Text('编辑提示词'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_name, '名称'),
              DropdownButtonFormField<String>(
                value: _scene,
                decoration: const InputDecoration(labelText: '场景'),
                items:
                    AiPromptScenes.labels.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setState(() => _scene = value!),
              ),
              _providerBindingDropdown(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用此提示词'),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '可用变量：$variables',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              _field(_system, 'System 提示词', maxLines: 5),
              _field(_user, 'User 模板', maxLines: 5),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _providerBindingDropdown() {
    final bindingValue =
        _useDefaultProvider
            ? _defaultProviderBinding
            : (_providerId.isEmpty ? _unboundProviderBinding : _providerId);
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: _defaultProviderBinding,
        child: Text('使用默认服务'),
      ),
      const DropdownMenuItem(
        value: _unboundProviderBinding,
        child: Text('暂不绑定'),
      ),
    ];
    if (!_useDefaultProvider &&
        _providerId.isNotEmpty &&
        aiSettings.providerById(_providerId) == null) {
      items.add(
        DropdownMenuItem(value: _providerId, child: const Text('服务不存在')),
      );
    }
    items.addAll(
      aiSettings.providers.map(
        (item) => DropdownMenuItem(value: item.id, child: Text(item.name)),
      ),
    );
    return DropdownButtonFormField<String>(
      value: bindingValue,
      decoration: const InputDecoration(labelText: 'AI 服务绑定'),
      items: items,
      onChanged: (value) {
        if (value == _defaultProviderBinding) {
          setState(() {
            _useDefaultProvider = true;
            _providerId = '';
          });
        } else if (value == _unboundProviderBinding) {
          setState(() {
            _useDefaultProvider = false;
            _providerId = '';
          });
        } else if (value != null) {
          setState(() {
            _useDefaultProvider = false;
            _providerId = value;
          });
        }
      },
    );
  }

  void _save() => Navigator.pop(
    context,
    widget.prompt.copyWith(
      name: _name.text.trim(),
      sceneId: _scene,
      providerId: _useDefaultProvider ? '' : _providerId,
      useDefaultProvider: _useDefaultProvider,
      systemPrompt: _system.text.trim(),
      userTemplate: _user.text.trim(),
      isActive: _active,
    ),
  );
}
