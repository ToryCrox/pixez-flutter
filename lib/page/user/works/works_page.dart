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

import 'dart:math';

import 'package:bot_toast/bot_toast.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/illust_card.dart';
import 'package:pixez/component/illust_card_grid.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/component/pixez_easy_refresh.dart';
import 'package:pixez/component/sort_group.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/lighting/lighting_store.dart';
import 'package:pixez/main.dart';
import 'package:pixez/network/api_client.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

class WorksPage extends StatefulWidget {
  final int id;
  final String portal;
  final LightingStore store;
  final String workType;
  final ValueChanged<String> onWorkTypeChange;

  const WorksPage(
      {Key? key,
      required this.id,
      required this.store,
      required this.portal,
      required this.workType,
      required this.onWorkTypeChange})
      : super(key: key);

  @override
  _WorksPageState createState() => _WorksPageState();
}

class _WorksPageState extends State<WorksPage> {
  late LightingStore _store;
  late EasyRefreshController _easyRefreshController;
  late String _workType;

  @override
  void initState() {
    _easyRefreshController = EasyRefreshController(
        controlFinishLoad: true, controlFinishRefresh: true);
    _store = widget.store;
    _store.easyRefreshController = _easyRefreshController;
    super.initState();
    _store.fetch();
    _workType = widget.workType;
  }

  @override
  void dispose() {
    _easyRefreshController.dispose();
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      return _buildContent(context);
    });
  }

  Widget _buildContent(context) {
    return _store.errorMessage != null && _store.iStores.isEmpty
        ? _buildErrorContent(context)
        : _buildWorks(context);
  }

  Widget _buildErrorContent(context) {
    return Container(
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            height: 50,
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child:
                Text(':(', style: Theme.of(context).textTheme.headlineMedium),
          ),
          TextButton(
              onPressed: () {
                _store.fetch(force: true);
              },
              child: Text(I18n.of(context).retry)),
          Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                (_store.errorMessage?.contains("400") == true
                    ? '${I18n.of(context).error_400_hint}\n ${_store.errorMessage}'
                    : '${_store.errorMessage}'),
              ))
        ],
      ),
    );
  }

  Widget _buildWorks(BuildContext context) {
    return SafeArea(
        top: false,
        bottom: false,
        child: Builder(
          builder: (BuildContext context) {
            return PixezEasyRefresh.builder(
                controller: _easyRefreshController,
                onLoad: () async {
                  await _store.fetchNext();
                },
                onRefresh: () async {
                  await _store.fetch(force: true);
                },
                header: PixezDefault.header(
                  context,
                  position: IndicatorPosition.locator,
                  safeArea: false,
                ),
                footer: PixezDefault.footer(
                  context,
                  position: IndicatorPosition.locator,
                ),
                childBuilder: (context, phy, scrollController) {
                  return Observer(builder: (_) {
                    // PixezEasyRefresh 会自动处理 NestedScrollView 的情况
                    // 如果在 NestedScrollView 中，scrollController 会是 null
                    return CustomScrollView(
                      physics: phy,
                      controller: scrollController,
                      key: PageStorageKey<String>(widget.portal),
                      slivers: [
                        SliverPinnedOverlapInjector(
                          handle:
                              NestedScrollView.sliverOverlapAbsorberHandleFor(
                                  context),
                        ),
                        const HeaderLocator.sliver(),
                        SliverPersistentHeader(
                          key: ValueKey('works_header'),
                          delegate: SliverChipDelegate(
                            Container(
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildSortChip(),
                                  const SizedBox(
                                    width: 8,
                                  ),
                                  _buildBatchDownloadButton(),
                                ],
                              ),
                            ),
                            height: 52,
                          ),
                          pinned: true,
                        ),
                        if (_store.refreshing && _store.iStores.isEmpty)
                          SliverToBoxAdapter(
                            child: Container(
                              height: 200,
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ),
                        userSetting.useWaterfallFlow
                            ? SliverWaterfallFlow(
                                gridDelegate: _buildGridDelegate(),
                                delegate:
                                    _buildSliverChildBuilderDelegate(context),
                              )
                            : SliverGrid(
                                gridDelegate: _buildSliverGridDelegate(),
                                delegate:
                                    _buildSliverGridChildBuilderDelegate(
                                        context),
                              ),
                        const FooterLocator.sliver(),
                      ],
                    );
                  });
                });
          },
        ));
  }

  SliverWaterfallFlowDelegate _buildGridDelegate() {
    var count = 2;
    if (userSetting.crossAdapt) {
      count = _buildSliderValue();
    } else {
      count = (MediaQuery.of(context).orientation == Orientation.portrait)
          ? userSetting.crossCount
          : userSetting.hCrossCount;
    }
    return SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
      crossAxisCount: count,
    );
  }

  SliverChildBuilderDelegate _buildSliverChildBuilderDelegate(
      BuildContext context) {
    _store.iStores
        .removeWhere((element) => element.illusts!.hateByUser(ai: false));
    return SliverChildBuilderDelegate((BuildContext context, int index) {
      return IllustCard(
        lightingStore: _store,
        store: _store.iStores[index],
        iStores: _store.iStores,
      );
    }, childCount: _store.iStores.length);
  }

  SliverChildBuilderDelegate _buildSliverGridChildBuilderDelegate(
      BuildContext context) {
    _store.iStores
        .removeWhere((element) => element.illusts!.hateByUser(ai: false));
    return SliverChildBuilderDelegate((BuildContext context, int index) {
      return IllustCardGrid(
        lightingStore: _store,
        store: _store.iStores[index],
        iStores: _store.iStores,
      );
    }, childCount: _store.iStores.length);
  }

  int _getCrossAxisCount() {
    if (userSetting.crossAdapt) {
      return _buildSliderValue();
    } else {
      return (MediaQuery.of(context).orientation == Orientation.portrait)
          ? userSetting.crossCount
          : userSetting.hCrossCount;
    }
  }

  SliverGridDelegate _buildSliverGridDelegate() {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: _getCrossAxisCount(),
      childAspectRatio: userSetting.gridAspectRatio,
    );
  }

  int _buildSliderValue() {
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

  Widget _buildSortChip() {
    return SortGroup(
      onChange: (index) {
        final type = index == 0 ? 'illust' : 'manga';
        setState(() {
          _workType = type;
        });
        widget.onWorkTypeChange(_workType);
        _store.source = ApiForceSource(
            futureGet: (bool e) => apiClient.getUserIllusts(widget.id, type));
        _store.fetch();
      },
      children: [
        I18n.of(context).illust,
        I18n.of(context).manga,
      ],
      initIndex: _workType == 'illust' ? 0 : 1,
    );
  }

  Widget _buildBatchDownloadButton() {
    return IconButton(
      icon: Icon(Icons.download, color: Theme.of(context).primaryColor),
      tooltip: '批量下载',
      onPressed: () {
        final availableIllusts = _store.iStores
            .where((store) => store.illusts != null && !store.illusts!.hateByUser(ai: false))
            .toList();
        _handleBatchDownload(availableIllusts);
      },
    );
  }

  Future<void> _handleBatchDownload(List illustStores) async {
    if (!downloadStore.isInitialized) {
      BotToast.showText(text: '下载功能未初始化');
      return;
    }

    if (illustStores.isEmpty) {
      BotToast.showText(text: '没有可下载的插画');
      return;
    }

    // 显示确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('批量下载'),
        content: Text('确定要下载 ${illustStores.length} 个插画吗？'),
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
      ),
    );

    if (confirm != true) {
      return;
    }

    int successCount = 0;
    int skipCount = 0;
    int errorCount = 0;

    for (final store in illustStores) {
      if (store.illusts == null) continue;
      
      final illusts = store.illusts!;
      
      // 跳过动图
      if (illusts.type == 'ugoira') {
        skipCount++;
        continue;
      }

      try {
        downloadStore.downloadIllust(illusts);
        successCount++;
      } catch (e) {
        errorCount++;
      }
    }

    // 显示结果
    final message = '已添加 $successCount 个下载任务';
    if (skipCount > 0) {
      BotToast.showText(text: '$message，跳过 $skipCount 个（动图）');
    } else if (errorCount > 0) {
      BotToast.showText(text: '$message，失败 $errorCount 个');
    } else {
      BotToast.showText(text: message);
    }
  }
}

