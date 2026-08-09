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

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_mana/flutter_mana.dart';
import 'package:flutter_mana_kits/flutter_mana_kits.dart';

/// Mana 调试工具管理器
///
/// 用于管理 flutter_mana 插件的初始化和配置。
/// - Debug 模式下自动启用所有插件
/// - Release 模式下通过设置控制是否启用（仅支持的插件）
class ManaManager {
  static final ManaManager instance = ManaManager._();
  ManaManager._();

  bool _initialized = false;

  /// Release 模式下是否启用 Mana（通过设置控制）
  bool _enableInRelease = false;

  /// Dio 拦截器实例（使用 ManaDioCollector）
  Interceptor? _dioInterceptor;

  /// 是否启用 Mana
  bool get isEnabled => kDebugMode || _enableInRelease;

  /// 获取 Dio 拦截器（用于网络请求追踪）
  Interceptor? get dioInterceptor => _dioInterceptor;

  /// 设置 Release 模式下是否启用
  void setEnableInRelease(bool enable) {
    _enableInRelease = enable;
  }

  /// 初始化并注册所有插件
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    // 创建 Dio 拦截器（使用 ManaDioCollector 收集网络请求）
    _dioInterceptor = ManaDioCollector();

    if (kDebugMode) {
      // Debug 模式：注册所有插件
      _registerAllPlugins();
    } else {
      // Release 模式：仅注册支持的插件
      _registerReleasePlugins();
    }
  }

  /// 注册所有插件（Debug 模式）
  void _registerAllPlugins() {
    ManaPluginManager.instance
      ..register(ManaScreenInfo())
      ..register(ManaTouchIndicator())
      ..register(ManaVisualHelper())
      ..register(ManaGrid())
      ..register(ManaLicense())
      ..register(ManaPackageInfo())
      ..register(ManaMemoryInfo())
      ..register(ManaShowCode())
      ..register(ManaLogViewer())
      ..register(ManaDeviceInfo())
      ..register(ManaColorSucker())
      ..register(ManaDioInspector())
      ..register(ManaWidgetInfoInspector())
      ..register(ManaFpsMonitor())
      ..register(ManaSharedPreferencesViewer())
      ..register(ManaAlignRuler());
  }

  /// 注册 Release 模式下支持的插件
  void _registerReleasePlugins() {
    ManaPluginManager.instance
      // 完全支持的插件
      ..register(ManaScreenInfo())
      ..register(ManaTouchIndicator())
      ..register(ManaGrid())
      ..register(ManaLicense())
      ..register(ManaPackageInfo())
      ..register(ManaDeviceInfo())
      ..register(ManaColorSucker())
      ..register(ManaDioInspector())
      ..register(ManaFpsMonitor())
      ..register(ManaSharedPreferencesViewer())
      ..register(ManaAlignRuler())
      // 部分支持的插件
      ..register(ManaLogViewer())
      ..register(ManaVisualHelper());
    // 不支持的插件（不注册）：
    // - ManaWidgetInfoInspector
    // - ManaShowCode
    // - ManaMemoryInfo
  }
}
