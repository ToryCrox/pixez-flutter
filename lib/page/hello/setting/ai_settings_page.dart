import 'package:flutter/material.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/main.dart';

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
            'API Key 将以明文保存在本机应用偏好设置中，请仅在可信设备上使用。',
            style: TextStyle(color: Colors.orange),
          ),
        ),
        for (final provider in providers)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: ListTile(
              title: Text(provider.name),
              subtitle: Text(
                '${provider.protocol.label}\n${provider.model} · ${provider.baseUrl}',
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
                '${aiSettings.providerById(prompt.providerId)?.name ?? '未绑定服务'}',
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
                  providerId:
                      aiSettings.providers.isEmpty
                          ? ''
                          : aiSettings.providers.first.id,
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
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
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
              _field(_model, '模型', hint: 'gpt-4o-mini'),
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
  late bool _active;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.prompt.name);
    _system = TextEditingController(text: widget.prompt.systemPrompt);
    _user = TextEditingController(text: widget.prompt.userTemplate);
    _scene = widget.prompt.sceneId;
    _providerId = widget.prompt.providerId;
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
              DropdownButtonFormField<String>(
                value: _providerId,
                decoration: const InputDecoration(labelText: 'AI 服务'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('暂不绑定')),
                  ...aiSettings.providers.map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _providerId = value ?? ''),
              ),
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

  void _save() => Navigator.pop(
    context,
    widget.prompt.copyWith(
      name: _name.text.trim(),
      sceneId: _scene,
      providerId: _providerId,
      systemPrompt: _system.text.trim(),
      userTemplate: _user.text.trim(),
      isActive: _active,
    ),
  );
}
