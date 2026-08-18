import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/downloaded/local_image_viewer_page.dart';
import 'package:pixez/store/downloaded_image_organizer_store.dart';
import 'package:pixez/utils/static_webp_processor.dart';

class WebpProcessingDialog extends StatefulWidget {
  final List<DownloadedImageDisplayItem> items;
  final Future<void> Function() onReplaced;

  const WebpProcessingDialog({
    super.key,
    required this.items,
    required this.onReplaced,
  });

  static Future<void> show(
    BuildContext context, {
    required List<DownloadedImageDisplayItem> items,
    required Future<void> Function() onReplaced,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => WebpProcessingDialog(items: items, onReplaced: onReplaced),
    );
  }

  @override
  State<WebpProcessingDialog> createState() => _WebpProcessingDialogState();
}

class _ResizePreset {
  final String id;
  String name;
  String percentage = '100';
  String maxWidth = '';
  String maxHeight = '';

  _ResizePreset({required this.id, required this.name});

  String get summary {
    final displayName = name.isEmpty ? '未命名配置' : name;
    final limits = <String>[
      '$percentage%',
      if (maxWidth.isNotEmpty) '宽≤$maxWidth',
      if (maxHeight.isNotEmpty) '高≤$maxHeight',
    ];
    return '$displayName（${limits.join('，')}）';
  }

  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'percentage': percentage,
    'maxWidth': maxWidth,
    'maxHeight': maxHeight,
  };

  static _ResizePreset? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'] as String?;
    if (id == null || id.isEmpty) return null;
    final preset = _ResizePreset(
      id: id,
      name: value['name'] as String? ?? '未命名配置',
    );
    preset
      ..percentage = value['percentage'] as String? ?? '100'
      ..maxWidth = value['maxWidth'] as String? ?? ''
      ..maxHeight = value['maxHeight'] as String? ?? '';
    return preset;
  }
}

class _WebpProcessingDialogState extends State<WebpProcessingDialog> {
  static const _thumbnailExtent = 67.2;
  static const _noResizePreset = '__no_resize_preset__';
  static const _webpQualityPreferenceKey = 'webp_processing_quality_v1';
  static const _concurrencyPreferenceKey = 'webp_processing_concurrency_v1';
  static const _resizePresetsPreferenceKey =
      'webp_processing_resize_presets_v1';
  static const _selectedResizePresetPreferenceKey =
      'webp_processing_selected_resize_preset_v1';

  final _qualityController = TextEditingController(text: '80');
  final _concurrencyController = TextEditingController(
    text: '${StaticWebpProcessor.defaultConcurrency}',
  );
  final _resizePresetNameController = TextEditingController();
  final _percentageController = TextEditingController(text: '100');
  final _maxWidthController = TextEditingController();
  final _maxHeightController = TextEditingController();
  final _processor = StaticWebpProcessor();

  Directory? _sessionDirectory;
  WebpToolCheck? _toolCheck;
  List<WebpProcessingResult>? _results;
  var _quality = 80;
  var _concurrency = StaticWebpProcessor.defaultConcurrency;
  var _completed = 0;
  var _processing = false;
  var _replacing = false;
  final _resizePresets = <_ResizePreset>[];
  String? _selectedResizePresetId;
  var _nextResizePresetNumber = 1;

  bool get _showResults => _results != null;
  bool get _busy => _processing || _replacing;
  _ResizePreset? get _selectedResizePreset {
    final selectedId = _selectedResizePresetId;
    if (selectedId == null) return null;
    for (final preset in _resizePresets) {
      if (preset.id == selectedId) return preset;
    }
    return null;
  }

  int get _scalePercentage {
    final value = int.tryParse(_percentageController.text.trim()) ?? 100;
    return value.clamp(1, 100);
  }

  /// 少量处理结果不应撑满整个弹框；批量结果则保持可滚动的最大高度。
  double get _resultContentHeight {
    final resultCount = _results?.length ?? 0;
    return math.min(680, math.max(250, 88 + resultCount * 104));
  }

  @override
  void initState() {
    super.initState();
    _restorePreferences();
    _checkTool();
    _cleanupStaleSessions();
  }

  @override
  void dispose() {
    _qualityController.dispose();
    _concurrencyController.dispose();
    _resizePresetNameController.dispose();
    _percentageController.dispose();
    _maxWidthController.dispose();
    _maxHeightController.dispose();
    unawaited(StaticWebpProcessor.cleanupSession(_sessionDirectory));
    super.dispose();
  }

