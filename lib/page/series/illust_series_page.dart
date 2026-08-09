import 'dart:math';

import 'package:bot_toast/bot_toast.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pixez/component/illust_card.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/component/pixiv_image.dart';

import 'package:pixez/er/leader.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/series/illust_series_notifier.dart';
import 'package:pixez/page/user/users_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class IllustSeriesPage extends StatefulHookConsumerWidget {
  final int id;

  const IllustSeriesPage({super.key, required this.id});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _IllustSeriesPageState();
}

class _IllustSeriesPageState extends ConsumerState<IllustSeriesPage> {
  late int id = widget.id;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(
      illustSeriesStoreProvider(widget.id).select((e) => e.model),
    );
    final isLoading = ref.watch(
      illustSeriesStoreProvider(widget.id).select((e) => e.isLoading),
    );
    final coverImageUrl = model?.illustSeriesDetail?.coverImageUrls?.medium;
    final caption =
        kDebugMode
            ? "wfaefafawefawfewaefaweewafawefaweffwafewfwafwafwafwfe"
            : (model?.illustSeriesDetail?.caption);
    final illusts = ref.watch(
      illustSeriesStoreProvider(widget.id).select((e) => e.illusts),
    );
    final watchListAdded = ref.watch(
      illustSeriesStoreProvider(widget.id).select((e) => e.watchlistAdded),
    );
    final errorMessage = ref.watch(
      illustSeriesStoreProvider(widget.id).select((e) => e.errorMessage),
    );
    final profileUrl =
        model?.illustSeriesDetail?.user?.profileImageUrls?.medium;
    final controller =
        ref.read(illustSeriesStoreProvider(widget.id).notifier).controller;

