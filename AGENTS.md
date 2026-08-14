# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在此代码仓库中工作时提供指导。
以后使用中文和我交流。

## 项目概述

PixEz 是一个使用 Flutter 构建的第三方 Pixiv 客户端，支持 Android、iOS、Windows 和 Linux 平台。该应用支持中国大陆地区直连。

## 构建命令
flutter的构建版本为3.38.10

```bash
# 获取依赖
fvm flutter pub get

# 运行代码生成（MobX、JSON 序列化、Riverpod、Freezed）
fvm flutter run build_runner build --delete-conflicting-outputs

# 在已连接的设备上运行
fvm flutter run

# 构建 Android APK
fvm flutter build apk

# 为 Google Play 构建（使用环境变量）
fvm flutter build apk --dart-define=IS_GOOGLEPLAY=true

# 构建 Windows MSIX
fvm flutter build windows
fvm flutter run msix:create

# 构建 iOS
fvm flutter build ios
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

### 关键页面

**主框架**
- `lib/page/hello/hello_page.dart`：主框架页面，包含底部导航栏的 5 个标签页（推荐、排行、动态、搜索、设置）

**首页/推荐**
- `lib/page/hello/recom/recom_spotlight_page.dart`：推荐页（首页），展示推荐插画和 Pixivision 特辑
- `lib/page/preview/preview_page.dart`：预览页（未登录状态下的推荐内容）

**排行榜**
- `lib/page/hello/ranking/rank_page.dart`：排行榜页面，支持日榜/周榜/月榜/R18 等多种模式
- `lib/page/hello/ranking/ranking_mode/rank_mode_page.dart`：具体排行模式页面

**动态（关注）**
- `lib/page/hello/new/new_page.dart`：动态标签页，包含 4 个子标签（关注作品、收藏、画师、追更）
- `lib/page/hello/new/illust/new_illust_page.dart`：关注画师的新作品列表
- `lib/page/follow/follow_list.dart`：关注的画师列表
- `lib/page/watchlist/watchlist.dart`：追更列表

**收藏**
- `lib/page/user/bookmark/bookmark_page.dart`：收藏页面，展示用户收藏的插画
- `lib/page/user/bookmark/tag/user_bookmark_tag_page.dart`：收藏标签管理页面
- `lib/page/book/tag/book_tag_page.dart`：收藏标签选择页面

**搜索**
- `lib/page/search/search_page.dart`：搜索页面，展示热门标签和搜索入口
- `lib/page/search/result_page.dart`：搜索结果页面
- `lib/page/search/suggest/search_suggestion_page.dart`：搜索建议/自动完成页面
- `lib/page/saucenao/saucenao_page.dart`：以图搜图（SauceNAO）页面

**设置**
- `lib/page/hello/setting/setting_page.dart`：设置页面入口，包含账户、历史、下载、主题等入口
- `lib/page/hello/setting/setting_quality_page.dart`：画质设置页面, 偏好设置页面
- `lib/page/theme/theme_page.dart`：主题设置页面
- `lib/page/shield/shield_page.dart`：屏蔽设置页面（屏蔽标签/用户/插画）
- `lib/page/network/network_setting_page.dart`：网络设置页面
- `lib/page/hello/setting/save_format_page.dart`：保存格式设置页面

**用户/画师**
- `lib/page/user/users_page.dart`：用户主页（画师个人页面），包含作品、收藏、关注等标签
- `lib/page/user/works/works_page.dart`：用户作品列表页面
- `lib/page/painter/painter_list.dart`：画师列表组件

**插画详情**
- `lib/page/picture/illust_lighting_page.dart`：插画详情页面（主要使用）,纵向滑动
- `lib/page/picture/picture_list_page.dart`：插画列表页面（左右滑动浏览）
- `lib/page/picture/illust_row_page.dart`：插画横向滑动页面
- `lib/page/comment/comment_page.dart`：评论页面
- `lib/page/zoom/photo_zoom_page.dart`：图片缩放查看页面

**下载**
- `lib/page/task/job_page.dart`：下载任务管理页面，展示下载进度和历史
- `lib/page/directory/directory_page.dart`：保存目录设置页面

**浏览历史**
- `lib/page/history/history_page.dart`：插画浏览历史页面
- `lib/page/novel/history/novel_history_page.dart`：小说浏览历史页面

**小说模块**
- `lib/page/novel/novel_rail.dart`：小说模块导航入口
- `lib/page/novel/recom/novel_recom_page.dart`：小说推荐页面
- `lib/page/novel/rank/novel_rank_page.dart`：小说排行榜页面
- `lib/page/novel/bookmark/novel_bookmark_page.dart`：小说收藏页面
- `lib/page/novel/viewer/novel_store.dart`：小说阅读器

**登录/账户**
- `lib/page/login/login_page.dart`：登录页面
- `lib/page/Init/guide_page.dart`：初始引导页面（语言选择等）
- `lib/page/account/select/account_select_page.dart`：多账户切换页面

**其他**
- `lib/page/about/about_page.dart`：关于页面
- `lib/page/spotlight/spotlight_page.dart`：Pixivision 特辑页面
- `lib/page/soup/soup_page.dart`：Pixivision 文章详情页面
- `lib/page/series/illust_series_page.dart`：插画系列页面
- `lib/page/report/report_items_page.dart`：举报页面

**下载**
- `lib/page/download/downloaded_page.dart`：下载页面
- `lib/page/download/downloaded_author_page.dart`：下载作者页面


### 全局单例（定义于 `lib/main.dart`）
- `userSetting`：用户设置（画质、主题、网络等）
- `saveStore`：移动端保存管理
- `muteStore`：屏蔽设置（标签、用户、插画）
- `accountStore`：账户管理（多账户支持）
- `tagHistoryStore`：搜索标签历史
- `topStore`：顶部状态管理
- `bookTagStore`：收藏标签管理
- `fetcher`：网络请求调度器
- `splashStore`：启动屏状态管理
- `downloadStore`：下载任务管理（Windows/Linux）

### 下载系统架构

PixEz 使用双下载系统架构：
- **新下载器**（Windows/Linux）：功能完整的下载管理系统，使用 SQLite 持久化存储
- **旧下载器**（Android/iOS）：直接保存到系统相册/图库

#### 新下载器核心组件

**Store 层**
- `lib/store/download_store.dart`：下载管理核心（约 2000 行）
  - `DownloadTask`：下载任务模型，包含状态、进度、错误信息
  - `DownloadTaskStatus`：任务状态枚举（pending/downloading/completed/failed/paused/deleted）
  - `DownloadStore`：下载管理器，负责队列调度、并发控制（最大并发数 3）

**数据层**
- `lib/models/download_record.dart`：下载记录和数据库操作（约 2200 行）
  - `DownloadedIllust`：已下载插画记录
  - `DownloadedImage`：已下载图片记录（支持多页插画）
  - `DownloadedAuthor`：已下载作者统计
  - `PendingDownload`：待下载任务记录
  - `DownloadDatabaseProvider`：SQLite 数据库管理（版本 7）
    - 主表：downloaded_illusts、downloaded_images、pending_downloads、downloaded_authors
    - 支持自动迁移和索引优化
    - macOS 外部存储权限支持

**工具类**
- `lib/utils/ugoira_downloader.dart`：动图下载工具（约 600 行）
  - 支持多种下载策略：逐帧下载 > 高清 ZIP > 中等 ZIP
  - ZIP 自动解压和临时文件管理
  - 序列帧存储到 `ugoira/` 子目录

#### 下载页面

**任务管理**
- `lib/page/task/job_page.dart`：下载任务管理页面
  - 支持按状态筛选（全部/运行中/已完成/失败）
  - 任务操作：重试、删除、暂停、恢复
  - 实时进度显示
- `lib/page/task/pending_download_dialog.dart`：待下载任务恢复对话框

**已下载内容**
- `lib/page/download/downloaded_page.dart`：已下载插画浏览页面
  - 网格展示，支持多种排序（下载时间/作品时间/文件大小）
  - 右键菜单：查看详情、打开文件夹、更新信息、删除
  - 统计信息显示
- `lib/page/download/downloaded_author_page.dart`：已下载作者列表页面
- `lib/component/downloaded_author_card.dart`：作者卡片组件

**设置相关**
- `lib/page/hello/setting/save_format_page.dart`：文件名格式设置
  - 支持变量：`{illust_id}`、`{title}`、`{user_id}`、`{user_name}`、`{part}`
  - 默认格式：`{illust_id}_p{part}`
  - 支持清除旧格式文件
- `lib/page/hello/setting/setting_quality_page.dart`：画质设置页面
- `lib/page/directory/directory_page.dart`：下载路径选择页面

**其他组件**
- `lib/page/download/optimize_json_dialog.dart`：数据库优化对话框
- `lib/page/download/import_dialog.dart`：导入已有下载记录
- `lib/page/download/update_illust_info_dialog.dart`：更新插画信息
- `lib/page/picture/save_effect_trailing.dart`：保存动画效果组件

#### 文件存储结构

```
basePath/
├── download/                        # 下载目录
│   └── [userName][userId]/          # 作者目录
│       └── [illustId]title/         # 作品简介
│           ├── xxx_p0.jpg           # 图片文件
│           ├── xxx_p1.jpg
│           └── ugoira/              # 动图序列帧
│               ├── 000000.jpg
│               └── 000001.jpg
├── download.db                      # SQLite 数据库
├── covers/                          # 封面缓存
└── ugoira/                          # 动图临时文件
```

#### 旧下载器组件

- `lib/store/save_store.dart`：移动端保存管理（约 400 行）
  - 状态：JOIN/SUCCESS/ALREADY/INQUEUE
  - 支持单图和批量保存
  - 文件名格式化

### 其他重要 Store

**账户管理**
- `lib/store/account_store.dart`：多账户管理
  - 支持账户添加、删除、切换
  - 认证状态持久化

**用户设置**
- `lib/store/user_setting.dart`：用户偏好设置
  - 画质设置（原图/大图/预览图）
  - 主题设置（亮色/暗色/跟随系统）
  - 网络设置（代理、DNS）
  - 安全设置（R18、屏蔽）

**屏蔽管理**
- `lib/store/mute_store.dart`：屏蔽功能
  - 屏蔽标签
  - 屏蔽用户
  - 屏蔽插画

**标签管理**
- `lib/store/tag_history_store.dart`：搜索标签历史
- `lib/store/book_tag_store.dart`：收藏标签管理

**界面状态**
- `lib/store/fullscreen_store.dart`：全屏状态管理
- `lib/store/top_store.dart`：顶部状态栏管理

### 网络层
- 使用 `dio` 配合 `rhttp` 实现 HTTP 请求，支持 SNI 绕过（用于国内直连）
- `Hoster` 类管理不同主机的 DNS 解析
- `RefreshTokenInterceptor` 处理令牌刷新

### 平台特定代码
- **Android**：原生 Kotlin 代码，使用 DocumentFile 实现 SAF、GIF 编码
- **Windows/Linux**：使用 `sqflite_common_ffi`、`window_manager`
- 通过 `SingleInstancePlugin` 处理单实例

#### Android 原生功能
- SAF (Storage Access Framework) 支持
- GIF 动图编码（原生实现）
- 文件权限管理

#### Windows 特有功能
- MSIX 打包（`msix:create` 命令）
- Mica/Tabbed 窗口特效（通过 `flutter_acrylic`）
- 协议激活：`pixiv://`、`pixez://`
- URI 处理：`i.pximg.net`、`pixiv.me`、`pixivvision.net`

