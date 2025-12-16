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
import 'package:pixez/custom/log.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/recommend.dart';
import 'package:pixez/network/api_client.dart';

part 'illust_about_store.g.dart';

class IllustAboutStore = _IllustAboutStoreBase with _$IllustAboutStore;

abstract class _IllustAboutStoreBase with Store {
  final int id;
  bool fetching = false;
  EasyRefreshController? refreshController;

  _IllustAboutStoreBase(this.id, this.refreshController);

  @observable
  String? errorMessage;

  String? _nextUrl;

  ObservableList<Illusts> illusts = ObservableList();

  /// 获取缓存键
  String get _cacheKey => 'illust_about_$id';

  @action
  Future<bool> next() async {
    if (fetching) {
      return false;
    }
    try {
      fetching = true;

      // 1. 第一页时尝试从缓存加载
      if ((_nextUrl == null || _nextUrl!.isEmpty) && illusts.isEmpty) {
        try {
          final cachedData = await DiskCache.readModel(
            _cacheKey,
            (map) => Recommend.fromJson(map),
          );
          if (cachedData != null && cachedData.illusts.isNotEmpty) {
            illusts.clear();
            illusts.addAll(
                cachedData.illusts.takeWhile((value) => !value.hateByUser()));
            _nextUrl = cachedData.nextUrl;
            Log.d('从缓存加载相关插画: ${illusts.length} 张');
          }
        } catch (e) {
          // 缓存读取失败，继续网络请求
          Log.w('缓存读取失败: $e');
        }
      }

      // 2. 加载网络数据
      Response response = _nextUrl == null || _nextUrl!.isEmpty
          ? await apiClient.getIllustRelated(id)
          : await apiClient.getNext(_nextUrl!);
      Recommend recommend = Recommend.fromJson(response.data);
      _nextUrl = recommend.nextUrl;
      final resultIllusts = recommend.illusts;
      if (resultIllusts.isEmpty) {
        refreshController?.finishLoad(IndicatorResult.noMore);
        return true;
      }
      illusts.addAll(resultIllusts.takeWhile((value) => !value.hateByUser()));

      // 3. 第一页时更新缓存
      if (illusts.length == resultIllusts.length) {
        Future.microtask(() async {
          await DiskCache.writeModel(_cacheKey, response.data);
          Log.d('已缓存相关插画数据');
        });
      }

      if (_nextUrl == null || _nextUrl!.isEmpty || recommend.illusts.isEmpty) {
        refreshController?.finishLoad(IndicatorResult.noMore);
      } else {
        refreshController?.finishLoad(IndicatorResult.success);
      }
      Log.d('nextUrl: $_nextUrl');
      return true;
    } catch (e) {
      refreshController?.finishLoad(IndicatorResult.fail);
      Log.d('failed to load next: $e');
      return false;
    } finally {
      fetching = false;
    }
  }
}
