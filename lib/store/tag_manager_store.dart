import 'package:mobx/mobx.dart';
import 'package:pixez/main.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/models/download_record.dart';
import 'package:collection/collection.dart';

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

  @action
  Future<void> loadTags({bool force = false}) async {
    // If not forced and already has data, skip loading
    if (!force && tags.isNotEmpty) return;

    isLoading = true;
    try {
      // Load ALL tags from DB (no db-side sorting/filtering needed if we do it locally,
      // but initial load might want a default sort. Let's just load all.)
      final list = await _dbProvider.getTags();
      tags = ObservableList.of(list);
    } catch (e) {
      Log.e('Load tags error', error: e);
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> syncTags() async {
    if (isSyncing) return;
    isSyncing = true;
    syncStatus = '正在准备...';
    try {
      await _dbProvider.syncTags(
        onStatus: (status) {
          runInAction(() {
            syncStatus = status;
          });
        },
      );

      // reload tags
      await loadTags(force: true);
    } catch (e) {
      Log.e('Sync tags error', error: e);
      syncStatus = '失败: $e';
    } finally {
      isSyncing = false;
      syncStatus = '';
    }
  }

  @action
  Future<void> updateTag(DownloadedTag tag) async {
    await _dbProvider.updateTag(tag);

    // Update local list
    int index = tags.indexWhere((t) => t.tag.name == tag.name);
    if (index != -1) {
      final oldData = tags[index];
      tags[index] = oldData.copyWith(tag: tag);
    }
  }

  @action
  Future<void> bookTag(String tagName) async {
    final index = tags.indexWhere((t) => t.tag.name == tagName);
    if (index != -1) {
      final oldData = tags[index];
      final newTag = oldData.tag.copyWith(
        isBookmarked: !oldData.tag.isBookmarked,
      );

      // Optimistically update UI
      tags[index] = oldData.copyWith(tag: newTag);

      await _dbProvider.updateTag(newTag);
    } else {
      // New tag, insert it as bookmarked
      final newTag = DownloadedTag(
        id: 0, // ID will be auto-generated or ignored by insert
        name: tagName,
        translatedName: '',
        isBookmarked: true,
        count: 0,
        category: 0,
      );
      await _dbProvider.updateTag(newTag);
      await loadTags(force: true);
    }
  }

  TagDisplayData? getTagDisplayData(String tagName) {
    return tags.firstWhereOrNull((t) => t.tag.name == tagName);
  }

  @action
  Future<void> associateTags(int primaryTagId, List<int> aliasTagIds) async {
    await _dbProvider.associateTags(primaryTagId, aliasTagIds);
    // Reload to refresh all info
    await loadTags(force: true);
  }

  @action
  Future<void> dissociateTags(List<int> tagIds) async {
    await _dbProvider.dissociateTags(tagIds);
    // Reload to refresh all info
    await loadTags(force: true);
  }

  @action
  Future<void> batchUpdateCategory(List<int> tagIds, int category) async {
    await _dbProvider.batchUpdateTagCategory(tagIds, category);

    // Update local list
    final tagIdSet = tagIds.toSet();
    for (int i = 0; i < tags.length; i++) {
      if (tagIdSet.contains(tags[i].tag.id)) {
        final oldData = tags[i];
        tags[i] = oldData.copyWith(
          tag: oldData.tag.copyWith(category: category),
        );
      }
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

  @action
  Future<List<DownloadedTag>> expandSelectedTags(List<int> ids) async {
    return await _dbProvider.getExpandedTags(ids);
  }

  @action
  Future<List<DownloadedTag>> getEquivalenceGroup(int tagId) async {
    return await _dbProvider.getEquivalenceGroup(tagId);
  }

  @action
  Future<void> updateEquivalenceGroup(
    int newPrimaryId,
    List<int> allTagIds,
  ) async {
    await _dbProvider.updateEquivalenceGroup(newPrimaryId, allTagIds);
    await loadTags(force: true);
  }

  @action
  Future<void> dissociateSingleTag(int tagId) async {
    await _dbProvider.dissociateTags([tagId]);
    await loadTags(force: true);
  }
}
