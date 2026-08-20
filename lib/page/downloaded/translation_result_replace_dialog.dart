import 'dart:io';
import 'dart:math' as math;

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pixez/exts.dart';
import 'package:pixez/page/downloaded/local_image_viewer_page.dart';
import 'package:pixez/page/downloaded/translation_result_replace_notifier.dart';
import 'package:pixez/utils/translation_result_replacer.dart';

/// 预览多个作品的翻译结果，并在确认后批量替换下载原图。
class TranslationResultReplaceDialog extends ConsumerStatefulWidget {
  final TranslationResultReplaceRequest request;
  final Future<void> Function(TranslationReplacementBatchSummary) onReplaced;

  const TranslationResultReplaceDialog({
    super.key,
    required this.request,
    required this.onReplaced,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Future<TranslationReplacementBatchPlan> Function() onLoad,
    required TranslationResultReplacer replacer,
    required Future<TranslationReplacementBatchPlan> Function() onRefresh,
    required Future<void> Function(TranslationReplacementBatchSummary)
    onReplaced,
  }) {
    final request = TranslationResultReplaceRequest(
      onLoad: onLoad,
      replacer: replacer,
      onRefresh: onRefresh,
    );
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder:
          (_) => TranslationResultReplaceDialog(
            request: request,
            onReplaced: onReplaced,
          ),
    );
  }

  @override
  ConsumerState<TranslationResultReplaceDialog> createState() =>
      _TranslationResultReplaceDialogState();
}

