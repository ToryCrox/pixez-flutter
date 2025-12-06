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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pixez/er/leader.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/picture/illust_lighting_page.dart';

class DownloadedPage extends StatefulWidget {
  const DownloadedPage({Key? key}) : super(key: key);

  @override
  State<DownloadedPage> createState() => _DownloadedPageState();
}

class _DownloadedPageState extends State<DownloadedPage> {
  List<DownloadedIllust> _illusts = [];
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _searchKeyword;
  int? _filterUserId;
  String? _filterUserName;
  final ScrollController _scrollController = ScrollController();
  int _page = 0;
  static const int _pageSize = 30;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

      if (mounted) {
        setState(() {
          _users = users;
          _illusts = illusts;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_filterUserName ?? I18n.of(context).history),
        actions: [
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
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _illusts.isEmpty
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
    return RefreshIndicator(
      onRefresh: _loadData,
      child: GridView.builder(
        controller: _scrollController,
        padding: EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _getCrossAxisCount(),
          childAspectRatio: 0.7,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _illusts.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _illusts.length) {
            return Center(child: CircularProgressIndicator());
          }
          return _buildIllustCard(_illusts[index]);
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildThumbnail(illust),
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
                  if (illust.pageCount > 1)
                    Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        '${illust.pageCount}P',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
    return FutureBuilder<String?>(
      future: _getFirstImagePath(illust),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.file(
            File(snapshot.data!),
            fit: BoxFit.cover,
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
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Future<String?> _getFirstImagePath(DownloadedIllust illust) async {
    return await downloadStore.getLocalImagePath(illust.illustId, 0);
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
                          child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?'),
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
                  final path = p.join(
                    downloadStore.downloadPath,
                    illust.relativePath,
                  );
                  // 打开文件夹（Windows/Linux）
                  if (Platform.isWindows) {
                    await Process.run('explorer', [path]);
                  } else if (Platform.isLinux) {
                    await Process.run('xdg-open', [path]);
                  }
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
