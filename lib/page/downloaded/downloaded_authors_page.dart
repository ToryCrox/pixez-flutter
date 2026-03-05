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
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/page/downloaded/widgets/downloaded_author_card.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/component/pixez_easy_refresh.dart';
import 'package:pixez/component/sort_group.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/downloaded_authors_page_store.dart';
import 'package:pixez/page/downloaded/downloaded_page.dart';

class DownloadedAuthorsPage extends StatefulWidget {
  const DownloadedAuthorsPage({Key? key}) : super(key: key);

  @override
  State<DownloadedAuthorsPage> createState() => _DownloadedAuthorsPageState();
}

class _DownloadedAuthorsPageState extends State<DownloadedAuthorsPage> {
  final DownloadedAuthorsPageStore _store = DownloadedAuthorsPageStore();
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;
  ScrollController? _scrollController; // 滚动控制器

  @override
  void initState() {
    super.initState();
    _store.easyRefreshController = EasyRefreshController(
      controlFinishLoad: true,
      controlFinishRefresh: true,
    );
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _searchController.addListener(_onSearchChanged);
    _store.init();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _store.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _store.onSearchChanged(_searchController.text);
  }

  void _toggleSearch() {
    _store.toggleSearch(
      isSearching: !_store.isSearching,
      onClear: () {
        _searchController.clear();
      },
    );
    if (_store.isSearching) {
      _searchFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        return Scaffold(
          appBar: _buildAppBar(),
          body: _buildBody(),
          floatingActionButton: _buildFab(),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title:
          _store.isSearching
              ? _buildSearchField()
              : Observer(
                builder: (_) {
                  return Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '下载的作者 '),
                        if (_store.totalCount > 0)
                          TextSpan(
                            text: '${_store.totalCount}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      actions: [
        IconButton(
          icon: Icon(_store.isSearching ? Icons.close : Icons.search),
          tooltip: _store.isSearching ? '关闭搜索' : '搜索',
          onPressed: _toggleSearch,
        ),
        IconButton(
          icon: Icon(Icons.list),
          tooltip: '下载记录',
          onPressed: () {
            DownloadedPage.open(context);
          },
        ),
        Observer(
          builder: (_) {
            return IconButton(
              icon: Icon(
                _store.markUnprocessed ? Icons.flag : Icons.outlined_flag,
                color:
                    _store.markUnprocessed
                        ? Theme.of(context).colorScheme.primary
                        : null,
              ),
              tooltip: '标记未处理',
              onPressed: () {
                _store.toggleMarkUnprocessed(!_store.markUnprocessed);
              },
            );
          },
        ),
        Observer(
          builder: (_) {
            // 收藏筛选按钮放到 AppBar
            return IconButton(
              icon: Icon(
                _store.showBookmarksOnly
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: _store.showBookmarksOnly ? Colors.red : null,
              ),
              tooltip: '只显示收藏',
              onPressed: () {
                _store.toggleShowBookmarksOnly(!_store.showBookmarksOnly);
              },
            );
          },
        ),
        Observer(builder: (_) => _buildMoreOptionsMenu()),
      ],
    );
  }

  Widget _buildMoreOptionsMenu() {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert),
      tooltip: '更多选项',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == 'update_all') {
          _updateAllAuthorsStats();
        } else if (value == 'toggle_non_webp') {
          _store.toggleShowNonWebpOnly(!_store.showNonWebpOnly);
        }
      },
      itemBuilder:
          (context) => [
            PopupMenuItem(
              value: 'update_all',
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 20),
                  SizedBox(width: 8),
                  Text('批量更新'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'toggle_non_webp',
              child: Row(
                children: [
                  Icon(
                    _store.showNonWebpOnly
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text('非 WebP 过滤'),
                ],
              ),
            ),
          ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      decoration: InputDecoration(
        hintText: '搜索作者名或用户ID',
        border: InputBorder.none,
        hintStyle: TextStyle(
          color: Theme.of(
            context,
          ).appBarTheme.foregroundColor?.withOpacity(0.6),
        ),
      ),
      style: TextStyle(color: Theme.of(context).appBarTheme.foregroundColor),
    );
  }

  Widget _buildBody() {
    if (_store.authors.isEmpty) {
      if (_store.loading) {
        return Center(child: CircularProgressIndicator());
      }
      return Center(child: Text('暂无数据'));
    }

    return PixezEasyRefresh.builder(
      controller: _store.easyRefreshController!,
      onRefresh: () async {
        await _store.loadData(refresh: true);
        _store.easyRefreshController?.finishRefresh();
      },
      onLoad:
          _store.hasMore
              ? () async {
                await _store.loadMore();
              }
              : null,
      header: PixezDefault.header(context),
      footer: PixezDefault.footer(context),
      childBuilder: (context, physics, scrollController) {
        // 保存滚动控制器以便 FAB 使用
        _scrollController = scrollController;
        return CustomScrollView(
          physics: physics,
          controller: scrollController,
          slivers: [_buildSortHeader(), _buildList()],
        );
      },
    );
  }

