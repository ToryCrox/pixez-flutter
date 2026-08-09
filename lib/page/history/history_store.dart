import 'dart:convert';
import 'dart:io';

import 'package:easy_refresh/easy_refresh.dart';
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
  static const int _pageSize = 50;
  final HistoryDatabaseProvider _dbProvider = HistoryDatabaseProvider.instance;

  final EasyRefreshController easyRefreshController = EasyRefreshController(
    controlFinishRefresh: true,
    controlFinishLoad: true,
  );

  @observable
  ObservableList<IllustStore> illusts = ObservableList<IllustStore>();

  @observable
  bool loading = false;

  @observable
  bool loadingMore = false;

  @observable
  bool hasMore = true;

  @observable
  int page = 0;

  @observable
  String? currentKeyword;

  _HistoryStore() {
    fetch(refresh: true);
  }

  @action
  Future<void> fetch({bool refresh = false}) async {
    if (refresh) {
      if (loading) return;
      loading = true;
      page = 0;
      hasMore = true;
    } else {
      if (loadingMore || !hasMore) {
        easyRefreshController.finishLoad(IndicatorResult.noMore);
        return;
      }
      loadingMore = true;
      page++;
    }

    try {
      final offset = page * _pageSize;
      final list = await _dbProvider.query(
        keyword: currentKeyword,
        limit: _pageSize,
        offset: offset,
      );

      if (refresh) {
        for (var s in illusts) {
          s.dispose();
        }
        illusts.clear();
      }

      for (var illust in list) {
        illusts.add(IllustStore(illust.id, illust));
      }

      hasMore = list.length >= _pageSize;

      if (refresh) {
        easyRefreshController.finishRefresh();
        easyRefreshController.resetFooter();
      } else {
        easyRefreshController.finishLoad(
          hasMore ? IndicatorResult.success : IndicatorResult.noMore,
        );
      }
    } catch (e) {
      Log.e('Fetch history failed (refresh: $refresh)', error: e);
      BotToast.showText(text: "Fetch failed: $e");
      if (refresh) {
        easyRefreshController.finishRefresh(IndicatorResult.fail);
      } else {
        page--;
        easyRefreshController.finishLoad(IndicatorResult.fail);
      }
    } finally {
      if (refresh) {
        loading = false;
      } else {
        loadingMore = false;
      }
    }
  }

  @action
  Future<void> search(String keyword) async {
    currentKeyword = keyword.isEmpty ? null : keyword;
    await fetch(refresh: true);
  }

  @action
  Future<void> delete(int id) async {
    await _dbProvider.delete(id);
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
    page = 0;
    hasMore = false;
    easyRefreshController.resetFooter();
  }

  Future<void> exportData(BuildContext context) async {
    try {
      final list = await _dbProvider.query();
      final entity = list.map((e) => e.toJson()).toList();
      final exportJson = jsonEncode(entity);
      final uint8List = utf8.encode(exportJson);

      if (Platform.isIOS) {
        await Sharer.exportUint8List(
          context,
          uint8List,
          "pixez_history_${DateTime.now().toIso8601String()}.json",
        );
      } else {
        final uri = await SAFPlugin.createFile(
          "pixez_history_${DateTime.now().toIso8601String()}.json",
          "application/json",
        );
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
