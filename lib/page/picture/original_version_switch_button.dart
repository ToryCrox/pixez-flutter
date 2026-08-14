import 'package:flutter/material.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/original_image.dart';
import 'package:pixez/page/picture/illust_store.dart';

/// 插画详情页左下角的图片版本快捷入口。
///
/// 点击会在下载版和各原图版本之间循环；长按可直接选择版本，或进入
/// 原图导入、版本管理流程。
class OriginalVersionSwitchButton extends StatelessWidget {
  final IllustStore store;
  final Future<void> Function(OriginalDisplayMode mode) onModeSelected;
  final Future<void> Function(int setId) onSetSelected;
  final Future<void> Function() onImport;
  final Future<void> Function() onManage;

  const OriginalVersionSwitchButton({
    super.key,
    required this.store,
    required this.onModeSelected,
    required this.onSetSelected,
    required this.onImport,
    required this.onManage,
  });

  Future<bool> _hasDownloadedVersion() async =>
      (await downloadStore.getLocalImageInfos(store.id)).isNotEmpty;

  Future<void> _cycleVersion() async {
    final sets = List<OriginalImageSet>.from(store.originalSets);
    if (sets.isEmpty) return;
    final hasDownloaded = await _hasDownloadedVersion();
    if (store.displayMode == OriginalDisplayMode.downloaded) {
      await onSetSelected(sets.first.id!);
      return;
    }

    final currentIndex = sets.indexWhere(
      (set) => set.id == store.selectedOriginalSetId,
    );
    if (currentIndex >= 0 && currentIndex + 1 < sets.length) {
      await onSetSelected(sets[currentIndex + 1].id!);
    } else if (hasDownloaded) {
      await onModeSelected(OriginalDisplayMode.downloaded);
    } else {
      await onSetSelected(sets.first.id!);
    }
  }

  Future<void> _showMenu(BuildContext context) async {
    final hasDownloaded = await _hasDownloadedVersion();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final sets = List<OriginalImageSet>.from(store.originalSets);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  leading: Icon(Icons.layers_outlined),
                  title: Text('显示图片版本'),
                ),
                if (hasDownloaded)
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('下载版'),
                    trailing:
                        store.displayMode == OriginalDisplayMode.downloaded
                            ? const Icon(Icons.check)
                            : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onModeSelected(OriginalDisplayMode.downloaded);
                    },
                  ),
                for (final set in sets)
                  ListTile(
                    leading: Icon(set.isDefault ? Icons.hd : Icons.hd_outlined),
                    title: Text(set.editionName),
                    subtitle: Text('${set.imageCount} 张原图'),
                    trailing:
                        store.displayMode ==
                                    OriginalDisplayMode.originalPreferred &&
                                store.selectedOriginalSetId == set.id
                            ? const Icon(Icons.check)
                            : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onSetSelected(set.id!);
                    },
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.add_photo_alternate_outlined),
                  title: const Text('更新或添加原图版本'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onImport();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('管理原图版本'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onManage();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final label =
        store.displayMode == OriginalDisplayMode.downloaded
            ? '下载版'
            : (store.displayManifest?.edition?.editionName ?? '原图');
    return Tooltip(
      message: '点击切换图片版本，长按管理原图版本',
      child: Material(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(20),
          onTap: _cycleVersion,
          onLongPress: () => _showMenu(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hd_outlined, color: Colors.white, size: 18),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
