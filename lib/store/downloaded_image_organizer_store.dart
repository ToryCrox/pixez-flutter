import 'package:mobx/mobx.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/downloaded_image_filter_conditions.dart';

part 'downloaded_image_organizer_store.g.dart';

enum PerIllustPickMode { last, first, all }

enum SortType { idAndPart, downloadTime, fileSize, width, height, area }

enum SortOrder { asc, desc }

enum GroupType { none, date, illust, type, resolution }

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

class DownloadedImageDisplayItem {
  final DownloadedIllust illust;
  final DownloadedImage image;
  final String path;

  const DownloadedImageDisplayItem({
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

  String get fileNameWithExt => image.getFullFileName();

  String get imageType {
    final ext = image.extension.trim().toLowerCase();
    if (ext.isEmpty) return 'unknown';
    return ext.startsWith('.') ? ext.substring(1) : ext;
  }

  String get partText => 'P${image.part}';

  String get resolutionText {
    final w = image.width;
    final h = image.height;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return '未知分辨率';
    }
    return '${w}x$h';
  }
}

class GroupedItems {
  final String title;
  final List<DownloadedImageDisplayItem> items;
  final GroupType type;
  final String id;

  const GroupedItems({
    required this.title,
    required this.items,
    required this.type,
    required this.id,
  });
}

class DownloadedImageOrganizerStore = _DownloadedImageOrganizerStore
    with _$DownloadedImageOrganizerStore;

abstract class _DownloadedImageOrganizerStore with Store {
  final DownloadedAuthor? author;
  final int? initialIllustId;
  final List<int>? illustIds;
  final String? title;

  _DownloadedImageOrganizerStore({
    this.author,
    this.initialIllustId,
    this.illustIds,
    this.title,
  }) : assert(
         author != null || (illustIds != null && illustIds.isNotEmpty),
         'author 或 illustIds 至少需要提供一个',
       ) {
    _illustIdFilter = initialIllustId;
    if (isTempFilter) {
      _excludeWebp = false;
      _excludeUgoira = false;
      _pickMode = PerIllustPickMode.all;
      _widthOp = ResolutionFilterOp.none;
      _heightOp = ResolutionFilterOp.none;
    }
  }

  // ============ Observables ============

  @observable
  bool loading = true;

  @observable
  String? error;

  @observable
  ObservableList<DownloadedImageDisplayItem> items = ObservableList.of([]);

  @observable
  ObservableList<GroupedItems> groupedItems = ObservableList.of([]);

  @observable
  List<DownloadedIllust>? rawIllusts;

  @observable
  Map<int, List<DownloadedImage>>? rawImagesByIllustId;

  @observable
  ObservableList<DownloadedImageDisplayItem> allFilteredItems =
      ObservableList.of([]);

  @observable
  bool isMultiSelectMode = false;

  @observable
  ObservableSet<String> selectedItemIds = ObservableSet.of({});

  @observable
  bool _excludeWebp = true;

  @observable
  bool _excludeUgoira = true;

  @observable
  PerIllustPickMode _pickMode = PerIllustPickMode.all;

  @observable
  int _pickCount = 4;

  @observable
  ResolutionFilterOp _widthOp = ResolutionFilterOp.none;

  @observable
  int? _widthValue;

  @observable
  ResolutionFilterOp _heightOp = ResolutionFilterOp.none;

  @observable
  int? _heightValue;

  @observable
  SortType sortType = SortType.idAndPart;

  @observable
  SortOrder sortOrder = SortOrder.asc;

  @observable
  GroupType groupType = GroupType.none;

  @observable
  int? _illustIdFilter;

  // ============ Computed ============

  @computed
  bool get isTempFilter => initialIllustId != null;

  @computed
  bool get hasAuthorContext => author != null;

  @computed
  String get titlePrefix {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    if (hasAuthorContext) return '${author!.userName} 图片整理';
    return '图片整理';
  }

  @computed
  DownloadedAuthor get filterContextAuthor {
    if (author != null) return author!;
    final t = title?.trim();
    return DownloadedAuthor(
      userId: 0,
      userName: t != null && t.isNotEmpty ? t : '图片整理',
      illustCount: rawIllusts?.length ?? 0,
      totalImageCount: 0,
      totalFileSize: 0,
      lastDownloadTime: 0,
      lastUpdateTime: 0,
    );
  }

  @computed
  Map<String, DownloadedImageDisplayItem> get itemMap {
    return {for (final item in allFilteredItems) item.id: item};
  }

  @computed
  bool get excludeWebp => _excludeWebp;

  @computed
  bool get excludeUgoira => _excludeUgoira;

