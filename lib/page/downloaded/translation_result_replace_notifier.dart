import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pixez/utils/translation_result_replacer.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'translation_result_replace_notifier.freezed.dart';
part 'translation_result_replace_notifier.g.dart';

enum TranslationResultReplaceOperation {
  loading,
  idle,
  refreshing,
  cleaning,
  replacing,
}

/// 本次翻译结果预览弹窗使用的依赖和文件扫描入口。
///
/// 作为 provider family 参数传入，确保每个弹窗实例使用自己的请求配置。
class TranslationResultReplaceRequest {
  final Future<TranslationReplacementBatchPlan> Function() onLoad;
  final TranslationResultReplacer replacer;
  final Future<TranslationReplacementBatchPlan> Function() onRefresh;

  const TranslationResultReplaceRequest({
    required this.onLoad,
    required this.replacer,
    required this.onRefresh,
  });
}

@freezed
abstract class TranslationResultReplaceState
    with _$TranslationResultReplaceState {
  const factory TranslationResultReplaceState({
    TranslationReplacementBatchPlan? batchPlan,
    @Default(TranslationResultReplaceOperation.loading)
    TranslationResultReplaceOperation operation,
    Object? loadError,
    @Default(false) bool showSkippedOnly,
    @Default(<String>{}) Set<String> skippedOriginalPaths,
    @Default(<String>{}) Set<String> protectedOriginalPaths,
  }) = _TranslationResultReplaceState;
}

extension TranslationResultReplaceStateX on TranslationResultReplaceState {
  bool get operationBusy =>
      operation == TranslationResultReplaceOperation.refreshing ||
      operation == TranslationResultReplaceOperation.cleaning ||
      operation == TranslationResultReplaceOperation.replacing;

  bool get busy => operation != TranslationResultReplaceOperation.idle;

  int get replacementCount {
    final plan = batchPlan;
    if (plan == null) return 0;
    return (plan.pairCount -
            skippedOriginalPaths.difference(protectedOriginalPaths).length -
            protectedOriginalPaths.length)
        .clamp(0, plan.pairCount)
        .toInt();
  }

  int get skippedPairCount => skippedOriginalPaths.length;

  int get protectedPairCount => protectedOriginalPaths.length;

  int get untranslatablePairCount {
    final plan = batchPlan;
    if (plan == null) return 0;
    return plan.plans.fold(
      0,
      (total, item) =>
          total +
          item.pairs.where((pair) => pair.hasUntranslatableContent).length,
    );
  }

  int get totalSkippedPairCount => skippedPairCount + protectedPairCount;

  List<TranslationReplacementPlan> get visiblePlans {
    final plan = batchPlan;
    if (plan == null || !showSkippedOnly) {
      return plan?.plans ?? const <TranslationReplacementPlan>[];
    }
    return plan.plans
        .where(
          (item) => item.pairs.any(
            (pair) =>
                skippedOriginalPaths.contains(pair.originalPath) ||
                protectedOriginalPaths.contains(pair.originalPath),
          ),
        )
        .toList(growable: false);
  }

  bool isPairSkipped(String originalPath) =>
      skippedOriginalPaths.contains(originalPath);

  bool isPairProtected(String originalPath) =>
      protectedOriginalPaths.contains(originalPath);

  bool isPlanFullySkipped(TranslationReplacementPlan plan) {
    return plan.pairs.isNotEmpty &&
        plan.pairs.every(
          (pair) => skippedOriginalPaths.contains(pair.originalPath),
        );
  }
}

@riverpod
class TranslationResultReplace extends _$TranslationResultReplace {
  late TranslationResultReplaceRequest _request;

  @override
  TranslationResultReplaceState build(TranslationResultReplaceRequest request) {
    _request = request;
    return const TranslationResultReplaceState();
  }

  /// 加载初始计划。返回 null 表示失败，false 表示没有可替换结果。
  Future<bool?> load() async {
    state = state.copyWith(
      operation: TranslationResultReplaceOperation.loading,
      loadError: null,
    );
    try {
      final plan = await _request.onLoad();
      if (!ref.mounted) return null;
      if (plan.plans.isEmpty) {
        state = state.copyWith(
          batchPlan: plan,
          operation: TranslationResultReplaceOperation.idle,
        );
        return false;
      }
      state = _stateWithPlan(plan);
      return true;
    } catch (error) {
      if (!ref.mounted) return null;
      state = state.copyWith(
        operation: TranslationResultReplaceOperation.idle,
        loadError: error,
      );
      return null;
    }
  }

