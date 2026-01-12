import 'package:mobx/mobx.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';

part 'tag_manager_page_store.g.dart';

class TagManagerPageStore = _TagManagerPageStore with _$TagManagerPageStore;

abstract class _TagManagerPageStore with Store {
  @observable
  bool isSearching = false;

  @observable
  String searchText = '';

  @observable
  int filterCategory = -1; // -1: All, 1: Work, 2: Character, 99: Bookmarked

  @observable
  int sortType = 4; // 0: count desc, 1: name asc, 2: last_used desc, 3: display_order desc, 4: category asc

  @computed
  List<TagDisplayData> get displayTags {
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
      case 4: // Category Asc
        result.sort((a, b) {
           int catCompare = a.tag.category.compareTo(b.tag.category);
           if (catCompare != 0) return catCompare;
           // Secondary sort by count desc
           return b.tag.count.compareTo(a.tag.count);
        });
        break;
    }

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
}
