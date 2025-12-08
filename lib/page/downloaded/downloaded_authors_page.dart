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

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:pixez/component/downloaded_author_card.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/component/sort_group.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

enum AuthorSortType {
  lastDownloadTime, // 最新下载
  userName, // 用户名
  illustCount, // 插画数量
}

class DownloadedAuthorsPage extends StatefulWidget {
  const DownloadedAuthorsPage({Key? key}) : super(key: key);

  @override
  State<DownloadedAuthorsPage> createState() => _DownloadedAuthorsPageState();
}

class _DownloadedAuthorsPageState extends State<DownloadedAuthorsPage> {
  final EasyRefreshController _easyRefreshController = EasyRefreshController(
    controlFinishLoad: true,
    controlFinishRefresh: true,
  );
  final ScrollController _scrollController = ScrollController();

  List<DownloadedAuthor> _authors = [];
  AuthorSortType _sortType = AuthorSortType.lastDownloadTime;
  bool _loading = false;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 20;
  
  // 显示模式：false=最新下载，true=最新发布
  bool _showLatestPublished = false;
  
  // 预加载的插画数据：key为userId，value为[最新下载列表, 最新发布列表]
  Map<int, List<List<DownloadedIllust>>> _authorIllustsMap = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _easyRefreshController.dispose();
    super.dispose();
  }

  String _getSortBy() {
    switch (_sortType) {
      case AuthorSortType.lastDownloadTime:
        return 'last_download_time';
      case AuthorSortType.userName:
        return 'user_name';
      case AuthorSortType.illustCount:
        return 'illust_count';
    }
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (!downloadStore.isInitialized) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    if (refresh) {
      _page = 0;
      _hasMore = true;
    }

    setState(() {
      _loading = true;
    });

    try {
      final authors = await downloadStore.getDownloadedAuthors(
        sortBy: _getSortBy(),
        desc: _sortType != AuthorSortType.userName,
        limit: _pageSize,
        offset: _page * _pageSize,
      );

      if (mounted) {
        setState(() {
          if (refresh) {
            _authors = authors;
            _authorIllustsMap.clear();
          } else {
            _authors.addAll(authors);
          }
          _hasMore = authors.length >= _pageSize;
          _loading = false;
        });
        
        // 预加载所有作者的插画数据
        _preloadAuthorIllusts(authors);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;

    _page++;
    await _loadData();
  }

  void _onSortChanged(int index) {
    setState(() {
      _sortType = AuthorSortType.values[index];
    });
    _loadData(refresh: true);
  }

  /// 预加载作者的插画数据（最新下载和最新发布）
  Future<void> _preloadAuthorIllusts(List<DownloadedAuthor> authors) async {
    // 异步加载，不阻塞UI
    Future.microtask(() async {
      for (final author in authors) {
        if (_authorIllustsMap.containsKey(author.userId)) continue;
        
        try {
          // 并行加载最新下载和最新发布的插画
          final futures = await Future.wait([
            downloadStore.getAuthorLatestIllusts(author.userId, limit: 3),
            downloadStore.getAuthorLatestPublishedIllusts(author.userId, limit: 3),
          ]);
          
          if (mounted) {
            setState(() {
              // 存储为列表：[最新下载列表, 最新发布列表]
              _authorIllustsMap[author.userId] = [
                futures[0], // 最新下载
                futures[1], // 最新发布
              ];
            });
          }
        } catch (e) {
          // 忽略单个作者加载失败
        }
      }
    });
  }

  void _toggleDisplayMode() {
    setState(() {
      _showLatestPublished = !_showLatestPublished;
    });
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          height: 45,
          child: SortGroup(
            children: [
              '最新下载',
              '用户名',
              '插画数量',
            ],
            onChange: _onSortChanged,
          ),
        ),
        Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '显示模式',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Row(
                children: [
                  Text(
                    '最新下载',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: !_showLatestPublished 
                          ? Theme.of(context).colorScheme.primary 
                          : Colors.grey,
                    ),
                  ),
                  Switch(
                    value: _showLatestPublished,
                    onChanged: (_) => _toggleDisplayMode(),
                  ),
                  Text(
                    '最新发布',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _showLatestPublished 
                          ? Theme.of(context).colorScheme.primary 
                          : Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('下载的作者'),
      ),
      body: Stack(
        children: [
          EasyRefresh(
            controller: _easyRefreshController,
            header: PixezDefault.header(context),
            footer: _hasMore
                ? ClassicFooter(
                    dragText: '上拉加载',
                    armedText: '释放加载',
                    readyText: '加载中...',
                    processingText: '加载中...',
                    processedText: '加载完成',
                    noMoreText: '没有更多了',
                    failedText: '加载失败',
                  )
                : null,
            onRefresh: () async {
              await _loadData(refresh: true);
              _easyRefreshController.finishRefresh();
            },
            onLoad: _hasMore
                ? () async {
                    await _loadMore();
                    _easyRefreshController.finishLoad(
                      _hasMore
                          ? IndicatorResult.success
                          : IndicatorResult.noMore,
                    );
                  }
                : null,
            child: _authors.isNotEmpty
                ? CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildHeader(),
                      ),
                      _buildList(),
                    ],
                  )
                : _loading
                    ? Center(child: CircularProgressIndicator())
                    : Center(
                        child: Text('暂无数据'),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return SliverWaterfallFlow(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < _authors.length) {
            final author = _authors[index];
            final illustsData = _authorIllustsMap[author.userId];
            // 根据显示模式选择插画：最新下载（索引0）或最新发布（索引1）
            final displayIllusts = illustsData != null
                ? (_showLatestPublished ? illustsData[1] : illustsData[0])
                : <DownloadedIllust>[];
            
            return DownloadedAuthorCard(
              author: author,
              illusts: displayIllusts,
              showLatestPublished: _showLatestPublished,
            );
          }
          return null;
        },
        childCount: _authors.length,
      ),
      gridDelegate: SliverWaterfallFlowDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 600,
      ),
    );
  }
}

