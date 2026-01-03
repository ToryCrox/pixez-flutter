# macOS 外部存储访问 - 编译指南

## 重要提示

新创建的 Swift 文件需要手动添加到 Xcode 项目中才能编译成功。

## 快速修复步骤

### 方法1: 使用 Xcode（推荐）

1. **打开 Xcode 项目**
   ```bash
   open macos/Runner.xcworkspace
   ```

2. **添加 Swift 文件**
   - 在左侧导航器中，找到 `Runner` 文件夹
   - 右键点击 `Runner` 文件夹 → `Add Files to Runner`
   - 导航到 `macos/Runner/` 目录
   - 选择以下文件（按住 Cmd 键多选）：
     - `FileAccessManager.swift`
     - `FileAccessPlugin.swift`
   - 确保勾选 ✅ `Copy items if needed`
   - 确保勾选 ✅ Target: `Runner`
   - 点击 `Add`

3. **验证文件已添加**
   - 在 Xcode 左侧导航器中，应该能看到这两个文件
   - 点击 `Runner` 文件夹，在文件列表中确认：
     - `AppDelegate.swift`
     - `MainFlutterWindow.swift`
     - `DocumentPlugin.swift`
     - `FileAccessManager.swift` ✨ 新添加
     - `FileAccessPlugin.swift` ✨ 新添加

4. **重新编译**
   ```bash
   flutter clean
   flutter pub get
   flutter build macos --debug
   ```

###方法2: 使用命令行

如果你熟悉 `pbxproj` 文件格式，可以手动编辑：

1. **生成唯一 ID**（使用随机字符串）
   ```bash
   # FileAccessManager.swift
   FILE_ACCESS_MANAGER_FILE_ID="FAM123456789ABCD"  # 替换为随机ID
   FILE_ACCESS_MANAGER_BUILD_ID="FAMB123456789ABC"  # 替换为随机ID
   
   # FileAccessPlugin.swift
   FILE_ACCESS_PLUGIN_FILE_ID="FAP123456789ABCD"
   FILE_ACCESS_PLUGIN_BUILD_ID="FAPB123456789ABC"
   ```

2. **编辑 `macos/Runner.xcodeproj/project.pbxproj`**

   在 `/* Begin PBXBuildFile section */` 中添加:
   ```
   ${FILE_ACCESS_MANAGER_BUILD_ID} /* FileAccessManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${FILE_ACCESS_MANAGER_FILE_ID} /* FileAccessManager.swift */; };
   ${FILE_ACCESS_PLUGIN_BUILD_ID} /* FileAccessPlugin.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${FILE_ACCESS_PLUGIN_FILE_ID} /* FileAccessPlugin.swift */; };
   ```

   在 `/* Begin PBXFileReference section */` 中添加:
   ```
   ${FILE_ACCESS_MANAGER_FILE_ID} /* FileAccessManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FileAccessManager.swift; sourceTree = "<group>"; };
   ${FILE_ACCESS_PLUGIN_FILE_ID} /* FileAccessPlugin.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FileAccessPlugin.swift; sourceTree = "<group>"; };
   ```

   在 Runner 组的 children 中（大约第186行）添加:
   ```
   ${FILE_ACCESS_MANAGER_FILE_ID} /* FileAccessManager.swift */,
   ${FILE_ACCESS_PLUGIN_FILE_ID} /* FileAccessPlugin.swift */,
   ```

   在 Sources 编译阶段（大约第439行）添加:
   ```
   ${FILE_ACCESS_MANAGER_BUILD_ID} /* FileAccessManager.swift in Sources */,
   ${FILE_ACCESS_PLUGIN_BUILD_ID} /* FileAccessPlugin.swift in Sources */,
   ```

## 验证安装

编译成功后，你应该看到：

```
✅ Building macOS application...
✅ Built build/macos/Build/Products/Debug/pixez_flutter.app
```

## 使用说明

### 首次运行

1. **启动应用**
   - 应用会自动检测下载路径是否在外部存储卷
   - 如果需要，会弹出文件选择器请求授权

2. **选择目录**
   - 在文件选择器中，选择外部存储卷的**根目录**
   - 例如：如果下载路径是 `/Volumes/Lexar/pixez_downloads/`
   - 请选择 `/Volumes/Lexar/`

3. **授权成功**
   - 应用会保存 Security-Scoped Bookmark
   - 下次启动时自动恢复访问权限

### 管理授权

访问 **设置 → macOS 文件访问权限** 页面可以：
- 查看所有已授权的目录
- 添加新的授权
- 删除不需要的授权

## 常见问题

### Q: 编译失败 "cannot find 'FileAccessPlugin' in scope"
**A:** Swift 文件未正确添加到 Xcode 项目中，请按照上述步骤添加。

### Q: 应用启动后仍然无法访问外部存储
**A:** 
1. 检查是否在文件选择器中选择了正确的目录
2. 确认外部存储已正确挂载
3. 尝试在设置中清除授权并重新授权

### Q: Bookmark 失效怎么办？
**A:** 
1. 打开设置中的文件访问权限页面
2. 删除失效的授权
3. 重新添加授权

### Q: 如何从外部存储切换回本地目录？
**A:** 
1. 在设置中修改下载路径到本地目录（如 `~/Documents/pixez/`）
2. 重启应用
3. 本地目录不需要额外授权

## 技术细节

- **Bookmark 存储位置**: `UserDefaults.standard`
- **Bookmark Key**: `securityScopedBookmark`
- **访问方式**: `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`
- **权限要求**: `com.apple.security.files.user-selected.read-write`

## 了解更多

查看详细文档：`docs/macos_file_access.md`
