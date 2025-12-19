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
 *
 */

import 'package:flutter/painting.dart';
import 'package:pixez/custom/log.dart';

/// 图片缓存管理器
/// 用于在进入插画详情页时临时增加图片内存缓存大小
class ImageCacheManager {
  static final ImageCacheManager _instance = ImageCacheManager._internal();
  factory ImageCacheManager() => _instance;
  ImageCacheManager._internal();

  /// 默认缓存大小：240MB
  static const int defaultCacheSize = 240 * 1024 * 1024; // 240MB

  /// 详情页缓存大小：1GB
  static const int detailPageCacheSize = 500 * 1024 * 1024; // 500MB

  /// 当前打开的详情页数量
  int _detailPageCount = 0;

  /// 是否已经初始化默认缓存大小
  bool _initialized = false;

  /// 初始化默认缓存大小
  void initialize() {
    if (!_initialized) {
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.maximumSizeBytes = defaultCacheSize;
      _initialized = true;
    }
  }

  /// 进入详情页时调用，增加缓存大小
  void enterDetailPage() {
    _detailPageCount++;
    Log.d(() => '进入详情页，当前详情页数量: $_detailPageCount');
    if (_detailPageCount == 1) {
      Log.d(() => '进入详情页，增加缓存大小到500MB');
      // 第一次进入详情页，将缓存大小增加到1GB
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.maximumSizeBytes = detailPageCacheSize;
    }
  }

  /// 退出详情页时调用，减少缓存大小
  void exitDetailPage() {
    if (_detailPageCount > 0) {
      _detailPageCount--;
      Log.d(() => '退出详情页，当前详情页数量: $_detailPageCount');
      if (_detailPageCount == 0) {
        // 所有详情页都已退出，还原缓存大小为240MB
        final imageCache = PaintingBinding.instance.imageCache;
        Log.d(() => '退出详情页，还原缓存大小为240MB');
        // 只调整缓存大小，让 Flutter 自动淘汰超出的缓存
        // 不调用 clear()，避免阻塞主线程导致页面加载卡顿
        imageCache.maximumSizeBytes = defaultCacheSize;
      }
    }
  }

  /// 获取当前详情页数量（用于调试）
  int get detailPageCount => _detailPageCount;
}

/// 全局单例
final imageCacheManager = ImageCacheManager();
