import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:pixez/utils/file_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/i18n.dart';

import 'log_store.dart';

/// 日志查看页面
class LogViewerPage extends ConsumerStatefulWidget {
  const LogViewerPage({super.key});

  @override
  ConsumerState<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends ConsumerState<LogViewerPage> {
  final ScrollController _scrollController = ScrollController();
  bool _isUserScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 检测用户是否在手动滚动
    final position = _scrollController.position;
    if (position.userScrollDirection != ScrollDirection.idle) {
      setState(() {
        _isUserScrolling = true;
      });
    }

    // 如果滚动到底部，重置用户滚动状态
    if (_isAtBottom) {
      setState(() {
        _isUserScrolling = false;
      });
    }
  }

  bool get _isAtBottom {
    if (!_scrollController.hasClients) return false;
    return _scrollController.offset >=
        _scrollController.position.maxScrollExtent - 100;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _openLogFolder() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final logPath = '${docDir.path}/pixez/logs';

      if (Platform.isWindows || Platform.isLinux) {
        await FileUtils.openFileOrDirectory(logPath);
      } else {
        // macOS/iOS: 显示路径提示
        if (!mounted) return;
        await showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(I18n.of(context).log_directory),
                content: SelectableText(logPath),
                actions: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: logPath));
                      Navigator.of(context).pop();
                    },
                    child: Text(I18n.of(context).copy),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(I18n.of(context).ok),
                  ),
                ],
              ),
        );
      }
    } catch (e) {
      Log.e(() => "Failed to open log folder", error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(logViewerProvider);
    final filteredLogs =
        ref.watch(logViewerProvider.notifier).getFilteredLogs();

    // 自动滚动到底部
    if (state.autoScroll && !_isUserScrolling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isAtBottom == false) {
          _scrollToBottom();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.of(context).log_viewer),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: I18n.of(context).log_open_folder,
            onPressed: _openLogFolder,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: I18n.of(context).refresh,
            onPressed: () => ref.read(logViewerProvider.notifier).refresh(),
          ),
          IconButton(
            icon: Icon(
              state.autoScroll
                  ? Icons.arrow_downward
                  : Icons.vertical_align_center,
            ),
            tooltip: state.autoScroll ? '停止自动滚动' : '启用自动滚动',
            onPressed:
                () => ref.read(logViewerProvider.notifier).toggleAutoScroll(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: _buildFilterChips(state, ref),
        ),
      ),
      body:
          filteredLogs.isEmpty
              ? _buildEmptyState()
              : _buildLogList(filteredLogs, state),
    );
  }

  Widget _buildFilterChips(LogViewerState state, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          _buildLevelChip(
            Level.debug,
            'Debug',
            Colors.cyan,
            state.filterLevels.contains(Level.debug),
            (selected) =>
                ref.read(logViewerProvider.notifier).toggleLevel(Level.debug),
          ),
          _buildLevelChip(
            Level.info,
            I18n.of(context).log_filter_info,
            Colors.blue,
            state.filterLevels.contains(Level.info),
            (selected) =>
                ref.read(logViewerProvider.notifier).toggleLevel(Level.info),
          ),
          _buildLevelChip(
            Level.warning,
            I18n.of(context).log_filter_warning,
            Colors.orange,
            state.filterLevels.contains(Level.warning),
            (selected) =>
                ref.read(logViewerProvider.notifier).toggleLevel(Level.warning),
          ),
          _buildLevelChip(
            Level.error,
            I18n.of(context).log_filter_error,
            Colors.red,
            state.filterLevels.contains(Level.error),
            (selected) =>
                ref.read(logViewerProvider.notifier).toggleLevel(Level.error),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelChip(
    Level level,
    String label,
    Color color,
    bool isSelected,
    Function(bool) onSelected,
  ) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: color.withOpacity(0.3),
      checkmarkColor: color,
      labelStyle: TextStyle(
        color: isSelected ? color : null,
        fontWeight: isSelected ? FontWeight.bold : null,
      ),
      side: BorderSide(color: isSelected ? color : Colors.grey),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.description_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            I18n.of(context).log_empty,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(List<OutputEvent> logs, LogViewerState state) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: logs.length,
      itemBuilder: (context, index) {
        return _LogEventTile(event: logs[index], maxLines: maxLogPreviewLines);
      },
    );
  }
}

