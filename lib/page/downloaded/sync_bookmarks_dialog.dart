import 'package:flutter/material.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/picture_list_page.dart';
import 'package:pixez/er/leader.dart';

class SyncBookmarksDialog extends StatefulWidget {
  const SyncBookmarksDialog({Key? key}) : super(key: key);

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SyncBookmarksDialog(),
    );
  }

  @override
  State<SyncBookmarksDialog> createState() => _SyncBookmarksDialogState();
}

class _SyncBookmarksDialogState extends State<SyncBookmarksDialog> {
  // 状态：0=初始, 1=加载中, 2=展示列表, 3=同步中
  int _state = 0;
  String _statusMessage = '';
  
  // 分页数据
  int _userId = 0;
  String _restrict = 'public'; // 'public' or 'private'
  int _currentOffset = 0;
  int? _nextOffset;
  List<Illusts> _currentIllusts = [];
  
  // 本地状态缓存
  Map<int, DownloadedIllust?> _localIllusts = {};
  
  // 选中待同步的ID
  Set<int> _selectedIds = {};
  
  @override
  void initState() {
    super.initState();
    _initUserId();
  }

  void _initUserId() {
    if (accountStore.now == null) {
      _statusMessage = '请先登录';
      return;
    }
    // 临时修复获取 userId 的问题
    try {
        if (accountStore.now != null) {
          _userId = int.parse(accountStore.now!.userId);
          _state = 0; // Ready to start
        } else {
           _statusMessage = '请先登录';
        }
    } catch (e) {
        _statusMessage = '无法获取用户信息: $e';
    }
  }

  // 加载一页数据
  Future<void> _loadPage({bool next = true}) async {
    if (_userId == 0) return;

    setState(() {
      _state = 1;
      _statusMessage = '正在获取在线收藏...';
    });

    try {
      
      // 如果是第一页，重置 offset
      if (!next) {
         _currentOffset = 0;
      }
      
      final result = await downloadStore.fetchOnlineBookmarksPage(
        _userId,
        _restrict,
        _currentOffset,
      );

      final illusts = result['illusts'] as List<Illusts>;
      final nextOff = result['nextOffset'] as int?;

      // 检查本地状态
      final localMap = <int, DownloadedIllust?>{};
      final selected = <int>{};
      
      for (final illust in illusts) {
        final local = await downloadStore.dbProvider.getIllustByIllustId(illust.id);
        localMap[illust.id] = local;
        
        // 默认勾选：本地已下载 且 未收藏
        if (local != null && local.bookmark == 0) {
          selected.add(illust.id);
        }
      }

      if (!mounted) return;
      setState(() {
        _currentIllusts = illusts;
        _nextOffset = nextOff;
        _localIllusts = localMap;
        _selectedIds = selected;
        _state = 2; // Show list
      });
    } catch (e) {
      Log.e('Sync load page failed', error: e);
      if (!mounted) return;
      setState(() {
        _statusMessage = '加载失败: $e';
        _state = 0; // Retry?
      });
    }
  }

