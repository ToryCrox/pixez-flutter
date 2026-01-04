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
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart' hide Size;
import 'package:path/path.dart' as p;
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/download_record.dart'
    show
        DownloadedIllust,
        DownloadedImage,
        DownloadDatabaseProvider,
        kImageExtensions;
import 'package:pixez/models/illust.dart';
import 'package:pixez/network/api_client.dart';

import '../../custom/log.dart';

class ImportDialog extends StatefulWidget {
  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _maxCountController =
      TextEditingController(text: '10');
  List<ImportIllustInfo> _illusts = [];
  bool _isLoading = false;
  bool _isImporting = false;
  Map<int, ImportProgress> _importProgress = {};
  String? _errorMessage;
  ImportMode _importMode = ImportMode.directory; // 导入模式：目录模式或平铺模式

  @override
  void dispose() {
    _pathController.dispose();
    _maxCountController.dispose();
    super.dispose();
  }

  // 获取最大导入数量
  int _getMaxImportCount() {
    final countStr = _maxCountController.text.trim();
    if (countStr.isEmpty) return 10; // 默认值
    final count = int.tryParse(countStr);
    return count ?? 10; // 解析失败时返回默认值
  }

  // 解析插画目录名，提取插画ID
  int? _extractIllustId(String dirName) {
    // 目录名格式: [133786790]fate　イリヤ　※再投稿
    // 第一个中括号中的是插画作品id
    final regex = RegExp(r'^\[(\d+)\]');
    final match = regex.firstMatch(dirName);
    if (match != null) {
      final idStr = match.group(1)!;
      final id = int.tryParse(idStr);
      // 如果是[0]开头，返回null，表示这是散图目录
      if (id == 0) {
        return null;
      }
      return id;
    }
    return null;
  }

  // 从文件名提取插画ID（用于散图目录）
  int? _extractIllustIdFromFileName(String fileName) {
    // 文件名格式: 130683511_p0.webp
    // 下划线前面的是作品ID
    final regex = RegExp(r'^(\d+)_');
    final match = regex.firstMatch(fileName);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  // 从文件名提取插画ID（用于平铺模式）
  // 文件名格式: [Ninempty][114880474]_129477132_Sorakado Ao - 空門蒼_p15.webp
  // 插画ID在第一个下划线之后，第二个下划线之前
  int? _extractIllustIdFromFlatFileName(String fileName) {
    // 匹配模式：_数字_任意字符_p数字.扩展名
    // 这样可以准确匹配到插画ID（在标题之前，页码之前）
    final regex = RegExp(r'_(\d+)_[^_]*_p\d+\.');
    final match = regex.firstMatch(fileName);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    // 备用方案：如果文件名格式不完全匹配，尝试匹配所有 _数字_ 的模式，取最后一个（通常是插画ID）
    final allMatches = RegExp(r'_(\d+)_').allMatches(fileName);
    if (allMatches.isNotEmpty) {
      // 取最后一个匹配（通常是插画ID，在标题之前）
      final lastMatch = allMatches.last;
      return int.tryParse(lastMatch.group(1)!);
    }
    return null;
  }

  // 解析文件名，提取页码
  int? _extractPart(String fileName) {
    // 文件名格式: 133786790_p0.webp
    final regex = RegExp(r'_p(\d+)\.');
    final match = regex.firstMatch(fileName);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  Future<void> _scanDirectory() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() {
        _errorMessage = '请输入目录路径';
      });
      return;
    }

