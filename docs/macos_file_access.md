# macOS 外部存储访问实现文档

## 概述

由于 macOS 沙盒机制的限制，应用无法直接访问外部存储卷（如 `/Volumes/` 下的 U盘、移动硬盘）。本实现使用 **Security-Scoped Bookmark** 机制来安全地访问这些资源。

## 实现架构

### 1. Native 层 (Swift)

#### FileAccessManager.swift
负责管理 Security-Scoped Bookmark 的核心逻辑：
- **创建 Bookmark**: 通过系统文件选择器让用户授权目录访问
- **保存 Bookmark**: 将 bookmark 数据持久化到 `UserDefaults`
- **恢复访问**: 从保存的 bookmark 数据恢复访问权限
- **管理访问状态**: 跟踪当前正在访问的资源

#### FileAccessPlugin.swift
Flutter 平台通道插件，提供以下方法：
- `requestDirectoryAccess`: 显示文件选择器，请求用户授权
- `startAccessingPath`: 开始访问指定路径（需要先有 bookmark）
- `stopAccessingPath`: 停止访问指定路径
- `hasBookmark`: 检查路径是否已有 bookmark
- `saveBookmark`: 保存路径的 bookmark
- `clearBookmark`: 清除指定路径的 bookmark
- `clearAllBookmarks`: 清除所有 bookmarks
- `getAllBookmarkedPaths`: 获取所有已保存的 bookmark 路径

### 2. Dart 层

#### MacOSFileAccessManager
封装平台通道调用，提供简洁的 API：

```dart
// 请求用户授权
final (success, path) = await MacOSFileAccessManager.requestDirectoryAccess();

// 开始访问路径
final granted = await MacOSFileAccessManager.startAccessingPath('/Volumes/MyDrive');

// 检查是否已有授权
final hasBookmark = await MacOSFileAccessManager.hasBookmark('/Volumes/MyDrive');

// 确保路径可访问（自动处理授权流程）
final canAccess = await MacOSFileAccessManager.ensureAccess(
  '/Volumes/MyDrive/data',
  autoRequest: true, // 如果没有授权，自动弹出文件选择器
);
```

### 3. 集成到数据库打开流程

在 `DownloadDatabaseProvider.open()` 中：
1. 检测路径是否为外部存储卷 (`/Volumes/` 开头)
2. 检查是否已有 bookmark
3. 如果没有，弹出文件选择器请求用户授权
4. 使用 bookmark 开始访问外部存储
5. 正常打开数据库

## 使用流程

### 首次使用外部存储

1. 用户设置下载路径为外部存储（如 `/Volumes/Lexar/pixez_downloads/`）
2. 应用检测到这是外部存储卷
3. 弹出系统文件选择器，提示用户选择存储卷根目录
4. 用户选择 `/Volumes/Lexar/`
5. 应用创建并保存 Security-Scoped Bookmark
6. 应用开始访问外部存储
7. 正常打开数据库和访问文件

### 后续使用

1. 应用启动，检测到外部存储路径
2. 从保存的 bookmark 恢复访问权限（无需用户交互）
3. 正常访问文件

### Bookmark 失效处理

Bookmark 可能因以下原因失效：
- 外部存储设备被拔出后重新插入（路径可能变化）
- 系统升级或权限变化
- Bookmark 数据损坏

处理流程：
1. 尝试从 bookmark 恢复访问失败
2. 清除旧的 bookmark
3. 提示用户重新授权
4. 重新请求授权并保存新的 bookmark

## 权限要求

在 `DebugProfile.entitlements` 和 `Release.entitlements` 中需要以下权限：

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

- `app-sandbox`: 启用沙盒（必需）
- `files.user-selected.read-write`: 允许访问用户选择的文件和目录

## UI 组件

### MacOSFileAccessSettingsPage
文件访问权限管理页面，提供：
- 查看所有已授权目录
- 添加新的授权目录
- 删除单个授权
- 清除所有授权
- 使用说明

将此页面添加到设置中，方便用户管理授权。

## 注意事项

### 1. Bookmark 的作用域
Bookmark 基于**文件路径字符串**匹配，不是基于设备 UUID。这意味着：
- ✅ 同一外部存储设备的不同子目录可以共享一个父目录的 bookmark
- ⚠️ 设备拔出重插后，如果挂载点名称变化，需要重新授权
- ⚠️ 重命名挂载点也需要重新授权

### 2. 性能考虑
- `startAccessingSecurityScopedResource()` 和 `stopAccessingSecurityScopedResource()` 必须成对调用
- 不要在短时间内频繁调用，会影响性能
- 建议在应用启动时调用一次，退出时释放

### 3. 错误处理
- 用户可能取消授权：优雅处理，提示用户原因
- Bookmark 失效：自动清除并提示重新授权
- 设备未挂载：提示用户连接外部存储

### 4. 用户体验
- 首次使用外部存储时，提供清晰的说明
- 文件选择器的提示信息要准确（如"请选择 /Volumes/Lexar/"）
- 验证用户选择的路径是否正确
- 提供权限管理页面，让用户了解哪些目录已授权

## 测试清单

- [ ] 首次使用外部存储，授权流程正常
- [ ] 用户取消授权，应用不崩溃
- [ ] 应用重启后，自动恢复外部存储访问
- [ ] 外部存储拔出重插后的处理
- [ ] 多个外部存储的管理
- [ ] Bookmark 失效时的重新授权流程
- [ ] 权限管理页面的各项功能
- [ ] 非 macOS 平台的兼容性

## 参考资料

- [Apple: Enabling App Sandbox](https://developer.apple.com/documentation/security/app_sandbox/enabling_app_sandbox)
- [Apple: Security-Scoped Bookmarks](https://developer.apple.com/documentation/security/app_sandbox/accessing_files_from_the_macos_app_sandbox)
- [Apple: NSOpenPanel](https://developer.apple.com/documentation/appkit/nsopenpanel)
