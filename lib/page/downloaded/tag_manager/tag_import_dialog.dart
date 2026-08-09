import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/downloaded_page.dart';
import 'package:pixez/page/downloaded/tag_manager/parent_selection_dialog.dart';
import 'package:pixez/store/tag_manager_store.dart';

/// 对话框状态
enum _DialogState {
  idle, // 初始状态
  loading, // 正在解析和匹配
  preview, // 预览变更
  applying, // 正在应用
  done, // 应用完成
}

/// 标签数据导入对话框
class TagImportDialog extends StatefulWidget {
  const TagImportDialog({super.key});

  /// 打开导入对话框
  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => const TagImportDialog(),
    );
  }

  @override
  State<TagImportDialog> createState() => _TagImportDialogState();
}

class _TagImportDialogState extends State<TagImportDialog> {
  _DialogState _state = _DialogState.idle;
  List<TagImportResult> _results = [];
  String? _errorMessage;
  int _lastAppliedCount = 0;
  bool _allSelected = true;
  String? _currentFilePath;

  @override
  void initState() {
    super.initState();
    _loadLastFile();
  }

  /// 加载上次选择的文件
  Future<void> _loadLastFile() async {
    final lastPath = Prefer.getString('last_tag_import_path');
    if (lastPath != null && File(lastPath).existsSync()) {
      _currentFilePath = lastPath;
      _parseFile(lastPath);
    }
  }

  /// 选择文件
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.single.path;
    if (filePath == null) return;

