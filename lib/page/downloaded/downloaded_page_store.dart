/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 */

import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:mobx/mobx.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/store/download_store.dart';

part 'downloaded_page_store.g.dart';

/// 下载过滤类型
enum DownloadFilter {
  all,
  downloading,
  completed,
  incomplete, // 未下载完整
}

/// 插画排序类型
enum IllustSortType {
  downloadTime, // 下载时间
  createDate, // 作品时间
  fileSize, // 文件大小
  averageFileSize, // 平均文件大小
  bookmark, // 收藏/优先级
}

// SharedPreferences 键名
const String _downloadedIllustsSortTypeKey = 'downloaded_illusts_sort_type';
const String _downloadedIllustsSortDescKey = 'downloaded_illusts_sort_desc';
const String _downloadedIllustsMarkUnprocessedKey =
    'downloaded_illusts_mark_unprocessed';
const String _downloadedIllustsShowBookmarksOnlyKey =
    'downloaded_illusts_show_bookmarks_only';
const String _enableDragKey = 'enable_drag';

class DownloadedPageStore = _DownloadedPageStoreBase with _$DownloadedPageStore;

abstract class _DownloadedPageStoreBase with Store {
  static const int _pageSize = 50;

  EasyRefreshController? easyRefreshController;
  StreamSubscription<IllustDownloadStatus>? _downloadStatusSubscription;
  Timer? _searchDebounce;
  Timer? _statsDebounce;

  // ===== 私有可观察状态 =====

  @readonly
  ObservableList<DownloadedIllust> _illusts = ObservableList();

  @readonly
  ObservableMap<int, DownloadTaskStatus> _illustDownloadStatus =
      ObservableMap();

  @readonly
  bool _loading = true;

  @readonly
  bool _loadingMore = false;

  @readonly
  bool _hasMore = true;

  @readonly
  int _page = 0;

  @readonly
  String? _searchKeyword;

  @readonly
  int? _filterTagId;

  @readonly
  bool _isSearching = false;

  @readonly
  int? _filterUserId;

  @readonly
  String? _filterUserName;

  @readonly
  DownloadFilter _downloadFilter = DownloadFilter.all;

  @readonly
  IllustSortType _sortType = IllustSortType.downloadTime;

  @readonly
  bool _sortDesc = true;

  @readonly
  Map<String, int>? _stats;

  @computed
  TagDisplayData? get filterTagData =>
      _filterTagId != null ? tagManagerStore.tagIdMap[_filterTagId] : null;

  @computed
  Set<int> get filterTagExampleIds =>
      filterTagData?.tag.exampleIllustIds.toSet() ?? {};

  bool isExample(int illustId) => filterTagExampleIds.contains(illustId);

  // ===== 多选模式状态 =====

  @readonly
  bool _isMultiSelectMode = false;

  @readonly
  ObservableSet<int> _selectedIllustIds = ObservableSet();

  // ===== 拖拽设置状态 =====

  @observable
  bool enableDrag = false;

  @action
  void toggleEnableDrag() {
    enableDrag = !enableDrag;
    Prefer.setBool(_enableDragKey, enableDrag);
  }

  // ===== 未处理标记状态 =====

  @readonly
  bool _markUnprocessed = false;

  @readonly
  ObservableSet<int> _unprocessedIllustIds = ObservableSet();

  // ===== 收藏状态 =====

  @readonly
  bool _showBookmarksOnly = false;

  // ===== 刷新状态 =====

  @readonly
  bool _isRefreshing = false;

  @action
  void toggleShowBookmarksOnly() {
    _showBookmarksOnly = !_showBookmarksOnly;
    Prefer.setBool(_downloadedIllustsShowBookmarksOnlyKey, _showBookmarksOnly);
    loadData();
    loadStats();
  }

  // ===== 计算属性 =====

  /// 根据过滤条件筛选后的插画列表
  @computed
  List<DownloadedIllust> get filteredIllusts {
    if (_downloadFilter == DownloadFilter.all ||
        _downloadFilter == DownloadFilter.incomplete) {
      // 未下载完整过滤：直接从数据库查询，不需要在应用层过滤
      return _illusts.toList();
    }

    return _illusts.where((illust) {
      final status = _illustDownloadStatus[illust.illustId];
      // 直接使用物化字段
      final isCompleted = illust.downloadedImageCount >= illust.pageCount;

      if (_downloadFilter == DownloadFilter.downloading) {
        return !isCompleted ||
            status == DownloadTaskStatus.downloading ||
            status == DownloadTaskStatus.pending ||
            status == DownloadTaskStatus.paused ||
            status == DownloadTaskStatus.failed;
      } else if (_downloadFilter == DownloadFilter.completed) {
        return isCompleted &&
            status != DownloadTaskStatus.downloading &&
            status != DownloadTaskStatus.pending &&
            status != DownloadTaskStatus.paused &&
            status != DownloadTaskStatus.failed;
      }
      return true;
    }).toList();
  }

