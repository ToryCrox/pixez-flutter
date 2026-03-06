import 'dart:io';
import 'dart:ui';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:pixez/er/leader.dart';
import 'package:open_file/open_file.dart';
import 'package:pixez/component/hover_scale_container.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/author_image_filter_conditions.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/picture_list_page.dart';
import 'package:pixez/utils/file_utils.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class AuthorImageOrganizerPage extends StatefulWidget {
  final DownloadedAuthor author;

  const AuthorImageOrganizerPage({super.key, required this.author});

  static Future<T?> open<T>(
    BuildContext context, {
    required DownloadedAuthor author,
  }) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(
        builder: (context) => AuthorImageOrganizerPage(author: author),
      ),
    );
  }

  @override
  State<AuthorImageOrganizerPage> createState() =>
      _AuthorImageOrganizerPageState();
}

class _AuthorImageOrganizerPageState extends State<AuthorImageOrganizerPage> {
  bool _loading = true;
  String? _error;
  List<_AuthorImageDisplayItem> _items = const [];
  bool _isMultiSelectMode = false;
  final Set<String> _selectedItemIds = {};
  final Map<String, _AuthorImageDisplayItem> _itemMap = {};

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  /// 核心加载流程：
  /// 1. 查询作者全部插画
  /// 2. 分片批量查询图片记录（每批最多50个illustId）
  /// 3. 执行可扩展筛选条件链
  /// 4. 解析本地路径并组装展示数据
  Future<void> _loadItems() async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedItemIds.clear();
      _itemMap.clear();
    });

    try {
      final illusts = await downloadStore.getDownloadedByUser(
        widget.author.userId,
        limit: null,
        offset: 0,
        orderBy: '${DownloadedIllustColumns.downloadTime} DESC',
      );

      final illustIds = illusts.map((e) => e.illustId).toList();
      final imagesByIllustId = await _loadImagesByIllustIdsBatched(illustIds);

      final context = AuthorImageFilterContext(
        author: widget.author,
        illusts: illusts,
        imagesByIllustId: imagesByIllustId,
      );
      final filterEngine = AuthorImageFilterEngine.defaultEngine();
      final candidates = await filterEngine.run(context);

      final resolved = await Future.wait(
        candidates.map(_resolveDisplayItemFromCandidate),
      );
      final displayItems =
          resolved.whereType<_AuthorImageDisplayItem>().toList();

      displayItems.sort((a, b) {
        final t = b.illust.downloadTime.compareTo(a.illust.downloadTime);
        if (t != 0) return t;
        final i = b.illust.illustId.compareTo(a.illust.illustId);
        if (i != 0) return i;
        return b.image.part.compareTo(a.image.part);
      });

      for (final item in displayItems) {
        _itemMap[item.id] = item;
      }

      if (!mounted) return;
      setState(() {
        _items = displayItems;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 按批次调用 getImagesByIllustIds，避免单次传参过大。
  /// 约束：每批最多 50 个 illustId。
  Future<Map<int, List<DownloadedImage>>> _loadImagesByIllustIdsBatched(
    List<int> illustIds,
  ) async {
    const batchSize = 50;
    final result = <int, List<DownloadedImage>>{};
    for (var i = 0; i < illustIds.length; i += batchSize) {
      final end =
          (i + batchSize < illustIds.length) ? i + batchSize : illustIds.length;
      final chunk = illustIds.sublist(i, end);
      final chunkMap = await downloadStore.dbProvider.getImagesByIllustIds(
        chunk,
      );
      result.addAll(chunkMap);
    }
    return result;
  }

  /// 将筛选后的候选项解析为可展示项（补齐本地文件路径）。
  Future<_AuthorImageDisplayItem?> _resolveDisplayItemFromCandidate(
    AuthorImageCandidate candidate,
  ) async {
    final path = await downloadStore.getLocalImagePathFromImage(
      candidate.image,
      relativePath: candidate.illust.relativePath,
      isUgoira: candidate.illust.isUgoira,
    );
    if (path == null) return null;

    return _AuthorImageDisplayItem(
      illust: candidate.illust,
      image: candidate.image,
      path: path,
    );
  }

  void _toggleSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) {
        _selectedItemIds.clear();
      }
    });
  }

  void _setSelected(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedItemIds.add(id);
      } else {
        _selectedItemIds.remove(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedItemIds
        ..clear()
        ..addAll(_items.map((e) => e.id));
    });
  }

  /// 进入插画详情页（与下载页一致，传入当前筛选结果中的插画列表）。
  Future<void> _openIllustDetail(_AuthorImageDisplayItem item) async {
    final uniqueIllusts = _buildUniqueIllustList();
    final currentIndex = uniqueIllusts.indexWhere(
      (e) => e.illustId == item.illust.illustId,
    );
    if (currentIndex < 0) return;

    final stores =
        uniqueIllusts
            .map((illust) => IllustStore(illust.illustId, illust.toIllusts()))
            .toList();
    final currentStore = stores[currentIndex];

    // 预加载首图，减少详情页首屏抖动。
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

  /// 由图片列表提取去重后的插画列表，保持当前展示顺序。
  List<DownloadedIllust> _buildUniqueIllustList() {
    final result = <DownloadedIllust>[];
    final seen = <int>{};
    for (final item in _items) {
      if (seen.add(item.illust.illustId)) {
        result.add(item.illust);
      }
    }
    return result;
  }

  /// 打开本地文件（外部程序）。
  Future<void> _openFile(String path) async {
    try {
      await OpenFile.open(path);
    } catch (e) {
      BotToast.showText(text: '打开失败: $e');
    }
  }

  /// 打开图片所在文件夹。
  Future<void> _openParentDirectory(String path) async {
    try {
      final directoryPath = File(path).parent.path;
      await FileUtils.openFileOrDirectory(directoryPath);
    } catch (e) {
      BotToast.showText(text: '打开文件夹失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isMultiSelectMode
              ? '${widget.author.userName} · 已选 ${_selectedItemIds.length}'
              : '${widget.author.userName} 图片整理',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loading ? null : _loadItems,
          ),
          if (_isMultiSelectMode)
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
              onPressed: _items.isEmpty ? null : _selectAll,
            ),
          if (_isMultiSelectMode)
            IconButton(
              icon: const Icon(Icons.deselect),
              tooltip: '清空选择',
              onPressed:
                  _selectedItemIds.isEmpty
                      ? null
                      : () {
                        setState(() {
                          _selectedItemIds.clear();
                        });
                      },
            ),
          IconButton(
            icon: Icon(
              _isMultiSelectMode
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
            ),
            tooltip: _isMultiSelectMode ? '退出多选' : '进入多选',
            onPressed: _toggleSelectMode,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('加载失败: $_error'));
    }
    if (_items.isEmpty) {
      return const Center(child: Text('没有符合条件的图片'));
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices:
            ScrollConfiguration.of(
              context,
            ).dragDevices.where((k) => k != PointerDeviceKind.mouse).toSet(),
      ),
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 210,
          childAspectRatio: 0.73,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          final selected = _selectedItemIds.contains(item.id);
          return _buildDraggableCard(item, selected);
        },
      ),
    );
  }

  Widget _buildDraggableCard(_AuthorImageDisplayItem item, bool isSelected) {
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

  Widget _buildCard(_AuthorImageDisplayItem item, bool isSelected) {
    return HoverScaleCard(
      isSelected: isSelected,
      child: InkWell(
        onTap: () {
          if (_isMultiSelectMode) {
            _setSelected(item.id, !isSelected);
          } else {
            _openIllustDetail(item);
          }
        },
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(item.path),
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => const ColoredBox(
                              color: Colors.black12,
                              child: Center(child: Icon(Icons.broken_image)),
                            ),
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _openFile(item.path),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        left: 38,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _openParentDirectory(item.path),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.folder_open,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_isMultiSelectMode)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: _buildSelectionBadge(isSelected),
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
                        item.fileNameWithExt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        '${item.resolutionText} · ${item.fileSize.formatFileSize()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.illust.illustId} · ${item.illust.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
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

  Widget _buildSelectionBadge(bool isSelected) {
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

  DragConfiguration? _createDragConfiguration(
    DragConfiguration config,
    _AuthorImageDisplayItem item,
  ) {
    final snapshot = config.items.isNotEmpty ? config.items.first.image : null;
    if (snapshot == null) return null;

    final ids = <String>[];
    if (_isMultiSelectMode && _selectedItemIds.contains(item.id)) {
      ids.addAll(_selectedItemIds);
    } else {
      ids.add(item.id);
    }

    final dragItems = <DragConfigurationItem>[];
    for (final id in ids) {
      final target = _itemMap[id];
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

  Widget _buildDragPreview(Widget child, _AuthorImageDisplayItem item) {
    final count =
        _isMultiSelectMode && _selectedItemIds.contains(item.id)
            ? _selectedItemIds.length
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

class _AuthorImageDisplayItem {
  final DownloadedIllust illust;
  final DownloadedImage image;
  final String path;

  const _AuthorImageDisplayItem({
    required this.illust,
    required this.image,
    required this.path,
  });

  String get id => '${illust.illustId}_${image.part}';

  int get fileSize => image.fileSize;

  /// 文件名（包含后缀）。
  String get fileNameWithExt => image.getFullFileName();

  /// 分辨率展示文案。
  String get resolutionText {
    final w = image.width;
    final h = image.height;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return '未知分辨率';
    }
    return '${w}x$h';
  }
}
