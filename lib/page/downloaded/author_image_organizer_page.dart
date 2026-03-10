import 'dart:io';
import 'dart:ui';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/er/leader.dart';
import 'package:open_file/open_file.dart';
import 'package:pixez/component/hover_scale_container.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/author_image_filter_conditions.dart';
import 'package:pixez/page/downloaded/local_image_viewer_page.dart';
import 'package:pixez/page/downloaded/update_illust_info_dialog.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/picture_list_page.dart';
import 'package:pixez/utils/file_utils.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

enum _PerIllustPickMode { last, first, all }

enum _SortType { idAndPart, downloadTime, fileSize, width, height, area }

enum _SortOrder { asc, desc }

enum _GroupType { none, date, illust, type, resolution }

// 筛选项持久化 key（仅在当前页面使用，不放入 UserSetting）。
const String _kAuthorOrganizerExcludeWebpKey = 'author_organizer_exclude_webp';
const String _kAuthorOrganizerExcludeUgoiraKey =
    'author_organizer_exclude_ugoira';
const String _kAuthorOrganizerPickModeKey = 'author_organizer_pick_mode';
const String _kAuthorOrganizerPickCountKey = 'author_organizer_pick_count';
const String _kAuthorOrganizerSortTypeKey = 'author_organizer_sort_type';
const String _kAuthorOrganizerSortOrderKey = 'author_organizer_sort_order';
const String _kAuthorOrganizerWidthOpKey = 'author_organizer_width_op';
const String _kAuthorOrganizerWidthValueKey = 'author_organizer_width_value';
const String _kAuthorOrganizerHeightOpKey = 'author_organizer_height_op';
const String _kAuthorOrganizerHeightValueKey = 'author_organizer_height_value';
const String _kAuthorOrganizerGroupTypeKey = 'author_organizer_group_type';

class AuthorImageOrganizerPage extends StatefulWidget {
  final DownloadedAuthor author;
  final int? illustId;

  const AuthorImageOrganizerPage({
    super.key,
    required this.author,
    this.illustId,
  });

  static Future<T?> open<T>(
    BuildContext context, {
    required DownloadedAuthor author,
    int? illustId,
  }) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(
        builder: (context) {
          return AuthorImageOrganizerPage(author: author, illustId: illustId);
        },
      ),
    );
  }

  /// 封装通过 userId 查询作者并跳转的公共逻辑
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
  State<AuthorImageOrganizerPage> createState() =>
      _AuthorImageOrganizerPageState();
}

class _AuthorImageOrganizerPageState extends State<AuthorImageOrganizerPage> {
  bool _loading = true;
  String? _error;
  List<_AuthorImageDisplayItem> _items = const [];
  List<_GroupedItems> _groupedItems = const [];

  // 原始数据缓存
  List<DownloadedIllust>? _rawIllusts;
  Map<int, List<DownloadedImage>>? _rawImagesByIllustId;
  // 已过滤并解析路径的所有项（中间状态，用于快速排序/分组）
  List<_AuthorImageDisplayItem> _allFilteredItems = const [];

  bool _isMultiSelectMode = false;
  final Set<String> _selectedItemIds = {};
  final Map<String, _AuthorImageDisplayItem> _itemMap = {};
  bool _excludeWebp = true;
  bool _excludeUgoira = true;
  _PerIllustPickMode _pickMode = _PerIllustPickMode.all;
  int _pickCount = 4;
  ResolutionFilterOp _widthOp = ResolutionFilterOp.none;
  int? _widthValue;
  ResolutionFilterOp _heightOp = ResolutionFilterOp.none;
  int? _heightValue;
  _SortType _sortType = _SortType.idAndPart;
  _SortOrder _sortOrder = _SortOrder.asc;
  _GroupType _groupType = _GroupType.none;
  int? _illustIdFilter;
  late final _isTempFilter = widget.illustId != null;

