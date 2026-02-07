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

part 'downloaded_authors_page_store.g.dart';

enum AuthorSortType {
  lastDownloadTime, // 最新下载
  userName, // 用户名
  fileSize, // 文件大小
  illustCount, // 作品数量 (原"插画数量")
  imageCount, // 插画数量 (图片数量)
}

// SharedPreferences 键名
const String _downloadedAuthorsSortTypeKey = 'downloaded_authors_sort_type';
const String _downloadedAuthorsShowLatestPublishedKey = 'downloaded_authors_show_latest_published';
const String _downloadedAuthorsSortDescKey = 'downloaded_authors_sort_desc';
const String _downloadedAuthorsMarkUnprocessedKey = 'downloaded_authors_mark_unprocessed';
const String _downloadedAuthorsShowBookmarksOnlyKey = 'downloaded_authors_show_bookmarks_only';

typedef AuthorUpdateProgressCallback = void Function(int current, int total);

class DownloadedAuthorsPageStore = _DownloadedAuthorsPageStoreBase with _$DownloadedAuthorsPageStore;

abstract class _DownloadedAuthorsPageStoreBase with Store {
  static const int _pageSize = 30;

  EasyRefreshController? easyRefreshController;
  Timer? _searchDebounce;

  // ===== 私有可观察状态 =====

  @readonly
  ObservableList<DownloadedAuthor> _authors = ObservableList();

  @readonly
  AuthorSortType _sortType = AuthorSortType.lastDownloadTime;

  @readonly
  bool _sortDesc = true;

  @readonly
  bool _loading = false;

  @readonly
  bool _hasMore = true;

  @readonly
  int _page = 0;

  @readonly
  bool _showLatestPublished = false;

  @readonly
  String? _searchKeyword;

  @readonly
  bool _isSearching = false;

  // 预加载的插画数据：key为userId，value为[最新下载列表, 最新发布列表]
  @readonly
  ObservableMap<int, List<List<DownloadedIllust>>> _authorIllustsMap = ObservableMap();

  @readonly
  bool _markUnprocessed = false;

  @readonly
  ObservableSet<int> _unprocessedUserIds = ObservableSet();

  @readonly
  bool _showBookmarksOnly = false;

  @readonly
  bool _showNonWebpOnly = false;

  @readonly
  int _totalCount = 0;

  // ===== 初始化与销毁 =====

  @action
  void init() {
    _loadPersistedState();
    loadData(refresh: true);
  }

  void dispose() {
    _searchDebounce?.cancel();
  }

  /// 加载持久化的状态
  void _loadPersistedState() {
    final sortTypeIndex = Prefer.getInt(_downloadedAuthorsSortTypeKey);
    if (sortTypeIndex != null &&
        sortTypeIndex >= 0 &&
        sortTypeIndex < AuthorSortType.values.length) {
      _sortType = AuthorSortType.values[sortTypeIndex];
    }

    final showLatestPublished = Prefer.getBool(_downloadedAuthorsShowLatestPublishedKey);
    if (showLatestPublished != null) {
      _showLatestPublished = showLatestPublished;
    }

    final sortDesc = Prefer.getBool(_downloadedAuthorsSortDescKey);
    if (sortDesc != null) {
      _sortDesc = sortDesc;
    }

    final markUnprocessed = Prefer.getBool(_downloadedAuthorsMarkUnprocessedKey);
    if (markUnprocessed != null) {
      _markUnprocessed = markUnprocessed;
    }

    final showBookmarksOnly = Prefer.getBool(_downloadedAuthorsShowBookmarksOnlyKey);
    if (showBookmarksOnly != null) {
      _showBookmarksOnly = showBookmarksOnly;
    }
  }

  String _getSortBy() {
    switch (_sortType) {
      case AuthorSortType.lastDownloadTime:
        return 'last_download_time';
      case AuthorSortType.userName:
        return 'user_name';
      case AuthorSortType.fileSize:
        return 'total_file_size';
      case AuthorSortType.illustCount:
        return 'illust_count';
      case AuthorSortType.imageCount:
        return 'total_image_count';
    }
  }

  // ===== Action 方法 =====

