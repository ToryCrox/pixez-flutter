import 'package:flutter/material.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/main.dart';
import 'tag_manager_page.dart';
import 'tag_selection_dialog.dart';
import 'parent_selection_dialog.dart';
import '../downloaded_page.dart';

class TagEditDialog extends StatefulWidget {
  final DownloadedTag tag;
  final List<TagDisplayData>? comicTags;

  const TagEditDialog({super.key, required this.tag, this.comicTags});

  @override
  State<TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<TagEditDialog> {
  late TextEditingController _customTranslateController;
  late TagCategory _selectedCategory;
  late bool _isBookmarked;
  late int _displayOrder;
  late List<TagDisplayData> _equivalenceGroup;
  late int _parentId;
  late List<TagDisplayData> _childTags;
  bool _isTranslating = false;

  @override
  void initState() {
    super.initState();
    _customTranslateController = TextEditingController(
      text: widget.tag.customTranslatedName,
    );
    _selectedCategory = widget.tag.categoryEnum;
    _isBookmarked = widget.tag.isBookmarked;
    _displayOrder = widget.tag.displayOrder;
    _equivalenceGroup = tagManagerStore.getEquivalenceGroup(widget.tag.id);
    _parentId = widget.tag.parentId;
    // 加载子标签
    _childTags = tagManagerStore.getDirectChildren(widget.tag.id);
  }

  @override
  void dispose() {
    _customTranslateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑标签'),
      content: SizedBox(
        width: 400, // 固定最大宽度
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('原名', widget.tag.name),
              if (widget.tag.translatedName.isNotEmpty)
                _buildInfoRow('官方翻译', widget.tag.translatedName),
              if (widget.tag.count > 0)
                _buildInfoRow('插画数量', widget.tag.count.toString()),
              const SizedBox(height: 16),
              TextField(
                controller: _customTranslateController,
                decoration: InputDecoration(
                  labelText: '自定义翻译',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'AI 翻译',
                    onPressed: _isTranslating ? null : _translateWithAi,
                    icon:
                        _isTranslating
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.auto_awesome),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildParentRow(),
              _buildEquivalenceGroup(),
              _buildChildrenRow(),
              const SizedBox(height: 16),
              const Text('分类', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children:
                    TagCategory.values
                        .where((e) => e != TagCategory.uncategorized)
                        .map((category) {
                          return ChoiceChip(
                            label: Text(category.label),
                            selected: _selectedCategory == category,
                            onSelected: (bool selected) {
                              setState(() {
                                _selectedCategory =
                                    selected
                                        ? category
                                        : TagCategory.uncategorized;
                              });
                            },
                          );
                        })
                        .toList(),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('收藏'),
                value: _isBookmarked,
                onChanged: (bool value) {
                  setState(() {
                    _isBookmarked = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              const Text(
                '优先级 (负数沉底，正数置顶)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Slider(
                value: _displayOrder.toDouble().clamp(-10.0, 10.0),
                min: -10,
                max: 10,
                divisions: 20,
                label: _displayOrder.toString(),
                onChanged: (double value) {
                  setState(() {
                    _displayOrder = value.round();
                  });
                },
              ),
              Center(child: Text('当前优先级: $_displayOrder')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  Widget _buildEquivalenceGroup() {
    // 排除当前标签
    final otherTags =
        _equivalenceGroup.where((td) => td.tag.id != widget.tag.id).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '关联标签: ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              if (widget.tag.referencedTagId == 0 && otherTags.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    border: Border.all(color: Colors.blue, width: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '主标签',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Spacer(),
              if (widget.comicTags != null && widget.comicTags!.isNotEmpty)
                TextButton.icon(
                  onPressed: _showTagSelectionDialog,
                  icon: const Icon(Icons.add_link, size: 16),
                  label: const Text('添加关联', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
            ],
          ),
          if (otherTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children:
                    otherTags.map((td) {
                      final t = td.tag;
                      // 判断是否为主标签（大师标签的 referencedTagId 为 0）
                      final isPrimary = t.referencedTagId == 0;

                      // 构建显示文本：原名 + (翻译) + [数量]
                      final namePart = t.name;
                      final translatePart =
                          t.displayTranslatedName.isNotEmpty
                              ? ' (${t.displayTranslatedName})'
                              : '';
                      final countPart = ' [${t.count}]';

                      final labelText = '$namePart$translatePart$countPart';

                      return ActionChip(
                        onPressed: () {
                          DownloadedPage.open(context, tagId: t.id);
                        },
                        label: Text(
                          labelText,
                          style: TextStyle(
                            fontSize: 11,
                            // 主标签使用蓝色加粗，别名标签使用默认样式
                            color: isPrimary ? Colors.blue : null,
                            fontWeight: isPrimary ? FontWeight.bold : null,
                          ),
                        ),
                        // 主标签背景色稍微淡一点以区分
                        backgroundColor:
                            isPrimary ? Colors.blue.withOpacity(0.1) : null,
                        side:
                            isPrimary
                                ? const BorderSide(
                                  color: Colors.blue,
                                  width: 0.5,
                                )
                                : null,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      );
                    }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建子标签预览行
  Widget _buildChildrenRow() {
    if (_childTags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '子标签: ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              Text(
                '${_childTags.length}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Spacer(),
              // 跳转子标签页按钮
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(); // 先关闭对话框
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => TagManagerPage(initialParentId: widget.tag.id),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('查看全部', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 单行横向滚动显示子标签
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _childTags.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final child = _childTags[index].tag;
                return ActionChip(
                  onPressed: () {
                    DownloadedPage.open(context, tagId: child.id);
                  },
                  label: Text(
                    '${child.displayName} (${child.count})',
                    style: TextStyle(
                      fontSize: 11,
                      color: child.categoryEnum.color,
                    ),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTagSelectionDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => TagSelectionDialog(
            comicTags: widget.comicTags!,
            currentGroup: _equivalenceGroup,
            currentTagId: widget.tag.id,
          ),
    );

    if (result == true) {
      // 重新加载等效组
      setState(() {
        _equivalenceGroup = tagManagerStore.getEquivalenceGroup(widget.tag.id);
      });
    }
  }

  Widget _buildParentRow() {
    final parent =
        _parentId != 0
            ? tagManagerStore.getTagDisplayDataByID(_parentId)?.tag
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('归属作品', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: _showParentSelectionDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_tree,
                  size: 16,
                  color: Colors.blueGrey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    parent != null ? parent.displayName : '无 (点击设置)',
                    style: TextStyle(
                      color: parent != null ? Colors.blue : Colors.grey,
                    ),
                  ),
                ),
                if (parent != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      setState(() => _parentId = 0);
                    },
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                const Icon(Icons.chevron_right, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showParentSelectionDialog() async {
    await ParentSelectionDialog.show(
      context,
      tags: [widget.tag],
      currentParentId: _parentId,
      onUpdated: () {
        if (mounted) {
          setState(() {
            final updatedTag =
                tagManagerStore.getTagDisplayDataByID(widget.tag.id)?.tag;
            if (updatedTag != null) {
              _parentId = updatedTag.parentId;
              _customTranslateController.text =
                  updatedTag.customTranslatedName ?? '';
            }
          });
        }
      },
    );
  }

  void _save() {
    final newTag = widget.tag.copyWith(
      customTranslatedName: _customTranslateController.text.trim(),
      category: _selectedCategory.value,
      isBookmarked: _isBookmarked,
      displayOrder: _displayOrder,
      parentId: _parentId,
    );
    tagManagerStore.updateTag(newTag);
    Navigator.of(context).pop();
  }

  Future<void> _translateWithAi() async {
    setState(() => _isTranslating = true);
    try {
      final translated = await aiTranslationService.translateTag(
        tagName: widget.tag.name,
        officialTranslation: widget.tag.translatedName,
      );
      if (mounted) {
        setState(() => _customTranslateController.text = translated);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }
}
