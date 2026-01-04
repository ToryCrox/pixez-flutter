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

import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:pixez/component/painter_avatar.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/downloaded/downloaded_page.dart';
import 'package:pixez/page/user/user_store.dart';
import 'package:pixez/page/user/users_page.dart';

class DownloadedAuthorCard extends StatefulWidget {
  final DownloadedAuthor author;
  final List<DownloadedIllust> illusts;
  final bool showLatestPublished;

  const DownloadedAuthorCard({
    Key? key,
    required this.author,
    required this.illusts,
    required this.showLatestPublished,
  }) : super(key: key);

  @override
  State<DownloadedAuthorCard> createState() => _DownloadedAuthorCardState();
}

class _DownloadedAuthorCardState extends State<DownloadedAuthorCard> {
  int? _totalImageCount;
  int? _totalFileSize;

  @override
  void initState() {
    super.initState();
    _loadImageStats();
  }

  @override
  void didUpdateWidget(DownloadedAuthorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.author.userId != widget.author.userId) {
      _loadImageStats();
    }
  }

  Future<void> _loadImageStats() async {
    if (!downloadStore.isInitialized) return;

    try {
      final stats =
          await downloadStore.getAuthorImageStats(widget.author.userId);
      if (mounted) {
        setState(() {
          _totalImageCount = stats['total_image_count'];
          _totalFileSize = stats['total_file_size'];
        });
      }
    } catch (e) {
      // 忽略错误，保持当前状态
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DownloadedPage(
              initialUserId: widget.author.userId,
              initialUserName: widget.author.userName,
            ),
          ),
        );
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildPreviewSection(context),
            _buildAuthorInfo(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection(BuildContext context) {
    final illusts = widget.illusts;

    return SizedBox(
      height: 120, // 固定预览区域高度
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: i < illusts.length
                  ? _buildCoverImage(context, illusts[i])
                  : Container(
                      color: Theme.of(context).cardColor,
                    ),
            ),
        ],
      ),
    );
  }

  /// 使用 PixivImage 加载封面，通过 header 传递 illustId 让 PixivCacheManager 识别并缓存
  Widget _buildCoverImage(BuildContext context, DownloadedIllust illust) {
    // 优化：直接使用 imageUrls 字段，无需解析 illustJson
    // 对于旧数据（imageUrlsJson 为空），回退到解析 illustJson
    final imageUrls = illust.getImageUrls();
    String coverUrl = imageUrls.squareMedium;
    if (coverUrl.isEmpty) {
      final illusts = illust.toIllusts();
      coverUrl = illusts.imageUrls.squareMedium;
    }

    return PixivImage(
      coverUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // 通过 header 传递 illustId，让 PixivCacheManager 识别封面请求
      httpHeaders: {'cover': '${illust.illustId}'},
    );
  }

  Widget _buildAuthorInfo(BuildContext context) {
    return SizedBox(
      height: 80, // 固定作者信息区域高度
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Hero(
              tag: 'author_${widget.author.userId}_${this.hashCode}',
              child: PainterAvatar(
                url: widget.author.profileImageUrl ?? '',
                id: widget.author.userId,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => UsersPage(
                        id: widget.author.userId,
                        userStore: UserStore(widget.author.userId, null, null),
                        heroTag:
                            'author_${widget.author.userId}_${this.hashCode}',
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.author.userName,
                      style: Theme.of(context).textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${widget.author.illustCount} 作品',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                        ),
                        if (_totalImageCount != null &&
                            _totalImageCount! > 0) ...[
                          SizedBox(width: 8),
                          Text(
                            '$_totalImageCount 张',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                          ),
                        ],
                      ],
                    ),
                    if (_totalImageCount != null &&
                        _totalImageCount! > 0 &&
                        _totalFileSize != null &&
                        _totalFileSize! > 0) ...[
                      SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '平均 ${(_totalFileSize! ~/ _totalImageCount!).formatFileSize()}/张',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[500],
                                      fontSize: 11,
                                    ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '总计 ${_totalFileSize!.formatFileSize()}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[500],
                                      fontSize: 11,
                                    ),
                          ),
                        ],
                      ),
                    ] else if (widget.author.totalFileSize > 0) ...[
                      SizedBox(height: 2),
                      Text(
                        '总计 ${widget.author.totalFileSize.formatFileSize()}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[500],
                              fontSize: 11,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.folder_open),
              iconSize: 20,
              color: Theme.of(context).iconTheme.color,
              tooltip: '打开下载目录',
              onPressed: () => _openAuthorDownloadDirectory(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAuthorDownloadDirectory(BuildContext context) async {
    if (!downloadStore.isInitialized) {
      BotToast.showText(text: '下载功能未初始化');
      return;
    }
    try {
      final dirPath = downloadStore.getAuthorDirectoryPath(widget.author);
      
      if (dirPath == null) {
        BotToast.showText(text: '无法获取下载目录');
        return;
      }

      final directory = Directory(dirPath);
      if (await directory.exists()) {
        await OpenFile.open(dirPath);
      } else {
        BotToast.showText(text: '目录不存在: $dirPath');
      }
    } catch (e) {
      BotToast.showText(text: '打开文件夹失败: $e');
    }
  }
}
