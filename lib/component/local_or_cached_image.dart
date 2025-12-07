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

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/custom/log.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/main.dart';
import 'package:pixez/store/download_store.dart';

/// 优先加载本地已下载图片的组件
/// 如果本地没有，则回退到网络加载
class LocalOrCachedImage extends StatefulWidget {
  final int illustId;
  final int part;
  final String networkUrl;
  final String? localPath; // 新增：预加载的本地路径
  final Widget? placeWidget;
  final bool fade;
  final BoxFit? fit;
  final double? height;
  final double? width;

  const LocalOrCachedImage({
    Key? key,
    required this.illustId,
    required this.part,
    required this.networkUrl,
    this.localPath, // 新增参数
    this.placeWidget,
    this.fade = true,
    this.fit,
    this.height,
    this.width,
  }) : super(key: key);

  @override
  State<LocalOrCachedImage> createState() => _LocalOrCachedImageState();
}

class _LocalOrCachedImageState extends State<LocalOrCachedImage> {
  String? _localPath;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    // 如果已经提供了本地路径，直接使用
    if (widget.localPath != null) {
      _localPath = widget.localPath;
      _checked = true;
    } else {
      _checkLocalFile();
    }
  }

  @override
  void didUpdateWidget(covariant LocalOrCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.illustId != widget.illustId ||
        oldWidget.part != widget.part ||
        oldWidget.networkUrl != widget.networkUrl ||
        oldWidget.localPath != widget.localPath) {
      _checked = false;
      _localPath = null;
      // 如果提供了新的本地路径，直接使用
      if (widget.localPath != null) {
        _localPath = widget.localPath;
        _checked = true;
      } else {
        _checkLocalFile();
      }
    }
  }

  Future<void> _checkLocalFile() async {
    if (!downloadStore.isInitialized) {
      if (mounted) {
        setState(() {
          _checked = true;
        });
      }
      return;
    }

    try {
      final path = await downloadStore.getLocalImagePath(
        widget.illustId,
        widget.part,
      );
      Log.d('LocalOrCachedImage path: $path');
      if (mounted) {
        setState(() {
          _localPath = path;
          _checked = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checked = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 还在检查中，显示占位
    if (!_checked) {
      return widget.placeWidget ??
          Container(
            height: widget.height,
            width: widget.width,
          );
    }

    // 如果有本地文件，优先显示本地文件
    if (_localPath != null) {
      return Image.file(
        File(_localPath!),
        fit: widget.fit ?? BoxFit.fitWidth,
        height: widget.height,
        width: widget.width,
        errorBuilder: (context, error, stackTrace) {
          // 本地文件加载失败，回退到网络
          return _buildNetworkImage();
        },
      );
    }

    // 没有本地文件，使用网络加载
    return _buildNetworkImage();
  }

  Widget _buildNetworkImage() {
    return PixivImage(
      widget.networkUrl,
      placeWidget: widget.placeWidget,
      fade: widget.fade,
      fit: widget.fit,
      height: widget.height,
      width: widget.width,
    );
  }
}

/// 用于PhotoView的本地或网络图片Provider
class LocalOrCachedImageProvider {
  final int illustId;
  final int part;
  final String networkUrl;

  LocalOrCachedImageProvider({
    required this.illustId,
    required this.part,
    required this.networkUrl,
  });

  Future<ImageProvider> getProvider() async {
    if (!downloadStore.isInitialized) {
      return CachedNetworkImageProvider(
        networkUrl,
        headers: Hoster.header(url: networkUrl),
        cacheManager: pixivCacheManager,
      );
    }

    try {
      final path = await downloadStore.getLocalImagePath(illustId, part);
      if (path != null && await File(path).exists()) {
        return FileImage(File(path));
      }
    } catch (_) {}

    return CachedNetworkImageProvider(
      networkUrl,
      headers: Hoster.header(url: networkUrl),
      cacheManager: pixivCacheManager,
    );
  }
}

/// PhotoView专用的图片加载器
class LocalOrPhotoViewImage extends StatefulWidget {
  final int illustId;
  final int part;
  final String networkUrl;
  final Object? heroTag;
  final PhotoViewComputedScale? initialScale;
  final Widget Function(BuildContext, ImageChunkEvent?)? loadingBuilder;

  const LocalOrPhotoViewImage({
    Key? key,
    required this.illustId,
    required this.part,
    required this.networkUrl,
    this.heroTag,
    this.initialScale,
    this.loadingBuilder,
  }) : super(key: key);

  @override
  State<LocalOrPhotoViewImage> createState() => _LocalOrPhotoViewImageState();
}

class _LocalOrPhotoViewImageState extends State<LocalOrPhotoViewImage> {
  ImageProvider? _imageProvider;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProvider();
  }

  @override
  void didUpdateWidget(covariant LocalOrPhotoViewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.illustId != widget.illustId ||
        oldWidget.part != widget.part ||
        oldWidget.networkUrl != widget.networkUrl) {
      _loading = true;
      _imageProvider = null;
      _loadProvider();
    }
  }

  Future<void> _loadProvider() async {
    final provider = LocalOrCachedImageProvider(
      illustId: widget.illustId,
      part: widget.part,
      networkUrl: widget.networkUrl,
    );

    final imageProvider = await provider.getProvider();
    if (mounted) {
      setState(() {
        _imageProvider = imageProvider;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _imageProvider == null) {
      return Center(
        child: CircularProgressIndicator(),
      );
    }

    return PhotoView(
      imageProvider: _imageProvider,
      filterQuality: FilterQuality.high,
      initialScale: widget.initialScale ?? PhotoViewComputedScale.contained,
      heroAttributes: widget.heroTag != null
          ? PhotoViewHeroAttributes(tag: widget.heroTag!)
          : null,
      loadingBuilder: widget.loadingBuilder,
    );
  }
}

/// 下载状态指示器组件
/// 支持三种状态: 下载中(显示进度)、下载完成、未下载
class DownloadStatusIndicator extends StatefulWidget {
  final int illustId;
  final int pageCount;
  final double size;
  final Color? downloadedColor;
  final Color? downloadingColor;

  const DownloadStatusIndicator({
    Key? key,
    required this.illustId,
    this.pageCount = 1,
    this.size = 16,
    this.downloadedColor,
    this.downloadingColor,
  }) : super(key: key);

  @override
  State<DownloadStatusIndicator> createState() =>
      _DownloadStatusIndicatorState();
}

enum _DownloadStatus {
  none,
  pending,
  downloading,
  downloaded,
  failed,
}

class _DownloadStatusIndicatorState extends State<DownloadStatusIndicator> {
  IllustDownloadStatus? _status;
  StreamSubscription<IllustDownloadStatus>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription =
        downloadStore.illustDownloadStatusStream.listen(_onProgressUpdate);
    _checkStatus();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DownloadStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.illustId != widget.illustId) {
      _checkStatus();
    }
  }

  void _onProgressUpdate(IllustDownloadStatus status) {
    if (status.illusts.illustId != widget.illustId) return;
    if (!mounted) return;

    setState(() {
      _status = status;
    });
  }

  Future<void> _checkStatus() async {
    if (!downloadStore.isInitialized) {
      if (mounted) {
        setState(() {
          _status = null;
        });
      }
      return;
    }
    _status = await downloadStore.getIllustDownloadStatus(widget.illustId);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final taskStatus = status?.status;
    if (taskStatus == null || status == null) {
      return const SizedBox.shrink();
    }
    switch (taskStatus) {
      case DownloadTaskStatus.completed:
        if (status.isAllDownloaded) {
          return _buildDownloadedIcon();
        }
        return _buildDownloadUncompletedIcon();
      case DownloadTaskStatus.downloading:
        return _buildDownloadingIndicator();
      case DownloadTaskStatus.pending:
        return _buildPendingIndicator();
      case DownloadTaskStatus.failed:
        return _buildFailedIcon();
      case DownloadTaskStatus.paused:
        return _buildPausedIcon();
    }
  }

  Widget _buildDownloadUncompletedIcon() {
    return Icon(
      Icons.download,
      size: widget.size,
      color: widget.downloadedColor ?? Colors.green,
    );
  }

  Widget _buildDownloadedIcon() {
    return Icon(
      Icons.download_done,
      size: widget.size,
      color: widget.downloadedColor ?? Colors.green,
    );
  }

  Widget _buildPendingIndicator() {
    return Icon(
      Icons.schedule,
      size: widget.size,
      color: Colors.grey,
    );
  }

  Widget _buildDownloadingIndicator() {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            //value: _currentProgress > 0 ? _currentProgress : null,
            strokeWidth: 2,
            color: widget.downloadingColor ??
                Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildFailedIcon() {
    return Icon(
      Icons.error,
      size: widget.size,
      color: Colors.red,
    );
  }

  Widget _buildPausedIcon() {
    return Icon(
      Icons.pause,
      size: widget.size,
      color: Colors.grey,
    );
  }
}
