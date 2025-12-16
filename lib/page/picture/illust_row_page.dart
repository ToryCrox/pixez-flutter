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

import 'package:bot_toast/bot_toast.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/ban_page.dart';
import 'package:pixez/component/common_back_area.dart';
import 'package:pixez/component/local_or_cached_image.dart';
import 'package:pixez/component/null_hero.dart';
import 'package:pixez/component/painter_avatar.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/component/star_icon.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/er/lprinter.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/ban_illust_id.dart';
import 'package:pixez/models/ban_tag.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/picture/illust_about_store.dart';
import 'package:pixez/page/picture/illust_detail_content.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/picture_list_page.dart';
import 'package:pixez/page/picture/tag_for_illust_page.dart';
import 'package:pixez/page/picture/ugoira_loader.dart';
import 'package:pixez/page/search/result_page.dart';
import 'package:pixez/page/user/user_store.dart';
import 'package:pixez/page/user/users_page.dart';
import 'package:pixez/page/zoom/photo_zoom_page.dart';
import 'package:share_plus/share_plus.dart';

class IllustRowPage extends StatefulWidget {
  final int id;
  final String? heroString;
  final IllustStore? store;
  final GestureDragEndCallback? onHorizontalDragEnd;

  const IllustRowPage(
      {Key? key,
      required this.id,
      this.heroString,
      this.store,
      this.onHorizontalDragEnd})
      : super(key: key);

  @override
  _IllustRowPageState createState() => _IllustRowPageState();
}

