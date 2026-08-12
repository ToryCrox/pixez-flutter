import 'package:flutter/material.dart';
import 'package:pixez/manga_ocr/manga_ocr_model_manager.dart';
import 'package:pixez/manga_ocr/manga_ocr_engines.dart';
import 'package:pixez/manga_ocr/manga_ocr_models.dart';
import 'package:pixez/manga_ocr/manga_ocr_preferences.dart';

class MangaOcrSettingsPage extends StatefulWidget {
  const MangaOcrSettingsPage({super.key});

  @override
  State<MangaOcrSettingsPage> createState() => _MangaOcrSettingsPageState();
}

class _MangaOcrSettingsPageState extends State<MangaOcrSettingsPage> {
  final _manager = MangaOcrModelManager();
  List<MangaOcrModelPackage>? _packages;
  final _installed = <String, bool>{};
  final _sizes = <String, int>{};
  final _progress = <String, MangaOcrModelProgress>{};
  String? _busyEngine;
  String? _error;
  MangaOcrPreferences _preferences = const MangaOcrPreferences();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final packages = await _manager.loadManifest();
      _preferences = await MangaOcrPreferences.load();
      for (final item in packages) {
        _installed[item.engineId] = await _manager.isInstalled(item.engineId);
        _sizes[item.engineId] = await _manager.installedSize(item.engineId);
      }
      if (mounted) setState(() => _packages = packages);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _run(String engineId, Future<void> Function() operation) async {
    setState(() {
      _busyEngine = engineId;
      _error = null;
    });
    try {
      await operation();
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyEngine = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('漫画 OCR 模型')),
      body:
          _packages == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    '图片与 OCR 全程在本地处理。首次使用默认下载 CTD 与 Baberu int4；远端 AI 只会收到识别后的文字。',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildEngineSettings(),
                  const SizedBox(height: 16),
                  for (final item in _packages!) _buildPackage(item),
                ],
              ),
    );
  }

  Widget _buildEngineSettings() {
    final registry = MangaOcrEngineRegistry.instance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('引擎选择', style: Theme.of(context).textTheme.titleMedium),
            DropdownButtonFormField<String>(
              initialValue: _preferences.detectorId,
              decoration: const InputDecoration(labelText: '文字检测器'),
              items: [
                for (final item in registry.detectors)
                  DropdownMenuItem(value: item.id, child: Text(item.id)),
              ],
              onChanged: (value) async {
                if (value == null) return;
                _preferences = _preferences.copyWith(detectorId: value);
                await _preferences.save();
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _preferences.recognizerId,
              decoration: const InputDecoration(labelText: '文字识别器'),
              items: [
                for (final item in registry.recognizers)
                  DropdownMenuItem(value: item.id, child: Text(item.id)),
              ],
              onChanged: (value) async {
                if (value == null) return;
                _preferences = _preferences.copyWith(recognizerId: value);
                await _preferences.save();
              },
            ),
            DropdownButtonFormField<MangaReadingOrder>(
              initialValue: _preferences.readingOrder,
              decoration: const InputDecoration(labelText: '阅读顺序'),
              items: const [
                DropdownMenuItem(
                  value: MangaReadingOrder.automatic,
                  child: Text('自动'),
                ),
                DropdownMenuItem(
                  value: MangaReadingOrder.mangaRtl,
                  child: Text('日漫 RTL'),
                ),
                DropdownMenuItem(
                  value: MangaReadingOrder.leftToRight,
                  child: Text('LTR'),
                ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                _preferences = _preferences.copyWith(readingOrder: value);
                await _preferences.save();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackage(MangaOcrModelPackage item) {
    final installed = _installed[item.engineId] ?? false;
    final busy = _busyEngine == item.engineId;
    final progress = _progress[item.engineId];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.engineId, style: Theme.of(context).textTheme.titleMedium),
            Text('${item.version} · ${item.architecture} · ${item.license}'),
            const SizedBox(height: 6),
            Text(
              '下载大小 ${_formatBytes(item.totalSize)} · '
              '本地占用 ${_formatBytes(_sizes[item.engineId] ?? 0)}',
            ),
            if (busy) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value:
                    progress == null || progress.total <= 0
                        ? null
                        : progress.received / progress.total,
              ),
              if (progress != null) Text(progress.fileName),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed:
                      busy
                          ? null
                          : () => _run(
                            item.engineId,
                            () => _manager.install(
                              item.engineId,
                              onProgress: (value) {
                                if (mounted) {
                                  setState(
                                    () => _progress[item.engineId] = value,
                                  );
                                }
                              },
                            ),
                          ),
                  child: Text(installed ? '更新/修复' : '下载'),
                ),
                OutlinedButton(
                  onPressed:
                      !installed || busy
                          ? null
                          : () => _run(item.engineId, () async {
                            final valid = await _manager.verify(item.engineId);
                            if (!valid) throw StateError('模型校验失败，请重新下载');
                          }),
                  child: const Text('重新校验'),
                ),
                OutlinedButton(
                  onPressed:
                      !installed || busy
                          ? null
                          : () => _run(
                            item.engineId,
                            () => _manager.remove(item.engineId),
                          ),
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
