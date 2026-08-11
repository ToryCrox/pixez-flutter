import 'dart:async';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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

class _WebpProcessingDialogState extends State<WebpProcessingDialog> {
  static const _thumbnailExtent = 67.2;

  final _qualityController = TextEditingController(text: '80');
  final _percentageController = TextEditingController(text: '100');
  final _maxWidthController = TextEditingController();
  final _maxHeightController = TextEditingController();
  final _processor = StaticWebpProcessor();

  Directory? _sessionDirectory;
  WebpToolCheck? _toolCheck;
  List<WebpProcessingResult>? _results;
  var _quality = 80;
  var _completed = 0;
  var _processing = false;
  var _replacing = false;

  bool get _showResults => _results != null;
  bool get _busy => _processing || _replacing;

  @override
  void initState() {
    super.initState();
    _checkTool();
    _cleanupStaleSessions();
  }

  @override
  void dispose() {
    _qualityController.dispose();
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

  WebpProcessingOptions? _buildOptions() {
    final quality = int.tryParse(_qualityController.text.trim());
    final percentage = int.tryParse(_percentageController.text.trim());
    final maxWidthText = _maxWidthController.text.trim();
    final maxHeightText = _maxHeightController.text.trim();
    final options = WebpProcessingOptions(
      quality: quality ?? -1,
      percentage: percentage ?? -1,
      maxWidth: maxWidthText.isEmpty ? null : int.tryParse(maxWidthText),
      maxHeight: maxHeightText.isEmpty ? null : int.tryParse(maxHeightText),
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
          height: _showResults ? 680 : 500,
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
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _numberField(
            controller: _percentageController,
            label: '缩放百分比',
            suffix: '%',
            helper: '1–100；与最大尺寸同时填写时，取缩小幅度最大的限制。',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _numberField(
                  controller: _maxWidthController,
                  label: '最大宽度',
                  suffix: 'px',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberField(
                  controller: _maxHeightController,
                  label: '最大高度',
                  suffix: 'px',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '默认不缩小。最多同时使用百分比、最大宽度和最大高度，始终保持原比例且不会放大。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
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
        const SizedBox(height: 12),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
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
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _preview(
                    result.input.sourcePath,
                    '处理前',
                    '${result.originalDimensions!.width}×${result.originalDimensions!.height}\n${result.originalSize.formatFileSize()}',
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.arrow_forward),
                ),
                Expanded(
                  child: _preview(
                    result.outputPath!,
                    '处理后',
                    '${result.outputDimensions!.width}×${result.outputDimensions!.height}\n${result.outputSize!.formatFileSize()}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(String filePath, String label, String detail) {
    return InkWell(
      onTap:
          () => LocalImageViewerPage.open(
            context,
            imagePath: filePath,
            title: label,
            subtitle: detail,
          ),
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
