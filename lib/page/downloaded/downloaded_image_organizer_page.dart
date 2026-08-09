import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:open_file/open_file.dart';
import 'package:pixez/component/hover_scale_container.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/downloaded_image_filter_conditions.dart';
import 'package:pixez/page/downloaded/local_image_viewer_page.dart';
import 'package:pixez/page/downloaded/update_illust_info_dialog.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/picture_list_page.dart';
import 'package:pixez/store/downloaded_image_organizer_store.dart';
import 'package:pixez/utils/file_utils.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

const double _kGroupHeaderExtent = 40;
const double _kGridPadding = 8;
const double _kGridCrossAxisSpacing = 8;
const double _kGridMainAxisSpacing = 8;
const double _kGridMaxCrossAxisExtent = 210;
const double _kGridChildAspectRatio = 0.73;

class DownloadedImageOrganizerPage extends StatefulWidget {
  final DownloadedAuthor? author;
  final int? illustId;
  final List<int>? illustIds;
  final String? title;

  const DownloadedImageOrganizerPage({
    super.key,
    this.author,
    this.illustId,
    this.illustIds,
    this.title,
  }) : assert(
         author != null || (illustIds != null && illustIds.length > 0),
         'author 或 illustIds 至少需要提供一个',
       );

  static Future<T?> open<T>(
    BuildContext context, {
    required DownloadedAuthor author,
    int? illustId,
  }) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(
        builder: (context) {
          return DownloadedImageOrganizerPage(
            author: author,
            illustId: illustId,
          );
        },
      ),
    );
  }

  static Future<T?> openForIllusts<T>(
    BuildContext context, {
    required List<int> illustIds,
    String? title,
  }) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(
        builder: (context) {
          return DownloadedImageOrganizerPage(
            illustIds: illustIds,
            title: title,
          );
        },
      ),
    );
  }

  static Future<void> pushByUserId(
    BuildContext context, {
    required int userId,
    int? illustId,
  }) async {
    try {
      final author = await downloadStore.getAuthorByUserId(userId);
      if (!context.mounted) return;

      if (author != null) {
        open(context, author: author, illustId: illustId);
      } else {
        BotToast.showText(text: '未找到该作者的信息');
      }
    } catch (e) {
      if (!context.mounted) return;
      BotToast.showText(text: '获取作者信息失败: $e');
    }
  }

  @override
  State<DownloadedImageOrganizerPage> createState() =>
      _DownloadedImageOrganizerPageState();
}

