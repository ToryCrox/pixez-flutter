import 'package:mobx/mobx.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/history/history_database.dart';

part 'history_manager.g.dart';

class HistoryInfo {
  final int illustId;
  final int timestamp;
  final int lastPage;
  final int totalPages;

  HistoryInfo({
    required this.illustId,
    required this.timestamp,
    required this.lastPage,
    required this.totalPages,
  });

  double get progress => totalPages > 0 ? (lastPage + 1) / totalPages : 0;
}

class HistoryManager extends _HistoryManagerBase with _$HistoryManager {
  HistoryManager._() : super._();
  static final HistoryManager instance = HistoryManager._();
}

abstract class _HistoryManagerBase with Store {
  _HistoryManagerBase._();

  final HistoryDatabaseProvider _dbProvider = HistoryDatabaseProvider.instance;

  /// 缓存已查明进度的作品详情
  /// Key:作品 ID, Value: 历史信息（由于是按需加载，若 Value 为 null 则表示该作品经查证后确实没有历史记录）
  @observable
  ObservableMap<int, HistoryInfo?> progressCache = ObservableMap<int, HistoryInfo?>();

  /// 待查询的 ID 队列
  final Set<int> _pendingIds = {};
  bool _isBatchQueryPending = false;

  @observable
  bool isInitialized = false;

  @action
  Future<void> init() async {
    // 启动时不加载任何数据，实现真正的按需加载
    isInitialized = true;
  }

  /// 检查是否已读（异步按需查询）
  bool isRead(int illustId) {
    // 如果 key 存在，说明已经查询过（无论结果是有历史还是无历史）
    if (progressCache.containsKey(illustId)) {
      return progressCache[illustId] != null;
    }
    _enqueueQuery(illustId);
    return false;
  }

  /// 获取历史记录摘要（异步按需查询）
  HistoryInfo? getHistory(int illustId) {
    if (progressCache.containsKey(illustId)) {
      return progressCache[illustId];
    }
    _enqueueQuery(illustId);
    return null;
  }

  void _enqueueQuery(int illustId) {
    // 如果已经确定是不存在或是已加载，则不再查询
    // 注意：这里我们只记录“已读”，未查询到的 ID 不会重复进入队列
    if (_pendingIds.contains(illustId)) return;
    
    _pendingIds.add(illustId);
    
    if (!_isBatchQueryPending) {
      _isBatchQueryPending = true;
      // 利用微任务将同一帧内的多个请求合并
      Future.microtask(_processBatchQuery);
    }
  }

  Future<void> _processBatchQuery() async {
    if (_pendingIds.isEmpty) {
      _isBatchQueryPending = false;
      return;
    }

    final queryIds = _pendingIds.toList();
    _pendingIds.clear();
    _isBatchQueryPending = false;

    try {
      final results = await _dbProvider.queryHistorySummaries(queryIds);
      _applyBatchResults(queryIds, results);
    } catch (e) {
      Log.e('Failed to process batch query', error: e);
    }
  }

  @action
  void _applyBatchResults(List<int> queryIds, List<HistorySummary> results) {
    // 首先将本批次所有 ID 标记为 null（已查明但默认无记录）
    for (var id in queryIds) {
      progressCache[id] = null;
    }
    
    // 然后用查到的结果填充
    for (var item in results) {
      final id = item.illustId;
      progressCache[id] = HistoryInfo(
        illustId: id,
        timestamp: item.timestamp,
        lastPage: item.lastPage,
        totalPages: item.totalPages,
      );
    }
  }

  static const int _maxCacheSize = 5000;

  @action
  Future<void> updateHistory(Illusts illust, {int lastPage = 0}) async {
    final illustId = illust.id;
    final totalPages = illust.pageCount;
    
    progressCache[illustId] = HistoryInfo(
      illustId: illustId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      lastPage: lastPage,
      totalPages: totalPages,
    );
    
    if (progressCache.length > _maxCacheSize) {
      // 简单清理策略
      final firstKey = progressCache.keys.first;
      progressCache.remove(firstKey);
    }

    try {
      await _dbProvider.insert(illust, lastPage: lastPage);
    } catch (e) {
      Log.e('Failed to auto-save history', error: e);
    }
  }

  @action
  void clear() {
    progressCache.clear();
    _pendingIds.clear();
  }
}
