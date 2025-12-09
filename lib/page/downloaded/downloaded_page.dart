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
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:pixez/er/leader.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/picture/illust_lighting_page.dart';
import 'package:pixez/page/downloaded/downloaded_authors_page.dart';
import 'package:pixez/page/downloaded/import_dialog.dart';
import 'package:pixez/page/downloaded/update_illust_info_dialog.dart';
import 'package:pixez/store/download_store.dart';
import 'package:pixez/component/sort_group.dart';
import 'package:pixez/er/prefer.dart';

enum DownloadFilter {
  all,
  downloading,
  completed,
}

enum IllustSortType {
  downloadTime, // 下载时间
  createDate, // 作品时间
  fileSize, // 文件大小
}

// SharedPreferences 键名
const String _DOWNLOADED_ILLUSTS_SORT_TYPE_KEY = 'downloaded_illusts_sort_type';
const String _DOWNLOADED_ILLUSTS_SORT_DESC_KEY = 'downloaded_illusts_sort_desc';

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
  List<DownloadedIllust> _illusts = [];
  Map<int, int> _downloadedCounts = {};
  Map<int, DownloadTaskStatus> _illustDownloadStatus = {};
  Map<int, String?> _thumbnailPaths = {};
  Map<int, int> _fileSizes = {}; // 存储文件大小（字节）
  bool _loading = true;
  String? _searchKeyword;
  int? _filterUserId;
  String? _filterUserName;
  DownloadFilter _downloadFilter = DownloadFilter.all;
  final ScrollController _scrollController = ScrollController();
  Offset? _tapPosition;
  int _page = 0;
  static const int _pageSize = 50;
  bool _hasMore = true;
  bool _loadingMore = false;
  StreamSubscription<IllustDownloadStatus>? _downloadStatusSubscription;
  
  // 排序相关
  IllustSortType _sortType = IllustSortType.downloadTime;
  bool _sortDesc = true; // true=倒序，false=正序

  @override
  void initState() {
    super.initState();
    // 如果传入了初始用户ID和用户名，则设置过滤条件
    if (widget.initialUserId != null) {
      _filterUserId = widget.initialUserId;
      _filterUserName = widget.initialUserName;
    }
    _loadPersistedState();
    _loadData();
    _scrollController.addListener(_onScroll);
    _downloadStatusSubscription = downloadStore.illustDownloadStatusStream
        .listen(_onDownloadStatusChanged);
  }

  /// 加载持久化的状态
  void _loadPersistedState() {
    final sortTypeIndex = Prefer.getInt(_DOWNLOADED_ILLUSTS_SORT_TYPE_KEY);
    if (sortTypeIndex != null && sortTypeIndex >= 0 && sortTypeIndex < IllustSortType.values.length) {
      _sortType = IllustSortType.values[sortTypeIndex];
    }
    
    final sortDesc = Prefer.getBool(_DOWNLOADED_ILLUSTS_SORT_DESC_KEY);
    if (sortDesc != null) {
      _sortDesc = sortDesc;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _downloadStatusSubscription?.cancel();
    super.dispose();
  }

  void _onDownloadStatusChanged(IllustDownloadStatus status) {
    if (mounted) {
      setState(() {
        // 如果是删除状态，从列表中移除
        if (status.status == DownloadTaskStatus.deleted) {
          _illusts.removeWhere((e) => e.illustId == status.illusts.illustId);
          _illustDownloadStatus.remove(status.illusts.illustId);
          _downloadedCounts.remove(status.illusts.illustId);
          _fileSizes.remove(status.illusts.illustId);
          return;
        }
        
        // 如果当前有作者过滤，检查新插画是否属于当前作者
        if (_filterUserId != null && status.illusts.userId != _filterUserId) {
          // 不属于当前作者，不添加到列表，但更新状态信息（如果已存在）
          if (_illusts.any((e) => e.illustId == status.illusts.illustId)) {
            _illustDownloadStatus[status.illusts.illustId] = status.status;
            _downloadedCounts[status.illusts.illustId] = status.completedCount;
          }
          return;
        }
        
        if (_illusts.firstWhereOrNull(
                (e) => e.illustId == status.illusts.illustId) ==
            null) {
          _illusts.insert(0, status.illusts);
        }
        _illustDownloadStatus[status.illusts.illustId] = status.status;
        _downloadedCounts[status.illusts.illustId] = status.completedCount;
        if (_thumbnailPaths[status.illusts.illustId] == null) {
          downloadStore.getLocalImagePath(status.illusts.illustId, 0).then((e) {
            setState(() {
              _thumbnailPaths[status.illusts.illustId] = e;
            });
          });
        }
        // 更新文件大小
        downloadStore
            .getIllustTotalFileSize(status.illusts.illustId)
            .then((size) {
          if (mounted) {
            setState(() {
              _fileSizes[status.illusts.illustId] = size;
            });
          }
        });
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  String? _getSortBy() {
    switch (_sortType) {
      case IllustSortType.downloadTime:
        return '${DownloadedIllustColumns.downloadTime} ${_sortDesc ? 'DESC' : 'ASC'}';
      case IllustSortType.createDate:
        return '${DownloadedIllustColumns.createDate} ${_sortDesc ? 'DESC' : 'ASC'}';
      case IllustSortType.fileSize:
        // 文件大小排序在数据库中进行
        return 'total_file_size ${_sortDesc ? 'DESC' : 'ASC'}';
    }
  }

  Future<void> _loadData() async {
    if (!downloadStore.isInitialized) {
      setState(() {
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _page = 0;
      _hasMore = true;
    });

    try {
      List<DownloadedIllust> illusts;
      final orderBy = _getSortBy();

      if (_filterUserId != null) {
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

      final counts = <int, int>{};
      final statusMap = <int, DownloadTaskStatus>{};
      final thumbnails = <int, String?>{};
      final fileSizes = <int, int>{};
      for (final illust in illusts) {
        counts[illust.illustId] =
            await downloadStore.getDownloadedPageCount(illust.illustId);
        final downloadStatus =
            await downloadStore.getIllustDownloadStatus(illust.illustId);
        if (downloadStatus != null) {
          statusMap[illust.illustId] = downloadStatus.status;
        }
        thumbnails[illust.illustId] =
            await downloadStore.getLocalImagePath(illust.illustId, 0);
        fileSizes[illust.illustId] =
            await downloadStore.getIllustTotalFileSize(illust.illustId);
      }

      if (mounted) {
        setState(() {
          _illusts = illusts;
          _downloadedCounts = counts;
          _illustDownloadStatus = statusMap;
          _thumbnailPaths = thumbnails;
          _fileSizes = fileSizes;
          _loading = false;
          _hasMore = illusts.length >= _pageSize;
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
    if (_loadingMore || !_hasMore) return;

    setState(() {
      _loadingMore = true;
    });

    _page++;
    final offset = _page * _pageSize;

    try {
      List<DownloadedIllust> moreIllusts;
      final orderBy = _getSortBy();

      if (_filterUserId != null) {
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

      for (final illust in moreIllusts) {
        _downloadedCounts[illust.illustId] =
            await downloadStore.getDownloadedPageCount(illust.illustId);
        final downloadStatus =
            await downloadStore.getIllustDownloadStatus(illust.illustId);
        if (downloadStatus != null) {
          _illustDownloadStatus[illust.illustId] = downloadStatus.status;
        }
        _thumbnailPaths[illust.illustId] =
            await downloadStore.getLocalImagePath(illust.illustId, 0);
        _fileSizes[illust.illustId] =
            await downloadStore.getIllustTotalFileSize(illust.illustId);
      }

      if (mounted) {
        setState(() {
          _illusts.addAll(moreIllusts);
          _loadingMore = false;
          _hasMore = moreIllusts.length >= _pageSize;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingMore = false;
        });
      }
    }
  }


  List<DownloadedIllust> get _filteredIllusts {
    if (_downloadFilter == DownloadFilter.all) {
      return _illusts;
    }

    return _illusts.where((illust) {
      final status = _illustDownloadStatus[illust.illustId];
      final downloadedCount = _downloadedCounts[illust.illustId] ?? 0;
      final isCompleted = downloadedCount >= illust.pageCount;

      if (_downloadFilter == DownloadFilter.downloading) {
        return !isCompleted ||
            status == DownloadTaskStatus.downloading ||
            status == DownloadTaskStatus.pending ||
            status == DownloadTaskStatus.paused ||
            status == DownloadTaskStatus.failed;
      } else if (_downloadFilter == DownloadFilter.completed) {
        return isCompleted && status != DownloadTaskStatus.downloading;
      }
      return true;
    }).toList();
  }

  void _onSortChanged(int index) {
    final newSortType = IllustSortType.values[index];
    setState(() {
      _sortType = newSortType;
    });
    // 持久化排序类型
    Prefer.setInt(_DOWNLOADED_ILLUSTS_SORT_TYPE_KEY, newSortType.index);
    _loadData();
  }

  void _onSortOrderChanged(bool desc) {
    setState(() {
      _sortDesc = desc;
    });
    // 持久化排序顺序
    Prefer.setBool(_DOWNLOADED_ILLUSTS_SORT_DESC_KEY, desc);
    _loadData();
  }

  void _pauseAll() {
    for (final illust in _illusts) {
      final status = _illustDownloadStatus[illust.illustId];
      if (status == DownloadTaskStatus.downloading ||
          status == DownloadTaskStatus.pending) {
        downloadStore.pauseIllustDownload(illust.illustId);
      }
    }
  }

  void _resumeAll() {
    for (final illust in _illusts) {
      final status = _illustDownloadStatus[illust.illustId];
      if (status == DownloadTaskStatus.paused ||
          status == DownloadTaskStatus.failed) {
        downloadStore.resumeIllustDownload(illust.illustId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_filterUserName ?? I18n.of(context).history),
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
                  setState(() => _downloadFilter = DownloadFilter.all);
                  break;
                case 'filter_downloading':
                  setState(() => _downloadFilter = DownloadFilter.downloading);
                  break;
                case 'filter_completed':
                  setState(() => _downloadFilter = DownloadFilter.completed);
                  break;
                case 'update_info':
                  _showUpdateIllustInfoDialog();
                  break;
                case 'pause_all':
                  _pauseAll();
                  break;
                case 'resume_all':
                  _resumeAll();
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
                      color: _downloadFilter == DownloadFilter.all
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    SizedBox(width: 8),
                    Text(I18n.of(context).all),
                    if (_downloadFilter == DownloadFilter.all)
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
                      color: _downloadFilter == DownloadFilter.downloading
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    SizedBox(width: 8),
                    Text(I18n.of(context).running),
                    if (_downloadFilter == DownloadFilter.downloading)
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
                      color: _downloadFilter == DownloadFilter.completed
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    SizedBox(width: 8),
                    Text(I18n.of(context).complete),
                    if (_downloadFilter == DownloadFilter.completed)
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
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'pause_all',
                child: Row(
                  children: [
                    Icon(Icons.pause_circle_outline),
                    SizedBox(width: 8),
                    Text('${I18n.of(context).paused}${I18n.of(context).all}'),
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
            ],
          ),
        ],
      ),
      body: _loading && _illusts.isEmpty
          ? Center(child: CircularProgressIndicator())
          : _filteredIllusts.isEmpty
              ? _buildEmptyView()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverPersistentHeader(
                        key: ValueKey('sort_header_${_sortType}_$_sortDesc'),
                        delegate: SliverChipDelegate(
                          Container(
                            alignment: Alignment.center,
                            child: Stack(
                              children: [
                                // 居中显示排序菜单
                                Center(
                                  child: SortGroup(
                                    key: ValueKey(_sortType),
                                    children: [
                                      '下载时间',
                                      '作品时间',
                                      '文件大小',
                                    ],
                                    onChange: _onSortChanged,
                                    initIndex: _sortType.index,
                                  ),
                                ),
                                // 右侧显示正序/倒序按钮
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
                  ),
                ),
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

  Widget _buildGridView() {
    final filteredList = _filteredIllusts;
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
          childCount: filteredList.length + (_loadingMore ? 1 : 0),
        ),
      ),
    );
  }

  Widget _buildIllustCard(DownloadedIllust illust) {
    final status = _illustDownloadStatus[illust.illustId];
    final isDownloading = status == DownloadTaskStatus.downloading ||
        status == DownloadTaskStatus.pending;
    final isPaused = status == DownloadTaskStatus.paused;
    final isFailed = status == DownloadTaskStatus.failed;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Leader.push(
            context,
            IllustLightingPage(id: illust.illustId),
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
                            _fileSizes[illust.illustId],
                          ),
                        ),
                      Spacer(),
                      if (_fileSizes[illust.illustId] != null &&
                          _fileSizes[illust.illustId]! > 0)
                        Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            _fileSizes[illust.illustId]!.formatFileSize(),
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
    final thumbnailPath = _thumbnailPaths[illust.illustId];
    if (thumbnailPath != null) {
      return Image.file(
        File(thumbnailPath),
        fit: BoxFit.cover,
        cacheWidth: (200 * MediaQuery.devicePixelRatioOf(context)).toInt(),
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[300],
            child: Icon(Icons.broken_image, color: Colors.grey),
          );
        },
      );
    }
    return Container(
      color: Colors.grey[300],
      child: Icon(Icons.image, color: Colors.grey),
    );
  }

  Widget _buildPageCountIndicator(DownloadedIllust illust, int? totalFileSize) {
    final downloadedCount =
        _downloadedCounts[illust.illustId] ?? illust.pageCount;
    final totalCount = illust.pageCount;

    String pageText;
    if (downloadedCount < totalCount) {
      pageText = '$downloadedCount/$totalCount';
    } else {
      pageText = '${totalCount}P';
    }

    // 计算平均每页文件大小
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
    final Offset position = tapPosition ?? Offset.zero;

    final status = _illustDownloadStatus[illust.illustId];
    final isDownloading = status == DownloadTaskStatus.downloading ||
        status == DownloadTaskStatus.pending;
    final isPaused = status == DownloadTaskStatus.paused;
    final isFailed = status == DownloadTaskStatus.failed;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
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
            Leader.push(
              context,
              IllustLightingPage(id: illust.illustId),
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
                Text(I18n.of(context).paused),
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
            Navigator.pop(context);
            await showDialog(
              context: context,
              builder: (context) => UpdateIllustInfoDialog(
                illusts: [illust],
              ),
            );
            _loadData();
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
              _loadData();
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
    // 如果导入成功，刷新数据
    if (result == true) {
      _loadData();
    }
  }

  void _showUpdateIllustInfoDialog() async {
    List<DownloadedIllust> illustsToUpdate;
    
    // 如果处于作者筛选条件下，获取所有作者的作品
    if (_filterUserId != null) {
      // 获取所有作者的作品（不限制数量）
      illustsToUpdate = await downloadStore.getDownloadedByUser(
        _filterUserId!,
        limit: null,
        offset: 0,
      );
    } else {
      // 否则更新当前页面加载的作品
      illustsToUpdate = List.from(_illusts);
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

    // 更新完成后刷新数据
    _loadData();
  }

  void _showIllustOptions(DownloadedIllust illust) {
    final status = _illustDownloadStatus[illust.illustId];
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
                    IllustLightingPage(id: illust.illustId),
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
                  title: Text(I18n.of(context).paused),
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
                  _loadData();
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
                    _loadData();
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
