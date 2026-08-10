import 'package:flutter/material.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/main.dart';
import 'package:pixez/store/original_import_service.dart';
import 'package:pixez/utils/file_utils.dart';
import 'dart:io';

class OriginalImportRecoveryDialog extends StatefulWidget {
  const OriginalImportRecoveryDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const OriginalImportRecoveryDialog(),
  );

  @override
  State<OriginalImportRecoveryDialog> createState() =>
      _OriginalImportRecoveryDialogState();
}

class _OriginalImportRecoveryDialogState
    extends State<OriginalImportRecoveryDialog> {
  late Future<({List<OriginalImportManifest> jobs, List<String> broken})> _scan;
  String? _workingJobId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _scan = () async {
      final values = await Future.wait([
        downloadStore.originalImportService.findRecoverableJobs(),
        downloadStore.originalImportService.findBrokenJobDirectories(),
      ]);
      return (
        jobs: values[0] as List<OriginalImportManifest>,
        broken: values[1] as List<String>,
      );
    }();
  }

  Future<void> _resume(OriginalImportManifest job) async {
    setState(() => _workingJobId = job.jobId);
    try {
      await downloadStore.originalImportService.execute(job);
    } catch (e, stackTrace) {
      Log.e('恢复原图导入失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('恢复失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _workingJobId = null;
          _reload();
        });
      }
    }
  }

  Future<void> _cancel(OriginalImportManifest job) async {
    final committed =
        job.items
            .where((item) => item.state == OriginalImportItemState.committed)
            .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('取消导入任务'),
            content: Text(
              committed == 0
                  ? '未提交的暂存副本会被清理，来源目录不会改变。'
                  : '已有 $committed 个作品完成导入，它们不会回滚；仅清理其余暂存副本。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('返回'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认取消'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await downloadStore.originalImportService.cancel(job);
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('中断的原图导入任务'),
      content: SizedBox(
        width: 700,
        height: 440,
        child: FutureBuilder<
          ({List<OriginalImportManifest> jobs, List<String> broken})
        >(
          future: _scan,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final scan = snapshot.data!;
            if (scan.jobs.isEmpty && scan.broken.isEmpty) {
              return const Center(child: Text('没有可恢复的任务'));
            }
            return ListView(
              children: [
                for (final brokenPath in scan.broken)
                  ListTile(
                    leading: const Icon(
                      Icons.warning_amber,
                      color: Colors.orange,
                    ),
                    title: const Text('Manifest 损坏，无法自动恢复'),
                    subtitle: Text(brokenPath),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed:
                              () => FileUtils.openFileOrDirectory(brokenPath),
                          child: const Text('打开目录'),
                        ),
                        TextButton(
                          onPressed: () => _cleanBroken(brokenPath),
                          child: const Text('清理暂存'),
                        ),
                      ],
                    ),
                  ),
                for (var index = 0; index < scan.jobs.length; index++) ...[
                  if (index > 0 || scan.broken.isNotEmpty) const Divider(),
                  Builder(
                    builder: (_) {
                      final job = scan.jobs[index];
                      final committed =
                          job.items
                              .where(
                                (item) =>
                                    item.state ==
                                    OriginalImportItemState.committed,
                              )
                              .length;
                      final busy = _workingJobId == job.jobId;
                      return ListTile(
                        leading:
                            busy
                                ? const CircularProgressIndicator()
                                : const Icon(Icons.restore),
                        title: Text(
                          '${job.mode.name} · ${job.items.length} 个作品',
                        ),
                        subtitle: Text(
                          '${job.sourceRoot}\n已完成 $committed，更新时间 ${DateTime.fromMillisecondsSinceEpoch(job.updatedAt)}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: busy ? null : () => _cancel(job),
                              child: const Text('取消任务'),
                            ),
                            FilledButton(
                              onPressed: busy ? null : () => _resume(job),
                              child: const Text('继续'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _cleanBroken(String directoryPath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('清理损坏的暂存任务'),
            content: const Text('仅删除暂存副本，不会修改原始来源目录或已提交版本。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认清理'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    final directory = Directory(directoryPath);
    if (await directory.exists()) await directory.delete(recursive: true);
    if (mounted) setState(_reload);
  }
}
