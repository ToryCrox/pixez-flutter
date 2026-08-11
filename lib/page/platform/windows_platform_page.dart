import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pixez/main.dart';
import 'package:pixez/utils/download_path.dart';

class WindowsPlatformPage extends StatefulWidget {
  @override
  State<WindowsPlatformPage> createState() => _WindowsPlatformPageState();
}

class _WindowsPlatformPageState extends State<WindowsPlatformPage> {
  late TextEditingController _pathController;
  String? _pathError;
  bool _isValidating = false;
  Timer? _debounceTimer;
  int _validationGeneration = 0;

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
    // 优先从 userSetting.downloadPath 读取
    String? configuredPath = userSetting.downloadPath;

    // 如果 downloadPath 为空，尝试从旧配置获取
    if (configuredPath == null || configuredPath.isEmpty) {
      configuredPath = userSetting.storePath;
    }

    final path =
        configuredPath == null || configuredPath.isEmpty
            ? await getDefaultDownloadPath()
            : configuredPath;

    if (mounted) {
      _pathController.text = path;
      await _validatePath(path);
    }
  }

  /// 校验路径
  Future<bool> _validatePath(String path) async {
    if (!mounted) return false;

    final normalizedPath = path.trim();
    final validationGeneration = ++_validationGeneration;

    setState(() {
      _isValidating = true;
      _pathError = null;
    });

    final result = await validateDownloadPath(normalizedPath);
    if (!mounted ||
        validationGeneration != _validationGeneration ||
        normalizedPath != _pathController.text.trim()) {
      return false;
    }

    final error = switch (result) {
      DownloadPathValidationResult.valid => null,
      DownloadPathValidationResult.empty => '路径不能为空',
      DownloadPathValidationResult.notFound => '目录不存在',
      DownloadPathValidationResult.inaccessible => '无法访问该目录',
    };

    setState(() {
      _pathError = error;
      _isValidating = false;
    });
    return result == DownloadPathValidationResult.valid;
  }

  /// 实时校验（带防抖）
  void _onPathChanged(String value) {
    _debounceTimer?.cancel();
    _validationGeneration++;
    setState(() {
      _isValidating = true;
      _pathError = null;
    });
    _debounceTimer = Timer(Duration(milliseconds: 500), () {
      _validatePath(value);
    });
  }

  /// 打开目录选择器
  Future<void> _chooseFolder() async {
    try {
      String? path = await FilePicker.platform.getDirectoryPath();

      if (mounted && path != null && path.isNotEmpty) {
        _pathController.text = path;
        await _validatePath(path);
      }
    } catch (e) {
      BotToast.showText(text: '选择目录失败: $e');
    }
  }

  /// 恢复默认下载目录
  Future<void> _restoreDefaultFolder() async {
    _debounceTimer?.cancel();

    try {
      final path = await getDefaultDownloadPath();
      await Directory(path).create(recursive: true);

      if (mounted) {
        _pathController.text = path;
        await _validatePath(path);
      }
    } catch (e) {
      BotToast.showText(text: '恢复默认目录失败: $e');
    }
  }

  /// 保存下载路径
  Future<void> _saveDownloadPath() async {
    final path = _pathController.text.trim();

    // 最终校验
    final isValid = await _validatePath(path);

    if (!isValid) {
      BotToast.showText(text: '请先解决路径错误');
      return;
    }

    // 检查是否修改了路径
    final currentPath = userSetting.downloadPath ?? '';
    if (currentPath.isNotEmpty && currentPath != path) {
      // 路径发生变化，提示用户需要手动迁移数据
      final confirm = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
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
      await userSetting.setDownloadPath(path);

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
    final platformName = Platform.isMacOS ? 'macOS' : 'Windows';
    final platformColor = Platform.isMacOS ? Colors.grey : Colors.blue;

    return AlertDialog(
      title: ListTile(
        title: Text("Platform Setting"),
        subtitle: Text(
          "For $platformName",
          style: TextStyle(color: platformColor),
        ),
      ),
      content: Container(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 24),
            Text('字体设置', style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                return Autocomplete<String>(
                  initialValue: TextEditingValue(
                    text: userSetting.fontFamily ?? '',
                  ),
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    const List<String> _kOptions = <String>[
                      'Microsoft YaHei',
                      'SimHei',
                      'Segoe UI',
                      'Consolas',
                      'Noto Sans Mono CJK SC',
                      'PingFang SC',
                      'Heiti SC',
                      'San Francisco',
                    ];
                    if (textEditingValue.text == '') {
                      return const Iterable<String>.empty();
                    }
                    return _kOptions.where((String option) {
                      return option.toLowerCase().contains(
                        textEditingValue.text.toLowerCase(),
                      );
                    });
                  },
                  onSelected: (String selection) {
                    userSetting.setFontFamily(selection);
                  },
                  fieldViewBuilder: (
                    BuildContext context,
                    TextEditingController textEditingController,
                    FocusNode focusNode,
                    VoidCallback onFieldSubmitted,
                  ) {
                    return Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: '输入或选择字体名称',
                              border: OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(Icons.clear),
                                onPressed: () {
                                  textEditingController.clear();
                                  userSetting.setFontFamily(null);
                                },
                                tooltip: '重置默字体',
                              ),
                            ),
                            onSubmitted: (String value) {
                              if (value.trim().isEmpty) {
                                userSetting.setFontFamily(null);
                              } else {
                                userSetting.setFontFamily(value.trim());
                              }
                            },
                          ),
                        ),
                        SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            final value = textEditingController.text.trim();
                            if (value.isEmpty) {
                              userSetting.setFontFamily(null);
                            } else {
                              userSetting.setFontFamily(value);
                            }
                            BotToast.showText(text: '字体已应用');
                          },
                          child: Text('应用'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            Divider(height: 32),
            Text('下载路径', style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 12),

            // 路径输入框
            TextField(
              controller: _pathController,
              decoration: InputDecoration(
                hintText: '请输入下载目录路径',
                border: OutlineInputBorder(),
                errorText: _pathError,
                suffixIcon:
                    _isValidating
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
                OutlinedButton.icon(
                  onPressed: _restoreDefaultFolder,
                  icon: Icon(Icons.restore),
                  label: Text('恢复默认目录'),
                ),
                SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed:
                      !_isValidating &&
                              _pathError == null &&
                              _pathController.text.isNotEmpty
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
