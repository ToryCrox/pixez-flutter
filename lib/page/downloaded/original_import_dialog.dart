import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pixez/custom/log.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/original_image.dart';
import 'package:pixez/page/downloaded/widgets/original_mapping_comparison_tile.dart';
import 'package:pixez/store/original_import_service.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

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
  bool _isDraggingDirectory = false;
  final Map<int, Future<String?>> _downloadPathFutures = {};
  List<OriginalImageSet> _existingSets = const [];

  @override
  void dispose() {
    _editionController.dispose();
    _downloadStartController.dispose();
    _originalStartController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _reloadExistingSets();
  }

  Future<void> _reloadExistingSets() async {
    final sets = await downloadStore.originalRepository.getSetsForIllust(
      widget.illust.illustId,
    );
    if (mounted) setState(() => _existingSets = sets);
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
    await _prepareDirectory(selected);
  }

  Future<void> _prepareDirectory(String selected) async {
    final existingSets = await downloadStore.originalRepository
        .getSetsForIllust(widget.illust.illustId);
    var existingSetAction = OriginalExistingSetAction.addVersion;
    if (existingSets.isNotEmpty) {
      final action = await _askExistingSetAction(existingSets);
      if (!mounted || action == null) return;
      if (action == OriginalExistingSetAction.skip) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已跳过，不会修改现有原图')));
        return;
      }
      existingSetAction = action;
      if (action == OriginalExistingSetAction.replaceDefault) {
        final defaultSet = existingSets.firstWhere(
          (set) => set.isDefault,
          orElse: () => existingSets.first,
        );
        _editionController.text = defaultSet.editionName;
      }
    }
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
      final manifest = await downloadStore.originalImportService
          .prepareSingleImport(
            sourceDirectory: selected,
            targetIllustId: widget.illust.illustId,
            editionName: requestedEdition,
            existingSetAction: existingSetAction,
            onProgress: _onProgress,
            isCancelled: () => _cancelRequested,
          );
      if (mounted) {
        setState(() {
          _manifest = manifest;
          // 新增版本时，服务会为重名版本自动生成唯一名称。提交时必须
          // 沿用该名称，否则会将其覆盖回输入的名称并触发唯一索引冲突。
          _editionController.text = manifest.items.single.editionName;
          _existingSets = existingSets;
        });
      }
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

  DropOperation _onDirectoryDropOver(DropOverEvent event) {
    if (_busy ||
        !event.session.items.any((item) => item.canProvide(Formats.fileUri))) {
      return DropOperation.none;
    }
    return DropOperation.copy;
  }

  Future<void> _handleDirectoryDrop(PerformDropEvent event) async {
    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null || !reader.canProvide(Formats.fileUri)) continue;
      reader.getValue<Uri>(Formats.fileUri, (uri) async {
        if (uri == null) return;
        final path = uri.toFilePath();
        if (!await Directory(path).exists()) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('请拖入作品目录，而不是单个文件')));
          }
          return;
        }
        if (mounted) setState(() => _isDraggingDirectory = false);
        await _prepareDirectory(path);
      });
      return;
    }
  }

  Future<String?> _downloadPath(OriginalImportMappingManifest mapping) {
    final part = mapping.downloadedPart;
    if (part == null) return Future<String?>.value();
    return _downloadPathFutures.putIfAbsent(
      part,
      () => downloadStore.getLocalImagePath(
        widget.illust.illustId,
        part,
        update: false,
      ),
    );
  }

  String? _originalPath(
    OriginalImportItemManifest item,
    OriginalImportMappingManifest mapping,
  ) {
    final sourceOrder = mapping.originalSourceOrder;
    if (sourceOrder == null) return null;
    final file = item.files.where((file) => file.sourceOrder == sourceOrder);
    if (file.isEmpty) return null;
    return p.join(item.sourceDirectory, file.first.sourceRelativePath);
  }

  Future<OriginalExistingSetAction?> _askExistingSetAction(
    List<OriginalImageSet> sets,
  ) {
    final defaultSet = sets.firstWhere(
      (set) => set.isDefault,
      orElse: () => sets.first,
    );
    return showDialog<OriginalExistingSetAction>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('该作品已有原图'),
            content: Text(
              '当前默认版为“${defaultSet.editionName}”，共 ${defaultSet.imageCount} 张。请选择本次目录的处理方式。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed:
                    () =>
                        Navigator.pop(context, OriginalExistingSetAction.skip),
                child: const Text('跳过'),
              ),
              OutlinedButton(
                onPressed:
                    () => Navigator.pop(
                      context,
                      OriginalExistingSetAction.replaceDefault,
                    ),
                child: const Text('替换默认版'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.pop(
                      context,
                      OriginalExistingSetAction.addVersion,
                    ),
                child: const Text('新增版本'),
              ),
            ],
          ),
    );
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

  Future<void> _applyEditionName() async {
    final manifest = _manifest;
    if (manifest == null) return;
    final item = manifest.items.single;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final resolvedName =
          item.existingSetId == null
              ? await downloadStore.originalImportService
                  .renamePreparedNewVersion(
                    manifest,
                    item.itemId,
                    _editionController.text,
                  )
              : await downloadStore.originalRepository.renameSet(
                item.existingSetId!,
                _editionController.text,
              );
      item.editionName = resolvedName;
      _editionController.text = resolvedName;
      await downloadStore.originalImportService.writeManifest(manifest);
      await _reloadExistingSets();
    } catch (e, stackTrace) {
      Log.e('修改原图版本名称失败', error: e, stackTrace: stackTrace);
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameExistingSet(OriginalImageSet set) async {
    final controller = TextEditingController(text: set.editionName);
    final name = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('修改版本名称'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: '版本名称'),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('保存'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (!mounted || name == null) return;
    try {
      final resolvedName = await downloadStore.originalRepository.renameSet(
        set.id!,
        name,
      );
      final item = _manifest?.items.single;
      if (item?.existingSetId == set.id) {
        item!.editionName = resolvedName;
        _editionController.text = resolvedName;
        await downloadStore.originalImportService.writeManifest(_manifest!);
      }
      await _reloadExistingSets();
    } catch (e, stackTrace) {
      Log.e('重命名原图版本失败', error: e, stackTrace: stackTrace);
      if (mounted) setState(() => _error = e.toString());
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
      content: DropRegion(
        formats: [Formats.fileUri],
        onDropOver: _onDirectoryDropOver,
        onDropEnter: (_) => setState(() => _isDraggingDirectory = true),
        onDropLeave: (_) => setState(() => _isDraggingDirectory = false),
        onDropEnded: (_) => setState(() => _isDraggingDirectory = false),
        onPerformDrop: _handleDirectoryDrop,
        child: SizedBox(
          width: 760,
          height: 620,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _editionController,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: '版本名称',
                        hintText: '例如：有字版、无字版',
                      ),
                    ),
                  ),
                  if (item != null) ...[
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _busy ? null : _applyEditionName,
                      child: const Text('应用名称'),
                    ),
                  ],
                ],
              ),
              if (_existingSets.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: SizedBox(
                    height: 104,
                    child: ListView.separated(
                      itemCount: _existingSets.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final set = _existingSets[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            set.isDefault ? Icons.star : Icons.collections,
                          ),
                          title: Text(set.editionName),
                          subtitle: Text('${set.imageCount} 张原图'),
                          trailing: IconButton(
                            tooltip: '修改版本名称',
                            onPressed:
                                _busy ? null : () => _renameExistingSet(set),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color:
                        _isDraggingDirectory
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  color:
                      _isDraggingDirectory
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                ),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _selectDirectory,
                      icon: const Icon(Icons.folder_open),
                      label: Text(item == null ? '选择作品目录' : '重新选择目录'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isDraggingDirectory
                            ? '松开以导入此作品目录'
                            : item?.sourceDirectory ?? '尚未选择目录（也可拖入目录）',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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
                        decoration: const InputDecoration(
                          labelText: '下载图从第几张开始',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _originalStartController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '原图从第几张开始',
                        ),
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
                        return OriginalMappingComparisonTile(
                          key: ValueKey(
                            '${mapping.downloadedPart}-${mapping.originalSourceOrder}-$index',
                          ),
                          mapping: mapping,
                          downloadPathFuture: _downloadPath(mapping),
                          originalPath: _originalPath(item, mapping),
                          editable: !_busy,
                          onRemove:
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
                                        item.pageMappings[i].displayOrder = i;
                                      }
                                    });
                                    downloadStore.originalImportService
                                        .writeManifest(_manifest!);
                                  },
                          onRelationChanged: (value) {
                            setState(() {
                              mapping.relationType = value;
                              mapping.manuallyAdjusted = true;
                            });
                            downloadStore.originalImportService.writeManifest(
                              _manifest!,
                            );
                          },
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