  // 执行同步
  Future<void> _confirmSync() async {
    if (_selectedIds.isEmpty) return;
    
    setState(() {
      _state = 3;
      _statusMessage = '正在同步...';
    });

    int successCount = 0;
    try {
      for (final id in _selectedIds) {
        // 更新本地为默认收藏 (1)
        await downloadStore.dbProvider.updateIllustBookmark(id, 1);
        successCount++;
        
        // 更新本地状态缓存，以便 UI 刷新
        final local = _localIllusts[id];
        if (local != null) {
           _localIllusts[id] = local.copyWith(bookmark: 1);
        }
      }
      
      if (!mounted) return;
      
      // 同步完成后回到列表状态，清空选中
      setState(() {
        _selectedIds.clear();
        _state = 2;
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('成功同步 $successCount 个收藏状态')),
        );
      });
    } catch (e) {
       setState(() {
         _statusMessage = '同步失败: $e';
         _state = 2;
       });
    }
  }

  void _onPageChange(bool next) {
     if (next) {
       if (_nextOffset != null) {
         _currentOffset = _nextOffset!;
         _loadPage(next: true);
       }
     } else {
        // 简单处理：不支持上一页（Pixiv API offset 分页比较麻烦，通常只能往后）
        // 或者支持重置到第一页
        _currentOffset = 0;
        _loadPage(next: false);
     }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text('同步在线收藏'),
          Spacer(),
          DropdownButton<String>(
            value: _restrict,
            onChanged: _state == 1 || _state == 3 ? null : (v) {
               if (v != null) {
                 setState(() {
                   _restrict = v;
                   _currentOffset = 0;
                   _currentIllusts.clear();
                   _state = 0;
                 });
               }
            },
            items: [
               DropdownMenuItem(value: 'public', child: Text('公开')),
               DropdownMenuItem(value: 'private', child: Text('非公开')),
            ],
            underline: SizedBox(),
            style: TextStyle(fontSize: 14, color: Theme.of(context).primaryColor),
          )
        ],
      ),
      content: Container(
        width: 600, // Limiting width
        height: 800, // Fixed height
        child: _buildContent(),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildContent() {
    if (_statusMessage.isNotEmpty && _state != 2) {
       if (_state == 1 || _state == 3) {
         return Center(
           child: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               CircularProgressIndicator(),
               SizedBox(height: 16),
               Text(_statusMessage),
             ],
           ),
         );
       }
       return Center(child: Text(_statusMessage));
    }
    
    if (_state == 0) {
      return Center(
        child: ElevatedButton(
          onPressed: () => _loadPage(next: false),
          child: Text('获取第一页'),
        ),
      );
    }
    
    if (_state == 2 && _currentIllusts.isEmpty) {
       return Center(child: Text('本页无数据'));
    }

    // List View
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
             children: [
               Text('本页共 ${_currentIllusts.length} 条'),
               Spacer(),
               TextButton(
                 onPressed: _currentIllusts.any((i) => _localIllusts[i.id]?.bookmark == 0) 
                     ? () {
                     // Select all update-able
                     final newIds = <int>{};
                     for(var i in _currentIllusts) {
                       final local = _localIllusts[i.id];
                       if (local != null && local.bookmark == 0) {
                          newIds.add(i.id);
                       }
                     }
                     setState(() => _selectedIds = newIds);
                 } : null,
                 child: Text('全选待更新'),
               ),
             ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _currentIllusts.length,
            itemBuilder: (context, index) {
              final illust = _currentIllusts[index];
              final local = _localIllusts[illust.id];
              
              bool isDownloaded = local != null;
              bool isBookmarked = local != null && local.bookmark > 0;
              bool isSelected = _selectedIds.contains(illust.id);
              
              String statusText = '';
              Color statusColor = Colors.grey;
              if (isBookmarked) {
                statusText = '已收藏';
                statusColor = Colors.green;
              } else if (isDownloaded) {
                statusText = '本地存在'; // 已下载但未同步/未收藏
                statusColor = Colors.orange;
              } else {
                statusText = '未下载';
                statusColor = Colors.grey;
              }

              return CheckboxListTile(
                value: isSelected,
                onChanged: (isDownloaded && !isBookmarked) ? (val) {
                   setState(() {
                     if (val == true) _selectedIds.add(illust.id);
                     else _selectedIds.remove(illust.id);
                   });
                } : null,
                enabled: isDownloaded && !isBookmarked,
                title: Text(illust.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Row(
                  children: [
                    Text('ID: ${illust.id}'),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(fontSize: 10, color: statusColor),
                      ),
                    ),
                  ],
                ),
                secondary: InkWell(
                  onTap: () => _navigateToIllust(illust),
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                   width: 50, height: 50,
                   child: PixivImage(
                      illust.imageUrls.squareMedium,
                      fit: BoxFit.cover,
                      width: 50,
                      height: 50,
                      httpHeaders: {
                        'cover': '${illust.id}',
                        'quality': 'square_medium',
                      },
                   ),
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                isThreeLine: false,
                contentPadding: EdgeInsets.only(left: 0, right: 8), 
              );
            }, 
          ),
        ),
      ],
    );
  }

  void _navigateToIllust(Illusts illust) {
    if (_currentIllusts.isEmpty) return;
    
    // Create stores for the current list to enable swiping
    final iStores = _currentIllusts.map((e) => IllustStore(e.id, e)).toList();
    final index = _currentIllusts.indexOf(illust);
    if (index == -1) return;
    
    Leader.push(
      context,
      PictureListPage(
        lightingStore: null,
        store: iStores[index],
        iStores: iStores,
      ),
    );
  }

  
  // Custom item builder to show status better
  // Using CheckboxListTile has limitations for secondary slot width/layout.
  // ... keeping simple for now.
  
  List<Widget> _buildActions() {
    if (_state == 2) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('关闭'),
        ),
        if (_currentOffset > 0)
          TextButton(
            onPressed: () => _onPageChange(false),
            child: Text('第一页'),
          ),
        ElevatedButton(
          onPressed: _nextOffset != null ? () => _onPageChange(true) : null,
          child: Text('下一页'),
        ),
        SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _selectedIds.isNotEmpty ? _confirmSync : null,
          icon: Icon(Icons.sync),
          label: Text('同步选中 (${_selectedIds.length})'),
        ),
      ];
    }
    return [
       TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消'),
        ),
    ];
  }
}
