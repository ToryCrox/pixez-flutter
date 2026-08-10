import 'package:flutter/material.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/original_image_repository.dart';

class LinkLocalWorkDialog extends StatefulWidget {
  final DownloadedIllust localWork;

  const LinkLocalWorkDialog({super.key, required this.localWork});

  static Future<bool?> show(BuildContext context, DownloadedIllust localWork) =>
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => LinkLocalWorkDialog(localWork: localWork),
      );

  @override
  State<LinkLocalWorkDialog> createState() => _LinkLocalWorkDialogState();
}

class _LinkLocalWorkDialogState extends State<LinkLocalWorkDialog> {
  final _target = TextEditingController();
  Map<int, List<OriginalMappingDraft>>? _preview;
  DownloadedIllust? _targetWork;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final id = int.tryParse(_target.text.trim());
    if (id == null || id <= 0) {
      setState(() => _error = '请输入有效的 Pixiv 作品 ID');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target = await downloadStore.getDownloadedIllust(id);
      if (target == null || target.isLocal) {
        throw StateError('只能关联数据库已有的 Pixiv 作品');
      }
      final preview = await downloadStore.originalImportService
          .previewLocalLink(
            localIllustId: widget.localWork.illustId,
            targetPixivIllustId: id,
          );
      if (mounted) {
        setState(() {
          _targetWork = target;
          _preview = preview;
        });
      }
    } catch (e, stackTrace) {
      Log.e('本地作品关联预览失败', error: e, stackTrace: stackTrace);
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final target = _targetWork;
    final preview = _preview;
    if (target == null || preview == null) return;
    setState(() => _busy = true);
    try {
      await downloadStore.originalRepository.linkLocalToPixiv(
        widget.localWork.illustId,
        target.illustId,
        mappingsBySet: preview,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e, stackTrace) {
      Log.e('关联本地作品失败', error: e, stackTrace: stackTrace);
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
      title: Text('关联 Pixiv 作品 · ${widget.localWork.title}'),
      content: SizedBox(
        width: 680,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _target,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '数据库已有 Pixiv 作品 ID'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _prepare,
              child: const Text('重新对齐并预览'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_targetWork != null) ...[
              const SizedBox(height: 12),
              Text(
                '目标：${_targetWork!.title}（${_targetWork!.pageCount} 页）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text('只迁移原图版本和映射；目标元数据、标签、收藏和下载记录保持不变。'),
            ],
            Expanded(
              child: ListView(
                children: [
                  for (final entry
                      in _preview?.entries.toList() ??
                          <MapEntry<int, List<OriginalMappingDraft>>>[])
                    ExpansionTile(
                      title: Text('版本 ${entry.key}'),
                      subtitle: Text('重新对齐后 ${entry.value.length} 页'),
                      children: [
                        for (final mapping in entry.value)
                          ListTile(
                            dense: true,
                            leading: Text('${mapping.displayOrder + 1}'),
                            title: Text(
                              '下载 ${mapping.downloadedPart == null ? "—" : mapping.downloadedPart! + 1} ↔ 原图 ${mapping.originalSourceOrder == null ? "—" : mapping.originalSourceOrder! + 1}',
                            ),
                            trailing: Text(mapping.relationType.value),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy || _preview == null ? null : _commit,
          child: const Text('确认关联'),
        ),
      ],
    );
  }
}
