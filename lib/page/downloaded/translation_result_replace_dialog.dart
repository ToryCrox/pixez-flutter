import 'dart:io';

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
  static const _dialogInset = EdgeInsets.symmetric(
    horizontal: 48,
    vertical: 24,
  );
  static const _gridMaxCrossAxisExtent = 460.0;
  static const _gridSpacing = 8.0;

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
    final batchPlan = state.batchPlan;
    return PopScope(
      canPop: !state.operationBusy,
      child: Dialog(
        insetPadding: _dialogInset,
        constraints: const BoxConstraints.expand(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildHeader(state, batchPlan),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: _buildContent(state),
              ),
            ),
            _buildFooter(state),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    TranslationResultReplaceState state,
    TranslationReplacementBatchPlan? batchPlan,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              batchPlan == null
                  ? '翻译结果预览'
                  : '翻译结果预览（${batchPlan.plans.length} 个目录）',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (batchPlan != null && state.loadError == null) ...[
            FilterChip(
              label: Text('仅显示已跳过/保护 (${state.totalSkippedPairCount})'),
              selected: state.showSkippedOnly,
              visualDensity: VisualDensity.compact,
              onSelected:
                  state.busy
                      ? null
                      : (selected) => ref
                          .read(_provider.notifier)
                          .setShowSkippedOnly(selected),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: state.busy ? null : _refreshPlan,
              icon:
                  state.operation ==
                          TranslationResultReplaceOperation.refreshing
                      ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.refresh, size: 18),
              label: Text(
                state.operation == TranslationResultReplaceOperation.refreshing
                    ? '刷新中…'
                    : '刷新预览',
              ),
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            tooltip: '关闭',
            onPressed: state.operationBusy ? null : _close,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(TranslationResultReplaceState state) {
    final actions = _buildActions(state);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: _buildFooterStatus(state)),
          const SizedBox(width: 16),
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            actions[index],
          ],
        ],
      ),
    );
  }

  Widget _buildFooterStatus(TranslationResultReplaceState state) {
    final batchPlan = state.batchPlan;
    final text =
        state.loadError != null
            ? '翻译结果读取失败'
            : state.operation == TranslationResultReplaceOperation.loading
            ? '正在读取翻译结果…'
            : batchPlan == null
            ? ''
            : '共 ${batchPlan.pairCount} 张 · 已跳过 ${state.totalSkippedPairCount} 张 · '
                '待替换 ${state.replacementCount} 张';
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  List<Widget> _buildActions(TranslationResultReplaceState state) {
    if (state.loadError != null) {
      return [
        FilledButton.icon(
          onPressed: state.busy ? null : _loadPlan,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      ];
    }
    if (state.operation == TranslationResultReplaceOperation.loading) {
      return const [];
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: _buildSummaryStats(batchPlan, state),
        ),
        if (batchPlan.unmatchedCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '未匹配文件不会参与替换；每个目录的翻译结果全部处理完成后，对应结果目录会被清理。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
            ),
          ),
        Expanded(
          child:
              state.visiblePlans.isEmpty
                  ? Center(
                    child: Text(
                      state.showSkippedOnly ? '没有已跳过的图片' : '没有可显示的翻译结果',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                  : CustomScrollView(
                    slivers: [
                      for (
                        var index = 0;
                        index < state.visiblePlans.length;
                        index++
                      )
                        ..._buildPlanSlivers(
                          state.visiblePlans[index],
                          state,
                          first: index == 0,
                        ),
                    ],
                  ),
        ),
      ],
    );
  }

  Widget _buildSummaryStats(
    TranslationReplacementBatchPlan batchPlan,
    TranslationResultReplaceState state,
  ) {
    final protectedPaths = state.protectedOriginalPaths;
    final skippedCount =
        state.skippedOriginalPaths.difference(protectedPaths).length;
    final protectedCount = protectedPaths.length;
    final translatedCount =
        (batchPlan.pairCount - skippedCount - protectedCount)
            .clamp(0, batchPlan.pairCount)
            .toInt();
    final theme = Theme.of(context);

    return Wrap(
      spacing: 28,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildSummaryStat(
          icon: Icons.image_outlined,
          label: '总页数',
          value: batchPlan.pairCount,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        _buildSummaryStat(
          icon: Icons.check_circle_outline,
          label: '已翻译',
          value: translatedCount,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        _buildSummaryStat(
          icon: Icons.remove_circle_outline,
          label: '已跳过',
          value: skippedCount,
          color: Colors.orange.shade800,
        ),
        _buildSummaryStat(
          icon: Icons.shield_outlined,
          label: '已保护',
          value: protectedCount,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        _buildSummaryFileSize(batchPlan),
      ],
    );
  }

  Widget _buildSummaryFileSize(TranslationReplacementBatchPlan batchPlan) {
    final delta = batchPlan.translatedTotalSize - batchPlan.originalTotalSize;
    final deltaColor = delta > 0 ? Colors.orange.shade800 : Colors.green;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.storage_outlined,
          size: 20,
          color: textTheme.bodyMedium?.color,
        ),
        const SizedBox(width: 8),
        Text('文件大小', style: textTheme.bodyMedium),
        const SizedBox(width: 8),
        Text(
          '${batchPlan.originalTotalSize.formatFileSize()} → '
          '${batchPlan.translatedTotalSize.formatFileSize()}',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(width: 6),
        Text(
          '(${_formatDelta(delta)})',
          style: textTheme.bodySmall?.copyWith(color: deltaColor),
        ),
      ],
    );
  }

  Widget _buildSummaryStat({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(label, style: textTheme.bodyMedium),
        const SizedBox(width: 8),
        Text(
          '$value',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  List<Widget> _buildPlanSlivers(
    TranslationReplacementPlan plan,
    TranslationResultReplaceState state, {
    required bool first,
  }) {
    final visiblePairs = _visiblePairs(plan, state);
    final collapsed = state.isPlanCollapsed(plan);
    return [
      if (!first)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 4),
            child: Divider(height: 1),
          ),
        ),
      SliverToBoxAdapter(child: _buildPlanHeader(plan, state)),
      SliverToBoxAdapter(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child:
              collapsed
                  ? const SizedBox.shrink()
                  : _buildExpandedPlanContent(plan, visiblePairs, state),
        ),
      ),
    ];
  }

  Widget _buildExpandedPlanContent(
    TranslationReplacementPlan plan,
    List<TranslationReplacementPair> visiblePairs,
    TranslationResultReplaceState state,
  ) {
    final children = <Widget>[];
    if (visiblePairs.isNotEmpty) {
      children.add(
        GridView.builder(
          padding: const EdgeInsets.only(bottom: 12),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _gridMaxCrossAxisExtent,
            crossAxisSpacing: _gridSpacing,
            mainAxisSpacing: _gridSpacing,
            childAspectRatio: 1.75,
          ),
          itemCount: visiblePairs.length,
          itemBuilder:
              (context, index) =>
                  _buildPairCard(plan, visiblePairs[index], state),
        ),
      );
    }
    if (!state.showSkippedOnly) {
      children.addAll(
        plan.unmatched.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildUnmatchedRow(item),
          ),
        ),
      );
    }
    return Column(children: children);
  }

  List<TranslationReplacementPair> _visiblePairs(
    TranslationReplacementPlan plan,
    TranslationResultReplaceState state,
  ) {
    if (!state.showSkippedOnly) return plan.pairs;
    return plan.pairs
        .where(
          (pair) =>
              state.isPairSkipped(pair.originalPath) ||
              state.isPairProtected(pair.originalPath),
        )
        .toList(growable: false);
  }

  Widget _buildPlanHeader(
    TranslationReplacementPlan plan,
    TranslationResultReplaceState state,
  ) {
    final directoryName = path.basename(plan.workDirectory);
    final title = plan.illust.title.trim();
    final groupTitle = title.isEmpty ? directoryName : title;
    final visiblePairs = _visiblePairs(plan, state);
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
    final collapsed = state.isPlanCollapsed(plan);

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: InkWell(
              onTap:
                  state.busy
                      ? null
                      : () => ref
                          .read(_provider.notifier)
                          .togglePlanCollapsed(plan),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: const Icon(Icons.expand_more, size: 20),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.folder_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            groupTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.titleSmall?.copyWith(color: titleColor),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildPlanSkipControl(plan, state),
        ],
      ),
    );
  }

  Widget _buildPlanSkipControl(
    TranslationReplacementPlan plan,
    TranslationResultReplaceState state,
  ) {
    final protected = plan.hasUntranslatableContent;
    final selected = protected || state.isPlanFullySkipped(plan);
    final disabled = state.busy || protected;
    void setSkipped(bool value) {
      ref.read(_provider.notifier).setPlanSkipped(plan, value);
    }

    return InkWell(
      onTap: disabled ? null : () => setSkipped(!selected),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: disabled ? null : (value) => setSkipped(value == true),
            ),
            Text(protected ? '整部已保护' : '全部跳过'),
          ],
        ),
      ),
    );
  }

  Widget _buildPairCard(
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
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
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
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${_formatDelta(delta)}（${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(1)}%）',
                  maxLines: 1,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: deltaColor),
                ),
                const SizedBox(width: 6),
                _buildPairSkipControl(pair, state, isProtected),
              ],
            ),
            const SizedBox(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildPreviewTile(
                      plan: plan,
                      pair: pair,
                      filePath: pair.originalPath,
                      label: '原图',
                      translated: false,
                      initialIndex: initialIndex,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Expanded(
                    child: _buildPreviewTile(
                      plan: plan,
                      pair: pair,
                      filePath: pair.translatedPath,
                      label: '翻译后',
                      translated: true,
                      initialIndex: initialIndex,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPairSkipControl(
    TranslationReplacementPair pair,
    TranslationResultReplaceState state,
    bool isProtected,
  ) {
    final selected = isProtected || state.isPairSkipped(pair.originalPath);
    final disabled = state.busy || isProtected;
    void setSkipped(bool value) {
      ref.read(_provider.notifier).setPairSkipped(pair.originalPath, value);
    }

    return InkWell(
      onTap: disabled ? null : () => setSkipped(!selected),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: disabled ? null : (value) => setSkipped(value == true),
            ),
            Text(isProtected ? '整部保护' : '跳过'),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewTile({
    required TranslationReplacementPlan plan,
    required TranslationReplacementPair pair,
    required String filePath,
    required String label,
    required bool translated,
    required int initialIndex,
  }) {
    final detail =
        translated
            ? _compactDetail(pair.translatedDimensions, pair.translatedSize)
            : _compactDetail(pair.originalDimensions, pair.originalSize);
    return InkWell(
      onTap:
          () =>
              _openPairViewer(plan, filePath, label, translated, initialIndex),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: label,
                style: Theme.of(context).textTheme.labelMedium,
                children:
                    pair.defaultSkipped && translated
                        ? [
                          TextSpan(
                            text: ' · 默认跳过',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: Colors.orange.shade800),
                          ),
                        ]
                        : const [],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: SizedBox.expand(
                    child: Image.file(
                      File(filePath),
                      fit: BoxFit.cover,
                      errorBuilder:
                          (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  void _openPairViewer(
    TranslationReplacementPlan plan,
    String filePath,
    String label,
    bool translated,
    int initialIndex,
  ) {
    final originalDetail = _detail(
      plan.pairs[initialIndex].originalDimensions,
      plan.pairs[initialIndex].originalSize,
    );
    final translatedDetail = _detail(
      plan.pairs[initialIndex].translatedDimensions,
      plan.pairs[initialIndex].translatedSize,
    );
    LocalImageViewerPage.open(
      context,
      imagePath: filePath,
      title: label,
      subtitle: translated ? translatedDetail : originalDetail,
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

  String _compactDetail(Size? size, int fileSize) {
    final dimensions =
        size == null ? '尺寸未知' : '${size.width.round()}×${size.height.round()}';
    return '$dimensions · ${fileSize.formatFileSize()}';
  }

  String _formatDelta(int delta) =>
      '${delta >= 0 ? '+' : '-'}${delta.abs().formatFileSize()}';
}