  /// 获取排序SQL（使用物化字段名）
  String? get _sortBy {
    switch (_sortType) {
      case IllustSortType.downloadTime:
        return '${DownloadedIllustColumns.downloadTime} ${_sortDesc ? 'DESC' : 'ASC'}';
      case IllustSortType.createDate:
        return '${DownloadedIllustColumns.createDate} ${_sortDesc ? 'DESC' : 'ASC'}';
      case IllustSortType.fileSize:
        return '${DownloadedIllustColumns.totalFileSize} ${_sortDesc ? 'DESC' : 'ASC'}';
      case IllustSortType.averageFileSize:
        return '${DownloadedIllustColumns.totalFileSize} / ${DownloadedIllustColumns.pageCount} ${_sortDesc ? 'DESC' : 'ASC'}';
      case IllustSortType.bookmark:
        return '${DownloadedIllustColumns.bookmark} ${_sortDesc ? 'DESC' : 'ASC'}';
    }
  }

  // ===== 初始化与销毁 =====

  /// 初始化 Store
  void init({
    int? initialUserId,
    String? initialUserName,
    String? initialSearchKeyword,
    int? initialTagId,
  }) {
    if (initialUserId != null) {
      _filterUserId = initialUserId;
      _filterUserName = initialUserName;
    }

    if (initialTagId != null) {
      _filterTagId = initialTagId;
    } else if (initialSearchKeyword != null) {
      _searchKeyword = initialSearchKeyword;
      _isSearching = true;
    }

    _loadPersistedState();
    loadData();
    loadStats();

    _downloadStatusSubscription = downloadStore.illustDownloadStatusStream
        .listen(_onDownloadStatusChanged);
  }

  /// 销毁 Store
  void dispose() {
    _downloadStatusSubscription?.cancel();
    _downloadStatusSubscription = null;
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _statsDebounce?.cancel();
    _statsDebounce = null;
  }

  /// 加载持久化的状态
  void _loadPersistedState() {
    final sortTypeIndex = Prefer.getInt(_downloadedIllustsSortTypeKey);
    if (sortTypeIndex != null &&
        sortTypeIndex >= 0 &&
        sortTypeIndex < IllustSortType.values.length) {
      _sortType = IllustSortType.values[sortTypeIndex];
    }

    final sortDesc = Prefer.getBool(_downloadedIllustsSortDescKey);
    if (sortDesc != null) {
      _sortDesc = sortDesc;
    }

    final enableDrag = Prefer.getBool(_enableDragKey);
    if (enableDrag != null) {
      this.enableDrag = enableDrag;
    }

    final markUnprocessed = Prefer.getBool(
      _downloadedIllustsMarkUnprocessedKey,
    );
    if (markUnprocessed != null) {
      _markUnprocessed = markUnprocessed;
    }

    final showBookmarksOnly = Prefer.getBool(
      _downloadedIllustsShowBookmarksOnlyKey,
    );
    if (showBookmarksOnly != null) {
      _showBookmarksOnly = showBookmarksOnly;
    }
  }

  // ===== Action 方法 =====

  @action
  void _onDownloadStatusChanged(IllustDownloadStatus status) {
    // 如果是删除状态，从列表中移除
    if (status.status == DownloadTaskStatus.deleted) {
      _illusts.removeWhere((e) => e.illustId == status.illusts.illustId);
      _illustDownloadStatus.remove(status.illusts.illustId);
      _refreshStatsWithDebounce();
      return;
    }

    // 如果当前有作者过滤，检查新插画是否属于当前作者
    if (_filterUserId != null && status.illusts.userId != _filterUserId) {
      // 不属于当前作者，不添加到列表，但更新状态信息（如果已存在）
      if (_illusts.any((e) => e.illustId == status.illusts.illustId)) {
        _illustDownloadStatus[status.illusts.illustId] = status.status;
      }
      return;
    }

    final index = _illusts.indexWhere(
      (e) => e.illustId == status.illusts.illustId,
    );
    if (index == -1) {
      _illusts.insert(0, status.illusts);
    } else {
      // 如果已在列表中，更新对象以反映物化字段的变化（已下载数、文件大小）
      _illusts[index] = status.illusts;
    }
    _illustDownloadStatus[status.illusts.illustId] = status.status;
    _refreshStatsWithDebounce();
  }

