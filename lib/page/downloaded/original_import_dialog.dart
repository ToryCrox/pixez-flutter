import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/original_image.dart';
import 'package:pixez/store/original_import_service.dart';

class OriginalImportDialog extends StatefulWidget {
  final DownloadedIllust illust;

  const OriginalImportDialog({super.key, required this.illust});

  static Future<bool?> show(BuildContext context, DownloadedIllust illust) =>
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => OriginalImportDialog(illust: illust),
      );

  @override
  State<OriginalImportDialog> createState() => _OriginalImportDialogState();
}

class _OriginalImportDialogState extends State<OriginalImportDialog> {
  final _editionController = TextEditingController(text: '默认版');
  final _downloadStartController = TextEditingController(text: '1');
  final _originalStartController = TextEditingController(text: '1');
  OriginalImportManifest? _manifest;
  bool _busy = false;
  String? _error;
  OriginalImportProgress? _progress;
  int _lastProgressUpdate = 0;
  bool _cancelRequested = false;

  @override
  void dispose() {
    _editionController.dispose();
    _downloadStartController.dispose();
    _originalStartController.dispose();
    super.dispose();
  }

  void _applyStarts(OriginalImportItemManifest item) {
    final downloadStart =
        (int.tryParse(_downloadStartController.text) ?? 1)
            .clamp(1, widget.illust.pageCount + 1)
            .toInt() -
        1;
    final originalStart =
        (int.tryParse(_originalStartController.text) ?? 1)
            .clamp(1, item.files.length + 1)
            .toInt() -
        1;
    final downloadCount = widget.illust.pageCount - downloadStart;
    final originalCount = item.files.length - originalStart;
    final count = downloadCount > originalCount ? downloadCount : originalCount;
    item.pageMappings = [
      for (var i = 0; i < count; i++)
        OriginalImportMappingManifest(
          displayOrder: i,
          downloadedPart: i < downloadCount ? downloadStart + i : null,
          originalSourceOrder: i < originalCount ? originalStart + i : null,
          relationType:
              i < downloadCount && i < originalCount
                  ? OriginalRelationType.replacement
                  : i < originalCount
                  ? OriginalRelationType.originalOnly
                  : OriginalRelationType.downloadFallback,
          manuallyAdjusted: true,
        ),
    ];
    downloadStore.originalImportService.writeManifest(_manifest!);
    setState(() {});
  }