  @computed
  PerIllustPickMode get pickMode => _pickMode;

  @computed
  int get pickCount => _pickCount;

  @computed
  ResolutionFilterOp get widthOp => _widthOp;

  @computed
  int? get widthValue => _widthValue;

  @computed
  ResolutionFilterOp get heightOp => _heightOp;

  @computed
  int? get heightValue => _heightValue;

  @computed
  int? get illustIdFilter => _illustIdFilter;

  // ============ Actions ============

  @action
  Future<void> init() async {
    _loadFilterPrefs();
    await loadData(forceReload: true);
  }

  @action
  Future<void> loadData({
    bool forceReload = false,
    bool refilter = true,
  }) async {
    if (forceReload) {
      loading = true;
      error = null;
      selectedItemIds.clear();
    }

    try {
      if (forceReload || rawIllusts == null || rawImagesByIllustId == null) {
        List<DownloadedIllust> illusts;
        Map<int, List<DownloadedImage>> imagesByIllustId;

        if (_illustIdFilter != null && _illustIdFilter! > 0) {
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
        } else if (illustIds != null && illustIds!.isNotEmpty) {
          final fetchedIllusts = await downloadStore.getDownloadedIllustsByIds(
            illustIds!,
          );
          final illustMap = <int, DownloadedIllust>{
            for (final illust in fetchedIllusts) illust.illustId: illust,
          };
          illusts =
              illustIds!
                  .map((id) => illustMap[id])
                  .whereType<DownloadedIllust>()
                  .toList();
          final ids = illusts.map((e) => e.illustId).toList();
          imagesByIllustId = await _loadImagesByIllustIdsBatched(ids);
        } else {
          illusts = await downloadStore.getDownloadedByUser(
            author!.userId,
            limit: null,
            offset: 0,
            orderBy: '${DownloadedIllustColumns.downloadTime} DESC',
          );
          final ids = illusts.map((e) => e.illustId).toList();
          imagesByIllustId = await _loadImagesByIllustIdsBatched(ids);
        }

        rawIllusts = illusts;
        rawImagesByIllustId = imagesByIllustId;
      }

      if (refilter) {
        final context = DownloadedImageFilterContext(
          author: filterContextAuthor,
          illusts: rawIllusts!,
          imagesByIllustId: rawImagesByIllustId!,
        );
        final filterEngine = _buildFilterEngine();
        final candidates = await filterEngine.run(context);

        final resolved = await Future.wait(
          candidates.map(_resolveDisplayItemFromCandidate),
        );
        allFilteredItems = ObservableList.of(
          resolved.whereType<DownloadedImageDisplayItem>(),
        );
      }

      final sortedItems = List<DownloadedImageDisplayItem>.from(
        allFilteredItems,
      );
      sortedItems.sort(_compareBySortOption);

      final grouped = _groupItems(sortedItems);

      items = ObservableList.of(sortedItems);
      groupedItems = ObservableList.of(grouped);
      loading = false;
    } catch (e) {
      error = e.toString();
      loading = false;
    }
  }

  // ============ Filter actions ============

  @action
  Future<void> toggleExcludeWebp() async {
    _excludeWebp = !_excludeWebp;
    await persistFilterPrefs();
    await loadData(refilter: true);
  }

  @action
  Future<void> toggleExcludeUgoira() async {
    _excludeUgoira = !_excludeUgoira;
    await persistFilterPrefs();
    await loadData(refilter: true);
  }

  @action
  Future<void> setPickMode(PerIllustPickMode mode) async {
    _pickMode = mode;
    await persistFilterPrefs();
    await loadData(refilter: true);
  }

  @action
  Future<void> setPickCount(int count) async {
    _pickCount = count.clamp(1, 20);
    await persistFilterPrefs();
    await loadData(refilter: true);
  }

  @action
  Future<void> setResolutionFilter({
    required ResolutionFilterOp widthOp,
    int? widthValue,
    required ResolutionFilterOp heightOp,
    int? heightValue,
  }) async {
    _widthOp = widthOp;
    _widthValue = widthValue;
    _heightOp = heightOp;
    _heightValue = heightValue;
    await persistFilterPrefs();
    await loadData(refilter: true);
  }

  @action
  Future<void> clearResolutionFilter() async {
    _widthOp = ResolutionFilterOp.none;
    _widthValue = null;
    _heightOp = ResolutionFilterOp.none;
    _heightValue = null;
    await persistFilterPrefs();
    await loadData(refilter: true);
  }

  @action
  Future<void> setSortType(SortType value) async {
    sortType = value;
    await persistFilterPrefs();
    await loadData(refilter: false);
  }

