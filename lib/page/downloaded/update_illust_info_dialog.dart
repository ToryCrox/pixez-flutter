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
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:pixez/utils/image_utils.dart';
import 'package:pixez/utils/file_utils.dart';
import 'package:path/path.dart' as p;
import 'package:pixez/custom/log.dart';
import 'package:pixez/exts.dart';

import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/picture/illust_lighting_page.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

enum UpdateResultType {
  changed, // 有变化
  broken, // 损坏
  incomplete, // 未下载完整
  inconsistent, // 统计不一致
  unchanged, // 无变化
}

class UpdateIllustInfo {
  DownloadedIllust illust;
  List<ImageUpdateInfo> imageUpdates;
  bool hasChanges = false;
  bool hasBroken = false;
  bool isIncomplete = false; // 是否未下载完整（下载的图片数量和illust里面记录的不同）
  bool hasStatsInconsistency = false; // 物化字段是否不一致
  bool isScanning = false; // 是否正在扫描
  int totalImageCount = 0; // 总图片数
  int scannedImageCount = 0; // 已扫描图片数
  int totalSizeInDb = 0; // 数据库中记录的总大小
  int totalSizeScanned = 0; // 实际扫描的总大小
  bool isUpdated = false; // 是否已成功更新
  String? updateError; // 更新失败的错误信息

  bool isScanned = false; // 是否已扫描完成至少一次

  UpdateResultType get resultType {
    if (!isScanned) return UpdateResultType.unchanged;
    if (hasBroken) return UpdateResultType.broken;
    if (isIncomplete) return UpdateResultType.incomplete;
    if (hasChanges) return UpdateResultType.changed;
    if (hasStatsInconsistency) return UpdateResultType.inconsistent;
    return UpdateResultType.unchanged;
  }

  UpdateIllustInfo({
    required this.illust,
    required this.imageUpdates,
    this.isScanning = false,
    this.totalImageCount = 0,
    this.scannedImageCount = 0,
    this.totalSizeInDb = 0,
    this.totalSizeScanned = 0,
  }) {
    refreshFlags();
  }

  void refreshFlags() {
    if (!isScanned) {
      hasChanges = false;
      hasBroken = false;
      isIncomplete = false;
      hasStatsInconsistency = false;
      return;
    }

    hasChanges = imageUpdates.any((e) => e.hasChange);
    hasBroken = imageUpdates.any((e) => e.isBroken || e.isFileNotFound);

    // 检测是否未下载完整
    final hasMissingFile = imageUpdates.any((e) => e.isFileNotFound);

    final isUgoira = illust.isUgoira;
    if (isUgoira) {
      // 动图特殊处理：检查预览图(part=0)和帧文件(part>=1)
      final hasPreview = imageUpdates.any(
        (e) => e.originalImage.part == 0 && !e.isBroken && !e.isFileNotFound,
      );
      final frameCount =
          imageUpdates
              .where(
                (e) =>
                    e.originalImage.part >= 1 &&
                    !e.isBroken &&
                    !e.isFileNotFound,
              )
              .length;

      // 获取元数据中的帧数
      final metadata = illust.getUgoiraMetadata();
      final expectedFrames = metadata?.frames.length ?? 0;

      final hasWebP = imageUpdates.any(
        (e) =>
            e.originalImage.part == DownloadedImage.partUgoiraWebP &&
            !e.isBroken &&
            !e.isFileNotFound,
      );

      // 动图完整：有预览图 且 (帧数符合预期 或 存在WebP合并文件)
      if (isScanning) {
        // 扫描中：发现明确的文件缺失（isFileNotFound）即为不完整
        isIncomplete = hasMissingFile;
      } else {
        // 扫描完：严格判定
        isIncomplete =
            !hasPreview ||
            (expectedFrames > 0 && frameCount < expectedFrames && !hasWebP);
      }
    } else {
      // 普通插画：比较 pageCount 和实际下载的图片数量
      final downloadedCount =
          imageUpdates.where((e) => !e.isBroken && !e.isFileNotFound).length;

      if (isScanning) {
        // 扫描中：只有发现文件不存在才算不完整，数量不足可能是还没扫到
        isIncomplete = hasMissingFile;
      } else {
        // 扫描完：数量不足即为不完整
        isIncomplete = hasMissingFile || downloadedCount < illust.pageCount;
      }
    }

    // 检测物化字段是否一致
    // 只在扫描完成后检测（imageUpdates 不为空）
    if (!isScanning && imageUpdates.isNotEmpty) {
      final actualCount =
          imageUpdates.where((e) => !e.isBroken && !e.isFileNotFound).length;

      // 检查是否与物化字段不一致
      hasStatsInconsistency =
          illust.downloadedImageCount != actualCount ||
          illust.totalFileSize != totalSizeScanned;
    } else {
      hasStatsInconsistency = false;
    }
  }

  void updateImageUpdates(List<ImageUpdateInfo> updates) {
    if (updates.isNotEmpty) {
      isScanned = true;
    }
    imageUpdates = updates;
    refreshFlags();
    // 计算总大小
    _calculateTotalSize();
  }

  void _calculateTotalSize() {
    // 只更新 totalSizeScanned，totalSizeInDb 在扫描开始时已经设置
    totalSizeScanned = 0;
    for (var update in imageUpdates) {
      if (update.newFileSize != null) {
        totalSizeScanned += update.newFileSize!;
      } else if (!update.isBroken && !update.isFileNotFound) {
        // 如果文件存在但没有扫描到大小，使用数据库中的大小
        totalSizeScanned += update.originalImage.fileSize;
      }
    }
    // 如果 totalSizeInDb 还没有设置（比如在扫描过程中），从 imageUpdates 计算
    if (totalSizeInDb == 0 && imageUpdates.isNotEmpty) {
      totalSizeInDb = 0;
      for (var update in imageUpdates) {
        totalSizeInDb += update.originalImage.fileSize;
      }
    }
    // 重新检测一致性
    refreshFlags();
  }

  void updateScanProgress(int total, int scanned) {
    totalImageCount = total;
    scannedImageCount = scanned;
  }
}