### 资源文件

- `assets/images/`：图片资源
- `assets/json/host.json`：主机 DNS 配置
- `assets/emojis/`：表情资源
- `assets/executables/`：可执行文件
- `assets/fonts/iconfont.ttf`：图标字体

### 主要依赖包

**核心框架**
- `mobx` / `flutter_mobx`：状态管理
- `riverpod` / `hooks_riverpod`：轻量级状态管理
- `freezed`：不可变数据类

**网络相关**
- `dio`：HTTP 客户端
- `rhttp`：桌面平台网络请求
- `dio_cache_interceptor`：请求缓存
- `flutter_cache_manager_dio`：图片缓存

**UI 组件**
- `bot_toast`：Toast 提示
- `waterfall_flow`：瀑布流布局
- `easy_refresh`：下拉刷新
- `photo_view`：图片查看
- `cached_network_image`：网络图片

**桌面平台**
- `flutter_acrylic`：窗口特效（Windows）
- `window_manager`：窗口管理
- `file_picker`：文件选择
- `sqflite` / `sqlite3`：数据库

**多媒体**
- `image_picker`：图片选择
- `archive`：ZIP 解压（动图）
- `image_size_getter`：获取图片尺寸

**其他**
- `share_plus`：分享
- `url_launcher`：打开链接
- `permission_handler`：权限管理
- `in_app_purchase`：应用内购买
- `receive_sharing_intent`：接收分享

