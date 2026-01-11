
import 'package:mobx/mobx.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';

part 'tag_manager_store.g.dart';

class TagManagerStore = _TagManagerStore with _$TagManagerStore;

abstract class _TagManagerStore with Store {
  DownloadDatabaseProvider get _dbProvider => downloadStore.dbProvider;

  @observable
  ObservableList<TagDisplayData> tags = ObservableList<TagDisplayData>();

  @observable
  bool isLoading = false;

  @observable
  bool isSyncing = false;

  @observable
  String syncStatus = '';

  // Client-side Filters
  @observable
  String searchText = '';

  @observable
  int filterCategory = -1; // -1: All, 1: Work, 2: Character, 99: Bookmarked

  @observable
  int sortType = 0; // 0: count desc, 1: name asc, 2: last_used desc, 3: display_order desc

  @computed
  List<TagDisplayData> get displayTags {
    var result = tags.toList();

    // 1. Filter by Search Text
    if (searchText.isNotEmpty) {
      final lowerSearch = searchText.toLowerCase();
      result = result.where((data) {
        return data.tag.name.toLowerCase().contains(lowerSearch) ||
               data.tag.translatedName.toLowerCase().contains(lowerSearch) ||
               (data.tag.customTranslatedName?.toLowerCase().contains(lowerSearch) ?? false);
      }).toList();
    }

    // 2. Filter by Category / Bookmark
    if (filterCategory != -1) {
      if (filterCategory == 99) {
        result = result.where((data) => data.tag.isBookmarked).toList();
      } else {
        result = result.where((data) => data.tag.category == filterCategory).toList();
      }
    }

    // 3. Sort
    switch (sortType) {
      case 0: // Count Desc
        result.sort((a, b) => b.tag.count.compareTo(a.tag.count));
        break;
      case 1: // Name Asc
        result.sort((a, b) => a.tag.displayName.compareTo(b.tag.displayName));
        break;
      case 2: // Last Used Desc
        result.sort((a, b) => (b.tag.lastUsedTime ?? 0).compareTo(a.tag.lastUsedTime ?? 0));
        break;
      case 3: // Display Order Desc
        result.sort((a, b) => b.tag.displayOrder.compareTo(a.tag.displayOrder));
        break;
    }

    return result;
  }

  @action
  Future<void> loadTags({bool force = false}) async {
    // If not forced and already has data, skip loading
    if (!force && tags.isNotEmpty) return;

    isLoading = true;
    try {
      // Load ALL tags from DB (no db-side sorting/filtering needed if we do it locally, 
      // but initial load might want a default sort. Let's just load all.)
      final list = await _dbProvider.getTags(sortType: 0, filterCategory: -1);
      tags = ObservableList.of(list);
    } catch (e) {
      print('Load tags error: $e');
    } finally {
      isLoading = false;
    }
  }

  @action
  void setSearchText(String text) {
    searchText = text;
  }

  @action
  void setFilterCategory(int category) {
    filterCategory = category;
  }

  @action
  void setSortType(int type) {
    sortType = type;
  }

  @action
  Future<void> syncTags() async {
    if (isSyncing) return;
    isSyncing = true;
    syncStatus = '正在准备...';
    try {
      await _dbProvider.syncTags(onStatus: (status) {
         runInAction(() {
             syncStatus = status;
         });
      });
      
      // reload tags
      await loadTags(force: true);
      
    } catch (e) {
      print('Sync tags error: $e');
      runInAction(() {
          syncStatus = '失败: $e';
      });
    } finally {
      runInAction(() {
          isSyncing = false;
          syncStatus = '';
      });
    }
  }

  @action
  Future<void> updateTag(DownloadedTag tag) async {
    await _dbProvider.updateTag(tag);
    
    // Update local list
    int index = tags.indexWhere((t) => t.tag.name == tag.name);
    if (index != -1) {
      final oldData = tags[index];
      tags[index] = TagDisplayData(tag: tag, previewIllusts: oldData.previewIllusts);
      // Trigger list refresh if needed
      tags = ObservableList.of(tags);
    }
  }

  @action
  Future<void> addCustomTagToIllust(int illustId, String tagName) async {
    await _dbProvider.addCustomTagToIllust(illustId, tagName);
  }

  @action
  Future<void> removeCustomTagFromIllust(int illustId, String tagName) async {
     await _dbProvider.removeCustomTagFromIllust(illustId, tagName);
  }

  Future<List<String>> getTagsForIllust(int illustId) async {
    return await _dbProvider.getTagsForIllust(illustId);
  }
}
