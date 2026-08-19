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

import 'dart:io' as io;

import 'package:easy_refresh/easy_refresh.dart';
import 'package:pixez/component/pixez_easy_refresh.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/utils/file_utils.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/downloaded_image_organizer_page.dart';
import 'package:pixez/page/downloaded/downloaded_page_store.dart';
import 'package:pixez/page/downloaded/optimize_json_dialog.dart';
import 'package:pixez/page/downloaded/sync_bookmarks_dialog.dart';

import 'package:pixez/page/downloaded/update_illust_info_dialog.dart';
import 'package:pixez/page/downloaded/bookmark_priority_dialog.dart';
import 'package:pixez/page/downloaded/original_import_dialog.dart';
import 'package:pixez/page/downloaded/original_author_import_dialog.dart';
import 'package:pixez/page/downloaded/original_version_manager_dialog.dart';
import 'package:pixez/page/downloaded/original_import_recovery_dialog.dart';
import 'package:pixez/page/downloaded/local_original_work_dialog.dart';
import 'package:pixez/page/downloaded/link_local_work_dialog.dart';
import 'package:pixez/page/downloaded/edit_local_work_dialog.dart';
import 'package:pixez/page/downloaded/translation_result_replace_dialog.dart';
import 'package:pixez/page/downloaded/translation_result_directory_dialog.dart';
import 'package:pixez/main.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/picture_list_page.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/store/download_store.dart';
import 'package:pixez/component/sort_group.dart';
import 'package:pixez/page/downloaded/widgets/downloaded_illust_card.dart';
import 'package:pixez/page/user/users_page.dart';
import 'package:pixez/utils/translation_result_replacer.dart';

class DownloadedPage extends StatefulWidget {
  final int? initialUserId;
  final String? initialUserName;
  final String? initialSearchKeyword;
  final int? initialTagId;

  const DownloadedPage({
    Key? key,
    this.initialUserId,
    this.initialUserName,
    this.initialSearchKeyword,
    this.initialTagId,
  }) : super(key: key);

  static Future<T?> open<T>(
    BuildContext context, {
    int? userId,
    String? userName,
    String? searchKeyword,
    int? tagId,
  }) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(
        builder:
            (context) => DownloadedPage(
              initialUserId: userId,
              initialUserName: userName,
              initialSearchKeyword: searchKeyword,
              initialTagId: tagId,
            ),
      ),
    );
  }

  @override
  State<DownloadedPage> createState() => _DownloadedPageState();
}

class _DownloadedPageState extends State<DownloadedPage> {
  late DownloadedPageStore _store;
  late EasyRefreshController _easyRefreshController;
  Offset? _tapPosition;
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;
  ScrollController? _scrollController; // 滚动控制器

  bool get _isDesktop =>
      io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _easyRefreshController = EasyRefreshController(
      controlFinishLoad: true,
      controlFinishRefresh: true,
    );
    _store = DownloadedPageStore();
    _store.easyRefreshController = _easyRefreshController;
    _searchController = TextEditingController(
      text: widget.initialSearchKeyword,
    );
    _searchFocusNode = FocusNode();
    _searchController.addListener(_onSearchChanged);
    _store.init(
      initialUserId: widget.initialUserId,
      initialUserName: widget.initialUserName,
      initialSearchKeyword: widget.initialSearchKeyword,
      initialTagId: widget.initialTagId,
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

  Future<void> _openImageOrganizer() async {
    if (_store.filterUserId != null) {
      final author = await downloadStore.getAuthorByUserId(
        _store.filterUserId!,
      );
      if (author != null && context.mounted) {
        DownloadedImageOrganizerPage.open(context, author: author);
      }
      return;
    }

    final illusts = await downloadStore.getDownloadedWithNonWebPImages();
    if (!mounted) return;

    if (illusts.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有发现包含非 WebP 图片的插画')));
      return;
    }

    await DownloadedImageOrganizerPage.openForIllusts(
      context,
      illustIds: illusts.map((e) => e.illustId).toList(),
      title: '非 WebP 图片整理',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder:
          (_) => Scaffold(
            appBar: _buildAppBar(),
            body: _buildBody(),
            floatingActionButton: _buildFab(),
          ),
    );
  }

  // ============ AppBar 相关 ============

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading:
          _store.isMultiSelectMode
              ? CloseButton(onPressed: _store.exitMultiSelectMode)
              : null,
      title: _store.isSearching ? _buildSearchField() : _buildAppBarTitle(),
      actions: [
        IconButton(
          icon: Icon(_store.isSearching ? Icons.close : Icons.search),
          tooltip: _store.isSearching ? '关闭搜索' : '搜索',
          onPressed: _toggleSearch,
        ),
        if (!_store.isSearching) ...[
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: '图片整理',
            onPressed: _openImageOrganizer,
          ),
          IconButton(
            icon: const Icon(Icons.update),
            tooltip: '更新插画信息',
            onPressed: _showUpdateIllustInfoDialog,
          ),
          Observer(
            builder: (_) {
              return IconButton(
                icon: Icon(
                  _store.showBookmarksOnly
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: _store.showBookmarksOnly ? Colors.red : null,
                ),
                tooltip: _store.showBookmarksOnly ? '显示所有' : '仅显示收藏',
                onPressed: _store.toggleShowBookmarksOnly,
              );
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
          _buildMoreMenu(),
        ],
      ],
    );
  }

