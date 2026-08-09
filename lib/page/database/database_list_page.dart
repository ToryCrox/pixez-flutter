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
      appBar: AppBar(title: const Text('数据库管理')),
      body: Observer(
        builder: (context) {
          if (_store.entries.isEmpty) {
            return const Center(child: Text('没有注册的数据库'));
          }

          return ListView.builder(
            itemCount: _store.entries.length,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.storage_rounded,
                  color: Colors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed:
                    () =>
                        FileUtils.openFileOrDirectory(Path.dirname(entry.path)),
                icon: const Icon(Icons.folder_open, size: 20),
                tooltip: '定位文件',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