class _TranslationResultReplaceDialogState
    extends ConsumerState<TranslationResultReplaceDialog> {
  static const _dialogWidth = 1200.0;
  static const _dialogHeight = 800.0;
  static const _thumbnailExtent = 67.2;

  TranslationResultReplaceProvider get _provider =>
      translationResultReplaceProvider(widget.request);

  @override
  void initState() {
    super.initState();
    // 等弹框完成首帧绘制后再开始扫描文件，确保用户先看到 loading。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPlan();
    });
  }

  Future<void> _loadPlan() async {
    if (!mounted) return;
    final result = await ref.read(_provider.notifier).load();
    if (!mounted || result != false) return;
    Navigator.of(context).pop(false);
  }

  Future<void> _refreshPlan() async {
    final state = ref.read(_provider);
    if (state.busy || state.batchPlan == null) return;
    try {
      await ref.read(_provider.notifier).refresh();
      if (!mounted) return;
      BotToast.showText(text: '翻译结果预览已刷新');
    } catch (error) {
      if (!mounted) return;
      BotToast.showText(text: '刷新翻译结果失败：$error');
    }
  }

  Future<bool> _confirmRemoveUntranslatableResults() {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('删除拒译结果？'),
            content: Text(
              '将删除 ${ref.read(_provider).untranslatablePairCount} 个拒译页面的输出图片、'
              'translations.json、inpainted 图片和 translation_map.json 记录。'
              '\n\n原图不会被删除。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('删除'),
              ),
            ],
          ),
    ).then((value) => value == true);
  }

  Future<void> _removeUntranslatableResults() async {
    final state = ref.read(_provider);
    final batchPlan = state.batchPlan;
    if (state.busy || batchPlan == null || state.untranslatablePairCount == 0) {
      return;
    }
    if (!await _confirmRemoveUntranslatableResults() || !mounted) return;

    try {
      final outcome =
          await ref.read(_provider.notifier).removeUntranslatableResults();
      if (!mounted || outcome == null) return;
      for (final plan in batchPlan.plans) {
        for (final pair in plan.pairs.where(
          (pair) => pair.hasUntranslatableContent,
        )) {
          await FileImage(File(pair.translatedPath)).evict();
        }
      }

      final summary = outcome.summary;
      final refreshError = outcome.refreshError;
      final errorCount = summary.errors.length + (refreshError == null ? 0 : 1);
      final errorText =
          errorCount == 0
              ? ''
              : '，失败 $errorCount 项${refreshError == null ? '' : '（刷新失败：$refreshError）'}';
      BotToast.showText(
        text:
            '已清理 ${summary.deletedPairCount} 个拒译页面、'
            '${summary.deletedFileCount} 个文件，'
            '移除 ${summary.removedTranslationMapEntryCount} 条映射$errorText',
      );
    } catch (error) {
      if (!mounted) return;
      BotToast.showText(text: '清理拒译结果失败：$error');
    }
  }

  Future<void> _replaceOriginals() async {
    final state = ref.read(_provider);
    final batchPlan = state.batchPlan;
    if (state.busy || batchPlan == null || batchPlan.pairCount == 0) return;
    final skippedOriginalPaths = state.skippedOriginalPaths;

    try {
      final summary = await ref.read(_provider.notifier).replaceOriginals();
      if (!mounted || summary == null) return;
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
          (pair) => skippedOriginalPaths.contains(pair.originalPath),
        )) {
          await FileImage(File(pair.translatedPath)).evict();
        }
      }

      try {
        await widget.onReplaced(summary);
      } catch (error) {
        if (!mounted) return;
        BotToast.showText(text: '替换已完成，但刷新下载列表失败：$error');
        return;
      }
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
    } catch (error) {
      if (!mounted) return;
      BotToast.showText(text: '批量替换失败：$error');
    }
  }

  void _close() {
    if (!ref.read(_provider).operationBusy) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final screenSize = MediaQuery.sizeOf(context);
    final contentWidth = math.min(_dialogWidth, screenSize.width - 80);
    final contentHeight = math.min(_dialogHeight, screenSize.height - 160);
    final batchPlan = state.batchPlan;
    return PopScope(
      canPop: !state.operationBusy,
      child: AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(
                batchPlan == null
                    ? '翻译结果预览'
                    : '翻译结果预览（${batchPlan.plans.length} 个目录）',
              ),
            ),
            if (batchPlan != null && state.loadError == null)
              IconButton(
                tooltip:
                    state.operation ==
                            TranslationResultReplaceOperation.refreshing
                        ? '刷新中…'
                        : '刷新预览',
                onPressed: state.busy ? null : _refreshPlan,
                icon:
                    state.operation ==
                            TranslationResultReplaceOperation.refreshing
                        ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.refresh),
              ),
          ],
        ),
        content: SizedBox(
          width: contentWidth,
          height: contentHeight,
          child: _buildContent(state),
        ),
        actions: _buildActions(state),
      ),
    );
  }

  List<Widget> _buildActions(TranslationResultReplaceState state) {
    if (state.loadError != null) {
      return [
        TextButton(onPressed: _close, child: const Text('取消')),
        FilledButton.icon(
          onPressed: state.busy ? null : _loadPlan,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      ];
    }
    if (state.operation == TranslationResultReplaceOperation.loading) {
      return [TextButton(onPressed: _close, child: const Text('取消'))];
    }
    return [
      if (state.untranslatablePairCount > 0)
        OutlinedButton.icon(
          onPressed: state.busy ? null : _removeUntranslatableResults,
          icon:
              state.operation == TranslationResultReplaceOperation.cleaning
                  ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.delete_sweep_outlined),
          label: Text(
            state.operation == TranslationResultReplaceOperation.cleaning
                ? '正在清理…'
                : '删除拒译结果（${state.untranslatablePairCount}）',
          ),
        ),
      TextButton(
        onPressed: state.operationBusy ? null : _close,
        child: const Text('取消'),
      ),
      FilledButton.icon(
        onPressed: state.busy ? null : _replaceOriginals,
        icon:
            state.operation == TranslationResultReplaceOperation.replacing
                ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Icon(Icons.swap_horiz),
        label: Text(
          state.operation == TranslationResultReplaceOperation.replacing
              ? '正在替换…'
              : '替换原图（${state.replacementCount}）',
        ),
      ),
    ];
  }

  Widget _buildContent(TranslationResultReplaceState state) {
    if (state.operation == TranslationResultReplaceOperation.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在读取翻译结果…'),
          ],
        ),
      );
    }
    final loadError = state.loadError;
    if (loadError != null) {
      return Center(
        child: Text('读取翻译结果失败：$loadError', textAlign: TextAlign.center),
      );
    }
    final batchPlan = state.batchPlan;
    if (batchPlan == null) return const SizedBox.shrink();

    final delta = batchPlan.translatedTotalSize - batchPlan.originalTotalSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '选中 ${batchPlan.selectedCount} 个目录，发现 '
                '${batchPlan.plans.length} 个可替换目录；共匹配 '
                '${batchPlan.pairCount} 张；总大小 '
                '${batchPlan.originalTotalSize.formatFileSize()} → '
                '${batchPlan.translatedTotalSize.formatFileSize()}（${_formatDelta(delta)}）'
                '${batchPlan.noResultCount == 0 ? '' : '；无结果 ${batchPlan.noResultCount} 个目录'}'
                '${batchPlan.unmatchedCount == 0 ? '' : '；未匹配 ${batchPlan.unmatchedCount} 项'}'
                '${state.skippedPairCount == 0 ? '' : '；已跳过 ${state.skippedPairCount} 张'}'
                '${state.protectedPairCount == 0 ? '' : '；已保护 ${state.protectedPairCount} 张'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text('仅显示已跳过/保护 (${state.totalSkippedPairCount})'),
              selected: state.showSkippedOnly,
              onSelected:
                  state.busy
                      ? null
                      : (selected) => ref
                          .read(_provider.notifier)
                          .setShowSkippedOnly(selected),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (batchPlan.unmatchedCount > 0)
          Text(
            '未匹配文件不会参与替换；每个目录的翻译结果全部处理完成后，对应结果目录会被清理。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
          ),
        if (batchPlan.unmatchedCount > 0) const SizedBox(height: 8),
        Expanded(
          child:
              state.visiblePlans.isEmpty
                  ? Center(
                    child: Text(
                      state.showSkippedOnly ? '没有已跳过的图片' : '没有可显示的翻译结果',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                  : ListView.separated(
                    itemCount: state.visiblePlans.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder:
                        (context, index) =>
                            _buildPlanGroup(state.visiblePlans[index], state),
                  ),
        ),
      ],
    );
  }

  Widget _buildPlanGroup(
    TranslationReplacementPlan plan,
    TranslationResultReplaceState state,
  ) {
    final directoryName = path.basename(plan.workDirectory);
    final title = plan.illust.title.trim();
    final groupTitle = title.isEmpty ? directoryName : title;
    final visiblePairs =
        state.showSkippedOnly
            ? plan.pairs
                .where(
                  (pair) =>
                      state.isPairSkipped(pair.originalPath) ||
                      state.isPairProtected(pair.originalPath),
                )
                .toList(growable: false)
            : plan.pairs;
    final subtitle =
        state.showSkippedOnly
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
                  plan.hasUntranslatableContent ||
                  state.isPlanFullySkipped(plan),
              onSelected:
                  state.busy || plan.hasUntranslatableContent
                      ? null
                      : (selected) => ref
                          .read(_provider.notifier)
                          .setPlanSkipped(plan, selected),
            ),
          ],
        ),
        subtitle: Text(subtitle),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        children: [
          for (final pair in visiblePairs) _buildPairRow(plan, pair, state),
          if (!state.showSkippedOnly)
            for (final item in plan.unmatched) _buildUnmatchedRow(item),
        ],
      ),
    );
  }

  Widget _buildPairRow(
    TranslationReplacementPlan plan,
    TranslationReplacementPair pair,
    TranslationResultReplaceState state,
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
                      state.busy || isProtected
                          ? null
                          : () => ref
                              .read(_provider.notifier)
                              .setPairSkipped(
                                pair.originalPath,
                                !state.isPairSkipped(pair.originalPath),
                              ),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(isProtected ? '整部保护' : '跳过'),
                  ),
                ),
                Checkbox(
                  value: isProtected || state.isPairSkipped(pair.originalPath),
                  onChanged:
                      state.busy || isProtected
                          ? null
                          : (value) => ref
                              .read(_provider.notifier)
                              .setPairSkipped(pair.originalPath, value == true),
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
            gallery: _buildGallery(plan, translated),
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
                  ref.read(_provider).isPairSkipped(currentPair.originalPath);
              return StatefulBuilder(
                builder: (context, setLocalState) {
                  return _buildViewerSkipControl(
                    skipped: skipped,
                    protected: protected,
                    onChanged: (value) {
                      if (protected) return;
                      ref
                          .read(_provider.notifier)
                          .setPairSkipped(currentPair.originalPath, value);
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

  List<LocalImageViewerItem> _buildGallery(
    TranslationReplacementPlan plan,
    bool translated,
  ) {
    return plan.pairs
        .map((pair) {
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
        })
        .toList(growable: false);
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
