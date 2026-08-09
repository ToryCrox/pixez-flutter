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

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/ugoira_metadata_response.dart';

enum UgoiraZoomMode {
  original, // 1倍图
  double, // 2倍图
  fit, // 适应窗口
}

class UgoiraWidget extends StatefulWidget {
  final List<FileSystemEntity> drawPools;
  final int delay;
  final Size maxSize;
  final UgoiraMetadataResponse ugoiraMetadataResponse;

  const UgoiraWidget({
    Key? key,
    required this.drawPools,
    required this.delay,
    required this.maxSize,
    required this.ugoiraMetadataResponse,
  }) : super(key: key);

  @override
  _UgoiraWidgetState createState() => _UgoiraWidgetState();
}

class _UgoiraWidgetState extends State<UgoiraWidget> with RouteAware {
  Map<File, ui.Image> _map = Map();
  UgoiraZoomMode _zoomMode = UgoiraZoomMode.original;
  Size? _actualImageSize;
  int point = 0;
  ui.Image? image;

  /// 根据缩放模式计算实际显示尺寸
  Size _calculateDisplaySize() {
    if (_actualImageSize == null) {
      // 尚未获取实际图片尺寸，使用 maxSize
      return widget.maxSize;
    }

    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    // ui.Image 的宽高是物理像素，需要转换为逻辑像素
    final originalWidth = _actualImageSize!.width / devicePixelRatio;
    final originalHeight = _actualImageSize!.height / devicePixelRatio;

    switch (_zoomMode) {
      case UgoiraZoomMode.original:
        // 原图尺寸，限制在 maxSize 内
        final scaleX = widget.maxSize.width / originalWidth;
        final scaleY = widget.maxSize.height / originalHeight;
        final scale = min(min(scaleX, scaleY), 1.0);
        return Size(originalWidth * scale, originalHeight * scale);

      case UgoiraZoomMode.double:
        // 2倍图，限制在 maxSize 内
        final scaleX = widget.maxSize.width / (originalWidth * 2);
        final scaleY = widget.maxSize.height / (originalHeight * 2);
        final scale = min(min(scaleX, scaleY), 1.0);
        return Size(originalWidth * 2 * scale, originalHeight * 2 * scale);

      case UgoiraZoomMode.fit:
        // 适应窗口（撑满宽度）
        final aspectRatio = originalHeight / originalWidth;
        return Size(widget.maxSize.width, widget.maxSize.width * aspectRatio);
    }
  }

  Future<ui.Image> _loadImage(File file) async {
    if (_map.containsKey(file) && _map[file] != null) return _map[file]!;
    final data = await file.readAsBytes();
    var image = await decodeImageFromList(data.buffer.asUint8List());
    _map[file] = image;
    if (_map.length > 10) _map.removeWhere((key, value) => key != file);

    // 首次加载图片时，记录实际图片尺寸（物理像素）并刷新显示
    if (_actualImageSize == null) {
      setState(() {
        _actualImageSize = Size(
          image.width.toDouble(),
          image.height.toDouble(),
        );
      });
    }

    return image;
  }

  /// 切换缩放模式
  void setZoomMode(UgoiraZoomMode mode) {
    setState(() {
      _zoomMode = mode;
    });
  }

  @override
  void initState() {
    super.initState();
    initBind();
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

  @override
  void didPopNext() {
    super.didPopNext();
    stopPainting = false;
    initBind();
  }

  @override
  void didPushNext() {
    super.didPushNext();
    stopPainting = true;
  }

  bool stopPainting = false;

  initBind() async {
    Future(() => {start()});
  }

  start() async {
    if (stopPainting) return;
    File file = widget.drawPools[point] as File;
    int duration =
        widget.ugoiraMetadataResponse.ugoiraMetadata.frames[point].delay;
    point++;
    if (point >= widget.drawPools.length) point = 0;
    final data = await _loadImage(file);
    if (mounted && !stopPainting) {
      setState(() {
        image = data;
      });
    } else
      return;
    Future.delayed(Duration(milliseconds: duration), () {
      if (mounted && !stopPainting) start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final displaySize = _calculateDisplaySize();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SizedBox(
            width: displaySize.width,
            height: displaySize.height,
            child:
                image != null
                    ? CustomPaint(
                      painter: UgoiraPainter(image!),
                      size: displaySize,
                    )
                    : Container(),
          ),
        ),
        _buildZoomControlBar(),
      ],
    );
  }

  /// 构建缩放控制按钮栏
  Widget _buildZoomControlBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildZoomButton('1x', UgoiraZoomMode.original),
          SizedBox(width: 12),
          _buildZoomButton('2x', UgoiraZoomMode.double),
          SizedBox(width: 12),
          _buildZoomButton('Fit', UgoiraZoomMode.fit),
        ],
      ),
    );
  }

  /// 构建单个缩放按钮
  Widget _buildZoomButton(String label, UgoiraZoomMode mode) {
    final isSelected = _zoomMode == mode;
    return OutlinedButton(
      onPressed: () => setZoomMode(mode),
      style: OutlinedButton.styleFrom(
        backgroundColor:
            isSelected
                ? Theme.of(context).colorScheme.secondary
                : Colors.transparent,
        foregroundColor:
            isSelected
                ? Theme.of(context).colorScheme.onSecondary
                : Theme.of(context).colorScheme.onSurface,
        side: BorderSide(
          color:
              isSelected
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(context).dividerColor,
        ),
      ),
      child: Text(label),
    );
  }
}

class UgoiraPainter extends CustomPainter {
  final ui.Image image;
  final BoxFit fit;

  UgoiraPainter(this.image, {this.fit = BoxFit.contain});

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: image,
      fit: fit,
      alignment: Alignment.center,
    );
  }

  @override
  bool shouldRepaint(UgoiraPainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.fit != fit;
  }
}
