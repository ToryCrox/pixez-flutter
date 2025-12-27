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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart' hide Size;
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:pixez/custom/log.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';
import 'package:pixez/page/picture/illust_lighting_page.dart';

enum UpdateResultType {
  changed, // 有变化
  broken, // 损坏
  incomplete, // 未下载完整
  unchanged, // 无变化
}

class UpdateIllustInfo {
  final DownloadedIllust illust;
  List<ImageUpdateInfo> imageUpdates;
  bool hasChanges = false;
  bool hasBroken = false;
  bool isIncomplete = false; // 是否未下载完整（下载的图片数量和illust里面记录的不同）
  bool isScanning = false; // 是否正在扫描
  int totalImageCount = 0; // 总图片数
  int scannedImageCount = 0; // 已扫描图片数
  int totalSizeInDb = 0; // 数据库中记录的总大小
  int totalSizeScanned = 0; // 实际扫描的总大小
  UpdateResultType get resultType {
    if (hasBroken) return UpdateResultType.broken;
    if (isIncomplete) return UpdateResultType.incomplete;
    if (hasChanges) return UpdateResultType.changed;
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
    _updateFlags();
  }

  void _updateFlags() {
    hasChanges = imageUpdates.any((e) => e.hasChange);
    hasBroken = imageUpdates.any((e) => e.isBroken);
    // 检测是否未下载完整：比较 pageCount 和实际下载的图片数量
    final downloadedCount = imageUpdates.where((e) => !e.isBroken).length;
    isIncomplete = downloadedCount < illust.pageCount;
  }

  void updateImageUpdates(List<ImageUpdateInfo> updates) {
    imageUpdates = updates;
    _updateFlags();
    // 计算总大小
    _calculateTotalSize();
  }

