import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 鼠标拖拽事件拦截器
/// 
/// 用于包裹在使用 `SelectionArea` 等需要用鼠标选中文本的单行或多行文本区域外面。
/// 
/// 解决痛点：
/// 在外层使用了具有横向或纵向滑动功能的组件（例如 [PageView] 或 [CustomScrollView]），
/// 同时全局配置了开启鼠标拖拽滚动的行为（如通过修改 [ScrollBehavior] 允许鼠标拖拽）时，
/// 用户如果想用鼠标选中文本并拖动，手势事件会冒泡到上一层的 PageView 并被其抢占（变成横向/纵向翻页）。
/// 
/// 通过使用此包裹器，可以拦截掉（吃掉）所有**鼠标设备的拖拽**事件（将其拦截但不触发实际滑动），
/// 保证文本能够正常被鼠标选中，并且**不影响触屏设备的滑动体验**。
class MouseDragBlocker extends StatelessWidget {
  final Widget child;
  const MouseDragBlocker({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _MouseHorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_MouseHorizontalDragGestureRecognizer>(
          () => _MouseHorizontalDragGestureRecognizer(),
          (_MouseHorizontalDragGestureRecognizer instance) {
            instance
              ..onDown = (_) {}
              ..onStart = (_) {}
              ..onUpdate = (_) {};
          },
        ),
        _MouseVerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_MouseVerticalDragGestureRecognizer>(
          () => _MouseVerticalDragGestureRecognizer(),
          (_MouseVerticalDragGestureRecognizer instance) {
            instance
              ..onDown = (_) {}
              ..onStart = (_) {}
              ..onUpdate = (_) {};
          },
        ),
      },
      child: child,
    );
  }
}

class _MouseHorizontalDragGestureRecognizer extends HorizontalDragGestureRecognizer {
  @override
  bool isPointerAllowed(PointerEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      return super.isPointerAllowed(event);
    }
    return false;
  }
}

class _MouseVerticalDragGestureRecognizer extends VerticalDragGestureRecognizer {
  @override
  bool isPointerAllowed(PointerEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      return super.isPointerAllowed(event);
    }
    return false;
  }
}
