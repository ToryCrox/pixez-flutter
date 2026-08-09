import 'package:easy_refresh/easy_refresh.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pixez/custom/disk_cache.dart';
import 'package:pixez/models/watchlist_manga_model.dart';
import 'package:pixez/network/api_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'watchlist_notifier.freezed.dart';
part 'watchlist_notifier.g.dart';

@freezed
abstract class WatchlistState with _$WatchlistState {
  const factory WatchlistState({
    @Default([]) List<MangaSeriesModel> mangaSeries,
    WatchlistMangaModel? model,
    String? errorMessage,
    @Default(false) bool isLoading,
  }) = _WatchlistState;
}

const _cacheKey = 'watchlist_manga';

@riverpod
class WatchlistStore extends _$WatchlistStore {
  EasyRefreshController controller = EasyRefreshController(
    controlFinishLoad: true,
    controlFinishRefresh: true,
  );
  @override
  WatchlistState build() {
    return const WatchlistState();
  }

  Future<void> fetch() async {
    state = state.copyWith(isLoading: true);

    // 1. 尝试从缓存加载
    if (state.mangaSeries.isEmpty) {
      try {
        final cachedData = await DiskCache.readModel(
          _cacheKey,
          (map) => WatchlistMangaModel.fromJson(map),
        );
        if (cachedData != null && cachedData.series.isNotEmpty) {
          state = state.copyWith(
            mangaSeries: cachedData.series,
            model: cachedData,
          );
        }
      } catch (e) {
        // 缓存读取失败，继续网络请求
      }
    }

    // 2. 加载网络数据
    try {
      final response = await apiClient.watchListManga();
      final data = WatchlistMangaModel.fromJson(response.data);
      final nextUrl = data.nextUrl;
      controller.finishRefresh(
        nextUrl != null ? IndicatorResult.success : IndicatorResult.noMore,
      );
      state = state.copyWith(
        mangaSeries: data.series,
        model: data,
        isLoading: false,
      );

      // 3. 更新缓存
      Future.microtask(() async {
        await DiskCache.writeModel(_cacheKey, response.data);
      });
    } catch (e) {
      controller.finishRefresh(IndicatorResult.fail);
      state = state.copyWith(errorMessage: e.toString(), isLoading: false);
    }
  }

  // load more
  Future<void> loadMore() async {
    try {
      var nextUrl = state.model?.nextUrl;
      if (nextUrl == null) {
        controller.finishLoad(IndicatorResult.noMore);
        return;
      }
      final response = await apiClient.getNext(nextUrl);
      final data = WatchlistMangaModel.fromJson(response.data);
      state = state.copyWith(
        model: data,
        mangaSeries: [...state.mangaSeries, ...data.series],
        isLoading: false,
      );
      nextUrl = data.nextUrl;
      controller.finishLoad(
        nextUrl != null ? IndicatorResult.success : IndicatorResult.noMore,
      );
    } catch (e) {
      controller.finishLoad(IndicatorResult.fail);
      state = state.copyWith(errorMessage: e.toString(), isLoading: false);
    }
  }
}
