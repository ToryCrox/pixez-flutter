import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pixez/main.dart';

/// 网络请求日志模型
class NetworkLog {
  final String id;
  final String url;
  final String method;
  final int? statusCode;
  final DateTime requestTime;
  final Duration? duration;
  final Map<String, dynamic>? requestHeaders;
  final dynamic requestBody;
  final Map<String, dynamic>? responseHeaders;
  final dynamic responseBody;
  final String? error;
  final String? protocol;

  NetworkLog({
    required this.id,
    required this.url,
    required this.method,
    this.statusCode,
    required this.requestTime,
    this.duration,
    this.requestHeaders,
    this.requestBody,
    this.responseHeaders,
    this.responseBody,
    this.error,
    this.protocol,
  });

  bool get isSuccess =>
      statusCode != null && statusCode! >= 200 && statusCode! < 300;

  String get formattedRequestTime =>
      "${requestTime.hour.toString().padLeft(2, '0')}:${requestTime.minute.toString().padLeft(2, '0')}:${requestTime.second.toString().padLeft(2, '0')}";
}

/// 网络请求日志存储
class NetworkLogStore extends ChangeNotifier {
  static final NetworkLogStore instance = NetworkLogStore._();
  NetworkLogStore._();

  final List<NetworkLog> _logs = [];
  String _searchQuery = "";

  bool get isCollecting => userSetting.isNetworkLogCollecting;

  void setCollecting(bool value) {
    userSetting.setNetworkLogCollecting(value);
    notifyListeners();
  }

  List<NetworkLog> get logs {
    if (_searchQuery.isEmpty) {
      return List.unmodifiable(_logs.reversed);
    }
    return List.unmodifiable(
      _logs.reversed.where((log) {
        final query = _searchQuery.toLowerCase();
        return log.url.toLowerCase().contains(query) ||
            log.method.toLowerCase().contains(query) ||
            (log.statusCode?.toString().contains(query) ?? false);
      }),
    );
  }

  void addLog(NetworkLog log) {
    _logs.add(log);
    if (_logs.length > 200) {
      _logs.removeAt(0);
    }
    notifyListeners();
  }

  void updateLog(
    String id, {
    int? statusCode,
    Duration? duration,
    Map<String, dynamic>? responseHeaders,
    dynamic responseBody,
    String? error,
    String? protocol,
  }) {
    final index = _logs.indexWhere((l) => l.id == id);
    if (index != -1) {
      final oldLog = _logs[index];
      _logs[index] = NetworkLog(
        id: oldLog.id,
        url: oldLog.url,
        method: oldLog.method,
        requestTime: oldLog.requestTime,
        requestHeaders: oldLog.requestHeaders,
        requestBody: oldLog.requestBody,
        statusCode: statusCode ?? oldLog.statusCode,
        duration: duration ?? oldLog.duration,
        responseHeaders: responseHeaders ?? oldLog.responseHeaders,
        responseBody: responseBody ?? oldLog.responseBody,
        error: error ?? oldLog.error,
        protocol: protocol ?? oldLog.protocol,
      );
      notifyListeners();
    }
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }
}

/// Dio 拦截器，用于抓取网络请求
class NetworkLogInterceptor extends Interceptor {
  final _logStore = NetworkLogStore.instance;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_logStore.isCollecting) {
      return super.onRequest(options, handler);
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    options.extra['network_log_id'] = id;

    final log = NetworkLog(
      id: id,
      url: options.uri.toString(),
      method: options.method,
      requestTime: DateTime.now(),
      requestHeaders: options.headers,
      requestBody: options.data,
    );
    _logStore.addLog(log);
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final id = response.requestOptions.extra['network_log_id'];
    if (id != null) {
      final duration = DateTime.now().difference(
        DateTime.fromMicrosecondsSinceEpoch(int.parse(id)),
      );
      _logStore.updateLog(
        id,
        statusCode: response.statusCode,
        duration: duration,
        responseHeaders: response.headers.map,
        responseBody: response.data,
        protocol: response.headers.value('x-protocol-version'),
      );
    }
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final id = err.requestOptions.extra['network_log_id'];
    if (id != null) {
      final duration = DateTime.now().difference(
        DateTime.fromMicrosecondsSinceEpoch(int.parse(id)),
      );
      _logStore.updateLog(
        id,
        statusCode: err.response?.statusCode,
        duration: duration,
        responseHeaders: err.response?.headers.map,
        responseBody: err.response?.data,
        error: err.toString(),
        protocol: err.response?.headers.value('x-protocol-version'),
      );
    }
    super.onError(err, handler);
  }
}