class _IllustRowPageState extends State<IllustRowPage>
    with AutomaticKeepAliveClientMixin {
  UserStore? userStore;
  late IllustStore _illustStore;
  late IllustAboutStore _aboutStore;
  late ScrollController _scrollController;
  late ScrollController _photoScrollController;
  late EasyRefreshController _refreshController;
  late FocusNode _focusNode;
  bool tempView = false;
  int _currentPage = 0;
  int _totalPages = 1;
  double? _itemHeight; // 存储每页高度，避免在滚动监听器中访问 context
  bool _sidebarVisible = true; // 控制侧边栏显示/隐藏

  @override
  void initState() {
    _refreshController = EasyRefreshController(
        controlFinishLoad: true, controlFinishRefresh: true);
    _scrollController = ScrollController();
    _photoScrollController = ScrollController();
    _focusNode = FocusNode();
    _photoScrollController.addListener(_onPhotoScroll);
    _illustStore = widget.store ?? IllustStore(widget.id, null);
    _illustStore.fetch(force: true);
    _aboutStore = IllustAboutStore(widget.id, _refreshController);
    super.initState();
  }

  void _onPhotoScroll() {
    if (!_photoScrollController.hasClients || _itemHeight == null) return;

    final illusts = _illustStore.illusts;
    if (illusts == null || illusts.pageCount <= 1) {
      if (_currentPage != 0 || _totalPages != 1) {
        setState(() {
          _currentPage = 0;
          _totalPages = 1;
        });
      }
      return;
    }

    _totalPages = illusts.pageCount;
    final scrollOffset = _photoScrollController.offset;
    final viewportHeight = _photoScrollController.position.viewportDimension;

    // 计算当前页数（基于滚动位置和视口中心）
    int newPage = ((scrollOffset + viewportHeight / 2) / _itemHeight!).floor();
    newPage = newPage.clamp(0, _totalPages - 1);

    if (newPage != _currentPage) {
      setState(() {
        _currentPage = newPage;
      });
    }
  }

  @override
  void didUpdateWidget(covariant IllustRowPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _illustStore = widget.store ?? IllustStore(widget.id, null);
      _illustStore.fetch();
      _aboutStore = IllustAboutStore(widget.id, _refreshController);
      LPrinter.d("state change");
    }
  }

  void _loadAbout() {
    if (mounted &&
        _scrollController.hasClients &&
        _aboutStore.illusts.isEmpty &&
        !_aboutStore.fetching) _aboutStore.next();
  }

  @override
  void dispose() {
    _illustStore.dispose();
    _scrollController.dispose();
    _photoScrollController.removeListener(_onPhotoScroll);
    _photoScrollController.dispose();
    _focusNode.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  Widget _buildAppbar() {
    return Column(
      children: [
        Container(
          height: MediaQuery.of(context).padding.top,
        ),
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
                    icon: Icon(Icons.more_vert),
                    onPressed: () {
                      buildShowModalBottomSheet(context, _illustStore.illusts!);
                    },
                  )
                ],
              )
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      extendBody: true,
      // appBar: AppBar(
      //   elevation: 0.0,
      //   // iconTheme: IconTheme.of(context).copyWith(color: Theme.of(context).textTheme!.bodyText1!.color),
      //   backgroundColor: Colors.transparent,
      //   actions: [
      //     IconButton(
      //         icon: Icon(Icons.more_vert),
      //         onPressed: () {
      //           buildShowModalBottomSheet(context, _illustStore.illusts!);
      //         })
      //   ],
      // ),
      extendBodyBehindAppBar: true,
      floatingActionButton: Observer(builder: (context) {
        return Visibility(
          visible: _illustStore.errorMessage == null,
          child: _buildFloatingActionButtons(),
        );
      }),
      body: Observer(builder: (_) {
        if (!tempView)
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
        if (!tempView && _illustStore.illusts != null) {
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
            for (var t1 in _illustStore.illusts!.tags) {
              if (t.name == t1.name)
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
        return Container(
          child: Stack(
            children: [
              _buildContent(context, _illustStore.illusts),
              _buildAppbar()
            ],
          ),
        );
      }),
    );
  }

  Widget colorText(String text, BuildContext context) => SelectionArea(
        child: Text(
          text,
          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
        ),
      );

  ScrollController scrollController = ScrollController();

  Widget _buildContent(BuildContext context, Illusts? data) {
    if (_illustStore.errorMessage != null && data == null)
      return _buildErrorContent(context);
    if (data == null)
      return Container(
        child: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      );
    var expectWidth =
        MediaQuery.of(context).size.width * 0.7 + userSetting.dragStartX;
    var leftWidth = MediaQuery.of(context).size.width - expectWidth;
    final atLeastWidth = 320.0;
    if (leftWidth < atLeastWidth) {
      leftWidth = atLeastWidth;
      expectWidth = MediaQuery.of(context).size.width - leftWidth;
    }
    final radio = (data.height.toDouble() / data.width);
    final screenHeight = MediaQuery.of(context).size.height;
    final height = (radio * expectWidth);
    final centerType = height <= screenHeight;
    if (userStore == null) userStore = UserStore(data.user.id, null, data.user);
    final dividerWidth = 28.0;
    // 动画持续时间
    const animationDuration = Duration(milliseconds: 300);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      onDoubleTap: () {
        // 双击切换侧边栏显示/隐藏
        setState(() {
          _sidebarVisible = !_sidebarVisible;
        });
      },
      child: Observer(builder: (context) {
        // 更新总页数和计算每页高度
        if (data.pageCount > 1) {
          _totalPages = data.pageCount;
          // 计算每页高度
          final radio = (data.height.toDouble() / data.width);
          _itemHeight = radio * expectWidth;
        } else {
          _totalPages = 1;
          _currentPage = 0;
          _itemHeight = null;
        }

        // 计算侧边栏宽度
        final sidebarWidth = leftWidth;

        return Container(
          child: Stack(
            children: [
              // 图片区域，使用 AnimatedPositioned 实现平滑过渡
              AnimatedPositioned(
                duration: animationDuration,
                curve: Curves.easeInOut,
                left: 0,
                top: 0,
                bottom: 0,
                right: _sidebarVisible ? sidebarWidth : 0,
                child: Focus(
                  focusNode: _focusNode,
                  autofocus: true,
                  onKeyEvent: _handleKeyEvent,
                  child: CustomScrollView(
                    controller: _photoScrollController,
                    slivers: [
                      ..._buildPhotoList(data, centerType, height),
                      SliverToBoxAdapter(
                          child: Container(
                        height: MediaQuery.of(context).padding.bottom,
                      ))
                    ],
                  ),
                ),
              ),
              // 侧边栏，使用 AnimatedPositioned 实现从右侧滑入/滑出
              AnimatedPositioned(
                duration: animationDuration,
                curve: Curves.easeInOut,
                right: _sidebarVisible ? 0 : -sidebarWidth,
                top: 0,
                bottom: 0,
                width: sidebarWidth,
                child: Container(
                  color: Theme.of(context).cardColor,
                  child: EasyRefresh(
                    controller: _refreshController,
                    onLoad: () {
                      _aboutStore.next();
                    },
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Container(
                            height: MediaQuery.of(context).padding.top,
                          ),
                        ),
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
                        _buildRecom()
                      ],
                    ),
                  ),
                ),
              ),
              // 拖拽调整宽度的分隔条，只在侧边栏可见时显示
              if (_sidebarVisible)
                Positioned(
                  right: sidebarWidth - (dividerWidth * 0.5),
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () {},
                    onHorizontalDragUpdate: (details) {
                      userSetting.setDragStartX(details.localPosition.dx);
                    },
                    behavior: HitTestBehavior.translucent,
                    child: Container(
                      width: dividerWidth,
                    ),
                  ),
                ),
              // 页数指示器
              if (data.pageCount > 1)
                Positioned(
                  bottom: 20,
                  left: 10,
                  child: Observer(
                    builder: (_) => _buildPageIndicator(),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (!_photoScrollController.hasClients) return KeyEventResult.ignored;

        final position = _photoScrollController.position;
        final viewportHeight = position.viewportDimension;
        final scrollDistance = viewportHeight * 0.75; // 滚动视口高度的 3/4
        final currentOffset = position.pixels;
        double targetOffset;

        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          // 向上滚动
          targetOffset = (currentOffset - scrollDistance)
              .clamp(0.0, position.maxScrollExtent);
        } else {
          // 向下滚动
          targetOffset = (currentOffset + scrollDistance)
              .clamp(0.0, position.maxScrollExtent);
        }

        if (targetOffset != currentOffset) {
          _scrollToOffset(targetOffset);
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  void _scrollToOffset(double offset) {
    if (!_photoScrollController.hasClients) return;

    _photoScrollController.animateTo(
      offset,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildPageIndicator() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${_currentPage + 1} / $_totalPages',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  SliverGrid _buildRecom() {
    return SliverGrid(
        delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
          var list = _aboutStore.illusts
              .map((element) => IllustStore(element.id, element))
              .toList();
          final illust = _aboutStore.illusts[index];
          return InkWell(
            onTap: () {
              Leader.push(
                  context,
                  PictureListPage(
                    iStores: list,
                    lightingStore: null,
                    store: list[index],
                  ));
            },
            onLongPress: () {
              saveStore.saveImage(_aboutStore.illusts[index]);
              if (userSetting.starAfterSave && (_illustStore.state == 0)) {
                _illustStore.star(
                    restrict:
                        userSetting.defaultPrivateLike ? "private" : "public");
              }
            },
            child: Stack(
              children: [
                PixivImage(
                  illust.imageUrls.squareMedium,
                  enableMemoryCache: false,
                  // 通过 header 传递 illustId，让 PixivCacheManager 识别封面请求
                  httpHeaders: {'cover': '${illust.id}'},
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: DownloadStatusIndicator(
                    illustId: illust.id,
                    pageCount: illust.pageCount,
                    size: 14,
                  ),
                ),
              ],
            ),
          );
        }, childCount: _aboutStore.illusts.length),
        gridDelegate:
            SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3));
  }

  List<Widget> _buildPhotoList(Illusts data, bool centerType, double height) {
    return [
      if (data.type == "ugoira")
        SliverToBoxAdapter(
          child: NullHero(
            tag: widget.heroString,
            child: UgoiraLoader(
              id: widget.id,
              illusts: data,
            ),
          ),
        ),
      if (data.type != "ugoira")
        data.pageCount == 1
            ? (centerType
                ? SliverFillRemaining(
                    child: _buildPicture(data, height),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                    return _buildPicture(data, height);
                  }, childCount: 1)))
            : SliverList(
                delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) {
                return InkWell(onLongPress: () {
                  _pressSave(data, index);
                }, onTap: () {
                  // Leader.push(
                  //     context,
                  //     PhotoZoomPage(
                  //       index: index,
                  //       illusts: data,
                  //       illustStore: _illustStore,
                  //     ));
                }, child: Observer(builder: (context) {
                  return _buildIllustsItem(index, data, height);
                }));
              }, childCount: data.metaPages.length)),
    ];
  }

  Widget _buildPicture(Illusts data, double height) {
    return Center(child: Builder(
      builder: (BuildContext context) {
        String url = data.illustDetailUrl;
        if (data.type == "manga") {
          url = data.managaDetailUrl;
        }
        Widget placeWidget = Container(height: height);
        // 移除点击打开大图，保留长按保存
        return InkWell(
          onLongPress: () {
            _pressSave(data, 0);
          },
          child: NullHero(
            tag: widget.heroString,
            child: PixivImage(
              url,
              localImageInfo: _illustStore.getLocalImageInfo(0),
              fade: false,
              placeWidget: (url != data.imageUrls.medium)
                  ? PixivImage(
                      data.imageUrls.medium,
                      placeWidget: placeWidget,
                      fade: false,
                    )
                  : placeWidget,
            ),
          ),
        );
      },
    ));
  }

  Center _buildErrorContent(BuildContext context) {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8.0),
            child:
                Text(':(', style: Theme.of(context).textTheme.headlineMedium),
          ),
          Text(
            '${_illustStore.errorMessage}',
            maxLines: 5,
          ),
          ElevatedButton(
            onPressed: () {
              _illustStore.fetch();
            },
            child: Text(I18n.of(context).refresh),
          )
        ],
      ),
    );
  }

  Widget _buildIllustsItem(int index, Illusts illust, double height) {
    final String imageUrl;
    final String mediumImageUrl;
    final bool useMediumPlaceHolder;
    final localImageInfo = _illustStore.getLocalImageInfo(index);
    if (illust.type == "manga") {
      imageUrl = illust.managaDetailImageUrl(index);
      mediumImageUrl = illust.metaPages[index].imageUrls!.squareMedium;
      useMediumPlaceHolder = index == 0 && userSetting.mangaQuality >= 1;
    } else {
      imageUrl = illust.illustDetailImageUrl(index);
      mediumImageUrl = illust.metaPages[index].imageUrls!.squareMedium;
      useMediumPlaceHolder = index == 0 && userSetting.pictureQuality >= 1;
    }

    Widget child = PixivImage(
      imageUrl,
      localImageInfo: _illustStore.getLocalImageInfo(index),
      placeWidget: useMediumPlaceHolder
          ? PixivImage(
              mediumImageUrl,
              fade: false,
              httpHeaders: {'cover': '${illust.id}'},
            )
          : Container(
              height: height,
              child: Center(
                child: Text('$index',
                    style: Theme.of(context).textTheme.headlineMedium),
              ),
            ),
      fade: false,
    );
    if (index == 0) {
      child = NullHero(
        child: child,
        tag: widget.heroString,
      );
    }
    return child;
  }

  Future _longPressTag(BuildContext context, Tags f) async {
    switch (await showDialog(
        context: context,
        builder: (BuildContext context) {
          return SimpleDialog(
            title: Text(f.name),
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
        })) {
      case 0:
        {
          muteStore.insertBanTag(BanTagPersist(
              name: f.name, translateName: f.translatedName ?? ""));
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: Duration(seconds: 1),
            content: Text(I18n.of(context).copied_to_clipboard),
          ));
        }
    }
  }

  Widget buildRow(BuildContext context, Tags f) {
    return GestureDetector(
      onLongPress: () async {
        await _longPressTag(context, f);
      },
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (context) {
          return ResultPage(
            word: f.name,
            translatedName: f.translatedName ?? "",
          );
        }));
      },
      child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
              text: "#${f.name}",
              children: [
                TextSpan(
                  text: " ",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                TextSpan(
                    text: "${f.translatedName ?? "~"}",
                    style: Theme.of(context).textTheme.bodySmall)
              ],
              style: Theme.of(context)
                  .textTheme
                  .bodySmall!
                  .copyWith(color: Theme.of(context).colorScheme.secondary))),
    );
  }

  Widget _buildNameAvatar(BuildContext context, Illusts illust) {
    if (userStore == null)
      userStore = UserStore(illust.user.id, null, illust.user);
    return Observer(builder: (_) {
      Future.delayed(Duration(seconds: 2), () {
        _loadAbout();
      });
      return Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Padding(
              child: GestureDetector(
                onLongPress: () {
                  userStore!.follow();
                },
                child: Container(
                  height: 70,
                  width: 70,
                  child: Stack(
                    children: <Widget>[
                      Center(
                        child: SizedBox(
                          height: 70,
                          width: 70,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: userStore!.isFollow
                                  ? Colors.yellow
                                  : Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Hero(
                          tag: illust.user.profileImageUrls.medium +
                              this.hashCode.toString(),
                          child: PainterAvatar(
                            url: illust.user.profileImageUrls.medium,
                            id: illust.user.id,
                            onTap: () async {
                              await Leader.push(
                                  context,
                                  UsersPage(
                                    id: illust.user.id,
                                    userStore: userStore,
                                    heroTag: this.hashCode.toString(),
                                  ));
                              _illustStore.illusts!.user.isFollowed =
                                  userStore!.isFollow;
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              padding: EdgeInsets.all(8.0)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  SelectionArea(
                    child: Text(
                      illust.title,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary),
                    ),
                  ),
                  Container(
                    height: 4.0,
                  ),
                  Hero(
                    tag: illust.user.name + this.hashCode.toString(),
                    child: SelectionArea(
                      child: Text(
                        illust.user.name,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  Text(
                    illust.createDate.toShortTime(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Future<void> _pressSave(Illusts illust, int index) async {
    if (userSetting.illustDetailSaveSkipLongPress) {
      saveStore.saveImage(illust, index: index);
      if (userSetting.starAfterSave && (_illustStore.state == 0)) {
        _illustStore.star(
            restrict: userSetting.defaultPrivateLike ? "private" : "public");
      }
      return;
    }
    showModalBottomSheet(
        context: context,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(16),
          ),
        ),
        builder: (c1) {
          return Container(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                illust.metaPages.isNotEmpty
                    ? ListTile(
                        title: Text(I18n.of(context).muti_choice_save),
                        leading: Icon(
                          Icons.save,
                        ),
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
                    saveStore.saveImage(illust, index: index);
                    if (userSetting.starAfterSave &&
                        (_illustStore.state == 0)) {
                      _illustStore.star(
                          restrict: userSetting.defaultPrivateLike
                              ? "private"
                              : "public");
                    }
                  },
                  onLongPress: () async {
                    Navigator.of(context).pop();
                    saveStore.saveImage(illust, index: index);
                    if (userSetting.starAfterSave &&
                        (_illustStore.state == 0)) {
                      _illustStore.star(
                          restrict: userSetting.defaultPrivateLike
                              ? "private"
                              : "public");
                    }
                  },
                  title: Text(I18n.of(context).save),
                ),
                ListTile(
                  leading: Icon(Icons.cancel),
                  onTap: () => Navigator.of(context).pop(),
                  title: Text(I18n.of(context).cancel),
                ),
                Container(
                  height: MediaQuery.of(c1).padding.bottom,
                )
              ],
            ),
          );
        });
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.0))),
        builder: (context) {
          return StatefulBuilder(builder: (context, setDialogState) {
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
                                    ));
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
                                          ))),
                                ],
                              ),
                            ),
                          ));
                        },
                        itemCount: illust.metaPages.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3),
                      ),
                    ),
                    ListTile(
                      leading: Icon(!allOn
                          ? Icons.check_circle_outline
                          : Icons.check_circle),
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
                      },
                    ),
                  ],
                ),
              ),
            );
          });
        });
    switch (result) {
      case "OK":
        {
          saveStore.saveChoiceImage(illust, indexs);
        }
    }
  }

  Future buildShowModalBottomSheet(BuildContext context, Illusts illusts) {
    return showModalBottomSheet(
        isScrollControlled: true,
        context: context,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(16),
          ),
        ),
        builder: (_) {
          return Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8.0),
                    topRight: Radius.circular(8.0))),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      _buildNameAvatar(context, illusts),
                      if (illusts.metaPages.isNotEmpty)
                        ListTile(
                          title: Text(I18n.of(context).muti_choice_save),
                          leading: Icon(
                            Icons.save,
                          ),
                          onTap: () async {
                            Navigator.of(context).pop();
                            _showMutiChoiceDialog(illusts, context);
                          },
                        ),
                      ListTile(
                        title: Text(I18n.of(context).copymessage),
                        leading: Icon(
                          Icons.local_library,
                        ),
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(
                              text:
                                  'title:${illusts.title}\npainter:${illusts.user.name}\nillust id:${widget.id}'));
                          BotToast.showText(
                              text: I18n.of(context).copied_to_clipboard);
                          Navigator.of(context).pop();
                        },
                      ),
                      Builder(builder: (context) {
                        return ListTile(
                          title: Text(I18n.of(context).share),
                          leading: Icon(
                            Icons.share,
                          ),
                          onTap: () {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            final pos = box != null
                                ? box.localToGlobal(Offset.zero) & box.size
                                : null;
                            Navigator.of(context).pop();
                            Share.share(
                                "https://www.pixiv.net/artworks/${widget.id}",
                                sharePositionOrigin: pos);
                          },
                        );
                      }),
                      ListTile(
                        leading: Icon(
                          Icons.link,
                        ),
                        title: Text(I18n.of(context).link),
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(
                              text:
                                  "https://www.pixiv.net/artworks/${widget.id}"));
                          BotToast.showText(
                              text: I18n.of(context).copied_to_clipboard);
                          Navigator.of(context).pop();
                        },
                      ),
                      ListTile(
                        title: Text(I18n.of(context).ban),
                        leading: Icon(Icons.brightness_auto),
                        onTap: () {
                          muteStore.insertBanIllusts(BanIllustIdPersist(
                              illustId: widget.id.toString(),
                              name: illusts.title));
                          Navigator.pop(context);
                        },
                      ),
                      ListTile(
                        title: Text(I18n.of(context).report),
                        leading: Icon(Icons.report),
                        onTap: () async {
                          await showDialog(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                  title: Text(I18n.of(context).report),
                                  content:
                                      Text(I18n.of(context).report_message),
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
                              });
                        },
                      )
                    ],
                  ),
                  Container(
                    height: MediaQuery.of(context).padding.bottom,
                  )
                ],
              ),
            ),
          );
        });
  }

  Future<void> _showBookMarkTag() async {
    final result =
        await Leader.pushWithScaffold(context, TagForIllustPage(id: widget.id));
    if (result is Map) {
      LPrinter.d(result);
      String restrict = result['restrict'];
      List<String>? tags = result['tags'];
      _illustStore.star(restrict: restrict, tags: tags, force: true);
    }
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
                      restrict: userSetting.defaultPrivateLike
                          ? "private"
                          : "public");
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
          onHorizontalDragEnd: (details) {
            if (widget.onHorizontalDragEnd != null) {
              widget.onHorizontalDragEnd!(details);
            }
          },
          child: FloatingActionButton(
            heroTag: widget.id,
            backgroundColor: Colors.white,
            onPressed: () async {
              if (userSetting.saveAfterStar && (_illustStore.state == 0)) {
                saveStore.saveImage(_illustStore.illusts!);
              }
              _illustStore.star(
                  restrict:
                      userSetting.defaultPrivateLike ? "private" : "public");
              if (userSetting.followAfterStar) {
                bool success = await _illustStore.followAfterStar();
                if (success) {
                  userStore?.isFollow = true;
                  BotToast.showText(
                      text:
                          "${_illustStore.illusts!.user.name} ${I18n.of(context).followed}");
                }
              }
            },
            child: Observer(builder: (_) {
              return StarIcon(
                state: _illustStore.state,
              );
            }),
          ),
        ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => false;
}
