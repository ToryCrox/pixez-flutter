import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/page/database/database_explorer_store.dart';

class TableDataViewerPage extends StatefulWidget {
  final DatabaseExplorerStore store;
  final String tableName;

  const TableDataViewerPage({
    super.key,
    required this.store,
    required this.tableName,
  });

  @override
  State<TableDataViewerPage> createState() => _TableDataViewerPageState();
}

class _TableDataViewerPageState extends State<TableDataViewerPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.store.loadTableData(widget.tableName);
    _searchController.addListener(() {
      widget.store.setSearch(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tableName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => widget.store.loadTableData(widget.tableName, resetPagination: false),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchHeader(),
          Expanded(
            child: _buildDataTable(),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Observer(
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              // 字段选择 - 固定宽度
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String>(
                  initialValue: widget.store.searchColumn,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '字段',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: '*', child: Text('所有字段')),
                    ...widget.store.tableColumns.map((col) => DropdownMenuItem(
                      value: col,
                      child: Text(col, overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      widget.store.setSearchColumn(val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              // 操作符选择 - 固定宽度
              SizedBox(
                width: 90,
                child: DropdownButtonFormField<String>(
                  initialValue: widget.store.searchOperator,
                  decoration: const InputDecoration(
                    labelText: '逻辑',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'LIKE', child: Text('包含')),
                    DropdownMenuItem(value: '=', child: Text('=')),
                    DropdownMenuItem(value: '!=', child: Text('!=')),
                    DropdownMenuItem(value: '>', child: Text('>')),
                    DropdownMenuItem(value: '>=', child: Text('>=')),
                    DropdownMenuItem(value: '<', child: Text('<')),
                    DropdownMenuItem(value: '<=', child: Text('<=')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      widget.store.setSearchOperator(val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              // 搜索内容文字框 - 填充剩余空间
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索内容...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onSubmitted: (_) {
                    widget.store.loadTableData(widget.tableName, resetPagination: true);
                  },
                ),
              ),
              const SizedBox(width: 6),
              // 搜索按钮
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(60, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () {
                  widget.store.loadTableData(widget.tableName, resetPagination: true);
                },
                child: const Text('执行'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDataTable() {
    return Observer(
      builder: (context) {
        if (widget.store.tableColumns.isEmpty || (widget.store.isLoading && widget.store.tableData.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }

        if (widget.store.tableData.isEmpty) {
          return const Center(child: Text('没有数据'));
        }

        return Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: Scrollbar(
              controller: _verticalController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _verticalController,
                scrollDirection: Axis.vertical,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.grey.withValues(alpha: 0.2),
                  ),
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 30,
                    dataRowMaxHeight: 60,
                    horizontalMargin: 12,
                    columnSpacing: 20,
                    sortColumnIndex: widget.store.sortColumn != null 
                      ? widget.store.tableColumns.indexOf(widget.store.sortColumn!)
                      : null,
                    sortAscending: widget.store.sortAscending,
                    columns: widget.store.tableColumns.map((col) {
                      return DataColumn(
                        label: Text(col, style: const TextStyle(fontWeight: FontWeight.bold)),
                        onSort: (index, ascending) {
                          widget.store.setSort(col);
                          widget.store.loadTableData(widget.tableName, resetPagination: false);
                        },
                      );
                    }).toList(),
                    rows: widget.store.tableData.map((row) {
                      return DataRow(
                        cells: widget.store.tableColumns.map((col) {
                          final value = row[col]?.toString() ?? '';
                          return DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 300),
                              child: SelectableText(
                                value,
                                maxLines: 2,
                                scrollPhysics: const NeverScrollableScrollPhysics(),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Observer(
      builder: (context) {
        final start = widget.store.currentPage * widget.store.pageSize + 1;
        final end = (widget.store.currentPage + 1) * widget.store.pageSize;
        final actualEnd = (end > widget.store.totalCount) ? widget.store.totalCount : end;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '第 $start - $actualEnd 条 (共 ${widget.store.totalCount} 条)',
                style: const TextStyle(fontSize: 12),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 16),
                    onPressed: widget.store.currentPage > 0 
                      ? () {
                          widget.store.prevPage();
                          widget.store.loadTableData(widget.tableName, resetPagination: false);
                        }
                      : null,
                  ),
                  Text('${widget.store.currentPage + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 16),
                    onPressed: (widget.store.currentPage + 1) * widget.store.pageSize < widget.store.totalCount
                      ? () {
                          widget.store.nextPage();
                          widget.store.loadTableData(widget.tableName, resetPagination: false);
                        }
                      : null,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
