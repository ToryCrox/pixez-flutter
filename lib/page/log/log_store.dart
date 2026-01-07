import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logger/logger.dart';
import 'package:pixez/custom/log.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'log_store.freezed.dart';
part 'log_store.g.dart';

/// 日志最大预览行数
const int maxLogPreviewLines = 2;

@freezed
class LogViewerState with _$LogViewerState {
  const factory LogViewerState({
    required List<OutputEvent> logs,
    required Set<Level> filterLevels,
    required bool autoScroll,
  }) = _LogViewerState;
}

@riverpod
class LogViewer extends _$LogViewer {
  Timer? _watchTimer;

  @override
  LogViewerState build() {
    // 启动时开始监听日志
    _startWatching();

    // 在 dispose 时清理定时器
    ref.onDispose(() {
      _watchTimer?.cancel();
    });

    return LogViewerState(
      logs: logMemoryOut.buffer.toList(),
      filterLevels: {Level.debug, Level.info, Level.warning, Level.error},
      autoScroll: true,
    );
  }

  /// 开始监听内存中的日志变化
  void _startWatching() {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final currentBuffer = logMemoryOut.buffer;
      final currentLogs = currentBuffer.toList();

      // 只在日志数量变化时更新状态
      if (currentLogs.length != state.logs.length) {
        state = state.copyWith(logs: currentLogs);
      }
    });
  }

  /// 切换级别筛选
  void toggleLevel(Level level) {
    final newFilters = Set<Level>.from(state.filterLevels);
    if (newFilters.contains(level)) {
      newFilters.remove(level);
    } else {
      newFilters.add(level);
    }
    state = state.copyWith(filterLevels: newFilters);
  }

  /// 切换自动滚动
  void toggleAutoScroll() {
    state = state.copyWith(autoScroll: !state.autoScroll);
  }

  /// 刷新日志列表
  void refresh() {
    state = state.copyWith(logs: logMemoryOut.buffer.toList());
  }

  /// 获取筛选后的日志列表
  List<OutputEvent> getFilteredLogs() {
    return state.logs.where((log) => state.filterLevels.contains(log.level)).toList();
  }
}
