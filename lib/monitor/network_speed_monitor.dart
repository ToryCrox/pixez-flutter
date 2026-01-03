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
import 'package:flutter/foundation.dart';

class NetworkSpeedData {
  final int downloadSpeed;
  final int uploadSpeed;
  final DateTime timestamp;

  NetworkSpeedData({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.timestamp,
  });

  String get downloadSpeedText => _formatSpeed(downloadSpeed);
  String get uploadSpeedText => _formatSpeed(uploadSpeed);

  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '$bytesPerSecond B/s';
    } else if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    }
  }
}

class NetworkSpeedMonitor {
  static final NetworkSpeedMonitor _instance = NetworkSpeedMonitor._internal();
  factory NetworkSpeedMonitor() => _instance;
  NetworkSpeedMonitor._internal();

  int _downloadBytes = 0;
  int _uploadBytes = 0;
  DateTime _lastUpdateTime = DateTime.now();

  final StreamController<NetworkSpeedData> _speedController =
      StreamController<NetworkSpeedData>.broadcast();

  Stream<NetworkSpeedData> get speedStream => _speedController.stream;

  Timer? _updateTimer;

  void start() {
    if (_updateTimer != null) return;

    _lastUpdateTime = DateTime.now();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateSpeed();
    });
  }

  void stop() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  void recordDownload(int bytes) {
    _downloadBytes += bytes;
  }

  void recordUpload(int bytes) {
    _uploadBytes += bytes;
  }

  void _updateSpeed() {
    final now = DateTime.now();
    final duration = now.difference(_lastUpdateTime);
    final seconds = duration.inMicroseconds / 1000000;

    if (seconds > 0) {
      final downloadSpeed = (_downloadBytes / seconds).round();
      final uploadSpeed = (_uploadBytes / seconds).round();

      final speedData = NetworkSpeedData(
        downloadSpeed: downloadSpeed,
        uploadSpeed: uploadSpeed,
        timestamp: now,
      );

      _speedController.add(speedData);

      _downloadBytes = 0;
      _uploadBytes = 0;
      _lastUpdateTime = now;
    }
  }

  void dispose() {
    stop();
    _speedController.close();
  }
}
