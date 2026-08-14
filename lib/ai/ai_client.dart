import 'package:dio/dio.dart';
import 'package:pixez/ai/ai_models.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/debug/network_logger.dart';

typedef AiRetryDelay = Future<void> Function(Duration duration);
typedef AiRetryLogger = void Function(String message);

Future<void> _defaultRetryDelay(Duration duration) => Future.delayed(duration);
void _defaultRetryLogger(String message) => Log.w(message);

class AiCompletionInput {
  final String systemPrompt;
  final String userPrompt;

  const AiCompletionInput({
    required this.systemPrompt,
    required this.userPrompt,
  });
}

abstract interface class AiProtocolAdapter {
  AiProtocolType get protocol;
  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  );
}

class AiRequestException implements Exception {
  final String message;
  const AiRequestException(this.message);

  /// 从兼容 OpenAI 协议的错误载荷中提取服务端消息。
  ///
  /// 部分第三方服务会在 HTTP 200 的响应正文中返回错误对象，因此此处也
  /// 会被翻译结果校验流程复用，避免用本地的格式错误覆盖服务端拒绝原因。
  static String? messageFromApiResponse(dynamic payload) {
    if (payload is String) {
      final message = payload.trim();
      return message.isEmpty ? null : message;
    }
    if (payload is! Map) return null;

    for (final key in const ['refusal', 'message', 'detail', 'error']) {
      final message = messageFromApiResponse(payload[key]);
      if (message != null) return message;
    }
    return null;
  }

  @override
  String toString() => message;
}

class AiClient {
  final Map<AiProtocolType, AiProtocolAdapter> _adapters;
  final AiRetryDelay _retryDelay;
  final AiRetryLogger _retryLogger;

  AiClient({
    Iterable<AiProtocolAdapter>? adapters,
    AiRetryDelay retryDelay = _defaultRetryDelay,
    AiRetryLogger retryLogger = _defaultRetryLogger,
  }) : _retryDelay = retryDelay,
       _retryLogger = retryLogger,
       _adapters = {
         for (final adapter
             in adapters ??
                 const [
                   OpenAiChatCompletionsAdapter(),
                   OpenAiResponsesAdapter(),
                 ])
           adapter.protocol: adapter,
       };

  void register(AiProtocolAdapter adapter) =>
      _adapters[adapter.protocol] = adapter;

  Future<String> complete(
    AiProviderConfig config,
    AiCompletionInput input,
  ) async {
    if (config.baseUrl.trim().isEmpty) {
      throw const AiConfigurationException('请设置 Base URL');
    }
    if (config.model.trim().isEmpty) {
      throw const AiConfigurationException('请设置模型名称');
    }
    final adapter = _adapters[config.protocol];
    if (adapter == null) {
      throw AiConfigurationException('尚未支持协议：${config.protocol.label}');
    }
    final headers = <String, dynamic>{'Content-Type': 'application/json'};
    if (config.apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
    }
    final dio = Dio(
      BaseOptions(
        headers: headers,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 30),
        responseType: ResponseType.json,
      ),
    )..interceptors.add(NetworkLogInterceptor());
    var retries = 0;
    while (true) {
      try {
        final result = await adapter.complete(dio, config, input);
        if (result.trim().isEmpty) {
          throw const AiRequestException('AI 未返回可用文本');
        }
        return result.trim();
      } on AiRequestException {
        rethrow;
      } on DioException catch (error) {
        if (retries < config.maxRetries && _isRetryable(error)) {
          final delay = _backoffDelay(retries);
          retries++;
          _retryLogger(
            'AI 请求临时失败，将在 ${delay.inMilliseconds}ms 后进行第 $retries/${config.maxRetries} 次重试',
          );
          await _retryDelay(delay);
          continue;
        }
        _throwRequestException(error);
      } catch (_) {
        throw const AiRequestException('AI 响应格式无法识别');
      }
    }
  }

  static bool _isRetryable(DioException error) {
    if (error.type == DioExceptionType.cancel ||
        error.type == DioExceptionType.badCertificate) {
      return false;
    }
    final statusCode = error.response?.statusCode;
    if (statusCode == null) return true;
    return statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode >= 500;
  }

  static Duration _backoffDelay(int retryIndex) {
    final milliseconds = (500 * (1 << retryIndex)).clamp(500, 8000);
    return Duration(milliseconds: milliseconds.toInt());
  }

  static Never _throwRequestException(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      throw const AiRequestException('AI 请求超时，请稍后重试');
    }
    final message = AiRequestException.messageFromApiResponse(
      error.response?.data,
    );
    throw AiRequestException(
      message != null
          ? 'AI 请求失败：$message'
          : 'AI 请求失败（HTTP ${error.response?.statusCode ?? '网络错误'}）',
    );
  }

  Future<void> testConfig(AiProviderConfig config) async {
    final response = await complete(
      config,
      const AiCompletionInput(
        systemPrompt: 'Reply with exactly OK.',
        userPrompt: 'OK',
      ),
    );
    if (response.isEmpty) throw const AiRequestException('测试请求没有返回内容');
  }

  static String endpoint(String baseUrl, String endpoint) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final normalizedEndpoint = endpoint.replaceFirst(RegExp(r'^/+'), '');
    return base.endsWith('/$normalizedEndpoint')
        ? base
        : '$base/$normalizedEndpoint';
  }
}

