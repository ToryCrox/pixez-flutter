import 'package:dio/dio.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:mobx/mobx.dart';
import 'package:pixez/custom/disk_cache.dart';
import 'package:pixez/lighting/lighting_store.dart';
import 'package:pixez/models/user_preview.dart';
import 'package:pixez/network/api_client.dart';

part 'painter_list_store.g.dart';

class PainterListStore = _PainterListStoreBase with _$PainterListStore;

abstract class _PainterListStoreBase with Store {
  ObservableList<UserPreviews> users = ObservableList();
  FutureGet source;
  String? nextUrl;
  final EasyRefreshController _controller;
  String? cacheKey;

  _PainterListStoreBase(this._controller, this.source, {this.cacheKey});

  bool _lock = false;
  @action
  Future<bool> fetch() async {
    if (_lock) return false;
    _lock = true;
    nextUrl = null;

    // 1. 尝试从缓存加载
    if (cacheKey != null && cacheKey!.isNotEmpty && users.isEmpty) {
      try {
        final cachedData = await DiskCache.readModel(
          cacheKey!,
          (map) => UserPreviewsResponse.fromJson(map),
        );
        if (cachedData != null && cachedData.user_previews.isNotEmpty) {
          users.clear();
          users.addAll(cachedData.user_previews);
          nextUrl = cachedData.next_url;
        }
      } catch (e) {
        // 缓存读取失败，继续网络请求
      }
    }

    // 2. 加载网络数据
    try {
      Response response = await source();
      UserPreviewsResponse userPreviewsResponse =
          UserPreviewsResponse.fromJson(response.data);
      nextUrl = userPreviewsResponse.next_url;
      final results = userPreviewsResponse.user_previews;
      users.clear();
      users.addAll(results);
      _controller.finishRefresh(IndicatorResult.success);

      // 3. 更新缓存
      if (cacheKey != null && cacheKey!.isNotEmpty) {
        Future.microtask(() async {
          await DiskCache.writeModel(cacheKey!, response.data);
        });
      }

      return true;
    } catch (e) {
      _controller.finishRefresh(IndicatorResult.fail);
      return false;
    } finally {
      _lock = false;
    }
  }

  @action
  Future<bool> next() async {
    if (_lock) return false;
    _lock = true;
    try {
      if (nextUrl != null && nextUrl!.isNotEmpty) {
        try {
          Response response = await apiClient.getNext(nextUrl!);
          UserPreviewsResponse userPreviewsResponse =
              UserPreviewsResponse.fromJson(response.data);
          nextUrl = userPreviewsResponse.next_url;
          final results = userPreviewsResponse.user_previews;
          users.addAll(results);
          _controller.finishLoad(IndicatorResult.success);
          return true;
        } catch (e) {
          _controller.finishLoad(IndicatorResult.fail);
          return false;
        }
      } else {
        _controller.finishLoad(IndicatorResult.noMore);
        return true;
      }
    } finally {
      _lock = false;
    }
  }
}
