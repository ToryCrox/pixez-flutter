import 'dart:async';

import 'package:mobx/mobx.dart';
import 'package:pixez/main.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/models/download_record.dart';
import 'package:collection/collection.dart';

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
  Map<String, TagDisplayData> get tagNameMap {
    Log.d(() => 'tagNameMap updated ${tags.length}');
    return {for (final t in tags) t.tag.name: t};
  }

  @computed
  Map<int, TagDisplayData> get tagIdMap => {for (final t in tags) t.tag.id: t};

  @computed
  Map<int, List<TagDisplayData>> get childrenMap {
    final map = <int, List<TagDisplayData>>{};
    for (final t in tags) {
      if (t.tag.parentId != 0) {
        map.putIfAbsent(t.tag.parentId, () => []).add(t);
      }
    }
    return map;
  }

  /// 获取指定父tag的所有直接子tag
  List<TagDisplayData> getDirectChildren(int parentId) {
    return childrenMap[parentId] ?? [];
  }

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
    if (localData != null && localData.tag.referencedTagId != 0) {
      return getTagDisplayDataByID(localData.tag.referencedTagId)?.tag;
    }
    return null;
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
  List<TagDisplayData> expandSelectedTags(List<int> ids) {
    if (ids.isEmpty) return [];

    // 如果 tags 已加载，则直接从内存中计算等价组展开
    if (tags.isNotEmpty) {
      final rootIds = ids.map((id) {
        final tagData = tagIdMap[id];
        if (tagData == null) return null;
        return tagData.tag.referencedTagId == 0 ? tagData.tag.id : tagData.tag.referencedTagId;
      }).whereType<int>().toSet();

      if (rootIds.isNotEmpty) {
        return tags
            .where((t) =>
                rootIds.contains(t.tag.id) ||
                (t.tag.referencedTagId != 0 &&
                    rootIds.contains(t.tag.referencedTagId)))
            .toList();
      }
    }

    return [];
  }

  @action
  List<TagDisplayData> getEquivalenceGroup(int tagId) {
    // 如果 tags 已加载，优先从内存获取
    if (tags.isNotEmpty) {
      final tagData = tagIdMap[tagId];
      if (tagData != null) {
        final mainId = tagData.tag.referencedTagId == 0 ? tagData.tag.id : tagData.tag.referencedTagId;
        Log.d(() => 'getEquivalenceGroup $tagId, $mainId');
        return tags
            .where((t) =>
                t.tag.id == mainId || t.tag.referencedTagId == mainId)
            .map((t) {
              Log.d(() => 'getEquivalenceGroup ${t.tag.name}, ${t.tag.referencedTagId}, ${t.tag.id}');
              return t;
            })
            .toList();
      }
    }

    return [];
  }

  @action
  Future<void> updateEquivalenceGroup(
    int newPrimaryId,
    List<int> allTagIds, [
    List<int>? removedIds,
  ]) async {
    Log.d(() => 'updateEquivalenceGroup $newPrimaryId, $allTagIds, $removedIds');
    await _dbProvider.updateEquivalenceGroup(newPrimaryId, allTagIds, removedIds);
    
    // 直接在内存中更新受影响的标签，避免重新加载所有标签
    final allAffectedIds = {...allTagIds, if (removedIds != null) ...removedIds};
    final aliasIds = allTagIds.where((id) => id != newPrimaryId).toSet();
    
    for (int i = 0; i < tags.length; i++) {
      final tagId = tags[i].tag.id;
      if (allAffectedIds.contains(tagId)) {
        final oldData = tags[i];
        final newReferencedTagId = 
            (removedIds?.contains(tagId) ?? false) ? 0 :
            (tagId == newPrimaryId ? 0 : newPrimaryId);
        Log.d(() => 'updateEquivalenceGroup $tagId, $newReferencedTagId');
        final hasEquivalentTags = allTagIds.contains(tagId);
        tags[i] = oldData.copyWith(
          tag: oldData.tag.copyWith(referencedTagId: newReferencedTagId),
          hasEquivalentTags: hasEquivalentTags,
        );
      } else if (aliasIds.contains(tags[i].tag.parentId)) {
        // 将非主标签成员的子标签的 parentId 重指向主标签
        final oldData = tags[i];
        tags[i] = oldData.copyWith(
          tag: oldData.tag.copyWith(parentId: newPrimaryId),
        );
      }
    }
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

  @action
  Future<void> updateTagParent(int childId, int parentId, {String? newName}) async {
    final index = tags.indexWhere((t) => t.tag.id == childId);
    if (index != -1) {
      final oldData = tags[index];
      
      // Reuse updateTag which persists to DB
      await updateTag(oldData.tag.copyWith(
        parentId: parentId,
        customTranslatedName: newName ?? oldData.tag.customTranslatedName,
      ));
    }
  }

  @action
  Future<void> batchUpdateTagParent(List<int> childIds, int parentId, {Map<int, String>? newNames}) async {
    final affectedParentIds = <int>{};
    
    for (final childId in childIds) {
      final index = tags.indexWhere((t) => t.tag.id == childId);
      if (index != -1) {
        final oldData = tags[index];
        final oldParentId = oldData.tag.parentId;
        if (oldParentId != 0) affectedParentIds.add(oldParentId);
        
        final newName = newNames?[childId];
        await updateTag(oldData.tag.copyWith(
          parentId: parentId,
          customTranslatedName: newName ?? oldData.tag.customTranslatedName,
        ));
      }
    }
  }

  /// 获取标签推荐的父级（作品）
  Future<List<DownloadedTag>> getRecommendedParents(int tagId) async {
    final coOccurring = await _dbProvider.getCoOccurringWorkTags(tagId, limit: 5);
    // Resolve to main tags and remove duplicates
    final results = <int, DownloadedTag>{};
    for (var tag in coOccurring) {
      final main = getMainTagByTag(tag) ?? tag;
      if (!results.containsKey(main.id)) {
        results[main.id] = main;
      }
    }
    return results.values.toList();
  }

  /// 扫描潜在的父子标签关联，基于命名规则和共现分析
  /// 例如 "角色名（作品名）" -> 父标签: "作品名"
  Future<List<TagAssociationProposal>> scanForAutoAssociations() async {
    final proposals = <TagAssociationProposal>[];
    if (tags.isEmpty) return proposals;
    
    // 限制单次扫描显示的建议数量，避免 UI 过载且提升响应速度
    const int maxProposals = 30;

    // 1. 构建作品标签映射表，用于快速查找
    final workMap = <String, DownloadedTag>{};
    for (var t in tags) {
      if (t.tag.category == TagCategory.work.value) {
        workMap[t.tag.name] = t.tag;
        if (t.tag.translatedName.isNotEmpty) {
          workMap[t.tag.translatedName] = t.tag;
        }
        if (t.tag.customTranslatedName?.isNotEmpty == true) {
          workMap[t.tag.customTranslatedName!] = t.tag;
        }
      }
    }

    final pattern = RegExp(r'^(.+)[(（](.+)[)）]$');

    // 第一步：执行高效的正则扫描
    for (final t in tags) {
      if (proposals.length >= maxProposals) break;

      // 遵守规则：已经有关联的不再扫描，排除作品、通用、元数据
      final cat = t.tag.category;
      if (t.tag.parentId != 0 || 
          cat == TagCategory.work.value || 
          cat == TagCategory.general.value || 
          cat == TagCategory.meta.value) continue;

      String nameToCheck = t.tag.displayTranslatedName.isNotEmpty 
          ? t.tag.displayTranslatedName : t.tag.name;

      var match = pattern.firstMatch(nameToCheck);
      if (match != null) {
        final cleanName = match.group(1)!.trim();
        final matchedWorkName = match.group(2)!.trim();
        
        var parentTag = workMap[matchedWorkName];
        if (parentTag != null) {
          // 优先使用主标签（如果存在等价标签）
          final mainTag = getMainTagByTag(parentTag) ?? parentTag;
          proposals.add(TagAssociationProposal(
            childTag: t.tag,
            parentTag: mainTag,
            newChildName: cleanName,
            suggestionReason: '正则匹配',
          ));
        }
      }
    }

    // 第二步：如果还没满，执行批量共现分析
    if (proposals.length < maxProposals) {
      final potentialBatches = await _dbProvider.getGlobalCoOccurrenceProposals(limit: 100);
      final existingChildIds = proposals.map((p) => p.childTag.id).toSet();
      
      for (var batch in potentialBatches) {
        if (proposals.length >= maxProposals) break;
        
        final childId = batch['child_id'] as int;
        final parentId = batch['parent_id'] as int;
        
        if (existingChildIds.contains(childId)) continue;
        
        final childData = tagIdMap[childId];
        final parentData = tagIdMap[parentId];
        
        if (childData != null && parentData != null) {
          // 优先使用主标签（如果存在等价标签）
          final mainParent = getMainTagByTag(parentData.tag) ?? parentData.tag;
          proposals.add(TagAssociationProposal(
            childTag: childData.tag,
            parentTag: mainParent,
            newChildName: childData.tag.displayTranslatedName.isNotEmpty 
                ? childData.tag.displayTranslatedName : childData.tag.name,
            suggestionReason: '插画共现分析',
          ));
          existingChildIds.add(childId);
        }
      }
    }

    return proposals;
  }

  /// Helper to get main tag for a given tag object
  DownloadedTag? getMainTagByTag(DownloadedTag tag) {
    final mainTagInfo = getMainTag(tag.name);
    if (mainTagInfo == null) return null;
    
    // Find the actual DownloadedTag for the main tag name
    return tags.firstWhereOrNull((t) => t.tag.name == mainTagInfo.name)?.tag;
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

class TagAssociationProposal {
  final DownloadedTag childTag;
  final DownloadedTag parentTag;
  final String newChildName;
  final String suggestionReason; // e.g. "正则匹配" or "标签共现"

  TagAssociationProposal({
    required this.childTag,
    required this.parentTag,
    required this.newChildName,
    this.suggestionReason = '正则匹配',
  });
}
