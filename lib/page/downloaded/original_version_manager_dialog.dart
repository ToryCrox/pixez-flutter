import 'package:flutter/material.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/original_image.dart';

class OriginalVersionManagerDialog extends StatefulWidget {
  final DownloadedIllust illust;

  const OriginalVersionManagerDialog({super.key, required this.illust});

  static Future<bool?> show(BuildContext context, DownloadedIllust illust) =>
      showDialog<bool>(
        context: context,
        builder: (_) => OriginalVersionManagerDialog(illust: illust),
      );

  @override
  State<OriginalVersionManagerDialog> createState() =>
      _OriginalVersionManagerDialogState();
}

class _OriginalVersionManagerDialogState
    extends State<OriginalVersionManagerDialog> {
  late Future<List<OriginalImageSet>> _sets;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _sets = downloadStore.originalRepository.getSetsForIllust(
      widget.illust.illustId,
    );
  }

  Future<void> _remove(OriginalImageSet set) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('移除原图版本'),
            content: Text(
              '确定移除“${set.editionName}”吗？\n${set.imageCount} 张，${_formatBytes(set.totalFileSize)}。\n此操作不会删除下载图。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('移除版本'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await downloadStore.originalRepository.removeSetSafely(set.id!);
      _changed = true;
      if (mounted) setState(_reload);
    } catch (e, stackTrace) {
      Log.e('移除原图版本失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('移除失败：$e')));
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('原图版本 · ${widget.illust.title}'),
      content: SizedBox(
        width: 620,
        height: 420,
        child: FutureBuilder<List<OriginalImageSet>>(
          future: _sets,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final sets = snapshot.data!;
            if (sets.isEmpty) return const Center(child: Text('暂无原图版本'));
            return ListView.separated(
              itemCount: sets.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final set = sets[index];
                return ListTile(
                  leading: Icon(set.isDefault ? Icons.star : Icons.hd),
                  title: Text(set.editionName),
                  subtitle: Text(
                    '${set.imageCount} 张 · 增强 ${set.enhancedPageCount} 页 · ${_formatBytes(set.totalFileSize)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!set.isDefault)
                        IconButton(
                          tooltip: '设为默认版本',
                          onPressed: () async {
                            await downloadStore.originalRepository.setDefault(
                              set.id!,
                            );
                            _changed = true;
                            if (mounted) setState(_reload);
                          },
                          icon: const Icon(Icons.star_border),
                        ),
                      IconButton(
                        tooltip: '移除版本',
                        onPressed: () => _remove(set),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
