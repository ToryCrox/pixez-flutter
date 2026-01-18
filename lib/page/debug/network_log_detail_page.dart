import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixez/component/json_highlighter.dart';
import 'package:pixez/debug/network_logger.dart';

class NetworkLogDetailPage extends StatelessWidget {
  final NetworkLog log;

  const NetworkLogDetailPage({Key? key, required this.log}) : super(key: key);

  static void show(BuildContext context, NetworkLog log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: NetworkLogDetailPage(log: log),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                    _buildInfoRow('URL', log.url, selectable: true),
                    _buildInfoRow('Method', log.method),
                    _buildInfoRow('Status', log.statusCode?.toString() ?? 'Pending',
                        valueColor: _getStatusColor(log.statusCode)),
                    _buildInfoRow('Time', log.formattedRequestTime),
                    if (log.duration != null)
                      _buildInfoRow('Duration', '${log.duration!.inMilliseconds} ms'),
                  ]),
                  if (log.error != null)
                    _buildSection(context, '错误信息', [
                      Text(log.error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ]),
                  _buildSection(context, '请求头 (Request Headers)', [
                    _buildHeaders(log.requestHeaders),
                  ]),
                  if (log.requestBody != null)
                    _buildSection(context, '请求体 (Request Body)', [
                      _buildFormattedBody(context, log.requestBody, isDark),
                    ]),
                  _buildSection(context, '响应头 (Response Headers)', [
                    _buildHeaders(log.responseHeaders),
                  ]),
                  if (log.responseBody != null)
                    _buildSection(context, '响应体 (Response Body)', [
                      _buildFormattedBody(context, log.responseBody, isDark),
                    ]),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).dividerColor.withOpacity(0.05),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor, bool selectable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 12, color: valueColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaders(Map<String, dynamic>? headers) {
    if (headers == null || headers.isEmpty) {
      return Text('无', style: TextStyle(fontSize: 12, color: Colors.grey));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: headers.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${e.key}: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Expanded(child: Text('${e.value}', style: TextStyle(fontSize: 12))),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFormattedBody(BuildContext context, dynamic body, bool isDark) {
    String content = '';
    // String language = 'text'; // Not needed with JsonHighlighter

    try {
      if (body is Map || body is List) {
        content = JsonEncoder.withIndent('  ').convert(body);
        // language = 'json';
      } else if (body is String) {
        try {
          final decoded = json.decode(body);
          content = JsonEncoder.withIndent('  ').convert(decoded);
          // language = 'json';
        } catch (_) {
          content = body;
        }
      } else {
        content = body.toString();
      }
    } catch (e) {
      content = body.toString();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          icon: Icon(Icons.copy, size: 16),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制到剪贴板')));
          },
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? Color(0xFF282C34) : Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: EdgeInsets.all(8),
          child: JsonHighlighter(
            json: content,
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
