import 'package:flutter/material.dart';
import 'package:pixez/main.dart'; // For tagManagerStore
import 'package:pixez/models/download_record.dart'; // For TagDisplayData

class ParentSelectionDialogResult {
  final int parentId;
  final Map<int, String>? newNames;

  ParentSelectionDialogResult({required this.parentId, this.newNames});
}

class ParentSelectionDialog extends StatefulWidget {
  final List<DownloadedTag> tags;
  final int currentParentId;

  const ParentSelectionDialog({
    super.key, 
    required this.tags,
    required this.currentParentId,
  });

  static Future<void> show(BuildContext context, {
    required List<DownloadedTag> tags, 
    required int currentParentId,
    VoidCallback? onUpdated,
  }) async {
    final result = await showDialog<ParentSelectionDialogResult>(
      context: context,
      builder: (context) => ParentSelectionDialog(
        tags: tags,
        currentParentId: currentParentId,
      ),
    );

    if (result != null) {
      await tagManagerStore.batchUpdateTagParent(
        tags.map((t) => t.id).toList(), 
        result.parentId,
        newNames: result.newNames,
      );
      onUpdated?.call();
    }
  }

  @override
  State<ParentSelectionDialog> createState() => _ParentSelectionDialogState();
}

class _ParentSelectionDialogState extends State<ParentSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<TagDisplayData> _allWorkTags = [];
  List<TagDisplayData> _filteredTags = [];
  List<DownloadedTag> _recommendedParents = [];
  bool _isLoadingRecommendations = true;
  final Map<int, String> _namePreviewMap = {};

  @override
  void initState() {
    super.initState();
    // Load all Work tags except the children themselves (circular dependency prevention)
    final childIds = widget.tags.map((t) => t.id).toSet();
    _allWorkTags = tagManagerStore.tags.where((t) => 
      t.tag.category == TagCategory.work.value && !childIds.contains(t.tag.id)
    ).toList();
    
    // Sort logic: By count descending
    _allWorkTags.sort((a,b) => b.tag.count.compareTo(a.tag.count));
    
    _filteredTags = _allWorkTags;

    _searchController.addListener(_onSearchChanged);
    _loadRecommendations();
    _generateNamePreviews();
  }

  void _generateNamePreviews() {
    final pattern = RegExp(r'^(.+)[(（](.+)[)）]$');
    for (final tag in widget.tags) {
      final nameToCheck = tag.displayTranslatedName.isNotEmpty 
          ? tag.displayTranslatedName : tag.name;
      final match = pattern.firstMatch(nameToCheck);
      if (match != null) {
        _namePreviewMap[tag.id] = match.group(1)!.trim();
      }
    }
  }

  Future<void> _loadRecommendations() async {
    if (widget.tags.isEmpty) return;
    try {
      // 如果是多个标签，取第一个的推荐（或者可以改进为合并推荐，但目前先保持简单）
      final recommended = await tagManagerStore.getRecommendedParents(widget.tags.first.id);
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
      content: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSelectionHeader(context),
            const SizedBox(height: 16),
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
              leading: const Icon(Icons.clear, size: 20),
              title: const Text('无 (清除归属)', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.pop(context, ParentSelectionDialogResult(
                parentId: 0,
                newNames: _namePreviewMap.isNotEmpty ? _namePreviewMap : null,
              )),
              selected: widget.currentParentId == 0,
              dense: true,
            ),
            const Divider(),
            if (_searchController.text.isEmpty && (_isLoadingRecommendations || _recommendedParents.isNotEmpty)) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '推荐归属',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.auto_awesome, size: 12, color: Colors.orange),
                  ],
                ),
              ),
              if (_isLoadingRecommendations)
                const Center(child: Padding(padding: EdgeInsets.all(8.0), child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
              if (!_isLoadingRecommendations && _recommendedParents.isNotEmpty)
                ..._recommendedParents.map((tag) {
                  final isCurrentParent = tag.id == widget.currentParentId;
                  final isSelf = widget.tags.any((t) => t.id == tag.id);
                  return ListTile(
                    title: Row(
                      children: [
                        Expanded(child: Text(tag.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                        if (isSelf) 
                          _buildBadge(context, '当前标签', Colors.purple),
                        if (isCurrentParent)
                          _buildBadge(context, '当前归属', Colors.blue),
                      ],
                    ),
                    subtitle: tag.displayTranslatedName.isNotEmpty 
                        ? Text(tag.displayTranslatedName, style: const TextStyle(fontSize: 12)) : null,
                    trailing: Text('${tag.count}', style: Theme.of(context).textTheme.bodySmall),
                    onTap: isSelf ? null : () => Navigator.pop(context, ParentSelectionDialogResult(
                      parentId: tag.id,
                      newNames: _namePreviewMap.isNotEmpty ? _namePreviewMap : null,
                    )),
                    dense: true,
                    enabled: !isSelf,
                  );
                }),
              const Divider(),
            ],
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredTags.length,
                itemBuilder: (context, index) {
                  final data = _filteredTags[index];
                  final isCurrentParent = data.tag.id == widget.currentParentId;
                  final isSelf = widget.tags.any((t) => t.id == data.tag.id);
                  return ListTile(
                    title: Row(
                      children: [
                        Expanded(child: Text(data.tag.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                        if (isSelf) 
                          _buildBadge(context, '当前标签', Colors.purple),
                        if (isCurrentParent)
                          _buildBadge(context, '当前归属', Colors.blue),
                      ],
                    ),
                    subtitle: data.tag.displayTranslatedName.isNotEmpty 
                        ? Text(data.tag.displayTranslatedName, style: const TextStyle(fontSize: 12)) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${data.tag.count}', style: Theme.of(context).textTheme.bodySmall),
                        if (isCurrentParent) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check, color: Colors.blue, size: 18),
                        ],
                      ],
                    ),
                    dense: true,
                    enabled: !isSelf,
                    onTap: isSelf ? null : () => Navigator.pop(context, ParentSelectionDialogResult(
                      parentId: data.tag.id,
                      newNames: _namePreviewMap.isNotEmpty ? _namePreviewMap : null,
                    )),
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

  Widget _buildBadge(BuildContext context, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSelectionHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 16, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              '已选择 ${widget.tags.length} 个标签',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 展示所有选中的标签
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.tags.map((tag) {
                  final color = tag.categoryEnum.color ?? Colors.grey;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.3)),
                    ),
                    child: Text(
                      tag.displayName,
                      style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        if (_namePreviewMap.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_fix_high, size: 14, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '名称清洗预览 (移除括号内容)',
                      style: TextStyle(
                        fontSize: 12, 
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 100),
                  child: SingleChildScrollView(
                    child: Column(
                      children: _namePreviewMap.entries.map((entry) {
                        final originalTag = widget.tags.firstWhere((t) => t.id == entry.key);
                        final originalName = originalTag.displayTranslatedName.isNotEmpty 
                            ? originalTag.displayTranslatedName : originalTag.name;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  originalName,
                                  style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_right_alt, size: 14, color: Colors.grey),
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