/// 单条日志事件组件
class _LogEventTile extends StatefulWidget {
  final OutputEvent event;
  final int maxLines;

  const _LogEventTile({required this.event, required this.maxLines});

  @override
  State<_LogEventTile> createState() => _LogEventTileState();
}

class _LogEventTileState extends State<_LogEventTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final level = widget.event.level;
    final message = _formatFullMessage();
    final textPainter = TextPainter(
      text: TextSpan(
        text: message,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      textDirection: Directionality.of(context),
      maxLines: widget.maxLines,
    )..layout(
      maxWidth: MediaQuery.of(context).size.width - 80,
    ); // 减去 padding 和 margin

    final didExceedMaxLines = textPainter.didExceedMaxLines;
    final displayMessage = _expanded ? message : message;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 第一行: 时间 + 级别 + 复制按钮
            Row(
              children: [
                _buildTimeText(),
                const SizedBox(width: 8),
                _buildLevelIcon(level),
                const Spacer(),
                // 复制按钮
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                // 展开/收起按钮
                if (didExceedMaxLines)
                  IconButton(
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                    ),
                    tooltip: _expanded ? '收起' : '展开',
                    onPressed: () {
                      setState(() {
                        _expanded = !_expanded;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // 消息内容 - 使用 SelectionArea 包裹 Text 以支持文本选择
            SelectionArea(
              child: Text(
                displayMessage,
                maxLines: _expanded ? null : widget.maxLines,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: _getLevelColor(level),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeText() {
    final time = DateFormat('HH:mm:ss.SSS').format(widget.event.origin.time);
    return Text(
      time,
      style: const TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        color: Colors.grey,
      ),
    );
  }

  Widget _buildLevelIcon(Level level) {
    IconData icon;
    Color color;
    String label;

    switch (level) {
      case Level.debug:
        icon = Icons.bug_report_outlined;
        color = Colors.cyan;
        label = 'DEBUG';
        break;
      case Level.info:
        icon = Icons.info_outline;
        color = Colors.blue;
        label = 'INFO';
        break;
      case Level.warning:
        icon = Icons.warning_outlined;
        color = Colors.orange;
        label = 'WARN';
        break;
      case Level.error:
        icon = Icons.error_outline;
        color = Colors.red;
        label = 'ERROR';
        break;
      default:
        icon = Icons.bug_report_outlined;
        color = Colors.cyan;
        label = 'DEBUG';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _getLevelColor(Level level) {
    switch (level) {
      case Level.debug:
        return Colors.cyan.shade700;
      case Level.info:
        return Colors.blue.shade700;
      case Level.warning:
        return Colors.orange.shade700;
      case Level.error:
        return Colors.red.shade700;
      default:
        return Colors.cyan.shade700;
    }
  }

  String _formatFullMessage() {
    final buffer = StringBuffer();
    final message = widget.event.origin.message;
    final finalMessage = message is Function ? message() : message;

    // 添加消息内容
    if (finalMessage is Map || finalMessage is Iterable) {
      const encoder = JsonEncoder.withIndent('  ');
      buffer.write(encoder.convert(finalMessage));
    } else {
      // 去除首尾的换行符和空白，避免多余空行
      final trimmed = finalMessage.toString().trim();
      buffer.write(trimmed);
    }

    // 添加 error
    if (widget.event.origin.error != null) {
      // 如果已经有消息内容，先换行
      if (buffer.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write('Error: ${widget.event.origin.error}');
    }

    // 添加 stackTrace
    if (widget.event.origin.stackTrace != null) {
      // 如果已经有内容，先换行
      if (buffer.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write('StackTrace:\n${widget.event.origin.stackTrace}');
    }

    return buffer.toString();
  }
}