class ImageUpdateInfo {
  final DownloadedImage originalImage;
  final int? newFileSize;
  final String? newExtension;
  final int? newWidth;
  final int? newHeight;
  final bool isBroken; // 文件损坏（无法解析图片）
  final bool isFileNotFound; // 文件不存在
  final String? scannedFilePath; // 扫描阶段获取的文件路径
  bool hasChange = false;

  ImageUpdateInfo({
    required this.originalImage,
    this.newFileSize,
    this.newExtension,
    this.newWidth,
    this.newHeight,
    this.isBroken = false,
    this.isFileNotFound = false,
    this.scannedFilePath,
  }) {
    hasChange =
        (newFileSize != null && newFileSize != originalImage.fileSize) ||
        (newExtension != null && newExtension != originalImage.extension) ||
        (newWidth != null && newWidth != originalImage.width) ||
        (newHeight != null && newHeight != originalImage.height);
  }
}

class UpdateIllustInfoDialog extends StatefulWidget {
  final List<DownloadedIllust> illusts;

  const UpdateIllustInfoDialog({Key? key, required this.illusts})
    : super(key: key);

  @override
  State<UpdateIllustInfoDialog> createState() => _UpdateIllustInfoDialogState();
}


class _UpdateIllustInfoDialogState extends State<UpdateIllustInfoDialog> {
  List<UpdateIllustInfo> _updateInfos = [];
  bool _isScanning = false; // 是否正在扫描
  bool _isPaused = false; // 是否已暂停
  bool _isUpdating = false;
  int _scannedCount = 0;
  int _totalCount = 0;
  int _updatingProgress = 0; // 当前更新进度（已更新的作品数）
  int _totalToUpdate = 0; // 需要更新的总作品数
  UpdateResultType? _filterType;
  List<int> _displayingChildIndexList = []; // 当前处于视口的项索引列表
  String? _errorMessage = null;
  late int _concurrentCount; // 每个作品内并发扫描的图片数量（从 userSetting 读取）
  late ListObserverController _observerController;
  late ScrollController _scrollController;
  bool _isFastScan = true; // 快速扫描模式
  Duration? _scanDuration; // 扫描结束后的总耗时
  Duration? _elapsedDuration; // 实时扫描耗时
  Stopwatch? _stopwatch;
  Timer? _timer;

  // 优化相关的字段
  DateTime _lastSetStateTime = DateTime.fromMillisecondsSinceEpoch(0); // 用于限流 UI 更新

  @override
  void initState() {
    super.initState();
    _concurrentCount = userSetting.updateIllustConcurrentCount;
    _totalCount = widget.illusts.length;
    // 初始化时只创建作品列表，不扫描
    _updateInfos =
        widget.illusts.map((illust) {
          return UpdateIllustInfo(
            illust: illust,
            imageUpdates: [],
            isScanning: false,
          );
        }).toList();
    _scrollController = ScrollController();
    _observerController = ListObserverController(controller: _scrollController);
  }