    useEffect(() {
      Future.delayed(Duration.zero, () {
        ref.read(illustSeriesStoreProvider(widget.id).notifier).fetch();
      });
      return null;
    }, []);
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (illusts.isNotEmpty)
            IconButton(
              onPressed: () {
                _downloadAllIllusts(context, illusts);
              },
              icon: Icon(Icons.download),
              tooltip: '一键下载',
            ),
          Builder(
            builder: (context) {
              return IconButton(
                onPressed: () {
                  final userId = model?.illustSeriesDetail?.user?.id;
                  final seriesId = model?.illustSeriesDetail?.id;
                  if (userId != null && seriesId != null) {
                    final box = context.findRenderObject() as RenderBox?;
                    final pos =
                        box != null
                            ? box.localToGlobal(Offset.zero) & box.size
                            : null;
                    final link =
                        "https://www.pixiv.net/user/$userId/series/$seriesId";
                    Share.share(link, sharePositionOrigin: pos);
                  }
                },
                icon: Icon(Icons.share),
              );
            },
          ),
        ],
      ),
      body: Container(
        child:
            isLoading
                ? Center(child: CircularProgressIndicator())
                : errorMessage != null
                ? _buildErrorContent(context, errorMessage)
                : EasyRefresh.builder(
                  controller: controller,
                  header: PixezDefault.header(context),
                  footer: PixezDefault.footer(context),
                  onRefresh: () async {
                    await ref
                        .read(illustSeriesStoreProvider(widget.id).notifier)
                        .fetch();
                  },
                  onLoad: () async {
                    await ref
                        .read(illustSeriesStoreProvider(widget.id).notifier)
                        .loadMore();
                  },
                  childBuilder: (context, physics) {
                    return CustomScrollView(
                      physics: physics,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              Container(
                                height: 140,
                                child:
                                    coverImageUrl == null
                                        ? Container()
                                        : PixivImage(
                                          coverImageUrl,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                        ),
                              ),
                              Container(
                                alignment: Alignment.center,
                                margin: EdgeInsets.only(left: 16, right: 16),
                                child: Text(
                                  model?.illustSeriesDetail?.title ?? "",
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              SizedBox(height: 4),
                              GestureDetector(
                                onTap: () {
                                  Leader.push(
                                    context,
                                    UsersPage(
                                      id:
                                          model?.illustSeriesDetail?.user?.id ??
                                          0,
                                    ),
                                  );
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (profileUrl != null) ...[
                                      ClipOval(
                                        child: PixivImage(
                                          profileUrl,
                                          width: 24,
                                          height: 24,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                    ],
                                    Text(
                                      model?.illustSeriesDetail?.user?.name ??
                                          "",
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium!
                                          .copyWith(fontSize: 16),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 12),
                              GestureDetector(
                                onTap: () {
                                  if (watchListAdded) {
                                    ref
                                        .read(
                                          illustSeriesStoreProvider(
                                            widget.id,
                                          ).notifier,
                                        )
                                        .removeWatchlist();
                                  } else {
                                    ref
                                        .read(
                                          illustSeriesStoreProvider(
                                            widget.id,
                                          ).notifier,
                                        )
                                        .addWatchlist();
                                  }
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  decoration:
                                      watchListAdded
                                          ? BoxDecoration(
                                            border: Border.all(
                                              color: Colors.black,
                                              width: 1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              21,
                                            ),
                                          )
                                          : BoxDecoration(
                                            color: Colors.blue,
                                            borderRadius: BorderRadius.circular(
                                              21,
                                            ),
                                          ),
                                  padding: EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    watchListAdded
                                        ? I18n.of(context).watchlist_added
                                        : I18n.of(context).add_to_watchlist,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge?.copyWith(
                                      color:
                                          watchListAdded
                                              ? Colors.black
                                              : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 12),
                              if (caption != null)
                                Container(
                                  alignment: Alignment.center,
                                  margin: EdgeInsets.only(left: 16, right: 16),
                                  child: Text(
                                    caption,
                                    style:
                                        Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ),
                              SizedBox(height: 12),
                            ],
                          ),
                        ),
                        if (illusts.isNotEmpty)
                          SliverPadding(
                            padding: EdgeInsets.only(left: 16, right: 16),
                            sliver:
                                userSetting.useWaterfallFlow
                                    ? SliverWaterfallFlow(
                                      gridDelegate: _buildGridDelegate(context),
                                      delegate: SliverChildBuilderDelegate((
                                        BuildContext context,
                                        int index,
                                      ) {
                                        return _buildItem(illusts[index], true);
                                      }, childCount: illusts.length),
                                    )
                                    : SliverGrid(
                                      gridDelegate: _buildSliverGridDelegate(
                                        context,
                                      ),
                                      delegate: SliverChildBuilderDelegate((
                                        BuildContext context,
                                        int index,
                                      ) {
                                        return _buildItem(
                                          illusts[index],
                                          false,
                                        );
                                      }, childCount: illusts.length),
                                    ),
                          ),
                      ],
                    );
                  },
                ),
      ),
    );
  }

  Widget _buildItem(IllustStore illust, bool isWaterfallFlow) {
    return IllustCard(
      store: illust,
      lightingStore: null,
      layoutMode:
          isWaterfallFlow
              ? IllustCardLayoutMode.waterfall
              : IllustCardLayoutMode.grid,
      showSeriesLink: false,
    );
  }

  SliverWaterfallFlowDelegate _buildGridDelegate(BuildContext context) {
    var count = 2;
    if (userSetting.crossAdapt) {
      count = _buildSliderValue(context);
    } else {
      count =
          (MediaQuery.of(context).orientation == Orientation.portrait)
              ? userSetting.crossCount
              : userSetting.hCrossCount;
    }
    return SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
      crossAxisCount: count,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
    );
  }

  int _buildSliderValue(BuildContext context) {
    final currentValue =
        (MediaQuery.of(context).orientation == Orientation.portrait
                ? userSetting.crossAdapterWidth
                : userSetting.hCrossAdapterWidth)
            .toDouble();
    var nowAdaptWidth = max(currentValue, 50.0);
    nowAdaptWidth = min(nowAdaptWidth, 2160.0);
    final screenWidth = MediaQuery.of(context).size.width;
    final result = max(screenWidth / nowAdaptWidth, 1.0).toInt();
    return result;
  }

  int _getCrossAxisCount(BuildContext context) {
    if (userSetting.crossAdapt) {
      return _buildSliderValue(context);
    } else {
      return (MediaQuery.of(context).orientation == Orientation.portrait)
          ? userSetting.crossCount
          : userSetting.hCrossCount;
    }
  }

  SliverGridDelegate _buildSliverGridDelegate(BuildContext context) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: _getCrossAxisCount(context),
      childAspectRatio: userSetting.gridAspectRatio,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
    );
  }

  Widget _buildErrorContent(BuildContext context, String errorMessage) {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              ':(',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          Text(errorMessage, maxLines: 5),
          ElevatedButton(
            onPressed: () {
              ref.read(illustSeriesStoreProvider(widget.id).notifier).fetch();
            },
            child: Text(I18n.of(context).refresh),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAllIllusts(
    BuildContext context,
    List<IllustStore> illusts,
  ) async {
    if (illusts.isEmpty) {
      BotToast.showText(text: '没有可下载的插画');
      return;
    }

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('一键下载'),
          content: Text('确定要下载系列中的所有 ${illusts.length} 个插画吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(I18n.of(context).cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(I18n.of(context).ok),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    int successCount = 0;
    int failCount = 0;

    for (final illustStore in illusts) {
      try {
        if (illustStore.illusts != null) {
          await downloadStore.downloadIllust(illustStore.illusts!);
          successCount++;
        }
      } catch (e) {
        failCount++;
      }
    }

    if (successCount > 0) {
      BotToast.showText(
        text:
            '已添加 $successCount 个下载任务${failCount > 0 ? '，失败 $failCount 个' : ''}',
      );
    } else if (failCount > 0) {
      BotToast.showText(text: '下载失败');
    }
  }
}
