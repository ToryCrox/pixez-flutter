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
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/picture_list_page.dart';
import 'package:pixez/utils/file_utils.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

enum _PerIllustPickMode { last, first }

enum _AuthorOrganizerSortOption {
  downloadTimeAsc,
  downloadTimeDesc,
  fileSizeAsc,
  fileSizeDesc,
  resolutionWidthAsc,
  resolutionWidthDesc,
  resolutionHeightAsc,
  resolutionHeightDesc,
  resolutionAreaAsc,
  resolutionAreaDesc,
}

// 筛选项持久化 key（仅在当前页面使用，不放入 UserSetting）。
const String _kAuthorOrganizerExcludeWebpKey = 'author_organizer_exclude_webp';
const String _kAuthorOrganizerExcludeUgoiraKey =
    'author_organizer_exclude_ugoira';
const String _kAuthorOrganizerPickModeKey = 'author_organizer_pick_mode';
const String _kAuthorOrganizerPickCountKey = 'author_organizer_pick_count';
const String _kAuthorOrganizerSortOptionKey = 'author_organizer_sort_option';
const String _kAuthorOrganizerWidthOpKey = 'author_organizer_width_op';
const String _kAuthorOrganizerWidthValueKey = 'author_organizer_width_value';
const String _kAuthorOrganizerHeightOpKey = 'author_organizer_height_op';
const String _kAuthorOrganizerHeightValueKey = 'author_organizer_height_value';

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
  bool _excludeWebp = true;
  bool _excludeUgoira = true;
  _PerIllustPickMode _pickMode = _PerIllustPickMode.last;
  int _pickCount = 4;
  ResolutionFilterOp _widthOp = ResolutionFilterOp.none;
  int? _widthValue;
  ResolutionFilterOp _heightOp = ResolutionFilterOp.none;
  int? _heightValue;
  _AuthorOrganizerSortOption _sortOption =
      _AuthorOrganizerSortOption.downloadTimeDesc;

  @override
  void initState() {
    super.initState();
    _loadFilterPrefs();
    _loadItems();
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

    final heightOpIndex =
        userSetting.prefs.getInt(_kAuthorOrganizerHeightOpKey);
    if (heightOpIndex != null &&
        heightOpIndex >= 0 &&
        heightOpIndex < ResolutionFilterOp.values.length) {
      _heightOp = ResolutionFilterOp.values[heightOpIndex];
    }
    final heightValue =
        userSetting.prefs.getInt(_kAuthorOrganizerHeightValueKey);
    if (heightValue != null && heightValue > 0) {
      _heightValue = heightValue;
    }

    final sortOptionIndex =
        userSetting.prefs.getInt(_kAuthorOrganizerSortOptionKey);
    if (sortOptionIndex != null &&
        sortOptionIndex >= 0 &&
        sortOptionIndex < _AuthorOrganizerSortOption.values.length) {
      _sortOption = _AuthorOrganizerSortOption.values[sortOptionIndex];
    }
  }

  /// 将筛选配置写入 UserSetting.prefs。
  Future<void> _persistFilterPrefs() async {
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
    await userSetting.prefs.setInt(_kAuthorOrganizerHeightOpKey, _heightOp.index);
    if (_heightValue != null && _heightValue! > 0) {
      await userSetting.prefs.setInt(
        _kAuthorOrganizerHeightValueKey,
        _heightValue!,
      );
    } else {
      await userSetting.prefs.remove(_kAuthorOrganizerHeightValueKey);
    }
    await userSetting.prefs.setInt(
      _kAuthorOrganizerSortOptionKey,
      _sortOption.index,
    );
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
      final filterEngine = _buildFilterEngine();
      final candidates = await filterEngine.run(context);

      final resolved = await Future.wait(
        candidates.map(_resolveDisplayItemFromCandidate),
      );
      var displayItems = resolved.whereType<_AuthorImageDisplayItem>().toList();

      displayItems.sort(_compareBySortOption);

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
    } else {
      conditions.add(FirstNPerIllustCondition(n: _pickCount));
    }
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
    return AuthorImageFilterEngine(conditions: conditions);
  }

  int _compareBySortOption(
    _AuthorImageDisplayItem a,
    _AuthorImageDisplayItem b,
  ) {
    final sortBy = switch (_sortOption) {
      _AuthorOrganizerSortOption.downloadTimeAsc =>
        a.illust.downloadTime.compareTo(b.illust.downloadTime),
      _AuthorOrganizerSortOption.downloadTimeDesc =>
        b.illust.downloadTime.compareTo(a.illust.downloadTime),
      _AuthorOrganizerSortOption.fileSizeAsc => a.fileSize.compareTo(b.fileSize),
      _AuthorOrganizerSortOption.fileSizeDesc =>
        b.fileSize.compareTo(a.fileSize),
      _AuthorOrganizerSortOption.resolutionWidthAsc =>
        _compareResolutionValue(a.resolutionWidth, b.resolutionWidth, asc: true),
      _AuthorOrganizerSortOption.resolutionWidthDesc =>
        _compareResolutionValue(a.resolutionWidth, b.resolutionWidth, asc: false),
      _AuthorOrganizerSortOption.resolutionHeightAsc =>
        _compareResolutionValue(a.resolutionHeight, b.resolutionHeight, asc: true),
      _AuthorOrganizerSortOption.resolutionHeightDesc =>
        _compareResolutionValue(
          a.resolutionHeight,
          b.resolutionHeight,
          asc: false,
        ),
      _AuthorOrganizerSortOption.resolutionAreaAsc =>
        _compareResolutionValue(a.resolutionArea, b.resolutionArea, asc: true),
      _AuthorOrganizerSortOption.resolutionAreaDesc =>
        _compareResolutionValue(a.resolutionArea, b.resolutionArea, asc: false),
    };
    if (sortBy != 0) return sortBy;
    return _compareFallback(a, b);
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

  int _compareFallback(_AuthorImageDisplayItem a, _AuthorImageDisplayItem b) {
    final i = a.illust.illustId.compareTo(b.illust.illustId);
    if (i != 0) return i;
    return a.image.part.compareTo(b.image.part);
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
    }
    if (shouldReload) {
      _loadItems();
    }
  }

  Future<void> _onSortOptionChanged(_AuthorOrganizerSortOption? value) async {
    if (value == null || value == _sortOption) return;
    setState(() => _sortOption = value);
    await _persistFilterPrefs();
    _loadItems();
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
            decoration: const InputDecoration(
              hintText: '像素值',
              isDense: true,
            ),
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

  String _sortOptionLabel(_AuthorOrganizerSortOption option) {
    return switch (option) {
      _AuthorOrganizerSortOption.downloadTimeAsc => '下载时间-顺序',
      _AuthorOrganizerSortOption.downloadTimeDesc => '下载时间-倒序',
      _AuthorOrganizerSortOption.fileSizeAsc => '文件大小-顺序',
      _AuthorOrganizerSortOption.fileSizeDesc => '文件大小-倒序',
      _AuthorOrganizerSortOption.resolutionWidthAsc => '分辨率(宽)-顺序',
      _AuthorOrganizerSortOption.resolutionWidthDesc => '分辨率(宽)-倒序',
      _AuthorOrganizerSortOption.resolutionHeightAsc => '分辨率(高)-顺序',
      _AuthorOrganizerSortOption.resolutionHeightDesc => '分辨率(高)-倒序',
      _AuthorOrganizerSortOption.resolutionAreaAsc => '分辨率(宽x高)-顺序',
      _AuthorOrganizerSortOption.resolutionAreaDesc => '分辨率(宽x高)-倒序',
    };
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_AuthorOrganizerSortOption>(
                  value: _sortOption,
                  icon: const Icon(Icons.sort),
                  onChanged: _loading ? null : _onSortOptionChanged,
                  items:
                      _AuthorOrganizerSortOption.values
                          .map(
                            (option) =>
                                DropdownMenuItem<_AuthorOrganizerSortOption>(
                                  value: option,
                                  child: Text(_sortOptionLabel(option)),
                                ),
                          )
                          .toList(),
                ),
              ),
            ),
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
                      PixivImage(
                        Uri.file(item.path).toString(),
                        fit: BoxFit.cover,
                        memCacheWidth: 250,
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