  @action
  Future<void> toggleSortOrder() async {
    sortOrder = sortOrder == SortOrder.asc ? SortOrder.desc : SortOrder.asc;
    await persistFilterPrefs();
    await loadData(refilter: false);
  }

  @action
  Future<void> setGroupType(GroupType value) async {
    groupType = value;
    await persistFilterPrefs();
    await loadData(refilter: false);
  }

  @action
  Future<void> clearIllustIdFilter() async {
    _illustIdFilter = null;
    await loadData(forceReload: true);
  }

  // ============ Selection actions ============

  @action
  void toggleMultiSelectMode() {
    if (isMultiSelectMode) {
      exitMultiSelectMode();
    } else {
      isMultiSelectMode = true;
    }
  }

  @action
  void exitMultiSelectMode() {
    isMultiSelectMode = false;
    selectedItemIds.clear();
  }

  @action
  void setSelected(String id, bool selected) {
    if (selected) {
      selectedItemIds.add(id);
    } else {
      selectedItemIds.remove(id);
    }
  }

  @action
  void toggleSelectAllOrClear() {
    if (items.isEmpty) return;
    if (selectedItemIds.length == items.length) {
      selectedItemIds.clear();
    } else {
      selectedItemIds
        ..clear()
        ..addAll(items.map((e) => e.id));
    }
  }

  @action
  void selectAllAndEnterMultiMode() {
    isMultiSelectMode = true;
    selectedItemIds
      ..clear()
      ..addAll(items.map((e) => e.id));
  }

  @action
  void selectItemAndEnterMultiMode(String id) {
    isMultiSelectMode = true;
    selectedItemIds.add(id);
  }

  @action
  void toggleGroupSelection(GroupedItems group) {
    final allSelected = group.items.every(
      (item) => selectedItemIds.contains(item.id),
    );
    if (allSelected) {
      for (final item in group.items) {
        selectedItemIds.remove(item.id);
      }
    } else {
      for (final item in group.items) {
        selectedItemIds.add(item.id);
      }
    }
  }

  // ============ Helpers ============

  List<DownloadedIllust> buildUniqueIllustList() {
    final result = <DownloadedIllust>[];
    final seen = <int>{};
    for (final item in items) {
      if (seen.add(item.illust.illustId)) {
        result.add(item.illust);
      }
    }
    return result;
  }

  // ============ Persistence ============

  void _loadFilterPrefs() {
    if (isTempFilter) return;
    _excludeWebp =
        userSetting.prefs.getBool(_kAuthorOrganizerExcludeWebpKey) ?? true;
    _excludeUgoira =
        userSetting.prefs.getBool(_kAuthorOrganizerExcludeUgoiraKey) ?? true;

    final modeIndex = userSetting.prefs.getInt(_kAuthorOrganizerPickModeKey);
    if (modeIndex != null &&
        modeIndex >= 0 &&
        modeIndex < PerIllustPickMode.values.length) {
      _pickMode = PerIllustPickMode.values[modeIndex];
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
        sortTypeIndex < SortType.values.length) {
      sortType = SortType.values[sortTypeIndex];
    }
    final sortOrderIndex = userSetting.prefs.getInt(
      _kAuthorOrganizerSortOrderKey,
    );
    if (sortOrderIndex != null &&
        sortOrderIndex >= 0 &&
        sortOrderIndex < SortOrder.values.length) {
      sortOrder = SortOrder.values[sortOrderIndex];
    }

    final groupTypeIndex = userSetting.prefs.getInt(
      _kAuthorOrganizerGroupTypeKey,
    );
    if (groupTypeIndex != null &&
        groupTypeIndex >= 0 &&
        groupTypeIndex < GroupType.values.length) {
      groupType = GroupType.values[groupTypeIndex];
    }
  }

  Future<void> persistFilterPrefs() async {
    if (isTempFilter) return;
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
      sortType.index,
    );
    await userSetting.prefs.setInt(
      _kAuthorOrganizerSortOrderKey,
      sortOrder.index,
    );
    await userSetting.prefs.setInt(
      _kAuthorOrganizerGroupTypeKey,
      groupType.index,
    );
  }

  // ============ Internal methods ============

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

