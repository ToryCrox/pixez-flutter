# 下载系统重构计划

## 需求分析

### 1. 数据库记录下载
- 包含Illusts基本信息、相对目录、文件名、后缀、文件大小
- 目录结构: `[{user_name}][{user_id}]/[{illust_id}]{title}/`
- 文件名: `{illust_id}_p{part}`
- 数据库放在下载目录

### 2. 已下载目录页面
- Windows侧边栏可打开
- 按作者、标签筛选
- 以作品维度展示

### 3. 下载功能优化
- 不使用Isolate
- 使用pixivCacheManager下载
- Windows平台直接使用io库
- 检查已存在文件

### 4. 详情页优先显示本地图片
- 检查多种后缀名
- 添加下载/删除按钮

### 5. IllustCard显示下载状态

---

## 技术分析

### 现有系统分析

**Isolate问题分析：**
- 当前使用Isolate处理下载，大量数据在主Isolate和子Isolate之间传递
- Isolate之间传递复杂对象需要序列化/反序列化，对于大量任务确实可能造成性能问题
- Flutter的Isolate不共享内存，传递大对象可能导致OOM
- **建议：** 移除Isolate，在主线程使用异步下载，配合队列控制并发数

**pixivCacheManager分析：**
- 已封装好Dio + rhttp的网络请求
- 支持缓存和断点续传
- 下载完成后文件在缓存目录，需要移动到下载目录

### 目录结构设计

```
下载目录/
├── download.db                           # SQLite数据库
├── [user_name][user_id]/                 # 作者目录
│   └── [illust_id]title/                 # 作品目录
│       ├── illust_id_p0.jpg              # 图片文件
│       ├── illust_id_p1.png
│       └── ...
```

### 数据库设计

**表: downloaded_illusts**
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER | 主键 |
| illust_id | INTEGER | 插画ID |
| user_id | INTEGER | 用户ID |
| user_name | TEXT | 用户名 |
| title | TEXT | 作品标题 |
| type | TEXT | 类型 (illust/manga/ugoira) |
| caption | TEXT | 说明 |
| create_date | TEXT | 创建日期 |
| page_count | INTEGER | 页数 |
| width | INTEGER | 宽度 |
| height | INTEGER | 高度 |
| sanity_level | INTEGER | 安全等级 |
| x_restrict | INTEGER | 限制等级 |
| total_view | INTEGER | 浏览数 |
| total_bookmarks | INTEGER | 收藏数 |
| tags | TEXT | 标签JSON |
| relative_path | TEXT | 相对目录路径 |
| download_time | INTEGER | 下载时间戳 |
| illust_json | TEXT | 完整Illusts JSON |

**表: downloaded_images**
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER | 主键 |
| illust_id | INTEGER | 插画ID |
| part | INTEGER | 页码 (0-based) |
| file_name | TEXT | 文件名(不含后缀) |
| extension | TEXT | 后缀 (.jpg/.png/.webp) |
| file_size | INTEGER | 文件大小(字节) |
| original_url | TEXT | 原始URL |
| relative_path | TEXT | 相对路径 |

---

## 实现步骤

### 第一阶段：数据库层

1. **创建 `lib/models/download_record.dart`**
   - DownloadedIllust 模型类
   - DownloadedImage 模型类
   - DownloadDatabase Provider类

2. **创建 `lib/store/download_store.dart`**
   - MobX Store管理下载状态
   - 提供查询、添加、删除、更新接口
   - 维护正在下载的任务队列

### 第二阶段：新下载器

3. **创建 `lib/er/downloader.dart`**
   - 新的下载器类，不使用Isolate
   - 使用pixivCacheManager下载
   - 队列控制并发数
   - 下载完成后移动文件到目标目录
   - 检查已存在文件逻辑

4. **修改 `lib/store/save_store.dart`**
   - 使用新的下载器
   - 保留原有的stream通知机制

### 第三阶段：已下载页面

5. **创建 `lib/page/downloaded/downloaded_page.dart`**
   - 已下载作品列表页面
   - 网格展示作品封面
   - 点击进入详情页

6. **创建 `lib/page/downloaded/downloaded_filter.dart`**
   - 作者筛选
   - 标签筛选
   - 搜索功能

7. **修改 `lib/page/hello/hello_page.dart`**
   - 在NavigationRail添加"已下载"入口

### 第四阶段：详情页优化

8. **创建 `lib/component/local_or_cached_image.dart`**
   - 优先加载本地已下载图片
   - 回退到PixivImage加载网络图片
   - 自动尝试多种后缀名

9. **修改 `lib/page/picture/illust_lighting_page.dart`**
   - 使用LocalOrCachedImage替换PixivImage
   - 添加下载状态按钮
   - 下载/删除功能

10. **修改 `lib/page/zoom/photo_zoom_page.dart`**
    - 使用LocalOrCachedImage

