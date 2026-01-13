import 'package:flutter/material.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';

class TagSelectionDialog extends StatefulWidget {
  final List<TagDisplayData> comicTags; // 备选标签池
  final List<TagDisplayData>? currentGroup; // 当前已有的族群（可选）
  final int? currentTagId; // 当前主要编辑的标签 ID（可选）

  const TagSelectionDialog({
    super.key,
    required this.comicTags,
    this.currentGroup,
    this.currentTagId,
  });

  @override
  State<TagSelectionDialog> createState() => _TagSelectionDialogState();
}

class _TagSelectionDialogState extends State<TagSelectionDialog> {
  // 使用 ID 集合来跟踪选中状态
  final Set<int> _selectedTagIds = {};
  final List<TagDisplayData> _displayTags = [];
  int? _primaryId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() {
    // 1. 初始化选中状态和主标签提示
    final group = widget.currentGroup ?? [];
    for (final td in group) {
      final t = td.tag;
      _selectedTagIds.add(t.id);
      if (t.referencedTagId == null) {
        _primaryId = t.id;
      }
    }

    // 如果指定了当前标签，确保它被选中
    if (widget.currentTagId != null) {
      _selectedTagIds.add(widget.currentTagId!);
      // 默认主标签
      _primaryId ??= widget.currentTagId;
    }

    // 2. 构造显示列表 (优先显示已关联的组员)
    final Map<int, TagDisplayData> allTagsMap = {};

    // 首先添加关联组的所有成员
    for (final td in group) {
      if (!allTagsMap.containsKey(td.tag.id)) {
        allTagsMap[td.tag.id] = td;
      }
    }

    // 然后添加提供的所有备选标签
    for (final td in widget.comicTags) {
      if (!allTagsMap.containsKey(td.tag.id)) {
        allTagsMap[td.tag.id] = td;
      }
    }

    _displayTags.clear();
    _displayTags.addAll(allTagsMap.values);

    // 兜底：如果没有设定主标签，取列表中第一个选中的
    if (_primaryId == null && _selectedTagIds.isNotEmpty) {
      _primaryId = _selectedTagIds.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择要关联的标签'),
      content: SizedBox(
        width: 360,
        height: 450,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Text(
                '勾选以关联，单选以设定主标签',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _displayTags.length,
                itemBuilder: (context, index) {
                  final comicTag = _displayTags[index].tag;
                  final isSelected = _selectedTagIds.contains(comicTag.id);

                  // 获取显示名称
                  final displayName = comicTag.displayTranslatedName;

                  return CheckboxListTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: comicTag.name),
                                    TextSpan(
                                      text: ' (${comicTag.count})',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).disabledColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (displayName.isNotEmpty)
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Radio<int>(
                            value: comicTag.id,
                            groupValue: _primaryId,
                            onChanged: (val) {
                              setState(() {
                                _primaryId = val;
                              });
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedTagIds.add(comicTag.id);
                        } else {
                          _selectedTagIds.remove(comicTag.id);
                           if (_primaryId == comicTag.id) {
                             final currentGroup = widget.currentGroup ?? [];
                             _primaryId = widget.currentTagId ?? (currentGroup.isNotEmpty ? currentGroup.first.tag.id : null);
                           }
                         }
                       });
                     },
                   );
                 },
               ),
             ),
           ],
         ),
       ),
       actions: [
         TextButton(
           onPressed: () => Navigator.pop(context),
           child: const Text('取消'),
         ),
         ElevatedButton(
           onPressed: _isLoading ? null : _confirm,
           child: const Text('确定'),
         ),
       ],
     );
   }
 
   Future<void> _confirm() async {
     setState(() => _isLoading = true);
 
     try {
       final List<int> allIds = _selectedTagIds.toList();
 
       // 如果选定的主标签不在勾选列表中，自动修正（虽然 UI 已经做了限制，但逻辑上兜底）
       int? finalPrimaryId = _primaryId;
 
       if (finalPrimaryId == null) {
         if (allIds.isNotEmpty) {
           finalPrimaryId = allIds.first;
         } else {
           throw Exception('请至少选择一个标签作为本组的主标签');
         }
       }
 
       if (!allIds.contains(finalPrimaryId)) {
          allIds.add(finalPrimaryId);
       }
 
       await tagManagerStore.updateEquivalenceGroup(finalPrimaryId, allIds);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('关联失败: $e')));
        setState(() => _isLoading = false);
      }
    }
  }
}