  @action
  Future<void> loadData({bool refresh = false}) async {
    if (!downloadStore.isInitialized) {
      _loading = false;
      return;
    }

    if (refresh) {
      _page = 0;
      _hasMore = true;
      if (_searchKeyword == null && !_isSearching) {
         // 重置未处理状态
         _unprocessedUserIds.clear();
      }
    }

    _loading = true;

    try {
      final t1 = DateTime.now();
      List<DownloadedAuthor> authors;
      
      if (_showNonWebpOnly) {
        // 优化方案：分步查询 + 批量过滤
        // 步骤1: 先快速查询有非 WebP 图片的作者 ID（只返回 ID，不加载完整数据）
        final nonWebpAuthorIds = await downloadStore.dbProvider.getAuthorsWithNonWebpImages();
        
        // 步骤2: 使用 WHERE userId IN (...) 批量获取作者详情，应用排序和搜索条件
        authors = await downloadStore.getDownloadedAuthors(
          sortBy: _getSortBy(),
          desc: _sortDesc,
          searchKeyword: _searchKeyword,
          filterBookmarks: _showBookmarksOnly,
          filterUserIds: nonWebpAuthorIds.toList(),
        );
        _totalCount = authors.length;
      } else {
        authors = await downloadStore.getDownloadedAuthors(
          sortBy: _getSortBy(),
          desc: _sortDesc,
          limit: _pageSize,
          offset: _page * _pageSize,
          searchKeyword: _searchKeyword,
          filterBookmarks: _showBookmarksOnly,
        );
        if (refresh) {
          // 异步加载总数，不阻塞当前方法
          _loadTotalCount();
        }
      }
      
      if (_markUnprocessed && authors.isNotEmpty) {
        // 异步标记未处理，不阻塞主流程
        _markUnprocessedAuthors(authors.map((e) => e.userId).toList());
      }
      final timeSpent = DateTime.now().difference(t1);
      Log.i(() => 'loadData cost ${timeSpent.inMilliseconds}ms, count ${authors.length}');
      if (timeSpent.inMilliseconds > 300) {
        BotToast.showText(text: 'loadData cost ${timeSpent.inMilliseconds}ms');
      }

      if (refresh) {
        _authors.clear();
        _authorIllustsMap.clear();
      }
      _authors.addAll(authors);
      // 非 WebP 过滤模式下不分页，禁用加载更多
      _hasMore = _showNonWebpOnly ? false : authors.length >= _pageSize;
      _loading = false;

      // 预加载所有作者的插画数据
      _preloadAuthorIllusts(authors);
    } catch (e, stack) {
      Log.e(() => '[DB] Failed to load authors data: $e\n$stack');
      _loading = false;
    }
  }

  @action
  Future<void> loadMore() async {
    if (_loading || !_hasMore) return;

    _page++;
    await loadData();
    easyRefreshController?.finishLoad(_hasMore ? IndicatorResult.success : IndicatorResult.noMore);
  }

  @action
  void onSortChanged(int index) {
    final newSortType = AuthorSortType.values[index];
    _sortType = newSortType;
    // 持久化排序类型
    Prefer.setInt(_downloadedAuthorsSortTypeKey, newSortType.index);
    loadData(refresh: true);
  }

  @action
  void onSortOrderChanged(bool desc) {
    _sortDesc = desc;
    // 持久化排序顺序
    Prefer.setBool(_downloadedAuthorsSortDescKey, desc);
    loadData(refresh: true);
  }

