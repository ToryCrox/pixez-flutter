/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/constants.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/downloaded/downloaded_page_store.dart';
import 'package:pixez/page/history/history_manager.dart';
import 'package:pixez/store/download_store.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:pixez/component/hover_scale_container.dart';
import 'package:pixez/page/downloaded/author_image_organizer_page.dart';

/// 已下载插画卡片组件
class DownloadedIllustCard extends StatelessWidget {
  final DownloadedIllust illust;
  final DownloadedPageStore store;
  final ValueChanged<Offset> onTapPosition;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSecondaryTap;
  final VoidCallback onOpenFolder;
  final VoidCallback onRefreshData;
  final VoidCallback? onAuthorTap;

  const DownloadedIllustCard({
    required this.illust,
    required this.store,
    required this.onTapPosition,
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTap,
    required this.onOpenFolder,
    required this.onRefreshData,
    this.onAuthorTap,
  });

  Widget _buildThumbnail(BuildContext context) {
    final heroTag = 'downloaded_illust_${illust.illustId}';

    final String quality = userSetting.previewQuality;
    String coverUrl;

    if (!userSetting.useWaterfallFlow) {
      // 网格模式：直接从 imageUrlsJson 获取 squareMedium，避免解析完整的 illustJson
      coverUrl = illust.getImageUrls().squareMedium;
    } else {
      // 瀑布流模式：根据设置选择对应的 URL
      final imageUrls = illust.getImageUrls();
      if (userSetting.feedPreviewQuality == Constants.qualityLevelMedium) {
        coverUrl = imageUrls.medium;
      } else if (userSetting.feedPreviewQuality ==
          Constants.qualityLevelLarge) {
        coverUrl = imageUrls.large;
      } else {
        // 原图质量或兜底：才需要解析完整的 Illusts 对象以获取原图 URL
        coverUrl = illust.toIllusts().previewUrl;
      }
    }

    Widget imageWidget = PixivImage(
      coverUrl,
      fit: BoxFit.cover,
      httpHeaders: {'cover': '${illust.illustId}', 'quality': quality},
      memCacheWidth: 480,
    );

    return Hero(tag: heroTag, child: imageWidget);
  }

