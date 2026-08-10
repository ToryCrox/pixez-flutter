import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pixez/models/original_image.dart';
import 'package:pixez/store/original_import_service.dart';

/// 下载图与原图的单页对照预览。
class OriginalMappingComparisonTile extends StatelessWidget {
  final OriginalImportMappingManifest mapping;
  final Future<String?> downloadPathFuture;
  final String? originalPath;
  final bool editable;
  final VoidCallback? onEditDownloaded;
  final VoidCallback? onEditOriginal;
  final VoidCallback? onRemove;
  final ValueChanged<OriginalRelationType> onRelationChanged;

  const OriginalMappingComparisonTile({
    super.key,
    required this.mapping,
    required this.downloadPathFuture,
    required this.originalPath,
    required this.editable,
    this.onEditDownloaded,
    this.onEditOriginal,
    this.onRemove,
    required this.onRelationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final downloadLabel =
        mapping.downloadedPart == null
            ? '下载图 —'
            : '下载图 ${mapping.downloadedPart! + 1}';
    final originalLabel =
        mapping.originalSourceOrder == null
            ? '原图 —'
            : '原图 ${mapping.originalSourceOrder! + 1}';
    return Container(
      height: 132,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '${mapping.displayOrder + 1}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          _MappingImage(
            label: downloadLabel,
            pathFuture: downloadPathFuture,
            icon: Icons.download_outlined,
            onEdit: onEditDownloaded,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.compare_arrows),
          ),
          _MappingImage(
            label: originalLabel,
            pathFuture: Future<String?>.value(originalPath),
            icon: Icons.photo_outlined,
            onEdit: onEditOriginal,
          ),
          const Spacer(),
          if (onRemove != null)
            IconButton(
              tooltip: '忽略此显示页',
              onPressed: editable ? onRemove : null,
              icon: const Icon(Icons.visibility_off_outlined),
            ),
          DropdownButton<OriginalRelationType>(
            value: mapping.relationType,
            onChanged:
                editable
                    ? (value) {
                      if (value != null) onRelationChanged(value);
                    }
                    : null,
            items: const [
              DropdownMenuItem(
                value: OriginalRelationType.replacement,
                child: Text('原图替换'),
              ),
              DropdownMenuItem(
                value: OriginalRelationType.originalOnly,
                child: Text('原图新增'),
              ),
              DropdownMenuItem(
                value: OriginalRelationType.downloadFallback,
                child: Text('下载补位'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MappingImage extends StatelessWidget {
  final String label;
  final Future<String?> pathFuture;
  final IconData icon;
  final VoidCallback? onEdit;

  const _MappingImage({
    required this.label,
    required this.pathFuture,
    required this.icon,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onEdit != null)
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.edit_outlined, size: 16),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: FutureBuilder<String?>(
              future: pathFuture,
              builder: (context, snapshot) {
                final path = snapshot.data;
                if (path == null) {
                  return Center(child: Icon(icon, color: colorScheme.outline));
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, _, _) => Center(
                          child: Icon(icon, color: colorScheme.outline),
                        ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
