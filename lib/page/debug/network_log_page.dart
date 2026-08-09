import 'package:flutter/material.dart';
import 'package:pixez/debug/network_logger.dart';
import 'package:pixez/page/debug/network_log_detail_page.dart';

class NetworkLogPage extends StatefulWidget {
  const NetworkLogPage({Key? key}) : super(key: key);

  /// 以 BottomSheet 形式打开网络日志页面，占屏幕高度的 80%
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 900),
      builder:
          (context) => Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: NetworkLogPage(),
          ),
    );
  }

  @override
  _NetworkLogPageState createState() => _NetworkLogPageState();
}

class _NetworkLogPageState extends State<NetworkLogPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
        ),
        title: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索请求...',
              border: InputBorder.none,
              hintStyle: TextStyle(
                color: Colors.grey.withOpacity(0.7),
                fontSize: 13,
              ),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (value) {
              NetworkLogStore.instance.setSearchQuery(value);
            },
          ),
        ),
        actions: [
          AnimatedBuilder(
            animation: NetworkLogStore.instance,
            builder: (context, child) {
              return Row(
                children: [
                  const Text(
                    '采集',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Transform.scale(
                    scale: 0.7,
                    child: Switch(
                      value: NetworkLogStore.instance.isCollecting,
                      activeColor: Theme.of(context).primaryColor,
                      onChanged: (value) {
                        NetworkLogStore.instance.setCollecting(value);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () {
              NetworkLogStore.instance.clear();
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: NetworkLogStore.instance,
        builder: (context, child) {
          final logs = NetworkLogStore.instance.logs;
          if (logs.isEmpty) {
            return const Center(
              child: Text(
                '暂无请求日志',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            );
          }
          return ListView.separated(
            itemCount: logs.length,
            separatorBuilder:
                (context, index) => const Divider(height: 1, thickness: 0.5),
            itemBuilder: (context, index) {
              final log = logs[index];
              return _buildLogItem(context, log);
            },
          );
        },
      ),
    );
  }

  Widget _buildLogItem(BuildContext context, NetworkLog log) {
    Color statusColor = Colors.grey;
    if (log.statusCode != null) {
      if (log.statusCode! >= 200 && log.statusCode! < 300) {
        statusColor = Colors.green;
      } else if (log.statusCode! >= 400) {
        statusColor = Colors.red;
      } else if (log.statusCode! >= 300) {
        statusColor = Colors.orange;
      }
    }

    return InkWell(
      onTap: () {
        NetworkLogDetailPage.show(context, log);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 方法栏
            Container(
              width: 50,
              padding: EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                log.method,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            SizedBox(width: 8),
            // URL 和信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        log.formattedRequestTime,
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      if (log.duration != null) ...[
                        Text(
                          ' • ',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        Text(
                          '${log.duration!.inMilliseconds}ms',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            // 状态码
            if (log.statusCode != null)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  log.statusCode.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
