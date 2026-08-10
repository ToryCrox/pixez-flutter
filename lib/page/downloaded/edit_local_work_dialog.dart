import 'package:flutter/material.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';

class EditLocalWorkDialog extends StatefulWidget {
  final DownloadedIllust work;

  const EditLocalWorkDialog({super.key, required this.work});

  static Future<bool?> show(BuildContext context, DownloadedIllust work) =>
      showDialog<bool>(
        context: context,
        builder: (_) => EditLocalWorkDialog(work: work),
      );

  @override
  State<EditLocalWorkDialog> createState() => _EditLocalWorkDialogState();
}

class _EditLocalWorkDialogState extends State<EditLocalWorkDialog> {
  late final TextEditingController _title;
  late DateTime _date;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.work.title);
    _date = DateTime.tryParse(widget.work.createDate) ?? DateTime.now();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '标题不能为空');
      return;
    }
    setState(() => _busy = true);
    try {
      await downloadStore.originalRepository.updateLocalMetadata(
        illustId: widget.work.illustId,
        title: _title.text.trim(),
        createDate: _date,
      );
      if (mounted) Navigator.pop(context, true);
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
      title: const Text('编辑本地作品'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: '作品标题'),
            ),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('保存')),
      ],
    );
  }
}