    await Prefer.setString('last_tag_import_path', filePath);
    _currentFilePath = filePath;
    _parseFile(filePath);
  }

  /// 解析指定的 JSON 文件
  Future<void> _parseFile(String filePath) async {
    setState(() {
      _state = _DialogState.loading;
      _errorMessage = null;
    });

    try {
      final jsonStr = await File(filePath).readAsString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final updates =
          (json['updates'] as List)
              .map((e) => TagImportItem.fromJson(e as Map<String, dynamic>))
              .toList();

      if (updates.isEmpty) {
        setState(() {
          _state = _DialogState.idle;
          _errorMessage = 'JSON 中没有标签更新数据';
        });
        return;
      }

      // 匹配本地标签
      final importResults = await tagManagerStore.importTagUpdates(updates);

      setState(() {
        _results = importResults;
        _state = _DialogState.preview;
        _updateAllSelected();
      });
    } catch (e) {
      setState(() {
        _state = _DialogState.idle;
        _errorMessage = '解析失败: $e';
      });
    }
  }

  /// 应用选中的变更
  Future<void> _applyChanges() async {
    setState(() => _state = _DialogState.applying);

    try {
      final applied = await tagManagerStore.applyImportResults(_results);
      setState(() {
        _lastAppliedCount = applied;
        _state = _DialogState.done;
      });
    } catch (e) {
      setState(() {
        _state = _DialogState.preview;
        _errorMessage = '应用失败: $e';
      });
    }
  }

  /// 重置并重新选择
  void _repickFile() {
    _pickFile();
  }

  void _updateAllSelected() {
    final matchedResults = _results.where((r) => r.matched).toList();
    _allSelected =
        matchedResults.isNotEmpty && matchedResults.every((r) => r.selected);
  }

  void _toggleAll() {
    setState(() {
      final newValue = !_allSelected;
      for (final r in _results) {
        if (r.matched) r.selected = newValue;
      }
      _allSelected = newValue;
    });
  }

  void _toggleItem(int index) {
    setState(() {
      final r = _results[index];
      if (r.matched) r.selected = !r.selected;
      _updateAllSelected();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('导入标签数据')),
          if (_state == _DialogState.preview || _state == _DialogState.done)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '重新选择文件',
              onPressed: _repickFile,
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.75,
        child: _buildContent(),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case _DialogState.idle:
        return _buildIdleContent();
      case _DialogState.loading:
        return const Center(child: CircularProgressIndicator());
      case _DialogState.preview:
        return _buildPreviewContent();
      case _DialogState.applying:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在应用变更...'),
            ],
          ),
        );
      case _DialogState.done:
        return _buildDoneContent();
    }
  }

  Widget _buildIdleContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.file_upload_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('选择 JSON 文件以导入标签数据'),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('选择文件'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewContent() {
    return Column(
      children: [
        if (_currentFilePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '当前文件: ${File(_currentFilePath!).path.split(Platform.pathSeparator).last}',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        _buildPreviewHeader(),
        const Divider(height: 1),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder:
                (context, index) => _TagImportResultItem(
                  result: _results[index],
                  onToggle: () => _toggleItem(index),
                  onEdit: () => setState(() {}),
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewHeader() {
    final selectedCount = _results.where((r) => r.matched && r.selected).length;
    final matchedCount = _results.where((r) => r.matched).length;
    final unmatchedCount = _results.where((r) => !r.matched).length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(value: _allSelected, onChanged: (_) => _toggleAll()),
          Text('全选 ($selectedCount/$matchedCount)'),
          const Spacer(),
          if (unmatchedCount > 0)
            Text(
              '$unmatchedCount 项未匹配',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDoneContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            '已成功更新 $_lastAppliedCount 个标签',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('导入其他文件'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions() {
    switch (_state) {
      case _DialogState.idle:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ];
      case _DialogState.loading:
      case _DialogState.applying:
        return [];
      case _DialogState.preview:
        final selectedCount =
            _results.where((r) => r.matched && r.selected).length;
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: selectedCount > 0 ? _applyChanges : null,
            child: Text('确认 ($selectedCount)'),
          ),
        ];
      case _DialogState.done:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ];
    }
  }
}

class _TagImportResultItem extends StatelessWidget {
  final TagImportResult result;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const _TagImportResultItem({
    required this.result,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final item = result.item;
    final tagData = result.tagData;

    return Opacity(
      opacity: result.matched ? 1.0 : 0.5,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: InkWell(
          onTap: result.matched ? onToggle : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.matched)
                  Checkbox(value: result.selected, onChanged: (_) => onToggle())
                else
                  const SizedBox(width: 48),
                _buildPreview(context, tagData),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTagHeader(context),
                      const SizedBox(height: 4),
                      // 分类行 - 可点击编辑
                      _buildCategoryEdge(context),
                      // 翻译行 - 可点击编辑
                      _buildTranslationEdge(context),
                      // 归属行 - 可点击编辑
                      _buildParentEdge(context),
                      // 其他变更描述 (不再包含这些，因为都已明确)
                      if (item.reason.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.reason,
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (result.matched && tagData != null)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    tooltip: '在下载页中查看',
                    onPressed: () => _navigateToDownloaded(context, tagData),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagHeader(BuildContext context) {
    final tag = result.tagData?.tag;
    String nameText = result.item.name;
    // 如果已有翻译，带上翻译显示
    if (tag != null && tag.displayTranslatedName.isNotEmpty) {
      nameText = '${tag.displayTranslatedName} ($nameText)';
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(nameText, style: const TextStyle(fontWeight: FontWeight.bold)),
        if (tag != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${tag.count}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryEdge(BuildContext context) {
    final tag = result.tagData?.tag;
    if (tag == null) return const SizedBox.shrink();

    final currentCatValue = result.editableCategory ?? tag.category;
    final currentCat = TagCategory.fromValue(currentCatValue);
    final hasChange =
        result.editableCategory != null &&
        result.editableCategory != tag.category;

    return PopupMenuButton<int>(
      onSelected: (val) {
        result.editableCategory = val;
        onEdit();
      },
      itemBuilder:
          (context) =>
              TagCategory.values.map((c) {
                final isSelected = c.value == currentCatValue;
                return PopupMenuItem(
                  value: c.value,
                  child: Text(
                    c.label,
                    style: TextStyle(
                      color:
                          isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                      fontWeight: isSelected ? FontWeight.bold : null,
                    ),
                  ),
                );
              }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              Icons.category_outlined,
              size: 14,
              color: Theme.of(context).hintColor,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '分类: ${currentCat.label}',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      hasChange
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).hintColor,
                  fontWeight: hasChange ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: Theme.of(context).hintColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranslationEdge(BuildContext context) {
    final tag = result.tagData?.tag;
    if (tag == null) return const SizedBox.shrink();

    final currentVal =
        result.editableTranslation ?? tag.customTranslatedName ?? '';
    final hasChange =
        result.editableTranslation != null &&
        result.editableTranslation != tag.customTranslatedName;

    return InkWell(
      onTap: () => _editTranslation(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(Icons.translate, size: 14, color: Theme.of(context).hintColor),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '翻译: ${currentVal.isEmpty ? "(无)" : currentVal}',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      hasChange
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).hintColor,
                  fontWeight: hasChange ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Icon(Icons.edit, size: 12, color: Theme.of(context).hintColor),
          ],
        ),
      ),
    );
  }

  Widget _buildParentEdge(BuildContext context) {
    final tag = result.tagData?.tag;
    if (tag == null) return const SizedBox.shrink();

    // 解析当前显示的父标签名和翻译
    final currentParentName = result.editableParentName;
    String parentDisplay = currentParentName ?? '(无)';
    String? countSuffix;

    if (currentParentName != null && currentParentName.isNotEmpty) {
      final pData = tagManagerStore.tagNameMap[currentParentName];
      if (pData != null) {
        countSuffix = ' [${pData.tag.count}]';
        if (pData.tag.displayTranslatedName.isNotEmpty) {
          parentDisplay =
              '${pData.tag.displayTranslatedName} ($currentParentName)';
        }
      }
    }

    final hasChange = result.editableParentName != null;

    return InkWell(
      onTap: () => _editParent(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 14,
              color: Theme.of(context).hintColor,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '归属: $parentDisplay'),
                    if (countSuffix != null)
                      TextSpan(
                        text: countSuffix,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.7),
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                  ],
                ),
                style: TextStyle(
                  fontSize: 12,
                  color:
                      hasChange
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).hintColor,
                  fontWeight: hasChange ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Icon(Icons.edit, size: 12, color: Theme.of(context).hintColor),
          ],
        ),
      ),
    );
  }

  Future<void> _editTranslation(BuildContext context) async {
    final tag = result.tagData!.tag;
    final controller = TextEditingController(
      text: result.editableTranslation ?? tag.customTranslatedName ?? '',
    );
    final newVal = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('修改自定义翻译'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: '翻译内容'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('确定'),
              ),
            ],
          ),
    );

    if (newVal != null) {
      result.editableTranslation = newVal;
      onEdit();
    }
  }

  Future<void> _editParent(BuildContext context) async {
    final tag = result.tagData!.tag;
    // 使用现有的 ParentSelectionDialog 选取父标签
    final res = await showDialog<ParentSelectionDialogResult>(
      context: context,
      builder:
          (context) =>
              ParentSelectionDialog(tags: [tag], currentParentId: tag.parentId),
    );

    if (res != null) {
      if (res.parentId == 0) {
        result.editableParentName = '';
      } else {
        final pData = tagManagerStore.tagIdMap[res.parentId];
        if (pData != null) {
          // 这里如果是同义标签，resolveToMainTagName
          result.editableParentName = tagManagerStore.resolveToMainTagName(
            pData.tag.name,
          );
        }
      }
      onEdit();
    }
  }

  Widget _buildPreview(BuildContext context, TagDisplayData? tagData) {
    if (tagData == null || tagData.previewIllusts.isEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image_not_supported, size: 24),
      );
    }

    final preview = tagData.previewIllusts.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        height: 56,
        child: PixivImage(
          preview.squareMediumUrl,
          fit: BoxFit.cover,
          httpHeaders: {'cover': '${preview.illustId}'},
        ),
      ),
    );
  }

  void _navigateToDownloaded(BuildContext context, TagDisplayData tagData) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DownloadedPage(initialTagId: tagData.tag.id),
      ),
    );
  }
}
