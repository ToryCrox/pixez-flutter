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
import 'package:pixez/lighting/lighting_store.dart';
import 'package:pixez/models/novel_recom_response.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/page/novel/viewer/novel_store.dart';
import 'package:pixez/custom/log.dart';

part 'novel_lighting_store.g.dart';

class NovelLightingStore extends _NovelLightingStoreBase
    with _$NovelLightingStore {
  NovelLightingStore(
    FutureGet source,
    EasyRefreshController controller, {
    String? cacheKey,
  }) : super(source, controller, cacheKey: cacheKey);
}

abstract class _NovelLightingStoreBase with Store {
  FutureGet source;
  final ApiClient _client = apiClient;
  final EasyRefreshController controller;

  _NovelLightingStoreBase(this.source, this.controller, {this.cacheKey});

  String? nextUrl;
  String? cacheKey;
  ObservableList<NovelStore> novels = ObservableList();
  @observable
  String? errorMessage;

  @action
  Future<void> fetch({bool loadCache = false}) async {
    nextUrl = null;
    errorMessage = null;

    if (cacheKey != null &&
        cacheKey!.isNotEmpty &&
        (loadCache || novels.isEmpty)) {
      try {
        final cachedData = await DiskCache.readModel(
          cacheKey!,
          (map) => NovelRecomResponse.fromJson(map),
        );
        if (cachedData != null && cachedData.novels.isNotEmpty) {
          novels.clear();
          nextUrl = cachedData.nextUrl;
          novels.addAll(
            cachedData.novels.map((element) => NovelStore(element.id, element)),
          );
        }
      } catch (_) {
        // 缓存读取失败时继续请求网络数据。
      }
    }

    try {
      Response response = await source();
      NovelRecomResponse novelRecomResponse = NovelRecomResponse.fromJson(
        response.data,
      );
      nextUrl = novelRecomResponse.nextUrl;
      final novel = novelRecomResponse.novels;
      this.novels.clear();
      this.novels.addAll(
        novel.map((element) => NovelStore(element.id, element)),
      );

      if (cacheKey != null && cacheKey!.isNotEmpty) {
        Future.microtask(() => DiskCache.writeModel(cacheKey!, response.data));
      }

      controller.finishRefresh(IndicatorResult.success);
    } catch (e) {
      Log.e('Failed to fetch novels', error: e);
      errorMessage = e.toString();
      controller.finishRefresh(IndicatorResult.fail);
    }
  }

  @action
  Future<void> next() async {
    if (nextUrl != null && nextUrl!.isNotEmpty) {
      try {
        Response response = await _client.getNext(nextUrl!);
        NovelRecomResponse novelRecomResponse = NovelRecomResponse.fromJson(
          response.data,
        );
        nextUrl = novelRecomResponse.nextUrl;
        final novel = novelRecomResponse.novels;
        novels.addAll(novel.map((element) => NovelStore(element.id, element)));
        controller.finishLoad(IndicatorResult.success);
      } catch (e) {
        controller.finishLoad(IndicatorResult.fail);
      }
    } else {
      controller.finishLoad(IndicatorResult.noMore);
    }
  }
}