  Widget _buildSortHeader() {
    return SliverPersistentHeader(
      key: ValueKey(
        'sort_header_${_store.sortType}_${_store.showLatestPublished}_${_store.sortDesc}',
      ),
      delegate: SliverChipDelegate(
        Container(
          alignment: Alignment.center,
          child: Observer(
            builder: (_) {
              return Stack(
                children: [
                  // 居中显示筛选菜单
                  Center(
                    child: SortGroup(
                      key: ValueKey(_store.sortType),
                      children: ['最新下载', '用户名', '文件大小', '作品数量', '插画数量'],
                      onChange: _store.onSortChanged,
                      initIndex: _store.sortType.index,
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
                          SizedBox(width: 8),
                          _buildDisplayModeButton(),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        height: 52,
      ),
      pinned: true,
    );
  }

  Widget _buildSortOrderButton() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _store.sortDesc ? '倒序' : '正序',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(width: 8),
        Switch(value: _store.sortDesc, onChanged: _store.onSortOrderChanged),
      ],
    );
  }

  Widget _buildDisplayModeButton() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _store.showLatestPublished ? '最新发布' : '最新下载',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        SizedBox(width: 8),
        Switch(
          value: _store.showLatestPublished,
          onChanged: _store.toggleDisplayMode,
        ),
      ],
    );
  }

  Widget _buildList() {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index < _store.authors.length) {
          final author = _store.authors[index];
          return Observer(
            builder: (context) {
              final illustsData = _store.authorIllustsMap[author.userId];

              // 根据显示模式选择插画：最新下载（索引0）或最新发布（索引1）
              final displayIllusts =
                  illustsData != null
                      ? (_store.showLatestPublished
                          ? illustsData[1]
                          : illustsData[0])
                      : <DownloadedIllust>[];

              final isMarked = _store.unprocessedUserIds.contains(
                author.userId,
              );

              return DownloadedAuthorCard(
                author: author,
                illusts: displayIllusts,
                showLatestPublished: _store.showLatestPublished,
                onRefresh: () => _store.refreshSingleAuthor(author.userId),
                isMarked: isMarked,
                onBookmarkChanged: (bookmark) {
                  _store.updateBookmark(author.userId, bookmark);
                },
              );
            },
          );
        }
        return null;
      }, childCount: _store.authors.length),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 600,
        mainAxisExtent: 210,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
    );
  }

  // ============ FAB 相关 ============

  Widget _buildFab() {
    return Observer(
      builder:
          (_) => FloatingActionButton(
            onPressed:
                _store.isRefreshing
                    ? null
                    : () async {
                      // 先滚动到顶部
                      if (_scrollController?.hasClients == true) {
                        await _scrollController!.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                      // 然后刷新
                      _store.refresh();
                    },
            tooltip: _store.isRefreshing ? '刷新中...' : '刷新数据',
            child:
                _store.isRefreshing
                    ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    )
                    : Icon(Icons.refresh),
          ),
    );
  }

  Future<void> _updateAllAuthorsStats() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _UpdateAuthorsDialog(store: _store),
    );
  }
}

/// 批量更新作者信息的对话框
class _UpdateAuthorsDialog extends StatefulWidget {
  final DownloadedAuthorsPageStore store;

  const _UpdateAuthorsDialog({required this.store});

  @override
  State<_UpdateAuthorsDialog> createState() => _UpdateAuthorsDialogState();
}

class _UpdateAuthorsDialogState extends State<_UpdateAuthorsDialog> {
  // 对话框状态：idle（初始）、updating（更新中）、completed（完成）、error（错误）
  String _status = 'idle';
  int _current = 0;
  int _total = 0;
  String? _errorMessage;

  Future<void> _startUpdate() async {
    setState(() {
      _status = 'updating';
      _current = 0;
      _total = 0;
    });

    try {
      await widget.store.updateAllAuthorsStats(
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _current = current;
              _total = total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _status = 'completed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'error';
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_getTitle()),
      content: _buildContent(),
      actions: _buildActions(),
    );
  }

  String _getTitle() {
    switch (_status) {
      case 'idle':
        return '更新作者信息';
      case 'updating':
        return '正在更新...';
      case 'completed':
        return '更新完成';
      case 'error':
        return '更新失败';
      default:
        return '更新作者信息';
    }
  }

  Widget _buildContent() {
    switch (_status) {
      case 'idle':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将重新计算所有作者的统计信息：'),
            SizedBox(height: 8),
            Text(
              '• 作品数量',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            Text(
              '• 图片数量',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            Text(
              '• 文件大小',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            SizedBox(height: 16),
            Text('是否继续？', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        );

      case 'updating':
        final progress = _total > 0 ? _current / _total : 0.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress),
            SizedBox(height: 16),
            Text(
              _total == 0 ? '正在准备...' : '进度: $_current / $_total',
              style: TextStyle(fontSize: 16),
            ),
            if (_total > 0) ...[
              SizedBox(height: 8),
              Text(
                '${(progress * 100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ],
        );

      case 'completed':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 48),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '成功更新',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '已更新 $_total 位作者的信息',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );

      case 'error':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 48),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '更新失败',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        _errorMessage ?? '未知错误',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );

      default:
        return SizedBox.shrink();
    }
  }

  List<Widget> _buildActions() {
    switch (_status) {
      case 'idle':
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消'),
          ),
          ElevatedButton(onPressed: _startUpdate, child: Text('开始')),
        ];

      case 'updating':
        return [
          TextButton(
            onPressed: null, // 更新中不允许取消
            child: Text('更新中...'),
          ),
        ];

      case 'completed':
      case 'error':
        return [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('完成'),
          ),
        ];

      default:
        return [];
    }
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
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(SliverChipDelegate oldDelegate) {
    return height != oldDelegate.height;
  }
}
