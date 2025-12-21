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

import 'package:flutter/material.dart';
import 'package:pixez/store/download_store.dart';

enum OptimizeDialogState {
  confirm,    // 确认阶段
  optimizing, // 优化中
  completed,  // 完成
  error,      // 错误
}

/// 合并的优化对话框（包含确认、进度、结果）
class _OptimizeDialog extends StatefulWidget {
  final DownloadStore downloadStore;

  const _OptimizeDialog({
    Key? key,
    required this.downloadStore,
  }) : super(key: key);

  @override
  State<_OptimizeDialog> createState() => _OptimizeDialogState();
}

class _OptimizeDialogState extends State<_OptimizeDialog> {
  OptimizeDialogState _state = OptimizeDialogState.confirm;
  int _current = 0;
  int _total = 0;
  int _savedBytes = 0;
  int _optimizedCount = 0;
  String? _errorMessage;
  bool _isCancelled = false;
  bool _isVacuuming = false;

  void _startOptimize() async {
    setState(() {
      _state = OptimizeDialogState.optimizing;
      _isCancelled = false;
    });

    try {
      final result = await widget.downloadStore.optimizeIllustJson(
        onProgress: (int current, int total, int savedBytes) {
          if (mounted && !_isCancelled) {
            setState(() {
              _current = current;
              _total = total;
              _savedBytes = savedBytes;
            });
          }
        },
        shouldCancel: () => _isCancelled,
        onVacuumStart: () {
          if (mounted && !_isCancelled) {
            setState(() {
              _isVacuuming = true;
            });
          }
        },
      );

      if (mounted) {
        _optimizedCount = result['optimized_count'] ?? 0;
        _savedBytes = result['saved_bytes'] ?? 0;
        
        // 显示完成状态
        setState(() {
          _state = OptimizeDialogState.completed;
          _isVacuuming = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // 如果是取消操作，不显示错误
        if (_isCancelled) {
          Navigator.of(context).pop();
          return;
        }
        setState(() {
          _state = OptimizeDialogState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _cancelOptimize() {
    setState(() {
      _isCancelled = true;
    });
    Navigator.of(context).pop();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    List<Widget> actions = [];

    switch (_state) {
      case OptimizeDialogState.confirm:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('此操作将优化数据库中的 illustJson 字段，移除重复存储的数据。'),
            SizedBox(height: 8),
            Text('同时会将图片 URL 提取为独立字段，提升列表加载性能。'),
            SizedBox(height: 8),
            Text('优化后可以显著减少数据库文件大小。'),
            SizedBox(height: 8),
            Text(
              '注意：此操作可能需要一些时间，请确保应用在运行过程中不会被关闭。',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );
        actions = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: _startOptimize,
            child: Text('确认优化'),
          ),
        ];
        break;

      case OptimizeDialogState.optimizing:
        final progressValue = _total > 0 ? _current / _total : 0.0;
        final percentage = _total > 0 ? (progressValue * 100).toStringAsFixed(1) : '0.0';

        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isVacuuming) ...[
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在回收数据库空间...'),
              SizedBox(height: 8),
              Text(
                '执行 VACUUM 操作，这可能需要一些时间',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ] else if (_total > 0) ...[
              LinearProgressIndicator(value: progressValue),
              SizedBox(height: 16),
              Text('正在优化数据库...'),
              SizedBox(height: 12),
              Text(
                '进度: $_current / $_total ($percentage%)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.storage, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '已节省: ${_formatBytes(_savedBytes)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在优化数据库...'),
              SizedBox(height: 8),
              Text(
                '请稍候，此操作可能需要一些时间',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        );
        actions = [
          TextButton(
            onPressed: _cancelOptimize,
            child: Text('取消'),
          ),
        ];
        break;

      case OptimizeDialogState.completed:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 24),
                SizedBox(width: 8),
                Text(
                  '优化完成',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text('优化了 $_optimizedCount 条记录'),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.storage, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '节省了 ${_formatBytes(_savedBytes)} 存储空间',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        actions = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('确定'),
          ),
        ];
        break;

      case OptimizeDialogState.error:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 24),
                SizedBox(width: 8),
                Text(
                  '优化失败',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text('优化过程中发生错误：'),
            SizedBox(height: 8),
            Text(
              _errorMessage ?? '未知错误',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        );
        actions = [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('确定'),
          ),
        ];
        break;
    }

    return AlertDialog(
      title: Text('优化数据库存储'),
      content: content,
      actions: actions,
    );
  }
}

/// 显示优化数据库存储对话框
class OptimizeJsonDialog {
  /// 显示优化对话框并执行优化
  static Future<void> show(BuildContext context, DownloadStore downloadStore) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _OptimizeDialog(downloadStore: downloadStore),
    );
  }
}
