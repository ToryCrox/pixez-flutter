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
