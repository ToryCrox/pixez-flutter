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

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mobx/mobx.dart';
import 'package:pixez/custom/disk_cache.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/error_message.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/illust_series_detail.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/page/history/history_store.dart';
import 'package:pixez/store/download_store.dart';

part 'illust_store.g.dart';

class IllustStore = _IllustStoreBase with _$IllustStore;

abstract class _IllustStoreBase with Store {
  final int id;
  final ApiClient client = apiClient;
  @observable
  Illusts? illusts;
  @observable
  bool isBookmark = false;
  @observable
  String? errorMessage;
  @observable
  int state = 0;
  @observable
  bool captionFetchError = false;
  @observable
  bool captionFetching = false;
  @observable
  IllustSeriesDetailResponse? illustSeriesDetailResponse;

  /// 本地图片信息（包含路径和宽高）
  @observable
  ObservableMap<int, LocalImageInfo?> localImageInfos =
      ObservableMap<int, LocalImageInfo?>();

  StreamSubscription<IllustDownloadStatus>? _downloadStatusSubscription;

  void dispose() {
    _downloadStatusSubscription?.cancel();
  }

  /// 获取指定页面的本地图片信息（同步方法）
  LocalImageInfo? getLocalImageInfo(int part) {
    return localImageInfos[part];
  }

  _IllustStoreBase(this.id, this.illusts) {
    isBookmark = illusts?.isBookmarked ?? false;
    state = illusts?.isBookmarked ?? isBookmark ? 2 : 0;
    _initDownloadStatusListener();
  }

  void _initDownloadStatusListener() {
    _downloadStatusSubscription =
        downloadStore.illustDownloadStatusStream.listen((status) {
      if (status.illusts.illustId == id) {
        _onDownloadStatusChanged(status);
      }
    });
  }

  @action
  void _onDownloadStatusChanged(IllustDownloadStatus status) {
    if (status.status == DownloadTaskStatus.deleted) {
      // 删除时清空所有本地图片信息
      localImageInfos.clear();
    } else if (status.status == DownloadTaskStatus.completed) {
      // 下载完成时重新加载本地图片信息
      if (illusts != null) {
        _loadLocalImageInfos();
      }
    }
  }

  @action
  fetch() async {
    errorMessage = null;

    await _loadLocalImageInfos();
    // 1. 尝试从缓存加载
    final cacheKey = 'illust_detail_$id';
    final cachedData = await DiskCache.readModel(
      cacheKey,
      (map) => Illusts.fromJson(map),
    );

    if (cachedData != null) {
      // 立即加载本地图片信息
      illusts = cachedData;
      isBookmark = illusts!.isBookmarked;
      state = illusts?.isBookmarked ?? isBookmark ? 2 : 0;
    }

    // 2. 加载网络数据
    if (illusts == null ||
        illusts?.caption == null ||
        illusts?.caption.isEmpty == true) {
      final captionEmtpyCase = illusts != null && illusts!.caption.isEmpty;
      if (captionEmtpyCase) {
        captionFetching = true;
      }
      try {
        Response response = await client.getIllustDetail(id);
        final result = Illusts.fromJson(response.data['illust']);
        illusts = result;
        isBookmark = illusts!.isBookmarked;
        state = illusts?.isBookmarked ?? isBookmark ? 2 : 0;
        captionFetching = false;

        // 3. 更新缓存
        DiskCache.writeModel(cacheKey, illusts!.toJson());
      } on DioException catch (e) {
        captionFetching = false;
        if (captionEmtpyCase) {
          captionFetchError = true;
        } else {
          if (e.response != null) {
            if (e.response!.statusCode == HttpStatus.notFound) {
              errorMessage = '404 Not Found';
              return;
            }
            try {
              errorMessage =
                  ErrorMessage.fromJson(e.response!.data).error.message;
            } catch (e) {
              errorMessage = e.toString();
            }
          } else {
            errorMessage = e.toString();
          }
        }
      }
    }

    if (illusts != null) {
      try {
        History.insertIllust(illusts!);
      } catch (e) {}
    }
    if (illusts?.series != null && illustSeriesDetailResponse == null) {
      try {
        Response response = await client.illustSeriesIllust(id);
        final result = IllustSeriesDetailResponse.fromJson(response.data);
        illustSeriesDetailResponse = result;
      } catch (e) {
        print(e);
      }
    }
  }

  /// 批量加载所有页面的本地图片信息（路径和宽高）
  Future<void> _loadLocalImageInfos() async {
    if (!downloadStore.isInitialized) return;

    final t1 = DateTime.now();
    // 批量从数据库获取所有图片信息（已自动检测后缀名）
    final imageInfos = await downloadStore.getLocalImageInfos(id);
    localImageInfos.clear();
    localImageInfos.addAll(imageInfos);
    Log.d(
        'loadLocalImageInfos time1: ${DateTime.now().difference(t1).inMilliseconds}ms, illusts.id: $id, length: ${imageInfos.length}');
    _tryUpdateLocalImageInfo(imageInfos);
  }

  Future<void> _tryUpdateLocalImageInfo(
      Map<int, LocalImageInfo> imageInfos) async {
    final infos = <int, LocalImageInfo>{};
    for (final i in imageInfos.keys) {
      // 校验文件是否存在以及文件大小是否变化
      final info = imageInfos[i];
      if (info != null) {
        final file = File(info.path);
        if (await file.exists()) {
          final currentFileSize = await file.length();
          if ((info.width == null || info.height == null) ||info.fileSize != currentFileSize) {
            final updatedInfo = await downloadStore.updateAndGetLocalImageInfo(
                illusts!.id, i, info.path, currentFileSize);
            if (updatedInfo != null && updatedInfo != info) {
              infos[i] = updatedInfo;
            }
          }
        }
      }
    }
    if (infos.isNotEmpty) {
      localImageInfos.addAll(infos);
    }
  }

  @action
  Future<bool> followAfterStar() async {
    try {
      if (!illusts!.user.isFollowed!) {
        await apiClient.postFollowUser(illusts!.user.id, "public");
        return illusts!.user.isFollowed = true;
      }
    } catch (e) {}
    return false;
  }

  @action
  Future<bool> star(
      {String restrict = 'public',
      List<String>? tags,
      bool force = false}) async {
    state = 1;
    if (force || !illusts!.isBookmarked) {
      try {
        await apiClient.postLikeIllust(illusts!.id, restrict, tags);
        illusts!.isBookmarked = true;
        isBookmark = true;
        state = 2;
        return true;
      } catch (e) {}
    } else {
      try {
        await apiClient.postUnLikeIllust(illusts!.id);
        illusts!.isBookmarked = false;
        isBookmark = false;
        state = 0;
        return false;
      } catch (e) {}
    }
    state = illusts!.isBookmarked ? 2 : 0;
    return illusts!.isBookmarked;
  }
}