  Future<void> _checkTool() async {
    final check = await StaticWebpProcessor.checkAvailability();
    if (mounted) setState(() => _toolCheck = check);
  }

  Future<void> _cleanupStaleSessions() async {
    final temporaryDirectory = await getTemporaryDirectory();
    await StaticWebpProcessor.cleanupStaleSessions(temporaryDirectory);
  }

  void _restorePreferences() {
    final savedQuality = Prefer.getInt(_webpQualityPreferenceKey);
    final savedConcurrency = Prefer.getInt(_concurrencyPreferenceKey);
    final savedSelectedPresetId = Prefer.getString(
      _selectedResizePresetPreferenceKey,
    );
    final savedPresets = <_ResizePreset>[];
    final rawPresets = Prefer.getString(_resizePresetsPreferenceKey);
    if (rawPresets != null) {
      try {
        final decoded = jsonDecode(rawPresets);
        if (decoded is List) {
          savedPresets.addAll(
            decoded.map(_ResizePreset.fromJson).whereType<_ResizePreset>(),
          );
        }
      } catch (e, stackTrace) {
        Log.e('读取 WebP 缩放配置失败', error: e, stackTrace: stackTrace);
      }
    }
    setState(() {
      _quality = (savedQuality ?? 80).clamp(0, 100);
      _qualityController.text = _quality.toString();
      _concurrency = _normalizeConcurrency(
        savedConcurrency ?? StaticWebpProcessor.defaultConcurrency,
      );
      _concurrencyController.text = _concurrency.toString();
      _resizePresets
        ..clear()
        ..addAll(savedPresets);
      _selectedResizePresetId =
          savedPresets.any((preset) => preset.id == savedSelectedPresetId)
              ? savedSelectedPresetId
              : null;
      _loadResizePreset(_selectedResizePreset);
      _nextResizePresetNumber = _resizePresets.length + 1;
    });
  }

  Future<void> _persistQuality() =>
      Prefer.setInt(_webpQualityPreferenceKey, _quality);

  Future<void> _persistConcurrency() =>
      Prefer.setInt(_concurrencyPreferenceKey, _concurrency);

  int _normalizeConcurrency(int value) {
    if (value < 1) return 1;
    if (value > StaticWebpProcessor.maxConcurrency) {
      return StaticWebpProcessor.maxConcurrency;
    }
    return value;
  }

  Future<void> _persistSelectedResizePreset() => Prefer.setString(
    _selectedResizePresetPreferenceKey,
    _selectedResizePresetId ?? '',
  );

  Future<void> _persistResizePresets() async {
    try {
      await Prefer.setString(
        _resizePresetsPreferenceKey,
        jsonEncode(_resizePresets.map((preset) => preset.toJson()).toList()),
      );
    } catch (e, stackTrace) {
      Log.e('保存 WebP 缩放配置失败', error: e, stackTrace: stackTrace);
    }
  }

  void _saveSelectedResizePreset() {
    final preset = _selectedResizePreset;
    if (preset == null) return;
    preset
      ..name = _resizePresetNameController.text.trim()
      ..percentage = _percentageController.text.trim()
      ..maxWidth = _maxWidthController.text.trim()
      ..maxHeight = _maxHeightController.text.trim();
  }

  void _loadResizePreset(_ResizePreset? preset) {
    _resizePresetNameController.text = preset?.name ?? '';
    _percentageController.text = preset?.percentage ?? '100';
    _maxWidthController.text = preset?.maxWidth ?? '';
    _maxHeightController.text = preset?.maxHeight ?? '';
  }

  void _selectResizePreset(String value) {
    setState(() {
      _saveSelectedResizePreset();
      _selectedResizePresetId = value == _noResizePreset ? null : value;
      _loadResizePreset(_selectedResizePreset);
    });
    unawaited(_persistResizePresets());
    unawaited(_persistSelectedResizePreset());
  }

  void _addResizePreset() {
    setState(() {
      _saveSelectedResizePreset();
      final preset = _ResizePreset(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: '缩放配置 ${_nextResizePresetNumber++}',
      );
      _resizePresets.add(preset);
      _selectedResizePresetId = preset.id;
      _loadResizePreset(preset);
    });
    unawaited(_persistResizePresets());
    unawaited(_persistSelectedResizePreset());
  }

  void _removeSelectedResizePreset() {
    final preset = _selectedResizePreset;
    if (preset == null) return;
    setState(() {
      _resizePresets.remove(preset);
      _selectedResizePresetId = null;
      _loadResizePreset(null);
    });
    unawaited(_persistResizePresets());
    unawaited(_persistSelectedResizePreset());
  }

