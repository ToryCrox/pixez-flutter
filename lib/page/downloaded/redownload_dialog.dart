import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/network/api_client.dart';

class RedownloadSummary {
  final int queuedCount;
  final int skippedCount;
  final int failedCount;

  const RedownloadSummary({
    required this.queuedCount,
    required this.skippedCount,
    required this.failedCount,
  });
}

class RedownloadDialog extends StatefulWidget {
  final List<DownloadedIllust> illusts;

  const RedownloadDialog({super.key, required this.illusts});

  static Future<RedownloadSummary?> show(
    BuildContext context, {
    required List<DownloadedIllust> illusts,
  }) {
    final targets = illusts.where((illust) => !illust.isLocal).toList();
    if (targets.isEmpty) return Future.value();

    return showDialog<RedownloadSummary>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RedownloadDialog(illusts: targets),
    );
  }

  @override
  State<RedownloadDialog> createState() => _RedownloadDialogState();
}

enum _RedownloadPhase { checking, ready, downloading, completed }

enum _RedownloadItemStatus {
  pending,
  exists,
  notFound,
  checkFailed,
  downloading,
  queued,
  downloadFailed,
}

class _RedownloadItem {
  final DownloadedIllust localIllust;
  _RedownloadItemStatus status = _RedownloadItemStatus.pending;
  Illusts? remoteIllust;

  _RedownloadItem(this.localIllust);
}

class _RedownloadDialogState extends State<RedownloadDialog> {
  late final List<_RedownloadItem> _items;

  _RedownloadPhase _phase = _RedownloadPhase.checking;
  int _checkedCount = 0;
  int _processedCount = 0;
  int _queuedCount = 0;
  int _failedCount = 0;
  RedownloadSummary? _summary;