## 国际化

使用 `intl` 包，ARB 文件位于 `lib/l10n/`。生成文件位于 `lib/generated/` 和 `lib/src/generated/i18n/`。

支持的语言：en-US、es-ES、ja-JP、ko-KR、ru-RU、tr-TR、zh-CN、zh-TW

## 代码生成

项目使用多种代码生成器，修改相关文件后需要运行：

```bash
dart run build_runner build --delete-conflicting-outputs
```

**生成内容：**
- MobX Store：`*.g.dart` 文件（`mobx_codegen`）
- JSON 序列化：模型类的 `.g.dart` 文件（`json_serializable`）
- Riverpod Provider：`.riverpod.dart` 文件（`riverpod_generator`）
- Freezed 类：`.freezed.dart` 和 `.g.dart` 文件（`freezed`）

## 日志输出规范

项目统一使用 `Log` 类进行日志输出，定义于 `lib/custom/log.dart`。

### 日志级别
- `Log.d()` - Debug 级别（开发调试信息）
- `Log.i()` - Info 级别（一般信息）
- `Log.w()` - Warning 级别（警告信息）
- `Log.e()` - Error 级别（错误信息）

### 使用规范
1. **必须使用 Log 类**：禁止使用 `print()`、`debugPrint()` 或 `developer.log()`
2. **推荐使用 Lambda 表达式**：建议使用 `Log.d(() => "message")` 形式，避免不必要的字符串拼接
   ```dart
   // 推荐
   Log.d(() => "用户ID: $userId, 操作: $action");

   // 也可以
   Log.d("用户ID: $userId, 操作: $action");
   ```
