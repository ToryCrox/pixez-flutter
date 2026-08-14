import 'dart:async';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:pixez/clipboard_plugin.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/manga_ocr/manga_ocr_controller.dart';
import 'package:pixez/manga_ocr/manga_page_image_resolver.dart';
import 'package:pixez/manga_ocr/manga_ocr_pipeline.dart';
import 'package:pixez/manga_ocr/manga_ocr_widgets.dart';
import 'package:pixez/manga_ocr/manga_ocr_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;

class PhotoZoomPage extends StatefulWidget {
  final int index;
  final Illusts illusts;
  final IllustStore illustStore;
  final bool initiallyOpenMangaOcr;

  const PhotoZoomPage({
    Key? key,
    required this.index,
    required this.illusts,
    required this.illustStore,
    this.initiallyOpenMangaOcr = false,
  }) : super(key: key);

  @override
  _PhotoZoomPageState createState() => _PhotoZoomPageState();
}

class _PhotoZoomPageState extends State<PhotoZoomPage> {
  late Illusts _illusts;
  int _index = 0;
  Map<int, String?> _localPaths = {};
  late final MangaOcrController _ocrController;
  final MangaPageImageResolver _ocrImageResolver =
      const PixivMangaPageImageResolver();
  bool _ocrPanelVisible = false;

  int get _pageCount => widget.illustStore.displayPageCount;

  String _urlFor(int index) {
    if (_illusts.pageCount == 1 && index == 0) {
      return _loadSource
          ? (_illusts.metaSinglePage?.originalImageUrl ??
              _illusts.imageUrls.large)
          : _illusts.imageUrls.large;
    }
    if (index >= 0 && index < _illusts.metaPages.length) {
      return _loadSource
          ? _illusts.metaPages[index].imageUrls!.original
          : _illusts.metaPages[index].imageUrls!.large;
    }
    return '';
  }

