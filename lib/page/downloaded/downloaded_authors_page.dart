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
          } else {
            _authors.addAll(authors);
          }
          _hasMore = authors.length >= _pageSize;
          _loading = false;
        });
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

  Widget _buildHeader() {
    return Container(
      height: 45,
      child: SortGroup(
        children: [
          '最新下载',
          '用户名',
          '插画数量',
        ],
        onChange: _onSortChanged,
      ),
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
            return DownloadedAuthorCard(
              author: _authors[index],
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