class _DownloadedImageOrganizerPageState
    extends State<DownloadedImageOrganizerPage> {
  late final DownloadedImageOrganizerStore store;
  late ReactionDisposer _groupReaction;

  late ScrollController _scrollController;
  late ScrollController _groupNavigatorController;
  final Map<String, double> _groupScrollOffsets = {};
  final Map<String, double> _groupNavigatorItemWidths = {};
  List<_GroupScrollOffset> _orderedGroupScrollOffsets = const [];
  final ValueNotifier<String?> _currentGroupIdNotifier = ValueNotifier<String?>(
    null,
  );

  @override
  void initState() {
    super.initState();
    store = DownloadedImageOrganizerStore(
      author: widget.author,
      initialIllustId: widget.illustId,
      illustIds: widget.illustIds,
      title: widget.title,
    );
    _scrollController = ScrollController();
    _groupNavigatorController = ScrollController();
    _scrollController.addListener(_syncCurrentGroupFromScroll);
    _currentGroupIdNotifier.addListener(_scrollCurrentGroupChipIntoView);

    _groupReaction = autorun((_) {
      final groups = store.groupedItems.toList();
      _syncGroupState(groups);
    });

    store.init();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncCurrentGroupFromScroll);
    _currentGroupIdNotifier.removeListener(_scrollCurrentGroupChipIntoView);
    _scrollController.dispose();
    _groupNavigatorController.dispose();
    _currentGroupIdNotifier.dispose();
    _groupReaction();
    super.dispose();
  }

  // ============ Action helpers (page orchestrates store) ============

  void _onSelectionFabPressed() {
    if (store.items.isEmpty) return;
    if (!store.isMultiSelectMode) {
      store.selectAllAndEnterMultiMode();
      return;
    }
    store.toggleSelectAllOrClear();
  }

  Future<void> _onFilterMenuSelected(String value) async {
    switch (value) {
      case 'toggle_webp':
        await store.toggleExcludeWebp();
      case 'toggle_ugoira':
        await store.toggleExcludeUgoira();
      case 'mode_last':
        await store.setPickMode(PerIllustPickMode.last);
      case 'mode_first':
        await store.setPickMode(PerIllustPickMode.first);
      case 'mode_all':
        await store.setPickMode(PerIllustPickMode.all);
      case 'set_count':
        final count = await _showPickCountDialog();
        if (count != null && count != store.pickCount) {
          await store.setPickCount(count);
        }
      case 'set_resolution_filter':
        final result = await _showResolutionFilterDialog();
        if (result != null) {
          await store.setResolutionFilter(
            widthOp: result.widthOp,
            widthValue: result.widthValue,
            heightOp: result.heightOp,
            heightValue: result.heightValue,
          );
        }
      case 'clear_resolution_filter':
        await store.clearResolutionFilter();
    }
  }

  // ============ Navigation ============

  Future<void> _openIllustDetail(DownloadedImageDisplayItem item) async {
    final uniqueIllusts = store.buildUniqueIllustList();
    final currentIndex = uniqueIllusts.indexWhere(
      (e) => e.illustId == item.illust.illustId,
    );
    if (currentIndex < 0) return;

    final stores =
        uniqueIllusts
            .map((illust) => IllustStore(illust.illustId, illust.toIllusts()))
            .toList();
    final currentStore = stores[currentIndex];

    await currentStore.preloadFirstImage(
      relativePath: item.illust.relativePath,
    );
    if (!mounted) return;

    Leader.push(
      context,
      PictureListPage(
        iStores: stores,
        store: currentStore,
        lightingStore: null,
        heroString: 'downloaded_illust_${item.illust.illustId}',
      ),
    );
  }

  Future<void> _openLocalImageViewer(DownloadedImageDisplayItem item) async {
    await LocalImageViewerPage.open(
      context,
      imagePath: item.path,
      title: '${item.illust.illustId} · ${item.illust.title}',
      subtitle: '${item.resolutionText} · ${item.partText}',
      heroTag: _heroTagForItem(item),
    );
  }

  String _heroTagForItem(DownloadedImageDisplayItem item) {
    return 'author_image_local_${item.id}_${item.path}';
  }

  Future<void> _openFile(String path) async {
    try {
      await OpenFile.open(path);
    } catch (e) {
      BotToast.showText(text: '打开失败: $e');
    }
  }

  Future<void> _openParentDirectory(String path) async {
    try {
      final directoryPath = File(path).parent.path;
      await FileUtils.openFileOrDirectory(directoryPath);
    } catch (e) {
      BotToast.showText(text: '打开文件夹失败: $e');
    }
  }

  void _showUpdateIllustInfoDialog() {
    UpdateIllustInfoDialog.show(
      context,
      illusts: store.buildUniqueIllustList(),
      userId: store.author?.userId,
    ).then((result) {
      if (result == true) {
        store.loadData(forceReload: true);
      }
    });
  }

  // ============ Dialogs ============

  Future<int?> _showPickCountDialog() async {
    var tempCount = store.pickCount;
    return showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('设置图片数量'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('每个作品: $tempCount 张'),
                  Slider(
                    value: tempCount.toDouble(),
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: '$tempCount',
                    onChanged: (value) {
                      setDialogState(() => tempCount = value.round());
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, tempCount),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<_ResolutionFilterDialogResult?> _showResolutionFilterDialog() async {
    var tempWidthOp = store.widthOp;
    var tempWidthValue = store.widthValue;
    var tempHeightOp = store.heightOp;
    var tempHeightValue = store.heightValue;
    final widthController = TextEditingController(
      text: tempWidthValue?.toString() ?? '',
    );
    final heightController = TextEditingController(
      text: tempHeightValue?.toString() ?? '',
    );

    final result = await showDialog<_ResolutionFilterDialogResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('分辨率过滤'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildResolutionFilterRow(
                      label: '宽',
                      op: tempWidthOp,
                      controller: widthController,
                      onOpChanged: (op) {
                        setDialogState(() => tempWidthOp = op);
                      },
                      onValueChanged: (value) {
                        tempWidthValue = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildResolutionFilterRow(
                      label: '高',
                      op: tempHeightOp,
                      controller: heightController,
                      onOpChanged: (op) {
                        setDialogState(() => tempHeightOp = op);
                      },
                      onValueChanged: (value) {
                        tempHeightValue = value;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      const _ResolutionFilterDialogResult(
                        widthOp: ResolutionFilterOp.none,
                        widthValue: null,
                        heightOp: ResolutionFilterOp.none,
                        heightValue: null,
                      ),
                    );
                  },
                  child: const Text('清空'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      _ResolutionFilterDialogResult(
                        widthOp: tempWidthOp,
                        widthValue: tempWidthValue,
                        heightOp: tempHeightOp,
                        heightValue: tempHeightValue,
                      ),
                    );
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );

    widthController.dispose();
    heightController.dispose();
    return result;
  }

  Widget _buildResolutionFilterRow({
    required String label,
    required ResolutionFilterOp op,
    required TextEditingController controller,
    required ValueChanged<ResolutionFilterOp> onOpChanged,
    required ValueChanged<int?> onValueChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 20, child: Text(label)),
        const SizedBox(width: 8),
        DropdownButton<ResolutionFilterOp>(
          value: op,
          items:
              ResolutionFilterOp.values
                  .map(
                    (e) => DropdownMenuItem<ResolutionFilterOp>(
                      value: e,
                      child: Text(_resolutionOpLabel(e)),
                    ),
                  )
                  .toList(),
          onChanged: (value) {
            if (value != null) {
              onOpChanged(value);
            }
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '像素值', isDense: true),
            onChanged: (value) {
              final parsed = int.tryParse(value.trim());
              onValueChanged(parsed != null && parsed > 0 ? parsed : null);
            },
          ),
        ),
      ],
    );
  }

  String _resolutionOpLabel(ResolutionFilterOp op) {
    return switch (op) {
      ResolutionFilterOp.none => '不限制',
      ResolutionFilterOp.gt => '大于',
      ResolutionFilterOp.lt => '小于',
    };
  }

  // ============ Build ============

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        return PopScope(
          canPop: !store.isMultiSelectMode,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (store.isMultiSelectMode) {
              store.exitMultiSelectMode();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: Icon(
                  store.isMultiSelectMode ? Icons.close : Icons.arrow_back,
                ),
                tooltip: store.isMultiSelectMode ? '退出多选' : '返回',
                onPressed: () async {
                  if (store.isMultiSelectMode) {
                    store.exitMultiSelectMode();
                    return;
                  }
                  await Navigator.maybePop(context);
                },
              ),
              title: Text(
                store.isMultiSelectMode
                    ? '已选 ${store.selectedItemIds.length} / 共 ${store.items.length}'
                    : '${store.titlePrefix} · 共 ${store.items.length} 张',
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: PopupMenuButton<GroupType>(
                    initialValue: store.groupType,
                    tooltip: '分组方式',
                    position: PopupMenuPosition.under,
                    onSelected:
                        store.loading
                            ? null
                            : (value) => store.setGroupType(value),
                    itemBuilder:
                        (context) =>
                            GroupType.values
                                .map(
                                  (type) => PopupMenuItem<GroupType>(
                                    value: type,
                                    child: Text(store.groupTypeLabel(type)),
                                  ),
                                )
                                .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.layers_outlined, size: 20),
                          const SizedBox(width: 4),
                          Text(store.groupTypeLabel(store.groupType)),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: PopupMenuButton<SortType>(
                    initialValue: store.sortType,
                    tooltip: '排序方式',
                    position: PopupMenuPosition.under,
                    onSelected:
                        store.loading
                            ? null
                            : (value) => store.setSortType(value),
                    itemBuilder:
                        (context) =>
                            SortType.values
                                .map(
                                  (type) => PopupMenuItem<SortType>(
                                    value: type,
                                    child: Text(store.sortTypeLabel(type)),
                                  ),
                                )
                                .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(store.sortTypeLabel(store.sortType)),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    store.sortOrder == SortOrder.asc
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                  ),
                  tooltip: store.sortOrder == SortOrder.asc ? '正序' : '倒序',
                  onPressed:
                      store.loading ? null : () => store.toggleSortOrder(),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.filter_alt_outlined),
                  tooltip: '筛选条件',
                  position: PopupMenuPosition.under,
                  onSelected: _onFilterMenuSelected,
                  itemBuilder: (context) {
                    return [
                      CheckedPopupMenuItem(
                        value: 'toggle_webp',
                        checked: store.excludeWebp,
                        child: const Text('排除 WebP'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'toggle_ugoira',
                        checked: store.excludeUgoira,
                        child: const Text('排除动图'),
                      ),
                      const PopupMenuDivider(),
                      CheckedPopupMenuItem(
                        value: 'mode_last',
                        checked: store.pickMode == PerIllustPickMode.last,
                        child: const Text('最后几张'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'mode_first',
                        checked: store.pickMode == PerIllustPickMode.first,
                        child: const Text('最前几张'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'mode_all',
                        checked: store.pickMode == PerIllustPickMode.all,
                        child: const Text('所有'),
                      ),
                      PopupMenuItem(
                        value: 'set_count',
                        child: Text('每作品数量: ${store.pickCount}'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'set_resolution_filter',
                        child: Text('分辨率过滤设置'),
                      ),
                      const PopupMenuItem(
                        value: 'clear_resolution_filter',
                        child: Text('清空分辨率过滤'),
                      ),
                    ];
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.update),
                  tooltip:
                      store.hasAuthorContext ? '扫描并更新作者作品信息' : '扫描并更新当前页面作品信息',
                  onPressed: store.loading ? null : _showUpdateIllustInfoDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '列表刷新',
                  onPressed:
                      store.loading
                          ? null
                          : () => store.loadData(forceReload: true),
                ),
                if (store.illustIdFilter != null && !store.isMultiSelectMode)
                  IconButton(
                    icon: const Icon(Icons.filter_alt_off),
                    tooltip: '清除作品 ID 过滤',
                    onPressed: () => store.clearIllustIdFilter(),
                  ),
                IconButton(
                  icon: Icon(
                    store.isMultiSelectMode
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                  ),
                  tooltip: store.isMultiSelectMode ? '退出多选' : '进入多选',
                  onPressed: () => store.toggleMultiSelectMode(),
                ),
              ],
            ),
            body: _buildBody(),
            floatingActionButton: _buildSelectionFab(),
          ),
        );
      },
    );
  }

  Widget? _buildSelectionFab() {
    if (store.loading || store.error != null || store.items.isEmpty) {
      return null;
    }
    final isAllSelected =
        store.isMultiSelectMode &&
        store.selectedItemIds.length == store.items.length;
    return FloatingActionButton.extended(
      onPressed: _onSelectionFabPressed,
      icon: Icon(isAllSelected ? Icons.deselect : Icons.select_all),
      label: Text(isAllSelected ? '全不选' : '全选'),
      tooltip: isAllSelected ? '全不选' : '全选',
    );
  }

  Widget _buildBody() {
    if (store.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (store.error != null) {
      return Center(child: Text('加载失败: ${store.error}'));
    }
    if (store.items.isEmpty) {
      return const Center(child: Text('没有符合条件的图片'));
    }

    return Column(
      children: [
        _buildGroupNavigator(),
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices:
                  ScrollConfiguration.of(context).dragDevices
                      .where((k) => k != PointerDeviceKind.mouse)
                      .toSet(),
            ),
            child: _buildGroupedGrid(),
          ),
        ),
      ],
    );
  }

  // ============ Group navigator & scroll ============

  Widget _buildGroupedGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _buildGridLayout(constraints.maxWidth);
        _cacheGroupScrollOffsets(_calculateGroupScrollOffsets(layout));

        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            for (final entry in store.groupedItems.asMap().entries)
              _buildGroupSliver(entry.value, entry.key),
            if (store.groupedItems.length > 1)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: math.max(
                    0.0,
                    constraints.maxHeight - _kGroupHeaderExtent,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildGroupSliver(GroupedItems group, int groupIndex) {
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyHeaderDelegate(
            child: _buildGroupHeader(group, groupIndex),
            minHeight: _kGroupHeaderExtent,
            maxHeight: _kGroupHeaderExtent,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(_kGridPadding),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _kGridMaxCrossAxisExtent,
              childAspectRatio: _kGridChildAspectRatio,
              crossAxisSpacing: _kGridCrossAxisSpacing,
              mainAxisSpacing: _kGridMainAxisSpacing,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = group.items[index];
                return _buildDraggableCard(
                  item,
                  store.selectedItemIds.contains(item.id),
                );
              },
              childCount: group.items.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
            ),
          ),
        ),
      ],
    );
  }

  _GridLayout _buildGridLayout(double maxWidth) {
    final crossAxisExtent = math.max(0.0, maxWidth - _kGridPadding * 2);
    final columnCount = math.max(
      1,
      (crossAxisExtent / (_kGridMaxCrossAxisExtent + _kGridCrossAxisSpacing))
          .ceil(),
    );
    final usableCrossAxisExtent = math.max(
      0.0,
      crossAxisExtent - _kGridCrossAxisSpacing * (columnCount - 1),
    );
    final tileWidth = usableCrossAxisExtent / columnCount;
    return _GridLayout(
      columnCount: columnCount,
      tileWidth: tileWidth,
      tileHeight: tileWidth / _kGridChildAspectRatio,
    );
  }

  List<_GroupScrollOffset> _calculateGroupScrollOffsets(_GridLayout layout) {
    final offsets = <_GroupScrollOffset>[];
    var scrollOffset = 0.0;

    for (final entry in store.groupedItems.asMap().entries) {
      final group = entry.value;
      offsets.add(_GroupScrollOffset(group.id, scrollOffset));
      scrollOffset += _kGroupHeaderExtent;
      final rowCount = (group.items.length / layout.columnCount).ceil();
      if (rowCount > 0) {
        scrollOffset +=
            _kGridPadding * 2 +
            rowCount * layout.tileHeight +
            math.max(0, rowCount - 1) * _kGridMainAxisSpacing;
      }
    }

    return offsets;
  }

  Widget _buildGroupNavigator() {
    if (store.groupedItems.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView.separated(
        controller: _groupNavigatorController,
        scrollDirection: Axis.horizontal,
        itemCount: store.groupedItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final group = store.groupedItems[index];
          return _GroupNavigatorItemMeasure(
            onSizeChanged:
                (width) => _recordGroupNavigatorItemWidth(group.id, width),
            child: ValueListenableBuilder<String?>(
              valueListenable: _currentGroupIdNotifier,
              child: Text(group.title),
              builder: (context, currentGroupId, label) {
                return ChoiceChip(
                  label: label!,
                  selected: currentGroupId == group.id,
                  onSelected: (_) => _scrollToGroup(group),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _syncGroupState(List<GroupedItems> groups) {
    final ids = groups.map((e) => e.id).toSet();
    _groupScrollOffsets.removeWhere((id, _) => !ids.contains(id));
    _groupNavigatorItemWidths.removeWhere((id, _) => !ids.contains(id));
    _orderedGroupScrollOffsets =
        _orderedGroupScrollOffsets
            .where((e) => ids.contains(e.groupId))
            .toList();
    final currentGroupId = _currentGroupIdNotifier.value;
    if (currentGroupId == null || !ids.contains(currentGroupId)) {
      _setCurrentGroupId(groups.isNotEmpty ? groups.first.id : null);
    }
  }

  void _cacheGroupScrollOffsets(List<_GroupScrollOffset> offsets) {
    _orderedGroupScrollOffsets = offsets;
    _groupScrollOffsets
      ..clear()
      ..addEntries(offsets.map((e) => MapEntry(e.groupId, e.offset)));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncCurrentGroupFromScroll();
      }
    });
  }

  Future<void> _scrollToGroup(GroupedItems group) async {
    _setCurrentGroupId(group.id);

    var targetOffset = _groupScrollOffsets[group.id];
    if (targetOffset == null) {
      await WidgetsBinding.instance.endOfFrame;
      targetOffset = _groupScrollOffsets[group.id];
    }
    if (targetOffset == null || !_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    final clampedOffset = targetOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    await _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
  }

  void _syncCurrentGroupFromScroll() {
    if (!_scrollController.hasClients || _orderedGroupScrollOffsets.isEmpty) {
      return;
    }

    final offset = _scrollController.offset + 1;
    var low = 0;
    var high = _orderedGroupScrollOffsets.length - 1;
    var visibleGroupId = _orderedGroupScrollOffsets.first.groupId;

    while (low <= high) {
      final middle = (low + high) >> 1;
      final entry = _orderedGroupScrollOffsets[middle];
      if (entry.offset <= offset) {
        visibleGroupId = entry.groupId;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }

    _setCurrentGroupId(visibleGroupId);
  }

  void _setCurrentGroupId(String? groupId) {
    if (_currentGroupIdNotifier.value == groupId) return;
    _currentGroupIdNotifier.value = groupId;
  }

  void _recordGroupNavigatorItemWidth(String groupId, double width) {
    if (width <= 0) return;
    final oldWidth = _groupNavigatorItemWidths[groupId];
    if (oldWidth != null && (oldWidth - width).abs() < 0.5) return;
    _groupNavigatorItemWidths[groupId] = width;
    if (_currentGroupIdNotifier.value == groupId) {
      _scrollCurrentGroupChipIntoView();
    }
  }

  void _scrollCurrentGroupChipIntoView() {
    final groupId = _currentGroupIdNotifier.value;
    if (groupId == null || !_groupNavigatorController.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_groupNavigatorController.hasClients) return;
      final range = _groupNavigatorItemRange(groupId);
      if (range == null) return;

      const margin = 8.0;
      final position = _groupNavigatorController.position;
      final visibleStart = position.pixels;
      final visibleEnd = visibleStart + position.viewportDimension;
      double? targetOffset;

      if (range.start < visibleStart + margin) {
        targetOffset = range.start - margin;
      } else if (range.end > visibleEnd - margin) {
        targetOffset = range.end - position.viewportDimension + margin;
      }

      if (targetOffset == null) return;
      final clampedOffset = targetOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((clampedOffset - position.pixels).abs() < 0.5) return;
      _groupNavigatorController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  _HorizontalRange? _groupNavigatorItemRange(String groupId) {
    var offset = 0.0;
    for (final group in store.groupedItems) {
      final width = _groupNavigatorItemWidths[group.id];
      if (width == null) return null;
      if (group.id == groupId) {
        return _HorizontalRange(start: offset, end: offset + width);
      }
      offset += width + 8;
    }
    return null;
  }

  Widget _buildGroupHeader(GroupedItems group, int index) {
    final allSelected = group.items.every(
      (item) => store.selectedItemIds.contains(item.id),
    );
    final anySelected = group.items.any(
      (item) => store.selectedItemIds.contains(item.id),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (store.isMultiSelectMode)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                allSelected
                    ? Icons.check_box
                    : (anySelected
                        ? Icons.indeterminate_check_box
                        : Icons.check_box_outline_blank),
                size: 20,
              ),
              onPressed: () => store.toggleGroupSelection(group),
              tooltip: allSelected ? '全组取消选中' : '全组选中',
            ),
        ],
      ),
    );
  }

  // ============ Card & drag ============

  Widget _buildDraggableCard(DownloadedImageDisplayItem item, bool isSelected) {
    final card = _buildCard(item, isSelected);
    return DragItemWidget(
      dragItemProvider: _createDragItemProvider,
      allowedOperations: () => [DropOperation.copy, DropOperation.link],
      dragBuilder: (context, child) => _buildDragPreview(child, item),
      child: DraggableWidget(
        child: card,
        onDragConfiguration: (config, session) {
          return _createDragConfiguration(config, item);
        },
      ),
    );
  }

  Widget _buildCard(DownloadedImageDisplayItem item, bool isSelected) {
    return _AuthorImageCard(
      item: item,
      isSelected: isSelected,
      isMultiSelectMode: store.isMultiSelectMode,
      heroTag: _heroTagForItem(item),
      onTap: () {
        if (store.isMultiSelectMode) {
          store.setSelected(item.id, !isSelected);
        } else {
          _openLocalImageViewer(item);
        }
      },
      onLongPress: () {
        if (!store.isMultiSelectMode) {
          store.selectItemAndEnterMultiMode(item.id);
        }
      },
      onOpenFile: () => _openFile(item.path),
      onOpenParentDirectory: () => _openParentDirectory(item.path),
      onOpenIllustDetail: () => _openIllustDetail(item),
      onOpenLocalImageViewer: () => _openLocalImageViewer(item),
    );
  }

  DragConfiguration? _createDragConfiguration(
    DragConfiguration config,
    DownloadedImageDisplayItem item,
  ) {
    final snapshot = config.items.isNotEmpty ? config.items.first.image : null;
    if (snapshot == null) return null;

    final ids = <String>[];
    if (store.isMultiSelectMode && store.selectedItemIds.contains(item.id)) {
      ids.addAll(store.selectedItemIds);
    } else {
      ids.add(item.id);
    }

    final dragItems = <DragConfigurationItem>[];
    for (final id in ids) {
      final target = store.itemMap[id];
      if (target == null) continue;
      final dragItem = DragItem();
      dragItem.add(Formats.fileUri(Uri.file(target.path)));
      dragItems.add(DragConfigurationItem(item: dragItem, image: snapshot));
    }
    if (dragItems.isEmpty) return null;

    return DragConfiguration(
      items: dragItems,
      allowedOperations: config.allowedOperations,
      options: config.options,
    );
  }

  Widget _buildDragPreview(Widget child, DownloadedImageDisplayItem item) {
    final count =
        store.isMultiSelectMode && store.selectedItemIds.contains(item.id)
            ? store.selectedItemIds.length
            : 1;

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 160,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (count > 1)
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<DragItem> _createDragItemProvider(DragItemRequest request) async {
    final item = DragItem();
    item.add(Formats.plainText('PixEz Author Image Organizer'));
    return item;
  }
}

// ============ Private widget classes ============

class _AuthorImageCard extends StatelessWidget {
  final DownloadedImageDisplayItem item;
  final bool isSelected;
  final bool isMultiSelectMode;
  final String heroTag;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenParentDirectory;
  final VoidCallback onOpenIllustDetail;
  final VoidCallback onOpenLocalImageViewer;

  const _AuthorImageCard({
    required this.item,
    required this.isSelected,
    required this.isMultiSelectMode,
    required this.heroTag,
    required this.onTap,
    required this.onLongPress,
    required this.onOpenFile,
    required this.onOpenParentDirectory,
    required this.onOpenIllustDetail,
    required this.onOpenLocalImageViewer,
  });

  @override
  Widget build(BuildContext context) {
    return HoverScaleCard(
      isSelected: isSelected,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: heroTag,
                        child: PixivImage(
                          Uri.file(item.path).toString(),
                          fit: BoxFit.cover,
                          memCacheWidth: 250,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: _CardOverlayButton(
                          icon: Icons.open_in_new,
                          onTap: onOpenFile,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        left: 38,
                        child: _CardOverlayButton(
                          icon: Icons.folder_open,
                          onTap: onOpenParentDirectory,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: _CardOverlayButton(
                          icon: Icons.info_outline,
                          onTap: onOpenIllustDetail,
                        ),
                      ),
                      if (isMultiSelectMode)
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: _CardOverlayButton(
                            icon: Icons.zoom_in,
                            onTap: onOpenLocalImageViewer,
                          ),
                        ),
                      if (isMultiSelectMode)
                        Positioned(
                          top: 4,
                          right: 38,
                          child: _SelectionBadge(isSelected: isSelected),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.illust.illustId} · ${item.illust.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.resolutionText} · ${item.fileSize.formatFileSize()} · ${item.imageType} · ${item.partText}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardOverlayButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CardOverlayButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}

class _SelectionBadge extends StatelessWidget {
  final bool isSelected;

  const _SelectionBadge({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            isSelected ? Theme.of(context).colorScheme.primary : Colors.black45,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child:
            isSelected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : const SizedBox(width: 16, height: 16),
      ),
    );
  }
}

class _GroupNavigatorItemMeasure extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onSizeChanged;

  const _GroupNavigatorItemMeasure({
    required this.onSizeChanged,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _GroupNavigatorItemMeasureRenderObject(onSizeChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _GroupNavigatorItemMeasureRenderObject renderObject,
  ) {
    renderObject.onSizeChanged = onSizeChanged;
  }
}

class _GroupNavigatorItemMeasureRenderObject extends RenderProxyBox {
  ValueChanged<double> onSizeChanged;
  double? _lastWidth;

  _GroupNavigatorItemMeasureRenderObject(this.onSizeChanged);

  @override
  void performLayout() {
    super.performLayout();
    final width = size.width;
    if (_lastWidth != null && (_lastWidth! - width).abs() < 0.5) return;
    _lastWidth = width;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onSizeChanged(width);
    });
  }
}

class _HorizontalRange {
  final double start;
  final double end;

  const _HorizontalRange({required this.start, required this.end});
}

class _GridLayout {
  final int columnCount;
  final double tileWidth;
  final double tileHeight;

  const _GridLayout({
    required this.columnCount,
    required this.tileWidth,
    required this.tileHeight,
  });
}

class _GroupScrollOffset {
  final String groupId;
  final double offset;

  const _GroupScrollOffset(this.groupId, this.offset);
}

class _ResolutionFilterDialogResult {
  final ResolutionFilterOp widthOp;
  final int? widthValue;
  final ResolutionFilterOp heightOp;
  final int? heightValue;

  const _ResolutionFilterDialogResult({
    required this.widthOp,
    required this.widthValue,
    required this.heightOp,
    required this.heightValue,
  });
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double minHeight;
  final double maxHeight;

  _StickyHeaderDelegate({
    required this.child,
    required this.minHeight,
    required this.maxHeight,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  double get maxExtent => maxHeight;

  @override
  double get minExtent => minHeight;

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.child != child ||
        oldDelegate.minHeight != minHeight ||
        oldDelegate.maxHeight != maxHeight;
  }
}
