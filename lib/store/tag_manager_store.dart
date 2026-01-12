import 'dart:async';

import 'package:mobx/mobx.dart';
import 'package:pixez/main.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/models/download_record.dart';

part 'tag_manager_store.g.dart';

class TagManagerStore = _TagManagerStore with _$TagManagerStore;

abstract class _TagManagerStore with Store {
  DownloadDatabaseProvider get _dbProvider => downloadStore.dbProvider;

  StreamSubscription<List<TagChangeEvent>>? _tagChangesSubscription;

  @observable
  ObservableList<TagDisplayData> tags = ObservableList<TagDisplayData>();

  @observable
  bool isLoading = false;

  @observable
  bool isSyncing = false;

  @observable
  String syncStatus = '';

  @computed
  Map<String, TagDisplayData> get tagNameMap => {
    for (final t in tags) t.tag.name: t,
  };

  @computed
  Map<int, TagDisplayData> get tagIdMap => {for (final t in tags) t.tag.id: t};

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
    return tagNameMap[tagName];
  }

  TagDisplayData? getTagDisplayDataByID(int tagId) {
    return tagIdMap[tagId];
  }

  /// 获取标签对应的主标签（如果它本身是别名）
  DownloadedTag? getMainTag(String tagName) {
    final localData = getTagDisplayData(tagName);
    if (localData != null && localData.tag.referencedTagId != null) {
      return getTagDisplayDataByID(localData.tag.referencedTagId!)?.tag;
    }
    return null;
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

  @action
  Future<void> toggleExampleIllust(
    int tagId,
    int illustId,
    String squareMediumUrl,
  ) async {
    final index = tags.indexWhere((t) => t.tag.id == tagId);
    if (index == -1) return;

    final oldData = tags[index];
    final exampleIds = List<int>.from(oldData.tag.exampleIllustIds);
    final List<IllustPreviewData> previewIllusts = List.from(
      oldData.previewIllusts,
    );

    if (exampleIds.contains(illustId)) {
      exampleIds.remove(illustId);
      previewIllusts.removeWhere((p) => p.illustId == illustId);
    } else {
      // 最多 3 个
      if (exampleIds.length >= 3) {
        exampleIds.removeAt(0);
        if (previewIllusts.isNotEmpty) {
          previewIllusts.removeAt(0);
        }
      }
      exampleIds.add(illustId);
      previewIllusts.add(
        IllustPreviewData(illustId: illustId, squareMediumUrl: squareMediumUrl),
      );
    }

    final newTag = oldData.tag.copyWith(exampleIllusts: exampleIds.join(','));
    await downloadStore.updateTagExampleIllusts(tagId, exampleIds);

    tags[index] = oldData.copyWith(tag: newTag, previewIllusts: previewIllusts);
  }

  /// 开始监听tag变更事件
  void startListening() {
    _tagChangesSubscription = _dbProvider.tagChanges.listen((events) {
      runInAction(() {
        for (final event in events) {
          _applyTagChange(event);
        }
      });
    });
  }

  /// 应用tag变更事件
  void _applyTagChange(TagChangeEvent event) {
    final index = tags.indexWhere((t) => t.tag.id == event.tagId);

    if (index == -1) {
      // Tag不在列表中，说明是新tag，需要添加
      final newTag = DownloadedTag(
        id: event.tagId,
        name: event.tagName,
        count: event.newCount,
        exampleIllusts: event.newExampleIllustIds.join(','),
      );

      final previews =
          event.type == TagChangeType.illustAdded &&
                  event.squareMediumUrl != null
              ? [
                IllustPreviewData(
                  illustId: event.illustId,
                  squareMediumUrl: event.squareMediumUrl!,
                ),
              ]
              : <IllustPreviewData>[];

      tags.add(
        TagDisplayData(
          tag: newTag,
          previewIllusts: previews,
          hasEquivalentTags: false,
        ),
      );
      return;
    }

    // Tag在列表中，更新现有数据
    final oldData = tags[index];
    DownloadedTag updatedTag = oldData.tag;
    List<IllustPreviewData> updatedPreviews = List.from(oldData.previewIllusts);

    // 更新 count 和 exampleIllusts
    updatedTag = updatedTag.copyWith(
      count: event.newCount,
      exampleIllusts: event.newExampleIllustIds.join(','),
    );

    // 更新 previewIllusts
    if (event.type == TagChangeType.illustAdded) {
      // 添加新的预览图（如果不足3个）
      if (updatedPreviews.length < 3 && event.squareMediumUrl != null) {
        final alreadyExists = updatedPreviews.any(
          (p) => p.illustId == event.illustId,
        );
        if (!alreadyExists) {
          updatedPreviews.add(
            IllustPreviewData(
              illustId: event.illustId,
              squareMediumUrl: event.squareMediumUrl!,
            ),
          );
        }
      }
    } else if (event.type == TagChangeType.illustRemoved) {
      // 移除对应的预览图
      updatedPreviews.removeWhere((p) => p.illustId == event.illustId);
    }

    tags[index] = oldData.copyWith(
      tag: updatedTag,
      previewIllusts: updatedPreviews,
    );
  }

  /// 清理资源
  void dispose() {
    _tagChangesSubscription?.cancel();
  }
}
