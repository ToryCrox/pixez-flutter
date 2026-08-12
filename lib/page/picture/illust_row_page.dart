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

import 'dart:convert';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart' hide Listener;
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:pixez/component/ban_page.dart';
import 'package:pixez/component/common_back_area.dart';
import 'package:pixez/component/illust_recommend_grid.dart';
import 'package:pixez/component/local_or_cached_image.dart';
import 'package:pixez/component/null_hero.dart';
import 'package:pixez/component/painter_avatar.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/component/star_icon.dart';
import 'package:pixez/constants.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/ban_illust_id.dart';
import 'package:pixez/models/ban_tag.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/original_image.dart';
import 'package:pixez/models/ugoira_metadata_response.dart';
import 'package:pixez/manga_ocr/manga_ocr_models.dart';
import 'package:pixez/manga_ocr/manga_ocr_pipeline.dart';
import 'package:pixez/manga_ocr/manga_ocr_reading_session.dart';
import 'package:pixez/manga_ocr/manga_ocr_widgets.dart';
import 'package:pixez/manga_ocr/manga_page_image_resolver.dart';

import 'package:pixez/page/downloaded/bookmark_priority_dialog.dart';
import 'package:pixez/page/picture/illust_about_store.dart';
import 'package:pixez/page/picture/illust_detail_content.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/picture_list_page.dart';
import 'package:pixez/page/comment/comment_page.dart';
import 'package:pixez/page/picture/tag_for_illust_page.dart';
import 'package:pixez/component/json_highlighter.dart';
import 'package:pixez/page/picture/ugoira_loader.dart';
import 'package:pixez/page/search/result_page.dart';
import 'package:pixez/page/user/user_store.dart';
import 'package:pixez/page/user/users_page.dart';
import 'package:pixez/page/zoom/photo_zoom_page.dart';
import 'package:pixez/utils/file_utils.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

enum _IllustSidebarOverlay { none, comments, mangaOcr }

class IllustRowPage extends StatefulWidget {
  final int id;
  final String? heroString;
  final IllustStore? store;
  final GestureDragEndCallback? onHorizontalDragEnd;

  const IllustRowPage({
    Key? key,
    required this.id,
    this.heroString,
    this.store,
    this.onHorizontalDragEnd,
  }) : super(key: key);

  @override
  _IllustRowPageState createState() => _IllustRowPageState();
}

