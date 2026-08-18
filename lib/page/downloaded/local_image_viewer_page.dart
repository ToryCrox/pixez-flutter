import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixez/er/prefer.dart';

class LocalImageViewerComparison {
  final String leftImagePath;
  final String rightImagePath;
  final String? leftTitle;
  final String? rightTitle;
  final String? leftSubtitle;
  final String? rightSubtitle;

  const LocalImageViewerComparison({
    required this.leftImagePath,
    required this.rightImagePath,
    this.leftTitle,
    this.rightTitle,
    this.leftSubtitle,
    this.rightSubtitle,
  });
}

class LocalImageViewerItem {
  final String imagePath;
  final String? title;
  final String? subtitle;
  final String? heroTag;
  final LocalImageViewerComparison? comparison;

  const LocalImageViewerItem({
    required this.imagePath,
    this.title,
    this.subtitle,
    this.heroTag,
    this.comparison,
  });
}

typedef LocalImageViewerBottomBuilder =
    Widget Function(BuildContext context, LocalImageViewerItem item, int index);

class LocalImageViewerPage extends StatefulWidget {
  final String imagePath;
  final String? title;
  final String? subtitle;
  final String? heroTag;
  final LocalImageViewerComparison? comparison;
  final List<LocalImageViewerItem> gallery;
  final int initialIndex;
  final LocalImageViewerBottomBuilder? bottomBuilder;

  const LocalImageViewerPage({
    super.key,
    required this.imagePath,
    this.title,
    this.subtitle,
    this.heroTag,
    this.comparison,
    this.gallery = const [],
    this.initialIndex = 0,
    this.bottomBuilder,
  });

