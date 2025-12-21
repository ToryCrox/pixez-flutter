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
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:pixez/er/leader.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/picture/illust_lighting_page.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/picture_list_page.dart';
import 'package:pixez/page/downloaded/downloaded_authors_page.dart';
import 'package:pixez/page/downloaded/downloaded_page_store.dart';
import 'package:pixez/page/downloaded/import_dialog.dart';
import 'package:pixez/page/downloaded/optimize_json_dialog.dart';
import 'package:pixez/page/downloaded/update_illust_info_dialog.dart';
import 'package:pixez/store/download_store.dart';
import 'package:pixez/component/pixez_easy_refresh.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/component/sort_group.dart';

import '../../component/pixiv_image.dart';

class DownloadedPage extends StatefulWidget {
  final int? initialUserId;
  final String? initialUserName;

  const DownloadedPage({
    Key? key,
    this.initialUserId,
    this.initialUserName,
  }) : super(key: key);

  @override
  State<DownloadedPage> createState() => _DownloadedPageState();
}

class _DownloadedPageState extends State<DownloadedPage> {
  late DownloadedPageStore _store;
  late EasyRefreshController _easyRefreshController;
  Offset? _tapPosition;

  @override
  void initState() {
    super.initState();
    _easyRefreshController = EasyRefreshController(
      controlFinishLoad: true,
      controlFinishRefresh: true,
    );
    _store = DownloadedPageStore();
    _store.easyRefreshController = _easyRefreshController;
    _store.init(
      initialUserId: widget.initialUserId,
      initialUserName: widget.initialUserName,
    );
  }

