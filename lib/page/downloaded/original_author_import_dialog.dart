import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pixez/custom/log.dart';
import 'package:pixez/ai/ai_client.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/original_image.dart';
import 'package:pixez/store/original_import_service.dart';

class OriginalAuthorImportDialog extends StatefulWidget {
  final int userId;
  final String userName;

  const OriginalAuthorImportDialog({
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
    barrierDismissible: false,
    builder:
        (_) => OriginalAuthorImportDialog(userId: userId, userName: userName),
  );

  @override
  State<OriginalAuthorImportDialog> createState() =>
      _OriginalAuthorImportDialogState();
}

class _AuthorImportRow {
  final String directory;
  int? targetIllustId;
  bool selected;
  String confidence;

  _AuthorImportRow({
    required this.directory,
    this.targetIllustId,
    this.selected = true,
    required this.confidence,
  });
}

class _OriginalAuthorImportDialogState
    extends State<OriginalAuthorImportDialog> {
  String? _root;
  List<DownloadedIllust> _works = [];
  Map<int, DownloadedIllust> _worksById = {};
  List<_AuthorImportRow> _rows = [];
  OriginalImportManifest? _manifest;
  bool _busy = false;
  String? _committingItemId;
  String? _error;
  OriginalImportProgress? _progress;
  int _lastProgressUpdate = 0;
  bool _cancelRequested = false;
  final ScrollController _matchScrollController = ScrollController();
  final ScrollController _previewScrollController = ScrollController();
  final Set<String> _expandedItemIds = <String>{};
  final Map<String, ScrollController> _mappingScrollControllers = {};

  @override
  void dispose() {
    _matchScrollController.dispose();
    _previewScrollController.dispose();
    for (final controller in _mappingScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _selectRoot() async {
    final root = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择作者原图根目录',
      lockParentWindow: true,
    );
    if (root == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _manifest = null;
      _progress = null;
      _cancelRequested = false;
    });
    try {
      final results = await Future.wait([
        downloadStore.originalImportService.discoverAuthorWorkDirectories(root),
        downloadStore.getDownloadedByUser(
          widget.userId,
          limit: null,
          offset: 0,
        ),
      ]);
      final directories = results[0] as List<FileSystemEntity>;
      final works = results[1] as List<DownloadedIllust>;
      final rows = <_AuthorImportRow>[];
      for (final directory in directories) {
        final match = _matchDirectory(directory.path, works);
        rows.add(
          _AuthorImportRow(
            directory: directory.path,
            targetIllustId: match.$1?.illustId,
            selected: match.$1 != null,
            confidence: match.$2,
          ),
        );
      }
      await _applyAiMatches(rows, works);
      if (_cancelRequested) {
        if (mounted) Navigator.pop(context, false);
        return;
      }
      if (mounted) {
        setState(() {
          _root = root;
          _works = works;
          _worksById = {for (final work in works) work.illustId: work};
          _rows = rows;
        });
      }
    } catch (e, stackTrace) {
      Log.e('扫描作者原图目录失败', error: e, stackTrace: stackTrace);
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyAiMatches(
    List<_AuthorImportRow> rows,
    List<DownloadedIllust> works,
  ) async {
    if (aiSettings.providers.isEmpty) return;
    final unmatched = rows.where((row) => row.targetIllustId == null).toList();
    if (unmatched.isEmpty) return;
    final validIds = works.map((work) => work.illustId).toSet();
    for (var offset = 0; offset < unmatched.length; offset += 20) {
      if (_cancelRequested) return;
      final batch = unmatched.skip(offset).take(20).toList();
      final payload = [
        for (final row in batch)
          {
            'directory': p.basename(row.directory),
            'date': _parseFolderDate(row.directory)?.toIso8601String(),
            'candidates': [
              for (final work in _candidateWorks(row.directory, works))
                {
                  'id': work.illustId,
                  'title': work.title,
                  'date': work.createDate,
                  'pages': work.pageCount,
                },
            ],
          },
      ];
      try {
        final response = await aiClient.complete(
          aiSettings.providers.first,
          AiCompletionInput(
            systemPrompt:
                '根据目录名和日期，从各自 candidates 中选择同一作品。只返回 JSON 数组，元素格式 {"directory":"原值","illust_id":整数或null}。不得返回候选外 ID。',
            userPrompt: jsonEncode(payload),
          ),
        );
        final cleaned = response
            .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
            .replaceFirst(RegExp(r'\s*```$'), '');
        final decoded = jsonDecode(cleaned);
        if (decoded is! List) continue;
        for (final result in decoded.whereType<Map>()) {
          final directory = result['directory'];
          final id = result['illust_id'];
          if (directory is! String || id is! int || !validIds.contains(id)) {
            continue;
          }
          _AuthorImportRow? row;
          for (final item in batch) {
            if (p.basename(item.directory) == directory) {
              row = item;
              break;
            }
          }
          final candidateIds =
              _candidateWorks(
                row?.directory ?? '',
                works,
              ).map((work) => work.illustId).toSet();
          if (row != null && candidateIds.contains(id)) {
            row.targetIllustId = id;
            row.selected = true;
            row.confidence = 'AI';
          }
        }
      } catch (e) {
        Log.w('AI 原图目录匹配失败，回退人工确认: $e');
      }
    }
  }

  List<DownloadedIllust> _candidateWorks(
    String directory,
    List<DownloadedIllust> works,
  ) {
    final date = _parseFolderDate(directory);
    if (date == null) return works.take(12).toList();
    final candidates =
        works.where((work) {
          final workDate = DateTime.tryParse(work.createDate)?.toLocal();
          return workDate != null &&
              date.difference(workDate).inDays.abs() <= 10;
        }).toList();
    return candidates.isEmpty ? works.take(12).toList() : candidates;
  }

  (DownloadedIllust?, String) _matchDirectory(
    String directory,
    List<DownloadedIllust> works,
  ) {
    final folder = p.basename(directory);
    final normalizedFolder = _normalize(folder);
    final sourceDate = _parseFolderDate(directory);
    DownloadedIllust? best;
    var bestScore = -1;
    var tied = false;
    for (final work in works) {
      var score = 0;
      final title = _normalize(work.title);
      if (title.isNotEmpty && normalizedFolder.contains(title)) score += 80;
      final date = DateTime.tryParse(work.createDate);
      if (sourceDate != null && date != null) {
        final days = sourceDate.difference(date.toLocal()).inDays.abs();
        if (days <= 10) score += 40 - days * 3;
      }
      if (score > bestScore) {
        best = work;
        bestScore = score;
        tied = false;
      } else if (score == bestScore) {
        tied = true;
      }
    }
    if (bestScore < 20 || tied) return (null, '需人工确认');
    return (best, bestScore >= 70 ? '高' : '中');
  }

  DateTime? _parseFolderDate(String directory) {
    final parentMatch = RegExp(
      r'(20\d{2})[.\-_年](\d{1,2})',
    ).firstMatch(p.basename(p.dirname(directory)));
    final dayMatch = RegExp(
      r'(\d{1,2})[-_.月](\d{1,2})',
    ).firstMatch(p.basename(directory));
    if (parentMatch == null || dayMatch == null) return null;
    final year = int.parse(parentMatch.group(1)!);
    final month = int.parse(dayMatch.group(1)!);
    final day = int.parse(dayMatch.group(2)!);
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  String _normalize(String text) => text.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9\u3040-\u30ff\u3400-\u9fff]+'),
    '',
  );

  Future<void> _selectWorkForRow(_AuthorImportRow row) async {
    final selected = await showDialog<int>(
      context: context,
      builder:
          (_) => _OriginalWorkPickerDialog(
            works: _works,
            selectedIllustId: row.targetIllustId,
          ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      row.targetIllustId = selected == 0 ? null : selected;
      row.selected = row.targetIllustId != null;
      if (row.targetIllustId == null) row.confidence = '需人工确认';
    });
  }

  Future<void> _preparePreview() async {
    final root = _root;
    if (root == null) return;
    final selections = [
      for (final row in _rows)
        if (row.selected && row.targetIllustId != null)
          OriginalAuthorImportSelection(
            sourceDirectory: row.directory,
            targetIllustId: row.targetIllustId!,
          ),
    ];
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
      _cancelRequested = false;
    });
    try {
      final manifest = await downloadStore.originalImportService
          .prepareAuthorImport(
            sourceRoot: root,
            selections: selections,
            onProgress: _onProgress,
            isCancelled: () => _cancelRequested,
          );
      if (mounted) setState(() => _manifest = manifest);
    } catch (e, stackTrace) {
      if (_cancelRequested) {
        if (mounted) Navigator.pop(context, false);
        return;
      }
      Log.e('生成作者导入预览失败', error: e, stackTrace: stackTrace);
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
      _progress = null;
      _cancelRequested = false;
    });
    try {
      await downloadStore.originalImportService.execute(
        manifest,
        onProgress: _onProgress,
        isCancelled: () => _cancelRequested,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e, stackTrace) {
      if (_cancelRequested) {
        await downloadStore.originalImportService.cancel(manifest);
        if (mounted) Navigator.pop(context, false);
        return;
      }
      Log.e('批量导入原图失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _commitItem(OriginalImportItemManifest item) async {
    final manifest = _manifest;
    if (manifest == null) return;
    setState(() {
      _committingItemId = item.itemId;
      _progress = null;
      _cancelRequested = false;
    });
    try {
      await downloadStore.originalImportService.executeItem(
        manifest,
        item.itemId,
        onProgress: _onProgress,
        isCancelled: () => _cancelRequested,
      );
      if (!mounted) return;
      if (manifest.status == OriginalImportJobStatus.completed) {
        Navigator.pop(context, true);
      } else {
        setState(() => _committingItemId = null);
      }
    } catch (e, stackTrace) {
      if (_cancelRequested) {
        await downloadStore.originalImportService.cancel(manifest);
        if (mounted) Navigator.pop(context, false);
        return;
      }
      Log.e('单项导入失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _committingItemId = null;
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

  Future<void> _close() async {
    if (_busy || _committingItemId != null) {
      setState(() => _cancelRequested = true);
      return;
    }
    if (_manifest != null) {
      await downloadStore.originalImportService.cancel(_manifest!);
    }
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final contentWidth = (screenSize.width - 96).clamp(360.0, 900.0);
    final contentHeight = (screenSize.height - 190).clamp(360.0, 680.0);
    return AlertDialog(
      title: Text('批量导入原图 · ${widget.userName}'),
      content: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: const {
            PointerDeviceKind.mouse,
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
            PointerDeviceKind.trackpad,
          },
        ),
        child: SizedBox(
          width: contentWidth,
          height: contentHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _selectRoot,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择作者目录'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_root ?? '尚未选择')),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progress?.fraction),
                Text(
                  _progress == null
                      ? '正在分析目录或计算图片哈希，请稍候…'
                      : '正在复制 ${(100 * _progress!.fraction).toStringAsFixed(1)}%',
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Expanded(
                child:
                    _manifest == null
                        ? _buildMatchList()
                        : _buildManifestPreview(_manifest!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancelRequested ? null : _close,
          child: Text(_cancelRequested ? '正在取消…' : '取消'),
        ),
        if (_manifest == null)
          FilledButton(
            onPressed:
                _busy ||
                        !_rows.any(
                          (row) => row.selected && row.targetIllustId != null,
                        )
                    ? null
                    : _preparePreview,
            child: const Text('生成详细预览'),
          )
        else
          FilledButton(
            onPressed: _busy ? null : _commit,
            child: Text('导入 ${_manifest!.items.length} 个作品'),
          ),
      ],
    );
  }

  Widget _buildMatchList() {
    if (_rows.isEmpty) return const Center(child: Text('选择作者目录后开始匹配'));
    return Scrollbar(
      controller: _matchScrollController,
      thumbVisibility: true,
      interactive: true,
      child: ListView.builder(
        controller: _matchScrollController,
        itemCount: _rows.length,
        itemExtent: 92,
        cacheExtent: 276,
        addAutomaticKeepAlives: false,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemBuilder: (_, index) {
          final row = _rows[index];
          final work = _worksById[row.targetIllustId];
          final workLabel =
              work == null
                  ? '选择匹配作品 · ${row.confidence}'
                  : '${work.createDate.split('T').first} · ${work.title}';
          return CheckboxListTile(
            key: ValueKey(row.directory),
            value: row.selected,
            onChanged:
                row.targetIllustId == null
                    ? null
                    : (value) => setState(() => row.selected = value ?? false),
            title: Text(
              p.basename(row.directory),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: InkWell(
              onTap: _busy ? null : () => _selectWorkForRow(row),
              child: SizedBox(
                height: 38,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        workLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              work == null
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            secondary: Chip(label: Text(row.confidence)),
          );
        },
      ),
    );
  }

  Widget _buildManifestPreview(OriginalImportManifest manifest) {
    return Scrollbar(
      controller: _previewScrollController,
      thumbVisibility: true,
      interactive: true,
      child: ListView.builder(
        controller: _previewScrollController,
        itemCount: manifest.items.length + 1,
        cacheExtent: 300,
        itemBuilder: (_, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('已生成 ${manifest.items.length} 个独立提交项，可展开检查对应关系。'),
            );
          }
          final item = manifest.items[index - 1];
          final expanded = _expandedItemIds.contains(item.itemId);
          return ExpansionTile(
            key: PageStorageKey(item.itemId),
            initiallyExpanded: expanded,
            onExpansionChanged: (value) {
              setState(() {
                if (value) {
                  _expandedItemIds.add(item.itemId);
                } else {
                  _expandedItemIds.remove(item.itemId);
                }
              });
            },
            title: Text(
              p.basename(item.sourceDirectory),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '原图 ${item.files.length} · 增强 ${item.pageMappings.length} · 作品 ${item.targetIllustId}',
            ),
            children:
                expanded ? [_buildManifestItem(manifest, item)] : const [],
          );
        },
      ),
    );
  }

  Widget _buildManifestItem(
    OriginalImportManifest manifest,
    OriginalImportItemManifest item,
  ) {
    final controller = _mappingScrollControllers.putIfAbsent(
      item.itemId,
      ScrollController.new,
    );
    final mappingHeight =
        (item.pageMappings.length * 52.0).clamp(52.0, 380.0).toDouble();
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 4),
            child: FilledButton.tonalIcon(
              onPressed:
                  _committingItemId == null &&
                          item.state != OriginalImportItemState.committed
                      ? () => _commitItem(item)
                      : null,
              icon:
                  _committingItemId == item.itemId
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.download_done),
              label: Text(
                item.state == OriginalImportItemState.committed
                    ? '已导入'
                    : '仅导入此作品',
              ),
            ),
          ),
        ),
        SizedBox(
          height: mappingHeight,
          child: Scrollbar(
            controller: controller,
            thumbVisibility: item.pageMappings.length > 7,
            interactive: true,
            child: ListView.builder(
              controller: controller,
              itemCount: item.pageMappings.length,
              itemExtent: 52,
              cacheExtent: 156,
              itemBuilder: (_, index) {
                final mapping = item.pageMappings[index];
                return ListTile(
                  dense: true,
                  leading: Text('${mapping.displayOrder + 1}'),
                  title: Text(
                    '下载 ${mapping.downloadedPart == null ? "—" : mapping.downloadedPart! + 1} ↔ 原图 ${mapping.originalSourceOrder == null ? "—" : mapping.originalSourceOrder! + 1}',
                  ),
                  trailing: DropdownButton<OriginalRelationType>(
                    value: mapping.relationType,
                    onChanged:
                        item.state == OriginalImportItemState.committed ||
                                _committingItemId != null
                            ? null
                            : (value) {
                              if (value == null) return;
                              setState(() {
                                mapping.relationType = value;
                                mapping.manuallyAdjusted = true;
                              });
                              downloadStore.originalImportService.writeManifest(
                                manifest,
                              );
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
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _OriginalWorkPickerDialog extends StatefulWidget {
  final List<DownloadedIllust> works;
  final int? selectedIllustId;

  const _OriginalWorkPickerDialog({
    required this.works,
    required this.selectedIllustId,
  });

  @override
  State<_OriginalWorkPickerDialog> createState() =>
      _OriginalWorkPickerDialogState();
}

class _OriginalWorkPickerDialogState extends State<_OriginalWorkPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered =
        normalizedQuery.isEmpty
            ? widget.works
            : widget.works.where((work) {
              return work.illustId.toString().contains(normalizedQuery) ||
                  work.title.toLowerCase().contains(normalizedQuery) ||
                  work.createDate.toLowerCase().contains(normalizedQuery);
            }).toList();

    final screenSize = MediaQuery.sizeOf(context);
    final contentWidth = (screenSize.width - 96).clamp(360.0, 720.0);
    final contentHeight = (screenSize.height - 190).clamp(320.0, 560.0);
    return AlertDialog(
      title: const Text('选择匹配作品'),
      content: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: const {
            PointerDeviceKind.mouse,
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
            PointerDeviceKind.trackpad,
          },
        ),
        child: SizedBox(
          width: contentWidth,
          height: contentHeight,
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索作品 ID、标题或日期',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child:
                    filtered.isEmpty
                        ? const Center(child: Text('没有匹配的作品'))
                        : Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          interactive: true,
                          child: ListView.builder(
                            controller: _scrollController,
                            itemCount: filtered.length,
                            itemExtent: 64,
                            cacheExtent: 256,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemBuilder: (_, index) {
                              final work = filtered[index];
                              final selected =
                                  work.illustId == widget.selectedIllustId;
                              return ListTile(
                                selected: selected,
                                leading: SizedBox(
                                  width: 88,
                                  child: Text(work.createDate.split('T').first),
                                ),
                                title: Text(
                                  work.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  'ID ${work.illustId} · ${work.pageCount} 页',
                                ),
                                trailing:
                                    selected ? const Icon(Icons.check) : null,
                                onTap:
                                    () => Navigator.pop(context, work.illustId),
                              );
                            },
                          ),
                        ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 0),
          child: const Text('清除匹配'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
