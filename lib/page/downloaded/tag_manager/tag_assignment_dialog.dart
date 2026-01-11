import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/main.dart'; // tagManagerStore

class TagAssignmentDialog extends StatefulWidget {
  final int illustId;

  const TagAssignmentDialog({super.key, required this.illustId});

  @override
  State<TagAssignmentDialog> createState() => _TagAssignmentDialogState();
}

class _TagAssignmentDialogState extends State<TagAssignmentDialog> {
  List<String> _assignedTags = [];
  bool _isLoading = true;
  final TextEditingController _newTagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAssignedTags();
    // Ensure stores are loaded
    if (tagManagerStore.tags.isEmpty) {
      tagManagerStore.loadTags();
    }
  }

  Future<void> _loadAssignedTags() async {
    final tags = await tagManagerStore.getTagsForIllust(widget.illustId);
    if (mounted) {
      setState(() {
        _assignedTags = tags;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑标签'),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _newTagController,
                    decoration: InputDecoration(
                      labelText: '添加新标签',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _addNewTag,
                      ),
                    ),
                    onSubmitted: (_) => _addNewTag(),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('已分配标签:', style: TextStyle(fontWeight: FontWeight.bold)),
                          Wrap(
                            spacing: 8.0,
                            children: _assignedTags.map((tagName) {
                              return Chip(
                                label: Text(tagName),
                                onDeleted: () => _removeTag(tagName),
                              );
                            }).toList(),
                          ),
                          const Divider(),
                          const Text('所有标签:', style: TextStyle(fontWeight: FontWeight.bold)),
                          Observer(builder: (context) {
                            return Wrap(
                              spacing: 8.0,
                              children: tagManagerStore.tags.where((t) => !_assignedTags.contains(t.tag.name)).map((data) {
                                return ActionChip(
                                  label: Text(data.tag.displayName),
                                  onPressed: () => _addTag(data.tag.name),
                                );
                              }).toList(),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _addTag(String tagName) async {
    if (_assignedTags.contains(tagName)) return;
    await tagManagerStore.addCustomTagToIllust(widget.illustId, tagName);
    setState(() {
      _assignedTags.add(tagName);
    });
  }

  Future<void> _addNewTag() async {
    final text = _newTagController.text.trim();
    if (text.isEmpty) return;
    await _addTag(text);
    _newTagController.clear();
    // reload store tags if it's new
     tagManagerStore.loadTags();
  }

  Future<void> _removeTag(String tagName) async {
    await tagManagerStore.removeCustomTagFromIllust(widget.illustId, tagName);
    setState(() {
      _assignedTags.remove(tagName);
    });
  }
}
