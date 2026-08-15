import 'package:flutter/material.dart';

/// 用于左右面板之间的可拖拽垂直分隔条。
///
/// 外层负责摆放此控件和保存面板宽度；本控件负责拖拽手势、范围限制、
/// 吸附点与系统列宽调整光标，因此可复用于任意双栏页面。
class ResizablePanelDivider extends StatefulWidget {
  const ResizablePanelDivider({
    super.key,
    required this.panelWidth,
    required this.maxPanelWidth,
    required this.onWidthChanged,
    required this.onWidthCommitted,
    this.minPanelWidth = 320,
    this.snapPoints = const [],
    this.onResizingChanged,
    this.onReset,
    this.hitWidth = 28,
    this.semanticLabel = '调整侧边栏宽度',
  }) : assert(minPanelWidth <= maxPanelWidth),
       assert(hitWidth > 0);

  final double panelWidth;
  final double maxPanelWidth;
  final double minPanelWidth;
  final List<double> snapPoints;
  final double hitWidth;
  final String semanticLabel;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double> onWidthCommitted;
  final ValueChanged<bool>? onResizingChanged;
  final VoidCallback? onReset;

  @override
  State<ResizablePanelDivider> createState() => _ResizablePanelDividerState();
}

class _ResizablePanelDividerState extends State<ResizablePanelDivider> {
  double _dragStartGlobalX = 0;
  double _dragStartWidth = 0;
  double _currentWidth = 0;

  void _startDrag(DragStartDetails details) {
    _dragStartGlobalX = details.globalPosition.dx;
    _dragStartWidth = widget.panelWidth;
    _currentWidth = widget.panelWidth;
    widget.onResizingChanged?.call(true);
  }

  void _updateDrag(DragUpdateDetails details) {
    // 右侧面板向左拖拽时变宽，向右拖拽时变窄。
    final width =
        (_dragStartWidth + _dragStartGlobalX - details.globalPosition.dx)
            .clamp(widget.minPanelWidth, widget.maxPanelWidth)
            .toDouble();
    _currentWidth = width;
    widget.onWidthChanged(width);
  }

  void _finishDrag() {
    var width = _currentWidth;
    for (final point in widget.snapPoints) {
      if ((point - width).abs() <= 16) {
        width = point;
        break;
      }
    }
    widget.onWidthChanged(width);
    widget.onWidthCommitted(width);
    widget.onResizingChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      child: MouseRegion(
        // Windows 常见的列宽调整光标：竖线两侧带左右箭头。
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          onDoubleTap: widget.onReset,
          onHorizontalDragStart: _startDrag,
          onHorizontalDragUpdate: _updateDrag,
          onHorizontalDragEnd: (_) => _finishDrag(),
          onHorizontalDragCancel: _finishDrag,
          behavior: HitTestBehavior.translucent,
          child: SizedBox(
            width: widget.hitWidth,
            child: Center(
              child: Container(
                width: 1,
                height: double.infinity,
                color: Theme.of(context).dividerColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
