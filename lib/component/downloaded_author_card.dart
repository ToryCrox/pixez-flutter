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

import 'package:flutter/material.dart';
import 'package:pixez/component/painter_avatar.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/recommend.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/page/downloaded/downloaded_page.dart';
import 'package:pixez/page/user/user_store.dart';
import 'package:pixez/page/user/users_page.dart';

class DownloadedAuthorCard extends StatefulWidget {
  final DownloadedAuthor author;

  const DownloadedAuthorCard({Key? key, required this.author})
      : super(key: key);

  @override
  State<DownloadedAuthorCard> createState() => _DownloadedAuthorCardState();
}

class _DownloadedAuthorCardState extends State<DownloadedAuthorCard> {
  bool _showLatestPublished = false;
  List<DownloadedIllust> _downloadedIllusts = [];
  List<Illusts> _publishedIllusts = [];
  bool _loadingPublished = false;

  @override
  void initState() {
    super.initState();
    _loadDownloadedIllusts();
  }

  Future<void> _loadDownloadedIllusts() async {
    final illusts = await downloadStore.getAuthorLatestIllusts(
      widget.author.userId,
      limit: 3,
    );
    if (mounted) {
      setState(() {
        _downloadedIllusts = illusts;
      });
    }
  }

  Future<void> _loadPublishedIllusts() async {
    if (_loadingPublished || _publishedIllusts.isNotEmpty) return;

    setState(() {
      _loadingPublished = true;
    });

    try {
      final response = await apiClient.getUserIllusts(
        widget.author.userId,
        'illust',
      );
      final recommend = Recommend.fromJson(response.data);
      if (mounted) {
        setState(() {
          _publishedIllusts = recommend.illusts.take(3).toList();
          _loadingPublished = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingPublished = false;
        });
      }
    }
  }

  void _togglePreview() {
    setState(() {
      _showLatestPublished = !_showLatestPublished;
    });
    if (_showLatestPublished) {
      _loadPublishedIllusts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context, rootNavigator: true).push(
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
    final showPublished = _showLatestPublished && _publishedIllusts.isNotEmpty;
    final illusts = showPublished ? _publishedIllusts : _downloadedIllusts;

    return Stack(
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: i < illusts.length
                    ? AspectRatio(
                        aspectRatio: 1.0,
                        child: showPublished
                            ? PixivImage(
                                (illusts[i] as Illusts).imageUrls.squareMedium,
                                fit: BoxFit.cover,
                              )
                            : _buildLocalImage(illusts[i] as DownloadedIllust),
                      )
                    : Container(
                        color: Theme.of(context).cardColor,
                      ),
              ),
          ],
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: Icon(
              _showLatestPublished ? Icons.download : Icons.public,
              size: 20,
              color: Colors.white,
            ),
            onPressed: _togglePreview,
            tooltip: _showLatestPublished
                ? '显示最新下载'
                : '显示最新发布',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              padding: EdgeInsets.all(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalImage(DownloadedIllust illust) {
    return FutureBuilder<String?>(
      future: downloadStore.getLocalImagePath(illust.illustId, 0),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.file(
            File(snapshot.data!),
            fit: BoxFit.cover,
            cacheWidth: (200 * MediaQuery.of(context).devicePixelRatio).toInt(),
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Theme.of(context).cardColor,
                child: Icon(Icons.broken_image, color: Colors.grey),
              );
            },
          );
        }
        return Container(
          color: Theme.of(context).cardColor,
        );
      },
    );
  }

  Widget _buildAuthorInfo(BuildContext context) {
    return Padding(
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
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                    builder: (context) => UsersPage(
                      id: widget.author.userId,
                      userStore: UserStore(widget.author.userId, null, null),
                      heroTag: 'author_${widget.author.userId}_${this.hashCode}',
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      SizedBox(width: 8),
                      if (widget.author.totalFileSize > 0)
                        Text(
                          widget.author.totalFileSize.formatFileSize(),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

