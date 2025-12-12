/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */


import 'package:dio/dio.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:mobx/mobx.dart';
import 'package:pixez/custom/disk_cache.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/glance_illust_persist.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/recommend.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/page/picture/illust_store.dart';

part 'lighting_store.g.dart';

class LightingStore = _LightingStoreBase with _$LightingStore;

typedef Future<Response> FutureGet();
typedef Future<Response> FutureRefreshGet(bool force);

abstract class LightSource {
  String? glanceKey;
  String? cacheKey;
}

class ApiSource extends LightSource {
  FutureGet futureGet;

  String? g;

  ApiSource({required this.futureGet, String? cacheKey}) : super() {
    this.cacheKey = cacheKey;
  }

  Future<Response> fetch() {
    return futureGet();
  }
}

class ApiForceSource extends LightSource {
  FutureRefreshGet futureGet;

  ApiForceSource({required this.futureGet, String? glanceKey, String? cacheKey})
      : super() {
    this.glanceKey = glanceKey;
    this.cacheKey = cacheKey;
  }

  Future<Response> fetch(bool force) {
    return futureGet(force);
  }
}

abstract class _LightingStoreBase with Store {
  late LightSource source;
  String? nextUrl;
  EasyRefreshController? easyRefreshController;
  Function? onChange;
  String? portal;
  @observable
  ObservableList<IllustStore> iStores = ObservableList();
  @observable
  bool refreshing = false;

  GlanceIllustPersistProvider glanceIllustPersistProvider =
      GlanceIllustPersistProvider();

  dispose() {
    // iStores.forEach((element) {
    //   final provider = ExtendedNetworkImageProvider(
    //     element.illusts.imageUrls.medium,
    //   );
    //   provider.evict();
    // });
    // iStores.clear();
  }

  @observable
  String? errorMessage;

  _LightingStoreBase(this.source);

  bool okForUser(Illusts illust) {
    // if (userSetting.hIsNotAllow)
    //   for (int i = 0; i < illust.tags.length; i++)
    //     if (illust.tags[i].name.startsWith('R-18')) return false;
    for (var t in muteStore.banTags) {
      for (var f in illust.tags) {
        if (f.name == t.name) return false;
      }
    }
    for (var j in muteStore.banUserIds) {
      if (j.userId == illust.user.id.toString()) {
        return false;
      }
    }
    for (var i in muteStore.banillusts)
      if (illust.id == i.id) {
        return false;
      }
    return true;
  }

  bool _lock = false;

  @action
  Future<bool> fetch({String? url, bool force = false}) async {
    if (_lock) return false;
    _lock = true;
    nextUrl = null;
    errorMessage = null;
    refreshing = true;

    final cacheKey = source.cacheKey;

    // 1. 尝试从缓存加载
    if (cacheKey != null && cacheKey.isNotEmpty && iStores.isEmpty) {
      try {
        final cachedData = await DiskCache.readModel(
          cacheKey,
          (map) => Recommend.fromJson(map),
        );
        if (cachedData != null && cachedData.illusts.isNotEmpty) {
          iStores.clear();
          iStores.addAll(cachedData.illusts.map((e) => IllustStore(e.id, e)));
          nextUrl = cachedData.nextUrl;
        }
      } catch (e) {
        // 缓存读取失败，继续网络请求
      }
    }

    // 2. 加载网络数据
    try {
      Response? result = null;
      if (source is ApiSource) {
        result = await (source as ApiSource).fetch();
      } else if (source is ApiForceSource) {
        result = await (source as ApiForceSource).fetch(force);
      }

      Recommend recommend = Recommend.fromJson(result!.data);
      //https://app-api.pixiv.net/v1/user/illusts?filter=for_android&user_id=${user_id}&type=illust&offset=30
      nextUrl = recommend.nextUrl;
      iStores.clear();
      iStores.addAll(recommend.illusts.map((e) => IllustStore(e.id, e)));
      String? glanceKey = source.glanceKey;
      refreshing = false;
      if (glanceKey != null && glanceKey.isNotEmpty) {
        await glanceIllustPersistProvider.open();
        Future.microtask(() async {
          await glanceIllustPersistProvider.insertAll(recommend.illusts
              .where((element) => !element.hateByUser(includeR18Setting: true))
              .toGlancePersist(
                  glanceKey, DateTime.now().microsecondsSinceEpoch));
        });
      }

      // 3. 更新缓存
      if (cacheKey != null && cacheKey.isNotEmpty) {
        Future.microtask(() async {
          await DiskCache.writeModel(cacheKey, result!.data);
        });
      }

      easyRefreshController?.finishRefresh(IndicatorResult.success);
      return true;
    } catch (e) {
      refreshing = false;
      errorMessage = e.toString();
      easyRefreshController?.finishRefresh(IndicatorResult.fail);
      return false;
    } finally {
      _lock = false;
    }
  }

  @action
  update(LightSource futureGet) async {
    source = futureGet;
    await fetch();
  }

  @action
  Future<bool> fetchNext() async {
    if (_lock) return false;
    _lock = true;
    errorMessage = null;
    try {
      if (nextUrl != null && nextUrl!.isNotEmpty) {
        Response result = await apiClient.getNext(nextUrl!);
        Recommend recommend = Recommend.fromJson(result.data);
        nextUrl = recommend.nextUrl;
        var map = recommend.illusts.map((e) => IllustStore(e.id, e));
        
        // 获取当前已加载的所有作品ID，用于去重
        var existingIds = iStores.map((element) => element.id).toSet();
        
        // 过滤掉已存在的作品，确保不会重复显示
        map = map.where((element) => !existingIds.contains(element.id));
        
        iStores.addAll(map);
        easyRefreshController?.finishLoad(IndicatorResult.success);
      } else {
        easyRefreshController?.finishLoad(IndicatorResult.noMore);
      }
      return true;
    } catch (e) {
      easyRefreshController?.finishLoad(IndicatorResult.fail);
      return false;
    } finally {
      _lock = false;
    }
  }
}
