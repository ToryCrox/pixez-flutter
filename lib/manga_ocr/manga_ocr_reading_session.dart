import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pixez/manga_ocr/manga_ocr_controller.dart';
import 'package:pixez/manga_ocr/manga_ocr_pipeline.dart';
import 'package:pixez/manga_ocr/manga_ocr_preferences.dart';

typedef MangaOcrPagePathResolver = Future<String?> Function(int pageIndex);
typedef MangaOcrTargetLanguageResolver = String Function();

class _MangaOcrPageRequest {
  final int pageIndex;
  final bool forceOcr;
  final bool forceTranslation;

  const _MangaOcrPageRequest({
    required this.pageIndex,
    this.forceOcr = false,
    this.forceTranslation = false,
  });
}

/// 连续阅读场景下的单任务协调器。
///
/// 正在执行的页面不会与下一页并发；等待队列只保留最后一次请求，从而避免
/// 快速滚动时对经过的每一页都启动下载和推理。
class MangaOcrReadingSession extends ChangeNotifier {
  final MangaOcrPipeline pipeline;
  final MangaOcrPagePathResolver resolvePagePath;
  final MangaOcrTargetLanguageResolver resolveTargetLanguage;
  final Duration pageSettleDuration;

  final Map<int, MangaOcrController> _controllers = {};
  MangaOcrPreferences? _preferences;
  _MangaOcrPageRequest? _pendingRequest;
  Timer? _settleTimer;
  int? _runningPage;
  int _currentPage = 0;
  bool _autoFollowEnabled = true;
  bool _panelActive = false;
  bool _hasStarted = false;
  bool _disposed = false;

  MangaOcrReadingSession({
    required this.pipeline,
    required this.resolvePagePath,
    required this.resolveTargetLanguage,
    this.pageSettleDuration = const Duration(milliseconds: 350),
  });

  int get currentPage => _currentPage;
  int? get runningPage => _runningPage;
  bool get autoFollowEnabled => _autoFollowEnabled;
  bool get panelActive => _panelActive;
  bool get hasStarted => _hasStarted;
  MangaOcrController get currentController => controllerFor(_currentPage);

  MangaOcrController controllerFor(int pageIndex) {
    return _controllers.putIfAbsent(pageIndex, () {
      final controller = MangaOcrController(pipeline);
      controller.addListener(_notifySafely);
      return controller;
    });
  }

  void open(int pageIndex) {
    _panelActive = true;
    setCurrentPage(pageIndex, schedule: false);
    _notifySafely();
  }

  void close() {
    _panelActive = false;
    _settleTimer?.cancel();
    _settleTimer = null;
    final pendingPage = _pendingRequest?.pageIndex;
    _pendingRequest = null;
    if (pendingPage != null && pendingPage != _runningPage) {
      controllerFor(pendingPage).markCancelled();
    }
    _hasStarted = false;
    _notifySafely();
  }

  void setAutoFollowEnabled(bool value) {
    if (_autoFollowEnabled == value) return;
    _autoFollowEnabled = value;
    _settleTimer?.cancel();
    if (value && _panelActive && _hasStarted) scheduleCurrentPage();
    _notifySafely();
  }

  void setCurrentPage(int pageIndex, {bool schedule = true}) {
    if (pageIndex < 0) return;
    final changed = _currentPage != pageIndex;
    _currentPage = pageIndex;
    controllerFor(pageIndex);
    if (changed) _notifySafely();
    if (schedule && _panelActive && _autoFollowEnabled && _hasStarted) {
      scheduleCurrentPage();
    }
  }

  void scheduleCurrentPage() {
    _settleTimer?.cancel();
    final page = _currentPage;
    _settleTimer = Timer(pageSettleDuration, () {
      if (!_disposed &&
          _panelActive &&
          _autoFollowEnabled &&
          _hasStarted &&
          page == _currentPage) {
        requestPage(page);
      }
    });
  }

  void requestCurrent({bool forceOcr = false, bool forceTranslation = false}) {
    requestPage(
      _currentPage,
      forceOcr: forceOcr,
      forceTranslation: forceTranslation,
    );
  }

  void requestPage(
    int pageIndex, {
    bool forceOcr = false,
    bool forceTranslation = false,
  }) {
    if (_disposed) return;
    _hasStarted = true;
    final controller = controllerFor(pageIndex);
    if (!forceOcr && !forceTranslation && controller.result != null) {
      _notifySafely();
      return;
    }
    if (_runningPage == pageIndex && controller.isRunning) return;

    final previousPendingPage = _pendingRequest?.pageIndex;
    if (previousPendingPage != null &&
        previousPendingPage != pageIndex &&
        previousPendingPage != _runningPage) {
      controllerFor(previousPendingPage).markCancelled();
    }
    _pendingRequest = _MangaOcrPageRequest(
      pageIndex: pageIndex,
      forceOcr: forceOcr,
      forceTranslation: forceTranslation,
    );
    controller.markQueued();
    _notifySafely();
    unawaited(_drain());
  }

  Future<void> cancelCurrent() async {
    final page = _currentPage;
    if (_pendingRequest?.pageIndex == page) {
      _pendingRequest = null;
      controllerFor(page).markCancelled();
    }
    if (_runningPage == page) await controllerFor(page).cancel();
    _notifySafely();
  }

  Future<void> _drain() async {
    if (_runningPage != null || _disposed) return;
    while (!_disposed && _pendingRequest != null) {
      final request = _pendingRequest!;
      _pendingRequest = null;
      _runningPage = request.pageIndex;
      _notifySafely();
      final controller = controllerFor(request.pageIndex);
      try {
        final imagePath = await resolvePagePath(request.pageIndex);
        if (imagePath == null) {
          controller.failExternally('无法取得当前页图片文件');
          continue;
        }
        final preferences = _preferences ??= await MangaOcrPreferences.load();
        if (_disposed) return;
        await controller.analyze(
          imagePath: imagePath,
          pageIndex: request.pageIndex,
          targetLanguage: resolveTargetLanguage(),
          forceOcr: request.forceOcr,
          forceTranslation: request.forceTranslation,
          detectorId: preferences.detectorId,
          recognizerId: preferences.recognizerId,
          options: preferences.options,
        );
      } catch (error) {
        controller.failExternally(error.toString());
      } finally {
        if (_runningPage == request.pageIndex) _runningPage = null;
        _notifySafely();
      }
    }
  }

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _settleTimer?.cancel();
    _pendingRequest = null;
    if (_runningPage != null) unawaited(pipeline.cancel());
    for (final controller in _controllers.values) {
      controller.removeListener(_notifySafely);
      controller.dispose();
    }
    _controllers.clear();
    super.dispose();
  }
}
