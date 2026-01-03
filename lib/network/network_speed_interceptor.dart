/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */

import 'package:dio/dio.dart';
import 'package:pixez/monitor/network_speed_monitor.dart';

class NetworkSpeedInterceptor extends Interceptor {
  final NetworkSpeedMonitor _monitor = NetworkSpeedMonitor();

  // 用于跟踪每个请求的下载进度
  final Map<String, int> _lastReceivedBytes = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 为每个请求设置下载进度回调
    final requestId = _getRequestId(options);

    // 保存原始的进度回调
    final originalCallback = options.onReceiveProgress;

    options.onReceiveProgress = (int received, int total) {
      // 计算增量字节数
      final lastBytes = _lastReceivedBytes[requestId] ?? 0;
      final increment = received - lastBytes;

      if (increment > 0) {
        _monitor.recordDownload(increment);
        _lastReceivedBytes[requestId] = received;
      }

      // 调用原始回调
      if (originalCallback != null) {
        originalCallback(received, total);
      }
    };

    final uploadBytes = _calculateRequestSize(options);
    if (uploadBytes > 0) {
      _monitor.recordUpload(uploadBytes);
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // 清理该请求的进度跟踪
    final requestId = _getRequestId(response.requestOptions);
    _lastReceivedBytes.remove(requestId);

    // 对于非流式响应，也计算响应体大小
    final downloadBytes = _calculateResponseSize(response);
    if (downloadBytes > 0) {
      _monitor.recordDownload(downloadBytes);
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 清理该请求的进度跟踪
    final requestId = _getRequestId(err.requestOptions);
    _lastReceivedBytes.remove(requestId);
    handler.next(err);
  }

  String _getRequestId(RequestOptions options) {
    return '${options.uri}_${options.hashCode}';
  }

  int _calculateRequestSize(RequestOptions options) {
    int size = 0;

    options.headers.forEach((key, value) {
      size += key.length + (value?.toString().length ?? 0);
    });

    if (options.data != null) {
      size += options.data.toString().length;
    }

    return size;
  }

  int _calculateResponseSize(Response response) {
    int size = 0;

    response.headers.forEach((key, values) {
      size += key.length + values.join(',').length;
    });

    if (response.data != null) {
      // 处理二进制数据（如图片）
      if (response.data is List<int>) {
        size += (response.data as List<int>).length;
      } else {
        // 处理其他数据类型（JSON 等）
        size += response.data.toString().length;
      }
    }

    return size;
  }
}
