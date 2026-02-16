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
import 'package:pixez/models/ugoira_metadata_response.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/store/download_store.dart';
import 'package:pixez/page/history/history_manager.dart';

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

  /// 动图元数据（如果有的话）
  @observable
  UgoiraMetadataResponse? ugoiraMetadata;

  /// 是否显示跳转到上次阅读位置的提示
  @observable
  bool showJumpHint = false;

  /// 上次阅读的页码
  @observable
  int lastReadPage = 0;

  /// 当前浏览的页数（用于多页插画）
  @observable
  int currentPage = 0;

  /// 总页数（用于多页插画）
  @observable
  int totalPages = 1;

  /// 本地图片信息（包含路径和宽高）
  @observable
  ObservableMap<int, LocalImageInfo?> localImageInfos =
      ObservableMap<int, LocalImageInfo?>();

  StreamSubscription<IllustDownloadStatus>? _downloadStatusSubscription;
  Timer? _jumpHintTimer;

  void dispose() {
    _jumpHintTimer?.cancel();
    if (_downloadStatusSubscription != null) {
      Log.d(() => {'illust_id': id, 'method': 'dispose'});
      _downloadStatusSubscription?.cancel();
      _downloadStatusSubscription = null;
    }
  }

  /// 获取指定页面的本地图片信息（同步方法）
  LocalImageInfo? getLocalImageInfo(int part) {
    return localImageInfos[part];
  }

  /// 预加载首帧图片信息（用于进入详情页前预加载，避免尺寸跳动）
  Future<void> preloadFirstImage({String? relativePath}) async {
    if (!downloadStore.isInitialized) return;
    if (localImageInfos.containsKey(0)) return;
    
    final firstImageInfo = await downloadStore.dbProvider.getLocalImageInfoByPart(id, 0, relativePath: relativePath);
    if (firstImageInfo != null) {
      localImageInfos[0] = firstImageInfo;
    }
  }

  /// 判断插画数据是否为被删除的无效数据
  /// 被删除的插画图片 URL 会变成 limit_unknown 占位图
  bool _isDeletedIllust(Illusts data) {
    return data.imageUrls.medium.contains('limit_unknown');
  }

  /// 用本地图片路径修复被删除的插画数据
  /// 将 limit_unknown 占位图 URL 替换为本地文件路径（file:// 协议）
  Illusts _fixIllustsWithLocalPaths(Illusts data) {
    if (localImageInfos.isEmpty) return data;

    // 获取第一张图片的本地路径用于 imageUrls
    final firstLocalPath = localImageInfos[0]?.path;
    if (firstLocalPath == null) return data;

    final localUrl = 'file://$firstLocalPath';

    // 修复 imageUrls
    final fixedImageUrls = ImageUrls(
      squareMedium: localUrl,
      medium: localUrl,
      large: localUrl,
    );

    // 对于动图，只修复 imageUrls，不修改 metaPages/metaSinglePage
    // 因为动图的 pageCount 是帧数，而 localImageInfos 只包含预览图
    if (data.isUgoira) {
      return data.copyWith(imageUrls: fixedImageUrls);
    }

    // 修复 metaSinglePage（单页插画）
    MetaSinglePage? fixedMetaSinglePage;
    final pageCount = localImageInfos.length;
    if (pageCount == 1) {
      fixedMetaSinglePage = MetaSinglePage(originalImageUrl: localUrl);
    }

    // 修复 metaPages（多页插画）
    List<MetaPages> fixedMetaPages = [];
    if (pageCount > 1) {
      for (int i = 0; i < pageCount; i++) {
        final localPath = localImageInfos[i]?.path;
        if (localPath != null) {
          final pageLocalUrl = 'file://$localPath';
          fixedMetaPages.add(MetaPages(
            imageUrls: MetaPagesImageUrls(
              squareMedium: pageLocalUrl,
              medium: pageLocalUrl,
              large: pageLocalUrl,
              original: pageLocalUrl,
            ),
          ));
        }
      }
    }

    return data.copyWith(
      pageCount: pageCount,
      imageUrls: fixedImageUrls,
      metaSinglePage: fixedMetaSinglePage ?? data.metaSinglePage,
      metaPages: fixedMetaPages.isNotEmpty ? fixedMetaPages : data.metaPages,
    );
  }

  _IllustStoreBase(this.id, this.illusts) {
    isBookmark = illusts?.isBookmarked ?? false;
    state = illusts?.isBookmarked ?? isBookmark ? 2 : 0;
  }

  /// 检查并修复被删除的插画数据
  @action
  Future<void> checkAndFixDeleted() async {
    if (illusts == null || !_isDeletedIllust(illusts!)) return;

    Log.d('检测到插画 ${id} 已被删除，尝试从本地恢复');

    // 1. 尝试从数据库加载已下载的信息
    if (downloadStore.isInitialized) {
      final downloadedIllust = await downloadStore.getDownloadedIllust(id);
      if (downloadedIllust != null) {
        try {
          final dbIllusts = downloadedIllust.toIllusts();
          illusts = dbIllusts;
        } catch (e) {
          Log.e('修复被删除插画失败: $e');
        }
      }
    }
  }

  void _initDownloadStatusListener() {
    Log.d(() => {'illust_id': id, 'method': 'initDownloadStatusListener'});
    if (_downloadStatusSubscription != null) {
      _downloadStatusSubscription?.cancel();
      _downloadStatusSubscription = null;
    }
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
  Future<void> fetch({bool force = false}) async {
    errorMessage = null;
    _initDownloadStatusListener();

    if (force) {
      currentPage = 0;
      showJumpHint = false;
      checkJumpHint();
    }

    // // 并行加载首帧图片信息和其余图片信息
    // if (downloadStore.isInitialized) {
    //   final t1 = DateTime.now();
    //   await Future.wait([
    //     // 快速加载第一张图片信息，避免首屏跳动
    //     downloadStore.dbProvider.getLocalImageInfoByPart(id, 0).then((info) {
    //       if (info != null) localImageInfos[0] = info;
    //       BotToast.showText(text: 'load first image: ${DateTime.now().difference(t1).inMilliseconds}ms');
    //     }),
    //     // 加载其余图片信息
    //     _loadLocalImageInfos(),
    //   ]);
    // }
    await _loadLocalImageInfos();

    // 1. 优先从数据库查询已下载的 illust（如果已下载）
    bool isDownloaded = false;
    Illusts? originalIllusts; // 保存从数据库加载的原始 illusts，用于对比
    if (downloadStore.isInitialized) {
      final downloadedIllust = await downloadStore.getDownloadedIllust(id);
      if (downloadedIllust != null) {
        Log.d('已下载的 illust: ${downloadedIllust.illustId}');
        try {
          final dbIllusts = downloadedIllust.toIllusts();
          // 校验数据库中的数据是否是被删除的无效数据
          // 但如果本地有图片文件，仍然可以使用数据库中的元数据（标题、作者等）
          final hasLocalImages = localImageInfos.isNotEmpty;
          if (_isDeletedIllust(dbIllusts) && !hasLocalImages) {
            Log.d('数据库中 illust:${id} 数据无效且本地无图片，跳过');
          } else {
            if (_isDeletedIllust(dbIllusts)) {
              // 用本地路径修复 illusts 的图片 URL
              illusts = _fixIllustsWithLocalPaths(dbIllusts);
              Log.d(() => 'illust:${id} 已被删除，但本地有图片，使用本地路径修复');
              Log.d(() => illusts!.toJson());
            } else {
              illusts = dbIllusts;
            }
            originalIllusts = dbIllusts; // 保存原始数据用于对比
            isBookmark = illusts!.isBookmarked;
            state = illusts?.isBookmarked ?? isBookmark ? 2 : 0;
            isDownloaded = true;
          }
        } catch (e) {
          Log.e('从数据库恢复 illust 失败: $e');
        }
      }
    }

    // 2. 如果数据库中没有，尝试从缓存加载
    final cacheKey = 'illust_detail_$id';
    if (illusts == null) {
      final cachedData = await DiskCache.readModel(
        cacheKey,
        (map) => Illusts.fromJson(map),
      );

      if (cachedData != null) {
        // 校验缓存中的数据是否是被删除的无效数据
        if (_isDeletedIllust(cachedData)) {
          Log.d('缓存中 illust:${id} 数据无效 (limit_unknown)，跳过');
        } else {
          illusts = cachedData;
          isBookmark = illusts!.isBookmarked;
          state = illusts?.isBookmarked ?? isBookmark ? 2 : 0;
        }
      }
    }

    // 3. 如果仍然没有数据或需要更新（caption 为空），从网络加载
    if (illusts == null ||
        force ||
        illusts?.caption == null ||
        illusts?.caption.isEmpty == true) {
      final captionEmtpyCase = illusts != null && illusts!.caption.isEmpty;
      if (captionEmtpyCase) {
        captionFetching = true;
      }
      try {
        Response response = await client.getIllustDetail(id);
        final result = Illusts.fromJson(response.data['illust']);

        // 校验插画是否已被删除
        // 被删除的插画图片 URL 会变成 limit_unknown 占位图
        if (_isDeletedIllust(result)) {
          Log.d('illust:${id} 已被删除 (图片为limit_unknown占位图)，使用缓存数据');
          captionFetching = false;
          // 只有当既无缓存数据又无本地图片时才设置错误信息
          if (illusts == null && localImageInfos.isEmpty) {
            errorMessage = '该作品已被删除';
          }
          return;
        }

        illusts = result;
        isBookmark = illusts!.isBookmarked;
        state = illusts?.isBookmarked ?? isBookmark ? 2 : 0;
        captionFetching = false;

        // 4. 更新缓存
        DiskCache.writeModel(cacheKey, illusts!.toJson());

        Log.d('从网络加载 illust:${id} 成功');
        // 5. 如果该 illust 已下载，对比数据是否有变化，有变化才更新数据库
        if (isDownloaded &&
            downloadStore.isInitialized &&
            originalIllusts != null) {
          if (illusts!.hasDataChanged(originalIllusts)) {
            Log.d('已下载的 illust:${id} 数据有变化，更新数据库');
            // Log.d(() => {
            //       'illusts': illusts!.toJson(),
            //       'originalIllusts': originalIllusts!.toJson(),
            //     });
            await downloadStore.updateDownloadedIllust(illusts!);
          } else {
            Log.d('已下载的 illust:${id} 数据未变化，无需更新');
          }
        }
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
      // 记录/更新历史记录（即使是在第 0 页进来的也要记录，以便在历史页显示）
      // 如果当前在第 0 页且我们有旧的阅读记录，则保留旧进度字段，只更新时间戳
      int pageToRecord = currentPage;
      if (currentPage == 0 && lastReadPage > 0) {
        pageToRecord = lastReadPage;
      }
      HistoryManager.instance.updateHistory(illusts!, lastPage: pageToRecord);
    }
    if (illusts?.series != null && illustSeriesDetailResponse == null) {
      try {
        Response response = await client.illustSeriesIllust(id);
        final result = IllustSeriesDetailResponse.fromJson(response.data);
        illustSeriesDetailResponse = result;
      } catch (e) {
        Log.e(e);
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
    int updateCount = 0;
    final infos = <int, LocalImageInfo>{};
    for (final i in imageInfos.keys) {
      // 校验文件是否存在以及文件大小是否变化
      final info = imageInfos[i];
      if (info != null) {
        final file = File(info.path);
        if (await file.exists()) {
          final currentFileSize = await file.length();
          if ((info.width == null || info.height == null) ||
              info.fileSize != currentFileSize) {
            final updatedInfo = await downloadStore.updateAndGetLocalImageInfo(
                id, i, info.path, currentFileSize);
            if (updatedInfo != null && updatedInfo != info) {
              updateCount++;
              Log.d(() => 'updateLocalImageInfo: $updatedInfo');
              infos[i] = updatedInfo;
            }
          }
        }
      }
      if (infos.length >= 10) {
        localImageInfos.addAll(infos);
        infos.clear();
      }
    }
    if (infos.isNotEmpty) {
      localImageInfos.addAll(infos);
    }
    if (updateCount > 0) {
      if (illusts != null) {
        // 更新插画自身的物化统计字段
        await downloadStore.dbProvider.batchRecalculateIllustStats([id]);
        // 更新作者表的统计信息
        await downloadStore.dbProvider.updateAuthorStats(illusts!.user.id);
      }
    }
  }

  @action
  Future<bool> followAfterStar() async {
    try {
      if (!illusts!.user.isFollowed!) {
        await apiClient.postFollowUser(illusts!.user.id, "public");
        return illusts!.user.isFollowed = true;
      }
    } catch (e) {
      Log.e('Failed to follow user', error: e);
    }
    return false;
  }

  @action
  Future<bool> star(
      {String restrict = 'public',
      List<String>? tags,
      int? bookmark,
      bool force = false}) async {
    state = 1;
    if (force || !illusts!.isBookmarked) {
      try {
        await apiClient.postLikeIllust(illusts!.id, restrict, tags);
        illusts!.isBookmarked = true;
        isBookmark = true;
        state = 2;
        // 同步本地数据库收藏状态
        if (downloadStore.isInitialized) {
          await downloadStore.updateIllustBookmark(illusts!.id, bookmark ?? 1);
        }
        return true;
      } catch (e) {
        Log.e('Failed to star', error: e);
      }
    } else {
      try {
        await apiClient.postUnLikeIllust(illusts!.id);
        illusts!.isBookmarked = false;
        isBookmark = false;
        state = 0;
        // 同步本地数据库收藏状态
        if (downloadStore.isInitialized) {
          await downloadStore.updateIllustBookmark(illusts!.id, 0);
        }
        return false;
      } catch (e) {
        Log.e('Failed to unstar', error: e);
      }
    }
    state = illusts!.isBookmarked ? 2 : 0;
    return illusts!.isBookmarked;
  }

  /// 更新当前页数
  @action
  void updateCurrentPage(int page) {
    if (page != currentPage && page >= 0 && page < totalPages) {
      currentPage = page;
      // 实时更新历史进度
      if (illusts != null) {
        HistoryManager.instance.updateHistory(illusts!, lastPage: currentPage);
      }
    }
  }

  /// 更新总页数
  @action
  void updateTotalPages(int pages) {
    if (pages != totalPages && pages > 0) {
      totalPages = pages;
      // 如果当前页超出范围，重置为0
      if (currentPage >= pages) {
        currentPage = 0;
      }
    }
  }

  /// 更新动图元数据
  @action
  void updateUgoiraMetadata(UgoiraMetadataResponse? metadata) {
    ugoiraMetadata = metadata;
  }

  /// 隐藏跳转提示
  @action
  void hideJumpHint() {
    showJumpHint = false;
    _jumpHintTimer?.cancel();
    _jumpHintTimer = null;
  }

  /// 检查并显示跳转提示
  @action
  void checkJumpHint() {
    // 如果已经显示了提示，或者已经在阅读中（不是第0页），则不检查
    if (showJumpHint || currentPage != 0) return;

    final history = HistoryManager.instance.getHistory(id);
    if (history != null && history.lastPage > 0) {
      lastReadPage = history.lastPage;
      showJumpHint = true;
      // 5秒后自动隐藏提示
      _jumpHintTimer?.cancel();
      _jumpHintTimer = Timer(const Duration(seconds: 10), () {
        hideJumpHint();
      });
    }
  }
}
