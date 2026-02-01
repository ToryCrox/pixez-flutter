/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pixez/utils/file_utils.dart';
import 'package:photo_view/photo_view.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/downloaded/bookmark_priority_dialog.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/downloaded/update_illust_info_dialog.dart';
import 'package:pixez/store/download_store.dart';
import 'package:pixez/utils/ugoira_downloader.dart';

/// 下载状态指示器组件
/// 支持三种状态: 下载中(显示进度)、下载完成、未下载
class DownloadStatusIndicator extends StatefulWidget {
  final int illustId;
  final int pageCount;
  final double size;
  final Color? downloadedColor;
  final Color? downloadingColor;

  const DownloadStatusIndicator({
    Key? key,
    required this.illustId,
    this.pageCount = 1,
    this.size = 16,
    this.downloadedColor,
    this.downloadingColor,
  }) : super(key: key);

  @override
  State<DownloadStatusIndicator> createState() =>
      _DownloadStatusIndicatorState();
}

class _DownloadStatusIndicatorState extends State<DownloadStatusIndicator> {
  IllustDownloadStatus? _status;
  StreamSubscription<IllustDownloadStatus>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = downloadStore.illustDownloadStatusStream.listen(
      _onProgressUpdate,
    );
    _checkStatus();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DownloadStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.illustId != widget.illustId) {
      _checkStatus();
    }
  }

  void _onProgressUpdate(IllustDownloadStatus status) {
    if (status.illusts.illustId != widget.illustId) return;
    if (!mounted) return;

    // 如果是删除状态，清空状态
    if (status.status == DownloadTaskStatus.deleted) {
      setState(() {
        _status = null;
      });
      return;
    }

    setState(() {
      _status = status;
    });
  }

  Future<void> _checkStatus() async {
    if (!downloadStore.isInitialized) {
      if (mounted) {
        setState(() {
          _status = null;
        });
      }
      return;
    }
    _status = await downloadStore.getIllustDownloadStatus(widget.illustId);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final taskStatus = status?.status;
    if (taskStatus == null || status == null) {
      return const SizedBox.shrink();
    }
    switch (taskStatus) {
      case DownloadTaskStatus.completed:
        if (status.isAllDownloaded) {
          return _buildDownloadedIcon();
        }
        return _buildDownloadUncompletedIcon();
      case DownloadTaskStatus.downloading:
        return _buildDownloadingIndicator();
      case DownloadTaskStatus.pending:
        return _buildPendingIndicator();
      case DownloadTaskStatus.failed:
        return _buildFailedIcon();
      case DownloadTaskStatus.paused:
        return _buildPausedIcon();
      case DownloadTaskStatus.deleted:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDownloadUncompletedIcon() {
    final fileSize = _status?.fileSize ?? 0;
    final icon = Icon(
      Icons.download,
      size: widget.size,
      color: widget.downloadedColor ?? Colors.green,
    );
    if (fileSize > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          SizedBox(width: 4),
          Text(
            fileSize.formatFileSize(),
            style: TextStyle(
              fontSize: 11,
              color: widget.downloadedColor ?? Colors.green,
            ),
          ),
        ],
      );
    }
    return icon;
  }

  Widget _buildDownloadedIcon() {
    final fileSize = _status?.fileSize ?? 0;
    final icon = Icon(
      Icons.download_done,
      size: widget.size,
      color: widget.downloadedColor ?? Colors.green,
    );
    if (fileSize > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          SizedBox(width: 4),
          Text(
            fileSize.formatFileSize(),
            style: TextStyle(
              fontSize: 11,
              color: widget.downloadedColor ?? Colors.green,
            ),
          ),
        ],
      );
    }
    return icon;
  }

  Widget _buildPendingIndicator() {
    return Icon(Icons.schedule, size: widget.size, color: Colors.grey);
  }

  Widget _buildDownloadingIndicator() {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            //value: _currentProgress > 0 ? _currentProgress : null,
            strokeWidth: 2,
            color:
                widget.downloadingColor ??
                Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildFailedIcon() {
    return Icon(Icons.error, size: widget.size, color: Colors.red);
  }

  Widget _buildPausedIcon() {
    return Icon(Icons.pause, size: widget.size, color: Colors.grey);
  }
}

/// 插画下载按钮组件
/// 实时监听下载状态，点击后显示下载/删除对话框（在页面中间）
class IllustDownloadButton extends StatefulWidget {
  final Illusts illusts;
  final double iconSize;
  final Future<bool> Function()? onStarAfterSave;

  /// 是否以 FloatingActionButton 样式显示
  final bool asFloatingActionButton;

  const IllustDownloadButton({
    Key? key,
    required this.illusts,
    this.iconSize = 24,
    this.onStarAfterSave,
    this.asFloatingActionButton = false,
  }) : super(key: key);

  @override
  State<IllustDownloadButton> createState() => _IllustDownloadButtonState();
}

