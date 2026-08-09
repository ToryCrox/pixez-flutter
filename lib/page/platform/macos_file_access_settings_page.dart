import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pixez/platform/macos_file_access.dart';

/// macOS 文件访问权限管理页面
class MacOSFileAccessSettingsPage extends StatefulWidget {
  const MacOSFileAccessSettingsPage({Key? key}) : super(key: key);

  @override
  State<MacOSFileAccessSettingsPage> createState() =>
      _MacOSFileAccessSettingsPageState();
}

class _MacOSFileAccessSettingsPageState
    extends State<MacOSFileAccessSettingsPage> {
  List<String> _bookmarkedPaths = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _loadBookmarks();
    }
  }

  Future<void> _loadBookmarks() async {
    setState(() => _isLoading = true);
    try {
      final paths = await MacOSFileAccessManager.getAllBookmarkedPaths();
      setState(() {
        _bookmarkedPaths = paths;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  Future<void> _requestAccess() async {
    try {
      final (success, path) =
          await MacOSFileAccessManager.requestDirectoryAccess();
      if (success && path != null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已授权访问: $path')));
        }
        await _loadBookmarks();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('用户取消或授权失败')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('请求授权失败: $e')));
      }
    }
  }

  Future<void> _clearBookmark(String path) async {
    try {
      await MacOSFileAccessManager.clearBookmark(path);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已清除: $path')));
      }
      await _loadBookmarks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('清除失败: $e')));
      }
    }
  }

  Future<void> _clearAllBookmarks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认清除'),
            content: const Text('确定要清除所有已授权的目录吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确定'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        await MacOSFileAccessManager.clearAllBookmarks();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已清除所有授权')));
        }
        await _loadBookmarks();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('清除失败: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return Scaffold(
        appBar: AppBar(title: const Text('文件访问权限')),
        body: const Center(child: Text('此功能仅适用于 macOS')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('文件访问权限管理'),
        actions: [
          if (_bookmarkedPaths.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清除所有授权',
              onPressed: _clearAllBookmarks,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadBookmarks,
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  // 说明卡片
                  Card(
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Theme.of(context).primaryColor,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '关于外部存储访问',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '由于 macOS 沙盒限制，访问外部存储卷（如 U盘、移动硬盘）需要用户明确授权。\n\n'
                            '授权后，应用会保存访问权限（Security-Scoped Bookmark），'
                            '下次启动时可以自动恢复访问。\n\n'
                            '如果更换了外部存储设备或路径变化，需要重新授权。',
                            style: TextStyle(fontSize: 14, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 已授权列表
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Text(
                          '已授权目录',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(${_bookmarkedPaths.length})',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  Expanded(
                    child:
                        _bookmarkedPaths.isEmpty
                            ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.folder_off,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '暂无已授权的目录',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '点击下方按钮添加授权目录',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            )
                            : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: _bookmarkedPaths.length,
                              itemBuilder: (context, index) {
                                final path = _bookmarkedPaths[index];
                                final isExternal =
                                    MacOSFileAccessManager.isExternalVolume(
                                      path,
                                    );

                                return Card(
                                  child: ListTile(
                                    leading: Icon(
                                      isExternal ? Icons.storage : Icons.folder,
                                      color:
                                          isExternal
                                              ? Colors.orange
                                              : Colors.blue,
                                    ),
                                    title: Text(
                                      path,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    subtitle: Text(
                                      isExternal ? '外部存储卷' : '本地目录',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: '清除授权',
                                      onPressed: () => _clearBookmark(path),
                                    ),
                                  ),
                                );
                              },
                            ),
                  ),
                ],
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _requestAccess,
        icon: const Icon(Icons.add),
        label: const Text('添加授权目录'),
      ),
    );
  }
}
