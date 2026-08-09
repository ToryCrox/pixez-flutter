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

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:pixez/utils.dart'
    show initializeScrollController, kLazyLoadSize;

/// 自动处理 EasyRefresh 鼠标滚轮滚动加载更多的 Mixin
///
/// 使用方法：
/// ```dart
/// class _MyPageState extends State<MyPage> with PixezEasyRefreshMixin {
///   late EasyRefreshController _easyRefreshController;
///   late ScrollController _scrollController;
///
///   @override
///   void initState() {
///     super.initState();
///     _scrollController = ScrollController();
///     _easyRefreshController = EasyRefreshController(...);
///
///     // 自动初始化滚动监听（处理鼠标滚轮问题）
///     initializeEasyRefreshScrollListener(
///       _scrollController,
///       onLoad: () => _store.fetchNext(),
///     );
///   }
///
///   @override
///   void dispose() {
///     disposeEasyRefreshScrollListener(); // 自动清理
///     _scrollController.dispose();
///     _easyRefreshController.dispose();
///     super.dispose();
///   }
/// }
/// ```
mixin PixezEasyRefreshMixin<T extends StatefulWidget> on State<T> {
  void Function()? _scrollListenerDisposer;

  /// 初始化 EasyRefresh 的滚动监听
  /// 自动处理桌面端鼠标滚轮滚动时无法触发加载更多的问题
  ///
  /// [scrollController] 滚动控制器
  /// [onLoad] 加载更多的回调函数
  void initializeEasyRefreshScrollListener(
    ScrollController scrollController, {
    required Future<void> Function() onLoad,
  }) {
    _scrollListenerDisposer = initializeScrollController(
      scrollController,
      onLoad,
    );
  }

  /// 清理滚动监听器
  /// 在 dispose 方法中调用
  void disposeEasyRefreshScrollListener() {
    if (_scrollListenerDisposer != null) {
      _scrollListenerDisposer!();
      _scrollListenerDisposer = null;
    }
  }
}

/// PixezEasyRefresh 是 EasyRefresh.builder 的包装器
/// 自动处理桌面端鼠标滚轮滚动时无法触发加载更多的问题
///
/// 使用方式：
/// ```dart
/// PixezEasyRefresh.builder(
///   controller: _easyRefreshController,
///   onLoad: () => _store.fetchNext(),
///   onRefresh: () => _store.fetch(force: true),
///   header: PixezDefault.header(context),
///   footer: PixezDefault.footer(context),
///   childBuilder: (context, physics, scrollController) => CustomScrollView(
///     physics: physics,
///     controller: scrollController, // 在 NestedScrollView 中可能为 null
///     slivers: [...],
///   ),
/// )
/// ```
class PixezEasyRefresh extends StatefulWidget {
  final EasyRefreshController controller;
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onLoad;
  final Header? header;
  final Footer? footer;
  final Widget Function(
    BuildContext context,
    ScrollPhysics physics,
    ScrollController? scrollController,
  )
  childBuilder;
  final ScrollController? scrollController;
  final double? callLoadOverOffset;
  final double? callRefreshOverOffset;
  final bool refreshOnStart;

  const PixezEasyRefresh({
    Key? key,
    required this.controller,
    required this.childBuilder,
    this.onRefresh,
    this.onLoad,
    this.header,
    this.footer,
    this.scrollController,
    this.callLoadOverOffset,
    this.callRefreshOverOffset,
    this.refreshOnStart = false,
  }) : super(key: key);

  /// builder 方法，提供更简洁的 API
  static Widget builder({
    required EasyRefreshController controller,
    required Widget Function(
      BuildContext context,
      ScrollPhysics physics,
      ScrollController? scrollController,
    )
    childBuilder,
    Future<void> Function()? onRefresh,
    Future<void> Function()? onLoad,
    Header? header,
    Footer? footer,
    ScrollController? scrollController,
    double? callLoadOverOffset,
    double? callRefreshOverOffset,
    bool refreshOnStart = false,
  }) {
    return PixezEasyRefresh(
      controller: controller,
      childBuilder: childBuilder,
      onRefresh: onRefresh,
      onLoad: onLoad,
      header: header,
      footer: footer,
      scrollController: scrollController,
      callLoadOverOffset: callLoadOverOffset,
      callRefreshOverOffset: callRefreshOverOffset,
      refreshOnStart: refreshOnStart,
    );
  }

  @override
  State<PixezEasyRefresh> createState() => _PixezEasyRefreshState();
}

class _PixezEasyRefreshState extends State<PixezEasyRefresh>
    with PixezEasyRefreshMixin {
  late ScrollController _scrollController;
  bool _isControllerOwned = false;
  bool _isNestedScrollView = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    // 如果没有传入 scrollController，则创建一个
    if (widget.scrollController == null) {
      _scrollController = ScrollController();
      _isControllerOwned = true;
    } else {
      _scrollController = widget.scrollController!;
      _isControllerOwned = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 检测是否在 NestedScrollView 中
    try {
      NestedScrollView.sliverOverlapAbsorberHandleFor(context);
      _isNestedScrollView = true;
    } catch (e) {
      _isNestedScrollView = false;
    }

    // 如果不在 NestedScrollView 中，初始化滚动监听
    if (!_isNestedScrollView &&
        widget.onLoad != null &&
        _scrollListenerDisposer == null) {
      // 使用 WidgetsBinding 延迟执行，确保在 build 之后
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          initializeEasyRefreshScrollListener(
            _scrollController,
            onLoad: widget.onLoad!,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    disposeEasyRefreshScrollListener();

    // 如果是我们创建的 controller，则销毁它
    if (_isControllerOwned) {
      _scrollController.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 构建参数映射，只传递非 null 的参数
    Widget child = EasyRefresh.builder(
      controller: widget.controller,
      scrollController: _scrollController,
      onRefresh: widget.onRefresh,
      onLoad: widget.onLoad,
      header: widget.header,
      footer: widget.footer,
      refreshOnStart: widget.refreshOnStart,
      childBuilder: (context, physics) {
        // 在 NestedScrollView 中，CustomScrollView 不应该有 controller
        // 否则会破坏嵌套滚动
        final scrollController = _isNestedScrollView ? null : _scrollController;
        return widget.childBuilder(context, physics, scrollController);
      },
    );

    // 如果在 NestedScrollView 中，使用 NotificationListener 监听滚动
    if (_isNestedScrollView && widget.onLoad != null) {
      child = NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification is ScrollUpdateNotification) {
            final metrics = notification.metrics;
            // 检查是否接近底部（距离底部 300px 以内）
            if (metrics.extentAfter <= kLazyLoadSize && !_isLoading) {
              _isLoading = true;
              widget.onLoad!()
                  .then((_) {
                    if (mounted) {
                      _isLoading = false;
                    }
                  })
                  .catchError((_) {
                    if (mounted) {
                      _isLoading = false;
                    }
                  });
            }
          }
          return false; // 继续传递通知
        },
        child: child,
      );
    }

    return child;
  }
}
