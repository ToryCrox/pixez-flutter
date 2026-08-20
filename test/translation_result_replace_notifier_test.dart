import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/translation_result_replace_notifier.dart';
import 'package:pixez/utils/translation_result_replacer.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  late _FakeReplacer replacer;

  setUp(() {
    replacer = _FakeReplacer();
  });

  test('加载计划后初始化默认跳过和整部保护状态', () async {
    final normalPlan = _plan(id: 1, defaultSkipped: true);
    final protectedPlan = _plan(id: 2, protected: true);
    final batchPlan = _batchPlan([normalPlan, protectedPlan]);
    final harness = _createContainer(
      replacer: replacer,
      load: () async => batchPlan,
      refresh: () async => batchPlan,
    );
    final container = harness.container;
    final provider = translationResultReplaceProvider(harness.request);
    addTearDown(container.dispose);

    final loaded = await container.read(provider.notifier).load();
    final state = container.read(provider);

    expect(loaded, isTrue);
    expect(state.operation, TranslationResultReplaceOperation.idle);
    expect(state.skippedPairCount, 1);
    expect(state.protectedPairCount, 1);
    expect(state.untranslatablePairCount, 1);
    expect(state.replacementCount, 0);
  });

  test('初始计划为空时返回 false 并保持可关闭状态', () async {
    final harness = _createContainer(
      replacer: replacer,
      load:
          () async => const TranslationReplacementBatchPlan(
            selectedCount: 2,
            plans: [],
          ),
      refresh: () async => throw StateError('不会调用刷新'),
    );
    final container = harness.container;
    final provider = translationResultReplaceProvider(harness.request);
    addTearDown(container.dispose);

    final loaded = await container.read(provider.notifier).load();
    final state = container.read(provider);

    expect(loaded, isFalse);
    expect(state.operation, TranslationResultReplaceOperation.idle);
    expect(state.loadError, isNull);
  });

  test('刷新失败后恢复 idle 并保留原计划', () async {
    final batchPlan = _batchPlan([_plan(id: 1)]);
    final harness = _createContainer(
      replacer: replacer,
      load: () async => batchPlan,
      refresh: () async => throw StateError('刷新失败'),
    );
    final container = harness.container;
    final provider = translationResultReplaceProvider(harness.request);
    addTearDown(container.dispose);
    final notifier = container.read(provider.notifier);
    await notifier.load();

    await expectLater(notifier.refresh(), throwsStateError);
    final state = container.read(provider);

    expect(state.operation, TranslationResultReplaceOperation.idle);
    expect(state.batchPlan, same(batchPlan));
  });

  test('替换异常后恢复 idle', () async {
    final batchPlan = _batchPlan([_plan(id: 1)]);
    replacer.applyError = StateError('替换失败');
    final harness = _createContainer(
      replacer: replacer,
      load: () async => batchPlan,
      refresh: () async => batchPlan,
    );
    final container = harness.container;
    final provider = translationResultReplaceProvider(harness.request);
    addTearDown(container.dispose);
    final notifier = container.read(provider.notifier);
    await notifier.load();

    await expectLater(notifier.replaceOriginals(), throwsStateError);

    expect(
      container.read(provider).operation,
      TranslationResultReplaceOperation.idle,
    );
  });

  test('可以切换单图和整部跳过状态', () async {
    final plan = _plan(id: 1);
    final batchPlan = _batchPlan([plan]);
    final harness = _createContainer(
      replacer: replacer,
      load: () async => batchPlan,
      refresh: () async => batchPlan,
    );
    final container = harness.container;
    final provider = translationResultReplaceProvider(harness.request);
    addTearDown(container.dispose);
    final notifier = container.read(provider.notifier);
    await notifier.load();

    notifier.setPairSkipped('/original/1.jpg', true);
    expect(container.read(provider).replacementCount, 0);

    notifier.setPairSkipped('/original/1.jpg', false);
    notifier.setPlanSkipped(plan, true);
    expect(container.read(provider).isPlanFullySkipped(plan), isTrue);

    expect(container.read(provider).isPlanCollapsed(plan), isFalse);
    notifier.togglePlanCollapsed(plan);
    expect(container.read(provider).isPlanCollapsed(plan), isTrue);
    notifier.togglePlanCollapsed(plan);
    expect(container.read(provider).isPlanCollapsed(plan), isFalse);
  });
}

({ProviderContainer container, TranslationResultReplaceRequest request})
_createContainer({
  required _FakeReplacer replacer,
  required Future<TranslationReplacementBatchPlan> Function() load,
  required Future<TranslationReplacementBatchPlan> Function() refresh,
}) {
  final request = TranslationResultReplaceRequest(
    onLoad: load,
    replacer: replacer,
    onRefresh: refresh,
  );
  final container = ProviderContainer();
  container.listen(translationResultReplaceProvider(request), (_, _) {});
  return (container: container, request: request);
}

TranslationReplacementBatchPlan _batchPlan(
  List<TranslationReplacementPlan> plans,
) {
  return TranslationReplacementBatchPlan(
    selectedCount: plans.length,
    plans: plans,
  );
}

TranslationReplacementPlan _plan({
  required int id,
  bool defaultSkipped = false,
  bool protected = false,
}) {
  final originalPath = '/original/$id.jpg';
  final pair = TranslationReplacementPair(
    image: DownloadedImage(
      illustId: id,
      part: 0,
      fileName: '$id',
      extension: '.jpg',
      fileSize: 100,
      originalUrl: '',
      width: 10,
      height: 10,
    ),
    originalPath: originalPath,
    translatedPath: '/translated/$id.jpg',
    originalSize: 100,
    translatedSize: 100,
    originalDimensions: null,
    translatedDimensions: null,
    defaultSkipped: defaultSkipped,
    defaultSkipReason: defaultSkipped ? '默认跳过' : null,
    hasUntranslatableContent: protected,
  );
  return TranslationReplacementPlan(
    illust: DownloadedIllust(
      illustId: id,
      userId: id,
      userName: 'user$id',
      title: 'title$id',
      type: 'illust',
      caption: '',
      createDate: '',
      pageCount: 1,
      width: 10,
      height: 10,
      sanityLevel: 0,
      xRestrict: 0,
      totalView: 0,
      totalBookmarks: 0,
      tags: '',
      relativePath: 'work/$id',
      downloadTime: 0,
      illustJson: '',
    ),
    workDirectory: '/work/$id',
    resultDirectories: const [],
    externalComicDirectory: null,
    pairs: [pair],
    unmatched: const [],
    untranslatableOriginalPaths:
        protected ? <String>{originalPath} : const <String>{},
  );
}

class _FakeReplacer extends TranslationResultReplacer {
  _FakeReplacer() : super(DownloadDatabaseProvider());

  Object? applyError;

  @override
  Future<TranslationReplacementBatchSummary> applyBatch(
    TranslationReplacementBatchPlan batchPlan, {
    Set<String> skippedOriginalPaths = const <String>{},
  }) async {
    final error = applyError;
    if (error != null) throw error;
    return const TranslationReplacementBatchSummary(items: []);
  }
}
