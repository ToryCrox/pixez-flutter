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

  @computed
  List<TagDisplayData> get displayTags {
    if (isTreeView && searchText.isEmpty && filterCategory == -1) {
       return _buildTreeList();
    }

    var result = tagManagerStore.tags.toList();

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


  @observable
  bool isTreeView = false;

  @observable
  ObservableSet<int> expandedParentIds = ObservableSet<int>();

  @action
  void toggleTreeView(bool value) {
    isTreeView = value;
    // Reset filters if entering tree view?
    if (value) {
      filterCategory = -1;
      searchText = '';
    }
  }

  @action
  void toggleParentExpansion(int parentId) {
    if (expandedParentIds.contains(parentId)) {
      expandedParentIds.remove(parentId);
    } else {
      expandedParentIds.add(parentId);
    }
  }

  List<TagDisplayData> _buildTreeList() {
    final output = <TagDisplayData>[];
    
    // 1. Get all Work tags
    final works = tagManagerStore.tags.where((t) => t.tag.category == TagCategory.work.value).toList();
    // Sort
    _sortTags(works);

    for (final work in works) {
      output.add(work);
      if (expandedParentIds.contains(work.tag.id)) {
        final children = tagManagerStore.childrenMap[work.tag.id];
        if (children != null) {
          final indented = children.map((c) => c.copyWith(indentLevel: 1)).toList();
          _sortTags(indented);
          output.addAll(indented);
        }
      }
    }

    // 2. Uncategorized (Tags that are NOT Works and have NO Parent)
    final uncategorized = tagManagerStore.tags.where((t) => 
      t.tag.category != TagCategory.work.value && t.tag.parentId == 0
    ).toList();
    
    if (uncategorized.isNotEmpty) {
      // Add a header for Uncategorized?
      // Or just append them. Currently appending.
      _sortTags(uncategorized);
      output.addAll(uncategorized);
    }

    return output;
  }

  void _sortTags(List<TagDisplayData> list) {
    list.sort((a, b) {
       // Just reuse simple sort logic: Count desc or Name asc?
       // Let's use name asc for tree view standard
       return a.tag.displayName.compareTo(b.tag.displayName);
    });
  }
}