3. **错误日志**：记录异常时使用 error 和 stackTrace 参数
   ```dart
   try {
     // ...
   } catch (e, stackTrace) {
     Log.e("操作失败", error: e, stackTrace: stackTrace);
   }
   ```

### Log 类特性
- 基于 `logger` 包实现
- 支持彩色输出（非 iOS 平台）
- 自动过滤调用栈中的 log.dart 文件
- 支持内存缓冲（最近 500 条日志）
- Release 模式下只输出 info 及以上级别

## 开发工具

项目包含开发调试工具：
- `flutter_mana`：开发工具包
- `flutter_mana_kits`：开发工具套件
- `custom_lint`：自定义 lint 规则
- `riverpod_lint`：Riverpod 特定 lint

## 测试

```bash
flutter test
```

测试文件位于 `test/` 目录。

## 常见开发任务

### 添加新的 MobX Store
1. 创建 Store 类
2. 添加 `@store` 注解
3. 运行 `dart run build_runner build`
4. 在 `lib/main.dart` 中注册为全局单例

### 添加新的数据模型
1. 创建模型类，使用 `@JsonSerializable()` 注解
2. 运行代码生成
3. 使用生成的 `.g.dart` 文件中的序列化方法

### 修改下载功能
- **新下载器**（桌面）：修改 `lib/store/download_store.dart` 和 `lib/models/download_record.dart`
- **旧下载器**（移动）：修改 `lib/store/save_store.dart`
- **动图下载**：修改 `lib/utils/ugoira_downloader.dart`

### 添加新页面
1. 在 `lib/page/` 相应目录创建页面文件
2. 如需 Fluent UI 变体，在 `lib/fluent/` 创建对应文件
3. 添加国际化字符串到 `lib/l10n/`

### 修改主题
- 主题配置：`lib/store/theme_setting.dart`
- 主题页面：`lib/page/theme/theme_page.dart`