  @override
  void initState() {
    _ocrController = MangaOcrController(
      MangaOcrPipeline(translationService: aiTranslationService),
    );
    _loadSource = userSetting.zoomQuality == 1;
    _illusts = widget.illusts;
    _index = widget.index;
    for (var i = 0; i < _pageCount; i++) {
      _localPaths[i] = widget.illustStore.getLocalImageInfo(i)?.path;
    }
    nowUrl = _urlFor(_index);

    super.initState();
    initCache();
    _loadLocalPaths();
    if (widget.initiallyOpenMangaOcr &&
        (Platform.isMacOS || Platform.isWindows)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openOcrPanel();
      });
    }
  }

  Future<void> _loadLocalPaths() async {
    if (!downloadStore.isInitialized) return;

    final localPaths = <int, String?>{};
    for (int i = 0; i < _pageCount; i++) {
      localPaths[i] = await _resolveLocalPath(i);
    }
    if (mounted) {
      setState(() {
        _localPaths.addAll(localPaths);
      });
    }
  }

  Future<String?> _resolveLocalPath(int pageIndex) async {
    var localPath =
        _localPaths[pageIndex] ??
        widget.illustStore.getLocalImageInfo(pageIndex)?.path;
    if (localPath != null && await File(localPath).exists()) {
      return localPath;
    }
    if (downloadStore.isInitialized) {
      return downloadStore.getLocalImagePath(_illusts.id, pageIndex);
    }
    return localPath;
  }

  ImageProvider _getImageProvider(int index, String url) {
    // 优先使用本地文件
    final localPath = _localPaths[index];
    if (localPath != null) {
      final file = File(localPath);
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    // 回退到网络
    return CachedNetworkImageProvider(
      url,
      headers: Hoster.header(url: url),
      cacheManager: pixivCacheManager,
    );
  }

  @override
  void dispose() {
    if (_ocrController.isRunning) unawaited(_ocrController.cancel());
    _ocrController.dispose();
    if (_fullScreen)
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    super.dispose();
  }

  initCache() async {
    final localPath = await _resolveLocalPath(_index);
    if (localPath != null && await File(localPath).exists()) {
      if (mounted) {
        setState(() {
          _localPaths[_index] = localPath;
          shareShow = true;
        });
      }
      return;
    }
    if (nowUrl.isEmpty) {
      if (mounted) setState(() => shareShow = _localPaths[_index] != null);
      return;
    }
    var fileInfo = await pixivCacheManager.getFileFromCache(nowUrl);
    if (mounted)
      setState(() {
        shareShow = fileInfo != null;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        if (_pageCount == 1) {
          final url = _urlFor(0);
          return Scaffold(
            extendBody: true,
            extendBodyBehindAppBar: true,
            backgroundColor: Colors.black,
            bottomNavigationBar: _buildBottom(context),
            body: Stack(
              children: [
                PhotoView(
                  filterQuality: FilterQuality.high,
                  initialScale: PhotoViewComputedScale.contained,
                  heroAttributes: PhotoViewHeroAttributes(tag: url),
                  imageProvider: _getImageProvider(0, url),
                  loadingBuilder: (context, event) => _buildLoading(event),
                  backgroundDecoration: BoxDecoration(color: Colors.black),
                  onTapUp: (context, details, controllerValue) {
                    // 点击图片区域时关闭页面
                    // 如果图片未缩放或缩放比例很小，点击时关闭
                    if (controllerValue.scale != null &&
                        controllerValue.scale! <= 1.0) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                // 左上角关闭按钮
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 8,
                  child: SafeArea(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ..._buildOcrLayers(),
              ],
            ),
          );
        } else {
          return Scaffold(
            extendBody: true,
            bottomNavigationBar: _buildBottom(context),
            extendBodyBehindAppBar: true,
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                PhotoViewGallery.builder(
                  scrollPhysics: const BouncingScrollPhysics(),
                  pageController: PageController(initialPage: _index),
                  builder: (BuildContext context, int index) {
                    final url = _urlFor(index);
                    return PhotoViewGalleryPageOptions(
                      imageProvider: _getImageProvider(index, url),
                      initialScale: PhotoViewComputedScale.contained,
                      heroAttributes: PhotoViewHeroAttributes(tag: url),
                      filterQuality: FilterQuality.high,
                      onTapUp: (context, details, controllerValue) {
                        // 点击图片区域时关闭页面
                        // 如果图片未缩放或缩放比例很小，点击时关闭
                        if (controllerValue.scale != null &&
                            controllerValue.scale! <= 1.0) {
                          Navigator.of(context).pop();
                        }
                      },
                    );
                  },
                  itemCount: _pageCount,
                  onPageChanged: (index) async {
                    nowUrl = _urlFor(index);
                    setState(() {
                      _index = index;
                      shareShow = false;
                    });
                    _ocrController.clearForPageChange();
                    var file = await pixivCacheManager.getFileFromCache(nowUrl);
                    if (file != null && mounted)
                      setState(() {
                        shareShow = true;
                      });
                  },
                  loadingBuilder: (context, event) => _buildLoading(event),
                ),
                // 左上角关闭按钮
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 8,
                  child: SafeArea(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ..._buildOcrLayers(),
              ],
            ),
          );
        }
      },
    );
  }

  String nowUrl = "";

  bool show = false;
  bool shareShow = false;
  bool _loadSource = false;
  bool _fullScreen = false;

  List<Widget> _buildOcrLayers() {
    if (!_ocrPanelVisible) return const [];
    return [
      AnimatedBuilder(
        animation: _ocrController,
        builder: (context, _) {
          final result = _ocrController.result;
          if (result == null) return const SizedBox.shrink();
          return Positioned.fill(
            right: MediaQuery.of(context).size.width > 700 ? 420 : 0,
            child: MangaOcrOverlay(
              result: result,
              selectedBlockId: _ocrController.selectedBlockId,
              onSelected: _ocrController.selectBlock,
            ),
          );
        },
      ),
      Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        width: MediaQuery.of(context).size.width.clamp(280, 420).toDouble(),
        child: MangaOcrSidePanel(
          controller: _ocrController,
          onClose: () => setState(() => _ocrPanelVisible = false),
          onRetryTranslation: () => _startOcr(forceTranslation: true),
          onForceOcr: () => _startOcr(forceOcr: true),
        ),
      ),
    ];
  }

  Future<void> _openOcrPanel() async {
    setState(() => _ocrPanelVisible = true);
    if (_ocrController.result == null && !_ocrController.isRunning) {
      await _startOcr();
    }
  }

  Future<void> _startOcr({
    bool forceOcr = false,
    bool forceTranslation = false,
  }) async {
    final pageIndex = _index;
    final imageUrl = _urlFor(pageIndex);
    final targetLanguage = Localizations.localeOf(context).toLanguageTag();
    final preferences = await MangaOcrPreferences.load();
    final localPath = await _resolveLocalPath(pageIndex);
    if (mounted && localPath != null && _localPaths[pageIndex] != localPath) {
      setState(() => _localPaths[pageIndex] = localPath);
    }
    final imagePath = await _ocrImageResolver.resolve(
      localPath: localPath,
      imageUrl: imageUrl,
    );
    if (imagePath == null) {
      _ocrController.clearForPageChange();
      return;
    }
    if (!mounted || _index != pageIndex) return;
    await _ocrController.analyze(
      imagePath: imagePath,
      pageIndex: pageIndex,
      targetLanguage: targetLanguage,
      forceOcr: forceOcr,
      forceTranslation: forceTranslation,
      detectorId: preferences.detectorId,
      recognizerId: preferences.recognizerId,
      options: preferences.options,
    );
  }

  Widget _buildBottom(BuildContext context) {
    if (_fullScreen) {
      return BottomAppBar(
        color: Colors.transparent,
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _fullScreen = false;
                });
                SystemChrome.setEnabledSystemUIMode(
                  SystemUiMode.manual,
                  overlays: SystemUiOverlay.values,
                );
              },
              icon: Icon(
                Icons.fullscreen_exit,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }
    return BottomAppBar(
      color: Colors.transparent,
      child: Visibility(
        visible: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                IconButton(
                  iconSize: 16,
                  icon: Icon(Icons.photo_library_outlined, color: Colors.white),
                  onPressed: () {},
                ),
                Text(
                  "${_index + 1}/$_pageCount",
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge!.copyWith(color: Colors.white),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () async {
                    Navigator.of(context).pop();
                  },
                ),
                if (Platform.isMacOS || Platform.isWindows)
                  IconButton(
                    tooltip: '识别并翻译当前页',
                    icon: const Icon(
                      Icons.document_scanner_outlined,
                      color: Colors.white,
                    ),
                    onPressed: _openOcrPanel,
                  ),
                IconButton(
                  icon: Icon(Icons.fullscreen, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _fullScreen = true;
                    });
                    SystemChrome.setEnabledSystemUIMode(
                      SystemUiMode.manual,
                      overlays: [],
                    );
                  },
                ),
                if (ClipboardPlugin.supported && !_illusts.id.isNegative)
                  IconButton(
                    icon: Icon(Icons.copy, color: Colors.white),
                    onPressed: () async {
                      final url = ClipboardPlugin.getImageUrl(_illusts, _index);
                      if (url == null) return;

                      ClipboardPlugin.showToast(
                        context,
                        ClipboardPlugin.copyImageFromUrl(url),
                      );
                    },
                  ),
                if (!_illusts.id.isNegative)
                  GestureDetector(
                    child: IconButton(
                      icon: Icon(Icons.save_alt, color: Colors.white),
                      onPressed: () {
                        final part = widget.illustStore
                            .getDownloadedPartForDisplayIndex(_index);
                        if (part == null) return;
                        downloadStore.downloadIllust(
                          widget.illusts,
                          part: part,
                        );
                        if (userSetting.starAfterSave &&
                            (widget.illustStore.state == 0)) {
                          widget.illustStore.star(
                            restrict:
                                userSetting.defaultPrivateLike
                                    ? "private"
                                    : "public",
                          );
                        }
                      },
                    ),
                    onLongPress: () async {
                      final part = widget.illustStore
                          .getDownloadedPartForDisplayIndex(_index);
                      if (part != null) {
                        downloadStore.downloadIllust(
                          widget.illusts,
                          part: part,
                        );
                      }
                    },
                  ),
                AnimatedOpacity(
                  opacity: shareShow ? 1 : 0.5,
                  duration: Duration(milliseconds: 500),
                  child: Builder(
                    builder: (context) {
                      return IconButton(
                        icon: Icon(Icons.share, color: Colors.white),
                        onPressed: () async {
                          final localPath = _localPaths[_index];
                          if (localPath != null &&
                              File(localPath).existsSync()) {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            Share.shareXFiles(
                              [XFile(localPath)],
                              sharePositionOrigin:
                                  box!.localToGlobal(Offset.zero) & box.size,
                            );
                            return;
                          }
                          var file = await pixivCacheManager.getFileFromCache(
                            nowUrl,
                          );
                          if (file != null) {
                            String targetPath = p.join(
                              (await getTemporaryDirectory()).path,
                              "share_cache",
                              p.basenameWithoutExtension(file.file.path) +
                                  (nowUrl.endsWith(".png") ? ".png" : ".jpg"),
                            );
                            File targetFile = new File(targetPath);
                            if (!targetFile.existsSync()) {
                              targetFile.createSync(recursive: true);
                            }
                            file.file.copySync(targetPath);
                            final box =
                                context.findRenderObject() as RenderBox?;
                            Share.shareXFiles(
                              [XFile(targetPath)],
                              sharePositionOrigin:
                                  box!.localToGlobal(Offset.zero) & box.size,
                            );
                          } else {
                            BotToast.showText(text: "can not find image cache");
                          }
                        },
                      );
                    },
                  ),
                ),
                if (!_illusts.id.isNegative)
                  IconButton(
                    icon: Icon(
                      !_loadSource ? Icons.hd_outlined : Icons.hd,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _loadSource = !_loadSource;
                      });
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Center _buildLoading(ImageChunkEvent? event) {
    double value =
        event == null || event.expectedTotalBytes == null
            ? 0
            : event.cumulativeBytesLoaded / event.expectedTotalBytes!;
    if (value == 1.0) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            shareShow = true;
          });
        }
      });
    }
    return Center(
      child: Container(
        width: 20.0,
        height: 20.0,
        child: CircularProgressIndicator(value: value),
      ),
    );
  }
}
