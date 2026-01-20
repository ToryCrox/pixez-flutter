import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/tag_manager/tag_item.dart';
import 'package:pixez/page/downloaded/tag_manager/tag_manager_page_store.dart';
import 'package:pixez/component/sort_group.dart';
import 'package:pixez/page/downloaded/tag_manager/tag_selection_dialog.dart';
import 'package:pixez/page/downloaded/tag_manager/parent_selection_dialog.dart';
import 'package:pixez/page/downloaded/tag_manager/auto_associate_dialog.dart';
import 'package:pixez/store/tag_manager_store.dart';

class TagManagerPage extends StatefulWidget {
  const TagManagerPage({super.key});

  @override
  State<TagManagerPage> createState() => _TagManagerPageState();
}

class _TagManagerPageState extends State<TagManagerPage> {
  final TagManagerPageStore _pageStore = TagManagerPageStore();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _pageStore.setSearchText(_searchController.text);
    });
    // Ensure data is loaded (will skip if already exists)
    tagManagerStore.loadTags();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    _pageStore.toggleSearch(!_pageStore.isSearching);
    if (_pageStore.isSearching) {
      _searchFocusNode.requestFocus();
    } else {
      _searchController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        return Scaffold(
          appBar:
              _pageStore.isSelectionMode
                  ? _buildSelectionAppBar()
                  : _buildNormalAppBar(),
          body: Observer(
            builder: (_) {
              if (tagManagerStore.isLoading && tagManagerStore.tags.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              final tags = _pageStore.displayTags;

              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: SliverChipDelegate(
                      Container(
                        alignment: Alignment.center,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: SortGroup(
                            key: ValueKey(_pageStore.filterCategory),
                            children: const ['全部', '作品', '角色', '特点', '收藏'],
                            initIndex: _getFilterIndex(
                              _pageStore.filterCategory,
                            ),
                            onChange: (index) {
                              final category = _getCategoryFromIndex(index);
                              _pageStore.setFilterCategory(category);
                            },
                          ),
                        ),
                      ),
                      height: 52,
                    ),
                  ),

                  if (tags.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('没有找到标签'),
                            if (tagManagerStore.tags.isEmpty) ...[
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _showSyncDialog,
                                child: const Text('从已下载作品同步'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  else if (_pageStore.isTreeView &&
                      _pageStore.searchText.isEmpty &&
                      _pageStore.filterCategory == -1)
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        return Observer(
                          builder: (_) {
                            final data = tags[index];
                            return TagItem(
                              key: ValueKey(data),
                              data: data,
                              isSelectionMode: _pageStore.isSelectionMode,
                              isSelected: _pageStore.selectedTagIds.contains(
                                data.tag.id,
                              ),
                              showAsTreeRow: true,
                              isExpanded: _pageStore.expandedParentIds.contains(data.tag.id),
                              onSelectionToggle: () {
                                _pageStore.toggleTagSelection(data.tag.id);
                              },
                              onSelectionModeToggle:
                                  (value) =>
                                      _pageStore.toggleSelectionMode(value),
                              onClassify: _showClassifyDialog,
                              onAssociate: _showAssociateDialog,
                              onToggleExpansion: () => _pageStore.toggleParentExpansion(data.tag.id),
                              onSetParent: () => _showSetParentDialog(data.tag),
                            );
                          },
                        );
                      }, childCount: tags.length),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(8.0),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 200,
                              childAspectRatio: 0.8,
                              crossAxisSpacing: 8.0,
                              mainAxisSpacing: 8.0,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return Observer(
                            builder: (_) {
                              final data = tags[index];
                              return TagItem(
                                key: ValueKey(data),
                                data: data, // ...
                                isSelectionMode: _pageStore.isSelectionMode,
                                isSelected: _pageStore.selectedTagIds.contains(
                                  data.tag.id,
                                ),
                                onSelectionToggle: () {
                                  _pageStore.toggleTagSelection(data.tag.id);
                                },
                                onSelectionModeToggle:
                                    (value) =>
                                        _pageStore.toggleSelectionMode(value),
                                onClassify: _showClassifyDialog,
                                onAssociate: _showAssociateDialog,
                                onSetParent: () => _showSetParentDialog(data.tag),
                              );
                            },
                          );
                        }, childCount: tags.length),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // ... (existing AppBar methods)

  void _showSetParentDialog(DownloadedTag tag) async {
    final parentId = await showDialog<int>(
      context: context,
      builder: (context) => ParentSelectionDialog(
        currentParentId: tag.parentId,
        childTagId: tag.id,
      ),
    );

    if (parentId != null) {
      await tagManagerStore.updateTagParent(tag.id, parentId);
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('已更新归属关系')),
         );
      }
    }
  }

  // ... (existing methods: _showClassifyDialog, _showAssociateDialog, _showSyncDialog, _showAutoAssociateDialog)
  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      title: _pageStore.isSearching ? _buildSearchField() : _buildAppBarTitle(),
      actions: [
        IconButton(
          icon: Icon(_pageStore.isSearching ? Icons.close : Icons.search),
          tooltip: _pageStore.isSearching ? '关闭搜索' : '搜索',
          onPressed: _toggleSearch,
        ),
        if (!_pageStore.isSearching) ...[
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: '选择模式',
            onPressed: () => _pageStore.toggleSelectionMode(true),
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            initialValue: _pageStore.sortType,
            onSelected: (value) {
              _pageStore.setSortType(value);
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(value: 4, child: Text('按分类排序 (默认)')),
                  const PopupMenuItem(value: 0, child: Text('按数量排序 (降序)')),
                  const PopupMenuItem(value: 1, child: Text('按名称排序 (升序)')),
                  const PopupMenuItem(value: 2, child: Text('按最近使用排序')),
                  const PopupMenuItem(value: 3, child: Text('按手动优先级排序')),
                ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onSelected: (value) {
              switch (value) {
                case 'tree_view':
                  _pageStore.toggleTreeView(!_pageStore.isTreeView);
                  break;
                case 'auto_associate':
                  _showAutoAssociateDialog();
                  break;
                case 'sync':
                  _showSyncDialog();
                  break;
              }
            },
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    value: 'tree_view',
                    child: Row(
                      children: [
                        Icon(
                          _pageStore.isTreeView
                              ? Icons.view_module
                              : Icons.account_tree,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(_pageStore.isTreeView ? '切换网格视图' : '切换层级视图'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'auto_associate',
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 20),
                        const SizedBox(width: 8),
                        Text('智能关联识别'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'sync',
                    child: Row(
                      children: [
                        Icon(Icons.sync, size: 20),
                        const SizedBox(width: 8),
                        Text('同步标签库'),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => _pageStore.toggleSelectionMode(false),
      ),
      title: Observer(
        builder: (_) => Text('${_pageStore.selectedTagIds.length} 已选择'),
      ),
      actions: [
        TextButton(onPressed: _pageStore.selectAll, child: const Text('全选')),
        Observer(
          builder: (_) {
            if (_pageStore.selectedTagIds.isEmpty)
              return const SizedBox.shrink();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: _showAssociateDialog,
                  child: const Text('关联'),
                ),
                TextButton(
                  onPressed: _showClassifyDialog,
                  child: const Text('分类'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildAppBarTitle() {
    return Observer(
      builder: (context) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('标签管理'),
            const SizedBox(width: 8),
            Text(
              '${_pageStore.displayTags.length} 标签',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      decoration: const InputDecoration(
        hintText: '搜索标签...',
        border: InputBorder.none,
      ),
      autofocus: true,
    );
  }

  int _getFilterIndex(int category) {
    switch (category) {
      case -1:
        return 0; // All
      case 1:
        return 1; // Work
      case 2:
        return 2; // Character
      case 6:
        return 3; // Feature
      case 99:
        return 4; // Bookmark
      default:
        return 0;
    }
  }

  int _getCategoryFromIndex(int index) {
    switch (index) {
      case 0:
        return -1;
      case 1:
        return TagCategory.work.value;
      case 2:
        return TagCategory.character.value;
      case 3:
        return TagCategory.feature.value;
      case 4:
        return 99;
      default:
        return -1;
    }
  }

  void _showClassifyDialog() async {
    if (_pageStore.selectedTagIds.isEmpty) return;

    // 智能扩展：识别选中标签背后的完整家族
    final expandedTags = tagManagerStore.expandSelectedTags(
      _pageStore.selectedTagIds.toList(),
    );
    final allIds = expandedTags.map((t) => t.tag.id).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (context) {
        return AlertDialog(
          title: Text('将 ${expandedTags.length} 个标签分类为'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (expandedTags.length > _pageStore.selectedTagIds.length)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '注：已自动包含同组关联标签',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children:
                        expandedTags
                            .map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tag.tag.name,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ),
              const Divider(height: 24),
              ...TagCategory.values.map((category) {
                return ListTile(
                  title: Text(category.label),
                  textColor: category.color,
                  dense: true,
                  onTap: () async {
                    Navigator.pop(context);
                    await tagManagerStore.batchUpdateCategory(
                      allIds,
                      category.value,
                    );
                    _pageStore.toggleSelectionMode(false);
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('全组分类已更新')));
                    }
                  },
                );
              }).toList(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  void _showAssociateDialog() async {
    final selectedIds = _pageStore.selectedTagIds.toList();
    if (selectedIds.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择两个标签进行关联')));
      return;
    }

    // 智能扩展：获取选中标签及其背后的完整家族成员
    final expandedTags = tagManagerStore.expandSelectedTags(selectedIds);

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => TagSelectionDialog(
            comicTags: expandedTags,
            currentGroup: expandedTags,
          ),
    );

    if (result == true) {
      _pageStore.toggleSelectionMode(false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('标签关联已更新')));
      }
    }
  }

  void _showSyncDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Observer(
          builder: (_) {
            if (tagManagerStore.isSyncing) {
              return AlertDialog(
                title: const Text('正在同步'),
                content: Row(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 16),
                    Expanded(child: Text(tagManagerStore.syncStatus)),
                  ],
                ),
              );
            }

            return AlertDialog(
              title: const Text('同步标签'),
              content: const Text(
                '这将扫描所有已下载的作品并重建标签库。\n现有的自定义设置（翻译、分类等）将被保留。\n是否继续？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () async {
                    await tagManagerStore.syncTags();
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('开始同步'),
                ),
              ],
            );
          },
        );
      },
    );
  }


  void _showAutoAssociateDialog() async {
    try {
      final proposals = await tagManagerStore.scanForAutoAssociations();

      if (proposals.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未发现可自动关联的标签')),
          );
        }
        return;
      }

      if (!mounted) return;

      final List<TagAssociationProposal>? selectedProposals = await showDialog<List<TagAssociationProposal>>(
        context: context,
        builder: (context) => AutoAssociateDialog(proposals: proposals),
      );

      if (selectedProposals != null && selectedProposals.isNotEmpty) {
        for (final p in selectedProposals) {
           await tagManagerStore.updateTagParent(
             p.childTag.id, 
             p.parentTag.id,
             newName: p.newChildName,
           );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已成功关联 ${selectedProposals.length} 项')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // 确保关闭加载中
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('关联扫描失败: $e')),
        );
      }
    }
  }
}

extension TextEditingControllerExt on TextEditingController {
  // Helper to rebuild on text change without full setstate
  Widget builder(Widget Function(BuildContext, TextEditingValue) builder) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: this,
      builder: (context, value, child) {
        return builder(context, value);
      },
    );
  }
}

class SliverChipDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  double height = 45;

  SliverChipDelegate(this.child, {this.height = 45});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(SliverChipDelegate oldDelegate) {
    return height != oldDelegate.height;
  }
}


