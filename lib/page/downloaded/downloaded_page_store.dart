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
}

// SharedPreferences 键名
const String _downloadedIllustsSortTypeKey = 'downloaded_illusts_sort_type';
const String _downloadedIllustsSortDescKey = 'downloaded_illusts_sort_desc';

class DownloadedPageStore = _DownloadedPageStoreBase with _$DownloadedPageStore;

abstract class _DownloadedPageStoreBase with Store {
  static const int _pageSize = 50;

  EasyRefreshController? easyRefreshController;
  StreamSubscription<IllustDownloadStatus>? _downloadStatusSubscription;
  Timer? _searchDebounce;

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
  String? _filterTagName;

  @observable
  ObservableList<int> exampleIllustIds = ObservableList();

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

  String? get filterTagName => _filterTagName;

  // ===== 多选模式状态 =====

  @readonly
  bool _isMultiSelectMode = false;

  @readonly
  ObservableSet<int> _selectedIllustIds = ObservableSet();

  // ===== 拖拽设置状态 =====
  
  static const String _dragOnlyNonWebpKey = 'drag_only_non_webp';

  @readonly
  bool _dragOnlyNonWebp = false;

  @observable
  bool disableMouseDragScroll = false;

  @action
  void toggleMouseDragScroll() {
    disableMouseDragScroll = !disableMouseDragScroll;
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
    }
  }

  // ===== 初始化与销毁 =====

  /// 初始化 Store
  void init({
    int? initialUserId,
    String? initialUserName,
    String? initialSearchKeyword,
    String? initialTagName,
  }) {
    if (initialUserId != null) {
      _filterUserId = initialUserId;
      _filterUserName = initialUserName;
    }

    if (initialTagName != null) {
      _filterTagName = initialTagName;
      // 初始化 exampleIllustIds
      final tag = tagManagerStore.getTagDisplayData(initialTagName);
      if (tag != null) {
        exampleIllustIds.clear();
        exampleIllustIds.addAll(tag.tag.exampleIllustIds);
      }
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

    final dragOnlyNonWebp = Prefer.getBool(_dragOnlyNonWebpKey);
    if (dragOnlyNonWebp != null) {
      _dragOnlyNonWebp = dragOnlyNonWebp;
    }
  }

  // ===== Action 方法 =====

  @action
  void _onDownloadStatusChanged(IllustDownloadStatus status) {
    // 如果是删除状态，从列表中移除
    if (status.status == DownloadTaskStatus.deleted) {
      _illusts.removeWhere((e) => e.illustId == status.illusts.illustId);
      _illustDownloadStatus.remove(status.illusts.illustId);
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

    if (!_illusts.any((e) => e.illustId == status.illusts.illustId)) {
      _illusts.insert(0, status.illusts);
    }
    _illustDownloadStatus[status.illusts.illustId] = status.status;
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
        );
      } else if (_filterTagName != null && _filterTagName!.isNotEmpty) {
        illusts = await downloadStore.searchDownloadedByTagName(
          _filterTagName!,
          limit: _pageSize,
          offset: 0,
          orderBy: orderBy,
          exampleIllustIds: exampleIllustIds,
        );
      } else if (_filterUserId != null) {
        illusts = await downloadStore.getDownloadedByUser(
          _filterUserId!,
          limit: _pageSize,
          offset: 0,
          orderBy: orderBy,
        );
      } else if (_searchKeyword != null && _searchKeyword!.isNotEmpty) {
        illusts = await downloadStore.searchDownloaded(
          _searchKeyword!,
          limit: _pageSize,
          offset: 0,
          orderBy: orderBy,
        );
      } else {
        illusts = await downloadStore.getAllDownloaded(
          limit: _pageSize,
          offset: 0,
          orderBy: orderBy,
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
      _illusts.addAll(illusts);
      _loading = false;
      _hasMore = illusts.length >= _pageSize;

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
        );
      } else if (_filterTagName != null && _filterTagName!.isNotEmpty) {
        moreIllusts = await downloadStore.searchDownloadedByTagName(
          _filterTagName!,
          limit: _pageSize,
          offset: offset,
          orderBy: orderBy,
          exampleIllustIds: exampleIllustIds,
        );
      } else if (_filterUserId != null) {
        moreIllusts = await downloadStore.getDownloadedByUser(
          _filterUserId!,
          limit: _pageSize,
          offset: offset,
          orderBy: orderBy,
        );
      } else if (_searchKeyword != null && _searchKeyword!.isNotEmpty) {
        moreIllusts = await downloadStore.searchDownloaded(
          _searchKeyword!,
          limit: _pageSize,
          offset: offset,
          orderBy: orderBy,
        );
      } else {
        moreIllusts = await downloadStore.getAllDownloaded(
          limit: _pageSize,
          offset: offset,
          orderBy: orderBy,
        );
      }

      _illusts.addAll(moreIllusts);
      _loadingMore = false;
      _hasMore = moreIllusts.length >= _pageSize;
      easyRefreshController?.finishLoad(
        _hasMore ? IndicatorResult.success : IndicatorResult.noMore,
      );

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
      } else if (_filterTagName != null && _filterTagName!.isNotEmpty) {
        filterType = 'tag';
        tagName = _filterTagName;
      } else if (_searchKeyword != null && _searchKeyword!.isNotEmpty) {
        filterType = 'search';
        searchKeyword = _searchKeyword;
      }

      final stats = await downloadStore.getFilteredStats(
        filterType: filterType,
        userId: userId,
        searchKeyword: searchKeyword,
        tagName: tagName,
      );

      _stats = stats;
    } catch (e) {
      // 忽略错误，不影响主功能
    }
  }

  /// 加载关键信息（下载任务状态）
  /// 物化字段已在 DownloadedIllust 对象中，只需获取运行时下载任务状态
  Future<void> _loadCriticalInfo(List<DownloadedIllust> illusts) async {
    final futures = illusts.map((illust) async {
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
    _filterTagName = null;
    _searchKeyword = null;
    _isSearching = false;
    _downloadFilter = DownloadFilter.all;
    _sortType = IllustSortType.downloadTime;
    loadData();
  }

  @action
  void initFromTag(String tagName) {
    _filterTagName = tagName;
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
    await loadData();
    await loadStats();
    easyRefreshController?.finishRefresh();
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
  void setDragOnlyNonWebp(bool value) {
    _dragOnlyNonWebp = value;
    Prefer.setBool(_dragOnlyNonWebpKey, value);
  }
}