  Future<void> refresh() async {
    if (state.busy || state.batchPlan == null) return;
    state = state.copyWith(
      operation: TranslationResultReplaceOperation.refreshing,
    );
    try {
      final plan = await _request.onRefresh();
      if (!ref.mounted) return;
      state = _stateWithPlan(plan);
    } finally {
      if (ref.mounted &&
          state.operation == TranslationResultReplaceOperation.refreshing) {
        state = state.copyWith(
          operation: TranslationResultReplaceOperation.idle,
        );
      }
    }
  }

  void setShowSkippedOnly(bool value) {
    if (state.busy) return;
    state = state.copyWith(showSkippedOnly: value);
  }

  void setPairSkipped(String originalPath, bool skipped) {
    if (state.busy || state.isPairProtected(originalPath)) return;
    final paths = Set<String>.from(state.skippedOriginalPaths);
    if (skipped) {
      paths.add(originalPath);
    } else {
      paths.remove(originalPath);
    }
    state = state.copyWith(skippedOriginalPaths: Set.unmodifiable(paths));
  }

  void setPlanSkipped(TranslationReplacementPlan plan, bool skipped) {
    if (state.busy || plan.hasUntranslatableContent) return;
    final paths = Set<String>.from(state.skippedOriginalPaths);
    for (final pair in plan.pairs) {
      if (skipped) {
        paths.add(pair.originalPath);
      } else {
        paths.remove(pair.originalPath);
      }
    }
    state = state.copyWith(skippedOriginalPaths: Set.unmodifiable(paths));
  }

  Future<
    ({TranslationUntranslatableCleanupSummary summary, Object? refreshError})?
  >
  removeUntranslatableResults() async {
    final plan = state.batchPlan;
    if (state.busy || plan == null || state.untranslatablePairCount == 0) {
      return null;
    }
    state = state.copyWith(
      operation: TranslationResultReplaceOperation.cleaning,
    );
    try {
      final summary = await _request.replacer.removeUntranslatableResultsBatch(
        plan,
      );
      TranslationReplacementBatchPlan? refreshedPlan;
      Object? refreshError;
      try {
        refreshedPlan = await _request.onRefresh();
      } catch (error) {
        refreshError = error;
      }
      if (ref.mounted && refreshedPlan != null) {
        state = _stateWithPlan(refreshedPlan);
      }
      if (!ref.mounted) return null;
      return (summary: summary, refreshError: refreshError);
    } finally {
      if (ref.mounted &&
          state.operation == TranslationResultReplaceOperation.cleaning) {
        state = state.copyWith(
          operation: TranslationResultReplaceOperation.idle,
        );
      }
    }
  }

  Future<TranslationReplacementBatchSummary?> replaceOriginals() async {
    final plan = state.batchPlan;
    if (state.busy || plan == null || plan.pairCount == 0) return null;
    state = state.copyWith(
      operation: TranslationResultReplaceOperation.replacing,
    );
    try {
      return await _request.replacer.applyBatch(
        plan,
        skippedOriginalPaths: state.skippedOriginalPaths,
      );
    } finally {
      if (ref.mounted &&
          state.operation == TranslationResultReplaceOperation.replacing) {
        state = state.copyWith(
          operation: TranslationResultReplaceOperation.idle,
        );
      }
    }
  }

  TranslationResultReplaceState _stateWithPlan(
    TranslationReplacementBatchPlan plan,
  ) {
    final skipped = <String>{};
    final protected = <String>{};
    for (final item in plan.plans) {
      skipped.addAll(item.defaultSkippedOriginalPaths);
      if (item.hasUntranslatableContent) {
        protected.addAll(item.pairs.map((pair) => pair.originalPath));
      }
    }
    return state.copyWith(
      batchPlan: plan,
      operation: TranslationResultReplaceOperation.idle,
      loadError: null,
      skippedOriginalPaths: Set.unmodifiable(skipped),
      protectedOriginalPaths: Set.unmodifiable(protected),
    );
  }
}
