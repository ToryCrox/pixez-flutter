import 'dart:convert';
import 'dart:io';


import 'package:flutter/material.dart';
import 'package:mobx/mobx.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/er/sharer.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/history/history_database.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/saf_plugin.dart';
import 'package:bot_toast/bot_toast.dart';

part 'history_store.g.dart';

class HistoryStore = _HistoryStore with _$HistoryStore;

abstract class _HistoryStore with Store {
  final HistoryDatabaseProvider _dbProvider = HistoryDatabaseProvider.instance;

  @observable
  ObservableList<IllustStore> illusts = ObservableList<IllustStore>();

  @observable
  bool loading = false;

  @observable
  String? currentKeyword;

  _HistoryStore() {
    _init();
  }

  Future<void> _init() async {
    await _dbProvider.open();
  }

  @action
  Future<void> fetch() async {
    if (loading) return;
    loading = true;
    try {
      await _dbProvider.open();
      // 获取数据
      final list = await _dbProvider.query(keyword: currentKeyword);
      
      // 清理旧的 store
      for (var s in illusts) {
        s.dispose();
      }
      illusts.clear();
      
      // 转换为 IllustStore
      // HistoryPage 的 item 不需要完整网络请求能力，但 IllustCard 需要 IllustStore
      // 我们创建一个已经包含数据的 IllustStore
      for (var illust in list) {
        illusts.add(IllustStore(illust.id, illust));
      }
    } finally {
      loading = false;
    }
  }

  @action
  Future<void> search(String keyword) async {
    currentKeyword = keyword;
    await fetch();
  }

  @action
  Future<void> delete(int id) async {
    await _dbProvider.delete(id);
    // 从列表中移除，避免重新 fetch
    final index = illusts.indexWhere((element) => element.id == id);
    if (index != -1) {
      illusts[index].dispose();
      illusts.removeAt(index);
    }
  }

  @action
  Future<void> deleteAll() async {
    await _dbProvider.deleteAll();
    for (var s in illusts) {
      s.dispose();
    }
    illusts.clear();
  }

  Future<void> exportData(BuildContext context) async {
    try {
       await _dbProvider.open();
       final list = await _dbProvider.query();
       final entity = list.map((e) => e.toJson()).toList();
       final exportJson = jsonEncode(entity);
       final uint8List = utf8.encode(exportJson);
       
        if (Platform.isIOS) {
          await Sharer.exportUint8List(context, uint8List,
              "pixez_history_${DateTime.now().toIso8601String()}.json");
        } else {
          final uri = await SAFPlugin.createFile(
              "pixez_history_${DateTime.now().toIso8601String()}.json",
              "application/json");
          if (uri != null) {
            await SAFPlugin.writeUri(uri, uint8List);
          }
        }
    } catch (e) {
      Log.e('Export history failed', error: e);
      BotToast.showText(text: "Export failed: $e");
      rethrow;
    }
  }

  Future<void> importData() async {
    try {
      final bytes = await SAFPlugin.openFile();
      if (bytes != null) {
        final jsonStr = utf8.decode(bytes);
        final List list = jsonDecode(jsonStr);
        await _dbProvider.open();
        for (var item in list) {
          try {
            await _dbProvider.insert(Illusts.fromJson(item));
          } catch (e) {
            Log.e('Import item failed', error: e);
          }
        }
        BotToast.showText(text: "Import success");
      }
    } catch (e) {
      Log.e('Import history failed', error: e);
      BotToast.showText(text: "Import failed: $e");
    }
  }
}