  @override
  void initState() {
    super.initState();
    _items = widget.illusts.map(_RedownloadItem.new).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkItems());
    });
  }

  Future<Illusts?> _getIllust(int illustId) async {
    final response = await apiClient.getIllustDetail(illustId);
    final responseData = response.data;
    if (responseData is! Map) return null;

    final illustData = responseData['illust'];
    if (illustData is! Map) return null;

    final illust = Illusts.fromJson(Map<String, dynamic>.from(illustData));
    if (illust.id != illustId ||
        illust.imageUrls.medium.contains('limit_unknown')) {
      return null;
    }
    return illust;
  }

  Future<void> _checkItem(_RedownloadItem item) async {
    Illusts? remoteIllust;
    _RedownloadItemStatus status;
    try {
      remoteIllust = await _getIllust(item.localIllust.illustId);
      status =
          remoteIllust == null
              ? _RedownloadItemStatus.notFound
              : _RedownloadItemStatus.exists;
    } catch (e, stackTrace) {
      status = _RedownloadItemStatus.checkFailed;
      Log.w(
        '确认重新下载作品失败: ${item.localIllust.illustId}',
        error: e,
        stackTrace: stackTrace,
      );
    }

    if (!mounted) return;
    setState(() {
      item.remoteIllust = remoteIllust;
      item.status = status;
      _checkedCount++;
    });
  }

  Future<void> _checkItems() async {
    await Future.wait(_items.map(_checkItem));
    if (!mounted) return;
    setState(() {
      _phase = _RedownloadPhase.ready;
    });
  }

  Future<void> _downloadItems() async {
    final validItems =
        _items
            .where((item) => item.status == _RedownloadItemStatus.exists)
            .toList();

    if (mounted) {
      setState(() {
        _phase = _RedownloadPhase.downloading;
      });
    }

    for (final item in validItems) {
      if (!mounted) return;
      setState(() {
        item.status = _RedownloadItemStatus.downloading;
      });

      try {
        await downloadStore.deleteDownloadedIllust(item.localIllust.illustId);
        await downloadStore.downloadIllust(
          item.remoteIllust!,
          bookmark: item.localIllust.bookmark,
        );
        _queuedCount++;
        if (mounted) {
          setState(() {
            item.status = _RedownloadItemStatus.queued;
            _processedCount++;
          });
        }
      } catch (e, stackTrace) {
        _failedCount++;
        Log.w(
          '重新下载作品失败: ${item.localIllust.illustId}',
          error: e,
          stackTrace: stackTrace,
        );
        if (mounted) {
          setState(() {
            item.status = _RedownloadItemStatus.downloadFailed;
            _processedCount++;
          });
        }
      }
    }
  }

  Future<void> _startRedownload() async {
    if (_phase != _RedownloadPhase.ready) return;
    await _downloadItems();
    if (!mounted) return;

    final skippedCount =
        _items
            .where((item) => item.status == _RedownloadItemStatus.notFound)
            .length;
    _summary = RedownloadSummary(
      queuedCount: _queuedCount,
      skippedCount: skippedCount,
      failedCount:
          _failedCount +
          _items
              .where((item) => item.status == _RedownloadItemStatus.checkFailed)
              .length,
    );
    setState(() {
      _phase = _RedownloadPhase.completed;
    });
  }

  Widget _buildItemStatus(_RedownloadItem item) {
    switch (item.status) {
      case _RedownloadItemStatus.pending:
        return const Icon(Icons.hourglass_empty, color: Colors.grey);
      case _RedownloadItemStatus.exists:
        return const Icon(Icons.check_circle, color: Colors.green);
      case _RedownloadItemStatus.notFound:
        return const Icon(Icons.remove_circle, color: Colors.orange);
      case _RedownloadItemStatus.checkFailed:
        return const Icon(Icons.error, color: Colors.red);
      case _RedownloadItemStatus.downloading:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _RedownloadItemStatus.queued:
        return const Icon(Icons.download_done, color: Colors.green);
      case _RedownloadItemStatus.downloadFailed:
        return const Icon(Icons.error_outline, color: Colors.red);
    }
  }

  String _itemStatusText(_RedownloadItem item) {
    switch (item.status) {
      case _RedownloadItemStatus.pending:
        return '等待检查';
      case _RedownloadItemStatus.exists:
        return '作品存在';
      case _RedownloadItemStatus.notFound:
        return '作品不存在，已跳过';
      case _RedownloadItemStatus.checkFailed:
        return '接口检查失败，已跳过';
      case _RedownloadItemStatus.downloading:
        return '正在删除并加入下载队列';
      case _RedownloadItemStatus.queued:
        return '已加入下载队列';
      case _RedownloadItemStatus.downloadFailed:
        return '重新下载失败';
    }
  }

  Widget _buildItemsList() {
    return SizedBox(
      height: 260,
      child: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return ListTile(
            dense: true,
            leading: SizedBox(
              width: 80,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildItemCover(item),
                  const SizedBox(width: 4),
                  _buildItemStatus(item),
                ],
              ),
            ),
            title: Text(
              item.localIllust.title.isEmpty
                  ? '${item.localIllust.illustId}'
                  : item.localIllust.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(_itemStatusText(item)),
          );
        },
      ),
    );
  }

  Widget _buildItemCover(_RedownloadItem item) {
    final remoteCoverUrl = item.remoteIllust?.imageUrls.squareMedium;
    var coverUrl =
        remoteCoverUrl?.isNotEmpty == true
            ? remoteCoverUrl!
            : item.localIllust.getImageUrls().squareMedium;
    if (coverUrl.isEmpty) {
      try {
        coverUrl = item.localIllust.toIllusts().imageUrls.squareMedium;
      } catch (e, stackTrace) {
        Log.w(
          '解析重新下载作品封面失败: ${item.localIllust.illustId}',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
    if (coverUrl.isEmpty) {
      return Container(
        width: 48,
        height: 64,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_outlined, size: 20),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 48,
        height: 64,
        child: PixivImage(
          coverUrl,
          fit: BoxFit.cover,
          memCacheWidth: 96,
          httpHeaders: {
            'cover': '${item.localIllust.illustId}',
            'quality': userSetting.previewQuality,
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_phase) {
      case _RedownloadPhase.checking:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('正在并发检查作品：$_checkedCount/${_items.length}'),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _checkedCount / _items.length),
            const SizedBox(height: 12),
            _buildItemsList(),
          ],
        );
      case _RedownloadPhase.ready:
        final existsCount =
            _items
                .where((item) => item.status == _RedownloadItemStatus.exists)
                .length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('检查完成：${_items.length} 项作品中有 $existsCount 项可以重新下载。'),
            const SizedBox(height: 8),
            if (existsCount > 0) const Text('确认后会删除这些作品现有的下载图片。'),
            if (existsCount == 0) const Text('没有可以重新下载的作品。'),
            const SizedBox(height: 12),
            _buildItemsList(),
          ],
        );
      case _RedownloadPhase.downloading:
        final validCount =
            _items
                .where(
                  (item) =>
                      item.status == _RedownloadItemStatus.exists ||
                      item.status == _RedownloadItemStatus.downloading ||
                      item.status == _RedownloadItemStatus.queued ||
                      item.status == _RedownloadItemStatus.downloadFailed,
                )
                .length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('正在删除并加入下载队列：$_processedCount/$validCount'),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: validCount == 0 ? 1 : _processedCount / validCount,
            ),
            const SizedBox(height: 12),
            _buildItemsList(),
          ],
        );
      case _RedownloadPhase.completed:
        final summary = _summary!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '检查完成：${_items.length} 项作品，'
              '已加入 ${summary.queuedCount} 项，'
              '跳过不存在 ${summary.skippedCount} 项，'
              '失败 ${summary.failedCount} 项。',
            ),
            const SizedBox(height: 12),
            _buildItemsList(),
          ],
        );
    }
  }

  String _title() {
    switch (_phase) {
      case _RedownloadPhase.checking:
        return '检查作品';
      case _RedownloadPhase.ready:
        return '重新下载';
      case _RedownloadPhase.downloading:
        return '重新下载';
      case _RedownloadPhase.completed:
        return '重新下载结果';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _phase == _RedownloadPhase.ready;
    final isCompleted = _phase == _RedownloadPhase.completed;
    final contentWidth =
        (MediaQuery.sizeOf(context).width - 64).clamp(280.0, 560.0).toDouble();
    final existsCount =
        _items
            .where((item) => item.status == _RedownloadItemStatus.exists)
            .length;
    return AlertDialog(
      title: Text(_title()),
      content: SizedBox(width: contentWidth, child: _buildContent()),
      actions: [
        if (_phase == _RedownloadPhase.checking)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(I18n.of(context).cancel),
          ),
        if (isReady)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(I18n.of(context).cancel),
          ),
        if (isReady && existsCount > 0)
          FilledButton(
            onPressed: () => unawaited(_startRedownload()),
            child: const Text('确认重新下载'),
          ),
        if (isReady && existsCount == 0)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(I18n.of(context).ok),
          ),
        if (isCompleted)
          TextButton(
            onPressed: () => Navigator.pop(context, _summary),
            child: Text(I18n.of(context).ok),
          ),
      ],
    );
  }
}
