import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixez/component/json_highlighter.dart';
import 'package:pixez/debug/network_logger.dart';

class NetworkLogDetailPage extends StatefulWidget {
  final NetworkLog log;

  const NetworkLogDetailPage({Key? key, required this.log}) : super(key: key);

  static void show(BuildContext context, NetworkLog log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 900),
      builder:
          (context) => Container(
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: NetworkLogDetailPage(log: log),
          ),
    );
  }

  @override
  State<NetworkLogDetailPage> createState() => _NetworkLogDetailPageState();
}

class _NetworkLogDetailPageState extends State<NetworkLogDetailPage> {
  // 缓存格式化后的结果
  FormattedBody? _requestBody;
  Future<FormattedBody>? _responseBodyFuture;

  @override
  void initState() {
    super.initState();
    if (widget.log.requestBody != null) {
      _requestBody = _formatBody(widget.log.requestBody);
    }
    if (widget.log.responseBody != null) {
      _responseBodyFuture = compute(_formatBody, widget.log.responseBody);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(
          automaticallyImplyLeading: false,
          title: const Text('请求详情', style: TextStyle(fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.pop(context),
          ),
          elevation: 0,
        ),
        Expanded(
          child: SelectionArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(context, '基本信息', [
                    _buildInfoRow('URL', widget.log.url, selectable: true),
                    _buildInfoRow('Method', widget.log.method),
                    _buildInfoRow('Protocol', widget.log.protocol ?? "Unknown"),
                    _buildInfoRow(
                      'Status',
                      widget.log.statusCode?.toString() ?? 'Pending',
                      valueColor: _getStatusColor(widget.log.statusCode),
                    ),
                    _buildInfoRow('Time', widget.log.formattedRequestTime),
                    if (widget.log.duration != null)
                      _buildInfoRow(
                        'Duration',
                        '${widget.log.duration!.inMilliseconds} ms',
                      ),
                  ]),
                  if (widget.log.error != null)
                    _buildSection(context, '错误信息', [
                      Text(
                        widget.log.error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ]),
                  _buildSection(context, '请求头 (Request Headers)', [
                    _buildHeaders(widget.log.requestHeaders),
                  ]),
                  if (widget.log.requestBody != null && _requestBody != null)
                    _buildSection(context, '请求体 (Request Body)', [
                      _buildFormattedBodyView(context, _requestBody!),
                    ]),
                  _buildSection(context, '响应头 (Response Headers)', [
                    _buildHeaders(widget.log.responseHeaders),
                  ]),
                  if (widget.log.responseBody != null)
                    _buildSection(context, '响应体 (Response Body)', [
                      _buildAsyncBody(context, _responseBodyFuture!),
                    ]),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).dividerColor.withOpacity(0.05),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    Color? valueColor,
    bool selectable = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaders(Map<String, dynamic>? headers) {
    if (headers == null || headers.isEmpty) {
      return const Text(
        '无',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          headers.entries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.key}: ',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${e.value}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  Widget _buildAsyncBody(BuildContext context, Future<FormattedBody> future) {
    return FutureBuilder<FormattedBody>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Text(
            'Error formatting body: ${snapshot.error}',
            style: const TextStyle(color: Colors.red),
          );
        }
        if (snapshot.hasData) {
          return _buildFormattedBodyView(context, snapshot.data!);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildFormattedBodyView(BuildContext context, FormattedBody result) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (result.isTruncated)
              const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Text(
                  "内容过长已截断显示",
                  style: TextStyle(color: Colors.orange, fontSize: 10),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: "复制完整内容",
              onPressed: () {
                Clipboard.setData(ClipboardData(text: result.fullContent));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已复制完整内容到剪贴板')));
              },
            ),
          ],
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF282C34) : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child:
              result.isTruncated
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      JsonHighlighter(
                        json: result.displayContent,
                        isDark: isDark,
                        padding: EdgeInsets.zero,
                      ),
                      const Divider(),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: result.fullContent),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制完整内容到剪贴板')),
                            );
                          },
                          child: const Text(
                            "点击复制完整内容 (显示已截断)",
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  )
                  : JsonHighlighter(
                    json: result.displayContent,
                    isDark: isDark,
                    padding: EdgeInsets.zero,
                  ),
        ),
      ],
    );
  }

  Color _getStatusColor(int? statusCode) {
    if (statusCode == null) return Colors.grey;
    if (statusCode >= 200 && statusCode < 300) return Colors.green;
    if (statusCode >= 400) return Colors.red;
    if (statusCode >= 300) return Colors.orange;
    return Colors.grey;
  }
}

/// 格式化结果模型
class FormattedBody {
  final String displayContent;
  final String fullContent;
  final bool isTruncated;

  FormattedBody({
    required this.displayContent,
    required this.fullContent,
    required this.isTruncated,
  });
}

/// 静态方法用于 compute 执行
FormattedBody _formatBody(dynamic body) {
  String content = '';
  try {
    if (body is Map || body is List) {
      content = const JsonEncoder.withIndent('  ').convert(body);
    } else if (body is String) {
      try {
        final decoded = json.decode(body);
        content = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        content = body;
      }
    } else {
      content = body.toString();
    }
  } catch (e) {
    content = body.toString();
  }

  // 截断阈值 50KB
  const int maxLength = 50 * 1024;
  if (content.length > maxLength) {
    return FormattedBody(
      displayContent: content.substring(0, maxLength),
      fullContent: content,
      isTruncated: true,
    );
  } else {
    return FormattedBody(
      displayContent: content,
      fullContent: content,
      isTruncated: false,
    );
  }
}
