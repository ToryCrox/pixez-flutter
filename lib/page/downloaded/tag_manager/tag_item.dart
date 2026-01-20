import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/tag_manager/tag_edit_dialog.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/page/downloaded/downloaded_page.dart';
import 'package:pixez/page/downloaded/tag_manager/tag_selection_dialog.dart';
import 'package:pixez/page/search/result_page.dart';
import 'package:pixez/main.dart';

class TagItem extends StatelessWidget {
  final TagDisplayData data;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;
  final Function(bool)? onSelectionModeToggle;
  final VoidCallback? onClassify;
  final VoidCallback? onAssociate;
  final bool showAsTreeRow;
  final bool isExpanded;
  final VoidCallback? onToggleExpansion;
  final ValueChanged<DownloadedTag>? onSetParent;
  final VoidCallback? onShowChildren; // 点击子标签徽章的回调

  const TagItem({
    super.key,
    required this.data,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionToggle,
    this.onSelectionModeToggle,
    this.onClassify,
    this.onAssociate,
    this.showAsTreeRow = false,
    this.isExpanded = false,
    this.onToggleExpansion,
    this.onSetParent,
    this.onShowChildren,
  });

  @override
  Widget build(BuildContext context) {
    // 动态计算宽高比，避免瀑布流布局跳动
    // 据封面数量决定
    // 0: 仅文字 -> 较小高度
    // 1: 1张大图 -> 16:9 或 4:3
    // 2-3: 组合图 -> 1:1 或 4:3
    // 这里简单预设一个比例，实际由内容撑开

    // 38: 这里简单预设一个比例，实际由内容撑开
    
    if (showAsTreeRow) {
      return _buildTreeRow(context);
    }

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _tapPosition = details.globalPosition;
      },
      onSecondaryTap: () {
        _showContextMenu(context);
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        // Selection border
        shape:
            isSelected
                ? RoundedRectangleBorder(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(12),
                )
                : null,
        child: InkWell(
          onTap: () {
            if (isSelectionMode) {
              onSelectionToggle?.call();
            } else {
              _navigateToLocalSearch(context);
            }
          },
          onLongPress: () {
            if (!isSelectionMode) {
              onSelectionModeToggle?.call(true);
              if (!isSelected) {
                onSelectionToggle?.call();
              }
            } else {
              onSelectionToggle?.call();
            }
          },
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildCoverArea(context)),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // First line: Name + Count
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                data.tag.name,
                                style: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.copyWith(
                                  color: data.tag.categoryEnum.color,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (data.tag.isBookmarked)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0,
                                ),
                                child: Icon(
                                  Icons.bookmark,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            const SizedBox(width: 4),
                            Text(
                              '${data.tag.count}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Combined Translation and Parent display
                      Row(
                        children: [
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final translation = data.tag.displayTranslatedName;
                                
                                final hasTranslation = translation.isNotEmpty;
                                final parent = data.tag.parentId != 0 
                                    ? tagManagerStore.getTagDisplayDataByID(data.tag.parentId)?.tag : null;


                                String tooltipMessage = '';
                                if (hasTranslation) tooltipMessage += '翻译: $translation';
                                if (parent != null) {
                                  if (tooltipMessage.isNotEmpty) tooltipMessage += '\n';
                                  tooltipMessage += '归属: ${parent.displayName}';
                                }

                                return Tooltip(
                                  message: tooltipMessage,
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        if (hasTranslation)
                                          TextSpan(
                                            text: translation,
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: data.tag.isCustomTranslatedName ? Colors.purple : Colors.grey,
                                            ),
                                          ),
                                        if (parent != null) ...[
                                          if (hasTranslation) const TextSpan(text: ' '),
                                          TextSpan(
                                            text: '(${parent.displayName})',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Colors.blueGrey,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              },
                            ),
                          ),
                          if (data.hasEquivalentTags)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _showEquivalenceDialog(context),
                                borderRadius: BorderRadius.circular(4),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  child: Icon(Icons.link, size: 14, color: Colors.blue),
                                ),
                              ),
                            ),
                        ],
                      ),
                      ],
                    ),
                  ),
                ],
              ),
              // 子标签数量徽章
              Builder(
                builder: (context) {
                  final childrenCount = tagManagerStore.getDirectChildren(data.tag.id).length;
                  if (childrenCount == 0 || isSelectionMode) {
                    return const SizedBox.shrink();
                  }
                  
                  return Positioned(
                    top: 4,
                    left: 4,
                    child: GestureDetector(
                      onTap: () => onShowChildren?.call(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.folder, size: 12, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              '$childrenCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (isSelectionMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Icon(Icons.check, size: 16, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEquivalenceDialog(BuildContext context) {
    if (isSelectionMode) {
      onAssociate?.call();
      return;
    }
    final group = tagManagerStore.getEquivalenceGroup(data.tag.id);
    showDialog(
      context: context,
      useRootNavigator: false,
      builder:
          (context) => TagSelectionDialog(
            comicTags: group,
            currentGroup: group,
            currentTagId: data.tag.id,
          ),
    );
  }

  static Offset _tapPosition = Offset.zero;

  Future<void> _showContextMenu(BuildContext context) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final localPosition = overlay.globalToLocal(_tapPosition);

    final result = await showMenu(
      context: context,
      position: RelativeRect.fromRect(
        localPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        if (isSelectionMode) ...[
          const PopupMenuItem(
            value: 'classify',
            child: Row(
              children: [
                Icon(Icons.category, size: 20),
                SizedBox(width: 8),
                Text('分类'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'associate',
            child: Row(
              children: [
                Icon(Icons.link, size: 20),
                SizedBox(width: 8),
                Text('关联'),
              ],
            ),
          ),
        ],
        const PopupMenuItem(
          value: 'set_parent',
          child: Row(
            children: [
              Icon(Icons.account_tree, size: 20),
              SizedBox(width: 8),
              Text('设置归属'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'search_online',
          child: Row(
            children: [
              Icon(Icons.search, size: 20),
              SizedBox(width: 8),
              Text('搜索线上结果'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'search_local',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 20),
              SizedBox(width: 8),
              Text('查看本地下载'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'bookmark',
          child: Row(
            children: [
              Icon(
                data.tag.isBookmarked
                    ? Icons.bookmark_remove
                    : Icons.bookmark_add,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(data.tag.isBookmarked ? '取消收藏' : '收藏'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy_title',
          child: Row(
            children: [
              Icon(Icons.copy, size: 20),
              SizedBox(width: 8),
              Text('复制标题'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy_translation',
          child: Row(
            children: [
              Icon(Icons.translate, size: 20),
              SizedBox(width: 8),
              Text('复制翻译'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 20),
              SizedBox(width: 8),
              Text('编辑标签'),
            ],
          ),
        ),
        if (isSelectionMode)
          const PopupMenuItem(
            value: 'exit_selection_mode',
            child: Row(
              children: [
                Icon(Icons.close, size: 20),
                const SizedBox(width: 8),
                Text('退出选择模式'),
              ],
            ),
          ),
      ],
    );

    if (result == null) return;

    switch (result) {
      case 'search_online':
        _navigateToOnlineSearch(context);
        break;
      case 'search_local':
        _navigateToLocalSearch(context);
        break;
      case 'bookmark':
        await tagManagerStore.updateTag(
          data.tag.copyWith(isBookmarked: !data.tag.isBookmarked),
        );
        break;
      case 'copy_title':
        await _copyToClipboard(context, data.tag.name);
        break;
      case 'copy_translation':
        final translation =
            (data.tag.customTranslatedName?.isNotEmpty == true)
                ? data.tag.customTranslatedName!
                : data.tag.translatedName;
        await _copyToClipboard(context, translation);
        break;
      case 'edit':
        if (context.mounted) {
          _showEditDialog(context);
        }
        break;
      case 'classify':
        onClassify?.call();
        break;
      case 'associate':
        onAssociate?.call();
        break;
      case 'set_parent':
        if (context.mounted) {
          onSetParent?.call(data.tag);
        }
        break;
      case 'exit_selection_mode':
        onSelectionModeToggle?.call(false);
        break;
    }
  }

  Future<void> _copyToClipboard(BuildContext context, String text) async {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
    );
  }

  void _navigateToLocalSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DownloadedPage(initialTagName: data.tag.name),
      ),
    );
  }

  void _navigateToOnlineSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => ResultPage(
              word: data.tag.name,
              translatedName: data.tag.translatedName,
            ),
      ),
    );
  }

  Widget _buildCoverArea(BuildContext context) {
    if (data.previewIllusts.isEmpty) {
      return Container(color: Colors.grey.withOpacity(0.1));
    }

    if (data.previewIllusts.length == 1) {
      return _buildImage(data.previewIllusts.first);
    }

    if (data.previewIllusts.length == 2) {
      return Row(
        children: [
          Expanded(flex: 2, child: _buildImage(data.previewIllusts[0])),
          const SizedBox(width: 2),
          Expanded(flex: 1, child: _buildImage(data.previewIllusts[1])),
        ],
      );
    }

    return Row(
      children: [
        Expanded(flex: 2, child: _buildImage(data.previewIllusts[0])),
        const SizedBox(width: 2),
        Expanded(
          flex: 1,
          child: Column(
            children: [
              Expanded(child: _buildImage(data.previewIllusts[1])),
              const SizedBox(height: 2),
              Expanded(child: _buildImage(data.previewIllusts[2])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImage(IllustPreviewData illust) {
    return PixivImage(
      illust.squareMediumUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // 通过 header 传递 illustId，让 PixivCacheManager 识别封面请求
      httpHeaders: {'cover': '${illust.illustId}'},
    );
  }

  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => TagEditDialog(tag: data.tag),
    );
  }


  Widget _buildTreeRow(BuildContext context) {
    final hasChildren = data.tag.category == TagCategory.work.value; // Assuming Works have children possibilities
    // Or check if it has children in store? But TagItem doesn't access store directly for that.
    // For visual consistency, we show expand button for all 'Work' tags or if we know it has children.
    // Since we filtered children in store, we can assume Work tags are expandable.
    
    return InkWell(
      onTap: () {
        if (isSelectionMode) {
          onSelectionToggle?.call();
        } else if (hasChildren && onToggleExpansion != null) {
          onToggleExpansion!.call();
        } else {
          _navigateToLocalSearch(context);
        }
      },
      onLongPress: () {
          if (!isSelectionMode) {
              onSelectionModeToggle?.call(true);
              if (!isSelected) onSelectionToggle?.call();
          } else {
              onSelectionToggle?.call();
          }
      },
      onSecondaryTapDown: (details) => _tapPosition = details.globalPosition,
      onSecondaryTap: () => _showContextMenu(context),
      child: Container(
        padding: EdgeInsets.only(left: data.indentLevel * 16.0),
        color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5) : null,
        child: Row(
          children: [
             // Expand Icon for Works
             if (hasChildren)
               IconButton(
                 icon: Icon(isExpanded ? Icons.expand_more : Icons.chevron_right, size: 20),
                 onPressed: onToggleExpansion,
                 visualDensity: VisualDensity.compact,
               )
             else
               const SizedBox(width: 40), // Placeholder alignment
             
             // Cover (Tiny)
             if (data.previewIllusts.isNotEmpty)
               Container(
                 width: 32, height: 32,
                 margin: const EdgeInsets.only(right: 8),
                 child: ClipRRect(
                   borderRadius: BorderRadius.circular(4),
                   child: _buildImage(data.previewIllusts.first),
                 ),
               ),
             
             // Info
             Expanded(
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text(
                     '${data.tag.displayName} (${data.tag.count})',
                     style: TextStyle(
                        fontWeight: data.indentLevel == 0 ? FontWeight.bold : FontWeight.normal,
                        color: data.tag.categoryEnum.color,
                     ),
                     maxLines: 1, overflow: TextOverflow.ellipsis,
                   ),
                   if (data.tag.displayTranslatedName.isNotEmpty && data.tag.displayTranslatedName != data.tag.name)
                      Text(
                        data.tag.name, // Show original name as subtitle if translated is used as primary
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                 ],
               ),
             ),
             
             // Actions
             if (data.tag.isBookmarked)
               Icon(Icons.bookmark, size: 16, color: Theme.of(context).colorScheme.primary),
             
             IconButton(
               icon: const Icon(Icons.more_vert, size: 16),
               onPressed: () {
                 // Use a simple RenderBox approach to show menu near the button
                 final renderBox = context.findRenderObject() as RenderBox;
                 final offset = renderBox.localToGlobal(Offset.zero);
                 final size = renderBox.size;
                 // Set tap position for context menu
                 _tapPosition = offset + Offset(size.width, size.height / 2);
                 _showContextMenu(context);
               },
             ),
          ],
        ),
      ),
    );
  }
}