  Future<void> _selectDirectory() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择单个作品的原图目录',
      lockParentWindow: true,
    );
    if (selected == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
      _cancelRequested = false;
    });
    try {
      final oldManifest = _manifest;
      if (oldManifest != null) {
        await downloadStore.originalImportService.cancel(oldManifest);
      }
      final requestedEdition =
          _editionController.text.trim().isEmpty
              ? '默认版'
              : _editionController.text.trim();
      final existingSets = await downloadStore.originalRepository
          .getSetsForIllust(widget.illust.illustId);
      final isUpdate = existingSets.any(
        (set) => set.editionName == requestedEdition,
      );
      final manifest = await downloadStore.originalImportService
          .prepareSingleImport(
            sourceDirectory: selected,
            targetIllustId: widget.illust.illustId,
            editionName: requestedEdition,
            mode:
                isUpdate
                    ? OriginalImportMode.update
                    : OriginalImportMode.single,
            onProgress: _onProgress,
            isCancelled: () => _cancelRequested,
          );
      if (mounted) setState(() => _manifest = manifest);
    } catch (e, stackTrace) {
      if (_cancelRequested) {
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      Log.e('准备原图导入失败', error: e, stackTrace: stackTrace);
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final manifest = _manifest;
    if (manifest == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
      _cancelRequested = false;
    });
    try {
      final item = manifest.items.single;
      item.editionName =
          _editionController.text.trim().isEmpty
              ? item.editionName
              : _editionController.text.trim();
      await downloadStore.originalImportService.writeManifest(manifest);
      await downloadStore.originalImportService.execute(
        manifest,
        onProgress: _onProgress,
        isCancelled: () => _cancelRequested,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e, stackTrace) {
      if (_cancelRequested) {
        await downloadStore.originalImportService.cancel(manifest);
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      Log.e('提交原图导入失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  void _onProgress(OriginalImportProgress progress) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!mounted ||
        (now - _lastProgressUpdate < 100 &&
            progress.copiedBytes < progress.totalBytes)) {
      return;
    }
    _lastProgressUpdate = now;
    setState(() => _progress = progress);
  }

  Future<void> _cancel() async {
    if (_busy) {
      setState(() => _cancelRequested = true);
      return;
    }
    final manifest = _manifest;
    if (manifest != null) {
      await downloadStore.originalImportService.cancel(manifest);
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final item = _manifest?.items.single;
    return AlertDialog(
      title: Text('导入原图 · ${widget.illust.title}'),
      content: SizedBox(
        width: 760,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _editionController,
              enabled: !_busy && item == null,
              decoration: const InputDecoration(
                labelText: '版本名称',
                hintText: '例如：有字版、无字版',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _selectDirectory,
                  icon: const Icon(Icons.folder_open),
                  label: Text(item == null ? '选择作品目录' : '重新选择目录'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item?.sourceDirectory ?? '尚未选择目录',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress?.fraction),
              const SizedBox(height: 8),
              Text(
                _progress == null
                    ? '正在扫描、计算哈希并生成页面对应关系…'
                    : _progress!.description,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (item != null) ...[
              const SizedBox(height: 16),
              Text(
                '下载 ${widget.illust.downloadedImageCount} · 原图 ${item.files.length} · 增强 ${item.pageMappings.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _downloadStartController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '下载图从第几张开始'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _originalStartController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '原图从第几张开始'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _applyStarts(item),
                    child: const Text('按起点重排'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: true,
                    itemCount: item.pageMappings.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final mapping = item.pageMappings.removeAt(oldIndex);
                        item.pageMappings.insert(newIndex, mapping);
                        for (var i = 0; i < item.pageMappings.length; i++) {
                          item.pageMappings[i]
                            ..displayOrder = i
                            ..manuallyAdjusted = true;
                        }
                      });
                    },
                    itemBuilder: (_, index) {
                      final mapping = item.pageMappings[index];
                      return ListTile(
                        key: ValueKey(
                          '${mapping.downloadedPart}-${mapping.originalSourceOrder}-$index',
                        ),
                        leading: Text('${index + 1}'),
                        title: Text(
                          '下载 ${mapping.downloadedPart == null ? "—" : mapping.downloadedPart! + 1}  ↔  原图 ${mapping.originalSourceOrder == null ? "—" : mapping.originalSourceOrder! + 1}',
                        ),
                        subtitle: Text(mapping.relationType.value),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '忽略此显示页',
                              onPressed:
                                  _busy
                                      ? null
                                      : () {
                                        setState(() {
                                          item.pageMappings.removeAt(index);
                                          for (
                                            var i = 0;
                                            i < item.pageMappings.length;
                                            i++
                                          ) {
                                            item.pageMappings[i].displayOrder =
                                                i;
                                          }
                                        });
                                      },
                              icon: const Icon(Icons.visibility_off_outlined),
                            ),
                            DropdownButton<OriginalRelationType>(
                              value: mapping.relationType,
                              onChanged:
                                  _busy
                                      ? null
                                      : (value) {
                                        if (value == null) return;
                                        setState(() {
                                          mapping.relationType = value;
                                          mapping.manuallyAdjusted = true;
                                        });
                                      },
                              items: const [
                                DropdownMenuItem(
                                  value: OriginalRelationType.replacement,
                                  child: Text('原图替换'),
                                ),
                                DropdownMenuItem(
                                  value: OriginalRelationType.originalOnly,
                                  child: Text('原图新增'),
                                ),
                                DropdownMenuItem(
                                  value: OriginalRelationType.downloadFallback,
                                  child: Text('下载补位'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const Text('可拖动调整显示顺序；修改后的对应关系会写入暂存 Manifest。'),
            ] else
              const Expanded(child: Center(child: Text('选择目录后可预览每张图片的对应关系'))),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancelRequested ? null : _cancel,
          child: Text(_cancelRequested ? '正在取消…' : '取消'),
        ),
        FilledButton(
          onPressed: _busy || _manifest == null ? null : _commit,
          child: const Text('复制并导入'),
        ),
      ],
    );
  }
}
