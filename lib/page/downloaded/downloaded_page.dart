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
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/utils/file_utils.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/picture_list_page.dart';
import 'package:pixez/page/downloaded/downloaded_authors_page.dart';
import 'package:pixez/page/downloaded/downloaded_page_store.dart';
import 'package:pixez/page/downloaded/tag_manager/tag_manager_page.dart' hide SliverChipDelegate;

import 'package:super_drag_and_drop/super_drag_and_drop.dart';


import 'package:pixez/page/downloaded/optimize_json_dialog.dart';
import 'package:pixez/page/downloaded/update_illust_info_dialog.dart';
import 'package:pixez/store/download_store.dart';
import 'package:pixez/component/pixez_easy_refresh.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/component/sort_group.dart';
import 'package:pixez/constants.dart';
import '../../component/pixiv_image.dart';

class DownloadedPage extends StatefulWidget {
  final int? initialUserId;
  final String? initialUserName;
  final String? initialSearchKeyword;
  final String? initialTagName;

  const DownloadedPage({
    Key? key,
    this.initialUserId,
    this.initialUserName,
    this.initialSearchKeyword,
    this.initialTagName,
  }) : super(key: key);

  @override
  State<DownloadedPage> createState() => _DownloadedPageState();
}

class _DownloadedPageState extends State<DownloadedPage> {
  late DownloadedPageStore _store;
  late EasyRefreshController _easyRefreshController;
  Offset? _tapPosition;
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _easyRefreshController = EasyRefreshController(
      controlFinishLoad: true,
      controlFinishRefresh: true,
    );
    _store = DownloadedPageStore();
    _store.easyRefreshController = _easyRefreshController;
    _searchController = TextEditingController(text: widget.initialSearchKeyword);
    _searchFocusNode = FocusNode();
    _searchController.addListener(_onSearchChanged);
    _store.init(
      initialUserId: widget.initialUserId,
      initialUserName: widget.initialUserName,
      initialSearchKeyword: widget.initialSearchKeyword,
      initialTagName: widget.initialTagName,
    );
     // Set text controller if search keyword is provided (but not tags, as tags are shown in title)
    if (widget.initialSearchKeyword?.isNotEmpty == true) {
      _searchController.text = widget.initialSearchKeyword!;
    }
  }

  @override
  void dispose() {
    _store.dispose();
    _easyRefreshController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
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
      builder: (_) => Scaffold(
        appBar: _buildAppBar(),
        body: _buildBody(),
      ),
    );
  }

  // ============ AppBar 相关 ============

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: _store.isSearching ? _buildSearchField() : _buildAppBarTitle(),
      actions: [
        IconButton(
          icon: Icon(_store.isSearching ? Icons.close : Icons.search),
          tooltip: _store.isSearching ? '关闭搜索' : '搜索',
          onPressed: _toggleSearch,
        ),
        if (!_store.isSearching) ...[

          _buildAuthorsButton(),
          _buildTagsButton(),
          _buildMoreMenu(),
        ],
      ],
    );
  }

  Widget _buildAppBarTitle() {
    final title = _store.filterUserName ?? _store.filterTagName ?? '已下载';
    final stats = _store.stats;

    if (stats == null) {
      return Text(title);
    }

    final illustCount = stats['illust_count'] ?? 0;
    final imageCount = stats['image_count'] ?? 0;
    final fileSize = stats['file_size'] ?? 0;

    if (illustCount == 0 && imageCount == 0 && fileSize == 0) {
      return Text(title);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title),
        SizedBox(width: 8),
        Text(
          '${illustCount}作品 · ${imageCount}图 · ${fileSize.formatFileSize()}',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
        hintText: '搜索标题，用户或者标签',
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



  Widget _buildAuthorsButton() {
    return IconButton(
      icon: const Icon(Icons.people),
      tooltip: '作者列表',
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DownloadedAuthorsPage(),
          ),
        );
      },
    );
  }

  Widget _buildTagsButton() {
    return IconButton(
      icon: const Icon(Icons.label),
      tooltip: '标签管理',
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const TagManagerPage(),
          ),
        );
      },
    );
  }

  Widget _buildMoreMenu() {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert),
      onSelected: _onMenuSelected,
      itemBuilder: (context) => [
        ..._buildFilterMenuItems(),
        PopupMenuDivider(),
        ..._buildActionMenuItems(),
        PopupMenuDivider(),
        ..._buildDownloadControlMenuItems(),
        PopupMenuDivider(),
         PopupMenuItem(
          enabled: false,
          child: Text('拖拽设置', style: TextStyle(
              fontSize: 12, color: Theme.of(context).disabledColor)),
        ),
        CheckedPopupMenuItem(
          value: 'toggle_drag_only_non_webp',
          checked: _store.dragOnlyNonWebp,
          child: Text('仅拖拽非WebP图片'),
        ),
        CheckedPopupMenuItem(
          value: 'toggle_mouse_drag_scroll',
          checked: _store.disableMouseDragScroll,
          child: Text('禁用鼠标拖拽滚动'),
        ),
      ],
    );
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'filter_all':
        _store.onFilterChanged(DownloadFilter.all);
        break;
      case 'filter_downloading':
        _store.onFilterChanged(DownloadFilter.downloading);
        break;
      case 'filter_completed':
        _store.onFilterChanged(DownloadFilter.completed);
        break;
      case 'filter_incomplete':
        _store.onFilterChanged(DownloadFilter.incomplete);
        break;
      case 'update_info':
        _showUpdateIllustInfoDialog();
        break;
      case 'pause_all':
        _store.pauseAll();
        break;
      case 'resume_all':
        _store.resumeAll();
        break;
      case 'cancel_all':
        _store.cancelAll();
        break;
      case 'toggle_drag_only_non_webp':
        _store.setDragOnlyNonWebp(!_store.dragOnlyNonWebp);
        break;
      case 'optimize_json':
        OptimizeJsonDialog.show(context, downloadStore);
        break;
      case 'toggle_mouse_drag_scroll':
        _store.toggleMouseDragScroll();
        break;
    }
  }

  List<PopupMenuEntry<String>> _buildFilterMenuItems() {
    return [
      _buildFilterMenuItem(
        value: 'filter_all',
        icon: Icons.list,
        label: I18n.of(context).all,
        isSelected: _store.downloadFilter == DownloadFilter.all,
      ),
      _buildFilterMenuItem(
        value: 'filter_downloading',
        icon: Icons.downloading,
        label: I18n.of(context).running,
        isSelected: _store.downloadFilter == DownloadFilter.downloading,
      ),
      _buildFilterMenuItem(
        value: 'filter_completed',
        icon: Icons.check_circle_outline,
        label: I18n.of(context).complete,
        isSelected: _store.downloadFilter == DownloadFilter.completed,
      ),
      _buildFilterMenuItem(
        value: 'filter_incomplete',
        icon: Icons.warning_amber,
        label: '未下载完整',
        isSelected: _store.downloadFilter == DownloadFilter.incomplete,
      ),
    ];
  }

  PopupMenuItem<String> _buildFilterMenuItem({
    required String value,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: isSelected ? primaryColor : null),
          SizedBox(width: 8),
          Text(label),
          if (isSelected)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Icon(Icons.check, size: 16, color: primaryColor),
            ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildActionMenuItems() {
    return [
      PopupMenuItem(
        value: 'update_info',
        child: Row(
          children: [
            Icon(Icons.update),
            SizedBox(width: 8),
            Text('更新插画信息'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'optimize_json',
        child: Row(
          children: [
            Icon(Icons.storage, color: Colors.orange),
            SizedBox(width: 8),
            Text('优化数据库存储'),
          ],
        ),
      ),
    ];
  }

  List<PopupMenuEntry<String>> _buildDownloadControlMenuItems() {
    return [
      PopupMenuItem(
        value: 'pause_all',
        child: Row(
          children: [
            Icon(Icons.pause_circle_outline),
            SizedBox(width: 8),
            Text('暂停${I18n.of(context).all}'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'resume_all',
        child: Row(
          children: [
            Icon(Icons.play_circle_outline),
            SizedBox(width: 8),
            Text('${I18n.of(context).start}${I18n.of(context).all}'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'cancel_all',
        child: Row(
          children: [
            Icon(Icons.cancel, color: Colors.red),
            SizedBox(width: 8),
            Text(
              '取消${I18n.of(context).all}',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
      ),
    ];
  }

  // ============ Body 相关 ============

  Widget _buildBody() {
    if (_store.loading && _store.filteredIllusts.isEmpty) {
      return Center(child: CircularProgressIndicator());
    }

    if (_store.filteredIllusts.isEmpty) {
      return _buildEmptyView();
    }

    return _buildRefreshableContent();
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.download_done, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            I18n.of(context).no_result,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshableContent() {
    return PixezEasyRefresh.builder(
      controller: _easyRefreshController,
      onRefresh: _store.isMultiSelectMode
          ? null
          : () async {
              await _store.refresh();
            },
      onLoad: _store.isMultiSelectMode ? null : _store.loadMore,
      header: PixezDefault.header(context),
      footer: PixezDefault.footer(context),
      childBuilder: (context, physics, scrollController) {
        return Observer(builder: (context) {
          return ScrollConfiguration(
            behavior: _store.disableMouseDragScroll
                ? ScrollConfiguration.of(context).copyWith(
                    dragDevices: ScrollConfiguration.of(context)
                        .dragDevices
                        .where((k) => k != PointerDeviceKind.mouse)
                        .toSet(),
                  )
                : ScrollConfiguration.of(context),
            child: CustomScrollView(
              physics: physics,
              controller: scrollController,
              slivers: [
                _buildSortHeader(),
                _buildGridView(),
              ],
            ),
          );
        });
      },
    );
  }

  Widget _buildSortHeader() {
    return SliverPersistentHeader(
      key: ValueKey('sort_header_${_store.sortType}_${_store.sortDesc}'),
      delegate: SliverChipDelegate(
        Container(
          alignment: Alignment.center,
          child: Stack(
            children: [
              Center(
                child: SortGroup(
                  key: ValueKey(_store.sortType),
                  children: ['下载时间', '作品时间', '文件大小', '平均大小'],
                  onChange: _store.onSortChanged,
                  initIndex: _store.sortType.index,
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(child: _buildSortOrderButton()),
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

  Widget _buildGridView() {
    final filteredList = _store.filteredIllusts;
    return SliverPadding(
      padding: EdgeInsets.all(8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          childAspectRatio: 0.7,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= filteredList.length) {
              return Center(child: CircularProgressIndicator());
            }
            return _DownloadedIllustCard(
              illust: filteredList[index],
              store: _store,
              onTapPosition: (pos) => _tapPosition = pos,
              onTap: () => _navigateToPictureList(filteredList[index]),
              onLongPress: () => _showContextMenu(
                context,
                filteredList[index],
                _tapPosition,
              ),
              onSecondaryTap: () => _showContextMenu(
                context,
                filteredList[index],
                _tapPosition,
              ),
              onOpenFolder: () => _openIllustFolder(filteredList[index]),
              onRefreshData: () {
                _store.loadData();
                _store.loadStats();
              },
              onAuthorTap: () => _navigateToAuthorDownloadedPage(filteredList[index]),
            );
          },
          childCount: filteredList.length + (_store.loadingMore ? 1 : 0),
        ),
      ),
    );
  }

  // ============ 导航与操作 ============

  void _navigateToPictureList(DownloadedIllust illust) async {
    final iStores = _store.filteredIllusts.map((item) {
      return IllustStore(item.illustId, item.toIllusts());
    }).toList();

    final currentIndex = _store.filteredIllusts.indexOf(illust);
    final currentStore = iStores[currentIndex];

    Leader.push(
      context,
      PictureListPage(
        iStores: iStores,
        store: currentStore,
        lightingStore: null,
        heroString: 'downloaded_illust_${illust.illustId}',
      ),
    );
  }

  void _navigateToAuthorDownloadedPage(DownloadedIllust illust) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DownloadedPage(
          initialUserId: illust.userId,
          initialUserName: illust.userName,
        ),
      ),
    );
  }

  Future<void> _openIllustFolder(DownloadedIllust illust) async {
    final dirPath = downloadStore.getIllustDirectoryPath(illust);
    if (dirPath != null) {
      await FileUtils.openFileOrDirectory(dirPath);
    }
  }

  // ============ 对话框 ============



  void _showUpdateIllustInfoDialog() async {
    List<DownloadedIllust> illustsToUpdate;

    if (_store.filterUserId != null) {
      illustsToUpdate = await downloadStore.getDownloadedByUser(
        _store.filterUserId!,
        limit: null,
        offset: 0,
      );
    } else {
      illustsToUpdate = List.from(_store.filteredIllusts);
    }

    if (illustsToUpdate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('没有需要更新的作品')),
      );
      return;
    }

    await showDialog(
      context: context,
      useRootNavigator: false, // 使用当前 Navigator 而不是根 Navigator
      builder: (context) => UpdateIllustInfoDialog(illusts: illustsToUpdate),
    );

    _store.loadData();
    _store.loadStats();
  }

  Future<bool?> _showDeleteConfirmDialog(List<DownloadedIllust> illusts) {
    return showDialog<bool>(
      context: context,
      builder: (ctx2) {
        return AlertDialog(
          title: Text(I18n.of(context).delete),
          content: Text('确认删除 ${illusts.length} 项作品吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2, false),
              child: Text(I18n.of(context).cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx2, true),
              child: Text(
                I18n.of(context).ok,
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteIllusts(List<DownloadedIllust> illusts) async {
    final confirm = await _showDeleteConfirmDialog(illusts);
    if (confirm == true) {
      for (final illust in illusts) {
        downloadStore.cancelIllustDownload(illust.illustId);
        await downloadStore.deleteDownloadedIllust(illust.illustId);
      }
      _store.loadStats();
      if (_store.isMultiSelectMode) {
        _store.exitMultiSelectMode();
      }
    }
  }

  // ============ 右键菜单 ============

  void _showContextMenu(
      BuildContext context, DownloadedIllust illust, Offset? tapPosition) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final localPosition =
        tapPosition != null ? overlay.globalToLocal(tapPosition) : Offset.zero;

    final isMulti = _store.isMultiSelectMode;
    final selectedCount = _store.selectedIllustIds.length;
    
    // 如果在多选模式下，且当前item未选中，则只对当前item操作? 
    // 或者通常右键点击未选中项会选中它并取消其他？
    // 这里简化逻辑：如果是多选模式，且当前item已选中，则对所有选中项操作。
    // 如果未选中，则只对当前item操作（如同单选）。
    final isSelectedInMulti = isMulti && _store.selectedIllustIds.contains(illust.illustId);
    
    final targetIllusts = isSelectedInMulti 
        ? _store.filteredIllusts.where((i) => _store.selectedIllustIds.contains(i.illustId)).toList()
        : [illust];

    final status = _store.illustDownloadStatus[illust.illustId];
    final isDownloading = status == DownloadTaskStatus.downloading ||
        status == DownloadTaskStatus.pending;
    final isPaused = status == DownloadTaskStatus.paused;
    final isFailed = status == DownloadTaskStatus.failed;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        localPosition & Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (isMulti)
          PopupMenuItem(
            child: Text('已选择 $selectedCount 项'),
            enabled: false,
          ),
        
        // 切换多选模式
        _buildContextMenuItem(
          icon: isMulti ? Icons.check_box_outline_blank : Icons.check_box,
          label: isMulti ? '退出多选模式' : '进入多选模式',
          onTap: () {
            if (isMulti) {
              _store.exitMultiSelectMode();
            } else {
              _store.enterMultiSelectMode();
              _store.selectItem(illust.illustId);
            }
          },
        ),
        
        _buildContextMenuItem(
          icon: Icons.open_in_new,
          label: I18n.of(context).detail,
          onTap: () => _navigateToPictureList(illust),
        ),

        if (!isMulti) ...[
          if (_store.filterTagName != null)
            _buildContextMenuItem(
              icon: _store.exampleIllustIds.contains(illust.illustId)
                  ? Icons.star
                  : Icons.star_border,
              label: _store.exampleIllustIds.contains(illust.illustId)
                  ? '取消示例插画'
                  : '设置为示例插画',
              onTap: () async {
                final tagName = _store.filterTagName!;
                final tagData = tagManagerStore.getTagDisplayData(tagName);
                if (tagData != null) {
                  final imageUrls = illust.getImageUrls();
                  String coverUrl = imageUrls.squareMedium;
                  if (coverUrl.isEmpty) {
                    final illusts = illust.toIllusts();
                    coverUrl = illusts.imageUrls.squareMedium;
                  }
                  await tagManagerStore.toggleExampleIllust(
                      tagData.tag.id, illust.illustId, coverUrl);
                  _store.exampleIllustIds.clear();
                  _store.exampleIllustIds.addAll(
                      tagManagerStore.getTagDisplayData(tagName)!.tag.exampleIllustIds);
                }
              },
            ),
          _buildContextMenuItem(
            icon: Icons.folder_open,
            label: I18n.of(context).save_path,
            onTap: () => _openIllustFolder(illust),
          ),
          _buildContextMenuItem(
            icon: Icons.copy,
            label: '复制路径',
            onTap: () {
              final path = downloadStore.getIllustDirectoryPath(illust);
              if (path != null) {
                // 在这里为复制的路径添加双引号，方便在其他地方粘贴使用
                Clipboard.setData(ClipboardData(text: path));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('路径已复制到剪贴板')),
                );
              }
            },
          ),
          if (isDownloading)
            _buildContextMenuItem(
              icon: Icons.pause,
              label: '暂停',
              onTap: () => downloadStore.pauseIllustDownload(illust.illustId),
            ),
          if (isPaused || isFailed)
            _buildContextMenuItem(
              icon: Icons.play_arrow,
              label: I18n.of(context).retry,
              onTap: () => downloadStore.resumeIllustDownload(illust.illustId),
            ),
        ],

        _buildContextMenuItem(
          icon: Icons.update,
          label: isSelectedInMulti ? '更新选中信息 ($selectedCount)' : '更新插画信息',
          onTap: () async {
            await showDialog(
              context: context,
              builder: (context) => UpdateIllustInfoDialog(
                illusts: targetIllusts,
              ),
            );
            _store.loadData();
          },
        ),
        _buildContextMenuItem(
          icon: Icons.delete,
          iconColor: Colors.red,
          label: isSelectedInMulti ? '删除选中 ($selectedCount)' : I18n.of(context).delete,
          labelColor: Colors.red,
          onTap: () => _deleteIllusts(targetIllusts),
        ),
      ],
    );
  }

  PopupMenuItem<void> _buildContextMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    Color? labelColor,
  }) {
    return PopupMenuItem(
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          SizedBox(width: 8),
          Text(label,
              style: labelColor != null ? TextStyle(color: labelColor) : null),
        ],
      ),
      onTap: onTap,
    );
  }


}

// ============ 独立组件 ============

/// 已下载插画卡片组件
class _DownloadedIllustCard extends StatelessWidget {
  final DownloadedIllust illust;
  final DownloadedPageStore store;
  final ValueChanged<Offset> onTapPosition;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSecondaryTap;
  final VoidCallback onOpenFolder;
  final VoidCallback onRefreshData;
  final VoidCallback? onAuthorTap;

  const _DownloadedIllustCard({
    required this.illust,
    required this.store,
    required this.onTapPosition,
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTap,
    required this.onOpenFolder,
    required this.onRefreshData,
    this.onAuthorTap,
  });

  Widget _buildThumbnail(BuildContext context) {
    final heroTag = 'downloaded_illust_${illust.illustId}';

    final imageUrls = illust.getImageUrls();
    String coverUrl = imageUrls.squareMedium;
    if (coverUrl.isEmpty) {
      final illusts = illust.toIllusts();
      coverUrl = illusts.imageUrls.squareMedium;
    }

    // 获取对应布局的质量标识
    // 目前 DownloadedPage 使用 SliverGrid，固定为网格模式。
    // 如果将来支持瀑布流模式，可以根据布局模式选择使用 Constants.qualitySquareMedium 或根据 feedPreviewQuality 选择质量。
    String quality = Constants.qualitySquareMedium;
    
    // 预留瀑布流布局的自适应逻辑（目前 useFeedPreview 为 false）
    /*
    if (useFeedPreview) {
      if (userSetting.feedPreviewQuality == Constants.qualityLevelMedium) {
        quality = Constants.qualityMedium;
      } else if (userSetting.feedPreviewQuality == Constants.qualityLevelLarge) {
        quality = Constants.qualityLarge;
      } else if (userSetting.feedPreviewQuality == Constants.qualityLevelOriginal) {
        quality = Constants.qualityOriginal;
      }
    }
    */

    // 计算建议的内存缓存宽度，避免内存占用过高
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final int? memCacheWidth = (240 * devicePixelRatio).toInt();

    Widget imageWidget = PixivImage(
      coverUrl,
      fit: BoxFit.cover,
      httpHeaders: {
        'cover': '${illust.illustId}',
        'quality': quality,
      },
      memCacheWidth: memCacheWidth,
    );

    return Hero(
      tag: heroTag,
      child: imageWidget,
    );
  }

  Widget _buildFolderButton(BuildContext context) {
    return Positioned(
      top: 4,
      left: 4,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpenFolder,
          child: Container(
            padding: EdgeInsets.all(6),
            child: Icon(
              Icons.folder_open,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final status = store.illustDownloadStatus[illust.illustId];
        final isSelected = store.isMultiSelectMode &&
            store.selectedIllustIds.contains(illust.illustId);

        final card = _buildCard(context, status, isSelected);

        // 拖拽逻辑
        return DragItemWidget(
          dragItemProvider: _createDragItemProvider,
          allowedOperations: () => [DropOperation.copy, DropOperation.link],
          dragBuilder: (context, child) =>
              _buildDragPreview(context, child, isSelected),
          child: DraggableWidget(
            child: card,
            onDragConfiguration: (config, session) =>
                _createDragConfiguration(config, session, isSelected),
          ),
        );
      },
    );
  }

  Widget _buildCard(
      BuildContext context, DownloadTaskStatus? status, bool isSelected) {
    final isDownloading = status == DownloadTaskStatus.downloading;
    final isPending = status == DownloadTaskStatus.pending;
    final isPaused = status == DownloadTaskStatus.paused;
    final isFailed = status == DownloadTaskStatus.failed;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: isSelected
          ? RoundedRectangleBorder(
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: InkWell(
        onTap: () {
          if (store.isMultiSelectMode) {
            store.setItemSelected(illust.illustId, !isSelected);
          } else {
            onTap();
          }
        },
        onTapDown: (details) => onTapPosition(details.globalPosition),
        onLongPress: store.isMultiSelectMode ? null : onLongPress,
        onSecondaryTapUp: (details) {
          onTapPosition(details.globalPosition);
          onSecondaryTap();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildThumbnail(context),
                  _buildFolderButton(context),
                  if (illust.isUgoira) _buildUgoiraBadge(context),
                  if (store.exampleIllustIds.contains(illust.illustId))
                    _buildExampleBadge(context),
                  if (isDownloading) _buildDownloadingOverlay(),
                  if (isPending) _buildPendingOverlay(context),
                  if (isPaused)
                    _buildStatusBadge(
                        context, I18n.of(context).paused, Colors.orange),
                  if (isFailed)
                    _buildStatusBadge(
                        context, I18n.of(context).failed, Colors.red),
                  // 多选模式下的复选框指示器
                  if (store.isMultiSelectMode)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black45,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: isSelected
                              ? Icon(Icons.check, size: 16, color: Colors.white)
                              : SizedBox(width: 16, height: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _buildInfoSection(context),
          ],
        ),
      ),
    );
  }

  Future<DragConfiguration?> _createDragConfiguration(
      DragConfiguration config, DragSession session, bool isSelected) async {
    // 处理多选和文件过滤逻辑
    final selectedIds = <int>[];
    if (store.isMultiSelectMode) {
      selectedIds.addAll(store.selectedIllustIds);
      // 如果当前拖拽的项不在选中列表中，则只拖拽当前项（或者视为单选拖拽）
      if (!selectedIds.contains(illust.illustId)) {
        selectedIds.clear();
        selectedIds.add(illust.illustId);
      }
    } else {
      selectedIds.add(illust.illustId);
    }

    if (selectedIds.isEmpty) return null;

    // 获取 snapshot (复用当前拖拽项的 snapshot)
    final snapshot = config.items.firstOrNull?.image;
    if (snapshot == null) return null;

    final targetIllusts = store.filteredIllusts
        .where((i) => selectedIds.contains(i.illustId))
        .toList();

    // 确保至少包含当前插画
    if (targetIllusts.isEmpty && selectedIds.contains(illust.illustId)) {
      targetIllusts.add(illust);
    }

    final newItems = <DragConfigurationItem>[];

    if (store.dragOnlyNonWebp) {
      // 优化：使用批量查询获取所有图片记录，避免循环 await
      try {
        final allImages = await downloadStore.dbProvider.getImagesByIllustIds(
            targetIllusts.map((e) => e.illustId).toList());

        // 按 illustId 分组
        final imagesMap = <int, List<DownloadedImage>>{};
        for (final img in allImages) {
          imagesMap.putIfAbsent(img.illustId, () => []).add(img);
        }

        for (final targetIllust in targetIllusts) {
          final images = imagesMap[targetIllust.illustId] ?? [];
          for (final image in images) {
            // 过滤非 WebP 图片
            if (image.extension.toLowerCase() != '.webp') {
              final fullPath = downloadStore.dbProvider
                  .getAbsolutePath(image.relativePath, image.getFullFileName());
              
              final dragItem = DragItem();
              dragItem.add(Formats.fileUri(Uri.file(fullPath)));
              newItems.add(DragConfigurationItem(
                item: dragItem,
                image: snapshot,
              ));
            }
          }
        }
      } catch (e) {
        // Fallback or ignore
      }
    } else {
      // 默认拖拽整个文件夹 (无需数据库查询，直接字符串拼接，速度极快)
      for (final targetIllust in targetIllusts) {
        final dirPath = downloadStore.getIllustDirectoryPath(targetIllust);
        if (dirPath != null) {
          final dragItem = DragItem();
          dragItem.add(Formats.fileUri(Uri.file(dirPath)));
          newItems.add(DragConfigurationItem(
            item: dragItem,
            image: snapshot,
          ));
        }
      }
    }

    if (newItems.isEmpty) return null;

    return DragConfiguration(
      items: newItems,
      allowedOperations: config.allowedOperations,
      options: config.options,
    );
  }

  // 原始方法已废弃，直接在 _createDragConfiguration 中批量处理
  // Future<List<Uri>> _getIllustFileUris...

  Widget _buildUgoiraBadge(BuildContext context) {
    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '动图',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildExampleBadge(BuildContext context) {
    return Positioned(
      top: 4,
      right: illust.isUgoira ? 40 : 4,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blueAccent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star, color: Colors.white, size: 10),
            SizedBox(width: 2),
            Text(
              '示例',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black38,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingOverlay(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black26,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hourglass_empty,
                color: Colors.white,
                size: 32,
              ),
              SizedBox(height: 4),
              Text(
                '等待下载',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, String text, Color color) {
    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(color: Colors.white, fontSize: 10),
        ),
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            illust.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: onAuthorTap != null
                    ? InkWell(
                        onTap: store.isMultiSelectMode ? null : onAuthorTap,
                        borderRadius: BorderRadius.circular(4),
                        child: Text(
                          illust.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                                decorationColor: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      )
                    : Text(
                        illust.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
              ),
              Text(
                illust.createDate.toShortDate(),
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                      fontSize: 11,
                    ),
              ),
            ],
          ),
          _buildStatsRow(context),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    final totalFileSize = illust.totalFileSize;  // 使用物化字段
    final isUgoira = illust.isUgoira;

    return Row(
      children: [
        // 动图或多页插画都显示页数/帧数信息
        if (isUgoira || illust.pageCount > 1)
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: _buildPageCountIndicator(context, totalFileSize, isUgoira),
          ),
        Spacer(),
        if (totalFileSize > 0)  // 物化字段不为 null
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              totalFileSize.formatFileSize(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildPageCountIndicator(BuildContext context, int? totalFileSize, bool isUgoira) {
    if (isUgoira) {
      // 动图特殊处理：显示帧数
      return _buildUgoiraFrameIndicator(context, totalFileSize);
    }

    // 普通插画：显示页数
    final downloadedCount = illust.downloadedImageCount;  // 使用物化字段
    final totalCount = illust.pageCount;

    String pageText;
    if (downloadedCount < totalCount) {
      pageText = '$downloadedCount/$totalCount';
    } else {
      pageText = '${totalCount}P';
    }

    String? avgSizeText;
    if (totalFileSize != null && totalFileSize > 0 && totalCount > 0) {
      final avgSize = totalFileSize ~/ totalCount;
      avgSizeText = avgSize.formatFileSize();
    }

    if (avgSizeText != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pageText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: downloadedCount < totalCount ? Colors.orange : null,
                ),
          ),
          SizedBox(width: 4),
          Text(
            '· $avgSizeText/P',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
          ),
        ],
      );
    } else {
      return Text(
        pageText,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: downloadedCount < totalCount ? Colors.orange : null,
            ),
      );
    }
  }

  /// 构建动图帧数指示器
  Widget _buildUgoiraFrameIndicator(BuildContext context, int? totalFileSize) {
    final downloadedCount = illust.downloadedImageCount;  // 使用物化字段

    // 动图的 downloadedCount 包含预览图(part=0)和所有帧(part=1,2,3...)
    // 实际帧数 = downloadedCount - 1（如果下载完整的话）
    final frameCount = downloadedCount > 0 ? downloadedCount - 1 : 0;

    String frameText;
    if (frameCount > 0) {
      frameText = '${frameCount}帧';
    } else {
      frameText = '动图';
    }

    // 计算平均每帧大小
    String? avgSizeText;
    if (totalFileSize != null && totalFileSize > 0 && frameCount > 0) {
      final avgSize = totalFileSize ~/ frameCount;
      avgSizeText = avgSize.formatFileSize();
    }

    if (avgSizeText != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            frameText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
          ),
          SizedBox(width: 4),
          Text(
            '· $avgSizeText/帧',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
          ),
        ],
      );
    } else {
      return Text(
        frameText,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.orange,
              fontWeight: FontWeight.w500,
            ),
      );
    }
  }
  Widget _buildDragPreview(
      BuildContext context, Widget child, bool isSelected) {
    // 如果多选，显示数量角标
    final count = store.isMultiSelectMode && isSelected
        ? store.selectedIllustIds.length
        : 1;

    // 拖动时透明度太低问题：
    // 使用 Material 并不透明背景，包裹 Opacity 控制透明度（如果需要）
    // 或者完全不透明。用户反馈“看不清楚”，倾向于更不透明。

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 150,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            child, // 复用 Card
            if (count > 1)
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<DragItem> _createDragItemProvider(DragItemRequest request) async {
    final item = DragItem();
    item.add(Formats.plainText('PixEz Downloaded Illust'));
    return item;
  }
}

