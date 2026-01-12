import 'package:flutter/material.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';

class TagEquivalenceDialog extends StatefulWidget {
  final int tagId;

  const TagEquivalenceDialog({super.key, required this.tagId});

  @override
  State<TagEquivalenceDialog> createState() => _TagEquivalenceDialogState();
}

class _TagEquivalenceDialogState extends State<TagEquivalenceDialog> {
  List<DownloadedTag>? _group;
  int? _primaryId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    setState(() => _isLoading = true);
    final group = await tagManagerStore.getEquivalenceGroup(widget.tagId);
    if (mounted) {
      setState(() {
        _group = group;
        // Find the current primary (referencedTagId is null)
        try {
          _primaryId = group.firstWhere((t) => t.referencedTagId == null).id;
        } catch (_) {
          // Fallback to first if not found (should not happen)
          _primaryId = group.first.id;
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('管理等价标签'),
      content: _isLoading
          ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('选择一个作为主标签，其他将作为其别名。'),
                  const SizedBox(height: 16),
                  if (_group != null)
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _group!.length,
                        itemBuilder: (context, index) {
                          final tag = _group![index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Radio<int>(
                              value: tag.id,
                              groupValue: _primaryId,
                              onChanged: (val) {
                                if (val != null) setState(() => _primaryId = val);
                              },
                            ),
                            title: Text(tag.name),
                            subtitle: Text(tag.translatedName),
                            trailing: IconButton(
                              icon: const Icon(Icons.link_off, size: 20),
                              onPressed: () => _dissociate(tag.id),
                              tooltip: '取消关联',
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
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        ElevatedButton(
          onPressed: _isLoading || _group == null ? null : _save,
          child: const Text('确定'),
        ),
      ],
    );
  }

  Future<void> _dissociate(int id) async {
    await tagManagerStore.dissociateSingleTag(id);
    if (!mounted) return;
    
    if (_group != null && _group!.length <= 2) {
      // If only 2 tags were in the group, removing one breaks the group
      Navigator.pop(context);
    } else {
      _loadGroup();
    }
  }

  Future<void> _save() async {
    if (_primaryId != null && _group != null) {
      await tagManagerStore.updateEquivalenceGroup(
        _primaryId!,
        _group!.map((t) => t.id).toList(),
      );
      if (mounted) Navigator.pop(context);
    }
  }
}
