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
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/sort_group.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/downloaded/downloaded_page.dart';
import 'package:pixez/store/download_store.dart';
import 'package:pixez/page/task/widgets/task_item_widget.dart';

class JobPage extends StatefulWidget {
  @override
  _JobPageState createState() => _JobPageState();
}

class _JobPageState extends State<JobPage> {
  int currentIndex = 0;

  String _formatSpeed(double bytes) {
    if (bytes <= 0) return '0 B/s';
    if (bytes < 1024) return '${bytes.toStringAsFixed(1)} B/s';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(I18n.of(context).task_progress),
        actions: [
          IconButton(
            tooltip: '清除已完成',
            icon: const Icon(Icons.cleaning_services_rounded),
            onPressed: () => downloadStore.clearCompletedTasks(),
          ),
          IconButton(
            tooltip: '全部取消',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () {
              showDialog(
                context: context,
                builder:
                    (context) => AlertDialog(
                      title: const Text('确认取消'),
                      content: const Text('确定要取消所有下载任务吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () {
                            downloadStore.cancelAllDownload();
                            Navigator.pop(context);
                          },
                          child: const Text(
                            '全部取消',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildControlPanel(),
            _buildTabSection(),
            Expanded(child: _buildTaskList()),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Observer(
      builder: (_) {
        final totalSpeed = downloadStore.totalSpeed;
        final tasks = downloadStore.downloadingTasks.values.toList();
        final runningCount =
            tasks
                .where((t) => t.status == DownloadTaskStatus.downloading)
                .length;
        final pendingCount =
            tasks.where((t) => t.status == DownloadTaskStatus.pending).length;
        final pausedCount =
            tasks
                .where(
                  (t) =>
                      t.status == DownloadTaskStatus.paused ||
                      t.status == DownloadTaskStatus.failed,
                )
                .length;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '总下载速度',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatSpeed(totalSpeed),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '队列: ${tasks.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatButton(
                    icon: Icons.pause_rounded,
                    label: '全部暂停',
                    onTap: () => downloadStore.pauseAllDownload(),
                    enabled: runningCount + pendingCount > 0,
                  ),
                  _buildStatButton(
                    icon: Icons.play_arrow_rounded,
                    label: '全部开始',
                    onTap: () => downloadStore.resumeAllDownload(),
                    enabled: pausedCount > 0,
                  ),
                  _buildStatButton(
                    icon: Icons.folder_open_rounded,
                    label: '浏览本地',
                    onTap: () => DownloadedPage.open(context),
                    enabled: true,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SortGroup(
        children: [
          I18n.of(context).all,
          I18n.of(context).running,
          I18n.of(context).failed,
        ],
        onChange: (index) {
          setState(() {
            currentIndex = index;
          });
        },
      ),
    );
  }

  Widget _buildTaskList() {
    return Observer(
      builder: (_) {
        List<DownloadTask> tasks =
            downloadStore.downloadingTasks.values.toList();

        // 排序规则：正在下载 > 等待 > 暂停 > 失败 > 完成
        tasks.sort((a, b) {
          int score(DownloadTaskStatus status) {
            switch (status) {
              case DownloadTaskStatus.downloading:
                return 0;
              case DownloadTaskStatus.pending:
                return 1;
              case DownloadTaskStatus.paused:
                return 2;
              case DownloadTaskStatus.failed:
                return 3;
              case DownloadTaskStatus.completed:
                return 4;
              default:
                return 5;
            }
          }

          return score(a.status).compareTo(score(b.status));
        });

        if (currentIndex == 1) {
          tasks =
              tasks
                  .where(
                    (t) =>
                        t.status == DownloadTaskStatus.downloading ||
                        t.status == DownloadTaskStatus.pending,
                  )
                  .toList();
        } else if (currentIndex == 2) {
          tasks =
              tasks
                  .where((t) => t.status == DownloadTaskStatus.failed)
                  .toList();
        }

        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox_rounded,
                  size: 64,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无下载任务',
                  style: TextStyle(color: Theme.of(context).dividerColor),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return TaskItemWidget(
              key: ValueKey(task.taskKey),
              task: task,
              downloadStore: downloadStore,
              onDelete: () => downloadStore.cancelTask(task.taskKey),
              onRetry: () => downloadStore.retryTask(task.taskKey),
              onResume:
                  () => downloadStore.resumeIllustDownload(
                    task.illusts.id,
                  ), // 注意这里是恢复整个插画的任务
            );
          },
        );
      },
    );
  }
}
