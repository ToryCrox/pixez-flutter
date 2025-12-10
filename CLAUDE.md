# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在此代码仓库中工作时提供指导。
以后使用中文和我交流。

## 项目概述

PixEz 是一个使用 Flutter 构建的第三方 Pixiv 客户端，支持 Android、iOS、Windows 和 Linux 平台。该应用支持中国大陆地区直连。

## 构建命令
flutter的构建版本为3.32.8

```bash
# 获取依赖
flutter pub get

# 运行代码生成（MobX、JSON 序列化、Riverpod、Freezed）
dart run build_runner build --delete-conflicting-outputs

# 在已连接的设备上运行
flutter run

# 构建 Android APK
flutter build apk

# 为 Google Play 构建（使用环境变量）
flutter build apk --dart-define=IS_GOOGLEPLAY=true

# 构建 Windows MSIX
flutter build windows
dart run msix:create

# 构建 iOS
flutter build ios
```

## 架构

### 状态管理
应用使用多种状态管理方案：
- **MobX**（主要）：Store 位于 `lib/store/`，带有 `.g.dart` 生成文件
- **Riverpod**：配合 `riverpod_annotation` 和代码生成使用
- **Freezed**：用于不可变数据类

### UI 框架
- **Material Design**：移动端（Android/iOS）默认 UI
- **Fluent UI**：当 `lib/constants.dart` 中 `Constants.isFluent = true` 时启用 Windows 风格 UI
  - Fluent 组件在 `lib/fluent/` 目录中对应 Material 组件
  - 使用 `fluent_ui` 和 `flutter_acrylic` 包实现 Windows 特效（Mica/Tabbed）

### 关键目录
- `lib/network/`：Pixiv API 客户端（`api_client.dart` 是主客户端）
- `lib/store/`：全局 MobX Store（用户设置、账户、保存、屏蔽、标签）
- `lib/page/`：按功能组织的 UI 页面
- `lib/models/`：带 JSON 序列化的数据模型（`.g.dart` 文件）
- `lib/er/`：工具模块（hoster、fetcher、leader 用于导航）
- `lib/fluent/`：页面/组件的 Fluent UI 变体，暂时不再使用了,不要修改该目录下的文件了。




### 全局单例（定义于 `lib/main.dart`）
- `userSetting`、`saveStore`、`muteStore`、`accountStore`、`tagHistoryStore`、`topStore`、`bookTagStore`、`fetcher`、`splashStore`

### 网络层
- 使用 `dio` 配合 `rhttp` 实现 HTTP 请求，支持 SNI 绕过（用于国内直连）
- `Hoster` 类管理不同主机的 DNS 解析
- `RefreshTokenInterceptor` 处理令牌刷新

### 平台特定代码
- Android：原生 Kotlin 代码，使用 DocumentFile 实现 SAF、GIF 编码
- Windows/Linux：使用 `sqflite_common_ffi`、`window_manager`
- 通过 `SingleInstancePlugin` 处理单实例

## 国际化

使用 `intl` 包，ARB 文件位于 `lib/l10n/`。生成文件位于 `lib/generated/` 和 `lib/src/generated/i18n/`。

支持的语言：en-US、es-ES、ja-JP、ko-KR、ru-RU、tr-TR、zh-CN、zh-TW

## 测试

```bash
flutter test
```

测试文件位于 `test/` 目录。
