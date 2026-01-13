import 'package:flutter/material.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/main.dart';
// import 'package:pixez/i18n.dart'; // Unused

class TagEditDialog extends StatefulWidget {
  final DownloadedTag tag;

  const TagEditDialog({super.key, required this.tag});

  @override
  State<TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<TagEditDialog> {
  late TextEditingController _customTranslateController;
  late TagCategory _selectedCategory;
  late bool _isBookmarked;
  late int _displayOrder;
  late List<DownloadedTag> _equivalenceGroup;

  @override
  void initState() {
    super.initState();
    _customTranslateController = TextEditingController(text: widget.tag.customTranslatedName);
    _selectedCategory = widget.tag.categoryEnum;
    _isBookmarked = widget.tag.isBookmarked;
    _displayOrder = widget.tag.displayOrder;
    _equivalenceGroup = tagManagerStore.getEquivalenceGroup(widget.tag.id);
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
                decoration: const InputDecoration(
                  labelText: '自定义翻译',
                  border: OutlineInputBorder(),
                ),
              ),
              _buildEquivalenceGroup(),
              const SizedBox(height: 16),
              const Text('分类', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: TagCategory.values.where((e) => e != TagCategory.uncategorized).map((category) {
                  return ChoiceChip(
                    label: Text(category.label),
                    selected: _selectedCategory == category,
                    onSelected: (bool selected) {
                      setState(() {
                        _selectedCategory = selected ? category : TagCategory.uncategorized;
                      });
                    },
                  );
                }).toList(),
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
              const Text('优先级 (负数沉底，正数置顶)', style: TextStyle(fontWeight: FontWeight.bold)),
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
        ElevatedButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  Widget _buildEquivalenceGroup() {
    if (_equivalenceGroup.isEmpty) {
      return const SizedBox.shrink();
    }

    // 排除当前标签
    final otherTags = _equivalenceGroup.where((t) => t.id != widget.tag.id).toList();
    if (otherTags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('关联标签: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: otherTags.map((t) {
                final customName = t.customTranslatedName ?? '';
                final displayName = customName.isNotEmpty
                    ? customName
                    : (t.translatedName.isNotEmpty ? t.translatedName : t.name);
                return Chip(
                  label: Text(displayName, style: const TextStyle(fontSize: 12)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final newTag = widget.tag.copyWith(
      customTranslatedName: _customTranslateController.text.trim(),
      category: _selectedCategory.value,
      isBookmarked: _isBookmarked,
      displayOrder: _displayOrder,
    );
    tagManagerStore.updateTag(newTag);
    Navigator.of(context).pop();
  }
}