  static Future<T?> open<T>(
    BuildContext context, {
    required String imagePath,
    String? title,
    String? subtitle,
    String? heroTag,
    LocalImageViewerComparison? comparison,
    List<LocalImageViewerItem> gallery = const [],
    int initialIndex = 0,
    LocalImageViewerBottomBuilder? bottomBuilder,
  }) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) {
          return LocalImageViewerPage(
            imagePath: imagePath,
            title: title,
            subtitle: subtitle,
            heroTag: heroTag,
            comparison: comparison,
            gallery: gallery,
            initialIndex: initialIndex,
            bottomBuilder: bottomBuilder,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<LocalImageViewerPage> createState() => _LocalImageViewerPageState();
}

class _ToggleScaleIntent extends Intent {
  const _ToggleScaleIntent();
}

class _PreviousImageIntent extends Intent {
  const _PreviousImageIntent();
}

class _NextImageIntent extends Intent {
  const _NextImageIntent();
}

class _LocalImageViewerPageState extends State<LocalImageViewerPage> {
  static const _comparisonModePreferenceKey =
      'local_image_viewer_comparison_mode';
  static const double _minScale = 0.1;
  static const double _maxScale = 8.0;
  static const double _stepScale = 1.25;
  static const double _epsilon = 0.0001;

  final FocusNode _focusNode = FocusNode();
  final TransformationController _transformController =
      TransformationController();
  late File _file;

  int _currentIndex = 0;
  int _loadGeneration = 0;

  Size? _imagePixelSize;
  Size? _leftImagePixelSize;
  Size? _rightImagePixelSize;
  Size? _viewportSize;
  String? _loadError;

  bool _isFitMode = false;
  bool _showRightImage = false;
  bool _comparisonMode = false;
  double _comparisonSplit = 0.5;
  bool _initialScaleReady = false;
  double _currentDesiredScale = 1.0;
  Size? _lastViewportSize;

  @override
  void initState() {
    super.initState();
    _currentIndex = _initialIndex;
    _comparisonMode = Prefer.getBool(_comparisonModePreferenceKey) ?? false;
    _showRightImage = _isRightImage(_currentItem);
    _file = File(_activeImagePath);
    _resolveImageInfo();
  }

  List<LocalImageViewerItem> get _items =>
      widget.gallery.isEmpty
          ? [
            LocalImageViewerItem(
              imagePath: widget.imagePath,
              title: widget.title,
              subtitle: widget.subtitle,
              heroTag: widget.heroTag,
              comparison: widget.comparison,
            ),
          ]
          : widget.gallery;

  int get _initialIndex =>
      widget.initialIndex.clamp(0, _items.length - 1).toInt();

  LocalImageViewerItem get _currentItem => _items[_currentIndex];

  LocalImageViewerComparison? get _comparison => _currentItem.comparison;

  bool get _hasComparison => _comparison != null;

  String get _activeImagePath {
    final comparison = _comparison;
    if (comparison == null) return _currentItem.imagePath;
    return _showRightImage
        ? comparison.rightImagePath
        : comparison.leftImagePath;
  }

  String? get _displayTitle {
    final comparison = _comparison;
    if (comparison == null) return _currentItem.title;
    return _showRightImage
        ? comparison.rightTitle ?? _currentItem.title
        : comparison.leftTitle ?? _currentItem.title;
  }

  String? get _displaySubtitle {
    final comparison = _comparison;
    if (comparison == null) return _currentItem.subtitle;
    return _showRightImage
        ? comparison.rightSubtitle ?? _currentItem.subtitle
        : comparison.leftSubtitle ?? _currentItem.subtitle;
  }

  bool _isRightImage(LocalImageViewerItem item) {
    final comparison = item.comparison;
    return comparison != null && item.imagePath == comparison.rightImagePath;
  }

  bool get _hasPrevious => _currentIndex > 0;

  bool get _hasNext => _currentIndex < _items.length - 1;

  @override
  void dispose() {
    _focusNode.dispose();
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _resolveImageInfo() async {
    final generation = _loadGeneration;
    final file = _file;
    final comparison = _comparison;
    final activeExists = await file.exists();
    final activeSize = activeExists ? await _resolveImagePixelSize(file) : null;

    if (!activeExists || activeSize == null) {
      if (!mounted) return;
      if (generation != _loadGeneration) return;
      setState(() {
        _imagePixelSize = activeSize;
        _leftImagePixelSize = null;
        _rightImagePixelSize = null;
        _loadError = activeExists ? '读取图片失败' : '文件不存在';
      });
      return;
    }

    if (!mounted) return;
    if (generation != _loadGeneration) return;
    setState(() {
      _imagePixelSize = activeSize;
      _leftImagePixelSize = null;
      _rightImagePixelSize = null;
      _loadError = null;
    });
    _initScaleForOpen();

    if (comparison == null) return;
    final comparisonSizes = await Future.wait([
      _resolveImagePixelSize(File(comparison.leftImagePath)),
      _resolveImagePixelSize(File(comparison.rightImagePath)),
    ]);
    if (!mounted) return;
    if (generation != _loadGeneration) return;
    setState(() {
      _leftImagePixelSize = comparisonSizes[0];
      _rightImagePixelSize = comparisonSizes[1];
    });
  }

  Future<Size?> _resolveImagePixelSize(File file) async {
    if (!await file.exists()) return null;

    final provider = FileImage(file);
    final stream = provider.resolve(const ImageConfiguration());
    final completer = Completer<Size?>();
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete(
            Size(info.image.width.toDouble(), info.image.height.toDouble()),
          );
        }
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  void _showImageAt(int index) {
    if (index < 0 || index >= _items.length || index == _currentIndex) return;
    _loadGeneration++;
    setState(() {
      _currentIndex = index;
      if (!_hasComparison) _showRightImage = false;
      _file = File(_activeImagePath);
      _imagePixelSize = null;
      _leftImagePixelSize = null;
      _rightImagePixelSize = null;
      _loadError = null;
      _initialScaleReady = false;
      _isFitMode = false;
      _comparisonSplit = 0.5;
      _currentDesiredScale = 1.0;
      _transformController.value = Matrix4.identity();
    });
    _resolveImageInfo();
  }

  void _showPreviousImage() => _showImageAt(_currentIndex - 1);

  void _showNextImage() => _showImageAt(_currentIndex + 1);

  Size? _actualLogicalImageSize() {
    final pixel = _imagePixelSize;
    if (pixel == null) return null;
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    return Size(pixel.width / dpr, pixel.height / dpr);
  }

  Size? _comparisonLogicalImageSize() {
    final left = _leftImagePixelSize;
    final right = _rightImagePixelSize;
    if (left == null && right == null) return _actualLogicalImageSize();
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    return Size(
      math.max(left?.width ?? 0, right?.width ?? 0) / dpr,
      math.max(left?.height ?? 0, right?.height ?? 0) / dpr,
    );
  }

  Size? _displayLogicalImageSize() {
    return _comparisonMode
        ? _comparisonLogicalImageSize()
        : _actualLogicalImageSize();
  }

  double _fitScale() {
    final viewport = _viewportSize;
    final image = _displayLogicalImageSize();
    if (viewport == null || image == null) return 1.0;
    if (image.width <= 0 || image.height <= 0) return 1.0;
    final byWidth = viewport.width / image.width;
    final byHeight = viewport.height / image.height;
    return math.min(1.0, math.min(byWidth, byHeight));
  }

  Size _interactionBoxForScale(double desiredScale) {
    final viewport = _viewportSize;
    final image = _displayLogicalImageSize();
    if (viewport == null || image == null) return const Size(0, 0);
    final scaledW = image.width * desiredScale;
    final scaledH = image.height * desiredScale;
    return Size(
      math.min(viewport.width, scaledW),
      math.min(viewport.height, scaledH),
    );
  }

  Matrix4 _centeredMatrix({
    required Size boxSize,
    required Size imageSize,
    required double scale,
  }) {
    final sw = imageSize.width * scale;
    final sh = imageSize.height * scale;
    final tx = (boxSize.width - sw) / 2;
    final ty = (boxSize.height - sh) / 2;
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  double _matrixScale() {
    return _transformController.value.getMaxScaleOnAxis();
  }

  void _setDesiredScale(double desired, {bool resetPosition = true}) {
    final image = _displayLogicalImageSize();
    if (image == null || _viewportSize == null) return;
    final box = _interactionBoxForScale(desired);
    final next = desired.clamp(_minScale, _maxScale);

    if (resetPosition) {
      _transformController.value = _centeredMatrix(
        boxSize: box,
        imageSize: image,
        scale: next,
      );
    } else {
      final current = _matrixScale();
      if (current <= 0) {
        _transformController.value = _centeredMatrix(
          boxSize: box,
          imageSize: image,
          scale: next,
        );
      } else {
        final ratio = next / current;
        final matrix = _transformController.value.clone();
        final cx = box.width / 2;
        final cy = box.height / 2;
        final tx = matrix.storage[12];
        final ty = matrix.storage[13];
        final ntx = cx - (cx - tx) * ratio;
        final nty = cy - (cy - ty) * ratio;
        matrix.storage[0] = matrix.storage[0] * ratio;
        matrix.storage[5] = matrix.storage[5] * ratio;
        matrix.storage[12] = ntx;
        matrix.storage[13] = nty;
        _transformController.value = matrix;
      }
    }

    setState(() {
      _currentDesiredScale = next;
    });
  }

  void _initScaleForOpen() {
    if (_initialScaleReady) return;
    if (_viewportSize == null || _actualLogicalImageSize() == null) return;
    final fit = _fitScale();
    final initial = fit;
    _isFitMode = (initial - fit).abs() < _epsilon;
    _initialScaleReady = true;
    _setDesiredScale(initial, resetPosition: true);
  }

  void _toggleFitAndActual() {
    setState(() {
      _isFitMode = !_isFitMode;
    });
    _setDesiredScale(_isFitMode ? _fitScale() : 1.0, resetPosition: true);
  }

  void _toggleComparisonImage() {
    if (!_hasComparison) return;
    _loadGeneration++;
    setState(() {
      _comparisonMode = false;
      _showRightImage = !_showRightImage;
      _file = File(_activeImagePath);
      _imagePixelSize = null;
      _leftImagePixelSize = null;
      _rightImagePixelSize = null;
      _loadError = null;
      _initialScaleReady = false;
      _isFitMode = false;
      _currentDesiredScale = 1.0;
      _transformController.value = Matrix4.identity();
    });
    unawaited(Prefer.setBool(_comparisonModePreferenceKey, false));
    _resolveImageInfo();
  }

  void _toggleComparisonMode() {
    if (!_hasComparison) return;
    setState(() {
      _comparisonMode = !_comparisonMode;
      _comparisonSplit = 0.5;
    });
    unawaited(Prefer.setBool(_comparisonModePreferenceKey, _comparisonMode));
    _setDesiredScale(_fitScale(), resetPosition: true);
  }

  void _updateComparisonSplit(double delta, double width) {
    if (width <= 0) return;
    setState(() {
      _comparisonSplit =
          (_comparisonSplit + delta / width).clamp(0.0, 1.0).toDouble();
    });
  }

  void _zoomIn() {
    final next = (_currentDesiredScale * _stepScale).clamp(
      _minScale,
      _maxScale,
    );
    _setDesiredScale(next, resetPosition: true);
    if (_isFitMode && next > _fitScale() + _epsilon) {
      setState(() {
        _isFitMode = false;
      });
    }
  }

  void _zoomOut() {
    final next = (_currentDesiredScale / _stepScale).clamp(
      _minScale,
      _maxScale,
    );
    _setDesiredScale(next, resetPosition: true);
    if (_isFitMode && next < _fitScale() - _epsilon) {
      setState(() {
        _isFitMode = false;
      });
    }
  }

  void _onDoubleTap() {
    final fit = _fitScale();
    if (_currentDesiredScale > fit + 0.01) {
      setState(() {
        _isFitMode = true;
      });
      _setDesiredScale(fit, resetPosition: true);
      return;
    }
    final target = fit < 1.0 ? 1.0 : math.min(2.0, _maxScale);
    setState(() {
      _isFitMode = false;
    });
    _setDesiredScale(target, resetPosition: true);
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.digit1): _ToggleScaleIntent(),
        SingleActivator(LogicalKeyboardKey.numpad1): _ToggleScaleIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _PreviousImageIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): _PreviousImageIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NextImageIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown): _NextImageIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ToggleScaleIntent: CallbackAction<_ToggleScaleIntent>(
            onInvoke: (_) {
              _toggleFitAndActual();
              return null;
            },
          ),
          _PreviousImageIntent: CallbackAction<_PreviousImageIntent>(
            onInvoke: (_) {
              _showPreviousImage();
              return null;
            },
          ),
          _NextImageIntent: CallbackAction<_NextImageIntent>(
            onInvoke: (_) {
              _showNextImage();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          focusNode: _focusNode,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: LayoutBuilder(
              builder: (context, constraints) {
                _viewportSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final viewportChanged =
                    _lastViewportSize == null ||
                    _lastViewportSize != _viewportSize;
                _lastViewportSize = _viewportSize;
                final image = _displayLogicalImageSize();
                final hasImage = _loadError == null && image != null;
                final boxSize =
                    image == null
                        ? Size(
                          constraints.maxWidth * 0.8,
                          constraints.maxHeight * 0.8,
                        )
                        : _interactionBoxForScale(_currentDesiredScale);

                if (!_initialScaleReady && hasImage) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _initScaleForOpen();
                  });
                }
                if (_initialScaleReady &&
                    _isFitMode &&
                    hasImage &&
                    viewportChanged) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _setDesiredScale(_fitScale(), resetPosition: true);
                  });
                }

                return Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    Center(
                      child:
                          hasImage
                              ? GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {},
                                onDoubleTap: _onDoubleTap,
                                child: SizedBox(
                                  width: boxSize.width,
                                  height: boxSize.height,
                                  child: InteractiveViewer(
                                    transformationController:
                                        _transformController,
                                    minScale: _minScale,
                                    maxScale: _maxScale,
                                    constrained: false,
                                    clipBehavior: Clip.hardEdge,
                                    onInteractionUpdate: (_) {
                                      final scale = _matrixScale();
                                      if ((scale - _currentDesiredScale).abs() <
                                          _epsilon)
                                        return;
                                      setState(() {
                                        _currentDesiredScale = scale;
                                        _isFitMode =
                                            (scale - _fitScale()).abs() < 0.01;
                                      });
                                    },
                                    child: SizedBox(
                                      width: image.width,
                                      height: image.height,
                                      child:
                                          _comparisonMode
                                              ? _buildComparisonImage()
                                              : _buildSingleImage(),
                                    ),
                                  ),
                                ),
                              )
                              : _buildFallback(),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 8,
                      child: _buildRoundButton(
                        icon: Icons.close,
                        tooltip: '关闭',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    if (_displayTitle != null || _displaySubtitle != null)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 10,
                        left: 56,
                        right: 20,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: math.max(
                                0.0,
                                constraints.maxWidth - 76,
                              ),
                            ),
                            child: _buildTitle(),
                          ),
                        ),
                      ),
                    if (_items.length > 1) ...[
                      Positioned(
                        left: 16,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _buildNavigationButton(
                            icon: Icons.chevron_left,
                            tooltip: '上一张（← / ↑）',
                            enabled: _hasPrevious,
                            onTap: _showPreviousImage,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 16,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _buildNavigationButton(
                            icon: Icons.chevron_right,
                            tooltip: '下一张（→ / ↓）',
                            enabled: _hasNext,
                            onTap: _showNextImage,
                          ),
                        ),
                      ),
                    ],
                    Positioned(
                      left: 16,
                      bottom: MediaQuery.of(context).padding.bottom + 18,
                      child: _buildScaleBadge(),
                    ),
                    if (widget.bottomBuilder != null)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: MediaQuery.of(context).padding.bottom + 18,
                        child: Center(
                          child: widget.bottomBuilder!(
                            context,
                            _currentItem,
                            _currentIndex,
                          ),
                        ),
                      ),
                    Positioned(
                      right: 16,
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                      child: _buildActionBar(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    final error = _loadError;
    if (error == null) {
      return const SizedBox(
        width: 64,
        height: 64,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, color: Colors.white70),
          const SizedBox(height: 12),
          Text(
            error,
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_displayTitle != null)
            Text(
              _displayTitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (_displaySubtitle != null)
            Text(
              _displaySubtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRoundButton(
            icon: _isFitMode ? Icons.fit_screen : Icons.filter_center_focus,
            tooltip: _isFitMode ? '当前: 适应窗口（按1切换）' : '当前: 实际大小（按1切换）',
            onTap: _toggleFitAndActual,
          ),
          const SizedBox(width: 4),
          _buildRoundButton(
            icon: Icons.zoom_out,
            tooltip: '缩小',
            onTap: _zoomOut,
          ),
          const SizedBox(width: 4),
          _buildRoundButton(icon: Icons.zoom_in, tooltip: '放大', onTap: _zoomIn),
          if (_hasComparison) ...[
            const SizedBox(width: 4),
            _buildRoundButton(
              icon: Icons.swap_horiz,
              tooltip: _comparisonMode ? '切换图片（退出对比）' : '切换原图和译图',
              onTap: _toggleComparisonImage,
            ),
            const SizedBox(width: 4),
            _buildRoundButton(
              icon: Icons.compare_arrows,
              tooltip: _comparisonMode ? '退出左右对比' : '开启左右对比',
              onTap: _toggleComparisonMode,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSingleImage() {
    final image = Image.file(
      _file,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.high,
    );
    if (_currentItem.heroTag == null || _showRightImage) return image;
    return Hero(tag: _currentItem.heroTag!, child: image);
  }

  Widget _buildComparisonImage() {
    final comparison = _comparison;
    if (comparison == null) return _buildSingleImage();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final split = width * _comparisonSplit;
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildComparisonLayer(comparison.leftImagePath),
            ClipRect(
              clipper: _RightComparisonClipper(_comparisonSplit),
              child: _buildComparisonLayer(comparison.rightImagePath),
            ),
            Positioned(
              left: (split - 1).clamp(0, math.max(0, width - 2)).toDouble(),
              top: 0,
              bottom: 0,
              width: 2,
              child: Container(color: Colors.white),
            ),
            Positioned(
              left: split - 20,
              top: 0,
              bottom: 0,
              width: 40,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  key: const ValueKey('local-image-comparison-divider'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate:
                      (details) =>
                          _updateComparisonSplit(details.delta.dx, width),
                  child: Center(child: _buildComparisonHandle()),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: _buildComparisonLabel(comparison.leftTitle ?? '左侧'),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: _buildComparisonLabel(comparison.rightTitle ?? '右侧'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildComparisonLayer(String imagePath) {
    return Image.file(
      File(imagePath),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder:
          (_, _, _) => const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white70),
          ),
    );
  }

  Widget _buildComparisonLabel(String text) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildComparisonHandle() {
    return Container(
      width: 38,
      height: 78,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white70),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row < 3; row++) ...[
              if (row > 0) const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildComparisonHandleDot(),
                  const SizedBox(width: 3),
                  _buildComparisonHandleDot(),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonHandleDot() {
    return Container(
      width: 5,
      height: 5,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildScaleBadge() {
    final percent = (_currentDesiredScale * 100)
        .clamp(1, 9999)
        .toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$percent%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNavigationButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 44,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: enabled ? 0.55 : 0.25),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: enabled ? Colors.white24 : Colors.white12,
              ),
            ),
            child: Icon(
              icon,
              size: 32,
              color: enabled ? Colors.white : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _RightComparisonClipper extends CustomClipper<Rect> {
  final double split;

  const _RightComparisonClipper(this.split);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(size.width * split, 0, size.width, size.height);
  }

  @override
  bool shouldReclip(_RightComparisonClipper oldClipper) {
    return oldClipper.split != split;
  }
}
