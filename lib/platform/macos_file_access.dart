import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pixez/custom/log.dart';

/// macOS 文件访问管理器
/// 使用 Security-Scoped Bookmark 机制访问外部存储卷
class MacOSFileAccessManager {
  static const _channel = MethodChannel('com.perol.pixez/file_access');

  /// 请求用户授权访问目录
  /// 显示系统文件选择器，用户选择目录后创建 bookmark
  /// 返回：(是否成功, 选择的路径)
  static Future<(bool, String?)> requestDirectoryAccess() async {
    if (!Platform.isMacOS) {
      return (false, null);
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'requestDirectoryAccess',
      );
      if (result == null) return (false, null);

      final success = result['success'] as bool? ?? false;
      final path = result['path'] as String?;
      return (success, path);
    } catch (e) {
      Log.e(() => '❌ requestDirectoryAccess error', error: e);
      return (false, null);
    }
  }

  /// 开始访问指定路径（从 bookmark 恢复权限）
  /// 必须在访问外部存储文件前调用
  /// - [path]: 文件或目录的绝对路径
  /// - 返回：是否成功
  static Future<bool> startAccessingPath(String path) async {
    if (!Platform.isMacOS) {
      return true; // 非 macOS 平台直接返回成功
    }

    try {
      final result = await _channel.invokeMethod<bool>('startAccessingPath', {
        'path': path,
      });
      return result ?? false;
    } catch (e) {
      Log.e(() => '❌ startAccessingPath error', error: e);
      return false;
    }
  }

  /// 停止访问指定路径
  /// 释放 Security-Scoped Resource
  /// - [path]: 文件或目录的绝对路径
  static Future<void> stopAccessingPath(String path) async {
    if (!Platform.isMacOS) {
      return;
    }

    try {
      await _channel.invokeMethod<bool>('stopAccessingPath', {'path': path});
    } catch (e) {
      Log.e(() => '❌ stopAccessingPath error', error: e);
    }
  }

  /// 检查路径是否已有 bookmark
  /// - [path]: 文件或目录的绝对路径
  /// - 返回：是否存在 bookmark
  static Future<bool> hasBookmark(String path) async {
    if (!Platform.isMacOS) {
      return true; // 非 macOS 平台直接返回 true
    }

    try {
      final result = await _channel.invokeMethod<bool>('hasBookmark', {
        'path': path,
      });
      return result ?? false;
    } catch (e) {
      Log.e(() => '❌ hasBookmark error', error: e);
      return false;
    }
  }

  /// 保存指定路径的 bookmark（不显示文件选择器）
  /// 用于用户已经通过其他方式选择了路径的情况
  /// - [path]: 文件或目录的绝对路径
  /// - 返回：是否成功
  static Future<bool> saveBookmark(String path) async {
    if (!Platform.isMacOS) {
      return true;
    }

    try {
      final result = await _channel.invokeMethod<bool>('saveBookmark', {
        'path': path,
      });
      return result ?? false;
    } catch (e) {
      Log.e(() => '❌ saveBookmark error', error: e);
      return false;
    }
  }

  /// 清除指定路径的 bookmark
  /// - [path]: 文件或目录的绝对路径
  static Future<void> clearBookmark(String path) async {
    if (!Platform.isMacOS) {
      return;
    }

    try {
      await _channel.invokeMethod<bool>('clearBookmark', {'path': path});
    } catch (e) {
      Log.e(() => '❌ clearBookmark error', error: e);
    }
  }

  /// 清除所有 bookmarks
  static Future<void> clearAllBookmarks() async {
    if (!Platform.isMacOS) {
      return;
    }

    try {
      await _channel.invokeMethod<bool>('clearAllBookmarks');
    } catch (e) {
      Log.e(() => '❌ clearAllBookmarks error', error: e);
    }
  }

  /// 获取所有已保存的 bookmark 路径
  /// - 返回：路径列表
  static Future<List<String>> getAllBookmarkedPaths() async {
    if (!Platform.isMacOS) {
      return [];
    }

    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getAllBookmarkedPaths',
      );
      return result?.cast<String>() ?? [];
    } catch (e) {
      Log.e(() => '❌ getAllBookmarkedPaths error', error: e);
      return [];
    }
  }

  /// 检查路径是否在 /Volumes/ 下（外部存储卷）
  static bool isExternalVolume(String path) {
    return path.startsWith('/Volumes/');
  }

  /// 获取路径的根目录（对于外部存储卷，返回 /Volumes/卷名）
  static String getRootPath(String path) {
    if (!isExternalVolume(path)) {
      return path;
    }

    // /Volumes/VolumeName/... -> /Volumes/VolumeName
    final parts = path.split('/');
    if (parts.length >= 3) {
      return '/${parts[1]}/${parts[2]}';
    }
    return path;
  }

  /// 确保路径可访问
  /// 如果是外部存储卷，检查并请求 bookmark 权限
  /// - [path]: 文件或目录的绝对路径
  /// - [autoRequest]: 如果没有 bookmark，是否自动显示文件选择器请求授权
  /// - 返回：是否成功获取访问权限
  static Future<bool> ensureAccess(
    String path, {
    bool autoRequest = false,
  }) async {
    if (!Platform.isMacOS) {
      return true;
    }

    // 非外部存储卷，直接返回成功
    if (!isExternalVolume(path)) {
      return true;
    }

    final rootPath = getRootPath(path);

    // 检查是否已有 bookmark
    final hasBookmarkResult = await hasBookmark(rootPath);
    if (hasBookmarkResult) {
      // 尝试开始访问
      return await startAccessingPath(rootPath);
    }

    // 没有 bookmark
    if (!autoRequest) {
      Log.w(() => '⚠️ No bookmark for external volume: $rootPath');
      return false;
    }

    // 自动请求授权
    Log.d(() => '📁 Requesting access for: $rootPath');
    final (success, selectedPath) = await requestDirectoryAccess();
    if (!success || selectedPath == null) {
      return false;
    }

    // 验证用户选择的路径是否匹配
    if (!path.startsWith(selectedPath)) {
      Log.w(
        () => '⚠️ Selected path does not match: $selectedPath vs $rootPath',
      );
      return false;
    }

    // 开始访问
    return await startAccessingPath(selectedPath);
  }
}
