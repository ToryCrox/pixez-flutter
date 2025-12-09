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
import 'package:path/path.dart' as p;
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart';

enum UpdateResultType {
  changed, // 有变化
  broken, // 损坏
  unchanged, // 无变化
}

class UpdateIllustInfo {
  final DownloadedIllust illust;
  List<ImageUpdateInfo> imageUpdates;
  bool hasChanges = false;
  bool hasBroken = false;
  bool isScanning = false; // 是否正在扫描
  UpdateResultType get resultType {
    if (hasBroken) return UpdateResultType.broken;
    if (hasChanges) return UpdateResultType.changed;
    return UpdateResultType.unchanged;
  }

  UpdateIllustInfo({
    required this.illust,
    required this.imageUpdates,
    this.isScanning = false,
  }) {
    _updateFlags();
  }

  void _updateFlags() {
    hasChanges = imageUpdates.any((e) => e.hasChange);
    hasBroken = imageUpdates.any((e) => e.isBroken);
  }

  void updateImageUpdates(List<ImageUpdateInfo> updates) {
    imageUpdates = updates;
    _updateFlags();
  }
}

class ImageUpdateInfo {
  final DownloadedImage originalImage;
  final int? newFileSize;
  final String? newExtension;
  final int? newWidth;
  final int? newHeight;
  final bool isBroken;
  bool hasChange = false;

  ImageUpdateInfo({
    required this.originalImage,
    this.newFileSize,
    this.newExtension,
    this.newWidth,
    this.newHeight,
    required this.isBroken,
  }) {
    hasChange = (newFileSize != null && newFileSize != originalImage.fileSize) ||
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
  bool _isUpdating = false;
  int _scannedCount = 0;
  int _totalCount = 0;
  UpdateResultType? _filterType;
  String? _errorMessage;

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

  Future<void> _scanIllusts() async {
    setState(() {
      _isScanning = true;
      _scannedCount = 0;
      // 重置所有作品的扫描状态
      for (var info in _updateInfos) {
        info.isScanning = true;
        info.updateImageUpdates([]);
      }
    });

    for (int i = 0; i < widget.illusts.length; i++) {
      if (!mounted) return;

      final illust = widget.illusts[i];
      final imageUpdates = <ImageUpdateInfo>[];
      final images = await downloadStore.dbProvider.getImagesByIllustId(illust.illustId);

      for (final image in images) {
        final actualPath = await downloadStore.getLocalImagePath(image.illustId, image.part, update: false);
        String? foundExtension;
        if (actualPath == null) {
          // 文件不存在，标记为损坏
          imageUpdates.add(ImageUpdateInfo(
            originalImage: image,
            isBroken: true,
          ));
          continue;
        } else {
          foundExtension = p.extension(actualPath);
        }

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

        imageUpdates.add(ImageUpdateInfo(
          originalImage: image,
          newFileSize: newFileSize,
          newExtension: foundExtension,
          newWidth: newWidth,
          newHeight: newHeight,
          isBroken: isBroken,
        ));
      }

      // 更新当前作品的扫描结果
      if (mounted) {
        setState(() {
          _scannedCount++;
          _updateInfos[i].isScanning = false;
          _updateInfos[i].updateImageUpdates(imageUpdates);
        });
      }
    }

    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
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

      for (final updateInfo in _updateInfos) {
        if (!mounted) return;

        // 只更新有变化的
        if (!updateInfo.hasChanges && !updateInfo.hasBroken) {
          continue;
        }

        for (final imageUpdate in updateInfo.imageUpdates) {
          if (imageUpdate.isBroken) {
            brokenCount++;
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

        // 更新作者表统计信息
        if (updateInfo.hasChanges) {
          await downloadStore.dbProvider.updateAuthorStats(updateInfo.illust.userId);
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
            content: Text(
              '已更新 $updatedCount 条记录\n损坏文件: $brokenCount 个',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(I18n.of(context).ok),
              ),
            ],
          ),
        );

        // 重新扫描以更新显示
        await _scanIllusts();
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
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (!_isScanning && !_isUpdating)
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
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
                    _buildFilterChip('无变化', UpdateResultType.unchanged),
                    Spacer(),
                    Text(
                      '总计: ${_updateInfos.length} | '
                      '有变化: ${_updateInfos.where((e) => e.hasChanges).length} | '
                      '损坏: ${_updateInfos.where((e) => e.hasBroken).length} | '
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
                              _filterType == null
                                  ? '没有需要更新的作品'
                                  : '没有符合条件的作品',
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
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      onPressed: _isUpdating ? null : _scanIllusts,
                      icon: Icon(Icons.search),
                      label: Text(_scannedCount == 0 ? '开始扫描' : '重新扫描'),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isUpdating ||
                              _scannedCount == 0 ||
                              _updateInfos.every((e) => !e.hasChanges && !e.hasBroken)
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
    final isScanning = info.isScanning;
    final isWaiting = !isScanning && info.imageUpdates.isEmpty && _scannedCount > 0;
    final isNotScanned = !isScanning && info.imageUpdates.isEmpty && _scannedCount == 0;
    
    Color backgroundColor;
    Color borderColor;
    IconData leadingIcon;
    Color iconColor;
    String statusText;
    
    if (isScanning) {
      backgroundColor = Colors.blue[50]!;
      borderColor = Colors.blue[400]!;
      leadingIcon = Icons.hourglass_empty;
      iconColor = Colors.blue[700]!;
      statusText = '正在扫描...';
    } else if (isWaiting) {
      backgroundColor = Colors.amber[50]!;
      borderColor = Colors.amber[300]!;
      leadingIcon = Icons.schedule;
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
          width: isChanged || isBroken || isScanning || isWaiting ? 2 : 1,
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
                    '[${info.illust.id}] ${info.illust.title}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    '${info.illust.userName} | ${info.illust.pageCount}P',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black45,
                    ),
                  ),
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
          ],
        ),
        subtitle: null,
        leading: Icon(leadingIcon, color: iconColor, size: 28),
        children: info.imageUpdates.isEmpty
            ? [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        isScanning
                            ? Icons.hourglass_empty
                            : isWaiting
                                ? Icons.schedule
                                : Icons.info_outline,
                        color: iconColor,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 14,
                          color: iconColor,
                          fontWeight: FontWeight.w500,
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

    if (imageUpdate.newFileSize != null &&
        imageUpdate.newFileSize != image.fileSize) {
      changes.add(
          '大小: ${image.fileSize.formatFileSize()} → ${imageUpdate.newFileSize!.formatFileSize()}');
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
            style: TextStyle(fontWeight: FontWeight.bold),
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
                    : Text(changes.join(', ')),
          ),
        ],
      ),
    );
  }
}

