import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pixez/custom/log.dart';
import 'package:pixez/ai/ai_client.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/original_image.dart';
import 'package:pixez/page/downloaded/local_image_viewer_page.dart';
import 'package:pixez/page/picture/illust_lighting_page.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/store/original_import_service.dart';
import 'package:pixez/utils/file_utils.dart';

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
  final Map<String, Future<String?>> _sourceCoverFutures = {};
  final Map<String, Future<int>> _sourceImageCountFutures = {};
  final Map<int, Future<String?>> _downloadCoverFutures = {};
  final Map<String, Future<String?>> _mappingDownloadPathFutures = {};
  final TextEditingController _batchSizeController = TextEditingController(
    text: '20',
  );
  int _batchSize = 20;
  bool _hasMoreDirectories = false;
  int _currentDirectoryCount = 0;

  List<OriginalImportItemManifest> get _remainingItems =>
      _manifest?.items
          .where((item) => item.state != OriginalImportItemState.committed)
          .toList() ??
      const [];

  int get _nextBatchCount {
    final remaining = _remainingItems.length;
    return remaining < _batchSize ? remaining : _batchSize;
  }

  @override
  void dispose() {
    _matchScrollController.dispose();
    _previewScrollController.dispose();
    _batchSizeController.dispose();
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
      final recoverable = await downloadStore.originalImportService
          .findRecoverableAuthorJob(sourceRoot: root, userId: widget.userId);
      if (recoverable != null) {
        if (mounted) {
          setState(() {
            _root = root;
            _manifest = recoverable;
            _rows = [];
            _hasMoreDirectories = false;
            _currentDirectoryCount = recoverable.items.length;
          });
        }
        return;
      }
      final results = await Future.wait([
        downloadStore.originalImportService.discoverNextAuthorDirectoryBatch(
          authorRoot: root,
          userId: widget.userId,
          limit: _batchSize,
        ),
        downloadStore.getDownloadedByUser(
          widget.userId,
          limit: null,
          offset: 0,
        ),
      ]);
      final directoryBatch = results[0] as OriginalAuthorDirectoryBatch;
      final works = results[1] as List<DownloadedIllust>;
      final directories = directoryBatch.directories;
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
          _hasMoreDirectories = directoryBatch.hasMore;
          _currentDirectoryCount = directories.length;
          if (directories.isEmpty) {
            _error = '该作者目录中没有尚未导入的作品';
          }
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

  Future<String?> _getSourceCoverPath(String directory) =>
      _sourceCoverFutures.putIfAbsent(
        directory,
        () => downloadStore.originalImportService.getFirstImagePath(directory),
      );

  Future<int> _getSourceImageCount(String directory) =>
      _sourceImageCountFutures.putIfAbsent(
        directory,
        () => downloadStore.originalImportService.getImageCount(directory),
      );

  Future<String?> _getDownloadCoverPath(DownloadedIllust work) =>
      _downloadCoverFutures.putIfAbsent(
        work.illustId,
        () => _resolveDownloadedCoverPath(work),
      );

  Future<void> _openDirectory(String directory) async {
    try {
      await FileUtils.openFileOrDirectory(directory);
    } catch (e, stackTrace) {
      Log.e('打开原图目录失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开目录失败：$e')));
      }
    }
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('路径已复制到剪贴板')));
    }
  }

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
    final batch = _remainingItems.take(_batchSize).toList();
    if (batch.isEmpty) return;
    setState(() {
      _busy = true;
      _progress = null;
      _cancelRequested = false;
      _error = null;
    });
    try {
      for (final item in batch) {
        if (_cancelRequested) break;
        if (mounted) setState(() => _committingItemId = item.itemId);
        await downloadStore.originalImportService.executeItem(
          manifest,
          item.itemId,
          onProgress: _onProgress,
          isCancelled: () => _cancelRequested,
        );
      }
      if (_cancelRequested) {
        await downloadStore.originalImportService.writeManifest(manifest);
        if (mounted) Navigator.pop(context, false);
        return;
      }
      if (!mounted) return;
      if (manifest.status == OriginalImportJobStatus.completed) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _busy = false;
          _committingItemId = null;
          _progress = null;
        });
      }
    } catch (e, stackTrace) {
      if (_cancelRequested) {
        if (mounted) Navigator.pop(context, false);
        return;
      }
      Log.e('批量导入原图失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _busy = false;
          _committingItemId = null;
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
      await downloadStore.originalImportService.writeManifest(_manifest!);
    }
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _discardTask() async {
    final manifest = _manifest;
    if (manifest == null || _busy || _committingItemId != null) return;
    final committed =
        manifest.items
            .where((item) => item.state == OriginalImportItemState.committed)
            .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('放弃剩余导入任务'),
            content: Text(
              committed == 0
                  ? '将删除此任务的 Manifest 和暂存文件，来源目录不会改变。'
                  : '已完成的 $committed 个作品会保留；将清理其余任务和暂存文件。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('返回'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认放弃'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await downloadStore.originalImportService.cancel(manifest);
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _returnToWorkSelection() async {
    final manifest = _manifest;
    if (manifest == null || _busy || _committingItemId != null) return;
    if (manifest.items.any(
      (item) => item.state == OriginalImportItemState.committed,
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已有作品完成导入，不能返回重新选择；可继续导入或放弃剩余任务')),
        );
      }
      return;
    }
    final rows = <_AuthorImportRow>[];
    for (final item in manifest.items) {
      rows.add(
        _AuthorImportRow(
          directory: item.sourceDirectory,
          targetIllustId: item.targetIllustId,
          selected: true,
          confidence: '预览中',
        ),
      );
    }
    if (_works.isEmpty) {
      final works = await downloadStore.getDownloadedByUser(
        widget.userId,
        limit: null,
        offset: 0,
      );
      if (!mounted) return;
      _works = works;
      _worksById = {for (final work in works) work.illustId: work};
    }
    await downloadStore.originalImportService.cancel(manifest);
    if (!mounted) return;
    setState(() {
      _manifest = null;
      _rows = rows;
      _expandedItemIds.clear();
      _error = null;
      _progress = null;
    });
  }

  Future<void> _openIllustDetail(int illustId) async {
    var work = _worksById[illustId];
    work ??= await downloadStore.getDownloadedIllust(illustId);
    if (!mounted) return;
    if (work == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未找到对应插画记录')));
      return;
    }
    final store = IllustStore(work.illustId, work.toIllusts());
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder:
            (_) => IllustLightingPage(
              id: work!.illustId,
              store: store,
              heroString: 'original_import_illust_${work.illustId}',
            ),
      ),
    );
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
                  const SizedBox(width: 10),
                  const Text('每批处理'),
                  const SizedBox(width: 6),
                  _buildBatchSizeField(),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_root ?? '尚未选择')),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progress?.fraction),
                Text(
                  _progress == null
                      ? '正在读取文件名并按顺序生成初步映射…'
                      : _progress!.description,
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
        if (_manifest != null)
          TextButton(
            onPressed:
                _busy || _committingItemId != null
                    ? null
                    : _returnToWorkSelection,
            child: const Text('重新选择作品'),
          ),
        if (_manifest != null)
          TextButton(
            onPressed: _busy || _committingItemId != null ? null : _discardTask,
            child: const Text('放弃任务'),
          ),
        TextButton(
          onPressed: _cancelRequested ? null : _close,
          child: Text(
            _cancelRequested
                ? '正在暂停…'
                : (_manifest == null ? '取消' : '暂不导入（稍后继续）'),
          ),
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
            onPressed:
                _busy || _committingItemId != null || _nextBatchCount == 0
                    ? null
                    : _commit,
            child: Text('导入接下来 $_nextBatchCount 个作品'),
          ),
      ],
    );
  }

  Widget _buildMatchList() {
    if (_rows.isEmpty) return const Center(child: Text('选择作者目录后开始匹配'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '本批只匹配 $_currentDirectoryCount 个${_hasMoreDirectories ? "，目录中还有后续作品" : ""}；完成后重新选择同一目录继续下一批。',
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('详细预览只根据文件名和顺序生成初步映射，不读取图片内容；请展开后人工检查和修正。')),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _matchScrollController,
            thumbVisibility: true,
            interactive: true,
            child: ListView.builder(
              controller: _matchScrollController,
              itemCount: _rows.length,
              itemExtent: 152,
              cacheExtent: 456,
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  value: row.selected,
                  onChanged:
                      row.targetIllustId == null
                          ? null
                          : (value) =>
                              setState(() => row.selected = value ?? false),
                  title: Text('', style: const TextStyle(fontSize: 0)),
                  subtitle: InkWell(
                    onTap: _busy ? null : () => _selectWorkForRow(row),
                    child: SizedBox(
                      height: 136,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.basename(row.directory),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Tooltip(
                                message: '打开原图目录',
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed:
                                      _busy
                                          ? null
                                          : () => _openDirectory(row.directory),
                                  icon: const Icon(Icons.folder_open_outlined),
                                ),
                              ),
                              Tooltip(
                                message: '复制原图目录路径',
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed:
                                      _busy
                                          ? null
                                          : () => _copyPath(row.directory),
                                  icon: const Icon(Icons.content_copy),
                                ),
                              ),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(row.confidence),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Row(
                              children: [
                                if (work != null) ...[
                                  _LocalCover(
                                    pathFuture: _getDownloadCoverPath(work),
                                    width: 64,
                                    height: 64,
                                    icon: Icons.image_outlined,
                                    title: work.title,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
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
                                      FutureBuilder<int>(
                                        future: _getSourceImageCount(
                                          row.directory,
                                        ),
                                        builder:
                                            (_, snapshot) => Text(
                                              '原图 ${snapshot.hasData ? snapshot.data : "…"} · 下载图 ${work?.downloadedImageCount ?? "—"}',
                                              style:
                                                  Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (work != null)
                                  Tooltip(
                                    message: '查看插画详情',
                                    child: IconButton(
                                      visualDensity: VisualDensity.compact,
                                      onPressed:
                                          () =>
                                              _openIllustDetail(work.illustId),
                                      icon: const Icon(Icons.open_in_new),
                                    ),
                                  ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  secondary: _LocalCover(
                    pathFuture: _getSourceCoverPath(row.directory),
                    width: 112,
                    height: 132,
                    icon: Icons.photo_outlined,
                    title: p.basename(row.directory),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBatchSizeField() {
    return SizedBox(
      width: 72,
      child: TextField(
        controller: _batchSizeController,
        enabled:
            !_busy &&
            _committingItemId == null &&
            (_root == null || _manifest != null),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          isDense: true,
          suffixText: '个',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) {
          final parsed = int.tryParse(value);
          if (parsed == null || parsed < 1) return;
          setState(() => _batchSize = parsed);
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
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '共 ${manifest.items.length} 个 · 已完成 ${manifest.items.length - _remainingItems.length} 个 · 剩余 ${_remainingItems.length} 个',
                  ),
                  Text('当前每批最多导入 $_batchSize 个，可展开检查或单独导入。'),
                ],
              ),
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
            leading: _LocalCover(
              pathFuture: _getSourceCoverPath(item.sourceDirectory),
              width: 60,
              height: 72,
              icon: Icons.photo_outlined,
              title: p.basename(item.sourceDirectory),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    p.basename(item.sourceDirectory),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Tooltip(
                  message: '打开原图目录',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openDirectory(item.sourceDirectory),
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ),
                Tooltip(
                  message: '复制原图目录路径',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _copyPath(item.sourceDirectory),
                    icon: const Icon(Icons.content_copy),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '下载图 ${_downloadedPageCount(item)} · 原图 ${item.files.length} · 显示 ${item.pageMappings.length} · ID ${item.targetIllustId}',
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
    final previewMappings = item.pageMappings.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openIllustDetail(item.targetIllustId),
                icon: const Icon(Icons.open_in_new),
                label: const Text('查看插画详情'),
              ),
              OutlinedButton.icon(
                onPressed:
                    item.pageMappings.isEmpty
                        ? null
                        : () => _showPageMappings(manifest, item),
                icon: const Icon(Icons.view_list_outlined),
                label: Text('查看全部 ${item.pageMappings.length} 页映射'),
              ),
              FilledButton.tonalIcon(
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
            ],
          ),
        ),
        const Divider(height: 1),
        for (final mapping in previewMappings)
          _buildMappingTile(manifest, item, mapping),
        if (item.pageMappings.length > previewMappings.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Text(
              '这里只显示前 ${previewMappings.length} 条，剩余 ${item.pageMappings.length - previewMappings.length} 条请在全部映射中查看。',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildMappingTile(
    OriginalImportManifest manifest,
    OriginalImportItemManifest item,
    OriginalImportMappingManifest mapping,
  ) {
    final editable =
        item.state != OriginalImportItemState.committed &&
        _committingItemId == null;
    return _MappingComparisonTile(
      mapping: mapping,
      downloadPathFuture: _getMappingDownloadPath(item, mapping),
      originalPath: _getMappingOriginalPath(item, mapping),
      editable: editable,
      onEditDownloaded:
          editable
              ? () => _editMappingPage(manifest, item, mapping, true)
              : null,
      onEditOriginal:
          editable
              ? () => _editMappingPage(manifest, item, mapping, false)
              : null,
      onRelationChanged: (value) {
        setState(() {
          mapping.relationType = value;
          mapping.manuallyAdjusted = true;
        });
        downloadStore.originalImportService.writeManifest(manifest);
      },
    );
  }

  Future<void> _editMappingPage(
    OriginalImportManifest manifest,
    OriginalImportItemManifest item,
    OriginalImportMappingManifest mapping,
    bool downloaded,
  ) async {
    final count = downloaded ? _downloadedPageCount(item) : item.files.length;
    final current =
        downloaded ? mapping.downloadedPart : mapping.originalSourceOrder;
    final selected = await showDialog<int>(
      context: context,
      builder:
          (_) => _PageIndexPickerDialog(
            title: downloaded ? '选择下载图' : '选择原图',
            pageCount: count,
            selectedIndex: current,
          ),
    );
    if (!mounted || selected == null) return;
    final value = selected < 0 ? null : selected;
    if (value == null &&
        (downloaded
            ? mapping.originalSourceOrder == null
            : mapping.downloadedPart == null)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('一条映射不能同时没有下载图和原图')));
      return;
    }
    setState(() {
      if (downloaded) {
        mapping.downloadedPart = value;
      } else {
        mapping.originalSourceOrder = value;
      }
      _normalizeMappingRelation(mapping);
      mapping.manuallyAdjusted = true;
    });
    await downloadStore.originalImportService.writeManifest(manifest);
  }

  Future<String?> _getMappingDownloadPath(
    OriginalImportItemManifest item,
    OriginalImportMappingManifest mapping,
  ) {
    final part = mapping.downloadedPart;
    if (part == null) return Future<String?>.value();
    final key = '${item.targetIllustId}:$part';
    return _mappingDownloadPathFutures.putIfAbsent(
      key,
      () => downloadStore.getLocalImagePath(
        item.targetIllustId,
        part,
        update: false,
      ),
    );
  }

  String? _getMappingOriginalPath(
    OriginalImportItemManifest item,
    OriginalImportMappingManifest mapping,
  ) {
    final sourceOrder = mapping.originalSourceOrder;
    if (sourceOrder == null) return null;
    for (final file in item.files) {
      if (file.sourceOrder == sourceOrder) {
        return p.join(item.sourceDirectory, file.sourceRelativePath);
      }
    }
    return null;
  }

  Future<void> _showPageMappings(
    OriginalImportManifest manifest,
    OriginalImportItemManifest item,
  ) async {
    await showDialog<void>(
      context: context,
      builder:
          (_) => _OriginalPageMappingDialog(
            manifest: manifest,
            item: item,
            editable:
                item.state != OriginalImportItemState.committed &&
                _committingItemId == null,
          ),
    );
    if (mounted) setState(() {});
  }
}

const _mappingRelationItems = [
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
];

int _downloadedPageCount(OriginalImportItemManifest item) {
  var count = 0;
  for (final mapping in item.pageMappings) {
    final part = mapping.downloadedPart;
    if (part != null && part + 1 > count) count = part + 1;
  }
  return count;
}

void _normalizeMappingRelation(OriginalImportMappingManifest mapping) {
  if (mapping.downloadedPart != null && mapping.originalSourceOrder != null) {
    mapping.relationType = OriginalRelationType.replacement;
  } else if (mapping.originalSourceOrder != null) {
    mapping.relationType = OriginalRelationType.originalOnly;
  } else {
    mapping.relationType = OriginalRelationType.downloadFallback;
  }
}

class _PageIndexPickerDialog extends StatefulWidget {
  final String title;
  final int pageCount;
  final int? selectedIndex;

  const _PageIndexPickerDialog({
    required this.title,
    required this.pageCount,
    required this.selectedIndex,
  });

  @override
  State<_PageIndexPickerDialog> createState() => _PageIndexPickerDialogState();
}

class _PageIndexPickerDialogState extends State<_PageIndexPickerDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        height: 460,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          interactive: true,
          child: ListView.builder(
            controller: _scrollController,
            itemCount: widget.pageCount + 1,
            itemExtent: 48,
            itemBuilder: (_, index) {
              final pageIndex = index - 1;
              final selected = widget.selectedIndex == pageIndex;
              return ListTile(
                selected: selected,
                title: Text(index == 0 ? '无' : '第 $index 页'),
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, pageIndex),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _OriginalPageMappingDialog extends StatefulWidget {
  final OriginalImportManifest manifest;
  final OriginalImportItemManifest item;
  final bool editable;

  const _OriginalPageMappingDialog({
    required this.manifest,
    required this.item,
    required this.editable,
  });

  @override
  State<_OriginalPageMappingDialog> createState() =>
      _OriginalPageMappingDialogState();
}

class _OriginalPageMappingDialogState
    extends State<_OriginalPageMappingDialog> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, Future<String?>> _downloadPathFutures = {};

  Future<String?> _downloadPath(OriginalImportMappingManifest mapping) {
    final part = mapping.downloadedPart;
    if (part == null) return Future<String?>.value();
    return _downloadPathFutures.putIfAbsent(
      part,
      () => downloadStore.getLocalImagePath(
        widget.item.targetIllustId,
        part,
        update: false,
      ),
    );
  }

  String? _originalPath(OriginalImportMappingManifest mapping) {
    final sourceOrder = mapping.originalSourceOrder;
    if (sourceOrder == null) return null;
    for (final file in widget.item.files) {
      if (file.sourceOrder == sourceOrder) {
        return p.join(widget.item.sourceDirectory, file.sourceRelativePath);
      }
    }
    return null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _updateRelation(
    OriginalImportMappingManifest mapping,
    OriginalRelationType value,
  ) async {
    setState(() {
      mapping.relationType = value;
      mapping.manuallyAdjusted = true;
    });
    try {
      await downloadStore.originalImportService.writeManifest(widget.manifest);
    } catch (e, stackTrace) {
      Log.e('保存页面映射失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存页面映射失败：$e')));
      }
    }
  }

  Future<void> _editPage(
    OriginalImportMappingManifest mapping,
    bool downloaded,
  ) async {
    final selected = await showDialog<int>(
      context: context,
      builder:
          (_) => _PageIndexPickerDialog(
            title: downloaded ? '选择下载图' : '选择原图',
            pageCount:
                downloaded
                    ? _downloadedPageCount(widget.item)
                    : widget.item.files.length,
            selectedIndex:
                downloaded
                    ? mapping.downloadedPart
                    : mapping.originalSourceOrder,
          ),
    );
    if (!mounted || selected == null) return;
    final value = selected < 0 ? null : selected;
    if (value == null &&
        (downloaded
            ? mapping.originalSourceOrder == null
            : mapping.downloadedPart == null)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('一条映射不能同时没有下载图和原图')));
      return;
    }
    setState(() {
      if (downloaded) {
        mapping.downloadedPart = value;
      } else {
        mapping.originalSourceOrder = value;
      }
      _normalizeMappingRelation(mapping);
      mapping.manuallyAdjusted = true;
    });
    await downloadStore.originalImportService.writeManifest(widget.manifest);
  }

  Future<void> _shiftAllPagesBackward(bool downloaded) async {
    if (!widget.editable || widget.item.pageMappings.isEmpty) return;
    final mappings = widget.item.pageMappings;
    final values = [
      for (final mapping in mappings)
        downloaded ? mapping.downloadedPart : mapping.originalSourceOrder,
    ];
    final lastValue = values.last;
    setState(() {
      for (var index = mappings.length - 1; index >= 1; index--) {
        if (downloaded) {
          mappings[index].downloadedPart = values[index - 1];
        } else {
          mappings[index].originalSourceOrder = values[index - 1];
        }
      }
      if (downloaded) {
        mappings.first.downloadedPart = null;
      } else {
        mappings.first.originalSourceOrder = null;
      }
      if (lastValue != null) {
        mappings.add(
          OriginalImportMappingManifest(
            displayOrder: mappings.length,
            downloadedPart: downloaded ? lastValue : null,
            originalSourceOrder: downloaded ? null : lastValue,
            relationType:
                downloaded
                    ? OriginalRelationType.downloadFallback
                    : OriginalRelationType.originalOnly,
            manuallyAdjusted: true,
          ),
        );
      }
      for (var index = 0; index < mappings.length; index++) {
        final mapping = mappings[index];
        mapping.displayOrder = index;
        _normalizeMappingRelation(mapping);
        mapping.manuallyAdjusted = true;
      }
    });
    await downloadStore.originalImportService.writeManifest(widget.manifest);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final contentWidth = (screenSize.width - 96).clamp(520.0, 840.0);
    final contentHeight = (screenSize.height - 190).clamp(320.0, 620.0);
    return AlertDialog(
      title: Text(
        '页面映射 · ${p.basename(widget.item.sourceDirectory)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
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
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '共 ${widget.item.pageMappings.length} 页 · 下载页和原图页均从 1 开始计数',
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          widget.editable
                              ? () => _shiftAllPagesBackward(true)
                              : null,
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text('下载图整体后移一位'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          widget.editable
                              ? () => _shiftAllPagesBackward(false)
                              : null,
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text('原图整体后移一位'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  interactive: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: widget.item.pageMappings.length,
                    itemExtent: 132,
                    cacheExtent: 396,
                    itemBuilder: (_, index) {
                      final mapping = widget.item.pageMappings[index];
                      return _MappingComparisonTile(
                        mapping: mapping,
                        downloadPathFuture: _downloadPath(mapping),
                        originalPath: _originalPath(mapping),
                        editable: widget.editable,
                        onEditDownloaded:
                            widget.editable
                                ? () => _editPage(mapping, true)
                                : null,
                        onEditOriginal:
                            widget.editable
                                ? () => _editPage(mapping, false)
                                : null,
                        onRelationChanged:
                            (value) => _updateRelation(mapping, value),
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
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

class _MappingComparisonTile extends StatelessWidget {
  final OriginalImportMappingManifest mapping;
  final Future<String?> downloadPathFuture;
  final String? originalPath;
  final bool editable;
  final VoidCallback? onEditDownloaded;
  final VoidCallback? onEditOriginal;
  final ValueChanged<OriginalRelationType> onRelationChanged;

  const _MappingComparisonTile({
    required this.mapping,
    required this.downloadPathFuture,
    required this.originalPath,
    required this.editable,
    this.onEditDownloaded,
    this.onEditOriginal,
    required this.onRelationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final downloadLabel =
        mapping.downloadedPart == null
            ? '下载图 —'
            : '下载图 ${mapping.downloadedPart! + 1}';
    final originalLabel =
        mapping.originalSourceOrder == null
            ? '原图 —'
            : '原图 ${mapping.originalSourceOrder! + 1}';
    return Container(
      height: 132,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '${mapping.displayOrder + 1}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          _MappingImage(
            label: downloadLabel,
            pathFuture: downloadPathFuture,
            icon: Icons.download_outlined,
            onEdit: onEditDownloaded,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.compare_arrows),
          ),
          _MappingImage(
            label: originalLabel,
            pathFuture: Future<String?>.value(originalPath),
            icon: Icons.photo_outlined,
            onEdit: onEditOriginal,
          ),
          const Spacer(),
          DropdownButton<OriginalRelationType>(
            value: mapping.relationType,
            onChanged:
                editable
                    ? (value) {
                      if (value != null) onRelationChanged(value);
                    }
                    : null,
            items: _mappingRelationItems,
          ),
        ],
      ),
    );
  }
}

class _MappingImage extends StatelessWidget {
  final String label;
  final Future<String?> pathFuture;
  final IconData icon;
  final VoidCallback? onEdit;

  const _MappingImage({
    required this.label,
    required this.pathFuture,
    required this.icon,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onEdit != null)
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.edit_outlined, size: 16),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Center(
              child: _LocalCover(
                pathFuture: pathFuture,
                width: 96,
                height: 88,
                icon: icon,
                title: label,
              ),
            ),
          ),
        ],
      ),
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
  final Map<int, Future<String?>> _coverFutures = {};
  String _query = '';

  Future<String?> _coverPath(DownloadedIllust work) => _coverFutures
      .putIfAbsent(work.illustId, () => _resolveDownloadedCoverPath(work));

  Future<String?> _workDirectoryPath(DownloadedIllust work) async {
    final downloadPath = downloadStore.getIllustDirectoryPath(work);
    if (downloadPath != null && await Directory(downloadPath).exists()) {
      return downloadPath;
    }
    final originalSet = await downloadStore.originalRepository.getDefaultSet(
      work.illustId,
    );
    return originalSet == null
        ? downloadPath
        : downloadStore.dbProvider.getOriginalAbsolutePath(
          originalSet.relativePath,
        );
  }

  Future<void> _openWorkDirectory(DownloadedIllust work) async {
    final directory = await _workDirectoryPath(work);
    if (!mounted) return;
    if (directory == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未找到作品目录')));
      return;
    }
    try {
      await FileUtils.openFileOrDirectory(directory);
    } catch (e, stackTrace) {
      Log.e('打开匹配作品目录失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开目录失败：$e')));
      }
    }
  }

  Future<void> _copyWorkPath(DownloadedIllust work) async {
    final directory = await _workDirectoryPath(work);
    if (!mounted) return;
    if (directory == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未找到作品目录')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: directory));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('路径已复制到剪贴板')));
    }
  }

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
                            itemExtent: 84,
                            cacheExtent: 336,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemBuilder: (_, index) {
                              final work = filtered[index];
                              final selected =
                                  work.illustId == widget.selectedIllustId;
                              return ListTile(
                                selected: selected,
                                leading: _LocalCover(
                                  pathFuture: _coverPath(work),
                                  width: 76,
                                  height: 72,
                                  icon: Icons.image_outlined,
                                  title: work.title,
                                ),
                                title: Text(
                                  work.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${work.createDate.split('T').first} · ID ${work.illustId} · ${work.pageCount} 页',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Tooltip(
                                      message: '打开作品目录',
                                      child: IconButton(
                                        onPressed:
                                            () => _openWorkDirectory(work),
                                        icon: const Icon(
                                          Icons.folder_open_outlined,
                                        ),
                                      ),
                                    ),
                                    Tooltip(
                                      message: '复制作品路径',
                                      child: IconButton(
                                        onPressed: () => _copyWorkPath(work),
                                        icon: const Icon(Icons.content_copy),
                                      ),
                                    ),
                                    if (selected) const Icon(Icons.check),
                                  ],
                                ),
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

Future<String?> _resolveDownloadedCoverPath(DownloadedIllust work) async {
  final cachedCover = File(downloadStore.getCoverCachePath(work.illustId));
  if (await cachedCover.exists()) return cachedCover.path;
  final infos = await downloadStore.getLocalImageInfos(work.illustId);
  if (infos.isEmpty) return null;
  final parts = infos.keys.toList()..sort();
  return infos[parts.first]?.path;
}

class _LocalCover extends StatelessWidget {
  final Future<String?> pathFuture;
  final double width;
  final double height;
  final IconData icon;
  final String? title;

  const _LocalCover({
    required this.pathFuture,
    required this.width,
    required this.height,
    required this.icon,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ColoredBox(
          color: colorScheme.surfaceContainerHighest,
          child: FutureBuilder<String?>(
            future: pathFuture,
            builder: (context, snapshot) {
              final path = snapshot.data;
              if (path == null) {
                return Center(
                  child:
                      snapshot.connectionState == ConnectionState.waiting
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Icon(icon, color: colorScheme.onSurfaceVariant),
                );
              }
              return Tooltip(
                message: '点击放大',
                child: InkWell(
                  onTap:
                      () => LocalImageViewerPage.open(
                        context,
                        imagePath: path,
                        title: title ?? p.basename(path),
                      ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(path),
                        fit: BoxFit.contain,
                        cacheWidth: (width * 2).round(),
                        filterQuality: FilterQuality.low,
                        gaplessPlayback: true,
                        errorBuilder:
                            (_, _, _) => Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                      ),
                      Positioned(
                        right: 3,
                        bottom: 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.zoom_in,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
