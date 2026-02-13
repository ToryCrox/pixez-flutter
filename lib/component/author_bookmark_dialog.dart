import 'package:flutter/material.dart';

/// 显示作者收藏/优先级设置对话框
///
/// 返回用户选择的 bookmark 值（0-99），取消时返回 null
Future<int?> showAuthorBookmarkDialog(
  BuildContext context, {
  required int currentBookmark,
}) {
  int tempBookmark = currentBookmark;
  return showDialog<int>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('设置已收藏作者/优先级'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('数值越大优先级越高 (0-99)。\n0 表示取消收藏。'),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '优先级: ${tempBookmark.toInt()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (tempBookmark > 0)
                      const Icon(Icons.favorite, color: Colors.red),
                  ],
                ),
                Slider(
                  value: tempBookmark.toDouble(),
                  min: 0,
                  max: 99,
                  divisions: 99,
                  label: tempBookmark.toString(),
                  onChanged: (double value) {
                    setState(() {
                      tempBookmark = value.round();
                    });
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => tempBookmark = 0),
                      child: const Text('取消收藏(0)'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => tempBookmark = 1),
                      child: const Text('默认(1)'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => tempBookmark = 99),
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
                onPressed: () {
                  Navigator.pop(context, tempBookmark);
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
    },
  );
}
