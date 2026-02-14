import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/page/database/database_explorer_store.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:pixez/utils/file_utils.dart';
import 'package:path/path.dart' as Path;

import 'database_detail_page.dart';

class DatabaseListPage extends StatefulWidget {
  const DatabaseListPage({super.key});

  @override
  State<DatabaseListPage> createState() => _DatabaseListPageState();
}

class _DatabaseListPageState extends State<DatabaseListPage> {
  final DatabaseExplorerStore _store = DatabaseExplorerStore();

  @override
  void initState() {
    super.initState();
    _store.init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据库管理'),
      ),
      body: Observer(
        builder: (context) {
          if (_store.entries.isEmpty) {
            return const Center(child: Text('没有注册的数据库'));
          }

          return ListView.builder(
            itemCount: _store.entries.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final entry = _store.entries[index];
              return _buildDatabaseCard(entry);
            },
          );
        },
      ),
    );
  }

  Widget _buildDatabaseCard(DatabaseEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DatabaseDetailPage(entry: entry),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storage_rounded, color: Colors.blue),
                  const SizedBox(width: 12),
                  Text(
                    entry.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '路径: ${entry.path}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              // 我们在这里不直接加载大小，留给详情页或者在进入页面时加载
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => FileUtils.openFileOrDirectory(Path.dirname(entry.path)),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('定位文件'),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