### 第五阶段：IllustCard状态显示

11. **修改 `lib/component/illust_card.dart`**
    - 添加下载状态图标
    - 监听下载进度

### 第六阶段：迁移和清理

12. **保持兼容**
    - 保留旧的job_page.dart用于显示下载进度
    - 逐步迁移到新系统

---

## 关键代码设计

### DownloadStore 核心接口

```dart
abstract class DownloadStore {
  // 查询
  Future<bool> isIllustDownloaded(int illustId);
  Future<DownloadedIllust?> getDownloadedIllust(int illustId);
  Future<String?> getLocalImagePath(int illustId, int part);
  Future<List<DownloadedIllust>> queryByUser(int userId);
  Future<List<DownloadedIllust>> queryByTag(String tag);

  // 下载
  Future<void> downloadIllust(Illusts illust, {int? part});
  Future<void> downloadAllPages(Illusts illust);

  // 删除
  Future<void> deleteIllust(int illustId);

  // 状态
  Stream<DownloadProgress> get progressStream;
  bool isDownloading(int illustId);
}
```

### Downloader 核心逻辑

```dart
class Downloader {
  final int maxConcurrent = 3;
  final Queue<DownloadTask> _queue = Queue();
  final Set<String> _running = {};

  Future<void> download(DownloadTask task) async {
    // 1. 检查目标文件是否已存在
    final targetPath = _buildTargetPath(task);
    if (await File(targetPath).exists()) {
      // 文件已存在，直接记录到数据库
      await _recordExisting(task, targetPath);
      return;
    }

    // 2. 尝试从缓存获取
    final cached = await pixivCacheManager.getFileFromCache(task.url);
    if (cached != null) {
      // 从缓存复制到目标目录
      await _copyToTarget(cached.file, targetPath);
      await _recordDownload(task, targetPath);
      return;
    }

    // 3. 加入下载队列
    _enqueue(task);
  }

  Future<void> _processQueue() async {
    while (_queue.isNotEmpty && _running.length < maxConcurrent) {
      final task = _queue.removeFirst();
      _running.add(task.url);

      try {
        // 使用pixivCacheManager下载
        final file = await pixivCacheManager.downloadFile(
          task.url,
          headers: Hoster.header(url: task.url),
        );

        // 移动到目标目录
        final targetPath = _buildTargetPath(task);
        await _copyToTarget(file.file, targetPath);
        await _recordDownload(task, targetPath);

        _notifySuccess(task);
      } catch (e) {
        _notifyError(task, e);
      } finally {
        _running.remove(task.url);
        _processQueue(); // 继续处理队列
      }
    }
  }
}
```

### 本地图片加载

```dart
class LocalOrCachedImage extends StatelessWidget {
  final int illustId;
  final int part;
  final String networkUrl;

  Future<String?> _findLocalPath() async {
    // 从数据库查询
    final path = await downloadStore.getLocalImagePath(illustId, part);
    if (path != null && await File(path).exists()) {
      return path;
    }

    // 尝试不同后缀
    final basePath = _getBasePath();
    for (final ext in ['.jpg', '.png', '.webp', '.gif']) {
      final testPath = '$basePath$ext';
      if (await File(testPath).exists()) {
        // 更新数据库中的后缀名
        await downloadStore.updateExtension(illustId, part, ext);
        return testPath;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _findLocalPath(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.file(File(snapshot.data!));
        }
        return PixivImage(networkUrl);
      },
    );
  }
}
```

---

## 文件列表

### 新建文件
1. `lib/models/download_record.dart` - 数据模型和数据库Provider
2. `lib/store/download_store.dart` - MobX Store
3. `lib/er/downloader.dart` - 新下载器
4. `lib/page/downloaded/downloaded_page.dart` - 已下载页面
5. `lib/page/downloaded/downloaded_filter.dart` - 筛选组件
6. `lib/component/local_or_cached_image.dart` - 本地/缓存图片组件

### 修改文件
1. `lib/main.dart` - 初始化downloadStore
2. `lib/store/save_store.dart` - 使用新下载器
3. `lib/page/hello/hello_page.dart` - 添加侧边栏入口
4. `lib/page/picture/illust_lighting_page.dart` - 本地图片显示+下载按钮
5. `lib/page/zoom/photo_zoom_page.dart` - 本地图片显示
6. `lib/component/illust_card.dart` - 下载状态显示

---

## 注意事项

1. **文件名合法化**: 使用 `toLegal()` 方法处理目录名和文件名
2. **并发控制**: maxRunningTask 从 userSetting 获取
3. **错误处理**: 网络错误、磁盘空间不足等情况的处理
4. **数据库迁移**: 考虑未来版本升级时的数据库迁移
5. **Windows路径**: 注意Windows平台的路径分隔符和长路径问题
6. **内存管理**: 大图片加载时的内存控制