class OpenAiChatCompletionsAdapter implements AiProtocolAdapter {
  const OpenAiChatCompletionsAdapter();

  @override
  AiProtocolType get protocol => AiProtocolType.openAiChatCompletions;

  @override
  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  ) async {
    final body = <String, dynamic>{
      'model': config.model.trim(),
      'messages': [
        {'role': 'system', 'content': input.systemPrompt},
        {'role': 'user', 'content': input.userPrompt},
      ],
    };
    if (config.reasoningEffort?.isNotEmpty == true) {
      body['reasoning_effort'] = config.reasoningEffort;
    }
    final response = await dio.post<dynamic>(
      AiClient.endpoint(config.baseUrl, 'chat/completions'),
      data: body,
    );
    final data = response.data;
    if (data is! Map) throw const AiRequestException('Chat 响应格式无效');
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AiRequestException('Chat 响应中没有可用结果');
    }
    final message = (choices.first as Map)['message'];
    final refusal = AiRequestException.messageFromApiResponse(
      message is Map ? message['refusal'] : null,
    );
    if (refusal != null) throw AiRequestException(refusal);
    final content = message is Map ? message['content'] : null;
    final text = _contentToText(content);
    if (text == null || text.trim().isEmpty) {
      throw const AiRequestException('Chat 响应中没有文本内容');
    }
    return text;
  }
}

class OpenAiResponsesAdapter implements AiProtocolAdapter {
  const OpenAiResponsesAdapter();

  @override
  AiProtocolType get protocol => AiProtocolType.openAiResponses;

  @override
  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  ) async {
    final body = <String, dynamic>{
      'model': config.model.trim(),
      'instructions': input.systemPrompt,
      'input': input.userPrompt,
      'store': false,
    };
    if (config.reasoningEffort?.isNotEmpty == true) {
      body['reasoning'] = {'effort': config.reasoningEffort};
    }
    final response = await dio.post<dynamic>(
      AiClient.endpoint(config.baseUrl, 'responses'),
      data: body,
    );
    final data = response.data;
    if (data is! Map) throw const AiRequestException('Responses 响应格式无效');
    final apiError = AiRequestException.messageFromApiResponse(data['error']);
    if (apiError != null) {
      throw AiRequestException(apiError);
    }
    final direct = data['output_text'];
    if (direct is String && direct.trim().isNotEmpty) return direct;
    final output = data['output'];
    if (output is! List) throw const AiRequestException('Responses 响应中没有可用结果');
    final buffer = StringBuffer();
    for (final item in output.whereType<Map>()) {
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content.whereType<Map>()) {
        if (part['type'] == 'refusal') {
          throw AiRequestException(
            AiRequestException.messageFromApiResponse(part['refusal']) ??
                'AI 拒绝生成译文',
          );
        }
        if (part['type'] == 'output_text' && part['text'] is String) {
          buffer.write(part['text']);
        }
      }
    }
    if (buffer.isEmpty) throw const AiRequestException('Responses 响应中没有文本内容');
    return buffer.toString();
  }
}

String? _contentToText(dynamic content) {
  if (content is String) return content;
  if (content is List) {
    final buffer = StringBuffer();
    for (final part in content.whereType<Map>()) {
      final text = part['text'] ?? part['content'];
      if (text is String) buffer.write(text);
    }
    return buffer.toString();
  }
  return null;
}