  @action
  void onSearchChanged(String text) {
    // 取消之前的定时器
    _searchDebounce?.cancel();

    // 设置新的定时器,延迟300ms后执行搜索
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final keyword = text.trim();
      if (keyword != _searchKeyword) {
        _searchKeyword = keyword.isEmpty ? null : keyword;
        loadData(refresh: true);
      }
    });
  }

  @action
  void toggleSearch({required bool isSearching, VoidCallback? onClear}) {
    _isSearching = isSearching;
    if (!_isSearching) {
      onClear?.call();
      _searchKeyword = null;
      loadData(refresh: true);
    }
  }

  @action
  Future<void> toggleMarkUnprocessed(bool value) async {
    _markUnprocessed = value;
    Prefer.setBool(_downloadedAuthorsMarkUnprocessedKey, value);
    if (_markUnprocessed) {
      if (_authors.isNotEmpty) {
        // 仅检查当前已加载作者的状态，避免重新加载整个列表
        // 注意：如果作者数量非常大，这里可能需要分批处理，但通常前端分页加载数量可控
        // 为防万一，这里简单分批（每次100个）
        final allIds = _authors.map((e) => e.userId).toList();
        final batchSize = 100;
        
        for (var i = 0; i < allIds.length; i += batchSize) {
           final end = (i + batchSize < allIds.length) ? i + batchSize : allIds.length;
           final batchIds = allIds.sublist(i, end);
           await _markUnprocessedAuthors(batchIds);
        }
      }
    } else {
      // 如果关闭，清空标记
      _unprocessedUserIds.clear();
    }
  }

  @action
  Future<void> refreshSingleAuthor(int userId) async {
    if (!downloadStore.isInitialized) return;

    try {
      // 从数据库重新获取作者信息
      final updatedAuthor = await downloadStore.dbProvider.getAuthorByUserId(userId);
      if (updatedAuthor == null) return;

      // 在列表中找到并替换对应的作者
      final index = _authors.indexWhere((author) => author.userId == userId);
      if (index != -1) {
        _authors[index] = updatedAuthor;
      }

      // 重新加载该作者的插画数据
      _authorIllustsMap.remove(userId);
      _preloadAuthorIllusts([updatedAuthor]);
    } catch (e, stack) {
      Log.e(() => '[DB] Failed to refresh author $userId: $e\n$stack');
    }
  }

  @action
  Future<void> updateBookmark(int userId, int bookmark) async {
    if (!downloadStore.isInitialized) return;
    try {
      await downloadStore.dbProvider.updateAuthorBookmark(userId, bookmark);
      await refreshSingleAuthor(userId);
    } catch (e, stack) {
      Log.e(() => '[DB] Failed to update bookmark for author $userId: $e\n$stack');
    }
  }

  @action
  void toggleShowBookmarksOnly(bool value) {
    _showBookmarksOnly = value;
    Prefer.setBool(_downloadedAuthorsShowBookmarksOnlyKey, value);
    loadData(refresh: true);
  }

  @action
  void toggleShowNonWebpOnly(bool value) {
    _showNonWebpOnly = value;
    loadData(refresh: true);
  }

  @action
  void toggleDisplayMode(bool value) {
    _showLatestPublished = value;
    // 持久化显示模式
    Prefer.setBool(_downloadedAuthorsShowLatestPublishedKey, value);
  }

  /// 批量更新所有作者的统计信息
  @action
  Future<void> updateAllAuthorsStats({
    AuthorUpdateProgressCallback? onProgress,
  }) async {
    if (!downloadStore.isInitialized) {
      throw Exception('下载功能未初始化');
    }

    // 从数据库获取所有作者
    final allAuthors = await downloadStore.dbProvider.getAllAuthors();
    
    final total = allAuthors.length;
    for (int i = 0; i < total; i++) {
      final author = allAuthors[i];
      await downloadStore.dbProvider.updateAuthorStats(author.userId);
      onProgress?.call(i + 1, total);
    }
    
    // 更新完成后刷新列表
    await loadData(refresh: true);
  }

  /// 异步加载作者总数（不阻塞主流程）
  @action
  Future<void> _loadTotalCount() async {
    try {
      final totalCount = await downloadStore.dbProvider.getAuthorsCount(
        filterBookmarks: _showBookmarksOnly,
      );
      _totalCount = totalCount;
    } catch (e, stack) {
      Log.e(() => '[DB] Failed to load total count: $e\n$stack');
    }
  }

  /// 异步标记未处理的作者（不阻塞主流程）
  @action
  Future<void> _markUnprocessedAuthors(List<int> authorIds) async {
    try {
      final unprocessedIds = await downloadStore.dbProvider
          .getAuthorsWithNonWebpImages(authorIds);
      
      // 删除当前批次中已处理好的作者（authorIds 中存在但不在 unprocessedIds 中的）
      final processedIds = authorIds.toSet().difference(unprocessedIds.toSet());
      _unprocessedUserIds.removeAll(processedIds);
      
      // 添加新的未处理作者
      _unprocessedUserIds.addAll(unprocessedIds);
    } catch (e, stack) {
      Log.e(() => '[DB] Failed to mark unprocessed authors: $e\n$stack');
    }
  }

  /// 预加载作者的插画数据（最新下载和最新发布）
  Future<void> _preloadAuthorIllusts(List<DownloadedAuthor> authors) async {
    // 异步加载，不阻塞UI
    Future.microtask(() async {
      for (final author in authors) {
        if (_authorIllustsMap.containsKey(author.userId)) continue;

        try {
          // 并行加载最新下载和最新发布的插画
          final illustsFutures = await Future.wait([
            downloadStore.getAuthorLatestIllusts(author.userId, limit: 3),
            downloadStore.getAuthorLatestPublishedIllusts(author.userId, limit: 3),
          ]);

          final latestDownloadIllusts = illustsFutures[0];
          final latestPublishedIllusts = illustsFutures[1];

          runInAction(() {
            // 存储插画数据：[最新下载列表, 最新发布列表]
            _authorIllustsMap[author.userId] = [
              latestDownloadIllusts,
              latestPublishedIllusts,
            ];
          });
        } catch (e, stack) {
          Log.e(() => '[DB] Failed to preload illusts for author ${author.userId}: $e\n$stack');
        }
      }
    });
  }
}