    final dir = Directory(path);
    if (!await dir.exists()) {
      setState(() {
        _errorMessage = '目录不存在';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _illusts = [];
    });

    try {
      final illustData =
          <int, Map<String, dynamic>>{}; // illustId -> {files: [], dirPath: ''}

      if (_importMode == ImportMode.flat) {
        // 平铺模式：直接扫描目录下的所有图片文件
        await _scanFlatDirectory(dir, illustData);
      } else {
        // 目录模式：扫描目录下的所有子目录
        await _scanDirectoryMode(dir, illustData);
      }

      // 从网络获取插画信息，并检查是否已存在
      final illustInfos = <ImportIllustInfo>[];
      for (final entry in illustData.entries) {
        final illustId = entry.key;
        final files = entry.value['files'] as List<String>;
        final sourceDirPath = entry.value['dirPath'] as String;

        // 检查插画是否已存在
        final existingIllust =
            await downloadStore.getDownloadedIllust(illustId);
        bool isExisting = existingIllust != null;

        // 尝试获取插画信息（优先从网络获取最新信息，失败则从数据库恢复）
        Illusts? illusts;
        String? error;

        try {
          // 优先从网络获取最新信息
          final response = await apiClient.getIllustDetail(illustId);
          illusts = Illusts.fromJson(response.data['illust']);
        } catch (e) {
          // 网络获取失败，如果已存在则尝试从数据库恢复
          if (isExisting) {
            try {
              illusts = existingIllust.toIllusts();
            } catch (e2) {
              error = '网络获取失败: $e, 数据库恢复失败: $e2';
            }
          } else {
            error = e.toString();
          }
        }

        if (illusts != null) {
          illustInfos.add(ImportIllustInfo(
            illusts: illusts,
            sourceFiles: files,
            isExisting: isExisting,
            sourceDirPath: sourceDirPath,
          ));
        } else {
          // 如果获取失败，仍然添加到列表，但标记为错误
          illustInfos.add(ImportIllustInfo(
            illustId: illustId,
            sourceFiles: files,
            error: error ?? '无法获取插画信息',
            isExisting: isExisting,
            sourceDirPath: sourceDirPath,
          ));
        }
      }

      setState(() {
        _illusts = illustInfos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '扫描目录失败: $e';
        _isLoading = false;
      });
    }
  }

  // 扫描平铺模式的目录（直接扫描目录下的所有图片文件）
  Future<void> _scanFlatDirectory(
      Directory dir, Map<int, Map<String, dynamic>> illustData) async {
    final groupedFiles = <int, List<String>>{}; // illustId -> files
    try {
      final fileList = await dir.list().toList();
      for (final fileEntity in fileList) {
        if (fileEntity is File) {
          final fileName = p.basename(fileEntity.path);
          final extension = p.extension(fileName).toLowerCase();
          if (kImageExtensions.contains(extension)) {
            // 从文件名提取作品ID和页码
            final fileIllustId = _extractIllustIdFromFlatFileName(fileName);
            final part = _extractPart(fileName);
            if (fileIllustId != null && part != null) {
              groupedFiles
                  .putIfAbsent(fileIllustId, () => [])
                  .add(fileEntity.path);
            }
          }
        }
      }
    } catch (e) {
      Log.e('扫描目录失败: $e');
      // 忽略无法访问的文件
    }
    // 为每个作品ID创建数据项
    for (final entry in groupedFiles.entries) {
      if (entry.value.isNotEmpty) {
        illustData[entry.key] = {
          'files': entry.value,
          'dirPath': dir.path,
        };
      }
      if (illustData.length > _getMaxImportCount()) {
        // 忽略数量超出限制的目录
        break;
      }
    }
  }

  // 扫描目录模式（扫描子目录）
  Future<void> _scanDirectoryMode(
      Directory dir, Map<int, Map<String, dynamic>> illustData) async {
    final subDirs = await dir.list().toList();
    for (final entity in subDirs) {
      if (entity is Directory) {
        final dirName = p.basename(entity.path);
        final illustId = _extractIllustId(dirName);

        // 处理散图目录（[0]开头的目录）
        if (illustId == null && dirName.startsWith('[0]')) {
          // 扫描该目录下的所有图片文件，按作品ID分组
          final groupedFiles = <int, List<String>>{}; // illustId -> files
          try {
            final fileList = await entity.list().toList();
            for (final fileEntity in fileList) {
              if (fileEntity is File) {
                final fileName = p.basename(fileEntity.path);
                final extension = p.extension(fileName).toLowerCase();
                if (kImageExtensions.contains(extension)) {
                  // 从文件名提取作品ID
                  final fileIllustId = _extractIllustIdFromFileName(fileName);
                  final part = _extractPart(fileName);
                  if (fileIllustId != null && part != null) {
                    groupedFiles
                        .putIfAbsent(fileIllustId, () => [])
                        .add(fileEntity.path);
                  }
                }
              }
            }
          } catch (e) {
            // 忽略无法访问的目录
          }
          // 为每个作品ID创建数据项
          for (final entry in groupedFiles.entries) {
            if (entry.value.isNotEmpty) {
              illustData[entry.key] = {
                'files': entry.value,
                'dirPath': entity.path,
              };
            }
            if (groupedFiles.length > _getMaxImportCount()) {
              // 忽略数量超出限制的目录
              break;
            }
          }
        } else if (illustId != null) {
          // 处理普通目录（单个作品目录）
          // 扫描该目录下的所有图片文件
          final files = <String>[];
          try {
            final fileList = await entity.list().toList();
            for (final fileEntity in fileList) {
              if (fileEntity is File) {
                final fileName = p.basename(fileEntity.path);
                final part = _extractPart(fileName);
                if (part != null &&
                    kImageExtensions
                        .contains(p.extension(fileName).toLowerCase())) {
                  files.add(fileEntity.path);
                }
              }
            }
          } catch (e) {
            // 忽略无法访问的目录
          }
          if (files.isNotEmpty) {
            illustData[illustId] = {
              'files': files,
              'dirPath': entity.path,
            };
          }
          if (illustData.length > _getMaxImportCount()) {
            // 忽略数量超出限制的目录
            break;
          }
        }
      }
    }
  }

