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

import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/scheduler.dart';
import 'package:pixez/component/pixez_easy_refresh.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:pixez/component/ban_page.dart';
import 'package:pixez/component/common_back_area.dart';
import 'package:pixez/component/illust_recommend_grid.dart';
import 'package:pixez/component/null_hero.dart';
import 'package:pixez/component/painter_avatar.dart';
import 'package:pixez/component/pixez_default_header.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/component/star_icon.dart';
import 'package:pixez/constants.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/ban_illust_id.dart';
import 'package:pixez/models/ban_tag.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/picture/illust_about_store.dart';
import 'package:pixez/page/picture/illust_detail_content.dart';
import 'package:pixez/page/picture/illust_row_page.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/picture_list_page.dart';
import 'package:pixez/page/picture/tag_for_illust_page.dart';
import 'package:pixez/page/picture/ugoira_loader.dart';
import 'package:pixez/page/picture/user_follow_button.dart';
import 'package:pixez/page/report/report_items_page.dart';
import 'package:pixez/page/search/result_page.dart';
import 'package:pixez/page/user/user_store.dart';
import 'package:pixez/page/user/users_page.dart';
import 'package:pixez/page/zoom/photo_zoom_page.dart';
import 'package:pixez/supportor_plugin.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pixez/component/local_or_cached_image.dart';
import 'package:pixez/custom/image_cache_manager.dart';
import 'package:url_launcher/url_launcher_string.dart';

class IllustLightingPage extends StatefulWidget {
  final int id;
  final String? heroString;
  final IllustStore? store;
  final GestureDragEndCallback? onHorizontalDragEnd;

  const IllustLightingPage({
    Key? key,
    required this.id,
    this.heroString,
    this.store,
    this.onHorizontalDragEnd,
  }) : super(key: key);

  @override
  State<IllustLightingPage> createState() => _IllustLightingPageState();
}

class _IllustLightingPageState extends State<IllustLightingPage> {
  @override
  void initState() {
    super.initState();
    // 进入详情页时增加缓存大小
    imageCacheManager.enterDetailPage();
  }

  @override
  void dispose() {
    widget.store?.dispose();
    // 退出详情页时减少缓存大小
    imageCacheManager.exitDetailPage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (userSetting.padMode) {
      case 0:
        MediaQueryData mediaQuery = MediaQuery.of(context);
        final ori = mediaQuery.size.width > mediaQuery.size.height;
        if (ori)
          return _buildRow();
        else
          return _buildVertical();
      case 1:
        return _buildVertical();
      case 2:
        return _buildRow();
      default:
        return Container();
    }
  }

  _buildVertical() {
    return IllustVerticalPage(
      id: widget.id,
      store: widget.store,
      heroString: widget.heroString,
      onHorizontalDragEnd: widget.onHorizontalDragEnd,
    );
  }

  _buildRow() {
    return IllustRowPage(
      id: widget.id,
      store: widget.store,
      heroString: widget.heroString,
      onHorizontalDragEnd: widget.onHorizontalDragEnd,
    );
  }
}

class IllustVerticalPage extends StatefulWidget {
  final int id;
  final String? heroString;
  final IllustStore? store;
  final GestureDragEndCallback? onHorizontalDragEnd;

  const IllustVerticalPage({
    Key? key,
    required this.id,
    this.heroString,
    this.store,
    this.onHorizontalDragEnd,
  }) : super(key: key);

  @override
  _IllustVerticalPageState createState() => _IllustVerticalPageState();
}