  /// 使用防抖刷新统计信息
  void _refreshStatsWithDebounce() {
    _statsDebounce?.cancel();
    _statsDebounce = Timer(const Duration(milliseconds: 500), () {
      loadStats();
    });
  }

  /// 加载数据
  @action
  Future<void> loadData() async {
    if (!downloadStore.isInitialized) {
      _loading = false;
      return;
    }

    _loading = true;
    _page = 0;
    _hasMore = true;

    try {
      List<DownloadedIllust> illusts;
      final orderBy = _sortBy;

      final t1 = DateTime.now();
      if (_downloadFilter == DownloadFilter.incomplete) {
        illusts = await downloadStore.getIncompleteDownloaded(
          limit: _pageSize,
          offset: 0,
          orderBy: orderBy,
          filterBookmarks: _showBookmarksOnly,
        );
      } else if (_filterTagId != null) {
        illusts = await downloadStore.searchDownloadedByTagId(
          _filterTagId!,
          limit: _pageSize,
          offset: 0,
          orderBy: orderBy,
          exampleIllustIds: filterTagData?.tag.exampleIllustIds,
          filterBookmarks: _showBookmarksOnly,
        );
      } else if (_filterUserId != null) {
        illusts = await downloadStore.getDownloadedByUser(
          _filterUserId!,
          limit: _pageSize,
          offset: 0,
          orderBy: orderBy,
          filterBookmarks: _showBookmarksOnly,
        );
      } else if (_searchKeyword != null && _searchKeyword!.isNotEmpty) {
        illusts = await downloadStore.searchDownloaded(
          _searchKeyword!,
          limit: _pageSize,
          offset: 0,
          orderBy: orderBy,
          filterBookmarks: _showBookmarksOnly,
        );
      } else {
        illusts = await downloadStore.getAllDownloaded(
          limit: _pageSize,
          offset: 0,
          orderBy: orderBy,
          filterBookmarks: _showBookmarksOnly,
        );
      }
      final timeSpent = DateTime.now().difference(t1);
      Log.i(
        () =>
            'loadData cost ${timeSpent.inMilliseconds}ms, count ${illusts.length}',
      );
      if (timeSpent.inMilliseconds > 300) {
        BotToast.showText(text: 'loadData cost ${timeSpent.inMilliseconds}ms');
      }

      _illusts.clear();
      _unprocessedIllustIds.clear();
      _illusts.addAll(illusts);
      _loading = false;
      _hasMore = illusts.length >= _pageSize;

      // 如果开启了标记未处理，加载未处理状态
      // 如果开启了标记未处理，加载未处理状态
      await _checkUnprocessedIllusts(illusts);

      // 并行加载关键信息
      await _loadCriticalInfo(illusts);
    } catch (e) {
      _loading = false;
    }
  }