  @override
  void dispose() {
    _store.dispose();
    _easyRefreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: _buildAppBarTitle(),
          actions: [
            IconButton(
              icon: Icon(Icons.upload_file),
              tooltip: '导入',
              onPressed: () {
                _showImportDialog();
              },
            ),
            IconButton(
              icon: Icon(Icons.people),
              tooltip: '作者列表',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => DownloadedAuthorsPage(),
                  ),
                );
              },
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert),
              onSelected: (value) {
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
                  case 'optimize_json':
                    OptimizeJsonDialog.show(context, downloadStore);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'filter_all',
                  child: Row(
                    children: [
                      Icon(
                        Icons.list,
                        color: _store.downloadFilter == DownloadFilter.all
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      SizedBox(width: 8),
                      Text(I18n.of(context).all),
                      if (_store.downloadFilter == DownloadFilter.all)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Icon(Icons.check,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'filter_downloading',
                  child: Row(
                    children: [
                      Icon(
                        Icons.downloading,
                        color: _store.downloadFilter == DownloadFilter.downloading
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      SizedBox(width: 8),
                      Text(I18n.of(context).running),
                      if (_store.downloadFilter == DownloadFilter.downloading)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Icon(Icons.check,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'filter_completed',
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: _store.downloadFilter == DownloadFilter.completed
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      SizedBox(width: 8),
                      Text(I18n.of(context).complete),
                      if (_store.downloadFilter == DownloadFilter.completed)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Icon(Icons.check,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'filter_incomplete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        color: _store.downloadFilter == DownloadFilter.incomplete
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      SizedBox(width: 8),
                      Text('未下载完整'),
                      if (_store.downloadFilter == DownloadFilter.incomplete)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Icon(Icons.check,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                    ],
                  ),
                ),
                PopupMenuDivider(),
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
                PopupMenuDivider(),
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
              ],
            ),
          ],
        ),
        body: _store.loading && _store.filteredIllusts.isEmpty
            ? Center(child: CircularProgressIndicator())
            : _store.filteredIllusts.isEmpty
                ? _buildEmptyView()
                : PixezEasyRefresh.builder(
                    controller: _easyRefreshController,
                    onRefresh: () async {
                      await _store.refresh();
                    },
                    onLoad: _store.loadMore,
                    header: PixezDefault.header(context),
                    footer: PixezDefault.footer(context),
                    childBuilder: (context, physics, scrollController) {
                      return CustomScrollView(
                        physics: physics,
                        controller: scrollController,
                        slivers: [
                          SliverPersistentHeader(
                            key: ValueKey('sort_header_${_store.sortType}_${_store.sortDesc}'),
                            delegate: SliverChipDelegate(
                              Container(
                                alignment: Alignment.center,
                                child: Stack(
                                  children: [
                                    Center(
                                      child: SortGroup(
                                        key: ValueKey(_store.sortType),
                                        children: [
                                          '下载时间',
                                          '作品时间',
                                          '文件大小',
                                          '平均大小',
                                        ],
                                        onChange: _store.onSortChanged,
                                        initIndex: _store.sortType.index,
                                      ),
                                    ),
                                    Positioned(
                                      right: 8,
                                      top: 0,
                                      bottom: 0,
                                      child: Center(
                                        child: _buildSortOrderButton(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              height: 52,
                            ),
                            pinned: true,
                          ),
                          _buildGridView(),
                        ],
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildAppBarTitle() {
    final title = _store.filterUserName ?? '已下载';
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
            return _buildIllustCard(filteredList[index]);
          },
          childCount: filteredList.length + (_store.loadingMore ? 1 : 0),
        ),
      ),
    );
  }

  Widget _buildIllustCard(DownloadedIllust illust) {
    final status = _store.illustDownloadStatus[illust.illustId];
    final isDownloading = status == DownloadTaskStatus.downloading;
    final isPending = status == DownloadTaskStatus.pending;
    final isPaused = status == DownloadTaskStatus.paused;
    final isFailed = status == DownloadTaskStatus.failed;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
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
        },
        onLongPress: () {
          _showIllustOptions(illust);
        },
        onSecondaryTapDown: (details) {
          _tapPosition = details.globalPosition;
        },
        onSecondaryTap: () {
          _showContextMenu(context, illust, _tapPosition);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildThumbnail(illust),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () async {
                          final dirPath = p.join(
                            downloadStore.downloadPath,
                            illust.relativePath,
                          );
                          await OpenFile.open(dirPath);
                        },
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
                  ),
                  if (isDownloading)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black38,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ),
                  if (isPending)
                    Positioned.fill(
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
                    ),
                  if (isPaused)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          I18n.of(context).paused,
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                  if (isFailed)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          I18n.of(context).failed,
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
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
                  Text(
                    illust.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  Row(
                    children: [
                      if (illust.pageCount > 1)
                        Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: _buildPageCountIndicator(
                            illust,
                            _store.fileSizes[illust.illustId],
                          ),
                        ),
                      Spacer(),
                      if (_store.fileSizes[illust.illustId] != null &&
                          _store.fileSizes[illust.illustId]! > 0)
                        Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            _store.fileSizes[illust.illustId]!.formatFileSize(),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[600],
                                      fontSize: 11,
                                    ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(DownloadedIllust illust) {
    final heroTag = 'downloaded_illust_${illust.illustId}';

    final imageUrls = illust.getImageUrls();
    String coverUrl = imageUrls.squareMedium;
    if (coverUrl.isEmpty) {
      final illusts = illust.toIllusts();
      coverUrl = illusts.imageUrls.squareMedium;
    }

    Widget imageWidget = PixivImage(
      coverUrl,
      fit: BoxFit.cover,
      httpHeaders: {'cover': '${illust.illustId}'},
    );

    return Hero(
      tag: heroTag,
      child: imageWidget,
    );
  }

  Widget _buildPageCountIndicator(DownloadedIllust illust, int? totalFileSize) {
    final downloadedCount =
        _store.downloadedCounts[illust.illustId] ?? illust.pageCount;
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

  void _showContextMenu(
      BuildContext context, DownloadedIllust illust, Offset? tapPosition) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final localPosition =
        tapPosition != null ? overlay.globalToLocal(tapPosition) : Offset.zero;

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
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.open_in_new),
              SizedBox(width: 8),
              Text(I18n.of(context).detail),
            ],
          ),
          onTap: () {
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
          },
        ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.folder_open),
              SizedBox(width: 8),
              Text(I18n.of(context).save_path),
            ],
          ),
          onTap: () async {
            final dirPath = p.join(
              downloadStore.downloadPath,
              illust.relativePath,
            );
            await OpenFile.open(dirPath);
          },
        ),
        if (isDownloading)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(Icons.pause),
                SizedBox(width: 8),
                Text('暂停'),
              ],
            ),
            onTap: () {
              downloadStore.pauseIllustDownload(illust.illustId);
            },
          ),
        if (isPaused || isFailed)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(Icons.play_arrow),
                SizedBox(width: 8),
                Text(I18n.of(context).retry),
              ],
            ),
            onTap: () {
              downloadStore.resumeIllustDownload(illust.illustId);
            },
          ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.update),
              SizedBox(width: 8),
              Text('更新插画信息'),
            ],
          ),
          onTap: () async {
            await showDialog(
              context: context,
              builder: (context) => UpdateIllustInfoDialog(
                illusts: [illust],
              ),
            );
            _store.loadData();
          },
        ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red),
              SizedBox(width: 8),
              Text(
                I18n.of(context).delete,
                style: TextStyle(color: Colors.red),
              ),
            ],
          ),
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx2) {
                return AlertDialog(
                  title: Text(I18n.of(context).delete),
                  content: Text('${illust.title}\n${I18n.of(context).delete}?'),
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
            if (confirm == true) {
              downloadStore.cancelIllustDownload(illust.illustId);
              await downloadStore.deleteDownloadedIllust(illust.illustId);
              _store.loadData();
              _store.loadStats();
            }
          },
        ),
      ],
    );
  }

  void _showImportDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ImportDialog(),
    );
    if (result == true) {
      _store.loadData();
      _store.loadStats();
    }
  }

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
      builder: (context) => UpdateIllustInfoDialog(illusts: illustsToUpdate),
    );

    _store.loadData();
    _store.loadStats();
  }

  void _showIllustOptions(DownloadedIllust illust) {
    final status = _store.illustDownloadStatus[illust.illustId];
    final isDownloading = status == DownloadTaskStatus.downloading ||
        status == DownloadTaskStatus.pending;
    final isPaused = status == DownloadTaskStatus.paused;
    final isFailed = status == DownloadTaskStatus.failed;

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text(illust.title),
                subtitle: Text(illust.userName),
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.open_in_new),
                title: Text(I18n.of(context).detail),
                onTap: () {
                  Navigator.pop(ctx);
                  Leader.push(
                    context,
                    IllustLightingPage(
                      id: illust.illustId,
                      heroString: 'downloaded_illust_${illust.illustId}',
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.folder_open),
                title: Text(I18n.of(context).save_path),
                onTap: () async {
                  Navigator.pop(ctx);
                  final dirPath = p.join(
                    downloadStore.downloadPath,
                    illust.relativePath,
                  );
                  await OpenFile.open(dirPath);
                },
              ),
              if (isDownloading)
                ListTile(
                  leading: Icon(Icons.pause),
                  title: Text('暂停'),
                  onTap: () {
                    Navigator.pop(ctx);
                    downloadStore.pauseIllustDownload(illust.illustId);
                  },
                ),
              if (isPaused || isFailed)
                ListTile(
                  leading: Icon(Icons.play_arrow),
                  title: Text(I18n.of(context).retry),
                  onTap: () {
                    Navigator.pop(ctx);
                    downloadStore.resumeIllustDownload(illust.illustId);
                  },
                ),
              ListTile(
                leading: Icon(Icons.update),
                title: Text('更新插画信息'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await showDialog(
                    context: context,
                    builder: (context) => UpdateIllustInfoDialog(
                      illusts: [illust],
                    ),
                  );
                  _store.loadData();
                  _store.loadStats();
                },
              ),
              ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text(
                  I18n.of(context).delete,
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx2) {
                      return AlertDialog(
                        title: Text(I18n.of(context).delete),
                        content: Text(
                            '${illust.title}\n${I18n.of(context).delete}?'),
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
                  if (confirm == true) {
                    downloadStore.cancelIllustDownload(illust.illustId);
                    await downloadStore.deleteDownloadedIllust(illust.illustId);
                    _store.loadData();
                    _store.loadStats();
                  }
                },
              ),
            ],
          ),
        );
      },
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
