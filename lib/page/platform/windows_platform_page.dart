import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';

class WindowsPlatformPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    if (Platform.isWindows || Platform.isMacOS) return _WindowsPlatformPageState();
    throw UnimplementedError();
  }
}

class _WindowsPlatformPageState extends State<WindowsPlatformPage> {
  String path = "";
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _initPath();
  }

  Future<void> _initPath() async {
    final currentPath = userSetting.downloadPath;
    if (mounted) {
      setState(() {
        path = currentPath ?? "";
      });
    }
  }

  /// 选择下载路径并更新 downloadStore
  Future<void> _chooseDownloadPath() async {
    try {
      setState(() {
        isLoading = true;
      });

      // 使用 file_picker 选择目录
      String? selectedPath = await FilePicker.platform.getDirectoryPath();
      
      if (selectedPath != null && selectedPath.isNotEmpty && selectedPath != path) {
        // 保存到 UserSetting
        await userSetting.setDownloadPath(selectedPath);
        
        // 更新 downloadStore 的下载路径（立即生效）
        await downloadStore.updateDownloadPath(selectedPath);
        
        if (mounted) {
          setState(() {
            path = selectedPath;
          });
          BotToast.showText(text: '下载路径已更新');
        }
      }
    } catch (e) {
      BotToast.showText(text: '设置失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// 打开当前下载目录
  Future<void> _openDownloadDirectory() async {
    if (path.isEmpty) {
      BotToast.showText(text: '下载路径未设置');
      return;
    }
    
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      // 使用系统命令打开文件夹
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      }
    } catch (e) {
      BotToast.showText(text: '打开目录失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final platformName = Platform.isWindows ? "Windows" : "macOS";
    final platformColor = Platform.isWindows ? Colors.blue : Colors.grey;
    
    return AlertDialog(
      title: ListTile(
        title: Text(I18n.ofContext().platform_special_setting),
        subtitle: Text(
          "For $platformName",
          style: TextStyle(color: platformColor),
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(Icons.folder),
              title: Text(I18n.ofContext().save_path),
              subtitle: Text(path.isEmpty ? '未设置' : path),
              trailing: isLoading 
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
              onTap: isLoading ? null : _chooseDownloadPath,
            ),
            ListTile(
              leading: Icon(Icons.folder_open),
              title: Text('打开下载目录'),
              enabled: path.isNotEmpty && !isLoading,
              onTap: path.isEmpty || isLoading ? null : _openDownloadDirectory,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text(I18n.ofContext().ok),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