  late ScrollController _scrollController;
  late SliverObserverController _sliverObserverController;
  final Map<String, GlobalKey> _groupHeaderKeys = {};
  final Map<String, GlobalKey> _groupObserveKeys = {};
  final Map<String, GlobalKey> _groupGridKeys = {};
  String? _currentGroupId;

  @override
  void initState() {
    super.initState();
    _illustIdFilter = widget.illustId;
    _scrollController = ScrollController();
    _sliverObserverController = SliverObserverController(
      controller: _scrollController,
    );
    _loadFilterPrefs();

    if (_isTempFilter) {
      // 如果是通过指定作品 ID 进入，临时禁用所有筛选条件
      _excludeWebp = false;
      _excludeUgoira = false;
      _pickMode = _PerIllustPickMode.all;
      _widthOp = ResolutionFilterOp.none;
      _heightOp = ResolutionFilterOp.none;
    }

    _loadData(forceReload: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 从 UserSetting.prefs 读取筛选配置。
  void _loadFilterPrefs() {
    _excludeWebp =
        userSetting.prefs.getBool(_kAuthorOrganizerExcludeWebpKey) ?? true;
    _excludeUgoira =
        userSetting.prefs.getBool(_kAuthorOrganizerExcludeUgoiraKey) ?? true;

    final modeIndex = userSetting.prefs.getInt(_kAuthorOrganizerPickModeKey);
    if (modeIndex != null &&
        modeIndex >= 0 &&
        modeIndex < _PerIllustPickMode.values.length) {
      _pickMode = _PerIllustPickMode.values[modeIndex];
    }

    final pickCount = userSetting.prefs.getInt(_kAuthorOrganizerPickCountKey);
    if (pickCount != null) {
      _pickCount = pickCount.clamp(1, 20);
    }

    final widthOpIndex = userSetting.prefs.getInt(_kAuthorOrganizerWidthOpKey);
    if (widthOpIndex != null &&
        widthOpIndex >= 0 &&
        widthOpIndex < ResolutionFilterOp.values.length) {
      _widthOp = ResolutionFilterOp.values[widthOpIndex];
    }
    final widthValue = userSetting.prefs.getInt(_kAuthorOrganizerWidthValueKey);
    if (widthValue != null && widthValue > 0) {
      _widthValue = widthValue;
    }

    final heightOpIndex = userSetting.prefs.getInt(
      _kAuthorOrganizerHeightOpKey,
    );
    if (heightOpIndex != null &&
        heightOpIndex >= 0 &&
        heightOpIndex < ResolutionFilterOp.values.length) {
      _heightOp = ResolutionFilterOp.values[heightOpIndex];
    }
    final heightValue = userSetting.prefs.getInt(
      _kAuthorOrganizerHeightValueKey,
    );
    if (heightValue != null && heightValue > 0) {
      _heightValue = heightValue;
    }

    final sortTypeIndex = userSetting.prefs.getInt(
      _kAuthorOrganizerSortTypeKey,
    );
    if (sortTypeIndex != null &&
        sortTypeIndex >= 0 &&
        sortTypeIndex < _SortType.values.length) {
      _sortType = _SortType.values[sortTypeIndex];
    }
    final sortOrderIndex = userSetting.prefs.getInt(
      _kAuthorOrganizerSortOrderKey,
    );
    if (sortOrderIndex != null &&
        sortOrderIndex >= 0 &&
        sortOrderIndex < _SortOrder.values.length) {
      _sortOrder = _SortOrder.values[sortOrderIndex];
    }

    final groupTypeIndex = userSetting.prefs.getInt(
      _kAuthorOrganizerGroupTypeKey,
    );
    if (groupTypeIndex != null &&
        groupTypeIndex >= 0 &&
        groupTypeIndex < _GroupType.values.length) {
      _groupType = _GroupType.values[groupTypeIndex];
    }
  }

  /// 将筛选配置写入 UserSetting.prefs。
  Future<void> _persistFilterPrefs() async {
    if (_isTempFilter) return;
    await userSetting.prefs.setBool(
      _kAuthorOrganizerExcludeWebpKey,
      _excludeWebp,
    );
    await userSetting.prefs.setBool(
      _kAuthorOrganizerExcludeUgoiraKey,
      _excludeUgoira,
    );
    await userSetting.prefs.setInt(
      _kAuthorOrganizerPickModeKey,
      _pickMode.index,
    );
    await userSetting.prefs.setInt(_kAuthorOrganizerPickCountKey, _pickCount);
    await userSetting.prefs.setInt(_kAuthorOrganizerWidthOpKey, _widthOp.index);
    if (_widthValue != null && _widthValue! > 0) {
      await userSetting.prefs.setInt(
        _kAuthorOrganizerWidthValueKey,
        _widthValue!,
      );
    } else {
      await userSetting.prefs.remove(_kAuthorOrganizerWidthValueKey);
    }
    await userSetting.prefs.setInt(
      _kAuthorOrganizerHeightOpKey,
      _heightOp.index,
    );
    if (_heightValue != null && _heightValue! > 0) {
      await userSetting.prefs.setInt(
        _kAuthorOrganizerHeightValueKey,
        _heightValue!,
      );
    } else {
      await userSetting.prefs.remove(_kAuthorOrganizerHeightValueKey);
    }
    await userSetting.prefs.setInt(
      _kAuthorOrganizerSortTypeKey,
      _sortType.index,
    );
    await userSetting.prefs.setInt(
      _kAuthorOrganizerSortOrderKey,
      _sortOrder.index,
    );
    await userSetting.prefs.setInt(
      _kAuthorOrganizerGroupTypeKey,
      _groupType.index,
    );
  }

  /// 核心加载与刷新流程：
  /// 1. [forceReload] 为 true 时，从数据库重新查询作者全部插画及图片记录。
  /// 2. 分片批量查询图片记录（每批最多50个illustId）。
  /// 3. [refilter] 为 true 时，执行可扩展筛选条件链并解析本地路径。
  /// 4. 在内存中执行排序与分组逻辑，实现快速响应。
  ///
  /// [forceReload] 是否强制从数据库重新读取原始插画和图片数据。
  /// [refilter] 是否重新执行过滤逻辑和路径解析。
  Future<void> _loadData({
    bool forceReload = false,
    bool refilter = true,
  }) async {
    if (forceReload) {
      setState(() {
        _loading = true;
        _error = null;
        _selectedItemIds.clear();
        _itemMap.clear();
      });
    }

    try {
      // 1. 加载原始数据
      if (forceReload || _rawIllusts == null || _rawImagesByIllustId == null) {
        List<DownloadedIllust> illusts;
        Map<int, List<DownloadedImage>> imagesByIllustId;

        if (_illustIdFilter != null && _illustIdFilter! > 0) {
          // 性能优化：当指定插画 ID 时，直接精确查询单作品数据，无需扫表加载作者全量作品
          final illust = await downloadStore.getDownloadedIllust(
            _illustIdFilter!,
          );
          if (illust != null) {
            illusts = [illust];
            final images = await downloadStore.dbProvider.getImagesByIllustId(
              _illustIdFilter!,
            );
            imagesByIllustId = {illust.illustId: images};
          } else {
            illusts = [];
            imagesByIllustId = {};
          }
        } else {
          // 全量扫表路径
          illusts = await downloadStore.getDownloadedByUser(
            widget.author.userId,
            limit: null,
            offset: 0,
            orderBy: '${DownloadedIllustColumns.downloadTime} DESC',
          );

          final illustIds = illusts.map((e) => e.illustId).toList();
          imagesByIllustId = await _loadImagesByIllustIdsBatched(illustIds);
        }

        _rawIllusts = illusts;
        _rawImagesByIllustId = imagesByIllustId;
      }

      // 2. 过滤与解析路径
      if (refilter) {
        final context = AuthorImageFilterContext(
          author: widget.author,
          illusts: _rawIllusts!,
          imagesByIllustId: _rawImagesByIllustId!,
        );
        final filterEngine = _buildFilterEngine();
        final candidates = await filterEngine.run(context);

        final resolved = await Future.wait(
          candidates.map(_resolveDisplayItemFromCandidate),
        );
        _allFilteredItems =
            resolved.whereType<_AuthorImageDisplayItem>().toList();

        // 维护 ID 到 Item 的映射
        _itemMap.clear();
        for (final item in _allFilteredItems) {
          _itemMap[item.id] = item;
        }
      }

      // 3. 排序
      final sortedItems = List<_AuthorImageDisplayItem>.from(_allFilteredItems);
      sortedItems.sort(_compareBySortOption);

      // 4. 分组
      final grouped = _groupItems(sortedItems);

      if (!mounted) return;
      setState(() {
        _items = sortedItems;
        _groupedItems = grouped;
        _syncGroupKeys(grouped);
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

  /// 根据菜单状态组装筛选条件，便于后续继续扩展。
  AuthorImageFilterEngine _buildFilterEngine() {
    final conditions = <AuthorImageFilterCondition>[];
    if (_excludeUgoira) {
      conditions.add(const ExcludeUgoiraCondition());
    }
    // 先做“前/后N张”截取，再做 webp 过滤。
    // 这样可以保证 N 的计算包含 webp，随后再排除 webp。
    if (_pickMode == _PerIllustPickMode.last) {
      conditions.add(LastNPerIllustCondition(n: _pickCount));
    } else if (_pickMode == _PerIllustPickMode.first) {
      conditions.add(FirstNPerIllustCondition(n: _pickCount));
    }
    // _pickMode == _PerIllustPickMode.all 时不添加数量限制条件。
    if (_excludeWebp) {
      conditions.add(const NonWebpCondition());
    }
    conditions.add(
      ResolutionCondition(
        widthOp: _widthOp,
        widthValue: _widthValue,
        heightOp: _heightOp,
        heightValue: _heightValue,
      ),
    );
    if (_illustIdFilter != null && _illustIdFilter! > 0) {
      conditions.add(IllustIdCondition(illustId: _illustIdFilter));
    }
    return AuthorImageFilterEngine(conditions: conditions);
  }

  int _compareBySortOption(
    _AuthorImageDisplayItem a,
    _AuthorImageDisplayItem b,
  ) {
    final asc = _sortOrder == _SortOrder.asc;
    final sortBy = switch (_sortType) {
      _SortType.idAndPart => _compareFallback(a, b, asc: asc),
      _SortType.downloadTime =>
        asc
            ? a.illust.downloadTime.compareTo(b.illust.downloadTime)
            : b.illust.downloadTime.compareTo(a.illust.downloadTime),
      _SortType.fileSize =>
        asc
            ? a.fileSize.compareTo(b.fileSize)
            : b.fileSize.compareTo(a.fileSize),
      _SortType.width => _compareResolutionValue(
        a.resolutionWidth,
        b.resolutionWidth,
        asc: asc,
      ),
      _SortType.height => _compareResolutionValue(
        a.resolutionHeight,
        b.resolutionHeight,
        asc: asc,
      ),
      _SortType.area => _compareResolutionValue(
        a.resolutionArea,
        b.resolutionArea,
        asc: asc,
      ),
    };
    if (sortBy != 0) return sortBy;
    if (_sortType == _SortType.idAndPart) return 0;
    return _compareFallback(a, b, asc: true);
  }

  int _compareResolutionValue(int? a, int? b, {required bool asc}) {
    final aKnown = a != null && a > 0;
    final bKnown = b != null && b > 0;
    if (!aKnown && !bKnown) return 0;
    if (!aKnown) return 1;
    if (!bKnown) return -1;
    final cmp = a.compareTo(b);
    return asc ? cmp : -cmp;
  }

  int _compareFallback(
    _AuthorImageDisplayItem a,
    _AuthorImageDisplayItem b, {
    bool asc = true,
  }) {
    final i = a.illust.illustId.compareTo(b.illust.illustId);
    if (i != 0) return asc ? i : -i;
    final p = a.image.part.compareTo(b.image.part);
    return asc ? p : -p;
  }

  /// 将筛选后的候选项解析为可展示项（补齐本地文件路径）。
  Future<_AuthorImageDisplayItem?> _resolveDisplayItemFromCandidate(
    AuthorImageCandidate candidate,
  ) async {
    final path = await downloadStore.getLocalImagePathFromImage(
      candidate.image,
      relativePath: candidate.illust.relativePath,
      isUgoira: candidate.illust.isUgoira,
      update: false,
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

  void _toggleGroupSelection(_GroupedItems group) {
    setState(() {
      final allSelected = group.items.every(
        (item) => _selectedItemIds.contains(item.id),
      );
      if (allSelected) {
        for (final item in group.items) {
          _selectedItemIds.remove(item.id);
        }
      } else {
        for (final item in group.items) {
          _selectedItemIds.add(item.id);
        }
      }
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

  /// 打开本地大图预览页。
  Future<void> _openLocalImageViewer(_AuthorImageDisplayItem item) async {
    await LocalImageViewerPage.open(
      context,
      imagePath: item.path,
      title: '${item.illust.illustId} · ${item.illust.title}',
      subtitle: '${item.resolutionText} · ${item.partText}',
      heroTag: _heroTagForItem(item),
    );
  }

  String _heroTagForItem(_AuthorImageDisplayItem item) {
    return 'author_image_local_${item.id}_${item.path}';
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

  /// 弹出更新插画信息对话框 (针对当前作者)
  void _showUpdateIllustInfoDialog() {
    UpdateIllustInfoDialog.show(
      context,
      illusts: _buildUniqueIllustList(),
      userId: widget.author.userId,
    ).then((result) {
      if (result == true) {
        _loadData(forceReload: true);
      }
    });
  }

  /// 处理筛选菜单动作，并按需重新加载数据。
  Future<void> _onFilterMenuSelected(String value) async {
    var shouldReload = false;
    switch (value) {
      case 'toggle_webp':
        setState(() => _excludeWebp = !_excludeWebp);
        shouldReload = true;
        break;
      case 'toggle_ugoira':
        setState(() => _excludeUgoira = !_excludeUgoira);
        shouldReload = true;
        break;
      case 'mode_last':
        setState(() => _pickMode = _PerIllustPickMode.last);
        shouldReload = true;
        break;
      case 'mode_first':
        setState(() => _pickMode = _PerIllustPickMode.first);
        shouldReload = true;
        break;
      case 'mode_all':
        setState(() => _pickMode = _PerIllustPickMode.all);
        shouldReload = true;
        break;
      case 'set_count':
        final count = await _showPickCountDialog();
        if (count != null && count != _pickCount) {
          setState(() => _pickCount = count);
          shouldReload = true;
        }
        break;
      case 'set_resolution_filter':
        final result = await _showResolutionFilterDialog();
        if (result != null) {
          setState(() {
            _widthOp = result.widthOp;
            _widthValue = result.widthValue;
            _heightOp = result.heightOp;
            _heightValue = result.heightValue;
          });
          shouldReload = true;
        }
        break;
      case 'clear_resolution_filter':
        setState(() {
          _widthOp = ResolutionFilterOp.none;
          _widthValue = null;
          _heightOp = ResolutionFilterOp.none;
          _heightValue = null;
        });
        shouldReload = true;
        break;
    }
    if (shouldReload) {
      await _persistFilterPrefs();
      _loadData(refilter: true);
    }
  }

  Future<void> _onSortTypeChanged(_SortType? value) async {
    if (value == null || value == _sortType) return;
    setState(() => _sortType = value);
    await _persistFilterPrefs();
    _loadData(refilter: false);
  }

  Future<void> _onSortOrderChanged(_SortOrder? value) async {
    if (value == null || value == _sortOrder) return;
    setState(() => _sortOrder = value);
    await _persistFilterPrefs();
    _loadData(refilter: false);
  }

  Future<void> _onGroupTypeChanged(_GroupType? value) async {
    if (value == null || value == _groupType) return;
    setState(() => _groupType = value);
    await _persistFilterPrefs();
    _loadData(refilter: false);
  }

  /// 设置“每个作品取几张”。
  Future<int?> _showPickCountDialog() async {
    var tempCount = _pickCount;
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
    var tempWidthOp = _widthOp;
    var tempWidthValue = _widthValue;
    var tempHeightOp = _heightOp;
    var tempHeightValue = _heightValue;
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

  String _sortTypeLabel(_SortType type) {
    return switch (type) {
      _SortType.idAndPart => '默认排序',
      _SortType.downloadTime => '下载时间',
      _SortType.fileSize => '文件大小',
      _SortType.width => '分辨率(宽)',
      _SortType.height => '分辨率(高)',
      _SortType.area => '分辨率(面积)',
    };
  }

  String _groupTypeLabel(_GroupType type) {
    return switch (type) {
      _GroupType.none => '不分组',
      _GroupType.date => '按日期',
      _GroupType.illust => '按作品',
      _GroupType.type => '按类型',
      _GroupType.resolution => '按分辨率',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isMultiSelectMode
              ? '${widget.author.userName} · 已选 ${_selectedItemIds.length}'
              : _illustIdFilter != null
              ? '${widget.author.userName} · 作品 $_illustIdFilter'
              : '${widget.author.userName} 图片整理',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: PopupMenuButton<_GroupType>(
              initialValue: _groupType,
              tooltip: '分组方式',
              position: PopupMenuPosition.under,
              onSelected: _loading ? null : _onGroupTypeChanged,
              itemBuilder:
                  (context) =>
                      _GroupType.values
                          .map(
                            (type) => PopupMenuItem<_GroupType>(
                              value: type,
                              child: Text(_groupTypeLabel(type)),
                            ),
                          )
                          .toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.layers_outlined, size: 20),
                    const SizedBox(width: 4),
                    Text(_groupTypeLabel(_groupType)),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: PopupMenuButton<_SortType>(
              initialValue: _sortType,
              tooltip: '排序方式',
              position: PopupMenuPosition.under,
              onSelected: _loading ? null : _onSortTypeChanged,
              itemBuilder:
                  (context) =>
                      _SortType.values
                          .map(
                            (type) => PopupMenuItem<_SortType>(
                              value: type,
                              child: Text(_sortTypeLabel(type)),
                            ),
                          )
                          .toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_sortTypeLabel(_sortType)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _sortOrder == _SortOrder.asc
                  ? Icons
                      .arrow_upward // 升序图标
                  : Icons.arrow_downward, // 降序图标
            ),
            tooltip: _sortOrder == _SortOrder.asc ? '正序' : '倒序',
            onPressed:
                _loading
                    ? null
                    : () {
                      _onSortOrderChanged(
                        _sortOrder == _SortOrder.asc
                            ? _SortOrder.desc
                            : _SortOrder.asc,
                      );
                    },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: '筛选条件',
            position: PopupMenuPosition.under,
            onSelected: (value) {
              _onFilterMenuSelected(value);
            },
            itemBuilder: (context) {
              return [
                CheckedPopupMenuItem(
                  value: 'toggle_webp',
                  checked: _excludeWebp,
                  child: const Text('排除 WebP'),
                ),
                CheckedPopupMenuItem(
                  value: 'toggle_ugoira',
                  checked: _excludeUgoira,
                  child: const Text('排除动图'),
                ),
                const PopupMenuDivider(),
                CheckedPopupMenuItem(
                  value: 'mode_last',
                  checked: _pickMode == _PerIllustPickMode.last,
                  child: const Text('最后几张'),
                ),
                CheckedPopupMenuItem(
                  value: 'mode_first',
                  checked: _pickMode == _PerIllustPickMode.first,
                  child: const Text('最前几张'),
                ),
                CheckedPopupMenuItem(
                  value: 'mode_all',
                  checked: _pickMode == _PerIllustPickMode.all,
                  child: const Text('所有'),
                ),
                PopupMenuItem(
                  value: 'set_count',
                  child: Text('每作品数量: $_pickCount'),
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
            tooltip: '扫描并更新作者作品信息',
            onPressed: _loading ? null : _showUpdateIllustInfoDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '列表刷新',
            onPressed: _loading ? null : () => _loadData(forceReload: true),
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
          if (_illustIdFilter != null && !_isMultiSelectMode)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              tooltip: '清除作品 ID 过滤',
              onPressed: () {
                setState(() {
                  _illustIdFilter = null;
                });
                _loadData(forceReload: true);
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
            child: SliverViewObserver(
              controller: _sliverObserverController,
              onObserveViewport: _onObserveViewport,
              sliverContexts:
                  () =>
                      _groupedItems
                          .map(
                            (group) =>
                                _groupObserveKeys[group.id]?.currentContext,
                          )
                          .whereType<BuildContext>()
                          .toList(),
              child: CustomScrollView(
                controller: _scrollController,
                slivers:
                    _groupedItems.asMap().entries.map((entry) {
                      final index = entry.key;
                      final group = entry.value;
                      return SliverMainAxisGroup(
                        key: _groupObserveKeys[group.id],
                        slivers: [
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _StickyHeaderDelegate(
                              child: _buildGroupHeader(group, index),
                              minHeight: 40,
                              maxHeight: 40,
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.all(8),
                            sliver: SliverGrid(
                              key: _groupGridKeys[group.id],
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 210,
                                    childAspectRatio: 0.73,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final item = group.items[index];
                                final selected = _selectedItemIds.contains(
                                  item.id,
                                );
                                return _buildDraggableCard(item, selected);
                              }, childCount: group.items.length),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupNavigator() {
    if (_groupedItems.isEmpty) {
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
        scrollDirection: Axis.horizontal,
        itemCount: _groupedItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final group = _groupedItems[index];
          return ChoiceChip(
            label: Text(group.title),
            selected: _currentGroupId == group.id,
            onSelected: (_) => _scrollToGroup(group),
          );
        },
      ),
    );
  }

  void _syncGroupKeys(List<_GroupedItems> groups) {
    final ids = groups.map((e) => e.id).toSet();
    _groupHeaderKeys.removeWhere((id, _) => !ids.contains(id));
    _groupObserveKeys.removeWhere((id, _) => !ids.contains(id));
    _groupGridKeys.removeWhere((id, _) => !ids.contains(id));
    for (final group in groups) {
      _groupHeaderKeys.putIfAbsent(group.id, () => GlobalKey());
      _groupObserveKeys.putIfAbsent(group.id, () => GlobalKey());
      _groupGridKeys.putIfAbsent(group.id, () => GlobalKey());
    }
    if (_currentGroupId == null || !ids.contains(_currentGroupId)) {
      _currentGroupId = groups.isNotEmpty ? groups.first.id : null;
    }
  }

  Future<void> _scrollToGroup(_GroupedItems group) async {
    setState(() {
      _currentGroupId = group.id;
    });

    final targetGridContext = _groupGridKeys[group.id]?.currentContext;
    if (targetGridContext != null) {
      try {
        await _sliverObserverController.animateTo(
          index: 0,
          sliverContext: targetGridContext,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          alignment: 0,
        );
        return;
      } catch (_) {}
    }

    final targetHeaderContext = _groupHeaderKeys[group.id]?.currentContext;
    if (targetHeaderContext != null) {
      await Scrollable.ensureVisible(
        targetHeaderContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
        alignment: 0,
      );
    }
  }

  void _onObserveViewport(SliverViewportObserveModel result) {
    if (_groupedItems.isEmpty) return;
    final firstContext = result.firstChild.sliverContext;
    String? visibleGroupId;
    for (final group in _groupedItems) {
      final ctx = _groupObserveKeys[group.id]?.currentContext;
      if (identical(ctx, firstContext)) {
        visibleGroupId = group.id;
        break;
      }
    }
    if (visibleGroupId == null || visibleGroupId == _currentGroupId) return;
    if (!mounted) return;
    setState(() {
      _currentGroupId = visibleGroupId;
    });
  }

  Widget _buildGroupHeader(_GroupedItems group, int index) {
    final allSelected = group.items.every(
      (item) => _selectedItemIds.contains(item.id),
    );
    final anySelected = group.items.any(
      (item) => _selectedItemIds.contains(item.id),
    );

    return Container(
      key: _groupHeaderKeys[group.id],
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
          if (_isMultiSelectMode)
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
              onPressed: () => _toggleGroupSelection(group),
              tooltip: allSelected ? '全组取消选中' : '全组选中',
            ),
        ],
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
            _openLocalImageViewer(item);
          }
        },
        onLongPress: () {
          // 长按进入选择模式，并选中当前卡片。
          if (!_isMultiSelectMode) {
            setState(() {
              _isMultiSelectMode = true;
              _selectedItemIds.add(item.id);
            });
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
                      Hero(
                        tag: _heroTagForItem(item),
                        child: PixivImage(
                          Uri.file(item.path).toString(),
                          fit: BoxFit.cover,
                          memCacheWidth: 250,
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
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _openIllustDetail(item),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_isMultiSelectMode)
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: Material(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openLocalImageViewer(item),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.zoom_in,
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
                          right: 38,
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

  List<_GroupedItems> _groupItems(List<_AuthorImageDisplayItem> items) {
    if (_groupType == _GroupType.none) {
      return [
        _GroupedItems(
          title: '所有图片 (${items.length})',
          items: items,
          type: _GroupType.none,
          id: 'none',
        ),
      ];
    }

    final groups = <String, List<_AuthorImageDisplayItem>>{};
    final groupTitles = <String, String>{};
    final groupOrder = <String>[];

    for (final item in items) {
      String groupId;
      String groupTitle;

      switch (_groupType) {
        case _GroupType.illust:
          groupId = 'illust_${item.illust.illustId}';
          groupTitle = '${item.illust.illustId} · ${item.illust.title}';
          break;
        case _GroupType.date:
          final date = DateTime.fromMillisecondsSinceEpoch(
            item.illust.downloadTime,
          );
          groupId = 'date_${date.year}_${date.month}_${date.day}';
          groupTitle =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          break;
        case _GroupType.type:
          groupId = 'type_${item.imageType}';
          groupTitle = item.imageType.toUpperCase();
          break;
        case _GroupType.resolution:
          groupId = 'res_${item.resolutionText}';
          groupTitle = item.resolutionText;
          break;
        case _GroupType.none:
          groupId = 'none';
          groupTitle = '所有图片';
          break;
      }

      if (!groups.containsKey(groupId)) {
        groups[groupId] = [];
        groupTitles[groupId] = groupTitle;
        groupOrder.add(groupId);
      }
      groups[groupId]!.add(item);
    }

    return groupOrder.map((id) {
      return _GroupedItems(
        title: '${groupTitles[id]} (${groups[id]!.length})',
        items: groups[id]!,
        type: _groupType,
        id: id,
      );
    }).toList();
  }
}

class _GroupedItems {
  final String title;
  final List<_AuthorImageDisplayItem> items;
  final _GroupType type;
  final String id;

  const _GroupedItems({
    required this.title,
    required this.items,
    required this.type,
    required this.id,
  });
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

  int? get resolutionWidth {
    final w = image.width;
    if (w == null || w <= 0) return null;
    return w;
  }

  int? get resolutionHeight {
    final h = image.height;
    if (h == null || h <= 0) return null;
    return h;
  }

  int? get resolutionArea {
    final w = resolutionWidth;
    final h = resolutionHeight;
    if (w == null || h == null) return null;
    return w * h;
  }

  /// 文件名（包含后缀）。
  String get fileNameWithExt => image.getFullFileName();

  /// 图片类型（png/webp/jpg...）。
  String get imageType {
    final ext = image.extension.trim().toLowerCase();
    if (ext.isEmpty) return 'unknown';
    return ext.startsWith('.') ? ext.substring(1) : ext;
  }

  String get partText => 'P${image.part}';

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