  void _calculateTotalSize() {
    // 只更新 totalSizeScanned，totalSizeInDb 在扫描开始时已经设置
    totalSizeScanned = 0;
    for (var update in imageUpdates) {
      if (update.newFileSize != null) {
        totalSizeScanned += update.newFileSize!;
      } else if (!update.isBroken) {
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
  final bool isBroken;
  final String? scannedFilePath; // 扫描阶段获取的文件路径
  bool hasChange = false;

  ImageUpdateInfo({
    required this.originalImage,
    this.newFileSize,
    this.newExtension,
    this.newWidth,
    this.newHeight,
    required this.isBroken,
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

  const UpdateIllustInfoDialog({
    Key? key,
    required this.illusts,
  }) : super(key: key);

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
  UpdateResultType? _filterType;
  String? _errorMessage;
  static const int _concurrentCount = 4; // 每个作品内并发扫描的图片数量

  @override
  void initState() {
    super.initState();
    _totalCount = widget.illusts.length;
    // 初始化时只创建作品列表，不扫描
    _updateInfos = widget.illusts.map((illust) {
      return UpdateIllustInfo(
        illust: illust,
        imageUpdates: [],
        isScanning: false,
      );
    }).toList();
  }

  /// 扫描单张图片
  Future<ImageUpdateInfo> _scanSingleImage(DownloadedImage image) async {
    final actualPath = await downloadStore
        .getLocalImagePath(image.illustId, image.part, update: false);
    String? foundExtension;
    if (actualPath == null) {
      // 文件不存在，标记为损坏
      return ImageUpdateInfo(
        originalImage: image,
        isBroken: true,
        scannedFilePath: null, // 文件不存在，路径为 null
      );
    }

    foundExtension = p.extension(actualPath);

    // 获取文件大小
    int? newFileSize;
    try {
      final file = File(actualPath);
      if (await file.exists()) {
        newFileSize = await file.length();
      }
    } catch (e) {
      // 忽略错误
    }

    // 获取图片宽高
    int? newWidth;
    int? newHeight;
    bool isBroken = false;
    try {
      final size = await compute(_parseImageSizeSync, actualPath);
      if (size != null) {
        newWidth = size.width.toInt();
        newHeight = size.height.toInt();
      } else {
        isBroken = true;
      }
    } catch (e) {
      isBroken = true;
    }

    return ImageUpdateInfo(
      originalImage: image,
      newFileSize: newFileSize,
      newExtension: foundExtension,
      newWidth: newWidth,
      newHeight: newHeight,
      isBroken: isBroken,
      scannedFilePath: actualPath, // 保存扫描阶段获取的文件路径
    );
  }

  /// 扫描单个作品
  Future<void> _scanSingleIllust(int index) async {
    if (!mounted) return;

    // 开始扫描当前作品，设置扫描状态为 true
    if (mounted) {
      setState(() {
        _updateInfos[index].isScanning = true;
      });
    }

    final illust = _updateInfos[index].illust;
    final images =
        await downloadStore.dbProvider.getImagesByIllustId(illust.illustId);

    // 先计算数据库中的总大小
    int dbTotalSize = 0;
    for (var image in images) {
      dbTotalSize += image.fileSize;
    }

    // 更新总图片数和数据库总大小
    if (mounted) {
      setState(() {
        _updateInfos[index].updateScanProgress(images.length, 0);
        _updateInfos[index].totalSizeInDb = dbTotalSize;
      });
    }

    // 如果没有关联的图片，保持扫描中状态直到所有illust扫描完成
    if (images.isEmpty) {
      if (mounted) {
        setState(() {
          _updateInfos[index].isScanning = true;
          _updateInfos[index].updateScanProgress(0, 0);
          // 如果 pageCount > 0 但没有下载的图片，标记为未下载完整
          _updateInfos[index].isIncomplete = illust.pageCount > 0;
          _scannedCount++;
        });
      }
      return;
    }

    // 批次并发扫描图片
    final imageUpdates = <ImageUpdateInfo>[];
    for (int batchStart = 0;
        batchStart < images.length;
        batchStart += _concurrentCount) {
      if (!mounted) return;

      // 检查是否暂停，如果暂停则等待
      while (_isPaused && mounted) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      if (!mounted) return;

      // 计算当前批次的结束索引
      final batchEnd = (batchStart + _concurrentCount).clamp(0, images.length);

      // 创建当前批次的扫描任务
      final futures = <Future<ImageUpdateInfo>>[];
      for (int j = batchStart; j < batchEnd; j++) {
        futures.add(_scanSingleImage(images[j]));
      }

      // 并发执行当前批次的所有扫描任务
      final batchResults = await Future.wait(futures);
      imageUpdates.addAll(batchResults);

      // 实时更新扫描进度
      if (mounted) {
        setState(() {
          _updateInfos[index].updateScanProgress(images.length, batchEnd);
          // 实时更新已扫描的图片信息
          _updateInfos[index].updateImageUpdates(List.from(imageUpdates));
        });
      }
    }

    // 更新当前作品的扫描结果
    if (mounted) {
      setState(() {
        _scannedCount++;
        _updateInfos[index].isScanning = false;
        _updateInfos[index].updateImageUpdates(imageUpdates);
        // 检测是否未下载完整
        final downloadedCount = imageUpdates.where((e) => !e.isBroken).length;
        _updateInfos[index].isIncomplete = downloadedCount < illust.pageCount;
      });
    }
  }

  /// 加载所有插画
  Future<void> _loadAllIllusts() async {
    // 显示确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('数据库中没有插画作品')),
        );
      }
      return;
    }

    // 更新状态
    if (mounted) {
      setState(() {
        _totalCount = allIllusts.length;
        _scannedCount = 0;
        _updateInfos = allIllusts.map((illust) {
          return UpdateIllustInfo(
            illust: illust,
            imageUpdates: [],
            isScanning: false,
          );
        }).toList();
      });

      // 显示加载成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加载 ${allIllusts.length} 个插画作品')),
      );
    }
  }

  Future<void> _scanIllusts() async {
    setState(() {
      _isScanning = true;
      _isPaused = false;
      _scannedCount = 0;
      // 重置所有作品的扫描状态，但不设置为正在扫描
      for (var info in _updateInfos) {
        info.isScanning = false; // 初始状态为 false，只有开始扫描时才设置为 true
        info.updateImageUpdates([]);
        info.updateScanProgress(0, 0);
      }
    });

    // 顺序扫描作品，每个作品内的图片会并发扫描
    for (int i = 0; i < _updateInfos.length; i++) {
      if (!mounted) return;

      // 检查是否暂停，如果暂停则等待
      while (_isPaused && mounted) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      if (!mounted) return;

      await _scanSingleIllust(i);
    }

    if (mounted) {
      setState(() {
        _isScanning = false;
        // 扫描完成后，确保所有作品的扫描状态都被重置
        for (var info in _updateInfos) {
          info.isScanning = false;
        }
      });
    }
  }

  void _pauseScan() {
    setState(() {
      _isPaused = true;
    });
  }

  void _resumeScan() {
    setState(() {
      _isPaused = false;
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

  static Size? _parseImageSizeSync(String filePath) {
    try {
      final file = File(filePath);
      final size = ImageSizeGetter.getSizeResult(FileInput(file));
      return Size(size.size.width.toDouble(), size.size.height.toDouble());
    } catch (e) {
      return null;
    }
  }

  Future<void> _performUpdate() async {
    setState(() {
      _isUpdating = true;
      _errorMessage = null;
    });

    try {
      int updatedCount = 0;
      int brokenCount = 0;
      int deletedCount = 0; // 已删除的损坏文件数量
      List<String> errors = []; // 收集错误信息

      for (final updateInfo in _updateInfos) {
        if (!mounted) return;

        // 只更新已扫描完成且有变化的（暂停状态下可以更新已扫描完成的）
        if (updateInfo.isScanning) {
          continue; // 跳过正在扫描的作品
        }
        if (!updateInfo.hasChanges && !updateInfo.hasBroken) {
          continue;
        }

        bool hasDeletedBroken = false; // 当前作品是否有删除损坏文件

        for (final imageUpdate in updateInfo.imageUpdates) {
          if (imageUpdate.isBroken) {
            brokenCount++;
            // 删除损坏的图片文件和数据库记录
            final image = imageUpdate.originalImage;

            // 使用扫描阶段获取的文件路径删除文件
            try {
              final scannedPath = imageUpdate.scannedFilePath;
              if (scannedPath != null) {
                // 使用扫描阶段保存的文件路径
                final file = File(scannedPath);
                if (await file.exists()) {
                  await file.delete();
                }
              }
            } catch (e, stackTrace) {
              // 记录删除文件时的错误
              final errorMsg = '删除文件失败 [${image.illustId}_p${image.part}]: $e';
              Log.e(errorMsg, stackTrace: stackTrace);
              errors.add(errorMsg);
            }

            // 删除数据库记录
            try {
              await downloadStore.dbProvider
                  .deleteImage(image.illustId, image.part);
              deletedCount++;
              hasDeletedBroken = true;
            } catch (e, stackTrace) {
              // 记录删除数据库记录时的错误
              final errorMsg =
                  '删除数据库记录失败 [${image.illustId}_p${image.part}]: $e';
              Log.e(errorMsg, stackTrace: stackTrace);
              errors.add(errorMsg);
            }

            continue;
          }

          if (!imageUpdate.hasChange) {
            continue;
          }

          final image = imageUpdate.originalImage;
          bool needUpdate = false;
          final updateData = <String, dynamic>{};

          // 更新文件大小
          if (imageUpdate.newFileSize != null &&
              imageUpdate.newFileSize != image.fileSize) {
            updateData[DownloadedImageColumns.fileSize] =
                imageUpdate.newFileSize;
            needUpdate = true;
          }

          // 更新后缀名
          if (imageUpdate.newExtension != null &&
              imageUpdate.newExtension != image.extension) {
            updateData[DownloadedImageColumns.extension] =
                imageUpdate.newExtension;
            needUpdate = true;
          }

          // 更新宽高
          if (imageUpdate.newWidth != null &&
              imageUpdate.newWidth != image.width) {
            updateData[DownloadedImageColumns.width] = imageUpdate.newWidth;
            needUpdate = true;
          }

          if (imageUpdate.newHeight != null &&
              imageUpdate.newHeight != image.height) {
            updateData[DownloadedImageColumns.height] = imageUpdate.newHeight;
            needUpdate = true;
          }

          if (needUpdate && updateData.isNotEmpty) {
            await downloadStore.dbProvider.db.update(
              DownloadedImageColumns.tableName,
              updateData,
              where:
                  '${DownloadedImageColumns.illustId} = ? AND ${DownloadedImageColumns.part} = ?',
              whereArgs: [image.illustId, image.part],
            );
            updatedCount++;
          }
        }

        // 更新作者表统计信息（如果有变化或删除了损坏文件）
        if (updateInfo.hasChanges || hasDeletedBroken) {
          await downloadStore.dbProvider
              .updateAuthorStats(updateInfo.illust.userId);
        }
      }

      if (mounted) {
        setState(() {
          _isUpdating = false;
        });

        // 显示更新结果
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('更新完成'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '已更新 $updatedCount 条记录\n'
                    '损坏文件: $brokenCount 个\n'
                    '已删除: $deletedCount 个',
                  ),
                  if (errors.isNotEmpty) ...[
                    SizedBox(height: 16),
                    Text(
                      '错误信息:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    SizedBox(height: 8),
                    ...errors.map((error) => Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: Text(
                            error,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red[700],
                            ),
                          ),
                        )),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(I18n.of(context).ok),
              ),
            ],
          ),
        );

        // 如果不在扫描状态，重新扫描以更新显示
        if (!_isScanning) {
          await _scanIllusts();
        }
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '更新插画信息',
                    style: Theme.of(context).textTheme.titleLarge,
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
            ),

            // 筛选栏
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!),
                ),
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
                  _buildFilterChip('未完整', UpdateResultType.incomplete),
                  SizedBox(width: 8),
                  _buildFilterChip('无变化', UpdateResultType.unchanged),
                  Spacer(),
                  Text(
                    '总计: ${_updateInfos.length} | '
                    '有变化: ${_updateInfos.where((e) => e.hasChanges).length} | '
                    '损坏: ${_updateInfos.where((e) => e.hasBroken).length} | '
                    '未完整: ${_updateInfos.where((e) => e.isIncomplete).length} | '
                    '无变化: ${_updateInfos.where((e) => !e.hasChanges && !e.hasBroken).length}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            // 内容区域
            Expanded(
              child: _filteredInfos.isEmpty
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
                  : ListView.builder(
                      itemCount: _filteredInfos.length,
                      itemBuilder: (context, index) {
                        final info = _filteredInfos[index];
                        return _buildIllustItem(info);
                      },
                    ),
            ),

            // 底部按钮栏
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
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
                  if (_isScanning) ...[
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
                      onPressed: _isUpdating ||
                              _updateInfos.every((e) =>
                                  e.isScanning ||
                                  (!e.hasChanges && !e.hasBroken))
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
                      onPressed: _isUpdating ? null : _scanIllusts,
                      icon: Icon(Icons.search),
                      label: Text(_scannedCount == 0 ? '开始扫描' : '重新扫描'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isUpdating ||
                              _scannedCount == 0 ||
                              _updateInfos
                                  .every((e) => !e.hasChanges && !e.hasBroken)
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

  Widget _buildIllustItem(UpdateIllustInfo info) {
    final isChanged = info.hasChanges;
    final isBroken = info.hasBroken;
    final isIncomplete = info.isIncomplete;
    // 只有当整个扫描过程在进行中，且该作品也在扫描中，且未暂停时，才认为是正在扫描
    final isScanning = _isScanning && info.isScanning && !_isPaused;
    // 如果扫描已暂停，且当前作品正在扫描中，显示为已暂停
    final isPaused = _isPaused && info.isScanning;
    // 如果扫描已开始但当前作品还未扫描，显示为等待中
    final isWaiting = _isScanning &&
        !info.isScanning &&
        info.imageUpdates.isEmpty &&
        !isPaused;
    final isNotScanned = !_isScanning &&
        !isScanning &&
        info.imageUpdates.isEmpty &&
        _scannedCount == 0;

    Color backgroundColor;
    Color borderColor;
    IconData leadingIcon;
    Color iconColor;
    String statusText;

    if (isScanning) {
      backgroundColor = Colors.blue[50]!;
      borderColor = Colors.blue[400]!;
      leadingIcon = Icons.autorenew; // 使用旋转刷新图标，更明显表示正在扫描
      iconColor = Colors.blue[700]!;
      statusText = '正在扫描...';
    } else if (isPaused) {
      backgroundColor = Colors.orange[50]!;
      borderColor = Colors.orange[300]!;
      leadingIcon = Icons.pause_circle; // 使用暂停图标
      iconColor = Colors.orange[700]!;
      statusText = '已暂停';
    } else if (isWaiting) {
      backgroundColor = Colors.amber[50]!;
      borderColor = Colors.amber[300]!;
      leadingIcon = Icons.queue; // 使用队列图标，更明显表示等待扫描
      iconColor = Colors.amber[700]!;
      statusText = '等待中';
    } else if (isNotScanned) {
      backgroundColor = Colors.grey[100]!;
      borderColor = Colors.grey[400]!;
      leadingIcon = Icons.pending;
      iconColor = Colors.grey[600]!;
      statusText = '未扫描';
    } else if (isBroken) {
      backgroundColor = Colors.red[50]!;
      borderColor = Colors.red[400]!;
      leadingIcon = Icons.error;
      iconColor = Colors.red[700]!;
      statusText = '已损坏';
    } else if (isIncomplete) {
      backgroundColor = Colors.purple[50]!;
      borderColor = Colors.purple[400]!;
      leadingIcon = Icons.incomplete_circle;
      iconColor = Colors.purple[700]!;
      statusText = '未下载完整';
    } else if (isChanged) {
      backgroundColor = Colors.orange[50]!;
      borderColor = Colors.orange[400]!;
      leadingIcon = Icons.update;
      iconColor = Colors.orange[700]!;
      statusText = '有变化';
    } else {
      backgroundColor = Colors.green[100]!;
      borderColor = Colors.green[300]!;
      leadingIcon = Icons.check_circle;
      iconColor = Colors.green[700]!;
      statusText = '无变化';
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
          width: isChanged ||
                  isBroken ||
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
                        '${info.illust.userName} | ${info.illust.pageCount}P',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black45,
                        ),
                      ),
                      if (isScanning && info.totalImageCount > 0) ...[
                        SizedBox(width: 8),
                        Text(
                          '(${info.scannedImageCount}/${info.totalImageCount})',
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
                          '(${info.imageUpdates.where((e) => !e.isBroken).length}/${info.illust.pageCount})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.purple[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (!isNotScanned &&
                      (info.totalSizeInDb > 0 ||
                          info.totalSizeScanned > 0 ||
                          (isScanning && info.totalImageCount > 0))) ...[
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
            if (isScanning)
              Padding(
                padding: EdgeInsets.only(left: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                  ),
                ),
              )
            else if (isWaiting || isNotScanned)
              Padding(
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
              ),
            // 打开文件夹按钮
            if (!isNotScanned)
              Padding(
                padding: EdgeInsets.only(left: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () async {
                      final dirPath = p.join(
                        downloadStore.downloadPath,
                        info.illust.relativePath,
                      );
                      await OpenFile.open(dirPath);
                    },
                    child: Container(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.folder_open,
                        color: iconColor,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            // 打开插画详情页按钮
            Padding(
              padding: EdgeInsets.only(left: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => IllustLightingPage(
                          id: info.illust.illustId,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.image,
                      color: iconColor,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        subtitle: null,
        leading: isScanning
            ? TweenAnimationBuilder<double>(
                key: ValueKey(
                    'scanning_${info.illust.illustId}'), // 使用 key 确保动画正确重置
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(seconds: 1),
                curve: Curves.linear,
                builder: (context, value, child) {
                  return Transform.rotate(
                    angle: value * 2 * 3.14159, // 完整旋转一圈
                    child: Icon(leadingIcon, color: iconColor, size: 28),
                  );
                },
                onEnd: () {
                  // 动画结束后重新开始，实现循环旋转
                  if (mounted && _isScanning && info.isScanning) {
                    setState(() {});
                  }
                },
              )
            : Icon(leadingIcon, color: iconColor, size: 28),
        children: info.imageUpdates.isEmpty
            ? [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        isScanning
                            ? Icons.autorenew // 与主图标保持一致
                            : isPaused
                                ? Icons.pause_circle // 与主图标保持一致
                                : isWaiting
                                    ? Icons.queue // 与主图标保持一致
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
                                '下载进度: ${info.imageUpdates.where((e) => !e.isBroken).length} / ${info.illust.pageCount}',
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
            '大小: ${image.fileSize.formatFileSize()} → ${imageUpdate.newFileSize!.formatFileSize()}');
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
            style:
                TextStyle(fontWeight: FontWeight.bold, color: Colors.black45),
          ),
          SizedBox(width: 8),
          Expanded(
            child: imageUpdate.isBroken
                ? Text(
                    '文件不存在或无法读取',
                    style: TextStyle(color: Colors.red),
                  )
                : changes.isEmpty
                    ? Text('无变化', style: TextStyle(color: Colors.grey))
                    : Text(changes.join(', '),
                        style: TextStyle(color: Colors.black45)),
          ),
        ],
      ),
    );
  }
}