class SliverPinnedOverlapInjector extends SingleChildRenderObjectWidget {
  const SliverPinnedOverlapInjector({
    required this.handle,
    Key? key,
  }) : super(key: key);

  final SliverOverlapAbsorberHandle handle;

  @override
  RenderSliverPinnedOverlapInjector createRenderObject(BuildContext context) {
    return RenderSliverPinnedOverlapInjector(
      handle: handle,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverPinnedOverlapInjector renderObject,
  ) {
    renderObject.handle = handle;
  }
}

class RenderSliverPinnedOverlapInjector extends RenderSliver {
  RenderSliverPinnedOverlapInjector({
    required SliverOverlapAbsorberHandle handle,
  }) : _handle = handle;

  double? _currentLayoutExtent;
  double? _currentMaxExtent;

  SliverOverlapAbsorberHandle get handle => _handle;
  SliverOverlapAbsorberHandle _handle;

  set handle(SliverOverlapAbsorberHandle value) {
    if (handle == value) return;
    if (attached) {
      handle.removeListener(markNeedsLayout);
    }
    _handle = value;
    if (attached) {
      handle.addListener(markNeedsLayout);
      if (handle.layoutExtent != _currentLayoutExtent ||
          handle.scrollExtent != _currentMaxExtent) markNeedsLayout();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    handle.addListener(markNeedsLayout);
    if (handle.layoutExtent != _currentLayoutExtent ||
        handle.scrollExtent != _currentMaxExtent) markNeedsLayout();
  }

  @override
  void detach() {
    handle.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void performLayout() {
    _currentLayoutExtent = handle.layoutExtent;

    final paintedExtent = min(
      _currentLayoutExtent!,
      constraints.remainingPaintExtent - constraints.overlap,
    );

    geometry = SliverGeometry(
      paintExtent: paintedExtent,
      maxPaintExtent: _currentLayoutExtent!,
      maxScrollObstructionExtent: _currentLayoutExtent!,
      paintOrigin: constraints.overlap,
      scrollExtent: _currentLayoutExtent!,
      layoutExtent: max(0, paintedExtent - constraints.scrollOffset),
      hasVisualOverflow: paintedExtent < _currentLayoutExtent!,
    );
  }
}

class SliverChipDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  double height = 45;

  SliverChipDelegate(this.child, {this.height = 45});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(SliverChipDelegate oldDelegate) {
    return height != oldDelegate.height;
  }
}
