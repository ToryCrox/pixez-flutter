import 'package:flutter/material.dart';
import 'package:pixez/main.dart'; // For tagManagerStore
import 'package:pixez/models/download_record.dart'; // For TagDisplayData

class ParentSelectionDialog extends StatefulWidget {
  final int currentParentId;
  final int childTagId;

  const ParentSelectionDialog({
    super.key, 
    required this.currentParentId,
    required this.childTagId,
  });

  @override
  State<ParentSelectionDialog> createState() => _ParentSelectionDialogState();
}

class _ParentSelectionDialogState extends State<ParentSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<TagDisplayData> _allWorkTags = [];
  List<TagDisplayData> _filteredTags = [];
  List<DownloadedTag> _recommendedParents = [];
  bool _isLoadingRecommendations = true;

  @override
  void initState() {
    super.initState();
    // Load all Work tags except the child itself (circular dependency prevention)
    _allWorkTags = tagManagerStore.tags.where((t) => 
      t.tag.category == TagCategory.work.value && t.tag.id != widget.childTagId
    ).toList();
    
    // Sort logic: By count descending
    _allWorkTags.sort((a,b) => b.tag.count.compareTo(a.tag.count));
    
    _filteredTags = _allWorkTags;

    _searchController.addListener(_onSearchChanged);
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    try {
      final recommended = await tagManagerStore.getRecommendedParents(widget.childTagId);
      if (mounted) {
        setState(() {
          _recommendedParents = recommended;
          _isLoadingRecommendations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRecommendations = false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredTags = _allWorkTags;
      } else {
        _filteredTags = _allWorkTags.where((t) =>
            t.tag.name.toLowerCase().contains(query) ||
            t.tag.translatedName.toLowerCase().contains(query) ||
            (t.tag.customTranslatedName?.toLowerCase().contains(query) ?? false)
        ).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置归属作品'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: '搜索作品标签',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('无 (清除归属)'),
              onTap: () => Navigator.pop(context, 0),
              selected: widget.currentParentId == 0,
            ),
            const Divider(),
            if (_searchController.text.isEmpty && (_isLoadingRecommendations || _recommendedParents.isNotEmpty)) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '推荐归属',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
                ),
              ),
              if (_isLoadingRecommendations)
                const Center(child: Padding(padding: EdgeInsets.all(8.0), child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
              if (!_isLoadingRecommendations && _recommendedParents.isNotEmpty)
                ..._recommendedParents.map((tag) => ListTile(
                  title: Text(tag.displayName),
                  subtitle: Text(tag.name, style: const TextStyle(fontSize: 10)),
                  trailing: const Icon(Icons.auto_awesome, size: 16, color: Colors.orange),
                  onTap: () => Navigator.pop(context, tag.id),
                  dense: true,
                )),
              const Divider(),
            ],
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredTags.length,
                itemBuilder: (context, index) {
                  final data = _filteredTags[index];
                  final isSelected = data.tag.id == widget.currentParentId;
                  return ListTile(
                    title: Text(data.tag.displayName),
                    subtitle: data.tag.translatedName.isNotEmpty && data.tag.translatedName != data.tag.displayName 
                      ? Text(data.tag.name) : null,
                    trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
                    dense: true,
                    onTap: () => Navigator.pop(context, data.tag.id),
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
      ],
    );
  }
}
