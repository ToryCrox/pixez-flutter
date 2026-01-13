import 'package:flutter/material.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';

class TagSelectionDialog extends StatefulWidget {
  final List<TagDisplayData> comicTags;
  final List<DownloadedTag> currentGroup;
  final int currentTagId;

  const TagSelectionDialog({
    super.key,
    required this.comicTags,
    required this.currentGroup,
    required this.currentTagId,
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
    for (final t in widget.currentGroup) {
      _selectedTagIds.add(t.id);
      if (t.referencedTagId == null) {
        _primaryId = t.id;
      }
    }
    // 确保当前编辑的标签本身被选中
    _selectedTagIds.add(widget.currentTagId);
    // 默认主标签
    _primaryId ??= widget.currentTagId;

    // 2. 构造显示列表 (优先显示已关联的组员)
    final Map<int, TagDisplayData> allTagsMap = {};
    
    // 首先添加关联组的所有成员
    for (final t in widget.currentGroup) {
      if (!allTagsMap.containsKey(t.id)) {
        allTagsMap[t.id] = tagManagerStore.tagIdMap[t.id] ?? 
            TagDisplayData(tag: t, previewIllusts: []);
      }
    }

    // 然后添加漫画中的其他标签
    for (final td in widget.comicTags) {
      if (!allTagsMap.containsKey(td.tag.id)) {
        allTagsMap[td.tag.id] = td;
      }
    }

    _displayTags.clear();
    _displayTags.addAll(allTagsMap.values);
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
              child: RadioGroup<int>(
                groupValue: _primaryId,
                onChanged: (val) {
                  setState(() {
                    _primaryId = val;
                  });
                },
                child: ListView.builder(
                  itemCount: _displayTags.length,
                  itemBuilder: (context, index) {
                    final comicTag = _displayTags[index].tag;
                    final isSelected = _selectedTagIds.contains(comicTag.id);
                    final isPrimary = _primaryId == comicTag.id;

                    // 获取显示名称
                    final displayName =
                        comicTag.customTranslatedName?.isNotEmpty == true
                            ? comicTag.customTranslatedName
                            : (comicTag.translatedName.isNotEmpty
                                ? comicTag.translatedName
                                : null);

                    return CheckboxListTile(
                      title: Row(
                        children: [
                          Expanded(child: Text(comicTag.name)),
                          if (isSelected) 
                            Radio<int>(
                              value: comicTag.id,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      subtitle: displayName != null ? Text(displayName) : null,
                      value: isSelected,
                      secondary: isPrimary 
                          ? const Icon(Icons.star, color: Colors.orange, size: 16)
                          : null,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedTagIds.add(comicTag.id);
                          } else {
                            _selectedTagIds.remove(comicTag.id);
                            if (_primaryId == comicTag.id) {
                              _primaryId = widget.currentTagId;
                            }
                          }
                        });
                      },
                    );
                  },
                ),
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

      if (!allIds.contains(widget.currentTagId)) {
        allIds.add(widget.currentTagId);
      }

      // 如果选定的主标签不在勾选列表中，自动修正（虽然 UI 已经做了限制，但逻辑上兜底）
      int finalPrimaryId = _primaryId ?? widget.currentTagId;
      if (!allIds.contains(finalPrimaryId)) {
        finalPrimaryId = widget.currentTagId;
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