  @override
  void dispose() {
    _stopTimer();
    _scrollController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _stopwatch != null) {
        setState(() {
          _elapsedDuration = _stopwatch!.elapsed;
        });
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _throttledSetState(VoidCallback fn, {bool force = false}) {
    if (force ||
        DateTime.now().difference(_lastSetStateTime).inMilliseconds > 100) {
      if (mounted) {
        setState(fn);
        _lastSetStateTime = DateTime.now();
      }
    } else {
      fn();
    }
  }



  /// 扫描单张图片 (全异步版本)
  Future<ImageUpdateInfo> _scanSingleImage(
    DownloadedImage image, {
    required DownloadedIllust illust,
    int? knownWidth,
    int? knownHeight,
    bool isFastScan = true,
    Map<String, String>? existingFileMap,
  }) async {
    String? actualPath;
    if (existingFileMap != null) {
      // 优先从预获取的文件映射中查找（基于文件名）
      actualPath = existingFileMap[image.fileName];
    }

    // 如果没有预获取或者预获取中没找到，回退到原始方式（带磁盘检查）
    actualPath ??= await downloadStore.getLocalImagePathFromImage(
      image,
      relativePath: illust.relativePath,
      isUgoira: illust.isUgoira,
      update: false,
      checkExists: existingFileMap == null, // 如果有 map 但没找到，说明确实不存在，这里传 true 会触发后缀遍历检查
    );

    if (actualPath == null) {
      return ImageUpdateInfo(
        originalImage: image,
        isFileNotFound: true,
        scannedFilePath: null,
      );
    }

    final foundExtension = p.extension(actualPath);

    // 异步获取文件大小
    int? newFileSize;
    try {
      final file = File(actualPath);
      newFileSize = await file.length();
    } catch (e) {
      // 忽略错误
    }

    // 获取图片宽高（如果没有提供已知宽高）
    int? newWidth = knownWidth;
    int? newHeight = knownHeight;
    bool isBroken = false;

    // 快速扫描逻辑：如果文件大小一致，且之前有宽高记录，则认为没有变化
    if (isFastScan &&
        newFileSize != null &&
        newFileSize == image.fileSize &&
        (image.width ?? 0) > 0 &&
        (image.height ?? 0) > 0) {
      newWidth = image.width;
      newHeight = image.height;
    } else if (knownWidth == null && knownHeight == null) {
      final size = await ImageUtils.parseImageSize(actualPath);
      if (size != null) {
        newWidth = size.width.toInt();
        newHeight = size.height.toInt();
      } else {
        isBroken = true;
      }
    }

    return ImageUpdateInfo(
      originalImage: image,
      newFileSize: newFileSize,
      newExtension: foundExtension,
      newWidth: newWidth,
      newHeight: newHeight,
      isBroken: isBroken,
      scannedFilePath: actualPath,
    );
  }

  /// 扫描单个作品 (异步版本)
  Future<void> _scanSingleIllust(
    int index,
    List<DownloadedImage> images,
  ) async {
    if (!mounted) return;

    // 开始扫描当前作品，设置扫描状态为 true
    _throttledSetState(() {
      _updateInfos[index].isScanning = true;
    });

    final illust = _updateInfos[index].illust;

    // 先计算数据库中的总大小
    int dbTotalSize = 0;
    for (var image in images) {
      dbTotalSize += image.fileSize;
    }

    // 更新总图片数和数据库总大小
    _throttledSetState(() {
      _updateInfos[index].updateScanProgress(images.length, 0);
      _updateInfos[index].totalSizeInDb = dbTotalSize;
    });

    // 如果没有关联的图片，保持扫描中状态直到所有illust扫描完成
    if (images.isEmpty) {
      _throttledSetState(() {
        _updateInfos[index].isScanned = true;
        _updateInfos[index].isScanning = false; // 直接标记完成
        _updateInfos[index].updateScanProgress(0, 0);
        // 没有图片记录时标记为未下载完整（动图和普通插画都适用）
        _updateInfos[index].isIncomplete = true;
        _scannedCount++;
      });
      return;
    }

    // 批次并发扫描图片
    int batchCount = illust.isUgoira ? 1 : _concurrentCount;
    int? knownWidth;
    int? knownHeight;
    final imageUpdates = <ImageUpdateInfo>[];

    // 预先获取插画所在目录的所有文件，减少后续 exists 调用
    final existingFileMap = await _getExistingFileMap(illust.relativePath);

    for (int batchStart = 0; batchStart < images.length; ) {
      if (!mounted) return;

      while (_isPaused && mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (!mounted) return;

      final batchEnd = (batchStart + batchCount).clamp(0, images.length);

      final futures = <Future<ImageUpdateInfo>>[];
      for (int j = batchStart; j < batchEnd; j++) {
        final image = images[j];
        // 动图：仅对帧图片(part>=1)使用已知宽高，预览图(part=0)正常扫描
        final useKnownSize =
            illust.isUgoira &&
            image.part >= 1 &&
            knownWidth != null &&
            knownHeight != null;
        futures.add(
          _scanSingleImage(
            image,
            illust: illust,
            knownWidth: useKnownSize ? knownWidth : null,
            knownHeight: useKnownSize ? knownHeight : null,
            isFastScan: _isFastScan,
            existingFileMap: existingFileMap,
          ),
        );
      }

      // 并发执行当前批次的所有扫描任务
      final batchResults = await Future.wait(futures);
      imageUpdates.addAll(batchResults);

      if (illust.isUgoira && knownWidth == null && batchResults.isNotEmpty) {
        final firstFrameResult = batchResults.firstWhere(
          (r) => r.originalImage.part >= 1,
          orElse: () => batchResults.first,
        );
        // 动图：从第一批结果中获取第一帧(part=1)宽高，之后恢复用户设置的并发数
        if (firstFrameResult.originalImage.part >= 1) {
          knownWidth =
              firstFrameResult.newWidth ?? firstFrameResult.originalImage.width;
          knownHeight =
              firstFrameResult.newHeight ??
              firstFrameResult.originalImage.height;
          batchCount = _concurrentCount;
        }
      }

      // 实时更新扫描进度
      _throttledSetState(() {
        _updateInfos[index].updateScanProgress(images.length, batchEnd);
        _updateInfos[index].updateImageUpdates(List.from(imageUpdates));
      });

      batchStart = batchEnd;
    }

    // 更新当前作品的扫描结果
    _throttledSetState(() {
      _scannedCount++;
      _updateInfos[index].isScanning = false;
      _updateInfos[index].updateImageUpdates(imageUpdates);
    });
  }

  /// 预先获取插画所在目录的所有文件，减少后续 exists 调用
  Future<Map<String, String>?> _getExistingFileMap(String relativePath) async {
    try {
      final illustPath = downloadStore.dbProvider.getIllustAbsolutePath(relativePath);
      final dir = Directory(illustPath);
      if (await dir.exists()) {
        final Map<String, String> existingFileMap = {};
        // 递归列出所有文件，处理动图的 ugoira 子目录
        final entities = dir.list(recursive: true, followLinks: false);
        await for (final entity in entities) {
          if (entity is File) {
            final fileName = p.basenameWithoutExtension(entity.path);
            existingFileMap[fileName] = entity.path;
          }
        }
        return existingFileMap;
      }
    } catch (e) {
      Log.w('预获取文件列表失败: $e');
    }
    return null;
  }

  /// 加载所有插画
  Future<void> _loadAllIllusts() async {
    // 显示确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('加载所有插画'),
            content: Text('将从数据库加载所有插画作品进行扫描,这可能需要较长时间。是否继续?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('确认'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    // 加载所有插画
    final allIllusts = await downloadStore.getAllDownloaded();

    if (allIllusts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('数据库中没有插画作品')));
      }
      return;
    }

    // 更新状态
    if (mounted) {
      setState(() {
        _totalCount = allIllusts.length;
        _scannedCount = 0;
        _updateInfos =
            allIllusts.map((illust) {
              return UpdateIllustInfo(
                illust: illust,
                imageUpdates: [],
                isScanning: false,
              );
            }).toList();
      });

      // 显示加载成功提示
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已加载 ${allIllusts.length} 个插画作品')));
    }
  }