  WebpProcessingOptions? _buildOptions() {
    _saveSelectedResizePreset();
    final quality = int.tryParse(_qualityController.text.trim());
    final resizePreset = _selectedResizePreset;
    final percentage = int.tryParse(_percentageController.text.trim());
    final maxWidthText = _maxWidthController.text.trim();
    final maxHeightText = _maxHeightController.text.trim();
    final options = WebpProcessingOptions(
      quality: quality ?? -1,
      percentage: resizePreset == null ? 100 : percentage ?? -1,
      maxWidth:
          resizePreset == null || maxWidthText.isEmpty
              ? null
              : int.tryParse(maxWidthText),
      maxHeight:
          resizePreset == null || maxHeightText.isEmpty
              ? null
              : int.tryParse(maxHeightText),
    );
    final error = options.validate();
    if (error != null) {
      BotToast.showText(text: error);
      return null;
    }
    return options;
  }

  Future<void> _startProcessing() async {
    final options = _buildOptions();
    if (options == null || _toolCheck?.isAvailable != true) return;
    final concurrency = int.tryParse(_concurrencyController.text.trim());
    if (concurrency == null ||
        concurrency < 1 ||
        concurrency > StaticWebpProcessor.maxConcurrency) {
      BotToast.showText(
        text: '并发数必须是 1～${StaticWebpProcessor.maxConcurrency} 的整数',
      );
      return;
    }
    _concurrency = concurrency;
    unawaited(_persistConcurrency());
    final temporaryDirectory = await getTemporaryDirectory();
    await StaticWebpProcessor.cleanupSession(_sessionDirectory);
    await StaticWebpProcessor.cleanupStaleSessions(temporaryDirectory);
    final sessionDirectory = await StaticWebpProcessor.createSessionDirectory(
      temporaryDirectory,
    );
    if (!mounted) {
      await StaticWebpProcessor.cleanupSession(sessionDirectory);
      return;
    }

    setState(() {
      _sessionDirectory = sessionDirectory;
      _processing = true;
      _completed = 0;
      _results = null;
    });
    try {
      final results = await _processor.processAll(
        inputs:
            widget.items
                .map(
                  (item) => WebpProcessingInput(
                    illustId: item.illust.illustId,
                    part: item.image.part,
                    userId: item.illust.userId,
                    sourcePath: item.path,
                    isUgoira: item.illust.isUgoira,
                  ),
                )
                .toList(),
        options: options,
        sessionDirectory: sessionDirectory,
        concurrency: concurrency,
        onProgress: (completed, _) {
          if (mounted) setState(() => _completed = completed);
        },
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _processing = false;
      });
    } catch (e) {
      await StaticWebpProcessor.cleanupSession(sessionDirectory);
      if (!mounted) return;
      setState(() {
        _sessionDirectory = null;
        _processing = false;
      });
      BotToast.showText(text: '处理无法开始：$e');
    }
  }

  Future<void> _discardAndReprocess() async {
    await StaticWebpProcessor.cleanupSession(_sessionDirectory);
    if (!mounted) return;
    setState(() {
      _sessionDirectory = null;
      _results = null;
      _completed = 0;
    });
  }

  Future<void> _replaceOriginals() async {
    final results = _results;
    if (results == null || _busy) return;
    final successful = results.where((result) => result.isSuccess).toList();
    if (successful.isEmpty) return;
    setState(() => _replacing = true);
    final replacements = await _processor.replaceAll(
      results: successful,
      databaseProvider: downloadStore.dbProvider,
    );
    final succeeded = replacements.where((result) => result.isSuccess).toList();
    for (final replacement in succeeded) {
      final sourcePath = replacement.processingResult.input.sourcePath;
      final targetPath =
          '${sourcePath.substring(0, sourcePath.lastIndexOf('.'))}.webp';
      await FileImage(File(sourcePath)).evict();
      await FileImage(File(targetPath)).evict();
    }
    await StaticWebpProcessor.cleanupSession(_sessionDirectory);
    if (!mounted) return;
    await widget.onReplaced();
    if (!mounted) return;
    final failed = replacements.length - succeeded.length;
    BotToast.showText(
      text:
          failed == 0
              ? '已替换 ${succeeded.length} 张图片'
              : '已替换 ${succeeded.length} 张，${failed} 张替换失败',
    );
    Navigator.of(context).pop();
  }

  void _close() {
    if (_busy) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final toolCheck = _toolCheck;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(_showResults ? '处理结果' : '图片格式处理'),
        content: SizedBox(
          width: 1100,
          height: _showResults ? _resultContentHeight : 500,
          child:
              toolCheck == null
                  ? const Center(child: CircularProgressIndicator())
                  : !toolCheck.isAvailable
                  ? _buildToolError(toolCheck)
                  : _showResults
                  ? _buildResults()
                  : _buildSettings(),
        ),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildToolError(WebpToolCheck check) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 34),
        const SizedBox(height: 12),
        Text(check.error ?? 'cwebp 工具不可用'),
        const SizedBox(height: 8),
        const Text('请确认应用安装包已包含与当前系统架构匹配的 cwebp 工具。'),
      ],
    );
  }

  Widget _buildSettings() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('将选中的 ${widget.items.length} 张静态图片处理为 WebP。动图会在处理结果中标记为跳过。'),
          if (_processing) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value:
                  widget.items.isEmpty ? 0 : _completed / widget.items.length,
            ),
            const SizedBox(height: 6),
            Text('正在处理 $_completed / ${widget.items.length}'),
          ],
          const SizedBox(height: 20),
          Text(
            'WebP 质量：$_quality%',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _quality.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '$_quality',
                  onChanged:
                      _busy
                          ? null
                          : (value) {
                            setState(() {
                              _quality = value.round();
                              _qualityController.text = _quality.toString();
                            });
                            unawaited(_persistQuality());
                          },
                ),
              ),
              SizedBox(
                width: 90,
                child: _numberField(
                  controller: _qualityController,
                  suffix: '%',
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed >= 0 && parsed <= 100) {
                      setState(() => _quality = parsed);
                      unawaited(_persistQuality());
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 180,
                child: _numberField(
                  controller: _concurrencyController,
                  label: '并发转换数',
                  suffix: '个',
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null &&
                        parsed >= 1 &&
                        parsed <= StaticWebpProcessor.maxConcurrency) {
                      setState(() => _concurrency = parsed);
                      unawaited(_persistConcurrency());
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '同时运行的 cwebp 进程数，默认 ${StaticWebpProcessor.defaultConcurrency}，建议设置为 2～4。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildResizeSettings(),
        ],
      ),
    );
  }

  Widget _buildResizeSettings() {
    final preset = _selectedResizePreset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey(_selectedResizePresetId ?? _noResizePreset),
                initialValue: _selectedResizePresetId ?? _noResizePreset,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '缩放配置',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: _noResizePreset,
                    child: Text('不缩放'),
                  ),
                  ..._resizePresets.map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.summary),
                    ),
                  ),
                ],
                onChanged:
                    _busy || _processing
                        ? null
                        : (value) {
                          if (value != null) _selectResizePreset(value);
                        },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _addResizePreset,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增配置'),
            ),
            if (preset != null) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: _busy ? null : _removeSelectedResizePreset,
                tooltip: '删除当前配置',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (preset == null)
          Text(
            '当前不缩放。可新增多套缩放配置，再选择其中一套使用。',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else ...[
          TextField(
            controller: _resizePresetNameController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: '配置名称',
              hintText: '例如：笔记本屏幕、社交平台',
              isDense: true,
            ),
            onChanged: (_) {
              setState(_saveSelectedResizePreset);
              unawaited(_persistResizePresets());
            },
          ),
          const SizedBox(height: 12),
          Text(
            '缩放百分比：$_scalePercentage%',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _scalePercentage.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '$_scalePercentage',
                  onChanged:
                      _busy
                          ? null
                          : (value) {
                            setState(() {
                              _percentageController.text =
                                  value.round().toString();
                              _saveSelectedResizePreset();
                            });
                            unawaited(_persistResizePresets());
                          },
                ),
              ),
              SizedBox(
                width: 90,
                child: _numberField(
                  controller: _percentageController,
                  suffix: '%',
                  onChanged: (_) {
                    setState(_saveSelectedResizePreset);
                    unawaited(_persistResizePresets());
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _numberField(
                  controller: _maxWidthController,
                  label: '最大宽度',
                  suffix: 'px',
                  onChanged: (_) {
                    setState(_saveSelectedResizePreset);
                    unawaited(_persistResizePresets());
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberField(
                  controller: _maxHeightController,
                  label: '最大高度',
                  suffix: 'px',
                  onChanged: (_) {
                    setState(_saveSelectedResizePreset);
                    unawaited(_persistResizePresets());
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '百分比、最大宽度和最大高度可同时填写，取缩小幅度最大的限制；保持比例且不会放大。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    String? label,
    String? suffix,
    String? helper,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: helper,
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildResults() {
    final results = _results!;
    final success = results.where((result) => result.isSuccess).toList();
    final originalSize = success.fold<int>(
      0,
      (sum, result) => sum + result.originalSize,
    );
    final outputSize = success.fold<int>(
      0,
      (sum, result) => sum + result.outputSize!,
    );
    final delta = outputSize - originalSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_processing) ...[
          LinearProgressIndicator(
            value: widget.items.isEmpty ? 0 : _completed / widget.items.length,
          ),
          const SizedBox(height: 8),
          Text('正在处理 $_completed / ${widget.items.length}'),
        ] else
          Text(
            '成功 ${success.length} 张，失败或跳过 ${results.length - success.length} 张；总大小 ${originalSize.formatFileSize()} → ${outputSize.formatFileSize()}（${_formatDelta(delta)}）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _buildResultRow(results[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildResultRow(WebpProcessingResult result) {
    final title = '${result.input.illustId} · P${result.input.part}';
    if (!result.isSuccess) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.orange),
          title: Text(title),
          subtitle: Text(result.error ?? '处理失败'),
        ),
      );
    }
    final delta = result.sizeDelta!;
    final ratio =
        result.originalSize == 0 ? 0 : delta / result.originalSize * 100;
    final deltaColor = delta > 0 ? Colors.orange : Colors.green;
    final comparison = LocalImageViewerComparison(
      leftImagePath: result.input.sourcePath,
      rightImagePath: result.outputPath!,
      leftTitle: '处理前',
      rightTitle: '处理后',
      leftSubtitle:
          '${result.originalDimensions!.width}×${result.originalDimensions!.height}\n${result.originalSize.formatFileSize()}',
      rightSubtitle:
          '${result.outputDimensions!.width}×${result.outputDimensions!.height}\n${result.outputSize!.formatFileSize()}',
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${_formatDelta(delta)}（${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(1)}%）',
                  style: TextStyle(color: deltaColor),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _preview(
                  result.input.sourcePath,
                  '处理前',
                  '${result.originalDimensions!.width}×${result.originalDimensions!.height}\n${result.originalSize.formatFileSize()}',
                  comparison: comparison,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward),
                ),
                _preview(
                  result.outputPath!,
                  '处理后',
                  '${result.outputDimensions!.width}×${result.outputDimensions!.height}\n${result.outputSize!.formatFileSize()}',
                  comparison: comparison,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(
    String filePath,
    String label,
    String detail, {
    required LocalImageViewerComparison comparison,
  }) {
    return InkWell(
      onTap:
          () => LocalImageViewerPage.open(
            context,
            imagePath: filePath,
            title: label,
            subtitle: detail,
            comparison: comparison,
          ),
      child: SizedBox(
        width: 210,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(
                File(filePath),
                width: _thumbnailExtent,
                height: _thumbnailExtent,
                fit: BoxFit.cover,
                errorBuilder:
                    (_, _, _) => const SizedBox(
                      width: _thumbnailExtent,
                      height: _thumbnailExtent,
                      child: Icon(Icons.broken_image),
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$label\n$detail',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDelta(int delta) =>
      '${delta >= 0 ? '+' : '-'}${delta.abs().formatFileSize()}';

  List<Widget> _buildActions() {
    if (_toolCheck?.isAvailable != true) {
      return [
        TextButton(onPressed: _busy ? null : _close, child: const Text('关闭')),
      ];
    }
    if (!_showResults) {
      return [
        TextButton(onPressed: _busy ? null : _close, child: const Text('取消')),
        FilledButton.icon(
          onPressed: _busy ? null : _startProcessing,
          icon:
              _processing
                  ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.play_arrow),
          label: Text(
            _processing ? '处理中 $_completed/${widget.items.length}' : '开始处理',
          ),
        ),
      ];
    }
    final successful = _results!.where((result) => result.isSuccess).length;
    return [
      TextButton(
        onPressed: _busy ? null : _discardAndReprocess,
        child: const Text('放弃替换并重新处理'),
      ),
      FilledButton(
        onPressed: _busy || successful == 0 ? null : _replaceOriginals,
        child: Text(_replacing ? '正在替换…' : '替换原图（$successful）'),
      ),
    ];
  }
}