class _IllustVerticalPageState extends State<IllustVerticalPage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  UserStore? userStore;
  late IllustStore _illustStore;
  late IllustAboutStore _aboutStore;
  late ScrollController _photoScrollController;
  late EasyRefreshController _refreshController;
  late ListObserverController _observerController;
  bool tempView = false;
  Ticker? _autoScrollTicker;
  bool _isAutoScrolling = false;

  @override
  void initState() {
    _focusNode = FocusNode();
    _refreshController = EasyRefreshController(
      controlFinishLoad: true,
      controlFinishRefresh: true,
    );
    _photoScrollController = ScrollController();
    _illustStore = widget.store ?? IllustStore(widget.id, null);
    _observerController = ListObserverController(
      controller: _photoScrollController,
    );
    _illustStore.fetch(force: true);
    _aboutStore = IllustAboutStore(widget.id, _refreshController);
    super.initState();
    supportTranslateCheck();
  }

  @override
  void didUpdateWidget(covariant IllustVerticalPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _illustStore = widget.store ?? IllustStore(widget.id, null);
      _illustStore.fetch();
      _aboutStore = IllustAboutStore(widget.id, _refreshController);
      Log.d(() => "state change");
    }
  }

  void _loadAbout() {
    if (mounted &&
        _photoScrollController.hasClients &&
        _aboutStore.illusts.isEmpty &&
        !_aboutStore.fetching) {
      _aboutStore.next();
    }
  }

  @override
  void dispose() {
    _illustStore.dispose();
    _photoScrollController.dispose();
    _autoScrollTicker?.dispose();
    _refreshController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildAppbar() {
    return Column(
      children: [
        Container(height: MediaQuery.of(context).padding.top),
        Container(
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CommonBackArea(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.expand_less),
                    onPressed: () {
                      double p =
                          _photoScrollController.position.maxScrollExtent -
                          (_aboutStore.illusts.length / 3.0) *
                              (MediaQuery.of(context).size.width / 3.0);
                      if (p < 0) p = 0;
                      _photoScrollController.position.jumpTo(p);
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert),
                    onPressed: () {
                      buildShowModalBottomSheet(context, _illustStore.illusts!);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Download 按钮（上方）
        if (_illustStore.illusts != null)
          Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: IllustDownloadButton(
              illusts: _illustStore.illusts!,
              asFloatingActionButton: true,
              onStarAfterSave: () async {
                if (_illustStore.state == 0) {
                  return _illustStore.star(
                    restrict:
                        userSetting.defaultPrivateLike ? "private" : "public",
                  );
                }
                return false;
              },
            ),
          ),
        // Star 按钮（下方）
        GestureDetector(
          onLongPress: () {
            _showBookMarkTag();
          },
          onHorizontalDragEnd: (DragEndDetails detail) {
            if (widget.onHorizontalDragEnd != null) {
              widget.onHorizontalDragEnd!(detail);
            }
          },
          child: FloatingActionButton(
            heroTag: widget.id,
            onPressed: () async {
              if (userSetting.saveAfterStar && (_illustStore.state == 0)) {
                downloadStore.downloadIllust(_illustStore.illusts!);
              }
              _illustStore.star(
                restrict: userSetting.defaultPrivateLike ? "private" : "public",
              );
              if (userSetting.followAfterStar) {
                bool success = await _illustStore.followAfterStar();
                if (success) {
                  userStore?.isFollow = true;
                  BotToast.showText(
                    text:
                        "${_illustStore.illusts!.user.name} ${I18n.of(context).followed}",
                  );
                }
              }
            },
            child: Observer(
              builder: (_) {
                return StarIcon(state: _illustStore.state);
              },
            ),
          ),
        ),
      ],
    );
  }

  late FocusNode _focusNode;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildBody(context);
  }

  Widget _buildBody(BuildContext context) {
    return Container(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
        },
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          floatingActionButton: Observer(
            builder: (context) {
              return Visibility(
                visible: _illustStore.errorMessage == null,
                child: _buildFloatingActionButtons(),
              );
            },
          ),
          body: Observer(
            builder: (_) {
              final banWidget = banLogic(context);
              if (banWidget != null) {
                return banWidget;
              }
              final data = _illustStore.illusts;
              return Container(
                child: Stack(
                  children: [
                    _buildContent(context, data),
                    _buildAppbar(),
                    Positioned(
                      bottom: 60,
                      left: 10,
                      child: Observer(builder: (_) => _buildJumpHint()),
                    ),
                    if (data != null && data.pageCount > 1)
                      Positioned(
                        bottom: 20,
                        left: 10,
                        child: Observer(builder: (_) => _buildPageIndicator()),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget? banLogic(BuildContext context) {
    if (tempView) return null;
    for (var i in muteStore.banillusts) {
      if (i.illustId == widget.id.toString()) {
        return BanPage(
          name: "${I18n.of(context).illust}\n${i.name}\n",
          onPressed: () {
            setState(() {
              tempView = true;
            });
          },
        );
      }
    }
    if (_illustStore.illusts != null) {
      for (var j in muteStore.banUserIds) {
        if (j.userId == _illustStore.illusts!.user.id.toString()) {
          return BanPage(
            name: "${I18n.of(context).painter}\n${j.name}\n",
            onPressed: () {
              setState(() {
                tempView = true;
              });
            },
          );
        }
      }
      for (var t in muteStore.banTags) {
        final tags = _illustStore.illusts!.tags;
        for (var t1 in tags) {
          if (t.isRegexMatch(t1.name)) {
            return BanPage(
              name: "${I18n.of(context).tag}\n${t.name}\n",
              onPressed: () {
                setState(() {
                  tempView = true;
                });
              },
            );
          }
        }
        final allText = tags.map((e) => '#${e.name}').join('');
        if (t.isRegexMatch(allText)) {
          return BanPage(
            name: "${I18n.of(context).tag}\n${t.name}\n",
            onPressed: () {
              setState(() {
                tempView = true;
              });
            },
          );
        }
      }
    }
    return null;
  }

  bool supportTranslate = false;

  Future<void> supportTranslateCheck() async {
    if (!Platform.isAndroid) return;
    bool results = await SupportorPlugin.processText();
    if (mounted) {
      setState(() {
        supportTranslate = results;
      });
    }
  }

  Widget colorText(String text, BuildContext context) {
    return SelectionArea(
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.secondary,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Illusts? data) {
    if (_illustStore.errorMessage != null) return _buildErrorContent(context);
    if (data == null)
      return Container(
        child: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      );
    if (userStore == null) userStore = UserStore(data.user.id, null, data.user);
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        onPointerDown: (_) {
          if (_isAutoScrolling) {
            _autoScrollTicker?.stop();
          }
        },
        onPointerUp: (_) {
          if (_isAutoScrolling &&
              _autoScrollTicker != null &&
              !_autoScrollTicker!.isActive) {
            _resumeAutoScrollAfterInertia();
          }
          _checkFlingGesture();
        },
        onPointerCancel: (_) {
          if (_isAutoScrolling &&
              _autoScrollTicker != null &&
              !_autoScrollTicker!.isActive) {
            _resumeAutoScrollAfterInertia();
          }
          _checkFlingGesture();
        },
        child: PixezEasyRefresh.builder(
          controller: _refreshController,
          header: PixezDefault.header(context),
          footer: PixezDefault.footer(context),
          scrollController: _photoScrollController,
          onLoad: () async {
            await _aboutStore.next();
          },
          childBuilder: (context, physics, scrollController) {
            return ListViewObserver(
              controller: _observerController,
              onObserve: _onObserve,
              child: CustomScrollView(
                physics: physics,
                controller: scrollController,
                slivers: [
                  if (userSetting.isBangs || ((data.width / data.height) > 5))
                    SliverToBoxAdapter(
                      child: Container(
                        height: MediaQuery.of(context).padding.top,
                      ),
                    ),
                  ..._buildPhotoList(data),
                  SliverToBoxAdapter(
                    child: IllustDetailContent(
                      illusts: data,
                      userStore: userStore,
                      illustStore: _illustStore,
                      loadAbout: () {
                        _loadAbout();
                      },
                    ),
                  ),
                  IllustRecommendGrid(
                    illusts: _aboutStore.illusts,
                    currentIllustStore: _illustStore,
                    showLongPressConfirm: userSetting.longPressSaveConfirm,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildPhotoList(Illusts data) {
    final height =
        ((data.height.toDouble() / data.width) *
            MediaQuery.of(context).size.width);

    return [
      if (data.type == "ugoira")
        SliverToBoxAdapter(
          child: NullHero(
            tag: widget.heroString,
            child: UgoiraLoader(
              id: widget.id,
              illusts: data,
              illustStore: _illustStore,
            ),
          ),
        ),
      if (data.type != "ugoira")
        data.pageCount == 1
            ? SliverList(
              delegate: SliverChildBuilderDelegate((
                BuildContext context,
                int index,
              ) {
                String url = data.illustDetailUrl;
                if (data.type == "manga") {
                  url = data.managaDetailUrl;
                }

                // 计算建议的质量标识，以匹配 IllustCard 的缓存键
                String quality = userSetting.previewQuality;

                Widget placeWidget = Container(height: height);
                return InkWell(
                  onLongPress: () {
                    _pressSave(data, 0);
                  },
                  onTap: () {
                    Leader.push(
                      context,
                      PhotoZoomPage(
                        index: 0,
                        illusts: data,
                        illustStore: _illustStore,
                      ),
                    );
                  },
                  child: NullHero(
                    tag: widget.heroString,
                    child: PixivImage(
                      url,
                      localImageInfo: _illustStore.getLocalImageInfo(0),
                      fade: false,
                      width: MediaQuery.of(context).size.width,
                      placeWidget:
                          (url != data.previewUrl)
                              ? PixivImage(
                                data.previewUrl,
                                width: MediaQuery.of(context).size.width,
                                placeWidget: placeWidget,
                                fade: false,
                                httpHeaders: {
                                  'cover': '${data.id}',
                                  'quality': quality,
                                },
                              )
                              : placeWidget,
                    ),
                  ),
                );
              }, childCount: 1),
            )
            : SliverList(
              delegate: SliverChildBuilderDelegate((
                BuildContext context,
                int index,
              ) {
                return InkWell(
                  onLongPress: () {
                    _pressSave(data, index);
                  },
                  onTap: () {
                    Leader.push(
                      context,
                      PhotoZoomPage(
                        index: index,
                        illusts: data,
                        illustStore: _illustStore,
                      ),
                    );
                  },
                  child: Observer(
                    builder: (context) {
                      return _buildIllustsItem(index, data, height);
                    },
                  ),
                );
              }, childCount: data.metaPages.length),
            ),
    ];
  }

  void _onObserve(ListViewObserveModel observeModel) {
    final illusts = _illustStore.illusts;
    if (illusts == null || illusts.pageCount <= 1) {
      if (_illustStore.currentPage != 0 || _illustStore.totalPages != 1) {
        _illustStore.updateTotalPages(1);
        _illustStore.updateCurrentPage(0);
      }
      return;
    }

    if (_illustStore.totalPages != illusts.pageCount) {
      _illustStore.updateTotalPages(illusts.pageCount);
    }

    final firstVisibleIndex = observeModel.firstChild?.index;

    int clampedIndex;
    if (firstVisibleIndex == null) {
      if (_photoScrollController.hasClients) {
        final position = _photoScrollController.position;
        final currentScroll = position.pixels;
        final maxScroll = position.maxScrollExtent;
        if (maxScroll > 0 && currentScroll / maxScroll > 0.9) {
          clampedIndex = illusts.pageCount - 1;
        } else {
          return;
        }
      } else {
        return;
      }
    } else {
      clampedIndex = firstVisibleIndex.clamp(0, illusts.pageCount - 1);
    }

    if (clampedIndex != _illustStore.currentPage) {
      _illustStore.updateCurrentPage(clampedIndex);
    }

    if (clampedIndex >= illusts.pageCount - 1 && _isAutoScrolling) {
      _stopAutoScroll();
    }
  }

  void _stopAutoScroll() {
    _autoScrollTicker?.stop();
    if (_isAutoScrolling) {
      setState(() {
        _isAutoScrolling = false;
      });
    }
  }

  void _startAutoScroll() {
    if (_autoScrollTicker == null) {
      _autoScrollTicker = createTicker((elapsed) {
        if (!_photoScrollController.hasClients) return;
        if (_illustStore.currentPage >= _illustStore.totalPages - 1 &&
            _illustStore.totalPages > 1) {
          _stopAutoScroll();
          return;
        }
        double current = _photoScrollController.offset;
        double max = _photoScrollController.position.maxScrollExtent;
        if (current >= max) {
          _stopAutoScroll();
          return;
        }
        double delta = userSetting.illustAutoScrollSpeed;
        _photoScrollController.jumpTo((current + delta).clamp(0.0, max));
      });
    }
    if (!_autoScrollTicker!.isActive) {
      _autoScrollTicker!.start();
      setState(() {
        _isAutoScrolling = true;
      });
    }
  }

  void _resumeAutoScrollAfterInertia() {
    if (!_photoScrollController.hasClients) return;

    final position = _photoScrollController.position;

    void checkAndResume() {
      position.isScrollingNotifier.removeListener(checkAndResume);

      if (!position.isScrollingNotifier.value &&
          _isAutoScrolling &&
          _autoScrollTicker != null &&
          !_autoScrollTicker!.isActive) {
        _autoScrollTicker!.start();
      }
    }

    if (position.isScrollingNotifier.value) {
      position.isScrollingNotifier.addListener(checkAndResume);
    } else {
      if (_autoScrollTicker != null && !_autoScrollTicker!.isActive) {
        _autoScrollTicker!.start();
      }
    }
  }

  void _checkFlingGesture() async {
    if (!_photoScrollController.hasClients) return;

    final position = _photoScrollController.position;

    await Future.delayed(Duration(milliseconds: 50));

    if (!mounted || !_photoScrollController.hasClients) return;
    if (!position.isScrollingNotifier.value) return;

    final startPos = position.pixels;

    await Future.delayed(Duration(milliseconds: 50));

    if (!mounted || !_photoScrollController.hasClients) return;
    final endPos = _photoScrollController.position.pixels;

    final velocity = (endPos - startPos) / 0.05;

    const double downwardVelocityThreshold = 1000.0;
    const double upwardVelocityThreshold = 800.0;

    if (velocity > downwardVelocityThreshold && !_isAutoScrolling) {
      void waitAndStart() {
        position.isScrollingNotifier.removeListener(waitAndStart);
        if (!_isAutoScrolling && mounted && _photoScrollController.hasClients) {
          _startAutoScroll();
        }
      }

      if (position.isScrollingNotifier.value) {
        position.isScrollingNotifier.addListener(waitAndStart);
      } else {
        _startAutoScroll();
      }
    } else if (velocity < -upwardVelocityThreshold && _isAutoScrolling) {
      _stopAutoScroll();
    }
  }

  void _showSpeedControl(RenderBox button) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final double menuWidth = 80.0;
    final double menuHeight = 200.0;

    final buttonPosition = button.localToGlobal(Offset.zero);
    final buttonSize = button.size;

    final menuGlobalPosition = Offset(
      buttonPosition.dx + (buttonSize.width - menuWidth) / 2,
      buttonPosition.dy - menuHeight - 30,
    );

    final menuLocalPosition = overlay.globalToLocal(menuGlobalPosition);

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        menuLocalPosition & Size(menuWidth, menuHeight),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          child: StatefulBuilder(
            builder: (context, setState) {
              return Container(
                width: menuWidth,
                height: menuHeight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "速度",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Slider(
                          value: userSetting.illustAutoScrollSpeed,
                          min: 0.5,
                          max: 10.0,
                          onChanged: (value) {
                            userSetting.setIllustAutoScrollSpeed(value);
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      userSetting.illustAutoScrollSpeed.toStringAsFixed(1),
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (!_photoScrollController.hasClients) return KeyEventResult.ignored;

        final position = _photoScrollController.position;
        final viewportHeight = position.viewportDimension;
        final scrollDistance = viewportHeight * 0.75;
        final currentOffset = position.pixels;
        double targetOffset;

        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          targetOffset = (currentOffset - scrollDistance).clamp(
            0.0,
            position.maxScrollExtent,
          );
        } else {
          targetOffset = (currentOffset + scrollDistance).clamp(
            0.0,
            position.maxScrollExtent,
          );
        }

        if (targetOffset != currentOffset) {
          _photoScrollController.animateTo(
            targetOffset,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _buildPageIndicator() {
    return Observer(
      builder: (context) {
        return Material(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              if (_isAutoScrolling) {
                _stopAutoScroll();
              } else {
                _startAutoScroll();
              }
            },
            onLongPress: () {
              final RenderBox button = context.findRenderObject() as RenderBox;
              _showSpeedControl(button);
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                '${_illustStore.currentPage + 1} / ${_illustStore.totalPages}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildJumpHint() {
    if (!_illustStore.showJumpHint) return const SizedBox.shrink();
    return AnimatedOpacity(
      opacity: _illustStore.showJumpHint ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Material(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
        elevation: 8,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            _illustStore.hideJumpHint();
            _observerController.animateTo(
              index: _illustStore.lastReadPage,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  "跳转到上次阅读位置 (第 ${_illustStore.lastReadPage + 1} 页)",
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _illustStore.hideJumpHint(),
                  child: Icon(Icons.close, color: Colors.white70, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Center _buildErrorContent(BuildContext context) {
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
          Text('${_illustStore.errorMessage}', maxLines: 5),
          ElevatedButton(
            onPressed: () {
              _illustStore.fetch();
            },
            child: Text(I18n.of(context).refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildIllustsItem(int index, Illusts illust, double height) {
    final String imageUrl;
    final String placeholderUrl;
    final bool usePlaceholder;
    final localImageInfo = _illustStore.getLocalImageInfo(index);

    // 计算质量标识
    String quality = userSetting.previewQuality;

    if (illust.type == "manga") {
      imageUrl = illust.managaDetailImageUrl(index);
      placeholderUrl =
          index == 0
              ? illust.previewUrl
              : illust.metaPages[index].imageUrls!.squareMedium;
      usePlaceholder = index == 0 ? userSetting.mangaQuality >= 1 : false;

      if (index != 0) {
        quality = Constants.qualitySquareMedium;
      }
    } else {
      imageUrl = illust.illustDetailImageUrl(index);
      placeholderUrl =
          index == 0
              ? illust.previewUrl
              : illust.metaPages[index].imageUrls!.squareMedium;
      usePlaceholder = index == 0 ? userSetting.pictureQuality >= 1 : false;

      if (index != 0) {
        quality = Constants.qualitySquareMedium;
      }
    }

    Widget child = PixivImage(
      imageUrl,
      localImageInfo: localImageInfo,
      placeWidget:
          usePlaceholder && localImageInfo == null
              ? PixivImage(
                placeholderUrl,
                fade: false,
                httpHeaders: {'cover': '${illust.id}', 'quality': quality},
              )
              : Container(
                height: height,
                child: Center(
                  child: Text(
                    '$index',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ),
      fade: false,
    );
    if (index == 0) {
      child = NullHero(child: child, tag: widget.heroString);
    }
    return child;
  }

  Future _longPressTag(BuildContext context, Tags f) async {
    switch (await showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: "${f.name}",
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (f.translatedName != null)
                  TextSpan(
                    text: "\n${"${f.translatedName}"}",
                    style: Theme.of(context).textTheme.bodyLarge!,
                  ),
              ],
            ),
          ),
          children: <Widget>[
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 0);
              },
              child: Text(I18n.of(context).ban),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 1);
              },
              child: Text(I18n.of(context).bookmark),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 2);
              },
              child: Text(I18n.of(context).copy),
            ),
          ],
        );
      },
    )) {
      case 0:
        {
          muteStore.insertBanTag(
            BanTagPersist(name: f.name, translateName: f.translatedName ?? ""),
          );
        }
        break;
      case 1:
        {
          bookTagStore.bookTag(f.name);
        }
        break;
      case 2:
        {
          await Clipboard.setData(ClipboardData(text: f.name));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: Duration(seconds: 1),
              content: Text(I18n.of(context).copied_to_clipboard),
            ),
          );
        }
    }
  }

  Future _showTagContextMenu(
    BuildContext context,
    Tags f,
    Offset position,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final result = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              Icon(Icons.copy, size: 20),
              SizedBox(width: 12),
              Text(I18n.of(context).copy),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              Icon(Icons.bookmark_outline, size: 20),
              SizedBox(width: 12),
              Text(I18n.of(context).bookmark),
            ],
          ),
        ),
      ],
    );

    if (result != null) {
      switch (result) {
        case 0:
          await Clipboard.setData(ClipboardData(text: f.name));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: Duration(seconds: 1),
              content: Text(I18n.of(context).copied_to_clipboard),
            ),
          );
          break;
        case 1:
          bookTagStore.bookTag(f.name);
          break;
      }
    }
  }

  Widget buildRow(BuildContext context, Tags f) {
    return InkWell(
      onLongPress: () async {
        await _longPressTag(context, f);
      },
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) {
              return ResultPage(
                word: f.name,
                translatedName: f.translatedName ?? "",
              );
            },
          ),
        );
      },
      onSecondaryTapDown: (details) async {
        await _showTagContextMenu(context, f, details.globalPosition);
      },
      mouseCursor: SystemMouseCursors.click,
      borderRadius: const BorderRadius.all(Radius.circular(12.5)),
      child: Container(
        height: 25,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: const BorderRadius.all(Radius.circular(12.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RichText(
              textAlign: TextAlign.start,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              text: TextSpan(
                text: "#${f.name}",
                children: [
                  TextSpan(
                    text: " ",
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall!.copyWith(fontSize: 12),
                  ),
                  if (f.translatedName != null)
                    TextSpan(
                      text: "${f.translatedName}",
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall!.copyWith(fontSize: 12),
                    ),
                ],
                style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameAvatar(BuildContext context, Illusts illust) {
    if (userStore == null)
      userStore = UserStore(illust.user.id, null, illust.user);
    return Observer(
      builder: (_) {
        Future.delayed(Duration(seconds: 2), () {
          _loadAbout();
        });
        return InkWell(
          onTap: () async {
            await _push2UserPage(context, illust);
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Padding(
                child: Hero(
                  tag:
                      illust.user.profileImageUrls.medium +
                      this.hashCode.toString(),
                  child: PainterAvatar(
                    url: illust.user.profileImageUrls.medium,
                    id: illust.user.id,
                    size: Size(32, 32),
                    onTap: () async {
                      await Leader.push(
                        context,
                        UsersPage(
                          id: illust.user.id,
                          userStore: userStore,
                          heroTag: this.hashCode.toString(),
                        ),
                      );
                      _illustStore.illusts!.user.isFollowed =
                          userStore!.isFollow;
                    },
                  ),
                ),
                padding: EdgeInsets.only(left: 16.0),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      Hero(
                        tag: illust.user.name + this.hashCode.toString(),
                        child: SelectionArea(
                          child: Text(
                            illust.user.name,
                            style: TextStyle(
                              fontSize: 14,
                              color:
                                  Theme.of(context).textTheme.bodySmall!.color,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              UserFollowButton(
                id: illust.user.id,
                followed:
                    userStore?.isFollow ?? illust.user.isFollowed ?? false,
                onPressed: () async {
                  await userStore?.follow();
                  if (userStore?.isFollow != null) {
                    _illustStore.illusts?.user.isFollowed = userStore?.isFollow;
                  }
                },
                onConfirm: (follow, restrict) {
                  userStore?.followWithRestrict(follow, restrict);
                  if (userStore?.isFollow != null) {
                    _illustStore.illusts?.user.isFollowed = userStore?.isFollow;
                  }
                },
              ),
              SizedBox(width: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _push2UserPage(BuildContext context, Illusts illust) async {
    await Leader.push(
      context,
      UsersPage(
        id: illust.user.id,
        userStore: userStore,
        heroTag: this.hashCode.toString(),
      ),
    );
    _illustStore.illusts!.user.isFollowed = userStore!.isFollow;
  }

  Future<void> _pressSave(Illusts illust, int index) async {
    if (userSetting.illustDetailSaveSkipLongPress) {
      downloadStore.downloadIllust(illust, part: index);
      if (userSetting.starAfterSave && (_illustStore.state == 0)) {
        _illustStore.star(
          restrict: userSetting.defaultPrivateLike ? "private" : "public",
        );
      }
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (c1) {
        return Container(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              illust.metaPages.isNotEmpty
                  ? ListTile(
                    title: Text(I18n.of(context).muti_choice_save),
                    leading: Icon(Icons.save),
                    onTap: () async {
                      Navigator.of(context).pop();
                      _showMutiChoiceDialog(illust, context);
                    },
                  )
                  : Container(),
              ListTile(
                leading: Icon(Icons.save_alt),
                onTap: () async {
                  Navigator.of(context).pop();
                  downloadStore.downloadIllust(illust, part: index);
                  if (userSetting.starAfterSave && (_illustStore.state == 0)) {
                    _illustStore.star(
                      restrict:
                          userSetting.defaultPrivateLike ? "private" : "public",
                    );
                  }
                },
                onLongPress: () async {
                  Navigator.of(context).pop();
                  downloadStore.downloadIllust(illust, part: index);
                },
                title: Text(I18n.of(context).save),
              ),
              ListTile(
                leading: Icon(Icons.cancel),
                onTap: () => Navigator.of(context).pop(),
                title: Text(I18n.of(context).cancel),
              ),
              Container(height: MediaQuery.of(c1).padding.bottom),
            ],
          ),
        );
      },
    );
  }

  Future _showMutiChoiceDialog(Illusts illust, BuildContext context) async {
    List<bool> indexs = [];
    bool allOn = false;
    for (int i = 0; i < illust.metaPages.length; i++) {
      indexs.add(false);
    }
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.8,
                child: Column(
                  children: [
                    Container(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(illust.title),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        itemBuilder: (context, index) {
                          final data = illust.metaPages[index];
                          return Container(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    indexs[index] = !indexs[index];
                                  });
                                },
                                onLongPress: () {
                                  Leader.push(
                                    context,
                                    PhotoZoomPage(
                                      index: index,
                                      illusts: illust,
                                      illustStore: _illustStore,
                                    ),
                                  );
                                },
                                child: Stack(
                                  children: [
                                    PixivImage(
                                      data.imageUrls!.squareMedium,
                                      placeWidget: Container(
                                        child: Center(
                                          child: Text(index.toString()),
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.bottomRight,
                                      child: Visibility(
                                        visible: indexs[index],
                                        child: Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        itemCount: illust.metaPages.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        !allOn
                            ? Icons.check_circle_outline
                            : Icons.check_circle,
                      ),
                      title: Text(I18n.of(context).all),
                      onTap: () {
                        allOn = !allOn;
                        for (var i = 0; i < indexs.length; i++) {
                          indexs[i] = allOn;
                        }
                        setDialogState(() {});
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.save),
                      title: Text(I18n.of(context).save),
                      onTap: () {
                        Navigator.of(context).pop("OK");
                        if (userSetting.starAfterSave &&
                            (_illustStore.state == 0)) {
                          _illustStore.star(
                            restrict:
                                userSetting.defaultPrivateLike
                                    ? "private"
                                    : "public",
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    switch (result) {
      case "OK":
        {
          for (int i = 0; i < indexs.length; i++) {
            if (indexs[i]) {
              downloadStore.downloadIllust(illust, part: i);
            }
          }
        }
    }
  }

  Future buildShowModalBottomSheet(BuildContext context, Illusts illusts) {
    return showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8.0),
              topRight: Radius.circular(8.0),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    _buildNameAvatar(context, illusts),
                    if (illusts.metaPages.isNotEmpty)
                      ListTile(
                        title: Text(I18n.of(context).muti_choice_save),
                        leading: Icon(Icons.save),
                        onTap: () async {
                          Navigator.of(context).pop();
                          _showMutiChoiceDialog(illusts, context);
                        },
                      ),
                    ListTile(
                      title: Text(I18n.of(context).copymessage),
                      leading: Icon(Icons.local_library),
                      onTap: () async {
                        final str = userSetting.illustToShareInfoText(illusts);
                        await Clipboard.setData(ClipboardData(text: str));
                        BotToast.showText(
                          text: I18n.of(context).copied_to_clipboard,
                        );
                        Navigator.of(context).pop();
                      },
                    ),
                    Builder(
                      builder: (context) {
                        return ListTile(
                          title: Text(I18n.of(context).share),
                          leading: Icon(Icons.share),
                          onTap: () {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            final pos =
                                box != null
                                    ? box.localToGlobal(Offset.zero) & box.size
                                    : null;
                            Navigator.of(context).pop();
                            Share.share(
                              "https://www.pixiv.net/artworks/${widget.id}",
                              sharePositionOrigin: pos,
                            );
                          },
                        );
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.link),
                      title: Text(I18n.of(context).link),
                      onTap: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: "https://www.pixiv.net/artworks/${widget.id}",
                          ),
                        );
                        BotToast.showText(
                          text: I18n.of(context).copied_to_clipboard,
                        );
                        Navigator.of(context).pop();
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.open_in_browser),
                      title: Text(I18n.of(context).open_in_browser),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await launchUrlString(
                          "https://www.pixiv.net/artworks/${widget.id}",
                        );
                      },
                    ),
                    ListTile(
                      title: Text(I18n.of(context).ban),
                      leading: Icon(Icons.brightness_auto),
                      onTap: () {
                        muteStore.insertBanIllusts(
                          BanIllustIdPersist(
                            illustId: widget.id.toString(),
                            name: illusts.title,
                          ),
                        );
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      title: Text(I18n.of(context).report),
                      leading: Icon(Icons.report),
                      onTap: () async {
                        if (Platform.isAndroid) {
                          Navigator.of(context).pop();
                          await Reporter.show(
                            context,
                            () async => await muteStore.insertBanIllusts(
                              BanIllustIdPersist(
                                illustId: widget.id.toString(),
                                name: illusts.title,
                              ),
                            ),
                          );
                        } else {
                          await showDialog(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                title: Text(I18n.of(context).report),
                                content: Text(I18n.of(context).report_message),
                                actions: <Widget>[
                                  TextButton(
                                    child: Text(I18n.of(context).cancel),
                                    onPressed: () {
                                      Navigator.of(context).pop("CANCEL");
                                    },
                                  ),
                                  TextButton(
                                    child: Text(I18n.of(context).ok),
                                    onPressed: () {
                                      Navigator.of(context).pop("OK");
                                    },
                                  ),
                                ],
                              );
                            },
                          );
                        }
                      },
                    ),
                  ],
                ),
                Container(height: MediaQuery.of(context).padding.bottom),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBookMarkTag() async {
    final result = await Leader.pushWithScaffold(
      context,
      TagForIllustPage(id: widget.id),
    );
    if (result is Map) {
      Log.d(() => result);
      String restrict = result['restrict'];
      List<String>? tags = result['tags'];
      if (userSetting.saveAfterStar && (_illustStore.state == 0)) {
        downloadStore.downloadIllust(_illustStore.illusts!);
      }
      _illustStore.star(restrict: restrict, tags: tags, force: true);
    }
  }

  @override
  bool get wantKeepAlive => false;
}

class TextSelectionFix {
  static TextSelectionControls? buildControls(BuildContext context) {
    TextSelectionControls? controls = null;
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        controls ??= materialTextSelectionControls;
        break;
      case TargetPlatform.iOS:
        controls ??= cupertinoTextSelectionControls;
        break;
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        controls ??= desktopTextSelectionControls;
        break;
      case TargetPlatform.macOS:
        controls ??= cupertinoDesktopTextSelectionControls;
        break;
    }
    return controls;
  }
}