  Widget _buildOrganizerButton(BuildContext context) {
    return Positioned(
      top: 38,
      left: 4,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => AuthorImageOrganizerPage.pushByUserId(
            context,
            userId: illust.userId,
            illustId: illust.illustId,
          ),
          child: Container(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.collections, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderButton(BuildContext context) {
    return Positioned(
      top: 4,
      left: 4,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpenFolder,
          child: Container(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.folder_open, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarkButton(BuildContext context) {
    final bool isBookmarked = illust.bookmark > 0;
    return Positioned(
      bottom: 4,
      left: 4,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            final newBookmark = isBookmarked ? 0 : 1;
            store.updateBookmark(illust.illustId, newBookmark);
          },
          onLongPress: () => _showPriorityDialog(context),
          child: Container(
            padding: EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isBookmarked ? Icons.favorite : Icons.favorite_border,
                  color: isBookmarked ? Colors.red : Colors.white,
                  size: 18,
                ),
                if (illust.bookmark > 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Text(
                      '${illust.bookmark}',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
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

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final status = store.illustDownloadStatus[illust.illustId];
        final isSelected =
            store.isMultiSelectMode &&
            store.selectedIllustIds.contains(illust.illustId);

        final card = _buildCard(context, status, isSelected);

        if (store.enableDrag) {
          return DragItemWidget(
            dragItemProvider: _createDragItemProvider,
            allowedOperations: () => [DropOperation.copy, DropOperation.link],
            dragBuilder:
                (context, child) =>
                    _buildDragPreview(context, child, isSelected),
            child: DraggableWidget(
              child: card,
              onDragConfiguration:
                  (config, session) =>
                      _createDragConfiguration(config, session, isSelected),
            ),
          );
        } else {
          return card;
        }
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    DownloadTaskStatus? status,
    bool isSelected,
  ) {
    final isMarked = store.unprocessedIllustIds.contains(illust.illustId);

    // 修改：直接使用封装好的 HoverScaleCard 提供悬浮效果和原生的 Surface Tint
    return HoverScaleCard(
      isSelected: isSelected,
      child: InkWell(
        onTap: () {
          if (store.isMultiSelectMode) {
            store.setItemSelected(illust.illustId, !isSelected);
          } else {
            onTap();
          }
        },
        onTapDown: (details) => onTapPosition(details.globalPosition),
        onLongPress: store.isMultiSelectMode ? null : onLongPress,
        onSecondaryTapUp: (details) {
          onTapPosition(details.globalPosition);
          onSecondaryTap();
        },
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildThumbnailStack(context, status, isMarked, isSelected),
                ),
                _buildInfoSection(context),
              ],
            ),
            _buildHistoryProgress(context),
          ],
        ),
      ),
    );
  }

  /// 构建缩略图区域的 Stack，包含图层覆盖和各种 Badge
  Widget _buildThumbnailStack(
    BuildContext context,
    DownloadTaskStatus? status,
    bool isMarked,
    bool isSelected,
  ) {
    final isDownloading = status == DownloadTaskStatus.downloading;
    final isPending = status == DownloadTaskStatus.pending;
    final isPaused = status == DownloadTaskStatus.paused;
    final isFailed = status == DownloadTaskStatus.failed;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildThumbnail(context),
        _buildFolderButton(context),
        _buildOrganizerButton(context),
        if (illust.isUgoira) _buildUgoiraBadge(context),
        if (isMarked) _buildUnprocessedBadge(context),
        if (store.isExample(illust.illustId)) _buildExampleBadge(context),
        _buildBookmarkButton(context),
        _buildLastReadBadge(context),
        if (isDownloading) _buildDownloadingOverlay(),
        if (isPending) _buildPendingOverlay(context),
        if (isPaused)
          _buildStatusBadge(
            context,
            I18n.of(context).paused,
            Colors.orange,
          ),
        if (isFailed) _buildFailedOverlay(context),
        // 多选模式下的复选框指示器
        if (store.isMultiSelectMode) _buildSelectionOverlay(context, isSelected),
      ],
    );
  }

  /// 构建选择模式下的覆盖层
  Widget _buildSelectionOverlay(BuildContext context, bool isSelected) {
    final color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Colors.black45;

    Widget child;
    if (isSelected) {
      child = const Icon(
        Icons.check,
        size: 16,
        color: Colors.white,
      );
    } else {
      child = const SizedBox(width: 16, height: 16);
    }

    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: child,
        ),
      ),
    );
  }

  DragConfiguration? _createDragConfiguration(
    DragConfiguration config,
    DragSession session,
    bool isSelected,
  ) {
    // 处理多选和文件过滤逻辑
    final selectedIds = <int>[];
    if (store.isMultiSelectMode) {
      selectedIds.addAll(store.selectedIllustIds);
      // 如果当前拖拽的项不在选中列表中，则只拖拽当前项（或者视为单选拖拽）
      if (!selectedIds.contains(illust.illustId)) {
        selectedIds.clear();
        selectedIds.add(illust.illustId);
      }
    } else {
      selectedIds.add(illust.illustId);
    }

    if (selectedIds.isEmpty) return null;

    // 获取 snapshot (复用当前拖拽项的 snapshot)
    final snapshot = config.items.firstOrNull?.image;
    if (snapshot == null) return null;

    final targetIllusts =
        store.filteredIllusts
            .where((i) => selectedIds.contains(i.illustId))
            .toList();

    // 确保至少包含当前插画
    if (targetIllusts.isEmpty && selectedIds.contains(illust.illustId)) {
      targetIllusts.add(illust);
    }

    final newItems = <DragConfigurationItem>[];

    if (!store.enableDrag) return null;

    if (store.isMultiSelectMode) {
      // 这里的逻辑保持不变：如果是多选模式且选中了当前项，则拖拽所有选中项
      // 否则只拖拽当前项（_createDragConfiguration start时已处理 selectedIds）
    }

    // 默认拖拽整个文件夹 (无需数据库查询，直接字符串拼接，速度极快)
    for (final targetIllust in targetIllusts) {
      final dirPath = downloadStore.getIllustDirectoryPath(targetIllust);
      if (dirPath != null) {
        final dragItem = DragItem();
        dragItem.add(Formats.fileUri(Uri.file(dirPath)));
        newItems.add(DragConfigurationItem(item: dragItem, image: snapshot));
      }
    }

    if (newItems.isEmpty) return null;

    return DragConfiguration(
      items: newItems,
      allowedOperations: config.allowedOperations,
      options: config.options,
    );
  }

  // 原始方法已废弃，直接在 _createDragConfiguration 中批量处理
  // Future<List<Uri>> _getIllustFileUris...

  Widget _buildUgoiraBadge(BuildContext context) {
    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '动图',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildExampleBadge(BuildContext context) {
    return Positioned(
      top: 4,
      right: illust.isUgoira ? 40 : 4,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blueAccent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star, color: Colors.white, size: 10),
            SizedBox(width: 2),
            Text(
              '示例',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black38,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingOverlay(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black26,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty, color: Colors.white, size: 32),
              SizedBox(height: 4),
              Text('等待下载', style: TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFailedOverlay(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black45,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => downloadStore.resumeIllustDownload(illust.illustId),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh, color: Colors.red, size: 32),
                    const SizedBox(height: 4),
                    Text(
                      I18n.of(context).failed,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const Text(
                      '点击重试',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryProgress(BuildContext context) {
    return Observer(
      builder: (context) {
        final history = HistoryManager.instance.getHistory(illust.illustId);
        if (history == null || history.totalPages <= 1) {
          return const SizedBox.shrink();
        }
        return Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(
            value: history.progress.clamp(0.0, 1.0),
            minHeight: 3,
            backgroundColor: Colors.black26,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );
  }

  // 移除 _buildReadBadge

  Widget _buildLastReadBadge(BuildContext context) {
    return Observer(
      builder: (context) {
        final history = HistoryManager.instance.getHistory(illust.illustId);
        if (history == null) return const SizedBox.shrink();

        final readTime = history.timestamp.toRelativeTime();
        // 移除 readTime == null 的检查，因为 toRelativeTime() 总是返回 String

        String labelText = readTime;
        if (history.totalPages > 1) {
          labelText = "$readTime · ${history.lastPage + 1}/${history.totalPages}P";
        }

        return Positioned(
          right: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.history, color: Colors.white, size: 10),
                const SizedBox(width: 4),
                Text(
                  labelText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(BuildContext context, String text, Color color) {
    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: TextStyle(color: Colors.white, fontSize: 10)),
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleRow(context),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(child: _buildAuthorName(context)),
              Text(
                illust.createDate.toShortDate(),
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
              ),
            ],
          ),
          _buildStatsRow(context),
        ],
      ),
    );
  }

  /// 构建作者名称显示，处理跳转逻辑
  Widget _buildAuthorName(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.primary,
    );

    // 如果不能点击跳转，直接显示文本
    if (onAuthorTap == null) {
      return Text(
        illust.userName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    // 处理跳转逻辑
    return InkWell(
      onTap: store.isMultiSelectMode ? null : onAuthorTap,
      borderRadius: BorderRadius.circular(4),
      child: Text(
        illust.userName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style?.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildTitleRow(BuildContext context) {
    return Text(
      illust.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    final totalFileSize = illust.totalFileSize; // 使用物化字段
    final isUgoira = illust.isUgoira;

    return Row(
      children: [
        // 动图或多页插画都显示页数/帧数信息
        if (isUgoira || illust.pageCount > 1)
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: _buildPageCountIndicator(context, totalFileSize, isUgoira),
          ),
        Spacer(),
        if (totalFileSize > 0) // 物化字段不为 null
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              totalFileSize.formatFileSize(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPageCountIndicator(
    BuildContext context,
    int? totalFileSize,
    bool isUgoira,
  ) {
    if (isUgoira) {
      // 动图特殊处理：显示帧数
      return _buildUgoiraFrameIndicator(context, totalFileSize);
    }

    // 普通插画：显示页数
    final downloadedCount = illust.downloadedImageCount; // 使用物化字段
    final totalCount = illust.pageCount;

    String pageText;
    if (downloadedCount < totalCount) {
      pageText = '$downloadedCount/$totalCount';
    } else {
      pageText = '${totalCount}P';
    }

    String? avgSizeText;
    if (totalFileSize != null && totalFileSize > 0 && totalCount > 0) {
      final avgSize = totalFileSize ~/ totalCount;
      avgSizeText = avgSize.formatFileSize();
    }

    if (avgSizeText != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pageText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: downloadedCount < totalCount ? Colors.orange : null,
            ),
          ),
          SizedBox(width: 4),
          Text(
            '· $avgSizeText/P',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[600],
              fontSize: 11,
            ),
          ),
        ],
      );
    } else {
      return Text(
        pageText,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: downloadedCount < totalCount ? Colors.orange : null,
        ),
      );
    }
  }

  /// 构建动图帧数指示器
  Widget _buildUgoiraFrameIndicator(BuildContext context, int? totalFileSize) {
    final downloadedCount = illust.downloadedImageCount; // 使用物化字段

    // 动图的 downloadedCount 包含预览图(part=0)和所有帧(part=1,2,3...)
    // Ugoira 的 pageCount 通常为 1，因此需要从元数据解析真实总帧数
    final totalFrames = illust.getUgoiraFrames()?.length ?? 0;
    
    // 如果 downloadedCount 为 2 且元数据中记录的帧数 > 1，说明已经合并为单个 WebP (预览图 + WebP)
    final isMerged = illust.isUgoira && downloadedCount == 2 && totalFrames > 1;
    
    // 实际帧数逻辑：已合并则取 totalFrames，未合并取已下载数-1
    final frameCount = isMerged ? totalFrames : (downloadedCount > 0 ? downloadedCount - 1 : 0);

    String frameText;
    if (frameCount > 0) {
      frameText = isMerged ? '${frameCount}帧(合并)' : '${frameCount}帧';
    } else {
      frameText = '动图';
    }

    // 计算平均每帧大小
    String? avgSizeText;
    if (totalFileSize != null && totalFileSize > 0 && frameCount > 0) {
      final avgSize = totalFileSize ~/ frameCount;
      avgSizeText = avgSize.formatFileSize();
    }

    if (avgSizeText != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            frameText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: 4),
          Text(
            '· $avgSizeText/帧',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[600],
              fontSize: 11,
            ),
          ),
        ],
      );
    } else {
      return Text(
        frameText,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.orange,
          fontWeight: FontWeight.w500,
        ),
      );
    }
  }

  Widget _buildUnprocessedBadge(BuildContext context) {
    return Positioned(
      top: 8,
      left: 36,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '未处理',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildDragPreview(
    BuildContext context,
    Widget child,
    bool isSelected,
  ) {
    // 如果多选，显示数量角标
    final count =
        store.isMultiSelectMode && isSelected
            ? store.selectedIllustIds.length
            : 1;

    // 拖动时透明度太低问题：
    // 使用 Material 并不透明背景，包裹 Opacity 控制透明度（如果需要）
    // 或者完全不透明。用户反馈“看不清楚”，倾向于更不透明。

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 150,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            child, // 复用 Card
            if (count > 1)
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<DragItem> _createDragItemProvider(DragItemRequest request) async {
    final item = DragItem();
    item.add(Formats.plainText('PixEz Downloaded Illust'));
    return item;
  }

  void _showPriorityDialog(BuildContext context) {
    int tempBookmark = illust.bookmark;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('设置插画收藏优先级'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('数值越大优先级越高 (0-99)。\n0 表示取消收藏。'),
                  SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '优先级: ${tempBookmark.toInt()}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (tempBookmark > 0)
                        Icon(Icons.favorite, color: Colors.red),
                    ],
                  ),
                  Slider(
                    value: tempBookmark.toDouble(),
                    min: 0,
                    max: 99,
                    divisions: 99,
                    label: tempBookmark.toString(),
                    onChanged: (double value) {
                      setState(() {
                        tempBookmark = value.round();
                      });
                    },
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => tempBookmark = 0),
                        child: Text('取消收藏(0)'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => tempBookmark = 1),
                        child: Text('默认(1)'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => tempBookmark = 99),
                        child: Text('置顶(99)'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    store.updateBookmark(illust.illustId, tempBookmark);
                    Navigator.pop(context);
                  },
                  child: Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