  DownloadedImageFilterEngine _buildFilterEngine() {
    final conditions = <DownloadedImageFilterCondition>[];
    if (_excludeUgoira) {
      conditions.add(const ExcludeUgoiraCondition());
    }
    if (_pickMode == PerIllustPickMode.last) {
      conditions.add(LastNPerIllustCondition(n: _pickCount));
    } else if (_pickMode == PerIllustPickMode.first) {
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
    if (_illustIdFilter != null && _illustIdFilter! > 0) {
      conditions.add(IllustIdCondition(illustId: _illustIdFilter));
    }
    return DownloadedImageFilterEngine(conditions: conditions);
  }

  Future<DownloadedImageDisplayItem?> _resolveDisplayItemFromCandidate(
    DownloadedImageCandidate candidate,
  ) async {
    final path = await downloadStore.getLocalImagePathFromImage(
      candidate.image,
      relativePath: candidate.illust.relativePath,
      isUgoira: candidate.illust.isUgoira,
      update: false,
    );
    if (path == null) return null;

    return DownloadedImageDisplayItem(
      illust: candidate.illust,
      image: candidate.image,
      path: path,
    );
  }

  int _compareBySortOption(
    DownloadedImageDisplayItem a,
    DownloadedImageDisplayItem b,
  ) {
    final asc = sortOrder == SortOrder.asc;
    final sortBy = switch (sortType) {
      SortType.idAndPart => _compareFallback(a, b, asc: asc),
      SortType.downloadTime =>
        asc
            ? a.illust.downloadTime.compareTo(b.illust.downloadTime)
            : b.illust.downloadTime.compareTo(a.illust.downloadTime),
      SortType.fileSize =>
        asc
            ? a.fileSize.compareTo(b.fileSize)
            : b.fileSize.compareTo(a.fileSize),
      SortType.width => _compareResolutionValue(
        a.resolutionWidth,
        b.resolutionWidth,
        asc: asc,
      ),
      SortType.height => _compareResolutionValue(
        a.resolutionHeight,
        b.resolutionHeight,
        asc: asc,
      ),
      SortType.area => _compareResolutionValue(
        a.resolutionArea,
        b.resolutionArea,
        asc: asc,
      ),
    };
    if (sortBy != 0) return sortBy;
    if (sortType == SortType.idAndPart) return 0;
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
    DownloadedImageDisplayItem a,
    DownloadedImageDisplayItem b, {
    bool asc = true,
  }) {
    final i = a.illust.illustId.compareTo(b.illust.illustId);
    if (i != 0) return asc ? i : -i;
    final p = a.image.part.compareTo(b.image.part);
    return asc ? p : -p;
  }

  List<GroupedItems> _groupItems(List<DownloadedImageDisplayItem> items) {
    if (groupType == GroupType.none) {
      return [
        GroupedItems(
          title: '所有图片 (${items.length})',
          items: items,
          type: GroupType.none,
          id: 'none',
        ),
      ];
    }

    final groups = <String, List<DownloadedImageDisplayItem>>{};
    final groupTitles = <String, String>{};
    final groupOrder = <String>[];

    for (final item in items) {
      String groupId;
      String groupTitle;

      switch (groupType) {
        case GroupType.illust:
          groupId = 'illust_${item.illust.illustId}';
          groupTitle = '${item.illust.illustId} · ${item.illust.title}';
        case GroupType.date:
          final date = DateTime.fromMillisecondsSinceEpoch(
            item.illust.downloadTime,
          );
          groupId = 'date_${date.year}_${date.month}_${date.day}';
          groupTitle =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        case GroupType.type:
          groupId = 'type_${item.imageType}';
          groupTitle = item.imageType.toUpperCase();
        case GroupType.resolution:
          groupId = 'res_${item.resolutionText}';
          groupTitle = item.resolutionText;
        case GroupType.none:
          groupId = 'none';
          groupTitle = '所有图片';
      }

      if (!groups.containsKey(groupId)) {
        groups[groupId] = [];
        groupTitles[groupId] = groupTitle;
        groupOrder.add(groupId);
      }
      groups[groupId]!.add(item);
    }

    return groupOrder.map((id) {
      return GroupedItems(
        title: '${groupTitles[id]} (${groups[id]!.length})',
        items: groups[id]!,
        type: groupType,
        id: id,
      );
    }).toList();
  }

  /// ============ 工具方法 ============
  /// 排序方式标签
  String sortTypeLabel(SortType type) {
    return switch (type) {
      SortType.idAndPart => '默认排序',
      SortType.downloadTime => '下载时间',
      SortType.fileSize => '文件大小',
      SortType.width => '分辨率(宽)',
      SortType.height => '分辨率(高)',
      SortType.area => '分辨率(面积)',
    };
  }

  String groupTypeLabel(GroupType type) {
    return switch (type) {
      GroupType.none => '不分组',
      GroupType.date => '按日期',
      GroupType.illust => '按作品',
      GroupType.type => '按类型',
      GroupType.resolution => '按分辨率',
    };
  }
}
