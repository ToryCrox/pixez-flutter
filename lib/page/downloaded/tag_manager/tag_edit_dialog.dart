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

  @override
  void initState() {
    super.initState();
    _customTranslateController = TextEditingController(text: widget.tag.customTranslatedName);
    _selectedCategory = widget.tag.categoryEnum;
    _isBookmarked = widget.tag.isBookmarked;
    _displayOrder = widget.tag.displayOrder;
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
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('原名', widget.tag.name),
            if (widget.tag.translatedName.isNotEmpty)
              _buildInfoRow('官方翻译', widget.tag.translatedName),
            const SizedBox(height: 16),
            TextField(
              controller: _customTranslateController,
              decoration: const InputDecoration(
                labelText: '自定义翻译',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('分类', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8.0,
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
          Expanded(child: Text(value)),
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
