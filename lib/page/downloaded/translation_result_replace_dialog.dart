import 'dart:io';
import 'dart:math' as math;

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:pixez/exts.dart';
import 'package:pixez/page/downloaded/local_image_viewer_page.dart';
import 'package:pixez/utils/translation_result_replacer.dart';

/// 预览多个作品的翻译结果，并在确认后批量替换下载原图。
class TranslationResultReplaceDialog extends StatefulWidget {
  final TranslationReplacementBatchPlan batchPlan;
  final TranslationResultReplacer replacer;
  final Future<void> Function(TranslationReplacementBatchSummary) onReplaced;

  const TranslationResultReplaceDialog({
    super.key,
    required this.batchPlan,
    required this.replacer,
    required this.onReplaced,
  });

  static Future<void> show(
    BuildContext context, {
    required TranslationReplacementBatchPlan batchPlan,
    required TranslationResultReplacer replacer,
    required Future<void> Function(TranslationReplacementBatchSummary)
    onReplaced,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => TranslationResultReplaceDialog(
            batchPlan: batchPlan,
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
  static const _dialogWidth = 1200.0;
  static const _dialogHeight = 800.0;
  static const _thumbnailExtent = 67.2;
  var _replacing = false;
  var _showSkippedOnly = false;
  final Set<String> _skippedOriginalPaths = <String>{};
  final Set<String> _protectedOriginalPaths = <String>{};

  @override
  void initState() {
    super.initState();
    for (final plan in widget.batchPlan.plans) {
      _skippedOriginalPaths.addAll(plan.defaultSkippedOriginalPaths);
      if (plan.hasUntranslatableContent) {
        _protectedOriginalPaths.addAll(
          plan.pairs.map((pair) => pair.originalPath),
        );
      }
    }
  }

  int get _replacementCount =>
      widget.batchPlan.pairCount -
      _skippedOriginalPaths.length -
      _protectedOriginalPaths.length;

  int get _skippedPairCount => _skippedOriginalPaths.length;
  int get _protectedPairCount => _protectedOriginalPaths.length;
  int get _totalSkippedPairCount => _skippedPairCount + _protectedPairCount;

  List<TranslationReplacementPlan> get _visiblePlans {
    if (!_showSkippedOnly) return widget.batchPlan.plans;
    return widget.batchPlan.plans
        .where(
          (plan) => plan.pairs.any(
            (pair) =>
                _skippedOriginalPaths.contains(pair.originalPath) ||
                _protectedOriginalPaths.contains(pair.originalPath),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _replaceOriginals() async {
    if (_replacing || widget.batchPlan.pairCount == 0) return;
    setState(() => _replacing = true);

    try {
      final summary = await widget.replacer.applyBatch(
        widget.batchPlan,
        skippedOriginalPaths: _skippedOriginalPaths,
      );
      for (final item in summary.items) {
        for (final result
            in item.summary?.results.where((result) => result.isSuccess) ??
                const <TranslationReplacementResult>[]) {
          final pair = result.pair;
          await FileImage(File(pair.originalPath)).evict();
          await FileImage(File(pair.translatedPath)).evict();
          await FileImage(File(pair.destinationPath)).evict();
        }
        for (final pair in item.plan.pairs.where(
          (pair) => _skippedOriginalPaths.contains(pair.originalPath),
        )) {
          await FileImage(File(pair.translatedPath)).evict();
        }
      }

      if (!mounted) return;
      await widget.onReplaced(summary);
      if (!mounted) return;

      final cleanedCount =
          summary.items
              .where((item) => item.translationResultDirectoriesCleaned)
              .length;
      final cleanupText = cleanedCount == 0 ? '' : '，已清理 $cleanedCount 个翻译结果目录';
      final protectedText =
          summary.protectedPlanCount == 0
              ? ''
              : '，整部跳过 ${summary.protectedPlanCount} 个插画';
      final manuallySkippedCount =
          summary.skippedCount - summary.protectedPageCount;
      final skippedText =
          manuallySkippedCount == 0 ? '' : '，跳过 $manuallySkippedCount 张';
      final failedPlanText =
          summary.failedPlanCount == 0
              ? ''
              : '，${summary.failedPlanCount} 个目录处理失败';
      final failureText =
          summary.failureCount == 0 ? '' : '，${summary.failureCount} 张替换失败';
      BotToast.showText(
        text:
            '已替换 ${summary.successCount} 张图片$failureText$failedPlanText'
            '$skippedText$protectedText$cleanupText',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _replacing = false);
      BotToast.showText(text: '批量替换失败：$e');
    }
  }

  void _close() {
    if (!_replacing) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final contentWidth = math.min(_dialogWidth, screenSize.width - 80);
    final contentHeight = math.min(_dialogHeight, screenSize.height - 160);
    return PopScope(
      canPop: !_replacing,
      child: AlertDialog(
        title: Text('翻译结果预览（${widget.batchPlan.plans.length} 个目录）'),
        content: SizedBox(
          width: contentWidth,
          height: contentHeight,
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
            label: Text(_replacing ? '正在替换…' : '替换原图（$_replacementCount）'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final delta =
        widget.batchPlan.translatedTotalSize -
        widget.batchPlan.originalTotalSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '选中 ${widget.batchPlan.selectedCount} 个目录，发现 '
                '${widget.batchPlan.plans.length} 个可替换目录；共匹配 '
                '${widget.batchPlan.pairCount} 张；总大小 '
                '${widget.batchPlan.originalTotalSize.formatFileSize()} → '
                '${widget.batchPlan.translatedTotalSize.formatFileSize()}（${_formatDelta(delta)}）'
                '${widget.batchPlan.noResultCount == 0 ? '' : '；无结果 ${widget.batchPlan.noResultCount} 个目录'}'
                '${widget.batchPlan.unmatchedCount == 0 ? '' : '；未匹配 ${widget.batchPlan.unmatchedCount} 项'}'
                '${_skippedPairCount == 0 ? '' : '；已跳过 $_skippedPairCount 张'}'
                '${_protectedPairCount == 0 ? '' : '；已保护 $_protectedPairCount 张'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text('仅显示已跳过/保护 ($_totalSkippedPairCount)'),
              selected: _showSkippedOnly,
              onSelected:
                  _replacing
                      ? null
                      : (selected) =>
                          setState(() => _showSkippedOnly = selected),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.batchPlan.unmatchedCount > 0)
          Text(
            '未匹配文件不会参与替换；每个目录的翻译结果全部处理完成后，对应结果目录会被清理。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
          ),
        if (widget.batchPlan.unmatchedCount > 0) const SizedBox(height: 8),
        Expanded(
          child:
              _visiblePlans.isEmpty
                  ? Center(
                    child: Text(
                      _showSkippedOnly ? '没有已跳过的图片' : '没有可显示的翻译结果',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                  : ListView.separated(
                    itemCount: _visiblePlans.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder:
                        (context, index) =>
                            _buildPlanGroup(_visiblePlans[index]),
                  ),
        ),
      ],
    );
  }

  void _setSkipped(String originalPath, bool skipped) {
    if (_replacing || _protectedOriginalPaths.contains(originalPath)) return;
    setState(() {
      if (skipped) {
        _skippedOriginalPaths.add(originalPath);
      } else {
        _skippedOriginalPaths.remove(originalPath);
      }
    });
  }

  bool _isPlanFullySkipped(TranslationReplacementPlan plan) {
    return plan.pairs.isNotEmpty &&
        plan.pairs.every(
          (pair) => _skippedOriginalPaths.contains(pair.originalPath),
        );
  }

  void _setPlanSkipped(TranslationReplacementPlan plan, bool skipped) {
    if (_replacing || plan.hasUntranslatableContent) return;
    setState(() {
      for (final pair in plan.pairs) {
        if (skipped) {
          _skippedOriginalPaths.add(pair.originalPath);
        } else {
          _skippedOriginalPaths.remove(pair.originalPath);
        }
      }
    });
  }

  Widget _buildPlanGroup(TranslationReplacementPlan plan) {
    final directoryName = path.basename(plan.workDirectory);
    final title = plan.illust.title.trim();
    final groupTitle = title.isEmpty ? directoryName : title;
    final visiblePairs =
        _showSkippedOnly
            ? plan.pairs
                .where(
                  (pair) =>
                      _skippedOriginalPaths.contains(pair.originalPath) ||
                      _protectedOriginalPaths.contains(pair.originalPath),
                )
                .toList(growable: false)
            : plan.pairs;
    final subtitle =
        _showSkippedOnly
            ? '$directoryName · ${visiblePairs.length} 张已跳过/保护'
            : '$directoryName · ${plan.pairs.length} 张匹配'
                '${plan.unmatched.isEmpty ? '' : ' · ${plan.unmatched.length} 项未匹配'}'
                '${plan.hasUntranslatableContent ? ' · 存在无法翻译内容，本次整部插画已跳过' : ''}';
    final titleColor =
        plan.hasUntranslatableContent
            ? Theme.of(context).colorScheme.error
            : null;

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(
              child: Text(groupTitle, style: TextStyle(color: titleColor)),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text(plan.hasUntranslatableContent ? '整部已保护' : '全部跳过'),
              selected:
                  plan.hasUntranslatableContent || _isPlanFullySkipped(plan),
              onSelected:
                  _replacing || plan.hasUntranslatableContent
                      ? null
                      : (selected) => _setPlanSkipped(plan, selected),
            ),
          ],
        ),
        subtitle: Text(subtitle),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        children: [
          for (final pair in visiblePairs) _buildPairRow(plan, pair),
          if (!_showSkippedOnly)
            for (final item in plan.unmatched) _buildUnmatchedRow(item),
        ],
      ),
    );
  }

  Widget _buildPairRow(
    TranslationReplacementPlan plan,
    TranslationReplacementPair pair,
  ) {
    final delta = pair.translatedSize - pair.originalSize;
    final ratio = pair.originalSize == 0 ? 0 : delta / pair.originalSize * 100;
    final deltaColor = delta > 0 ? Colors.orange : Colors.green;
    final initialIndex = plan.pairs.indexOf(pair);
    final isProtected = plan.hasUntranslatableContent;
    final titleColor =
        pair.hasUntranslatableContent
            ? Theme.of(context).colorScheme.error
            : null;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'P${pair.image.part} · ${pair.baseName}',
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: titleColor),
                      children: [
                        if (pair.hasUntranslatableContent)
                          TextSpan(
                            text: ' · 包含无法翻译内容',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (pair.defaultSkipped &&
                            pair.defaultSkipReason != null)
                          TextSpan(
                            text: ' · ${pair.defaultSkipReason}',
                            style: TextStyle(color: Colors.orange.shade800),
                          ),
                      ],
                    ),
                  ),
                ),
                Text(
                  '${_formatDelta(delta)}（${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(1)}%）',
                  style: TextStyle(color: deltaColor),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap:
                      _replacing || isProtected
                          ? null
                          : () => _setSkipped(
                            pair.originalPath,
                            !_skippedOriginalPaths.contains(pair.originalPath),
                          ),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(isProtected ? '整部保护' : '跳过'),
                  ),
                ),
                Checkbox(
                  value:
                      isProtected ||
                      _skippedOriginalPaths.contains(pair.originalPath),
                  onChanged:
                      _replacing || isProtected
                          ? null
                          : (value) =>
                              _setSkipped(pair.originalPath, value == true),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _preview(
                    plan,
                    pair.originalPath,
                    '原图',
                    _detail(pair.originalDimensions, pair.originalSize),
                    translated: false,
                    initialIndex: initialIndex,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward),
                ),
                Expanded(
                  child: _preview(
                    plan,
                    pair.translatedPath,
                    '翻译后',
                    _detail(pair.translatedDimensions, pair.translatedSize),
                    translated: true,
                    initialIndex: initialIndex,
                  ),
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
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_outlined, color: Colors.orange),
        title: Text(
          '${item.isOriginal ? '原图' : '译图'}：${path.basename(item.path)}',
        ),
        subtitle: Text(item.reason),
      ),
    );
  }

  Widget _preview(
    TranslationReplacementPlan plan,
    String filePath,
    String label,
    String detail, {
    required bool translated,
    required int initialIndex,
  }) {
    final gallery =
        plan.pairs.map((pair) {
          final originalDetail = _detail(
            pair.originalDimensions,
            pair.originalSize,
          );
          final translatedDetail = _detail(
            pair.translatedDimensions,
            pair.translatedSize,
          );
          return LocalImageViewerItem(
            imagePath: translated ? pair.translatedPath : pair.originalPath,
            title: translated ? '翻译后' : '原图',
            subtitle:
                'P${pair.image.part}\n${translated ? translatedDetail : originalDetail}',
            comparison: LocalImageViewerComparison(
              leftImagePath: pair.originalPath,
              rightImagePath: pair.translatedPath,
              leftTitle: '原图',
              rightTitle: '翻译后',
              leftSubtitle: 'P${pair.image.part}\n$originalDetail',
              rightSubtitle: 'P${pair.image.part}\n$translatedDetail',
            ),
          );
        }).toList();
    final originalDetail = _detail(
      plan.pairs[initialIndex].originalDimensions,
      plan.pairs[initialIndex].originalSize,
    );
    final translatedDetail = _detail(
      plan.pairs[initialIndex].translatedDimensions,
      plan.pairs[initialIndex].translatedSize,
    );
    return InkWell(
      onTap:
          () => LocalImageViewerPage.open(
            context,
            imagePath: filePath,
            title: label,
            subtitle: detail,
            gallery: gallery,
            initialIndex: initialIndex,
            comparison: LocalImageViewerComparison(
              leftImagePath: plan.pairs[initialIndex].originalPath,
              rightImagePath: plan.pairs[initialIndex].translatedPath,
              leftTitle: '原图',
              rightTitle: '翻译后',
              leftSubtitle:
                  'P${plan.pairs[initialIndex].image.part}\n$originalDetail',
              rightSubtitle:
                  'P${plan.pairs[initialIndex].image.part}\n$translatedDetail',
            ),
            bottomBuilder: (context, _, index) {
              final currentPair = plan.pairs[index];
              final protected = plan.hasUntranslatableContent;
              var skipped =
                  protected ||
                  _skippedOriginalPaths.contains(currentPair.originalPath);
              return StatefulBuilder(
                builder: (context, setLocalState) {
                  return _buildViewerSkipControl(
                    skipped: skipped,
                    protected: protected,
                    onChanged: (value) {
                      if (protected) return;
                      _setSkipped(currentPair.originalPath, value);
                      setLocalState(() => skipped = value);
                    },
                  );
                },
              );
            },
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

  Widget _buildViewerSkipControl({
    required bool skipped,
    required bool protected,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            protected
                ? '当前插画：含无法翻译内容，已保护'
                : skipped
                ? '当前图片：跳过替换'
                : '当前图片：将替换',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Checkbox(
            value: skipped,
            activeColor: Colors.orange,
            onChanged: protected ? null : (value) => onChanged(value == true),
          ),
        ],
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