  Future<void> _startImport() async {
    if (_illusts.isEmpty) {
      return;
    }

    setState(() {
      _isImporting = true;
      _importProgress = {};
      for (final illust in _illusts) {
        if (illust.illusts != null) {
          _importProgress[illust.illusts!.id] = ImportProgress(
            total: illust.sourceFiles.length,
            completed: 0,
            status: illust.isExisting ? '准备替换' : '准备中',
          );
        } else if (illust.isExisting && illust.illustId != null) {
          _importProgress[illust.illustId!] = ImportProgress(
            total: illust.sourceFiles.length,
            completed: 0,
            status: '准备替换',
          );
        }
      }
    });

    try {
      for (final illustInfo in _illusts) {
        if (illustInfo.illusts == null || illustInfo.error != null) {
          continue; // 跳过无法获取信息的插画
        }

        final illusts = illustInfo.illusts!;
        final illustId = illusts.id;

        // 检查是否已存在（用于更新状态显示）
        final existingIllust =
            await downloadStore.getDownloadedIllust(illustId);
        if (existingIllust != null) {
          illustInfo.isExisting = true;
        }

        // 更新进度
        setState(() {
          _importProgress[illustId] = ImportProgress(
            total: illustInfo.sourceFiles.length,
            completed: 0,
            status: illustInfo.isExisting ? '替换中' : '导入中',
          );
        });

        // 构建目标路径
        final relativePath =
            DownloadDatabaseProvider.buildRelativePath(illusts);
        final targetDir = Directory(
            downloadStore.dbProvider.getIllustAbsolutePath(relativePath));
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        // 移动文件并记录到数据库
        int completedCount = 0;
        for (final sourceFile in illustInfo.sourceFiles) {
          final t1 = DateTime.now();
          try {
            final source = File(sourceFile);
            if (!await source.exists()) {
              continue;
            }

            final fileName = p.basename(sourceFile);
            final part = _extractPart(fileName);
            if (part == null) continue;

            final extension = p.extension(fileName);
            final targetFileName =
                DownloadDatabaseProvider.buildFileName(illusts.id, part);
            final targetPath =
                p.join(targetDir.path, '$targetFileName$extension');

            // 检查文件或记录是否已存在
            final isImageDownloaded = await downloadStore.dbProvider
                .isImageDownloaded(illustId, part);
            if (isImageDownloaded) {
              // 已存在，需要删除旧文件（可能后缀不同）
              try {
                // 尝试找到旧文件路径（自动检测后缀）
                final oldFilePath = await downloadStore.dbProvider
                    .findImagePath(illustId, part);
                if (oldFilePath != null) {
                  final oldFile = File(oldFilePath);
                  if (await oldFile.exists()) {
                    await oldFile.delete();
                  }
                }
              } catch (e) {
                Log.w('删除旧文件失败: $e');
                // 继续导入，即使删除旧文件失败
              }
            } else if (await File(targetPath).exists()) {
              // 文件已存在但数据库中没有记录，删除旧文件
              try {
                await File(targetPath).delete();
              } catch (e) {
                Log.w('删除已存在文件失败: $e');
              }
            }

            // 移动文件：先尝试 rename，失败则使用 copy + delete
            try {
              await source.rename(targetPath);
            } catch (e) {
              Log.w('move file ${source.path} => ${targetPath} failed: $e');
              // rename 失败（可能是跨磁盘），使用 copy + delete
              await source.copy(targetPath);
              await source.delete();
            }

            // 获取文件大小
            int fileSize = 0;
            try {
              final file = File(targetPath);
              if (await file.exists()) {
                fileSize = await file.length();
              }
            } catch (_) {}

            // 解析图片宽高
            int? imageWidth;
            int? imageHeight;
            try {
              final size = await _getImageSize(targetPath);
              if (size != null) {
                imageWidth = size.width.toInt();
                imageHeight = size.height.toInt();
              }
            } catch (e) {
              // 忽略解析失败
            }

            // 获取原始URL（从illusts中获取）
            String url = '';
            if (illusts.pageCount == 1) {
              url = illusts.metaSinglePage?.originalImageUrl ?? '';
            } else if (part < illusts.metaPages.length) {
              url = illusts.metaPages[part].imageUrls?.original ?? '';
            }

            // 插入插画信息（如果不存在）
            final existingIllust =
                await downloadStore.getDownloadedIllust(illusts.id);
            if (existingIllust == null) {
              final downloadedIllust =
                  DownloadedIllust.fromIllusts(illusts, relativePath);
              await downloadStore.dbProvider.insertIllust(downloadedIllust);
            }

            // 插入图片记录
            final downloadedImage = DownloadedImage(
              illustId: illusts.id,
              part: part,
              fileName: targetFileName,
              extension: extension,
              fileSize: fileSize,
              originalUrl: url,
              relativePath: relativePath,
              width: imageWidth,
              height: imageHeight,
            );
            await downloadStore.dbProvider.insertImage(downloadedImage);

            completedCount++;
            setState(() {
              _importProgress[illustId] = ImportProgress(
                total: illustInfo.sourceFiles.length,
                completed: completedCount,
                status: illustInfo.isExisting ? '替换中' : '导入中',
              );
            });
          } catch (e) {
            // 单个文件导入失败，继续下一个
          }
          Log.d(
              'import file ${sourceFile} completed in ${DateTime.now().difference(t1).inMilliseconds}ms');
        }

        // 更新作者统计
        await downloadStore.dbProvider.updateAuthorStats(illusts.user.id);

        // 标记为完成
        setState(() {
          _importProgress[illustId] = ImportProgress(
            total: illustInfo.sourceFiles.length,
            completed: completedCount,
            status: '完成',
          );
        });

        // 通知插画下载状态更新，触发监听位置刷新
        await downloadStore.notifyIllustDownloadStatus(illustId);

        // 检查并删除源目录（如果为空）
        if (illustInfo.sourceDirPath != null) {
          try {
            final sourceDir = Directory(illustInfo.sourceDirPath!);
            if (await sourceDir.exists()) {
              // 检查目录是否为空（只检查图片文件）
              final isEmpty = await _isDirectoryEmptyOfImages(sourceDir);
              if (isEmpty) {
                await sourceDir.delete(recursive: true);
              }
            }
          } catch (e) {
            // 删除目录失败，忽略错误
          }
        }
      }

      // 刷新下载计数
      await downloadStore.refreshCount();

      // 标记导入完成，但不关闭对话框
      setState(() {
        _isImporting = false;
      });

      // 显示完成提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入完成')),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = '导入失败: $e';
        _isImporting = false;
      });
    }
  }

  Future<Size?> _getImageSize(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final size = await compute(_parseImageSizeSync, filePath);
      return size;
    } catch (e) {
      return null;
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

  // 检查目录是否为空（只检查图片文件）
  Future<bool> _isDirectoryEmptyOfImages(Directory dir) async {
    try {
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final fileName = p.basename(entity.path);
          final extension = p.extension(fileName).toLowerCase();
          if (kImageExtensions.contains(extension)) {
            return false; // 发现图片文件，目录不为空
          }
        }
      }
      return true; // 没有图片文件，目录为空
    } catch (e) {
      return false; // 检查失败，假设不为空
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('导入插画'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 导入模式选择
            Row(
              children: [
                Text('导入模式: '),
                SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Radio<ImportMode>(
                        value: ImportMode.directory,
                        groupValue: _importMode,
                        onChanged: _isLoading || _isImporting
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() {
                                    _importMode = value;
                                    _illusts = [];
                                    _errorMessage = null;
                                  });
                                }
                              },
                      ),
                      Text('目录模式'),
                      SizedBox(width: 16),
                      Radio<ImportMode>(
                        value: ImportMode.flat,
                        groupValue: _importMode,
                        onChanged: _isLoading || _isImporting
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() {
                                    _importMode = value;
                                    _illusts = [];
                                    _errorMessage = null;
                                  });
                                }
                              },
                      ),
                      Text('平铺模式'),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: InputDecoration(
                      labelText: '目录路径',
                      hintText: _importMode == ImportMode.flat
                          ? '请输入包含平铺图片的目录路径'
                          : '请输入目录路径',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _scanDirectory,
                  child: _isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('获取'),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Text('最大导入数量: '),
                SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _maxCountController,
                    enabled: !_isLoading && !_isImporting,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '10',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            if (_errorMessage != null)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red),
                ),
              ),
            SizedBox(height: 16),
            Expanded(
              child: _illusts.isEmpty
                  ? Center(
                      child: Text(
                        _isLoading ? '正在扫描目录...' : '请先扫描目录获取插画列表',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _illusts.length,
                      itemBuilder: (context, index) {
                        final illust = _illusts[index];
                        if (illust.illusts == null && !illust.isExisting) {
                          return Card(
                            margin: EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: SelectableText('插画ID: ${illust.illustId}'),
                              subtitle: Text('获取信息失败: ${illust.error}'),
                              leading: Icon(Icons.error, color: Colors.red),
                            ),
                          );
                        }

                        // 已存在的插画
                        // if (illust.isExisting) {
                        //   final progress = _importProgress[illust.illustId];
                        //   return Card(
                        //     margin: EdgeInsets.symmetric(vertical: 4),
                        //     color: Colors.orange[50],
                        //     child: ListTile(
                        //       leading: Icon(Icons.info, color: Colors.orange),
                        //       title: SelectableText('插画ID: ${illust.illustId}'),
                        //       subtitle: Column(
                        //         crossAxisAlignment: CrossAxisAlignment.start,
                        //         children: [
                        //           Text('状态: 已存在（将替换）', style: TextStyle(color: Colors.orange[700])),
                        //           Text('文件数: ${illust.sourceFiles.length}'),
                        //           if (progress != null)
                        //             Column(
                        //               crossAxisAlignment: CrossAxisAlignment.start,
                        //               children: [
                        //                 SizedBox(height: 4),
                        //                 LinearProgressIndicator(
                        //                   value: progress.total > 0
                        //                       ? progress.completed / progress.total
                        //                       : 0,
                        //                 ),
                        //                 Text(
                        //                   '${progress.completed}/${progress.total} - ${progress.status}',
                        //                   style: TextStyle(fontSize: 12),
                        //                 ),
                        //               ],
                        //             ),
                        //         ],
                        //       ),
                        //     ),
                        //   );
                        // }

                        final illusts = illust.illusts!;
                        final progress = _importProgress[illusts.id];
                        final isPageComplete = illust.sourceFiles.length == illusts.pageCount;

                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: illust.isExisting
                                ? Icon(Icons.info, color: Colors.orange)
                                : Icon(Icons.image),
                            title: SelectableText(
                                '#$index, ${illusts.id} ${illusts.title}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('作者: ${illusts.user.name}'),
                                Text(
                                  '文件数: ${illust.sourceFiles.length}/${illusts.pageCount}',
                                  style: !isPageComplete ? TextStyle(color: Colors.red) : null,
                                ),
                                if (illust.isExisting)
                                  Text('状态: 已存在（将替换）',
                                      style:
                                          TextStyle(color: Colors.orange[700])),
                                if (progress != null)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(height: 4),
                                      LinearProgressIndicator(
                                        value: progress.total > 0
                                            ? progress.completed /
                                                progress.total
                                            : 0,
                                      ),
                                      Text(
                                        '${progress.completed}/${progress.total} - ${progress.status}',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isImporting ? null : () => Navigator.of(context).pop(false),
          child: Text(I18n.of(context).cancel),
        ),
        if (_isImporting)
          ElevatedButton(
            onPressed: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('导入中...'),
              ],
            ),
          )
        else
          ElevatedButton(
            onPressed: _illusts.isEmpty ? null : _startImport,
            child: Text('确认导入'),
          ),
      ],
    );
  }
}

class ImportIllustInfo {
  final Illusts? illusts;
  final int? illustId;
  final List<String> sourceFiles;
  final String? error;
  bool isExisting; // 标记是否已存在
  String? sourceDirPath; // 源目录路径，用于导入完成后删除空文件夹

  ImportIllustInfo({
    this.illusts,
    this.illustId,
    required this.sourceFiles,
    this.error,
    this.isExisting = false,
    this.sourceDirPath,
  });
}

class ImportProgress {
  final int total;
  final int completed;
  final String status;

  ImportProgress({
    required this.total,
    required this.completed,
    required this.status,
  });
}

enum ImportMode {
  directory, // 目录模式：扫描子目录
  flat, // 平铺模式：直接扫描目录下的图片文件
}
