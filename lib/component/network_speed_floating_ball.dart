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
import 'package:flutter/material.dart';
import 'package:pixez/main.dart';
import 'package:pixez/monitor/network_speed_monitor.dart';

class FloatingNetworkSpeedBall extends StatefulWidget {
  const FloatingNetworkSpeedBall({super.key});

  @override
  State<FloatingNetworkSpeedBall> createState() =>
      _FloatingNetworkSpeedBallState();
}

class _FloatingNetworkSpeedBallState extends State<FloatingNetworkSpeedBall> {
  double _x = 16.0;
  double _y = 0.0;
  bool _isDragging = false;
  NetworkSpeedData? _speedData;
  StreamSubscription<NetworkSpeedData>? _speedSubscription;

  @override
  void initState() {
    super.initState();
    _loadPosition();
    _startMonitoring();
  }

  @override
  void dispose() {
    _speedSubscription?.cancel();
    super.dispose();
  }

  void _loadPosition() {
    setState(() {
      _x = userSetting.networkSpeedBallX;
      _y = userSetting.networkSpeedBallY;
    });
  }

  void _savePosition() {
    userSetting.setNetworkSpeedBallPosition(_x, _y);
  }

  void _startMonitoring() {
    NetworkSpeedMonitor().start();
    _speedSubscription = NetworkSpeedMonitor().speedStream.listen((speedData) {
      if (mounted) {
        setState(() {
          _speedData = speedData;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 使用默认位置（左下角）
    double displayY = _y > 0 ? _y : screenSize.height - 120;

    // 特殊值：-1.0 表示右贴边（会在运行时计算）
    const double snappedRightValue = -1.0;
    const double snappedLeftValue = 8.0;

    // 计算实际显示位置
    double displayX;
    if (_x < 0) {
      // 右贴边，根据当前窗口宽度计算
      displayX = screenSize.width - 88;
    } else {
      displayX = _x > 0 ? _x : snappedLeftValue;
    }

    // 当窗口大小变化时调整位置
    if (!_isDragging) {
      // 确保在屏幕范围内
      displayX = displayX.clamp(snappedLeftValue, screenSize.width - 88.0);
      displayY = displayY.clamp(0.0, screenSize.height - 80.0);

      // 如果位置改变了，更新保存的位置
      // 注意：右贴边时保持特殊值 -1.0，不更新为实际坐标
      if (_x >= 0 && (displayX != _x || displayY != _y)) {
        _x = displayX;
        _y = displayY;
        _savePosition();
      } else if (_y != displayY) {
        // 右贴边时，只需要更新 Y 坐标
        _y = displayY;
        _savePosition();
      }
    }

    return Positioned(
      left: displayX,
      bottom: screenSize.height - displayY - 60,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onPanStart: (_) {
            setState(() {
              _isDragging = true;
              // 如果是右贴边（特殊值 -1.0），先转换为实际坐标
              if (_x < 0) {
                _x = screenSize.width - 88;
              }
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _x += details.delta.dx;
              _y += details.delta.dy;

              _x = _x.clamp(0.0, screenSize.width - 80);
              _y = _y.clamp(0.0, screenSize.height - 80);
            });
          },
          onPanEnd: (_) {
            setState(() {
              _isDragging = false;
              final centerX = _x + 40;
              if (centerX < screenSize.width / 2) {
                // 左贴边
                _x = 8.0;
              } else {
                // 右贴边，保存特殊值 -1.0
                _x = -1.0;
              }
              _savePosition();
            });
          },
          child: _buildBall(isDark),
        ),
      ),
    );
  }

  Widget _buildBall(bool isDark) {
    final backgroundColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.black.withValues(alpha: 0.75);
    final textColor = isDark ? Colors.black87 : Colors.white;
    final shadowColor = isDark
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.3);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: _isDragging
            ? _buildDraggingContent(textColor)
            : _buildSpeedContent(textColor),
      ),
    );
  }

  Widget _buildSpeedContent(Color textColor) {
    if (_speedData == null) {
      return _buildPlaceholder(textColor);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSpeedRow(Icons.arrow_downward, _speedData!.downloadSpeedText,
            Colors.green, textColor),
        const SizedBox(height: 4),
        _buildSpeedRow(Icons.arrow_upward, _speedData!.uploadSpeedText,
            Colors.blue, textColor),
      ],
    );
  }

  Widget _buildSpeedRow(
      IconData icon, String text, Color iconColor, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: iconColor),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDraggingContent(Color textColor) {
    return SizedBox(
      width: 60,
      height: 60,
      child: Icon(
        Icons.drag_indicator,
        color: textColor.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildPlaceholder(Color textColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '↓ 0 B/s',
          style: TextStyle(color: textColor, fontSize: 11),
        ),
        Text(
          '↑ 0 B/s',
          style: TextStyle(color: textColor, fontSize: 11),
        ),
      ],
    );
  }
}
