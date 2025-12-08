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
import 'package:pixez/store/download_store.dart';

enum DownloadFilter {
  all,
  downloading,
  completed,
}

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
  List<Map<String, dynamic>> _users = [];
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
  static const int _pageSize = 30;
  bool _hasMore = true;
  bool _loadingMore = false;
  StreamSubscription<IllustDownloadStatus>? _downloadStatusSubscription;

  @override
  void initState() {
    super.initState();
    // 如果传入了初始用户ID和用户名，则设置过滤条件
    if (widget.initialUserId != null) {
      _filterUserId = widget.initialUserId;
      _filterUserName = widget.initialUserName;
    }
    _loadData();
    _scrollController.addListener(_onScroll);
    _downloadStatusSubscription = downloadStore.illustDownloadStatusStream
        .listen(_onDownloadStatusChanged);
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
      final users = await downloadStore.getDistinctUsers();
      List<DownloadedIllust> illusts;

      if (_filterUserId != null) {
        illusts = await downloadStore.getDownloadedByUser(
          _filterUserId!,
          limit: _pageSize,
          offset: 0,
        );
      } else if (_searchKeyword != null && _searchKeyword!.isNotEmpty) {
        illusts = await downloadStore.searchDownloaded(
          _searchKeyword!,
          limit: _pageSize,
          offset: 0,
        );
      } else {
        illusts = await downloadStore.getAllDownloaded(
          limit: _pageSize,
          offset: 0,
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
          _users = users;
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

      if (_filterUserId != null) {
        moreIllusts = await downloadStore.getDownloadedByUser(
          _filterUserId!,
          limit: _pageSize,
          offset: offset,
        );
      } else if (_searchKeyword != null && _searchKeyword!.isNotEmpty) {
        moreIllusts = await downloadStore.searchDownloaded(
          _searchKeyword!,
          limit: _pageSize,
          offset: offset,
        );
      } else {
        moreIllusts = await downloadStore.getAllDownloaded(
          limit: _pageSize,
          offset: offset,
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

  void _onSearch(String keyword) {
    setState(() {
      _searchKeyword = keyword.isEmpty ? null : keyword;
      _filterUserId = null;
      _filterUserName = null;
    });
    _loadData();
  }

  void _onFilterByUser(int? userId, String? userName) {
    setState(() {
      _filterUserId = userId;
      _filterUserName = userName;
      _searchKeyword = null;
    });
    _loadData();
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
          IconButton(
            icon: Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
          if (_filterUserId != null || _searchKeyword != null)
            IconButton(
              icon: Icon(Icons.clear),
              onPressed: () {
                _onFilterByUser(null, null);
              },
            ),
        ],
      ),
      body: _loading && _illusts.isEmpty
          ? Center(child: CircularProgressIndicator())
          : _filteredIllusts.isEmpty
              ? _buildEmptyView()
              : _buildGridView(),
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

  Widget _buildGridView() {
    final filteredList = _filteredIllusts;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: GridView.builder(
        controller: _scrollController,
        padding: EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          childAspectRatio: 0.7,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: filteredList.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= filteredList.length) {
            return Center(child: CircularProgressIndicator());
          }
          return _buildIllustCard(filteredList[index]);
        },
      ),
    );
  }

  int _getCrossAxisCount() {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 6;
    if (width > 900) return 5;
    if (width > 600) return 4;
    if (width > 400) return 3;
    return 2;
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
                          child: _buildPageCountIndicator(illust),
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

  Widget _buildPageCountIndicator(DownloadedIllust illust) {
    final downloadedCount =
        _downloadedCounts[illust.illustId] ?? illust.pageCount;
    final totalCount = illust.pageCount;

    if (downloadedCount < totalCount) {
      return Text(
        '$downloadedCount/$totalCount',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.orange,
            ),
      );
    } else {
      return Text(
        '${totalCount}P',
        style: Theme.of(context).textTheme.bodySmall,
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

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          expand: false,
          builder: (ctx2, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    I18n.of(context).filter,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.clear_all),
                  title: Text(I18n.of(context).all),
                  selected: _filterUserId == null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _onFilterByUser(null, null);
                  },
                ),
                Divider(),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _users.length,
                    itemBuilder: (ctx3, index) {
                      final user = _users[index];
                      final userId = user['user_id'] as int;
                      final userName = user['user_name'] as String;
                      final count = user['count'] as int;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(userName.isNotEmpty
                              ? userName[0].toUpperCase()
                              : '?'),
                        ),
                        title: Text(userName),
                        subtitle: Text('$count'),
                        selected: _filterUserId == userId,
                        onTap: () {
                          Navigator.pop(ctx);
                          _onFilterByUser(userId, userName);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSearchDialog() {
    final controller = TextEditingController(text: _searchKeyword);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(I18n.of(context).search),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: I18n.of(context).search,
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (value) {
              Navigator.pop(ctx);
              _onSearch(value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(I18n.of(context).cancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _onSearch(controller.text);
              },
              child: Text(I18n.of(context).ok),
            ),
          ],
        );
      },
    );
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
