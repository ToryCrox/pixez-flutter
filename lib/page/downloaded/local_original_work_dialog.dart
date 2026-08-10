import 'package:flutter/material.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/downloaded/original_import_dialog.dart';

class LocalOriginalWorkDialog extends StatefulWidget {
  final int userId;
  final String userName;

  const LocalOriginalWorkDialog({
    super.key,
    required this.userId,
    required this.userName,
  });

  static Future<bool?> show(
    BuildContext context, {
    required int userId,
    required String userName,
  }) => showDialog<bool>(
    context: context,
    builder: (_) => LocalOriginalWorkDialog(userId: userId, userName: userName),
  );

  @override
  State<LocalOriginalWorkDialog> createState() =>
      _LocalOriginalWorkDialogState();
}

class _LocalOriginalWorkDialogState extends State<LocalOriginalWorkDialog> {
  final _title = TextEditingController();
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请输入作品标题');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final author = await downloadStore.dbProvider.getAuthorByUserId(
        widget.userId,
      );
      if (author == null) throw StateError('本地作品必须归入数据库已有作者');
      final local = await downloadStore.originalRepository.createLocalIllust(
        userId: widget.userId,
        userName: widget.userName,
        title: title,
        createDate: _date,
      );
      if (!mounted) return;
      final imported = await OriginalImportDialog.show(context, local);
      if (imported != true) {
        await downloadStore.dbProvider.deleteIllustByIllustId(local.illustId);
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (context.mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('新建本地作品 · ${widget.userName}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '作品标题'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('作品日期'),
              subtitle: Text(_date.toIso8601String().split('T').first),
              onTap:
                  _busy
                      ? null
                      : () async {
                        final selected = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                          initialDate: _date,
                        );
                        if (selected != null) setState(() => _date = selected);
                      },
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const Text('下一步选择单个作品目录并预览页面关系。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _continue,
          child: const Text('下一步'),
        ),
      ],
    );
  }
}
