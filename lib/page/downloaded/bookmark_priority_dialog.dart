/*
 * Copyright (C) 2024. by perol_notsf, All rights reserved
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
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/store/download_store.dart';

class BookmarkPriorityDialog extends StatefulWidget {
  final List<DownloadedIllust>? illusts;
  final Function(int illustId, int bookmark)? onUpdate;
  final Function(int priority)? onPrioritySelected;

  const BookmarkPriorityDialog({
    Key? key,
    this.illusts,
    this.onUpdate,
    this.onPrioritySelected,
  }) : super(key: key);

  @override
  State<BookmarkPriorityDialog> createState() => _BookmarkPriorityDialogState();

  static Future<void> show(
    BuildContext context, {
    required List<DownloadedIllust> illusts,
    Function(int illustId, int bookmark)? onUpdate,
  }) {
    return showDialog(
      context: context,
      builder: (context) => BookmarkPriorityDialog(
        illusts: illusts,
        onUpdate: onUpdate,
      ),
    );
  }
}

class _BookmarkPriorityDialogState extends State<BookmarkPriorityDialog> {
  late int _tempBookmark;

  @override
  void initState() {
    super.initState();
    // 如果是单个作品，初始值为当前收藏值；如果是多个，默认为 1；如果没有作品，默认为 1
    if (widget.illusts != null && widget.illusts!.length == 1) {
      _tempBookmark = widget.illusts!.first.bookmark;
    } else {
      _tempBookmark = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBatch = (widget.illusts?.length ?? 0) > 1;
    final title = isBatch
        ? '批量设置收藏优先级 (${widget.illusts!.length})'
        : '设置插画收藏优先级';
    
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(isBatch
              ? '将选中的 ${widget.illusts!.length} 个作品设为相同优先级。\n0 表示取消收藏。'
              : '数值越大优先级越高 (0-99)。\n0 表示取消收藏。'),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '优先级: ${_tempBookmark.toInt()}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (_tempBookmark > 0)
                const Icon(Icons.favorite, color: Colors.red),
            ],
          ),
          Slider(
            value: _tempBookmark.toDouble(),
            min: 0,
            max: 99,
            divisions: 99,
            label: _tempBookmark.toString(),
            onChanged: (double value) {
              setState(() {
                _tempBookmark = value.round();
              });
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () => setState(() => _tempBookmark = 0),
                child: const Text('取消(0)'),
              ),
              TextButton(
                onPressed: () => setState(() => _tempBookmark = 1),
                child: const Text('默认(1)'),
              ),
              TextButton(
                onPressed: () => setState(() => _tempBookmark = 99),
                child: const Text('置顶(99)'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (widget.onPrioritySelected != null) {
              widget.onPrioritySelected!(_tempBookmark);
            } else if (widget.illusts != null) {
              for (var illust in widget.illusts!) {
                if (widget.onUpdate != null) {
                  widget.onUpdate!(illust.illustId, _tempBookmark);
                } else {
                  await downloadStore.updateIllustBookmark(illust.illustId, _tempBookmark);
                }
              }
            }
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