class _IllustRowPageState extends State<IllustRowPage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  UserStore? userStore;
  late IllustStore _illustStore;
  late IllustAboutStore _aboutStore;
  late ScrollController _scrollController;
  late ScrollController _photoScrollController;
  late EasyRefreshController _refreshController;
  late FocusNode _focusNode;
  late ListObserverController _observerController; // 用于监听可见元素的控制器
  bool tempView = false;
  bool _sidebarVisible = true; // 控制侧边栏显示/隐藏
  Ticker? _autoScrollTicker;
  bool _isAutoScrolling = false;
  _IllustSidebarOverlay _sidebarOverlay = _IllustSidebarOverlay.none;
  bool _sidebarVisibleBeforeFullscreen = true;
  ReactionDisposer? _fullScreenReaction;
  late final MangaOcrReadingSession _ocrSession;
  final MangaPageImageResolver _ocrImageResolver =
      const PixivMangaPageImageResolver();
  Set<int> _visibleOcrPages = <int>{};
  double? _lastOcrObserveOffset;
  bool _ocrScrollForward = true;

  bool get _showComments => _sidebarOverlay == _IllustSidebarOverlay.comments;
  bool get _showMangaOcr => _sidebarOverlay == _IllustSidebarOverlay.mangaOcr;

  @override
  void initState() {
    _refreshController = EasyRefreshController(
      controlFinishLoad: true,
      controlFinishRefresh: true,
    );
    _scrollController = ScrollController();
    _photoScrollController = ScrollController();
    _focusNode = FocusNode();
    _observerController = ListObserverController(
      controller: _photoScrollController,
    ); // 初始化观察控制器
    _illustStore = widget.store ?? IllustStore(widget.id, null);
    _illustStore.fetch(force: true);
    _aboutStore = IllustAboutStore(widget.id, _refreshController);
    _ocrSession = MangaOcrReadingSession(
      pipeline: MangaOcrPipeline(translationService: aiTranslationService),
      resolvePagePath: _resolveOcrPagePath,
      resolveTargetLanguage:
          () => Localizations.localeOf(context).toLanguageTag(),
    );

    _fullScreenReaction = reaction((_) => fullScreenStore.fullscreen, (
      bool isFullscreen,
    ) {
      if (isFullscreen) {
        _sidebarVisibleBeforeFullscreen = _sidebarVisible;
        if (_showMangaOcr) _ocrSession.close();
        setState(() {
          _sidebarVisible = false;
          if (_showMangaOcr) {
            _sidebarOverlay = _IllustSidebarOverlay.none;
          }
        });
      } else {
        setState(() {
          _sidebarVisible = _sidebarVisibleBeforeFullscreen;
        });
      }
    });

    super.initState();
  }

  // 处理滚动观察回调，更新当前页数
  void _onObserve(ListViewObserveModel observeModel) {
    final illusts = _illustStore.illusts;
    if (illusts == null || illusts.pageCount <= 1) {
      if (_illustStore.currentPage != 0 || _illustStore.totalPages != 1) {
        _illustStore.updateTotalPages(1);
        _illustStore.updateCurrentPage(0);
      }
      return;
    }

    // 更新总页数
    if (_illustStore.totalPages != illusts.pageCount) {
      _illustStore.updateTotalPages(illusts.pageCount);
    }

    // 选择实际可见高度最大的页面，避免下一页刚露出边缘时过早切换。
    final visiblePages = observeModel.displayingChildModelList;
    final previousOffset = _lastOcrObserveOffset;
    _lastOcrObserveOffset = observeModel.scrollOffset;
    if (previousOffset != null && observeModel.scrollOffset != previousOffset) {
      _ocrScrollForward = observeModel.scrollOffset > previousOffset;
    }
    _visibleOcrPages = visiblePages.map((item) => item.index).toSet();
    final firstVisibleIndex =
        visiblePages.isEmpty
            ? observeModel.firstChild?.index ?? 0
            : visiblePages
                .reduce(
                  (current, next) =>
                      next.visibleMainAxisSize > current.visibleMainAxisSize
                          ? next
                          : current,
                )
                .index;

    if (firstVisibleIndex != _illustStore.currentPage) {
      _illustStore.updateCurrentPage(firstVisibleIndex);
      _ocrSession.setCurrentPage(firstVisibleIndex, schedule: false);
    }
    _scheduleVisibleOcrPages();
  }

  @override
  void didUpdateWidget(covariant IllustRowPage oldWidget) {
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
        _scrollController.hasClients &&
        _aboutStore.illusts.isEmpty &&
        !_aboutStore.fetching)
      _aboutStore.next();
  }

  @override
  void dispose() {
    _illustStore.dispose();
    _scrollController.dispose();
    _photoScrollController.dispose();
    _autoScrollTicker?.dispose();
    _focusNode.dispose();
    _refreshController.dispose();
    _fullScreenReaction?.call();
    _ocrSession.dispose();
    super.dispose();
  }

  void _toggleFullScreen() {
    fullScreenStore.toggle();
  }

  Future<void> _toggleImageDisplayMode() async {
    final target =
        _illustStore.displayMode == OriginalDisplayMode.downloaded
            ? OriginalDisplayMode.originalPreferred
            : OriginalDisplayMode.downloaded;
    final targetIndex = await _illustStore.selectDisplayMode(target);
    if (mounted) {
      await _observerController.animateTo(
        index: targetIndex,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _removeAllOriginals() async {
    final sets = List<OriginalImageSet>.from(_illustStore.originalSets);
    if (sets.isEmpty) return;
    final imageCount = sets.fold<int>(0, (sum, set) => sum + set.imageCount);
    final totalBytes = sets.fold<int>(0, (sum, set) => sum + set.totalFileSize);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('删除原图及关联'),
            content: Text(
              '将删除 ${sets.length} 个原图版本、$imageCount 张原图和全部页面映射（${_formatBytes(totalBytes)}）。\n\n下载图不会受到影响；之后如需原图，需要重新导入。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除原图'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      for (final set in sets) {
        await downloadStore.originalRepository.removeSetSafely(set.id!);
      }
      if (!mounted) return;
      if (_illustStore.illusts?.id.isNegative == true) {
        Navigator.of(context).pop();
        return;
      }
      final targetIndex = await _illustStore.reloadAfterOriginalRemoved();
      if (mounted) {
        await _observerController.animateTo(
          index: targetIndex,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('原图及页面映射已删除，可重新导入')));
      }
    } catch (e, stackTrace) {
      Log.e('横向详情页删除原图失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除原图失败：$e')));
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }

  List<IllustDownloadMenuAction> _originalMenuActions() {
    if (!_illustStore.hasOriginal) return const [];
    return [
      IllustDownloadMenuAction(
        icon: Icons.folder_copy_outlined,
        title: '打开原图目录',
        onTap: _openOriginalDirectory,
      ),
      IllustDownloadMenuAction(
        icon:
            _illustStore.displayMode == OriginalDisplayMode.downloaded
                ? Icons.hd_outlined
                : Icons.download_outlined,
        title:
            _illustStore.displayMode == OriginalDisplayMode.downloaded
                ? '切换到原图优先'
                : '切换到下载版',
        onTap: _toggleImageDisplayMode,
      ),
      IllustDownloadMenuAction(
        icon: Icons.delete_sweep_outlined,
        title: '删除原图及关联',
        color: Colors.redAccent,
        onTap: _removeAllOriginals,
      ),
    ];
  }

  Future<void> _openOriginalDirectory() async {
    final set = await downloadStore.originalRepository.getDefaultSet(widget.id);
    if (set == null) return;
    try {
      await FileUtils.openFileOrDirectory(
        downloadStore.dbProvider.getOriginalAbsolutePath(set.relativePath),
      );
    } catch (e, stackTrace) {
      Log.e('横向详情页打开原图目录失败', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开原图目录失败：$e')));
      }
    }
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
              Observer(
                builder: (context) {
                  return fullScreenStore.canFullScreen &&
                          fullScreenStore.fullscreen
                      ? IconButton(
                        icon: Icon(Icons.fullscreen_exit),
                        tooltip: '退出全屏',
                        onPressed: _toggleFullScreen,
                      )
                      : CommonBackArea();
                },
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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

  Future<String?> _resolveOcrPagePath(int pageIndex) async {
    final illust = _illustStore.illusts;
    if (illust == null || pageIndex < 0) return null;
    final localPath = _illustStore.getLocalImageInfo(pageIndex)?.path;
    String imageUrl = '';
    if (pageIndex < illust.pageCount) {
      if (illust.pageCount == 1 && pageIndex == 0) {
        imageUrl =
            illust.type == 'manga'
                ? illust.managaDetailUrl
                : illust.illustDetailUrl;
      } else {
        imageUrl =
            illust.type == 'manga'
                ? illust.managaDetailImageUrl(pageIndex)
                : illust.illustDetailImageUrl(pageIndex);
      }
    }
    return _ocrImageResolver.resolve(localPath: localPath, imageUrl: imageUrl);
  }

  void _openMangaOcr() {
    if (_illustStore.illusts == null) return;
    if (fullScreenStore.fullscreen) fullScreenStore.setFullScreen(false);
    setState(() {
      _sidebarVisible = true;
      _sidebarOverlay = _IllustSidebarOverlay.mangaOcr;
    });
    _ocrSession.open(_illustStore.currentPage);
  }

  void _startMangaOcr() {
    _ocrSession.requestCurrent();
    _scheduleVisibleOcrPages();
  }

  void _setMangaOcrAutoFollow(bool value) {
    _ocrSession.setAutoFollowEnabled(value);
    if (value) _scheduleVisibleOcrPages();
  }

  void _scheduleVisibleOcrPages() {
    if (!_showMangaOcr ||
        !_ocrSession.panelActive ||
        !_ocrSession.hasStarted ||
        !_ocrSession.autoFollowEnabled) {
      return;
    }
    // 页面进入视口后立即排队；路径解析器会等待同一个缓存文件可读，随后
    // 直接开始 OCR，不依赖 Flutter 图片组件完成绘制。
    _ocrSession.requestReadyVisiblePages(
      _visibleOcrPages,
      forward: _ocrScrollForward,
    );
  }

  void _closeSidebarOverlay() {
    if (_sidebarOverlay == _IllustSidebarOverlay.mangaOcr) {
      _ocrSession.close();
    }
    setState(() => _sidebarOverlay = _IllustSidebarOverlay.none);
  }

  void _openComments() {
    if (_showMangaOcr) _ocrSession.close();
    setState(() {
      _sidebarVisible = true;
      _sidebarOverlay = _IllustSidebarOverlay.comments;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PopScope(
      canPop: _sidebarOverlay == _IllustSidebarOverlay.none,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_sidebarOverlay != _IllustSidebarOverlay.none) {
          _closeSidebarOverlay();
        }
      },
      child: Scaffold(
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
                  _buildAppbar(),
                ],
              ),
            );
          },
        ),
      ),
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
      child: Observer(
        builder: (context) {
          // 更新总页数
          if (data.pageCount > 1) {
            // 使用 runInAction 确保在 observer 外部更新状态
            if (_illustStore.totalPages != data.pageCount) {
              Future.microtask(
                () => _illustStore.updateTotalPages(data.pageCount),
              );
            }
          } else {
            if (_illustStore.totalPages != 1 || _illustStore.currentPage != 0) {
              Future.microtask(() {
                _illustStore.updateTotalPages(1);
                _illustStore.updateCurrentPage(0);
              });
            }
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
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (_showComments) {
                        _closeSidebarOverlay();
                      }
                    },
                    onDoubleTap: () {
                      // 双击切换侧边栏显示/隐藏
                      if (_sidebarVisible && _showMangaOcr) {
                        _ocrSession.close();
                      }
                      setState(() {
                        _sidebarVisible = !_sidebarVisible;
                        if (!_sidebarVisible) {
                          _sidebarOverlay = _IllustSidebarOverlay.none;
                        }
                      });
                    },
                    child: Focus(
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
                          // 检测快速滑动
                          // - 如果未开启自动滚动,向下快速滑动可启动
                          // - 如果已开启自动滚动,向上快速滑动可停止
                          _checkFlingGesture();
                        },
                        onPointerCancel: (_) {
                          if (_isAutoScrolling &&
                              _autoScrollTicker != null &&
                              !_autoScrollTicker!.isActive) {
                            _resumeAutoScrollAfterInertia();
                          }
                          // 检测快速滑动
                          _checkFlingGesture();
                        },
                        child:
                            data.type == "ugoira"
                                ? // 动图：直接居中显示，不使用 CustomScrollView
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    return Center(
                                      child: NullHero(
                                        tag: widget.heroString,
                                        child: UgoiraLoader(
                                          id: widget.id,
                                          illusts: data,
                                          illustStore: _illustStore,
                                          constraintSize: Size(
                                            constraints.maxWidth,
                                            constraints.maxHeight,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                )
                                : // 普通图片：使用 CustomScrollView
                                ListViewObserver(
                                  controller: _observerController,
                                  onObserve: _onObserve,
                                  child: CustomScrollView(
                                    controller: _photoScrollController,
                                    slivers: [
                                      ..._buildPhotoList(
                                        data,
                                        centerType,
                                        height,
                                      ),
                                      SliverToBoxAdapter(
                                        child: Container(
                                          height:
                                              MediaQuery.of(
                                                context,
                                              ).padding.bottom,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                      ),
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
                              onCommentClick: () {
                                _openComments();
                              },
                            ),
                          ),
                          _buildRecom(),
                        ],
                      ),
                    ),
                  ),
                ),
                // OCR 与翻译侧边栏，与评论一样覆盖在作品详情之上。
                AnimatedPositioned(
                  duration: animationDuration,
                  curve: Curves.easeInOut,
                  right: (_sidebarVisible && _showMangaOcr) ? 0 : -sidebarWidth,
                  top: 0,
                  bottom: 0,
                  width: sidebarWidth,
                  child: AnimatedBuilder(
                    animation: _ocrSession,
                    builder: (context, _) {
                      return MangaOcrSidePanel(
                        key: ValueKey(_ocrSession.currentPage),
                        controller: _ocrSession.currentController,
                        title: '漫画 OCR 与翻译',
                        pageLabel:
                            '第 ${_ocrSession.currentPage + 1} / ${_illustStore.totalPages} 页',
                        autoFollowEnabled: _ocrSession.autoFollowEnabled,
                        onAutoFollowChanged: _setMangaOcrAutoFollow,
                        recognitionStarted: _ocrSession.hasStarted,
                        onStart: _startMangaOcr,
                        onClose: _closeSidebarOverlay,
                        onCancel: _ocrSession.cancelCurrent,
                        onRetryTranslation:
                            () => _ocrSession.requestCurrent(
                              forceTranslation: true,
                            ),
                        onForceOcr:
                            () => _ocrSession.requestCurrent(forceOcr: true),
                      );
                    },
                  ),
                ),
                // 评论侧边栏，覆盖在详情侧边栏之上
                AnimatedPositioned(
                  duration: animationDuration,
                  curve: Curves.easeInOut,
                  right: (_sidebarVisible && _showComments) ? 0 : -sidebarWidth,
                  top: 0,
                  bottom: 0,
                  width: sidebarWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                    ),
                    clipBehavior:
                        Clip.hardEdge, // Ensure overlay doesn't bleed out
                    child: CommentPage(
                      id: data.id,
                      embedded: true,
                      onBack: () {
                        _closeSidebarOverlay();
                      },
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
                      child: Container(width: dividerWidth),
                    ),
                  ),
                // 跳转到上次阅读位置提示
                Positioned(
                  bottom: 60, // 在页数指示器上方
                  left: 10,
                  child: Observer(builder: (_) => _buildJumpHint()),
                ),
                // 页数指示器及全屏按钮
                Positioned(
                  bottom: 20,
                  left: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (data.pageCount > 1)
                        Observer(builder: (_) => _buildPageIndicator()),
                      if (Platform.isMacOS || Platform.isWindows) ...[
                        if (data.pageCount > 1) const SizedBox(width: 8),
                        _buildMangaOcrButton(),
                      ],
                      if (fullScreenStore.canFullScreen) ...[
                        if (data.pageCount > 1 ||
                            Platform.isMacOS ||
                            Platform.isWindows)
                          const SizedBox(width: 8),
                        _buildFullScreenButton(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.f11) {
        _toggleFullScreen();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (fullScreenStore.fullscreen) {
          fullScreenStore.setFullScreen(false);
          return KeyEventResult.handled;
        }
        if (_sidebarOverlay != _IllustSidebarOverlay.none) {
          _closeSidebarOverlay();
          return KeyEventResult.handled;
        }
      }
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
          targetOffset = (currentOffset - scrollDistance).clamp(
            0.0,
            position.maxScrollExtent,
          );
        } else {
          // 向下滚动
          targetOffset = (currentOffset + scrollDistance).clamp(
            0.0,
            position.maxScrollExtent,
          );
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

  // 等待惯性滚动结束后再恢复自动滚动
  void _resumeAutoScrollAfterInertia() {
    if (!_photoScrollController.hasClients) return;

    // 使用 ScrollPosition 的 isScrollingNotifier 来监听滚动状态
    final position = _photoScrollController.position;

    void checkAndResume() {
      // 确保监听器只执行一次
      position.isScrollingNotifier.removeListener(checkAndResume);

      // 如果滚动已停止且仍处于自动滚动模式，则恢复
      if (!position.isScrollingNotifier.value &&
          _isAutoScrolling &&
          _autoScrollTicker != null &&
          !_autoScrollTicker!.isActive) {
        _autoScrollTicker!.start();
      }
    }

    // 如果当前正在滚动（惯性滚动），则等待停止
    if (position.isScrollingNotifier.value) {
      position.isScrollingNotifier.addListener(checkAndResume);
    } else {
      // 如果已经停止，直接恢复
      if (_autoScrollTicker != null && !_autoScrollTicker!.isActive) {
        _autoScrollTicker!.start();
      }
    }
  }

  // 检测快速滑动手势
  // - 向下快速滑动：如果未开启自动滚动，则自动启动
  // - 向上快速滑动：如果已开启自动滚动，则自动停止
  void _checkFlingGesture() async {
    if (!_photoScrollController.hasClients) return;

    final position = _photoScrollController.position;

    // 等待 50ms 让惯性滚动开始
    await Future.delayed(Duration(milliseconds: 50));

    if (!mounted || !_photoScrollController.hasClients) return;
    if (!position.isScrollingNotifier.value) return; // 没有惯性滚动

    final startPos = position.pixels;

    // 再等待 50ms 来计算速度
    await Future.delayed(Duration(milliseconds: 50));

    if (!mounted || !_photoScrollController.hasClients) return;
    final endPos = _photoScrollController.position.pixels;

    // 计算速度：像素/秒（正值表示向下，负值表示向上）
    final velocity = (endPos - startPos) / 0.05; // 50ms = 0.05s

    // ========== 速度阈值配置 ==========
    // 向下滚动速度阈值（单位：像素/秒）
    // 当用户快速向下滑动并松手后，如果惯性滚动速度超过此值，则自动启动自动滚动模式
    // 建议值范围：300.0 ~ 1500.0
    const double downwardVelocityThreshold = 1000.0;

    // 向上滚动速度阈值（单位：像素/秒，取绝对值）
    // 当用户快速向上滑动并松手后，如果惯性滚动速度超过此值，则自动停止自动滚动模式
    // 建议值范围：300.0 ~ 1500.0
    const double upwardVelocityThreshold = 800.0;
    // ================================

    if (velocity > downwardVelocityThreshold && !_isAutoScrolling) {
      // 向下快速滑动且未开启自动滚动 → 启动自动滚动
      // 等待惯性滚动结束后再启动，避免速度突变
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
      // 向上快速滑动且已开启自动滚动 → 停止自动滚动
      _stopAutoScroll();
    }
  }

  void _showSpeedControl(RenderBox button) {
    if (_isAutoScrolling) {
      // 保持滚动，不停止
    }
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final double menuWidth = 80.0;
    final double menuHeight = 200.0;

    // 获取按钮在全局坐标中的位置和大小
    final buttonPosition = button.localToGlobal(Offset.zero);
    final buttonSize = button.size;

    // 计算菜单应该出现的位置（在按钮正上方，水平居中）
    final menuGlobalPosition = Offset(
      buttonPosition.dx + (buttonSize.width - menuWidth) / 2, // 水平居中对齐按钮
      buttonPosition.dy - menuHeight - 30, // 菜单底部在按钮上方30px
    );

    // 转换为 overlay 的本地坐标
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
                    // 使用 RotatedBox 将 Slider 旋转 90 度，使其垂直显示
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3, // 逆时针旋转 270 度（3 个 90 度）
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

  Widget _buildJumpHint() {
    if (!_illustStore.showJumpHint) return const SizedBox.shrink();
    return AnimatedOpacity(
      opacity: _illustStore.showJumpHint ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Material(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
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

  Widget _buildFullScreenButton() {
    return Observer(
      builder: (context) {
        return Material(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(20),
            onTap: _toggleFullScreen,
            child: Container(
              padding: EdgeInsets.all(8),
              child: Icon(
                fullScreenStore.fullscreen
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMangaOcrButton() {
    return AnimatedBuilder(
      animation: _ocrSession,
      builder: (context, _) {
        final controller = _ocrSession.currentController;
        final active = _showMangaOcr;
        final color =
            controller.stage == MangaOcrStage.failed
                ? Colors.orangeAccent
                : active || controller.result != null
                ? Theme.of(context).colorScheme.primary
                : Colors.white;
        return Tooltip(
          message: active ? '关闭 OCR 与翻译' : '识别并翻译当前页',
          child: Material(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(20),
              onTap: active ? _closeSidebarOverlay : _openMangaOcr,
              child: SizedBox(
                width: 30,
                height: 30,
                child: Center(
                  child:
                      controller.isRunning
                          ? SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: controller.progress,
                              color: color,
                            ),
                          )
                          : Icon(
                            controller.stage == MangaOcrStage.failed
                                ? Icons.error_outline
                                : Icons.translate,
                            color: color,
                            size: 16,
                          ),
                ),
              ),
            ),
          ),
        );
      },
    );
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
              // 直接使用 Observer 的 context 获取按钮的 RenderBox
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

  Widget _buildRecom() {
    return IllustRecommendGrid(
      illusts: _aboutStore.illusts,
      currentIllustStore: _illustStore,
      showLongPressConfirm: false,
      memCacheWidth: 480,
    );
  }

  List<Widget> _buildPhotoList(Illusts data, bool centerType, double height) {
    return [
      // 动图已经在上一层单独处理，这里只处理普通图片
      if (data.type != "ugoira")
        data.pageCount == 1
            ? (centerType
                ? SliverFillRemaining(child: _buildPicture(data, height))
                : SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return _buildPicture(data, height);
                  }, childCount: 1),
                ))
            : SliverList(
              delegate: SliverChildBuilderDelegate((
                BuildContext context,
                int index,
              ) {
                return InkWell(
                  onTap: () {
                    // 点击左侧区域关闭评论区
                    if (_showComments) {
                      _closeSidebarOverlay();
                    }
                  },
                  onLongPress: () {
                    _pressSave(data, index);
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

  Widget _buildPicture(Illusts data, double height) {
    return Center(
      child: Builder(
        builder: (BuildContext context) {
          String url = data.illustDetailUrl;
          if (data.type == "manga") {
            url = data.managaDetailUrl;
          }

          // 计算建议的质量标识，以匹配 IllustCard 的缓存键
          String quality = userSetting.previewQuality;

          Widget placeWidget = Container(height: height);
          // 移除单独图片项的点击行为，统一通过 InkWell 处理点击关闭评论逻辑
          return InkWell(
            onTap: () {
              // 点击左侧区域关闭评论区
              if (_showComments) {
                _closeSidebarOverlay();
              }
            },
            onLongPress: () {
              _pressSave(data, 0);
            },
            child: _withMangaOcrOverlay(
              index: 0,
              child: NullHero(
                tag: widget.heroString,
                child: PixivImage(
                  url,
                  localImageInfo: _illustStore.getLocalImageInfo(0),
                  fade: false,
                  placeWidget:
                      (url != data.previewUrl)
                          ? PixivImage(
                            data.previewUrl,
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
            ),
          );
        },
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
      // 多页插图/漫画的第一页通常在列表中显示的是 previewUrl
      placeholderUrl =
          index == 0
              ? illust.previewUrl
              : illust.metaPages[index].imageUrls!.squareMedium;
      usePlaceholder = index == 0 ? userSetting.mangaQuality >= 1 : false;

      // 如果不是第一页且使用 squareMedium，更新质量标识
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
      localImageInfo: _illustStore.getLocalImageInfo(index),
      placeWidget:
          usePlaceholder
              ? PixivImage(
                placeholderUrl,
                fade: false,
                fit: BoxFit.contain,
                httpHeaders: {'cover': '${illust.id}', 'quality': quality},
                memCacheWidth: 480,
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
    return _withMangaOcrOverlay(index: index, child: child);
  }

  Widget _withMangaOcrOverlay({required int index, required Widget child}) {
    return AnimatedBuilder(
      animation: _ocrSession,
      child: child,
      builder: (context, image) {
        if (!_showMangaOcr || _ocrSession.currentPage != index) return image!;
        final controller = _ocrSession.currentController;
        final result = controller.result;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            image!,
            if (result != null)
              Positioned.fill(
                child: MangaOcrOverlay(
                  result: result,
                  selectedBlockId: controller.selectedBlockId,
                  onSelected: controller.selectBlock,
                ),
              ),
          ],
        );
      },
    );
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
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          text: "#${f.name}",
          children: [
            TextSpan(text: " ", style: Theme.of(context).textTheme.bodySmall),
            TextSpan(
              text: "${f.translatedName ?? "~"}",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            color: Theme.of(context).colorScheme.secondary,
          ),
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
                              color:
                                  userStore!.isFollow
                                      ? Colors.yellow
                                      : Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Hero(
                          tag:
                              illust.user.profileImageUrls.medium +
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
                                ),
                              );
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
              padding: EdgeInsets.all(8.0),
            ),
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
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ),
                    Container(height: 4.0),
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
      },
    );
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
                  if (userSetting.starAfterSave && (_illustStore.state == 0)) {
                    _illustStore.star(
                      restrict:
                          userSetting.defaultPrivateLike ? "private" : "public",
                    );
                  }
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
                        Navigator.of(context).pop();
                        _showIllustInfoDialog(context, illusts);
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

  void _showPriorityDialog() {
    showDialog(
      context: context,
      builder:
          (context) => BookmarkPriorityDialog(
            onPrioritySelected: (priority) {
              if (userSetting.saveAfterStar && (_illustStore.state == 0)) {
                downloadStore.downloadIllust(
                  _illustStore.illusts!,
                  bookmark: priority,
                );
              }
              _illustStore.star(
                restrict: userSetting.defaultPrivateLike ? "private" : "public",
                bookmark: priority,
                force: true, // 强制更新，即使已收藏也应用新优先级
              );
            },
          ),
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
              additionalMenuActions: _originalMenuActions(),
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
          onLongPress: _showPriorityDialog,
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
                downloadStore.downloadIllust(
                  _illustStore.illusts!,
                  bookmark: 1,
                );
              }
              _illustStore.star(
                restrict: userSetting.defaultPrivateLike ? "private" : "public",
                bookmark: userSetting.saveAfterStar ? 1 : null,
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

  Future<void> _showIllustInfoDialog(
    BuildContext context,
    Illusts illust,
  ) async {
    // 在显示对话框前先获取 i18n，避免在对话框中无法获取 context 的问题
    final cancelText = I18n.of(context).cancel;
    return showDialog(
      context: context,
      useRootNavigator: false,
      builder:
          (context) => IllustInfoDialog(
            illust: illust,
            cancelText: cancelText,
            ugoiraMetadata: _illustStore.ugoiraMetadata,
          ),
    );
  }

  @override
  bool get wantKeepAlive => false;
}

class IllustInfoDialog extends StatefulWidget {
  final Illusts illust;
  final String cancelText;
  final UgoiraMetadataResponse? ugoiraMetadata;

  const IllustInfoDialog({
    Key? key,
    required this.illust,
    required this.cancelText,
    this.ugoiraMetadata,
  }) : super(key: key);

  @override
  State<IllustInfoDialog> createState() => _IllustInfoDialogState();
}

class _IllustInfoDialogState extends State<IllustInfoDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    final hasUgoiraMetadata = widget.ugoiraMetadata != null;
    _tabController = TabController(
      length: hasUgoiraMetadata ? 2 : 1,
      vsync: this,
    );
    super.initState();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 生成原来的复制信息
    final shareInfo =
        'title:${widget.illust.title}\npainter:${widget.illust.user.name}\nillust id:${widget.illust.id}';

    // 生成 JSON 格式的插画信息
    final jsonData = jsonEncode(widget.illust.toJson());
    final formattedJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(widget.illust.toJson());

    // 生成动图 metadata JSON（如果有）
    final hasUgoiraMetadata = widget.ugoiraMetadata != null;
    String ugoiraMetadataJson = '';
    String formattedUgoiraMetadataJson = '';
    if (hasUgoiraMetadata) {
      ugoiraMetadataJson = jsonEncode(widget.ugoiraMetadata!.toJson());
      formattedUgoiraMetadataJson = const JsonEncoder.withIndent(
        '  ',
      ).convert(widget.ugoiraMetadata!.toJson());
    }

    return AlertDialog(
      title: Text('插画信息'),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
            maxWidth: 800,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tab bar
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: 'Illust'),
                  if (hasUgoiraMetadata) Tab(text: 'Ugoira Metadata'),
                ],
              ),
              SizedBox(height: 8),
              // Tab bar view
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Illust Tab
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 原来的复制信息
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '复制信息:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Spacer(),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(text: shareInfo),
                                      );
                                      BotToast.showText(text: '已复制');
                                    },
                                    child: Icon(Icons.copy, size: 16),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              SelectionArea(
                                child: Text(
                                  shareInfo,
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
                        // JSON 数据
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'JSON 数据:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Spacer(),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(text: jsonData),
                                      );
                                      BotToast.showText(text: '已复制全部');
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '复制全部',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        SizedBox(width: 4),
                                        Icon(Icons.copy_all, size: 16),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: JsonHighlighter(json: formattedJson),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Ugoira Metadata Tab
                    if (hasUgoiraMetadata)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Ugoira Metadata:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Spacer(),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(
                                    ClipboardData(text: ugoiraMetadataJson),
                                  );
                                  BotToast.showText(text: '已复制');
                                },
                                child: Icon(Icons.copy, size: 16),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              child: JsonHighlighter(
                                json: formattedUgoiraMetadataJson,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelText),
        ),
      ],
    );
  }
}
