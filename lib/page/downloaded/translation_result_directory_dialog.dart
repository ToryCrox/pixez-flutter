import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pixez/main.dart';

/// 设置外部漫画翻译结果根目录。
class TranslationResultDirectoryDialog extends StatefulWidget {
  const TranslationResultDirectoryDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const TranslationResultDirectoryDialog(),
    );
  }

  @override
  State<TranslationResultDirectoryDialog> createState() =>
      _TranslationResultDirectoryDialogState();
}

class _TranslationResultDirectoryDialogState
    extends State<TranslationResultDirectoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: userSetting.translationResultDirectory,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择漫画翻译结果目录',
      lockParentWindow: true,
    );
    if (selected == null || !mounted) return;
    setState(() => _controller.text = selected);
  }

  Future<void> _save() async {
    await userSetting.setTranslationResultDirectory(_controller.text);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('漫画翻译结果目录'),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: '目录路径',
            hintText: '留空则仅使用漫画目录内的 result 目录',
            helperText: '外部目录中应包含与原漫画同名的漫画目录',
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    tooltip: '清空',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(_controller.clear),
                  ),
                IconButton(
                  tooltip: '选择目录',
                  icon: const Icon(Icons.folder_open),
                  onPressed: _pickDirectory,
                ),
              ],
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('确认')),
      ],
    );
  }
}
