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

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/main.dart';

/// WebP动图缩放模式
enum WebpZoomMode {
  original,  // 1倍图
  double,    // 2倍图
  fit,       // 适应窗口
}

/// WebP动图显示组件
/// 
/// 支持：
/// - 从文件加载WebP动图
/// - 1倍、2倍和适应宽高切换
/// - 异步获取并更新宽高信息
class WebpAnimatedWidget extends StatefulWidget {
  final String webpPath;
  final int illustId;
  final Size maxSize;
  final int? initialWidth;
  final int? initialHeight;
  /// 宽高更新回调（用于更新数据库）
  final void Function(int width, int height)? onDimensionsChanged;

  const WebpAnimatedWidget({
    Key? key,
    required this.webpPath,
    required this.illustId,
    required this.maxSize,
    this.initialWidth,
    this.initialHeight,
    this.onDimensionsChanged,
  }) : super(key: key);

  @override
  State<WebpAnimatedWidget> createState() => _WebpAnimatedWidgetState();
}

class _WebpAnimatedWidgetState extends State<WebpAnimatedWidget> with RouteAware {
  WebpZoomMode _zoomMode = WebpZoomMode.original;
  Size? _actualImageSize;

  @override
  void initState() {
    super.initState();
    // 使用初始宽高
    if (widget.initialWidth != null && widget.initialHeight != null &&
        widget.initialWidth! > 0 && widget.initialHeight! > 0) {
      _actualImageSize = Size(
        widget.initialWidth!.toDouble(),
        widget.initialHeight!.toDouble(),
      );
    }
    // 异步验证并更新宽高
    _checkAndUpdateDimensions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// 异步检查并更新WebP尺寸
  Future<void> _checkAndUpdateDimensions() async {
    try {
      final file = File(widget.webpPath);
      if (!await file.exists()) return;

      // 使用downloadStore的方法获取尺寸
      final size = await downloadStore.getImageSize(widget.webpPath);
      if (size == null) return;
      
      final newWidth = size.width.toInt();
      final newHeight = size.height.toInt();

      if (newWidth > 0 && newHeight > 0) {
        // 检查尺寸是否有变化
        final needUpdate = widget.initialWidth != newWidth ||
            widget.initialHeight != newHeight;

        if (needUpdate && widget.onDimensionsChanged != null) {
          Log.d('WebpAnimatedWidget: 尺寸变化 ${widget.initialWidth}x${widget.initialHeight} -> ${newWidth}x$newHeight');
          widget.onDimensionsChanged!(newWidth, newHeight);
        }

        if (mounted) {
          setState(() {
            _actualImageSize = Size(newWidth.toDouble(), newHeight.toDouble());
          });
        }
      }
    } catch (e) {
      Log.w('WebpAnimatedWidget: 获取尺寸失败: $e');
    }
  }

  /// 根据缩放模式计算实际显示尺寸
  Size _calculateDisplaySize() {
    if (_actualImageSize == null) {
      return widget.maxSize;
    }

    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    // ImageSizeGetter获取的宽高是物理像素，需要转换为逻辑像素
    final originalWidth = _actualImageSize!.width / devicePixelRatio;
    final originalHeight = _actualImageSize!.height / devicePixelRatio;

    switch (_zoomMode) {
      case WebpZoomMode.original:
        // 原图尺寸，限制在 maxSize 内
        final scaleX = widget.maxSize.width / originalWidth;
        final scaleY = widget.maxSize.height / originalHeight;
        final scale = min(min(scaleX, scaleY), 1.0);
        return Size(originalWidth * scale, originalHeight * scale);

      case WebpZoomMode.double:
        // 2倍图，限制在 maxSize 内
        final scaleX = widget.maxSize.width / (originalWidth * 2);
        final scaleY = widget.maxSize.height / (originalHeight * 2);
        final scale = min(min(scaleX, scaleY), 1.0);
        return Size(originalWidth * 2 * scale, originalHeight * 2 * scale);

      case WebpZoomMode.fit:
        // 适应窗口（撑满宽度）
        final aspectRatio = originalHeight / originalWidth;
        return Size(widget.maxSize.width, widget.maxSize.width * aspectRatio);
    }
  }

  void _setZoomMode(WebpZoomMode mode) {
    setState(() {
      _zoomMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final displaySize = _calculateDisplaySize();
    
    return Stack(
      children: [
        // WebP动图显示
        SizedBox(
          width: displaySize.width,
          height: displaySize.height,
          child: Image.file(
            File(widget.webpPath),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
        // 缩放控制按钮
        Positioned(
          right: 8,
          bottom: 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildZoomButton('1x', WebpZoomMode.original),
                _buildZoomButton('2x', WebpZoomMode.double),
                _buildZoomButton('适应', WebpZoomMode.fit),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildZoomButton(String label, WebpZoomMode mode) {
    final isSelected = _zoomMode == mode;
    return InkWell(
      onTap: () => _setZoomMode(mode),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.blue : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
