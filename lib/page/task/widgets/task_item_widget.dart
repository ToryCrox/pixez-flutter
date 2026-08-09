/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful, but WITHOUT ANY
 *  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 *  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along with
 *  this program. If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:flutter/material.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/page/picture/illust_lighting_page.dart';
import 'package:pixez/store/download_store.dart';

class TaskItemWidget extends StatelessWidget {
  final DownloadTask task;
  final bool isPending;
  final DownloadStore downloadStore;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;
  final VoidCallback? onResume;

  const TaskItemWidget({
    Key? key,
    required this.task,
    this.isPending = false,
    required this.downloadStore,
    this.onDelete,
    this.onRetry,
    this.onResume,
  }) : super(key: key);

  String _formatBytes(double bytes) {
    if (bytes <= 0) return '0 B/s';
    if (bytes < 1024) {
      return '${bytes.toStringAsFixed(1)} B/s';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB/s';
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 0) return '--:--';
    if (seconds > 3600) {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '${hours}h ${minutes}m';
    }
    final minutes = seconds ~/ 60;
    final scnds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${scnds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final illust = task.illusts;
    final isRunning = task.status == DownloadTaskStatus.downloading;
    final isFailed = task.status == DownloadTaskStatus.failed;
    final isPaused = task.status == DownloadTaskStatus.paused;
    final progress = task.progress;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => IllustLightingPage(id: illust.id),
              ),
            );
          },
          child: IntrinsicHeight(
            child: Row(
              children: [
                // 缩略图
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PixivImage(illust.imageUrls.medium, fit: BoxFit.cover),
                      if (isRunning)
                        Container(
                          color: Colors.black26,
                          child: Center(
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                value: progress > 0 ? progress : null,
                                strokeWidth: 3,
                                valueColor: const AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (isPaused)
                        const Center(
                          child: Icon(
                            Icons.pause_circle_filled,
                            color: Colors.white70,
                            size: 40,
                          ),
                        ),
                      if (isFailed)
                        const Center(
                          child: Icon(
                            Icons.error,
                            color: Colors.redAccent,
                            size: 40,
                          ),
                        ),
                    ],
                  ),
                ),
                // 内容区
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${illust.title} (p${task.part})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              illust.user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 状态与信息
                        Row(
                          children: [
                            if (isRunning) ...[
                              Text(
                                _formatBytes(task.speed),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'ETA: ${_formatDuration(task.eta)}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                  textAlign: TextAlign.end,
                                  maxLines: 1,
                                ),
                              ),
                            ] else ...[
                              Expanded(
                                child: Text(
                                  isFailed
                                      ? '下载失败'
                                      : (isPaused
                                          ? '已暂停'
                                          : (isPending ? '等待确认' : '等待中')),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color:
                                        isFailed
                                            ? Colors.red
                                            : (isPaused
                                                ? Colors.orange
                                                : Colors.grey),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 8),
                            Text(
                              '${_formatSize(task.received)} / ${_formatSize(task.total)}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // 进度条
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value:
                                progress > 0
                                    ? progress
                                    : (isRunning ? null : 0.0),
                            minHeight: 4,
                            backgroundColor: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.05),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 操作按钮
                Container(
                  width: 48,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (isPaused || isFailed || isPending)
                        IconButton(
                          icon: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.green,
                            size: 20,
                          ),
                          onPressed: onResume ?? onRetry,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        )
                      else if (isRunning ||
                          task.status == DownloadTaskStatus.pending)
                        IconButton(
                          icon: const Icon(
                            Icons.pause_rounded,
                            color: Colors.orange,
                            size: 20,
                          ),
                          onPressed:
                              () =>
                                  downloadStore.pauseIllustDownload(illust.id),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        onPressed: onDelete,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
