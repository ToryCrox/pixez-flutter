import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/page/database/database_explorer_store.dart';

class TableStructurePage extends StatefulWidget {
  final DatabaseExplorerStore store;
  final String tableName;

  const TableStructurePage({
    super.key,
    required this.store,
    required this.tableName,
  });

  @override
  State<TableStructurePage> createState() => _TableStructurePageState();
}

class _TableStructurePageState extends State<TableStructurePage> {
  @override
  void initState() {
    super.initState();
    widget.store.loadTableStructure(widget.tableName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.tableName} - 表结构'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => widget.store.loadTableStructure(widget.tableName),
          ),
        ],
      ),
      body: Observer(
        builder: (context) {
          if (widget.store.isLoading && widget.store.tableFields.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildInfoCard(
                title: '基础信息',
                child: Column(
                  children: [
                    _buildInfoRow('预估行数', '${widget.store.totalCount}'),
                    _buildInfoRow('估算空间占用', _formatSize(widget.store.tableBytes)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                title: '字段列表',
                child: Column(
                  children: widget.store.tableFields.map((f) {
                    final isPk = f['pk'] == 1;
                    final isNotNull = f['notnull'] == 1;
                    return ListTile(
                      dense: true,
                      leading: Icon(isPk ? Icons.key : Icons.reorder, size: 18, color: isPk ? Colors.orange : null),
                      title: Text('${f['name']}'),
                      subtitle: Text('${f['type']}'),
                      trailing: isNotNull ? const Text('NOT NULL', style: TextStyle(fontSize: 10, color: Colors.grey)) : null,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              _buildInfoCard(
                title: '索引列表',
                child: widget.store.tableIndexes.isEmpty 
                  ? const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('没有索引', style: TextStyle(color: Colors.grey)),
                    )
                  : Column(
                      children: widget.store.tableIndexes.map((idx) {
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.flash_on, size: 18, color: Colors.blue),
                          title: Text('${idx['name']}'),
                          subtitle: Text('${idx['sql'] ?? ''}', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                    ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoCard({required String title, required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 0) return '不可用 (需要 dbstat 扩展)';
    if (bytes == 0) return '0 B';
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return "${d.toStringAsFixed(2)} ${suffixes[i]}";
  }
}
