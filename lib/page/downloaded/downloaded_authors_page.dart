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
import 'package:pixez/component/downloaded_author_card.dart';
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
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: _store.isSearching ? _buildSearchField() : Text('下载的作者'),
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
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => DownloadedPage(),
              ),
            );
          },
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
          color: Theme.of(context).appBarTheme.foregroundColor?.withOpacity(0.6),
        ),
      ),
      style: TextStyle(
        color: Theme.of(context).appBarTheme.foregroundColor,
      ),
    );
  }

  Widget _buildBody() {
    if (_store.authors.isEmpty) {
      if (_store.loading) {
        return Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Text('暂无数据'),
      );
    }

    return PixezEasyRefresh.builder(
      controller: _store.easyRefreshController!,
      onRefresh: () async {
        await _store.loadData(refresh: true);
        _store.easyRefreshController?.finishRefresh();
      },
      onLoad: _store.hasMore
          ? () async {
              await _store.loadMore();
            }
          : null,
      header: PixezDefault.header(context),
      footer: PixezDefault.footer(context),
      childBuilder: (context, physics, scrollController) {
        return CustomScrollView(
          physics: physics,
          controller: scrollController,
          slivers: [
            _buildSortHeader(),
            _buildList(),
          ],
        );
      },
    );
  }

  Widget _buildSortHeader() {
    return SliverPersistentHeader(
      key: ValueKey(
          'sort_header_${_store.sortType}_${_store.showLatestPublished}_${_store.sortDesc}'),
      delegate: SliverChipDelegate(
        Container(
          alignment: Alignment.center,
          child: Stack(
            children: [
              // 居中显示筛选菜单
              Center(
                child: SortGroup(
                  key: ValueKey(_store.sortType),
                  children: [
                    '最新下载',
                    '用户名',
                    '插画数量',
                  ],
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
        Switch(
          value: _store.sortDesc,
          onChanged: _store.onSortOrderChanged,
        ),
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
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < _store.authors.length) {
            final author = _store.authors[index];
            return Observer(
              builder: (context) {
                final illustsData = _store.authorIllustsMap[author.userId];

                // 根据显示模式选择插画：最新下载（索引0）或最新发布（索引1）
                final displayIllusts = illustsData != null
                    ? (_store.showLatestPublished ? illustsData[1] : illustsData[0])
                    : <DownloadedIllust>[];

                return DownloadedAuthorCard(
                  author: author,
                  illusts: displayIllusts,
                  showLatestPublished: _store.showLatestPublished,
                  onRefresh: () => _store.refreshSingleAuthor(author.userId),
                );
              },
            );
          }
          return null;
        },
        childCount: _store.authors.length,
      ),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 600, mainAxisExtent: 210),
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