  /// 加载非 WebP 插画
  Future<void> _loadNonWebPIllusts() async {
    // 显示确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('加载非 WebP 插画'),
            content: Text('将加载所有包含非 WebP 图片的插画（排除动图）进行扫描。是否继续?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('确认'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    // 加载非 WebP 插画
    final illusts = await downloadStore.getDownloadedWithNonWebPImages();

    if (illusts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('没有发现包含非 WebP 图片的插画')));
      }
      return;
    }

    // 更新状态
    if (mounted) {
      setState(() {
        _totalCount = illusts.length;
        _scannedCount = 0;
        _updateInfos =
            illusts.map((illust) {
              return UpdateIllustInfo(
                illust: illust,
                imageUpdates: [],
                isScanning: false,
              );
            }).toList();
      });

      // 显示加载成功提示
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已加载 ${illusts.length} 个插画作品')));
    }
  }

  Future<void> _scanIllusts() async {
    setState(() {
      _isScanning = true;
      _isPaused = false;
      _scannedCount = 0;
      _elapsedDuration = null; // 重置实时耗时
      _scanDuration = null; // 重置耗时
      _lastSetStateTime = DateTime.fromMillisecondsSinceEpoch(0);
      // 重置所有作品的扫描状态，但不设置为正在扫描
      for (var info in _updateInfos) {
        info.isScanned = false; // 重置扫描标记
        info.isScanning = false; // 初始状态为 false，只有开始扫描时才设置为 true
        info.imageUpdates = []; // 直接赋空值，不调用 updateImageUpdates 避免触发 isScanned
        info.refreshFlags();
        info.updateScanProgress(0, 0);
      }
    });
 
    _stopwatch = Stopwatch()..start();
    _startTimer();
    const int dbBatchSize = 10; // 每 20 个作品一批查询数据库

    for (int i = 0; i < _updateInfos.length; i += dbBatchSize) {
      if (!mounted) return;

      final end = (i + dbBatchSize).clamp(0, _updateInfos.length);
      final batchIds =
          _updateInfos.sublist(i, end).map((e) => e.illust.illustId).toList();

      // 批量预加载图片信息
      final Map<int, List<DownloadedImage>> imageCache = await downloadStore
          .dbProvider
          .getImagesByIllustIds(batchIds);

      for (int j = i; j < end; j++) {
        if (!mounted) return;

        while (_isPaused && mounted) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        if (!mounted) return;

        _autoScrollTo(j);

        final images = imageCache[_updateInfos[j].illust.illustId] ?? [];
        await _scanSingleIllust(j, images);
      }
    }

    if (mounted) {
      _stopwatch?.stop();
      _stopTimer();
      setState(() {
        _isScanning = false;
        _scanDuration = _stopwatch?.elapsed;
        _stopwatch = null;
        // 扫描完成后，确保所有作品的扫描状态都被重置
        for (var info in _updateInfos) {
          info.isScanning = false;
        }
      });
    }
  }

  void _autoScrollTo(int index) {
    if (index != -1 && _scrollController.hasClients && _filterType == null) {
      // 逻辑：只有当当前扫描的索引 index 达到了当前屏幕显示的最后一个索引时，才触发滚动
      // 这样可以确保手动扫描完一屏后再滚动
      if (_displayingChildIndexList.isNotEmpty) {
        final lastVisibleIndex = _displayingChildIndexList.last;
        if (index >= lastVisibleIndex || index == 0) {
          _observerController.animateTo(
            index: index,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeInOut,
            alignment: 0,
          );
        }
      } else if (index == 0) {
        // 初始滚动
        _observerController.animateTo(
          index: 0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          alignment: 0,
        );
      }
    }
  }

  void _pauseScan() {
    setState(() {
      _isPaused = true;
      _stopwatch?.stop();
      _stopTimer();
    });
  }

  void _resumeScan() {
    setState(() {
      _isPaused = false;
      _stopwatch?.start();
      _startTimer();
    });
  }

  void _handleClose() {
    // 如果正在扫描，先暂停扫描
    if (_isScanning && !_isPaused) {
      _pauseScan();
    }
    // 关闭对话框（扫描循环会因为 mounted 检查而自然退出）
    Navigator.pop(context);
  }

  // 删除损坏或丢失的图片文件和数据库记录
  Future<({bool success, String? error})> _deleteBrokenImage(
    ImageUpdateInfo imageUpdate,
  ) async {
    final image = imageUpdate.originalImage;

    // 删除文件
    try {
      final scannedPath = imageUpdate.scannedFilePath;
      if (scannedPath != null) {
        final file = File(scannedPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e, stackTrace) {
      final errorMsg = '删除文件失败 [${image.illustId}_p${image.part}]: $e';
      Log.e(errorMsg, stackTrace: stackTrace);
      // 文件删除失败但继续尝试删除数据库记录
    }

    // 删除数据库记录（不自动更新统计，由 _performUpdate 批量更新）
    try {
      await downloadStore.dbProvider.deleteImageWithoutStats(
        image.illustId,
        image.part,
      );
      return (success: true, error: null);
    } catch (e, stackTrace) {
      final errorMsg = '删除数据库记录失败 [${image.illustId}_p${image.part}]: $e';
      Log.e(errorMsg, stackTrace: stackTrace);
      return (success: false, error: errorMsg);
    }
  }

  // 更新单个图片记录到数据库
  Future<bool> _updateImageRecord(ImageUpdateInfo imageUpdate) async {
    final image = imageUpdate.originalImage;
    final updateData = <String, dynamic>{};
    bool needUpdate = false;

    // 更新文件大小
    if (imageUpdate.newFileSize != null &&
        imageUpdate.newFileSize != image.fileSize) {
      updateData[DownloadedImageColumns.fileSize] = imageUpdate.newFileSize;
      needUpdate = true;
    }

    // 更新后缀名
    if (imageUpdate.newExtension != null &&
        imageUpdate.newExtension != image.extension) {
      updateData[DownloadedImageColumns.extension] = imageUpdate.newExtension;
      needUpdate = true;
    }

    // 更新宽高
    if (imageUpdate.newWidth != null && imageUpdate.newWidth != image.width) {
      updateData[DownloadedImageColumns.width] = imageUpdate.newWidth;
      needUpdate = true;
    }

    if (imageUpdate.newHeight != null &&
        imageUpdate.newHeight != image.height) {
      updateData[DownloadedImageColumns.height] = imageUpdate.newHeight;
      needUpdate = true;
    }

    if (needUpdate && updateData.isNotEmpty) {
      await downloadStore.dbProvider.updateImageRecord(
        image.illustId,
        image.part,
        updateData,
      );
      return true;
    }
    return false;
  }

  Future<void> _performUpdate() async {
    // 计算需要更新的总作品数
    final toUpdateCount =
        _updateInfos
            .where(
              (info) =>
                  !info.isScanning &&
                  (info.hasChanges ||
                      info.hasBroken ||
                      info.hasStatsInconsistency),
            )
            .length;

    setState(() {
      _isUpdating = true;
      _errorMessage = null;
      _updatingProgress = 0;
      _totalToUpdate = toUpdateCount;
    });

    try {
      for (final updateInfo in _updateInfos) {
        if (!mounted) return;

        // 如果在执行更新时扫描被暂停，建议也停下更新动作
        while (_isPaused && mounted) {
          await Future.delayed(Duration(milliseconds: 100));
        }
        if (!mounted) return;

        // 只更新已扫描完成且有变化的
        if (updateInfo.isScanning) {
          continue;
        }
        if (!updateInfo.hasChanges &&
            !updateInfo.hasBroken &&
            !updateInfo.hasStatsInconsistency) {
          continue;
        }

        try {
          // 用于并在内存中更新的新列表
          final newImageUpdates = <ImageUpdateInfo>[];
          bool hasAnyUpdateSuccess = false;

          for (final imageUpdate in updateInfo.imageUpdates) {
            // 1. 处理损坏/丢失文件
            if (imageUpdate.isBroken || imageUpdate.isFileNotFound) {
              final result = await _deleteBrokenImage(imageUpdate);
              if (result.success) {
                hasAnyUpdateSuccess = true;
                // 删除成功，不加入 newImageUpdates，即从列表中移除
                continue;
              } else if (result.error != null) {
                updateInfo.updateError = result.error;
                // 删除失败，保留原条目
                newImageUpdates.add(imageUpdate);
                continue;
              }
            }

            // 2. 处理信息变更
            if (imageUpdate.hasChange) {
              if (await _updateImageRecord(imageUpdate)) {
                hasAnyUpdateSuccess = true;
                // 更新成功，但为了保留 Diff 视图（Showing Old -> New），
                // 我们不更新 ImageUpdateInfo 中的 originalImage。
                // 仅标记整个作品为“更新成功”。
                newImageUpdates.add(imageUpdate);
              } else {
                // 更新失败，保留原条目
                newImageUpdates.add(imageUpdate);
              }
              continue;
            }

            // 3. 无变化的条目，直接保留
            newImageUpdates.add(imageUpdate);
          }

          // 如果有变化、删除了损坏文件、或统计不一致，都需要重新计算统计信息
          if (hasAnyUpdateSuccess ||
              updateInfo.hasStatsInconsistency) {
            // 1. 先更新插画自身的数据库统计
            await downloadStore.dbProvider.batchRecalculateIllustStats([
              updateInfo.illust.illustId,
            ]);

            // 2. 更新内存状态
            // 更新 imageUpdates 列表（主要是为了移除已删除的项）
            updateInfo.imageUpdates = newImageUpdates;
            
            // 为了让头部统计信息显示正确的新值（New），我们需要更新 illust 对象中的统计字段
            // 但为了保留 Diff 视图（Old -> New），我们不更新 UpdateIllustInfo.totalSizeInDb
            // final actualCount =
            //     newImageUpdates
            //         .where((e) => !e.isBroken && !e.isFileNotFound)
            //         .length;
            // final actualSize = updateInfo.totalSizeScanned;

            // updateInfo.illust = updateInfo.illust.copyWith(
            //   downloadedImageCount: actualCount,
            //   totalFileSize: actualSize,
            // );
            
            // 标记为更新成功
            updateInfo.isUpdated = true;
            updateInfo.updateError = null;

            // 3. 更新作者汇总统计
            await downloadStore.dbProvider.updateAuthorStats(
              updateInfo.illust.userId,
            );
          }
        } catch (e, stack) {
          Log.e('更新作品失败: ${updateInfo.illust.title}', error: e, stackTrace: stack);
          updateInfo.updateError = e.toString();
        }

        // 更新进度
        if (mounted) {
          setState(() {
            _updatingProgress++;
          });
        }
      }

      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUpdating = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  List<UpdateIllustInfo> get _filteredInfos {
    if (_filterType == null) return _updateInfos;
    return _updateInfos
        .where((info) => info.resultType == _filterType)
        .toList();
  }

  // 构建标题栏
  Widget _buildTitleBar() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          Text('更新插画信息', style: Theme.of(context).textTheme.titleLarge),
          SizedBox(width: 16),
          // 并发数设置
          Text('并发数:', style: TextStyle(fontSize: 14)),
          SizedBox(width: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButton<int>(
              value: _concurrentCount,
              underline: SizedBox(),
              isDense: true,
              items:
                  List.generate(10, (index) => index + 1)
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(),
              onChanged:
                  _isScanning || _isUpdating
                      ? null
                      : (value) {
                        if (value != null) {
                          setState(() {
                            _concurrentCount = value;
                          });
                          userSetting.setUpdateIllustConcurrentCount(value);
                        }
                      },
            ),
          ),
          SizedBox(width: 16),
          // 快速扫描选项
          Row(
            children: [
              Checkbox(
                value: _isFastScan,
                onChanged:
                    _isScanning || _isUpdating
                        ? null
                        : (value) {
                          if (value != null) {
                            setState(() {
                              _isFastScan = value;
                            });
                          }
                        },
              ),
              Text(
                '快速扫描',
                style: TextStyle(fontSize: 14),
                // 添加 tooltip 解释快速扫描
              ),
              Tooltip(
                message: '如果文件大小未发生变化，则跳过图片尺寸校验。\n这将显著加快扫描速度。',
                child: Icon(
                  Icons.help_outline,
                  size: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          Spacer(),
          if (_isScanning || _isUpdating)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: _isUpdating ? null : _handleClose,
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  // 构建筛选栏
  Widget _buildFilterBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          Text('筛选:', style: TextStyle(fontSize: 14)),
          SizedBox(width: 8),
          _buildFilterChip('全部', null),
          SizedBox(width: 8),
          _buildFilterChip('有变化', UpdateResultType.changed),
          SizedBox(width: 8),
          _buildFilterChip('损坏', UpdateResultType.broken),
          SizedBox(width: 8),
          _buildFilterChip('统计不一致', UpdateResultType.inconsistent),
          SizedBox(width: 8),
          _buildFilterChip('未完整', UpdateResultType.incomplete),
          SizedBox(width: 8),
          _buildFilterChip('无变化', UpdateResultType.unchanged),
          Spacer(),
          Text(
            '${_isScanning ? '耗时: ${_elapsedDuration?.inSeconds ?? 0}s | ' : (_scanDuration != null ? '耗时: ${_scanDuration!.inSeconds}s | ' : '')}'
            '总计: ${_updateInfos.length} | '
            '有变化: ${_updateInfos.where((e) => e.resultType == UpdateResultType.changed).length} | '
            '损坏: ${_updateInfos.where((e) => e.resultType == UpdateResultType.broken).length} | '
            '统计不一致: ${_updateInfos.where((e) => e.resultType == UpdateResultType.inconsistent).length} | '
            '未完整: ${_updateInfos.where((e) => e.resultType == UpdateResultType.incomplete).length} | '
            '无变化: ${_updateInfos.where((e) => e.resultType == UpdateResultType.unchanged).length}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            _buildTitleBar(),

            _buildFilterBar(),

            // 内容区域
            Expanded(
              child:
                  _filteredInfos.isEmpty
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isScanning) ...[
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('正在扫描: $_scannedCount / $_totalCount'),
                            ] else ...[
                              Text(
                                _filterType == null ? '没有需要更新的作品' : '没有符合条件的作品',
                              ),
                            ],
                          ],
                        ),
                      )
                      : ListViewObserver(
                        controller: _observerController,
                        onObserve: (resultModel) {
                          _displayingChildIndexList =
                              resultModel.displayingChildIndexList;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: _filteredInfos.length,
                          itemBuilder: (context, index) {
                            final info = _filteredInfos[index];
                            return _buildIllustItem(info);
                          },
                        ),
                      ),
            ),

            // 底部按钮栏
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_errorMessage != null)
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  if (_isUpdating) ...[
                    // 显示更新进度
                    Text('正在更新: $_updatingProgress / $_totalToUpdate'),
                    SizedBox(width: 16),
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ] else if (_isScanning) ...[
                    Text('扫描中: $_scannedCount / $_totalCount'),
                    SizedBox(width: 16),
                    if (_isPaused) ...[
                      ElevatedButton.icon(
                        onPressed: _isUpdating ? null : _resumeScan,
                        icon: Icon(Icons.play_arrow),
                        label: Text('继续'),
                      ),
                      SizedBox(width: 8),
                    ] else ...[
                      ElevatedButton.icon(
                        onPressed: _isUpdating ? null : _pauseScan,
                        icon: Icon(Icons.pause),
                        label: Text('暂停'),
                      ),
                      SizedBox(width: 8),
                    ],
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    // 暂停状态下可以更新已扫描的内容
                    ElevatedButton(
                      onPressed:
                          _isUpdating ||
                                  _updateInfos.every(
                                    (e) =>
                                        e.isScanning ||
                                        (!e.hasChanges &&
                                            !e.hasBroken &&
                                            !e.hasStatsInconsistency),
                                  )
                              ? null
                              : _performUpdate,
                      child: Text('更新已扫描'),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      onPressed: _isUpdating ? null : _loadAllIllusts,
                      icon: Icon(Icons.cloud_download),
                      label: Text('加载所有插画'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isUpdating ? null : _loadNonWebPIllusts,
                      icon: Icon(Icons.image_not_supported),
                      label: Text('非WebP'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isUpdating ? null : _scanIllusts,
                      icon: Icon(Icons.search),
                      label: Text(_scannedCount == 0 ? '开始扫描' : '重新扫描'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed:
                          _isUpdating ||
                                  _scannedCount == 0 ||
                                  _updateInfos.every(
                                    (e) =>
                                        !e.hasChanges &&
                                        !e.hasBroken &&
                                        !e.hasStatsInconsistency,
                                  )
                              ? null
                              : _performUpdate,
                      child: Text('确认更新'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, UpdateResultType? type) {
    final isSelected = _filterType == type;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterType = selected ? type : null;
        });
      },
    );
  }

  // 作品状态判断
  ({
    bool isScanning,
    bool isPaused,
    bool isWaiting,
    bool isNotScanned,
    bool hasChanges,
    bool hasBroken,
    bool isIncomplete,
    bool hasStatsInconsistency,
    bool isUpdated,
    String? updateError,
  })
  _determineIllustStatus(UpdateIllustInfo info) {
    final isScanning = _isScanning && info.isScanning && !_isPaused;
    final isPaused = _isPaused && info.isScanning;
    final isWaiting =
        _isScanning &&
        !info.isScanning &&
        !info.isScanned &&
        !isPaused;
    final isNotScanned =
        !_isScanning &&
        !isScanning &&
        !info.isScanned &&
        _scannedCount == 0;

    return (
      isScanning: isScanning,
      isPaused: isPaused,
      isWaiting: isWaiting,
      isNotScanned: isNotScanned,
      hasChanges: info.hasChanges,
      hasBroken: info.hasBroken,
      isIncomplete: info.isIncomplete,
      hasStatsInconsistency: info.hasStatsInconsistency,
      isUpdated: info.isUpdated,
      updateError: info.updateError,
    );
  }

  // 根据状态获取样式配置
  ({
    Color backgroundColor,
    Color borderColor,
    IconData leadingIcon,
    Color iconColor,
    String statusText,
  })
  _getStyleConfig(
    ({
      bool isScanning,
      bool isPaused,
      bool isWaiting,
      bool isNotScanned,
      bool hasChanges,
      bool hasBroken,
      bool isIncomplete,
      bool hasStatsInconsistency,
      bool isUpdated,
      String? updateError,
    })
    status,
  ) {
    if (status.updateError != null) {
      return (
        backgroundColor: Colors.red[50]!,
        borderColor: Colors.red[400]!,
        leadingIcon: Icons.error_outline,
        iconColor: Colors.red[700]!,
        statusText: '更新失败',
      );
    } else if (status.isUpdated) {
      return (
        backgroundColor: Colors.green[50]!,
        borderColor: Colors.green[400]!,
        leadingIcon: Icons.check_circle_outline,
        iconColor: Colors.green[700]!,
        statusText: '更新成功',
      );
    } else if (status.isScanning) {
      return (
        backgroundColor: Colors.blue[50]!,
        borderColor: Colors.blue[400]!,
        leadingIcon: Icons.autorenew,
        iconColor: Colors.blue[700]!,
        statusText: '正在扫描...',
      );
    } else if (status.isPaused) {
      return (
        backgroundColor: Colors.orange[50]!,
        borderColor: Colors.orange[300]!,
        leadingIcon: Icons.pause_circle,
        iconColor: Colors.orange[700]!,
        statusText: '已暂停',
      );
    } else if (status.isWaiting) {
      return (
        backgroundColor: Colors.amber[50]!,
        borderColor: Colors.amber[300]!,
        leadingIcon: Icons.queue,
        iconColor: Colors.amber[700]!,
        statusText: '等待中',
      );
    } else if (status.isNotScanned) {
      return (
        backgroundColor: Colors.grey[100]!,
        borderColor: Colors.grey[400]!,
        leadingIcon: Icons.pending,
        iconColor: Colors.grey[600]!,
        statusText: '未扫描',
      );
    } else if (status.hasBroken) {
      return (
        backgroundColor: Colors.red[50]!,
        borderColor: Colors.red[400]!,
        leadingIcon: Icons.error,
        iconColor: Colors.red[700]!,
        statusText: '已损坏',
      );
    } else if (status.isIncomplete) {
      return (
        backgroundColor: Colors.purple[50]!,
        borderColor: Colors.purple[400]!,
        leadingIcon: Icons.incomplete_circle,
        iconColor: Colors.purple[700]!,
        statusText: '未下载完整',
      );
    } else if (status.hasStatsInconsistency) {
      return (
        backgroundColor: Colors.amber[50]!,
        borderColor: Colors.amber[400]!,
        leadingIcon: Icons.analytics,
        iconColor: Colors.amber[800]!,
        statusText: '统计不一致',
      );
    } else if (status.hasChanges) {
      return (
        backgroundColor: Colors.orange[50]!,
        borderColor: Colors.orange[400]!,
        leadingIcon: Icons.update,
        iconColor: Colors.orange[700]!,
        statusText: '信息有误',
      );
    } else {
      return (
        backgroundColor: Colors.green[100]!,
        borderColor: Colors.green[300]!,
        leadingIcon: Icons.check_circle,
        iconColor: Colors.green[700]!,
        statusText: '无变化',
      );
    }
  }

  // 构建前导图标（带旋转动画）
  Widget _buildLeadingIcon(
    bool isScanning,
    IconData icon,
    Color iconColor,
    UpdateIllustInfo info,
  ) {
    if (isScanning) {
      return TweenAnimationBuilder<double>(
        key: ValueKey('scanning_${info.illust.illustId}'),
        tween: Tween(begin: 0.0, end: 1.0),
        duration: Duration(seconds: 1),
        curve: Curves.linear,
        builder: (context, value, child) {
          return Transform.rotate(
            angle: value * 2 * 3.14159,
            child: Icon(icon, color: iconColor, size: 28),
          );
        },
        onEnd: () {
          if (mounted && _isScanning && info.isScanning) {
            setState(() {});
          }
        },
      );
    }
    return Icon(icon, color: iconColor, size: 28);
  }

  // 构建状态标签（扫描中/等待中）
  Widget? _buildStatusBadge(
    bool isScanning,
    bool isWaiting,
    bool isNotScanned,
    Color iconColor,
    String statusText,
  ) {
    if (isScanning) {
      return Padding(
        padding: EdgeInsets.only(left: 8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(iconColor),
          ),
        ),
      );
    } else if (isWaiting || isNotScanned || statusText != '') {
      return Padding(
        padding: EdgeInsets.only(left: 8),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              color: iconColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }
    return null;
  }

  // 构建操作按钮
  List<Widget> _buildActionButtons(
    bool isNotScanned,
    UpdateIllustInfo info,
    Color iconColor,
  ) {
    final actions = <Widget>[];

    // 打开文件夹按钮
    if (!isNotScanned) {
      actions.add(
        Padding(
          padding: EdgeInsets.only(left: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                final dirPath = downloadStore.getIllustDirectoryPath(
                  info.illust,
                );
                if (dirPath != null) {
                  await FileUtils.openFileOrDirectory(dirPath);
                }
              },
              child: Container(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.folder_open, color: iconColor, size: 20),
              ),
            ),
          ),
        ),
      );
    }

    // 打开插画详情页按钮
    actions.add(
      Padding(
        padding: EdgeInsets.only(left: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (context) => Scaffold(
                        body: IllustLightingPage(id: info.illust.illustId),
                      ),
                ),
              );
            },
            child: Container(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.image, color: iconColor, size: 20),
            ),
          ),
        ),
      ),
    );

    return actions;
  }

  /// 获取页数/帧数显示文本
  /// 对于动图显示"50帧"，对于普通插画显示"10P"
  String _getPageCountText(DownloadedIllust illust) {
    if (illust.isUgoira) {
      // 动图：获取帧数
      final metadata = illust.getUgoiraMetadata();
      final frameCount = metadata?.frames.length ?? 0;
      return '$frameCount帧';
    } else {
      // 普通插画
      return '${illust.pageCount}P';
    }
  }

  /// 获取未完整状态的显示文本
  /// 对于动图显示"(x/50帧)"，对于普通插画显示"(x/10P)"
  String _getIncompleteText(UpdateIllustInfo info) {
    if (info.illust.isUgoira) {
      // 动图：统计帧文件数量(part>=1)
      final frameCount =
          info.imageUpdates
              .where(
                (e) =>
                    e.originalImage.part >= 1 &&
                    !e.isBroken &&
                    !e.isFileNotFound,
              )
              .length;
      final metadata = info.illust.getUgoiraMetadata();
      final expectedFrames = metadata?.frames.length ?? 0;
      return '($frameCount/$expectedFrames帧)';
    } else {
      // 普通插画
      final downloadedCount =
          info.imageUpdates
              .where((e) => !e.isBroken && !e.isFileNotFound)
              .length;
      return '($downloadedCount/${info.illust.pageCount})';
    }
  }

  /// 获取扫描进度的显示文本
  /// 对于动图需要过滤帧文件，对于普通插画显示全部
  String _getScanProgressText(UpdateIllustInfo info) {
    if (info.illust.isUgoira) {
      // 动图：显示所有文件的扫描进度（包含预览图和帧文件）
      return '(${info.scannedImageCount}/${info.totalImageCount}文件)';
    } else {
      // 普通插画
      return '(${info.scannedImageCount}/${info.totalImageCount})';
    }
  }

  Widget _buildIllustItem(UpdateIllustInfo info) {
    // 获取作品状态和样式配置
    final status = _determineIllustStatus(info);
    final style = _getStyleConfig(status);

    final isScanning = status.isScanning;
    final isPaused = status.isPaused;
    final isWaiting = status.isWaiting;
    final isNotScanned = status.isNotScanned;
    final isIncomplete = status.isIncomplete;

    final backgroundColor = style.backgroundColor;
    final borderColor = style.borderColor;
    final leadingIcon = style.leadingIcon;
    final iconColor = style.iconColor;
    final statusText = style.statusText;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
          width:
              status.hasChanges ||
                      status.hasBroken ||
                      status.hasStatsInconsistency ||
                      isIncomplete ||
                      isScanning ||
                      isWaiting ||
                      isPaused
                  ? 2
                  : 1,
        ),
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '[${info.illust.illustId}] ${info.illust.title}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${info.illust.userName} | ${_getPageCountText(info.illust)}',
                        style: TextStyle(fontSize: 13, color: Colors.black45),
                      ),
                      if (isScanning && info.totalImageCount > 0) ...[
                        SizedBox(width: 8),
                        Text(
                          _getScanProgressText(info),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (!isScanning && !isNotScanned && isIncomplete) ...[
                        SizedBox(width: 8),
                        Text(
                          _getIncompleteText(info),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.purple[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (info.hasStatsInconsistency) ...[
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.numbers, size: 12, color: Colors.amber[800]),
                        SizedBox(width: 4),
                        Text(
                          '图片数: ${info.illust.downloadedImageCount} → ${info.imageUpdates.where((e) => !e.isBroken && !e.isFileNotFound).length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber[900],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 12),
                        Icon(
                          Icons.sd_storage,
                          size: 12,
                          color: Colors.amber[800],
                        ),
                        SizedBox(width: 4),
                        Text(
                          '大小: ${info.illust.totalFileSize.formatFileSize()} → ${info.totalSizeScanned.formatFileSize()}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber[900],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ] else if (!isNotScanned &&
                      (info.totalSizeInDb > 0 ||
                          info.totalSizeScanned > 0 ||
                          (isScanning && info.totalImageCount > 0))) ...[
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '总大小: ',
                          style: TextStyle(fontSize: 12, color: Colors.black45),
                        ),
                        if (info.totalSizeInDb != info.totalSizeScanned)
                          Text(
                            '${info.totalSizeInDb.formatFileSize()} → ${info.totalSizeScanned.formatFileSize()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[700],
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        else
                          Text(
                            '${info.totalSizeInDb.formatFileSize()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // 状态标签
            if (_buildStatusBadge(
                  isScanning,
                  isWaiting,
                  isNotScanned,
                  iconColor,
                  statusText,
                ) !=
                null)
              _buildStatusBadge(
                isScanning,
                isWaiting,
                isNotScanned,
                iconColor,
                statusText,
              )!,
            // 操作按钮
            ..._buildActionButtons(isNotScanned, info, iconColor),
          ],
        ),
        subtitle: null,
        leading: _buildLeadingIcon(isScanning, leadingIcon, iconColor, info),
        children:
            info.imageUpdates.isEmpty
                ? [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          isScanning
                              ? Icons
                                  .autorenew // 与主图标保持一致
                              : isPaused
                              ? Icons
                                  .pause_circle // 与主图标保持一致
                              : isWaiting
                              ? Icons
                                  .queue // 与主图标保持一致
                              : Icons.info_outline,
                          color: iconColor,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: iconColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (isScanning && info.totalImageCount > 0) ...[
                                SizedBox(height: 4),
                                Text(
                                  '扫描进度: ${info.scannedImageCount} / ${info.totalImageCount}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ],
                              if (!isNotScanned &&
                                  (info.totalSizeInDb > 0 ||
                                      info.totalSizeScanned > 0)) ...[
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '总大小: ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black45,
                                      ),
                                    ),
                                    if (info.totalSizeInDb !=
                                        info.totalSizeScanned)
                                      Text(
                                        '${info.totalSizeInDb.formatFileSize()} → ${info.totalSizeScanned.formatFileSize()}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      )
                                    else
                                      Text(
                                        '${info.totalSizeInDb.formatFileSize()}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                              if (isIncomplete) ...[
                                SizedBox(height: 4),
                                Text(
                                  '下载进度: ${_getIncompleteText(info)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.purple[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ]
                : info.imageUpdates.map((imageUpdate) {
                  return _buildImageUpdateItem(imageUpdate);
                }).toList(),
      ),
    );
  }

  Widget _buildImageUpdateItem(ImageUpdateInfo imageUpdate) {
    final image = imageUpdate.originalImage;
    final changes = <String>[];

    // 始终显示文件大小对比
    if (imageUpdate.newFileSize != null) {
      if (imageUpdate.newFileSize != image.fileSize) {
        changes.add(
          '大小: ${image.fileSize.formatFileSize()} → ${imageUpdate.newFileSize!.formatFileSize()}',
        );
      } else {
        changes.add('大小: ${image.fileSize.formatFileSize()} (无变化)');
      }
    } else if (image.fileSize > 0) {
      changes.add('大小: ${image.fileSize.formatFileSize()} (数据库中)');
    }

    if (imageUpdate.newExtension != null &&
        imageUpdate.newExtension != image.extension) {
      changes.add('后缀: ${image.extension} → ${imageUpdate.newExtension}');
    }

    if (imageUpdate.newWidth != null && imageUpdate.newWidth != image.width) {
      changes.add('宽度: ${image.width} → ${imageUpdate.newWidth}');
    }

    if (imageUpdate.newHeight != null &&
        imageUpdate.newHeight != image.height) {
      changes.add('高度: ${image.height} → ${imageUpdate.newHeight}');
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            'P${image.part}:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black45,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child:
                imageUpdate.isFileNotFound
                    ? Text(
                      '文件不存在',
                      style: TextStyle(
                        color: Colors.red[700],
                        fontWeight: FontWeight.w500,
                      ),
                    )
                    : imageUpdate.isBroken
                    ? Text(
                      '图片损坏（无法解析）',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    )
                    : changes.isEmpty
                    ? Text('无变化', style: TextStyle(color: Colors.grey))
                    : Text(
                      changes.join(', '),
                      style: TextStyle(color: Colors.black45),
                    ),
          ),
        ],
      ),
    );
  }
}


