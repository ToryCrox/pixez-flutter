

import 'package:mobx/mobx.dart';
import 'package:pixez/main.dart';
import 'package:pixez/custom/log.dart';
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
      Log.e('Sync tags error', error: e);
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
