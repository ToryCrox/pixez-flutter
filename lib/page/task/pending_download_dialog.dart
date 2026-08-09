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
import 'package:pixez/store/download_store.dart';

/// 待下载任务确认对话框
class PendingDownloadDialog extends StatefulWidget {
  final List<DownloadTask> tasks;

  const PendingDownloadDialog({Key? key, required this.tasks})
    : super(key: key);

  @override
  State<PendingDownloadDialog> createState() => _PendingDownloadDialogState();
}

class _PendingDownloadDialogState extends State<PendingDownloadDialog> {
  late Set<String> _selectedTaskKeys;

  @override
  void initState() {
    super.initState();
    // 默认全选
    _selectedTaskKeys = widget.tasks.map((t) => t.taskKey).toSet();
  }

  @override
  Widget build(BuildContext context) {
    // 按插画分组
    final Map<int, List<DownloadTask>> groupedTasks = {};
    for (final task in widget.tasks) {
      groupedTasks.putIfAbsent(task.illusts.id, () => []).add(task);
    }

    return AlertDialog(
      title: Text('继续下载'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '发现 ${widget.tasks.length} 个待下载任务',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: groupedTasks.length,
                itemBuilder: (context, index) {
                  final illustId = groupedTasks.keys.elementAt(index);
                  final tasks = groupedTasks[illustId]!;
                  final illusts = tasks.first.illusts;
                  final allSelected = tasks.every(
                    (t) => _selectedTaskKeys.contains(t.taskKey),
                  );

                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: SizedBox(
                        width: 60,
                        height: 60,
                        child: PixivImage(
                          illusts.imageUrls.medium,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(
                        illusts.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${illusts.user.name} · ${tasks.length} ${tasks.length > 1 ? "页" : "页"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Checkbox(
                        value: allSelected,
                        tristate: true,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              // 全选
                              for (final task in tasks) {
                                _selectedTaskKeys.add(task.taskKey);
                              }
                            } else {
                              // 全不选
                              for (final task in tasks) {
                                _selectedTaskKeys.remove(task.taskKey);
                              }
                            }
                          });
                        },
                      ),
                      onTap: () {
                        setState(() {
                          if (allSelected) {
                            // 全不选
                            for (final task in tasks) {
                              _selectedTaskKeys.remove(task.taskKey);
                            }
                          } else {
                            // 全选
                            for (final task in tasks) {
                              _selectedTaskKeys.add(task.taskKey);
                            }
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(<String>[]);
          },
          child: Text('全部取消'),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              if (_selectedTaskKeys.length == widget.tasks.length) {
                _selectedTaskKeys.clear();
              } else {
                _selectedTaskKeys = widget.tasks.map((t) => t.taskKey).toSet();
              }
            });
          },
          child: Text(
            _selectedTaskKeys.length == widget.tasks.length ? '取消全选' : '全选',
          ),
        ),
        FilledButton(
          onPressed:
              _selectedTaskKeys.isEmpty
                  ? null
                  : () {
                    Navigator.of(context).pop(_selectedTaskKeys.toList());
                  },
          child: Text('继续下载 (${_selectedTaskKeys.length})'),
        ),
      ],
    );
  }
}