class _IllustDownloadButtonState extends State<IllustDownloadButton> {
  IllustDownloadStatus? _status;
  StreamSubscription<IllustDownloadStatus>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = downloadStore.illustDownloadStatusStream.listen(
      _onProgressUpdate,
    );
    _checkStatus();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IllustDownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.illusts.id != widget.illusts.id) {
      _checkStatus();
    }
  }

  void _onProgressUpdate(IllustDownloadStatus status) {
    if (status.illusts.illustId != widget.illusts.id) return;
    if (!mounted) return;

    if (status.status == DownloadTaskStatus.deleted) {
      setState(() {
        _status = null;
      });
      return;
    }

    setState(() {
      _status = status;
    });
  }

  Future<void> _checkStatus() async {
    if (!downloadStore.isInitialized) {
      if (mounted) {
        setState(() {
          _status = null;
        });
      }
      return;
    }
    _status = await downloadStore.getIllustDownloadStatus(widget.illusts.id);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final taskStatus = status?.status;
    final fileSize = status?.fileSize ?? 0;
    final showFileSize =
        taskStatus != null && taskStatus != DownloadTaskStatus.deleted;

    Widget iconWidget = _buildIcon();

    // 如果以 FloatingActionButton 样式显示
    if (widget.asFloatingActionButton) {
      Widget child = iconWidget;
      if (showFileSize) {
        child = Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            SizedBox(height: 2),
            Text(
              fileSize.formatFileSize(),
              style: TextStyle(fontSize: 10, color: Colors.green.shade300),
            ),
          ],
        );
      }
      return GestureDetector(
        onLongPress: _showPriorityDialog,
        child: FloatingActionButton(onPressed: _showDownloadDialog, child: child),
      );
    }

    return SizedBox(
      width: 40,
      height: 40,
      child: InkWell(
        onTap: _showDownloadDialog,
        onLongPress: _showPriorityDialog,
        borderRadius: BorderRadius.circular(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            if (showFileSize) SizedBox(height: 2),
            if (showFileSize)
              Text(
                fileSize.formatFileSize(),
                maxLines: 1,
                style: TextStyle(fontSize: 9, height: 1.0, color: Colors.green),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    final status = _status;
    final taskStatus = status?.status;

    if (taskStatus == null || status == null) {
      return Icon(Icons.download_outlined, size: widget.iconSize);
    }

    switch (taskStatus) {
      case DownloadTaskStatus.completed:
        if (status.isAllDownloaded) {
          return Icon(
            Icons.download_done,
            size: widget.iconSize,
            color:
                widget.asFloatingActionButton
                    ? Colors.green.shade300
                    : Colors.green,
          );
        }
        return Icon(
          Icons.download,
          size: widget.iconSize,
          color:
              widget.asFloatingActionButton
                  ? Colors.green.shade300
                  : Colors.green,
        );
      case DownloadTaskStatus.downloading:
        return SizedBox(
          width: widget.iconSize,
          height: widget.iconSize,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color:
                widget.asFloatingActionButton
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.primary,
          ),
        );
      case DownloadTaskStatus.pending:
        return Icon(
          Icons.schedule,
          size: widget.iconSize,
          color: widget.asFloatingActionButton ? null : Colors.grey,
        );
      case DownloadTaskStatus.failed:
        return Icon(
          Icons.error,
          size: widget.iconSize,
          color:
              widget.asFloatingActionButton ? Colors.red.shade300 : Colors.red,
        );
      case DownloadTaskStatus.paused:
        return Icon(
          Icons.pause,
          size: widget.iconSize,
          color: widget.asFloatingActionButton ? null : Colors.grey,
        );
      case DownloadTaskStatus.deleted:
        return Icon(Icons.download_outlined, size: widget.iconSize);
    }
  }

  Future<void> _showDownloadDialog() async {
    final status = _status;
    final isDownloaded =
        status?.status == DownloadTaskStatus.completed &&
        status?.isAllDownloaded == true;
    final isDownloading =
        status?.status == DownloadTaskStatus.downloading ||
        status?.status == DownloadTaskStatus.pending;

    // 如果未下载且未在下载中，直接下载而不显示弹框
    if (!isDownloaded && !isDownloading) {
      _downloadAllPages();
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            widget.illusts.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDownloading)
                ListTile(
                  leading: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('下载中...'),
                ),
              ListTile(
                leading: Icon(Icons.folder_open),
                title: Text('打开文件夹'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openDownloadDirectory();
                },
              ),
              if (isDownloaded) ...[
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text('已下载'),
                  subtitle:
                      status?.fileSize != null && status!.fileSize > 0
                          ? Text(
                            status.fileSize.formatFileSize(),
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          )
                          : null,
                ),
                // 动图转换选项（仅限动图类型）
                if (widget.illusts.type == 'ugoira')
                  ListTile(
                    leading: Icon(Icons.movie_creation, color: Colors.blue),
                    title: Text('转换为动图 (WebP)'),
                    subtitle: Text('将序列帧合成为单个动图文件', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _convertToWebP();
                    },
                  ),
                // 测试高清下载选项（仅限动图类型）
                if (widget.illusts.type == 'ugoira')
                  ListTile(
                    leading: Icon(Icons.science, color: Colors.orange),
                    title: Text('测试高清ZIP下载'),
                    subtitle: Text('方案一: 尝试下载 1920x1080 ZIP', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _testOriginalDownload();
                    },
                  ),
                // 测试逐帧下载选项（仅限动图类型）
                if (widget.illusts.type == 'ugoira')
                  ListTile(
                    leading: Icon(Icons.burst_mode, color: Colors.purple),
                    title: Text('测试逐帧下载'),
                    subtitle: Text('方案二: 逐帧下载原始图片', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _testOriginalFramesDownload();
                    },
                  ),
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('更新信息'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openUpdateInfoDialog();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text('删除', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDelete();
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('关闭')),
          ],
        );
      },
    );
  }

  Future<void> _openDownloadDirectory() async {
    if (!downloadStore.isInitialized) {
      return;
    }
    try {
      final dirPath = await downloadStore.getIllustDownloadDirectory(widget.illusts);
      if (dirPath != null) {
        await FileUtils.openFileOrDirectory(dirPath);
      }
    } catch (e) {
      Log.e('Failed to open download directory: $e');
      BotToast.showText(text: '打开文件夹失败: $e');
    }
  }

  Future<void> _downloadAllPages({int bookmark = 0}) async {
    // 如果设置了下载后收藏，且未指定 bookmark，则设为 1
    int effectiveBookmark = bookmark;
    if (effectiveBookmark == 0 && userSetting.starAfterSave) {
      effectiveBookmark = 1;
    }

    downloadStore.downloadIllust(widget.illusts, bookmark: effectiveBookmark);
    if (userSetting.starAfterSave && widget.onStarAfterSave != null) {
      widget.onStarAfterSave!();
    }
  }

  void _showPriorityDialog() {
    showDialog(
      context: context,
      builder: (context) => BookmarkPriorityDialog(
        onPrioritySelected: (priority) {
          _downloadAllPages(bookmark: priority);
        },
      ),
    );
  }

  Future<void> _openUpdateInfoDialog() async {
    if (!downloadStore.isInitialized) {
      BotToast.showText(text: '下载功能未初始化');
      return;
    }

    try {
      final DownloadedIllust? downloadedIllust = await downloadStore
          .getDownloadedIllust(widget.illusts.id);
      if (downloadedIllust == null) {
        BotToast.showText(text: '未找到下载记录');
        return;
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (ctx) => UpdateIllustInfoDialog(illusts: [downloadedIllust]),
      );
    } catch (e) {
      Log.e('Failed to open update info dialog: $e');
      BotToast.showText(text: '打开更新信息对话框失败: $e');
    }
  }

  /// 将动图序列帧转换为WebP
  Future<void> _convertToWebP() async {
    if (!downloadStore.isInitialized) {
      BotToast.showText(text: '下载功能未初始化');
      return;
    }

    BotToast.showText(text: '开始转换动图...');

    try {
      final result = await downloadStore.convertUgoiraToWebP(widget.illusts.id);
      if (result != null) {
        BotToast.showText(text: '转换完成！');
        // 刷新状态
        await _checkStatus();
      } else {
        BotToast.showText(text: '转换失败，请检查日志');
      }
    } catch (e) {
      Log.e('转换动图失败: $e');
      BotToast.showText(text: '转换失败: $e');
    }
  }

  /// 测试高清动图下载
  Future<void> _testOriginalDownload() async {
    BotToast.showText(text: '开始测试高清下载...');

    try {
      final result = await ugoiraDownloader.testDownloadOriginalUgoira(
        widget.illusts.id,
      );

      // 显示结果对话框
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text('测试结果'),
            content: SingleChildScrollView(
              child: SelectableText(
                result,
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('关闭'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      Log.e('测试高清下载失败: $e');
      BotToast.showText(text: '测试失败: $e');
    }
  }

  /// 测试逐帧下载原始图片（方案二）
  Future<void> _testOriginalFramesDownload() async {
    BotToast.showText(text: '开始测试逐帧下载...');

    try {
      final result = await ugoiraDownloader.testDownloadOriginalFrames(
        widget.illusts.id,
      );

      // 显示结果对话框
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text('逐帧下载测试结果'),
            content: SingleChildScrollView(
              child: SelectableText(
                result,
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('关闭'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      Log.e('测试逐帧下载失败: $e');
      BotToast.showText(text: '测试失败: $e');
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('确认删除'),
          content: Text('确定要删除 "${widget.illusts.title}" 的下载吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await downloadStore.deleteDownloadedIllust(widget.illusts.id);
    }
  }
}