  /// 加载更多数据
  @action
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) {
      easyRefreshController?.finishLoad(IndicatorResult.noMore);
      return;
    }

    _loadingMore = true;
    _page++;
    final offset = _page * _pageSize;

    try {
      List<DownloadedIllust> moreIllusts;
      final orderBy = _sortBy;

      if (_downloadFilter == DownloadFilter.incomplete) {
        moreIllusts = await downloadStore.getIncompleteDownloaded(
          limit: _pageSize,
          offset: offset,
          orderBy: orderBy,
          filterBookmarks: _showBookmarksOnly,
        );
      } else if (_filterTagId != null) {
        moreIllusts = await downloadStore.searchDownloadedByTagId(
          _filterTagId!,
          limit: _pageSize,
          offset: offset,
          orderBy: orderBy,
          exampleIllustIds: filterTagData?.tag.exampleIllustIds,
          filterBookmarks: _showBookmarksOnly,
        );
      } else if (_filterUserId != null) {
        moreIllusts = await downloadStore.getDownloadedByUser(
          _filterUserId!,
          limit: _pageSize,
          offset: offset,
          orderBy: orderBy,
          filterBookmarks: _showBookmarksOnly,
        );
      } else if (_searchKeyword != null && _searchKeyword!.isNotEmpty) {
        moreIllusts = await downloadStore.searchDownloaded(
          _searchKeyword!,
          limit: _pageSize,
          offset: offset,
          orderBy: orderBy,
          filterBookmarks: _showBookmarksOnly,
        );
      } else {
        moreIllusts = await downloadStore.getAllDownloaded(
          limit: _pageSize,
          offset: offset,
          orderBy: orderBy,
          filterBookmarks: _showBookmarksOnly,
        );
      }

      _illusts.addAll(moreIllusts);
      _loadingMore = false;
      _hasMore = moreIllusts.length >= _pageSize;
      easyRefreshController?.finishLoad(
        _hasMore ? IndicatorResult.success : IndicatorResult.noMore,
      );

      // 如果开启了标记未处理，加载未处理状态
      // 如果开启了标记未处理，加载未处理状态
      await _checkUnprocessedIllusts(moreIllusts);

      await _loadCriticalInfo(moreIllusts);
    } catch (e) {
      _loadingMore = false;
      easyRefreshController?.finishLoad(IndicatorResult.fail);
    }
  }

  /// 加载统计信息
  @action
  Future<void> loadStats() async {
    if (!downloadStore.isInitialized) {
      return;
    }

    try {
      String filterType = 'all';
      int? userId;
      String? searchKeyword;
      String? tagName;

      if (_downloadFilter == DownloadFilter.incomplete) {
        filterType = 'incomplete';
      } else if (_filterUserId != null) {
        filterType = 'user';
        userId = _filterUserId;
      } else if (_filterTagId != null) {
        filterType = 'tag';
        tagName = filterTagName;
      } else if (_searchKeyword != null && _searchKeyword!.isNotEmpty) {
        filterType = 'search';
        searchKeyword = _searchKeyword;
      }

      final stats = await downloadStore.getFilteredStats(
        filterType: filterType,
        userId: userId,
        searchKeyword: searchKeyword,
        tagName: tagName,
        filterBookmarks: _showBookmarksOnly,
      );

      _stats = stats;
    } catch (e) {
      // 忽略错误，不影响主功能
    }
  }

  /// 加载关键信息（下载任务状态）
  /// 物化字段已在 DownloadedIllust 对象中，只需获取运行时下载任务状态
  Future<void> _loadCriticalInfo(List<DownloadedIllust> illusts) async {
    final futures =
        illusts.map((illust) async {
          // 传入 downloadedIllust 避免重复查询数据库
          final downloadStatus = await downloadStore.getIllustDownloadStatus(
            illust.illustId,
            downloadedIllust: illust,
          );
          return MapEntry(illust.illustId, downloadStatus?.status);
        }).toList();

    final results = await Future.wait(futures);
    for (final entry in results) {
      if (entry.value != null) {
        _illustDownloadStatus[entry.key] = entry.value!;
      }
    }
  }

  /// 切换排序类型
  @action
  void onSortChanged(int index) {
    final newSortType = IllustSortType.values[index];
    _sortType = newSortType;
    Prefer.setInt(_downloadedIllustsSortTypeKey, newSortType.index);
    loadData();
  }

  /// 切换排序方向
  @action
  void onSortOrderChanged(bool desc) {
    _sortDesc = desc;
    Prefer.setBool(_downloadedIllustsSortDescKey, desc);
    loadData();
  }

  /// 切换下载过滤器
  @action
  void onFilterChanged(DownloadFilter filter) {
    _downloadFilter = filter;
    loadData();
    loadStats();
  }

  /// 设置搜索关键词
  @action
  void setSearchKeyword(String? keyword) {
    _searchKeyword = keyword;
    loadData();
  }

  @action
  void onSearchChanged(String text) {
    // 取消之前的定时器
    _searchDebounce?.cancel();

    // 设置新的定时器,延迟300ms后执行搜索
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final keyword = text.trim();
      if (keyword != _searchKeyword) {
        setSearchKeyword(keyword.isEmpty ? null : keyword);
      }
    });
  }

  @action
  void toggleSearch({required bool isSearching, VoidCallback? onClear}) {
    _isSearching = isSearching;
    if (!_isSearching) {
      onClear?.call();
      setSearchKeyword(null);
    }
  }

  /// 设置用户筛选
  @action
  void setFilterUser(int? userId, String? userName) {
    _filterUserId = userId;
    _filterUserName = userName;
    loadData();
    loadStats();
  }

  /// 清除用户筛选
  @action
  void clearFilterUser() {
    _filterUserId = null;
    _filterUserName = null;
    _filterTagId = null;
    _searchKeyword = null;
    _isSearching = false;
    _downloadFilter = DownloadFilter.all;
    _sortType = IllustSortType.downloadTime;
    loadData();
  }

  @action
  void initFromTag(String tagName) {
    final tagData = tagManagerStore.getTagDisplayData(tagName);
    if (tagData != null) {
      _filterTagId = tagData.tag.id;
    }
    _isSearching = true;
    loadData();
  }

  /// 暂停全部下载
  @action
  void pauseAll() {
    for (final illust in _illusts) {
      final status = _illustDownloadStatus[illust.illustId];
      if (status == DownloadTaskStatus.downloading ||
          status == DownloadTaskStatus.pending) {
        downloadStore.pauseIllustDownload(illust.illustId);
      }
    }
  }

  /// 恢复全部下载
  @action
  void resumeAll() {
    for (final illust in _illusts) {
      final status = _illustDownloadStatus[illust.illustId];
      if (status == DownloadTaskStatus.paused ||
          status == DownloadTaskStatus.failed) {
        downloadStore.resumeIllustDownload(illust.illustId);
      }
    }
  }

  /// 取消全部下载
  @action
  void cancelAll() {
    for (final illust in _illusts) {
      final status = _illustDownloadStatus[illust.illustId];
      if (status == DownloadTaskStatus.downloading ||
          status == DownloadTaskStatus.pending) {
        downloadStore.cancelIllustDownload(illust.illustId);
      }
    }
  }

  /// 刷新数据
  @action
  Future<void> refresh() async {
    _isRefreshing = true;
    try {
      await loadData();
      await loadStats();
      easyRefreshController?.finishRefresh();
    } finally {
      _isRefreshing = false;
    }
  }

  // ===== 多选模式 Actions =====

  @action
  void toggleMultiSelectMode() {
    _isMultiSelectMode = !_isMultiSelectMode;
    if (!_isMultiSelectMode) {
      _selectedIllustIds.clear();
    }
  }

  @action
  void exitMultiSelectMode() {
    _isMultiSelectMode = false;
    _selectedIllustIds.clear();
  }

  @action
  void enterMultiSelectMode() {
    _isMultiSelectMode = true;
  }

  @action
  void selectItem(int id) {
    if (_selectedIllustIds.contains(id)) {
      _selectedIllustIds.remove(id);
    } else {
      _selectedIllustIds.add(id);
    }
  }

  @action
  void setItemSelected(int id, bool selected) {
    if (selected) {
      _selectedIllustIds.add(id);
    } else {
      _selectedIllustIds.remove(id);
    }
  }

  @action
  void selectAll() {
    // 仅选择当前列表中的项
    _selectedIllustIds.addAll(filteredIllusts.map((e) => e.illustId));
  }

  @action
  void clearSelection() {
    _selectedIllustIds.clear();
  }

  // ===== 拖拽设置 Actions =====

  @action
  Future<void> toggleMarkUnprocessed(bool value) async {
    _markUnprocessed = value;
    Prefer.setBool(_downloadedIllustsMarkUnprocessedKey, value);
    if (_markUnprocessed) {
      if (_illusts.isNotEmpty) {
        // 分批查询
        final allIds = _illusts.map((e) => e.illustId).toList();
        final batchSize = 100;

        for (var i = 0; i < allIds.length; i += batchSize) {
          final end =
              (i + batchSize < allIds.length) ? i + batchSize : allIds.length;
          final batchIds = allIds.sublist(i, end);

          final unprocessedIds = await downloadStore.dbProvider
              .getIllustsWithNonWebpImages(batchIds);
          runInAction(() {
            _unprocessedIllustIds.addAll(unprocessedIds);
          });
        }
      }
    } else {
      _unprocessedIllustIds.clear();
    }
  }

  /// 检查并添加未处理的插画ID
  Future<void> _checkUnprocessedIllusts(List<DownloadedIllust> illusts) async {
    if (_markUnprocessed && illusts.isNotEmpty) {
      final unprocessedIds = await downloadStore.dbProvider
          .getIllustsWithNonWebpImages(illusts.map((e) => e.illustId).toList());
      runInAction(() {
        _unprocessedIllustIds.addAll(unprocessedIds);
      });
    }
  }

  @action
  Future<void> updateBookmark(int illustId, int bookmark) async {
    await downloadStore.updateIllustBookmark(illustId, bookmark);
    final index = _illusts.indexWhere((e) => e.illustId == illustId);
    if (index != -1) {
      // 使用 copyWith 创建带有新收藏状态的新对象
      _illusts[index] = _illusts[index].copyWith(bookmark: bookmark);

      // 如果开启了“仅显示收藏”，且该项被取消收藏，则从列表中移除
      if (_showBookmarksOnly && bookmark == 0) {
        _illusts.removeAt(index);
        _refreshStatsWithDebounce();
      }
    }
  }
}
