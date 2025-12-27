import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:pixez/document_plugin.dart';
import 'package:pixez/main.dart';

class WindowsPlatformPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    if (Platform.isWindows) return _WindowsPlatformPageState();
    throw UnimplementedError();
  }
}

class _WindowsPlatformPageState extends State<WindowsPlatformPage> {
  late TextEditingController _pathController;
  String? _pathError;
  bool _isValidating = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController();
    _initPath();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initPath() async {
    // 优先从 userSetting.storePath 读取
    String? path = userSetting.storePath;
    
    // 如果 storePath 为空，尝试从 DocumentPlugin 获取
    if (path == null || path.isEmpty) {
      path = await DocumentPlugin.getPath();
    }
    
    if (mounted && path != null && path.isNotEmpty) {
      _pathController.text = path;
      // 初始化时校验一次
      await _validatePath(path);
    }
  }

  /// 校验路径
  Future<void> _validatePath(String path) async {
    if (!mounted) return;
    
    setState(() {
      _isValidating = true;
      _pathError = null;
    });

    try {
      if (path.isEmpty) {
        setState(() {
          _pathError = '路径不能为空';
          _isValidating = false;
        });
        return;
      }

      final dir = Directory(path);
      final exists = await dir.exists();
      
      if (!exists) {
        setState(() {
          _pathError = '目录不存在';
          _isValidating = false;
        });
        return;
      }

      // 检查访问权限 - 尝试列出目录
      try {
        await dir.list(followLinks: false).first.timeout(
          Duration(seconds: 2),
          onTimeout: () => throw TimeoutException('访问超时'),
        );
      } catch (e) {
        setState(() {
          _pathError = '无法访问该目录';
          _isValidating = false;
        });
        return;
      }

      // 校验通过
      setState(() {
        _pathError = null;
        _isValidating = false;
      });
    } catch (e) {
      setState(() {
        _pathError = '校验失败: $e';
        _isValidating = false;
      });
    }
  }

  /// 实时校验（带防抖）
  void _onPathChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: 500), () {
      _validatePath(value);
    });
  }

  /// 打开目录选择器
  Future<void> _chooseFolder() async {
    try {
      await DocumentPlugin.choiceFolder();
      final path = await DocumentPlugin.getPath();
      
      if (mounted && path != null && path.isNotEmpty) {
        _pathController.text = path;
        await _validatePath(path);
      }
    } catch (e) {
      BotToast.showText(text: '选择目录失败: $e');
    }
  }

  /// 保存下载路径
  Future<void> _saveDownloadPath() async {
    final path = _pathController.text.trim();
    
    // 最终校验
    await _validatePath(path);
    
    if (_pathError != null) {
      BotToast.showText(text: '请先解决路径错误');
      return;
    }

    // 检查是否修改了路径
    final currentPath = userSetting.storePath ?? '';
    if (currentPath.isNotEmpty && currentPath != path) {
      // 路径发生变化，提示用户需要手动迁移数据
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('确认修改下载路径？'),
          content: Text(
            '修改下载路径后，您需要手动将以下文件迁移到新路径：\n\n'
            '1. download.db（数据库文件）\n'
            '2. download/（下载文件夹）\n\n'
            '从：$currentPath\n'
            '到：$path\n\n'
            '确认继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('确认'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    try {
      // 1. 保存到 userSetting
      await userSetting.setStorePath(path);
      
      // 2. 更新 downloadStore 的下载路径和数据库
      await downloadStore.updateDownloadPath(path);
      
      // 3. 通知用户
      BotToast.showText(text: '下载路径已更新');
      
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      BotToast.showText(text: '保存失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: ListTile(
        title: Text("Platform Setting"),
        subtitle: Text(
          "For Windows",
          style: TextStyle(color: Colors.blue),
        ),
      ),
      content: Container(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '下载路径',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 12),
            
            // 路径输入框
            TextField(
              controller: _pathController,
              decoration: InputDecoration(
                hintText: '请输入下载目录路径',
                border: OutlineInputBorder(),
                errorText: _pathError,
                suffixIcon: _isValidating
                    ? Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _pathError == null && _pathController.text.isNotEmpty
                        ? Icon(Icons.check_circle, color: Colors.green)
                        : null,
              ),
              onChanged: _onPathChanged,
            ),
            SizedBox(height: 12),
            
            // 操作按钮
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _chooseFolder,
                  icon: Icon(Icons.folder_open),
                  label: Text('选择目录'),
                ),
                SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _pathError == null && _pathController.text.isNotEmpty
                      ? _saveDownloadPath
                      : null,
                  icon: Icon(Icons.save),
                  label: Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text('取消'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
