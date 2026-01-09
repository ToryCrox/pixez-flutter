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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/component/sort_group.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/downloaded/downloaded_page.dart';
import 'package:pixez/page/picture/illust_lighting_page.dart';
import 'package:pixez/store/download_store.dart';

class JobPage extends StatefulWidget {
  @override
  _JobPageState createState() => _JobPageState();
}

class _JobPageState extends State<JobPage> with SingleTickerProviderStateMixin {
  Timer? _timer;
  ScrollController _scrollController = ScrollController();
  bool _itemSimple = true;

  // 新下载器任务列表
  List<DownloadTask> _downloaderTasks = [];

  // 待确认的下载任务
  List<DownloadTask> _pendingTasks = [];
  StreamSubscription<DownloadTask>? _downloaderSubscription;

  @override
  void initState() {
    super.initState();
    initMethod();

    // 监听新下载器进度
    _downloaderSubscription = downloadStore.progressStream.listen((progress) {
      if (mounted) {
        _updateDownloaderTasks();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _timer?.cancel();
    _downloaderSubscription?.cancel();
    super.dispose();
  }

  void _updateDownloaderTasks() async {
    if (mounted) {
      setState(() {
        _downloaderTasks = downloadStore.downloadingTasks.values.toList();
      });
    }
  }

  initMethod() async {
    _updateDownloaderTasks();
    _timer = Timer.periodic(Duration(seconds: 1), (time) {
      _updateDownloaderTasks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(I18n.of(context).task_progress),
        actions: [
          IconButton(
              onPressed: () {
                setState(() {
                  _itemSimple = !_itemSimple;
                });
              },
              icon: (_itemSimple ? Icon(Icons.hide_image) : Icon(Icons.image))),
          buildIconButton(context),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_buildTopChip(), Expanded(child: _body())],
        ),
      ),
    );
  }

  IconButton buildIconButton(BuildContext context) {
    return IconButton(
        icon: Icon(Icons.more_vert),
        onPressed: () async {
          await showModalBottomSheet(
              context: context,
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(16.0))),
              builder: (_) {
                return SafeArea(
                  child: Column(
                    children: <Widget>[
                      ListTile(
                        title: Text(I18n.of(context).retry_seed_task),
                        onTap: () async {
                          downloadStore.addDownloadTasks(_pendingTasks);
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                    mainAxisSize: MainAxisSize.min,
                  ),
                );
              });
          initMethod();
        });
  }

  int currentIndex = 0;

  Widget _buildTopChip() {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0),
      child: SortGroup(
        children: [
          I18n.of(context).all,
          I18n.of(context).running,
          I18n.of(context).complete,
          I18n.of(context).failed,
        ],
        onChange: (index) {
          _scrollController.jumpTo(0);
          setState(() {
            this.currentIndex = index;
          });
        },
      ),
    );
  }

  Widget _body() {
    // 合并正在下载和待确认的任务
    List<DownloadTask> allTasks = [..._downloaderTasks];

    // 根据当前选中的标签过滤任务
    List<DownloadTask> filteredTasks = allTasks;
    if (currentIndex == 1) {
      // 只显示正在运行的任务
      filteredTasks = _downloaderTasks
          .where((t) =>
              t.status == DownloadTaskStatus.pending ||
              t.status == DownloadTaskStatus.downloading)
          .toList();
    } else if (currentIndex == 0) {
      // 显示所有任务
      filteredTasks = allTasks;
    }

    if (filteredTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "[ ]",
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium!
                  .copyWith(fontSize: 24),
            ),
            SizedBox(height: 16),
            if (currentIndex == 0)
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DownloadedPage()),
                  );
                },
                icon: Icon(Icons.folder_open),
                label: Text(I18n.of(context).history),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: filteredTasks.length,
      itemBuilder: (context, index) {
        final task = filteredTasks[index];
        final isPending = _pendingTasks.contains(task);
        return _buildNewDownloaderItem(task, isPending: isPending);
      },
    );
  }

  Widget _buildNewDownloaderItem(DownloadTask task, {bool isPending = false}) {
    final illusts = task.illusts;
    final progress = task.total > 0 ? task.received / task.total : 0.0;
    final isRunning = task.status == DownloadTaskStatus.downloading ||
        task.status == DownloadTaskStatus.pending;
    final isFailed = task.status == DownloadTaskStatus.failed;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12))),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IllustLightingPage(id: illusts.id),
            ),
          );
        },
        child: Stack(
          children: [
            Row(
              children: [
                if (!_itemSimple)
                  Container(
                    height: 100,
                    width: 100,
                    child: Stack(
                      children: [
                        PixivImage(
                          illusts.imageUrls.medium,
                          fit: BoxFit.cover,
                          height: 100,
                          width: 100,
                        ),
                        if (isRunning && !isPending)
                          Container(
                            height: 100,
                            width: 100,
                            child: Center(
                              child: CircularProgressIndicator(
                                value: progress > 0 ? progress : null,
                                backgroundColor: Colors.grey[200],
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  Container(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  if (isPending)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(right: 8.0),
                                      child: Icon(
                                        Icons.pause_circle_outline,
                                        size: 16,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      '${illusts.title} (p${task.part})',
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_itemSimple) ...[
                            if (isPending)
                              InkWell(
                                onTap: () async {
                                  await downloadStore.addDownloadTasks([task]);
                                  _updateDownloaderTasks();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Icon(Icons.play_arrow,
                                      color: Colors.green),
                                ),
                              )
                            else if (isFailed)
                              InkWell(
                                onTap: () {
                                  downloadStore.retryTask(task.taskKey);
                                },
                                child: Icon(Icons.refresh),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: InkWell(
                                onTap: () {
                                  if (isPending) {
                                    downloadStore
                                        .clearPendingTasks([task.taskKey]);
                                  } else {
                                    downloadStore.cancelTask(task.taskKey);
                                  }
                                  _updateDownloaderTasks();
                                },
                                child: Icon(Icons.delete),
                              ),
                            ),
                          ],
                          if (!isPending)
                            Padding(
                              padding: const EdgeInsets.only(right: 16.0),
                              child: _buildNewDownloaderStatus(task.status),
                            ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          illusts.user.name,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge!
                              .copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 12,
                              ),
                        ),
                      ),
                      if (!_itemSimple)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(" "),
                            Row(
                              children: [
                                if (isPending)
                                  IconButton(
                                    onPressed: () async {
                                      await downloadStore
                                          .addDownloadTasks([task]);
                                      _updateDownloaderTasks();
                                    },
                                    icon: Icon(Icons.play_arrow,
                                        color: Colors.green),
                                  )
                                else if (isFailed)
                                  IconButton(
                                    onPressed: () {
                                      downloadStore.retryTask(task.taskKey);
                                    },
                                    icon: Icon(Icons.refresh),
                                  ),
                                IconButton(
                                  onPressed: () {
                                    if (isPending) {
                                      downloadStore
                                          .clearPendingTasks([task.taskKey]);
                                    } else {
                                      downloadStore.cancelTask(task.taskKey);
                                    }
                                    _updateDownloaderTasks();
                                  },
                                  icon: Icon(Icons.delete),
                                ),
                              ],
                            ),
                          ],
                        )
                      else
                        Container(height: 10),
                    ],
                  ),
                ),
              ],
            ),
            if (isRunning && !isPending)
              Positioned(
                left: 0.0,
                right: 0.0,
                bottom: 0.0,
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  backgroundColor: Colors.grey[200],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewDownloaderStatus(DownloadTaskStatus status) {
    switch (status) {
      case DownloadTaskStatus.pending:
        return Text(
          'seed',
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 12),
        );
      case DownloadTaskStatus.downloading:
        return Text(
          I18n.of(context).running,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 12),
        );
      case DownloadTaskStatus.completed:
        return Icon(Icons.check_circle, color: Colors.green, size: 16);
      case DownloadTaskStatus.paused:
        return Text(
          I18n.of(context).paused,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 12),
        );
      case DownloadTaskStatus.failed:
        return Icon(Icons.error, size: 16);
      case DownloadTaskStatus.deleted:
        return const SizedBox();
    }
  }
}
