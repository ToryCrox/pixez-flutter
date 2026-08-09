import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/page/database/database_explorer_store.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:pixez/exts.dart';

import 'table_data_viewer_page.dart';
import 'table_structure_page.dart';

class DatabaseDetailPage extends StatefulWidget {
  final DatabaseEntry entry;

  const DatabaseDetailPage({super.key, required this.entry});

  @override
  State<DatabaseDetailPage> createState() => _DatabaseDetailPageState();
}

class _DatabaseDetailPageState extends State<DatabaseDetailPage> {
  late DatabaseExplorerStore _store;

  @override
  void initState() {
    super.initState();
    _store = DatabaseExplorerStore();
    _store.init();
    _store.selectDatabase(widget.entry);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.name)),
      body: Observer(
        builder: (context) {
          if (_store.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return CustomScrollView(slivers: [_buildHeader(), _buildTableList()]);
        },
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.all(16),
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(Icons.file_present_rounded, '路径', _store.dbPath),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.sd_storage_rounded,
              '文件大小',
              _store.dbSize.formatFileSize(),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.table_rows_rounded,
              '表数量',
              _store.tables.length.toString(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildTableList() {
    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final table = _store.tables[index];
          return Card(
            child: ListTile(
              leading: const Icon(
                Icons.table_chart_rounded,
                color: Colors.green,
              ),
              title: Text(
                table['name'],
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text('记录数: ${table['count']}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Colors.blue,
                    ),
                    tooltip: '查看结构',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => TableStructurePage(
                                store: _store,
                                tableName: table['name'],
                              ),
                        ),
                      );
                    },
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => TableDataViewerPage(
                          store: _store,
                          tableName: table['name'],
                        ),
                  ),
                );
              },
            ),
          );
        }, childCount: _store.tables.length),
      ),
    );
  }
}
