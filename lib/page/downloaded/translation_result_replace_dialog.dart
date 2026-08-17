import 'dart:io';
import 'dart:math' as math;

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/page/downloaded/local_image_viewer_page.dart';
import 'package:pixez/utils/translation_result_replacer.dart';

/// 预览外部翻译工具生成的 result 图片，并在确认后替换下载原图。
class TranslationResultReplaceDialog extends StatefulWidget {
  final TranslationReplacementPlan plan;
  final TranslationResultReplacer replacer;
  final Future<void> Function() onReplaced;

  const TranslationResultReplaceDialog({
    super.key,
    required this.plan,
    required this.replacer,
    required this.onReplaced,
  });

  static Future<void> show(
    BuildContext context, {
    required TranslationReplacementPlan plan,
    required TranslationResultReplacer replacer,
    required Future<void> Function() onReplaced,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => TranslationResultReplaceDialog(
            plan: plan,
            replacer: replacer,
            onReplaced: onReplaced,
          ),
    );
  }

  @override
  State<TranslationResultReplaceDialog> createState() =>
      _TranslationResultReplaceDialogState();
}

class _TranslationResultReplaceDialogState
    extends State<TranslationResultReplaceDialog> {
  static const _thumbnailExtent = 67.2;
  var _replacing = false;
  final Set<String> _skippedOriginalPaths = <String>{};

  int get _itemCount => widget.plan.pairs.length + widget.plan.unmatched.length;

  double get _contentHeight =>
      math.min(680, math.max(280, 104 + _itemCount * 104));

  Future<void> _replaceOriginals() async {
    if (_replacing || widget.plan.pairs.isEmpty) return;
    setState(() => _replacing = true);
    final summary = await widget.replacer.apply(
      widget.plan,
      skippedOriginalPaths: _skippedOriginalPaths,
    );
    for (final result in summary.results.where((item) => item.isSuccess)) {
      final pair = result.pair;
      await FileImage(File(pair.originalPath)).evict();
      await FileImage(File(pair.translatedPath)).evict();
      await FileImage(File(pair.destinationPath)).evict();
    }
    for (final pair in widget.plan.pairs.where(
      (pair) => _skippedOriginalPaths.contains(pair.originalPath),
    )) {
      await FileImage(File(pair.translatedPath)).evict();
    }
    if (!mounted) return;
    await widget.onReplaced();
    if (!mounted) return;
    final cleanupText =
        summary.translationResultDirectoriesCleaned ? '，已清理翻译结果目录' : '';
    final skippedText =
        summary.skippedCount == 0 ? '' : '，跳过 ${summary.skippedCount} 张';
    BotToast.showText(
      text:
          summary.failureCount == 0
              ? '已替换 ${summary.successCount} 张图片$skippedText$cleanupText'
              : '已替换 ${summary.successCount} 张，${summary.failureCount} 张替换失败$skippedText',
    );
    Navigator.of(context).pop();
  }

  void _close() {
    if (!_replacing) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_replacing,
      child: AlertDialog(
        title: const Text('翻译结果预览'),
        content: SizedBox(
          width: 1100,
          height: _contentHeight,
          child: _buildContent(),
        ),
        actions: [
          TextButton(
            onPressed: _replacing ? null : _close,
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: _replacing ? null : _replaceOriginals,
            icon:
                _replacing
                    ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.swap_horiz),
            label: Text(
              _replacing
                  ? '正在替换…'
                  : '替换原图（${widget.plan.pairs.length - _skippedOriginalPaths.length}）',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final delta =
        widget.plan.translatedTotalSize - widget.plan.originalTotalSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已匹配 ${widget.plan.pairs.length} 张；总大小 '
          '${widget.plan.originalTotalSize.formatFileSize()} → '
          '${widget.plan.translatedTotalSize.formatFileSize()}（${_formatDelta(delta)}）'
          '${widget.plan.unmatched.isEmpty ? '' : '；未匹配 ${widget.plan.unmatched.length} 项'}'
          '${_skippedOriginalPaths.isEmpty ? '' : '；已跳过 ${_skippedOriginalPaths.length} 张'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (widget.plan.unmatched.isNotEmpty)
          Text(
            '未匹配文件不会参与替换；应用成功后，本次翻译结果目录会一并清理。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
          ),
        if (widget.plan.unmatched.isNotEmpty) const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: _itemCount,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index < widget.plan.pairs.length) {
                return _buildPairRow(widget.plan.pairs[index]);
              }
              return _buildUnmatchedRow(
                widget.plan.unmatched[index - widget.plan.pairs.length],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPairRow(TranslationReplacementPair pair) {
    final delta = pair.translatedSize - pair.originalSize;
    final ratio = pair.originalSize == 0 ? 0 : delta / pair.originalSize * 100;
    final deltaColor = delta > 0 ? Colors.orange : Colors.green;
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
                    'P${pair.image.part} · ${pair.baseName}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${_formatDelta(delta)}（${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(1)}%）',
                  style: TextStyle(color: deltaColor),
                ),
                const SizedBox(width: 8),
                const Text('跳过'),
                Checkbox(
                  value: _skippedOriginalPaths.contains(pair.originalPath),
                  onChanged:
                      _replacing
                          ? null
                          : (value) {
                            setState(() {
                              if (value == true) {
                                _skippedOriginalPaths.add(pair.originalPath);
                              } else {
                                _skippedOriginalPaths.remove(pair.originalPath);
                              }
                            });
                          },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _preview(
                  pair.originalPath,
                  '原图',
                  _detail(pair.originalDimensions, pair.originalSize),
                  translated: false,
                  initialIndex: widget.plan.pairs.indexOf(pair),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward),
                ),
                _preview(
                  pair.translatedPath,
                  '翻译后',
                  _detail(pair.translatedDimensions, pair.translatedSize),
                  translated: true,
                  initialIndex: widget.plan.pairs.indexOf(pair),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnmatchedRow(TranslationUnmatchedFile item) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.warning_amber_outlined, color: Colors.orange),
        title: Text(
          '${item.isOriginal ? '原图' : '译图'}：${item.path.split(Platform.pathSeparator).last}',
        ),
        subtitle: Text(item.reason),
      ),
    );
  }

  Widget _preview(
    String filePath,
    String label,
    String detail, {
    required bool translated,
    required int initialIndex,
  }) {
    final gallery =
        widget.plan.pairs
            .map(
              (pair) => LocalImageViewerItem(
                imagePath: translated ? pair.translatedPath : pair.originalPath,
                title: label,
                subtitle:
                    'P${pair.image.part}\n${_detail(translated ? pair.translatedDimensions : pair.originalDimensions, translated ? pair.translatedSize : pair.originalSize)}',
              ),
            )
            .toList();
    return InkWell(
      onTap:
          () => LocalImageViewerPage.open(
            context,
            imagePath: filePath,
            title: label,
            subtitle: detail,
            gallery: gallery,
            initialIndex: initialIndex,
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

  String _detail(Size? size, int fileSize) {
    final dimensions =
        size == null ? '尺寸未知' : '${size.width.round()}×${size.height.round()}';
    return '$dimensions\n${fileSize.formatFileSize()}';
  }

  String _formatDelta(int delta) =>
      '${delta >= 0 ? '+' : '-'}${delta.abs().formatFileSize()}';
}