  Widget _buildAppBarTitle() {
    final tagData = _store.filterTagData;
    String? tagNameTitle;
    if (tagData != null) {
      if (tagData.tag.translatedName.isNotEmpty) {
        tagNameTitle = '${tagData.tag.name}(${tagData.tag.translatedName})';
      } else {
        tagNameTitle = tagData.tag.name;
      }
    }
    String title = _store.filterUserName ?? tagNameTitle ?? '已下载';

    Widget titleWidget = Text(title);
    if (_store.filterUserId != null) {
      titleWidget = InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => UsersPage(id: _store.filterUserId!),
            ),
          );
        },
        child: titleWidget,
      );
    }

    final stats = _store.stats;

    if (stats == null) {
      return titleWidget;
    }

    final illustCount = stats['illust_count'] ?? 0;
    final imageCount = stats['image_count'] ?? 0;
    final fileSize = stats['file_size'] ?? 0;
    final originalStats = _store.originalStats;
    final originalCount = originalStats?['image_count'] ?? 0;
    final originalSize = originalStats?['total_file_size'] ?? 0;

    if (illustCount == 0 &&
        imageCount == 0 &&
        fileSize == 0 &&
        originalCount == 0) {
      return titleWidget;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        titleWidget,
        SizedBox(width: 8),
        Text(
          '${illustCount}作品 · ${imageCount}图 · ${fileSize.formatFileSize()}'
          '${originalCount > 0 ? '  |  原图 $originalCount · ${originalSize.formatFileSize()}' : ''}',
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
          color: Theme.of(
            context,
          ).appBarTheme.foregroundColor?.withOpacity(0.6),
        ),
      ),
      style: TextStyle(color: Theme.of(context).appBarTheme.foregroundColor),
    );
  }

  Widget _buildMoreMenu() {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert),
      onSelected: _onMenuSelected,
      position: PopupMenuPosition.under,
      itemBuilder:
          (context) => [
            ..._buildFilterMenuItems(),
            PopupMenuDivider(),
            ..._buildActionMenuItems(),
            PopupMenuDivider(),
            ..._buildDownloadControlMenuItems(),
            PopupMenuDivider(),
            CheckedPopupMenuItem(
              value: 'toggle_enable_drag',
              checked: _store.enableDrag,
              child: Text('启用拖拽功能'),
            ),
          ],
    );
  }

  Future<void> _onMenuSelected(String value) async {
    switch (value) {
      case 'filter_all':
        _store.onFilterChanged(DownloadFilter.all);
        break;
      case 'filter_incomplete':
        _store.onFilterChanged(DownloadFilter.incomplete);
        break;
      case 'filter_has_original':
        _store.onFilterChanged(DownloadFilter.hasOriginal);
        break;
      case 'filter_original_only':
        _store.onFilterChanged(DownloadFilter.originalOnly);
        break;
      case 'filter_no_ugoira':
        _store.onFilterChanged(DownloadFilter.noUgoira);
        break;
      case 'filter_only_ugoira':
        _store.onFilterChanged(DownloadFilter.onlyUgoira);
        break;
      case 'pause_all':
        _store.pauseAll();
        break;
      case 'resume_all':
        _store.resumeAll();
        break;
      case 'toggle_enable_drag':
        _store.toggleEnableDrag();
        break;
      case 'sync_bookmarks':
        SyncBookmarksDialog.show(context);
        break;
      case 'scan_translation_results':
        final count = await _store.scanTranslationResults();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('扫描完成，发现 $count 个可替换作品')));
        }
        break;
      case 'translation_result_directory':
        final changed = await TranslationResultDirectoryDialog.show(context);
        if (changed == true) {
          _store.clearTranslationResults();
        }
        break;
      case 'optimize_json':
        OptimizeJsonDialog.show(context, downloadStore);
        break;
      case 'import_author_originals':
        if (_store.filterUserId != null) {
          OriginalAuthorImportDialog.show(
            context,
            userId: _store.filterUserId!,
            userName: _store.filterUserName ?? '作者',
          ).then((changed) {
            if (changed == true) _store.refresh();
          });
        }
        break;
      case 'recover_original_imports':
        OriginalImportRecoveryDialog.show(context);
        break;
      case 'create_local_original_work':
        if (_store.filterUserId != null) {
          LocalOriginalWorkDialog.show(
            context,
            userId: _store.filterUserId!,
            userName: _store.filterUserName ?? '作者',
          ).then((changed) {
            if (changed == true) _store.refresh();
          });
        }
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
        value: 'filter_incomplete',
        icon: Icons.warning_amber,
        label: '未下载完整',
        isSelected: _store.downloadFilter == DownloadFilter.incomplete,
      ),
      _buildFilterMenuItem(
        value: 'filter_has_original',
        icon: Icons.hd,
        label: '有原图',
        isSelected: _store.downloadFilter == DownloadFilter.hasOriginal,
      ),
      _buildFilterMenuItem(
        value: 'filter_original_only',
        icon: Icons.image_outlined,
        label: '仅原图',
        isSelected: _store.downloadFilter == DownloadFilter.originalOnly,
      ),
      _buildFilterMenuItem(
        value: 'filter_no_ugoira',
        icon: Icons.videocam_off_outlined,
        label: '排除动图',
        isSelected: _store.downloadFilter == DownloadFilter.noUgoira,
      ),
      _buildFilterMenuItem(
        value: 'filter_only_ugoira',
        icon: Icons.movie_filter_outlined,
        label: '仅显示动图',
        isSelected: _store.downloadFilter == DownloadFilter.onlyUgoira,
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
      if (_store.filterUserId != null)
        PopupMenuItem(
          value: 'import_author_originals',
          child: Row(
            children: [
              Icon(Icons.add_photo_alternate_outlined, color: Colors.indigo),
              SizedBox(width: 8),
              Text('批量导入该作者原图'),
            ],
          ),
        ),
      if (_store.filterUserId != null)
        PopupMenuItem(
          value: 'create_local_original_work',
          child: Row(
            children: [
              Icon(Icons.create_new_folder_outlined, color: Colors.teal),
              SizedBox(width: 8),
              Text('新建本地作品并导入'),
            ],
          ),
        ),
      PopupMenuItem(
        value: 'recover_original_imports',
        child: Row(
          children: [
            Icon(Icons.restore, color: Colors.blueGrey),
            SizedBox(width: 8),
            Text('恢复原图导入任务'),
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
      PopupMenuItem(
        value: 'sync_bookmarks',
        child: Row(
          children: [
            Icon(Icons.sync, color: Colors.blue),
            SizedBox(width: 8),
            Text('同步在线收藏'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'translation_result_directory',
        child: Row(
          children: [
            Icon(Icons.translate, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('漫画翻译结果目录'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'scan_translation_results',
        child: Row(
          children: [
            Icon(Icons.manage_search, color: Colors.green),
            SizedBox(width: 8),
            Text('扫描翻译结果'),
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
      onRefresh:
          _store.isMultiSelectMode
              ? null
              : () async {
                await _store.refresh();
              },
      onLoad: _store.isMultiSelectMode ? null : _store.loadMore,
      header: PixezDefault.header(context),
      footer: PixezDefault.footer(context),
      childBuilder: (context, physics, scrollController) {
        // 保存滚动控制器以便 FAB 使用
        _scrollController = scrollController;
        return Observer(
          builder: (context) {
            return ScrollConfiguration(
              behavior:
                  _store.enableDrag
                      ? ScrollConfiguration.of(context).copyWith(
                        dragDevices:
                            ScrollConfiguration.of(context).dragDevices
                                .where((k) => k != PointerDeviceKind.mouse)
                                .toSet(),
                      )
                      : ScrollConfiguration.of(context),
              child: CustomScrollView(
                physics: physics,
                controller: scrollController,
                slivers: [_buildSortHeader(), _buildGridView()],
              ),
            );
          },
        );
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
                  children: ['下载时间', '作品时间', '文件大小', '平均大小', '收藏优先级'],
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
        Switch(value: _store.sortDesc, onChanged: _store.onSortOrderChanged),
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
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index >= filteredList.length) {
            return Center(child: CircularProgressIndicator());
          }
          return DownloadedIllustCard(
            illust: filteredList[index],
            store: _store,
            onTapPosition: (pos) => _tapPosition = pos,
            onTap: () => _navigateToPictureList(filteredList[index]),
            onLongPress:
                _isDesktop
                    ? () => _enterMultiSelect(filteredList[index])
                    : () => _showContextMenu(
                      context,
                      filteredList[index],
                      _tapPosition,
                    ),
            onSecondaryTap:
                () => _showContextMenu(
                  context,
                  filteredList[index],
                  _tapPosition,
                ),
            onOpenFolder: () => _openIllustFolder(filteredList[index]),
            onOpenOriginalFolder:
                () => _openOriginalFolder(filteredList[index]),
            onRefreshData: () {
              _store.loadData();
              _store.loadStats();
            },
            onTranslationStatusTap:
                () => _store.updateTranslationStatus(
                  filteredList[index].illustId,
                  !filteredList[index].isTranslated,
                ),
            onApplyTranslationResult:
                () => _showTranslationResultDialog([filteredList[index]]),
            onAuthorTap:
                () => _navigateToAuthorDownloadedPage(filteredList[index]),
          );
        }, childCount: filteredList.length + (_store.loadingMore ? 1 : 0)),
      ),
    );
  }

  // ============ 导航与操作 ============

  void _enterMultiSelect(DownloadedIllust illust) {
    _store.enterMultiSelectMode();
    _store.selectItem(illust.illustId);
  }

  void _navigateToPictureList(DownloadedIllust illust) async {
    final filteredList = _store.filteredIllusts;
    final int index = filteredList.indexOf(illust);
    if (index == -1) return;

    // 限制前后总共最多200条数据
    const int windowSize = 200;
    int start = index - windowSize ~/ 2;
    int end = start + windowSize;

    if (start < 0) {
      start = 0;
      end = windowSize;
    }

    if (end > filteredList.length) {
      end = filteredList.length;
      start = end - windowSize;
      if (start < 0) start = 0;
    }

    final subset = filteredList.sublist(start, end);

    final iStores =
        subset.map((item) {
          return IllustStore(item.illustId, item.toIllusts());
        }).toList();

    final currentIndex = subset.indexOf(illust);
    final currentStore = iStores[currentIndex];

    // 预加载首帧图片信息，避免详情页渲染时的尺寸跳动
    await currentStore.preloadFirstImage(relativePath: illust.relativePath);

    if (!context.mounted) return;

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
    DownloadedPage.open(
      context,
      userId: illust.userId,
      userName: illust.userName,
    );
  }

  Future<void> _openIllustFolder(DownloadedIllust illust) async {
    String? dirPath;
    if (illust.isLocal || illust.downloadedImageCount == 0) {
      final set = await downloadStore.originalRepository.getDefaultSet(
        illust.illustId,
      );
      if (set != null) {
        dirPath = downloadStore.dbProvider.getOriginalAbsolutePath(
          set.relativePath,
        );
      }
    }
    dirPath ??= downloadStore.getIllustDirectoryPath(illust);
    if (dirPath != null) {
      await FileUtils.openFileOrDirectory(dirPath);
    }
  }

  Future<void> _openOriginalFolder(DownloadedIllust illust) async {
    final set = await downloadStore.originalRepository.getDefaultSet(
      illust.illustId,
    );
    if (set == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('该作品尚未导入原图')));
      }
      return;
    }
    final dirPath = downloadStore.dbProvider.getOriginalAbsolutePath(
      set.relativePath,
    );
    try {
      await FileUtils.openFileOrDirectory(dirPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开原图目录失败：$e')));
      }
    }
  }

  // ============ FAB 相关 ============

  Widget _buildFab() {
    return Observer(
      builder:
          (_) => FloatingActionButton(
            heroTag: 'downloaded_page_refresh_fab',
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
    illustsToUpdate = illustsToUpdate.where((item) => !item.isLocal).toList();

    if (illustsToUpdate.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('没有需要更新的作品')));
      return;
    }

    final result = await UpdateIllustInfoDialog.show(
      context,
      illusts: illustsToUpdate,
      userId: _store.filterUserId,
    );

    if (result == true) {
      _store.loadData();
      _store.loadStats();
    }
  }

  void _showSinglePriorityDialog(
    BuildContext context,
    DownloadedIllust illust,
  ) {
    BookmarkPriorityDialog.show(
      context,
      illusts: [illust],
      onUpdate: (id, bookmark) => _store.updateBookmark(id, bookmark),
    );
  }

  void _showBatchPriorityDialog(
    BuildContext context,
    List<DownloadedIllust> illusts,
  ) {
    BookmarkPriorityDialog.show(
      context,
      illusts: illusts,
      onUpdate: (id, bookmark) => _store.updateBookmark(id, bookmark),
    );
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

  Future<void> _showContextMenu(
    BuildContext context,
    DownloadedIllust illust,
    Offset? tapPosition,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final localPosition =
        tapPosition != null ? overlay.globalToLocal(tapPosition) : Offset.zero;

    final isMulti = _store.isMultiSelectMode;
    final selectedCount = _store.selectedIllustIds.length;

    // 确定目标作品列表
    final isSelectedInMulti =
        isMulti && _store.selectedIllustIds.contains(illust.illustId);
    final targetIllusts =
        isSelectedInMulti
            ? _store.filteredIllusts
                .where((i) => _store.selectedIllustIds.contains(i.illustId))
                .toList()
            : [illust];

    final hasTranslationResult =
        !isMulti && _store.hasTranslationResult(illust.illustId);
    final isBatchTranslationTarget = isMulti && isSelectedInMulti;
    if (!mounted) return;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        localPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (hasTranslationResult || isBatchTranslationTarget)
          _buildContextMenuItem(
            icon: Icons.translate,
            label:
                isBatchTranslationTarget
                    ? '应用选中翻译结果 ($selectedCount)'
                    : '应用翻译结果',
            labelColor: Theme.of(context).colorScheme.primary,
            onTap: () => _showTranslationResultDialog(targetIllusts),
          ),
        if (isMulti)
          PopupMenuItem(child: Text('已选择 $selectedCount 项'), enabled: false),

        _buildSelectionToggleItem(isMulti, isSelectedInMulti, illust),
        _buildContextMenuItem(
          icon: Icons.open_in_new,
          label: I18n.of(context).detail,
          onTap: () => _navigateToPictureList(illust),
        ),

        if (!isMulti) ..._buildSingleModeMenus(context, illust),

        _buildBookmarkMenuItem(
          isSelectedInMulti,
          selectedCount,
          illust,
          targetIllusts,
        ),
        _buildPriorityMenuItem(
          isSelectedInMulti,
          selectedCount,
          illust,
          targetIllusts,
        ),

        if (!targetIllusts.any((item) => item.isLocal))
          _buildContextMenuItem(
            icon: Icons.update,
            label: isSelectedInMulti ? '更新选中信息 ($selectedCount)' : '更新插画信息',
            onTap: () async {
              final result = await UpdateIllustInfoDialog.show(
                context,
                illusts: targetIllusts,
                userId: _store.filterUserId,
              );
              if (result == true) {
                _store.loadData();
              }
            },
          ),

        if (!targetIllusts.any((item) => item.isLocal))
          _buildContextMenuItem(
            icon: Icons.delete,
            iconColor: Colors.red,
            label:
                isSelectedInMulti
                    ? '删除选中 ($selectedCount)'
                    : I18n.of(context).delete,
            labelColor: Colors.red,
            onTap: () => _deleteIllusts(targetIllusts),
          ),
      ],
    );
  }

  /// 构建多选/退出选择切换项
  PopupMenuItem<void> _buildSelectionToggleItem(
    bool isMulti,
    bool isSelectedInMulti,
    DownloadedIllust illust,
  ) {
    final icon = isMulti ? Icons.check_box_outline_blank : Icons.check_box;
    final label = isMulti ? '退出多选模式' : '进入多选模式';
    return _buildContextMenuItem(
      icon: icon,
      label: label,
      onTap: () {
        if (isMulti) {
          _store.exitMultiSelectMode();
        } else {
          _store.enterMultiSelectMode();
          _store.selectItem(illust.illustId);
        }
      },
    );
  }

  /// 构建单选模式特有的菜单项
  List<PopupMenuEntry<void>> _buildSingleModeMenus(
    BuildContext context,
    DownloadedIllust illust,
  ) {
    final status = _store.illustDownloadStatus[illust.illustId];
    final isDownloading =
        status == DownloadTaskStatus.downloading ||
        status == DownloadTaskStatus.pending;
    final isPaused = status == DownloadTaskStatus.paused;
    final isFailed = status == DownloadTaskStatus.failed;

    return [
      _buildContextMenuItem(
        icon: Icons.add_photo_alternate_outlined,
        label:
            (_store.originalImageCounts[illust.illustId] ?? 0) > 0
                ? '更新/添加原图版本'
                : '导入原图',
        onTap: () async {
          final changed = await OriginalImportDialog.show(context, illust);
          if (changed == true) {
            await _store.loadData();
            await _store.loadStats();
          }
        },
      ),
      if ((_store.originalImageCounts[illust.illustId] ?? 0) > 0)
        _buildContextMenuItem(
          icon: Icons.tune,
          label: '管理原图版本',
          onTap: () async {
            final changed = await OriginalVersionManagerDialog.show(
              context,
              illust,
            );
            if (changed == true) await _store.loadData();
          },
        ),
      if ((_store.originalImageCounts[illust.illustId] ?? 0) > 0)
        _buildContextMenuItem(
          icon: Icons.folder_copy_outlined,
          label: '打开原图目录',
          onTap: () => _openOriginalFolder(illust),
        ),
      if (illust.isLocal)
        _buildContextMenuItem(
          icon: Icons.edit_outlined,
          label: '编辑本地作品',
          onTap: () async {
            final changed = await EditLocalWorkDialog.show(context, illust);
            if (changed == true) await _store.refresh();
          },
        ),
      if (illust.isLocal)
        _buildContextMenuItem(
          icon: Icons.link,
          label: '关联已有 Pixiv 作品',
          onTap: () async {
            final changed = await LinkLocalWorkDialog.show(context, illust);
            if (changed == true) await _store.refresh();
          },
        ),
      if (_store.filterTagId != null)
        _buildContextMenuItem(
          icon:
              _store.isExample(illust.illustId)
                  ? Icons.star
                  : Icons.star_border,
          label: _store.isExample(illust.illustId) ? '取消示例插画' : '设置为示例插画',
          onTap: () => _handleSetExampleIllust(illust),
        ),
      _buildContextMenuItem(
        icon: Icons.folder_open,
        label: I18n.of(context).save_path,
        onTap: () => _openIllustFolder(illust),
      ),
      _buildContextMenuItem(
        icon: Icons.copy,
        label: '复制路径',
        onTap: () => _copyIllustPath(context, illust),
      ),
      _buildContextMenuItem(
        icon: Icons.collections,
        label: '整理该作者',
        onTap:
            () => DownloadedImageOrganizerPage.pushByUserId(
              context,
              userId: illust.userId,
              illustId: illust.illustId,
            ),
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
    ];
  }

  /// 处理设置/取消示例插画
  Future<void> _handleSetExampleIllust(DownloadedIllust illust) async {
    final tagData = _store.filterTagData;
    if (tagData != null) {
      final imageUrls = illust.getImageUrls();
      String coverUrl = imageUrls.squareMedium;
      if (coverUrl.isEmpty) {
        final illusts = illust.toIllusts();
        coverUrl = illusts.imageUrls.squareMedium;
      }
      await tagManagerStore.toggleExampleIllust(
        tagData.tag.id,
        illust.illustId,
        coverUrl,
      );
    }
  }

  /// 复制插画路径
  void _copyIllustPath(BuildContext context, DownloadedIllust illust) {
    final path = downloadStore.getIllustDirectoryPath(illust);
    if (path != null) {
      Clipboard.setData(ClipboardData(text: path));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('路径已复制到剪贴板')));
    }
  }

  Future<void> _showTranslationResultDialog(
    List<DownloadedIllust> illusts,
  ) async {
    final replacer = TranslationResultReplacer(downloadStore.dbProvider);
    final selectedIllusts = List<DownloadedIllust>.unmodifiable(illusts);
    try {
      final hasResults = await TranslationResultReplaceDialog.show(
        context,
        onLoad:
            () => replacer.prepareBatch(
              selectedIllusts,
              translationResultRootDirectory:
                  userSetting.translationResultDirectory,
            ),
        replacer: replacer,
        onRefresh: () async {
          await _store.scanTranslationResults();
          return replacer.prepareBatch(
            selectedIllusts,
            translationResultRootDirectory:
                userSetting.translationResultDirectory,
          );
        },
        onReplaced: (summary) async {
          for (final item in summary.items) {
            if (item.translationResultDirectoriesCleaned) {
              _store.removeTranslationResult(item.plan.illust.illustId);
            }
          }
          if (_store.isMultiSelectMode) {
            _store.exitMultiSelectMode();
          }
          await _store.loadData();
          await _store.loadStats();
        },
      );
      if (!mounted || hasResults != false) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选中的 ${selectedIllusts.length} 个目录中没有可替换的翻译图片')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('读取翻译结果失败：$e')));
    }
  }

  /// 收藏/取消收藏菜单项
  PopupMenuItem<void> _buildBookmarkMenuItem(
    bool isSelectedInMulti,
    int selectedCount,
    DownloadedIllust illust,
    List<DownloadedIllust> targetIllusts,
  ) {
    final isBookmarked = illust.bookmark > 0;
    String label;
    if (isSelectedInMulti) {
      label = '收藏/取消选中 ($selectedCount)';
    } else {
      label = isBookmarked ? '取消收藏' : '收藏';
    }

    return _buildContextMenuItem(
      icon: isBookmarked ? Icons.favorite : Icons.favorite_border,
      iconColor: isBookmarked ? Colors.red : null,
      label: label,
      onTap: () async {
        final newBookmark = isBookmarked ? 0 : 1;
        if (isSelectedInMulti) {
          for (var item in targetIllusts) {
            await _store.updateBookmark(item.illustId, newBookmark);
          }
        } else {
          await _store.updateBookmark(illust.illustId, newBookmark);
        }
      },
    );
  }

  /// 设置优先级菜单项
  PopupMenuItem<void> _buildPriorityMenuItem(
    bool isSelectedInMulti,
    int selectedCount,
    DownloadedIllust illust,
    List<DownloadedIllust> targetIllusts,
  ) {
    final label = isSelectedInMulti ? '设置选中优先级 ($selectedCount)' : '设置收藏优先级';
    return _buildContextMenuItem(
      icon: Icons.priority_high,
      label: label,
      onTap: () {
        if (isSelectedInMulti) {
          _showBatchPriorityDialog(context, targetIllusts);
        } else {
          _showSinglePriorityDialog(context, illust);
        }
      },
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
          Text(
            label,
            style: labelColor != null ? TextStyle(color: labelColor) : null,
          ),
        ],
      ),
      onTap: onTap,
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
