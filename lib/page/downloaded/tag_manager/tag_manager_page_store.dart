import 'package:mobx/mobx.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/store/tag_manager_store.dart';

part 'tag_manager_page_store.g.dart';

class TagManagerPageStore = _TagManagerPageStore with _$TagManagerPageStore;

abstract class _TagManagerPageStore with Store {
  @observable
  bool isSearching = false;

  @observable
  String searchText = '';

  @observable
  int filterCategory = -1; // -1: All, TagCategory.work.value: Work, TagCategory.character.value: Character, 99: Bookmarked

  @observable
  int sortType = 4; // 0: count desc, 1: name asc, 2: last_used desc, 3: display_order desc, 4: category asc

  @observable
  int? filterByParentId; // null表示不过滤，否则只显示该父标签的子标签

  @computed
  List<TagDisplayData> get displayTags {
    var result = tagManagerStore.tags.toList();

    // 0. 优先处理父标签过滤
    if (filterByParentId != null) {
      // 只显示该父标签的所有子标签
      result = tagManagerStore.getDirectChildren(filterByParentId!);
    }

    // 1. Filter by Search Text
    if (searchText.isNotEmpty) {
      final lowerSearch = searchText.toLowerCase();
      final matchedSet = <int>{}; // 用于去重的Set
      
      for (final data in result) {
        // 检查当前tag是否匹配
        final isMatch = data.tag.name.toLowerCase().contains(lowerSearch) ||
               data.tag.translatedName.toLowerCase().contains(lowerSearch) ||
               (data.tag.customTranslatedName?.toLowerCase().contains(lowerSearch) ?? false);
        
        if (isMatch) {
          matchedSet.add(data.tag.id);
          // 如果匹配的是父tag，也将其所有直接子tag加入结果
          final children = tagManagerStore.getDirectChildren(data.tag.id);
          for (final child in children) {
            matchedSet.add(child.tag.id);
          }
        }
      }
      
      // 根据去重后的id集合过滤结果
      result = result.where((data) => matchedSet.contains(data.tag.id)).toList();
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
    int compareTags(TagDisplayData a, TagDisplayData b) {
      switch (sortType) {
        case 0: // Count Desc
          int countCompare = b.tag.count.compareTo(a.tag.count);
          if (countCompare != 0) return countCompare;
          break;
        case 1: // Name Asc
          int nameCompare = a.tag.displayName.compareTo(b.tag.displayName);
          if (nameCompare != 0) return nameCompare;
          break;
        case 2: // Last Used Desc
          int timeCompare = (b.tag.lastUsedTime ?? 0).compareTo(a.tag.lastUsedTime ?? 0);
          if (timeCompare != 0) return timeCompare;
          break;
        case 3: // Priority / Display Order Desc
          // Primary sort is priority here, handled below
          break;
        case 4: // Category / Priority Asc
          int catCompare = a.tag.category.compareTo(b.tag.category);
          if (catCompare != 0) return catCompare;
          break;
      }
      
      // Default / Secondary sort: Priority (displayOrder) DESC
      int priorityCompare = b.tag.displayOrder.compareTo(a.tag.displayOrder);
      if (priorityCompare != 0) return priorityCompare;
      
      // Tertiary sort: Count DESC
      final countComapre = b.tag.count.compareTo(a.tag.count);
      if (countComapre != 0) return countComapre;

      return b.tag.displayName.compareTo(a.tag.displayName);
    }

    result.sort(compareTags);

    return result;
  }

  @action
  void toggleSearch(bool value) {
    isSearching = value;
    if (!value) {
      searchText = '';
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

  @observable
  bool isSelectionMode = false;

  @observable
  ObservableSet<int> selectedTagIds = ObservableSet<int>();

  @action
  void setSortType(int type) {
    sortType = type;
  }

  @action
  void toggleSelectionMode(bool value) {
    isSelectionMode = value;
    if (!value) {
      selectedTagIds.clear();
    }
  }

  @action
  void toggleTagSelection(int tagId) {
    if (selectedTagIds.contains(tagId)) {
      selectedTagIds.remove(tagId);
    } else {
      selectedTagIds.add(tagId);
    }
  }

  @action
  void selectAll() {
    for (final data in displayTags) {
      selectedTagIds.add(data.tag.id);
    }
  }

  @action
  void clearSelection() {
    selectedTagIds.clear();
  }

  @action
  void setFilterByParent(int parentId) {
    filterByParentId = parentId;
  }

  @action
  void clearParentFilter() {
    filterByParentId = null;
  }
}
