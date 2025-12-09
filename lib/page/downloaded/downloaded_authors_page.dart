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
import 'package:pixez/er/prefer.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/downloaded_page.dart';

enum AuthorSortType {
  lastDownloadTime, // 最新下载
  userName, // 用户名
  illustCount, // 插画数量
}

// SharedPreferences 键名
const String _DOWNLOADED_AUTHORS_SORT_TYPE_KEY = 'downloaded_authors_sort_type';
const String _DOWNLOADED_AUTHORS_SHOW_LATEST_PUBLISHED_KEY = 'downloaded_authors_show_latest_published';
const String _DOWNLOADED_AUTHORS_SORT_DESC_KEY = 'downloaded_authors_sort_desc';

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
  bool _sortDesc = true; // true=倒序，false=正序
  bool _loading = false;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 20;
  
  // 显示模式：false=最新下载，true=最新发布
  bool _showLatestPublished = false;
  
  // 预加载的插画数据和图片路径：key为userId，value为[最新下载列表, 最新发布列表]
  Map<int, List<List<DownloadedIllust>>> _authorIllustsMap = {};
  
  // 预加载的图片路径：key为userId，value为[最新下载路径列表, 最新发布路径列表]
  // 每个路径列表包含最多3个图片路径（可能为null）
  Map<int, List<List<String?>>> _authorImagePathsMap = {};

  @override
  void initState() {
    super.initState();
    _loadPersistedState();
    _loadData();
  }

  /// 加载持久化的状态
  void _loadPersistedState() {
    final sortTypeIndex = Prefer.getInt(_DOWNLOADED_AUTHORS_SORT_TYPE_KEY);
    if (sortTypeIndex != null && sortTypeIndex >= 0 && sortTypeIndex < AuthorSortType.values.length) {
      _sortType = AuthorSortType.values[sortTypeIndex];
    }
    
    final showLatestPublished = Prefer.getBool(_DOWNLOADED_AUTHORS_SHOW_LATEST_PUBLISHED_KEY);
    if (showLatestPublished != null) {
      _showLatestPublished = showLatestPublished;
    }
    
    final sortDesc = Prefer.getBool(_DOWNLOADED_AUTHORS_SORT_DESC_KEY);
    if (sortDesc != null) {
      _sortDesc = sortDesc;
    }
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
        desc: _sortDesc,
        limit: _pageSize,
        offset: _page * _pageSize,
      );

      if (mounted) {
        setState(() {
          if (refresh) {
            _authors = authors;
            _authorIllustsMap.clear();
            _authorImagePathsMap.clear();
          } else {
            _authors.addAll(authors);
          }
          _hasMore = authors.length >= _pageSize;
          _loading = false;
        });
        
        // 预加载所有作者的插画数据和图片路径
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
    final newSortType = AuthorSortType.values[index];
    setState(() {
      _sortType = newSortType;
    });
    // 持久化排序类型
    Prefer.setInt(_DOWNLOADED_AUTHORS_SORT_TYPE_KEY, newSortType.index);
    _loadData(refresh: true);
  }

  void _onSortOrderChanged(bool desc) {
    setState(() {
      _sortDesc = desc;
    });
    // 持久化排序顺序
    Prefer.setBool(_DOWNLOADED_AUTHORS_SORT_DESC_KEY, desc);
    _loadData(refresh: true);
  }

  /// 预加载作者的插画数据和图片路径（最新下载和最新发布）
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
          
          // 并行加载所有图片路径
          final imagePathFutures = [
            Future.wait(
              latestDownloadIllusts.map((illust) => 
                downloadStore.getLocalImagePath(illust.illustId, 0)
              ).toList(),
            ),
            Future.wait(
              latestPublishedIllusts.map((illust) => 
                downloadStore.getLocalImagePath(illust.illustId, 0)
              ).toList(),
            ),
          ];
          
          final imagePaths = await Future.wait(imagePathFutures);
          
          if (mounted) {
            setState(() {
              // 存储插画数据：[最新下载列表, 最新发布列表]
              _authorIllustsMap[author.userId] = [
                latestDownloadIllusts,
                latestPublishedIllusts,
              ];
              // 存储图片路径：[最新下载路径列表, 最新发布路径列表]
              _authorImagePathsMap[author.userId] = [
                imagePaths[0],
                imagePaths[1],
              ];
            });
          }
        } catch (e) {
          // 忽略单个作者加载失败
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('下载的作者'),
        actions: [
          IconButton(
            icon: Icon(Icons.list),
            tooltip: '下载记录',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => DownloadedPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: EasyRefresh(
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
                  SliverPersistentHeader(
                    key: ValueKey('sort_header_${_sortType}_${_showLatestPublished}_${_sortDesc}'),
                    delegate: SliverChipDelegate(
                      Container(
                        alignment: Alignment.center,
                        child: Stack(
                          children: [
                            // 居中显示筛选菜单
                            Center(
                              child: SortGroup(
                                key: ValueKey(_sortType),
                                children: [
                                  '最新下载',
                                  '用户名',
                                  '插画数量',
                                ],
                                onChange: _onSortChanged,
                                initIndex: _sortType.index,
                              ),
                            ),
                            // 右侧显示排序方向和显示模式按钮
                            Positioned(
                              right: 8,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildSortOrderButton(),
                                    SizedBox(width: 16),
                                    _buildDisplayModeButton(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      height: 52,
                    ),
                    pinned: true,
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
    );
  }

  Widget _buildSortOrderButton() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _sortDesc ? '倒序' : '正序',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(width: 8),
        Switch(
          value: _sortDesc,
          onChanged: _onSortOrderChanged,
        ),
      ],
    );
  }

  Widget _buildDisplayModeButton() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _showLatestPublished ? '最新发布' : '最新下载',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(width: 8),
        Switch(
          value: _showLatestPublished,
          onChanged: (value) {
            setState(() {
              _showLatestPublished = value;
            });
            // 持久化显示模式
            Prefer.setBool(_DOWNLOADED_AUTHORS_SHOW_LATEST_PUBLISHED_KEY, value);
          },
        ),
      ],
    );
  }

  Widget _buildList() {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < _authors.length) {
            final author = _authors[index];
            final illustsData = _authorIllustsMap[author.userId];
            final imagePathsData = _authorImagePathsMap[author.userId];
            
            // 根据显示模式选择插画和图片路径：最新下载（索引0）或最新发布（索引1）
            final displayIllusts = illustsData != null
                ? (_showLatestPublished ? illustsData[1] : illustsData[0])
                : <DownloadedIllust>[];
            final displayImagePaths = imagePathsData != null
                ? (_showLatestPublished ? imagePathsData[1] : imagePathsData[0])
                : <String?>[];
            
            return DownloadedAuthorCard(
              author: author,
              illusts: displayIllusts,
              imagePaths: displayImagePaths,
              showLatestPublished: _showLatestPublished,
            );
          }
          return null;
        },
        childCount: _authors.length,
      ),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 600,
        mainAxisExtent: 210
      ),
    );
  }
}

class SliverChipDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  double height = 45;

  SliverChipDelegate(this.child, {this.height = 45});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(SliverChipDelegate oldDelegate) {
    return height != oldDelegate.height;
  }
}

