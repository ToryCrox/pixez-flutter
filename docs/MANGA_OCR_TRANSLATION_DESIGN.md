# 桌面端漫画整页 OCR 与 AI 翻译设计

## 1. 目标、非目标与用户流程

本功能面向 macOS 与 Windows 桌面端，为当前正在查看的图片页提供“一键自动检测、OCR、翻译”。用户不需要手动框选：入口位于纵向详情、横向详情和全屏图片查看器，点击后右侧打开 420px 面板，图片上显示检测框，面板与检测框可以互相定位。

首版目标：

- 自动检测当前页全部候选文字，包括对白、标题、拟声词和低置信度区域。
- 日语、英语和中文使用本地 OCR；图片和裁剪不发送给翻译服务。
- OCR 完成后，将带稳定分段 ID 的纯文字批量交给已有 AI 翻译服务。
- AI 未配置、断网或返回不完整时仍显示 OCR 原文；漏掉的翻译分段单独补译。
- 当前页处理完成后写入独立 SQLite 缓存。切页只加载对应缓存，不自动处理下一页。
- 检测器、识别器、预处理器、运行时和模型版本均可替换。

首版不实现擦字、图像修复、译文回填、整部作品批处理、手动框选和移动端支持。动图不属于首版 OCR 输入。

用户流程：

1. 在横屏详情页点击左下角的小型翻译按钮，只打开覆盖作品详情栏的 OCR 面板，不立即调用 OCR 或 AI。
2. 用户在面板点击“开始识别并翻译”；首次使用时按 manifest 下载 CTD 和 Baberu ONNX 文件，支持断点续传、SHA-256 校验和原子安装。
3. helper 准备工作图或长图分块，自动检测并识别全部文字块。
4. 页面立即显示 OCR 原文；已配置 AI 时继续显示整页翻译。
5. 启动后若“随页面自动识别翻译”开启，下一页图片一旦加载完成并进入可见区域，就提前加入最新页队列，不必等它完全成为当前页；关闭面板即停止自动跟随。
6. 用户可点击框或条目、复制文本、重新翻译、强制重新 OCR、取消或关闭面板。

### 横屏连续阅读交互

横屏详情页不通过 `Navigator` 打开新的图片页。左下角控制顺序为“页数、OCR/翻译、全屏”，OCR 按钮只切换右侧面板。右侧以与评论面板相同的 `AnimatedPositioned` 覆盖作品详情，评论和 OCR 使用互斥的 sidebar overlay 状态；返回键先关闭覆盖面板。全屏会隐藏详情栏，因此从全屏点击 OCR 时先退出全屏并恢复右侧栏。

连续阅读使用单任务、最新页优先的协调器。页数指示器仍由可见高度最大的图片决定，避免下一页刚出现时过早跳页；OCR 调度则更积极：只要下一页进入视口就立即排队，路径解析器通过同一个 Pixiv 缓存等待本地文件可读，随后直接开始 OCR 和翻译，无需等待它成为当前页或完成 Flutter 绘制。helper 同时只执行一页，等待槽只保留滚动方向上的最新可见页，因此快速经过第 4、5、6 页时不会积压全部页面。已处理页面保存在页面会话和 SQLite 中，回看时直接显示；自动翻页不会设置 `forceOcr` 或 `forceTranslation`。

OCR 不修改 `PixivImage`，也不为 `CachedNetworkImage` 设置自定义 `imageBuilder`。只有用户点击面板内“开始识别并翻译”后，可见页才会交给路径解析器；未启用或关闭面板时不会创建额外图片请求。

## 2. 模型选择依据

### BallonsTranslator 参考

[BallonsTranslator](https://github.com/dmMaze/BallonsTranslator) 的漫画流水线验证了“文本检测 + 独立 OCR + 翻译 + 修复/排版”的工程拆分。它默认生态使用 [comic-text-detector](https://github.com/dmMaze/comic-text-detector)，并支持 Manga OCR、PaddleOCR-VL-for-Manga、YSG YOLO 等组件。本项目不需要擦字和回填，因此仅复用前两段思路，不引入编辑器、修复模型或完整 Python 环境。

社区反馈显示 CTD 对常规日漫对白较实用，但对复杂拟声词、艺术字和极小文字仍可能漏检。因此本项目不会静默丢弃低分区域，并让检测器 ID 可更换。CTD 代码是 GPL-3.0；当前默认权重来自 manga-image-translator `beta-0.3`，manifest 固定内容哈希。发布方仍需单独确认权重训练数据与再分发边界，所以应用采用首次远端下载，不把权重放入安装包。

### 默认识别器：Baberu OCR int4

[Baberu OCR](https://huggingface.co/genshiai-daichi/baberu-ocr) 是约 115M 参数的漫画气泡 OCR，支持日语、英语和中文。`vision_int4.onnx + decoder_*_int8.onnx` 总计约 121MB，Apache-2.0，适合桌面 CPU 本地推理。它要求输入单个气泡/文字块，因此与 CTD 组合。

helper 完整实现其三图推理：DINOv2 图像预处理、vision encoder、decoder prefill、带 12 组 KV cache 的 decoder step、重复惩罚和连续字符限制。裁剪保持宽高比、留白到正方形后缩放到 224px；这与上游直接拉伸的示例略有差别，但能避免竖排文字变形，需要用项目 benchmark 持续比较 CER。

### 备选方案

- [manga-ocr](https://github.com/kha-white/manga-ocr)：成熟、日文漫画评价稳定，但模型约 400MB 且主要面向日语。适合作为 `manga_ocr_onnx` 备选，不作为日英中混排默认项。
- PaddleOCR-VL-for-Manga：对复杂布局与历史印刷体有潜力，但约 1B 参数，冷启动、内存和包体成本明显更高；其公开评测还应注意训练/测试来源重叠。预留 `paddleocr_vl_manga` ID。
- BallonsTranslator 的 YSG YOLO：适合希望过滤或专门检测拟声词的配置，但目标取舍和当前“显示全部候选”不同。预留为检测器插件。
- 系统 Vision、Tesseract、通用 PaddleOCR：部署较小，但漫画竖排、描边、气泡和拟声词通常不如漫画专用组合稳定，可作为低资源或系统原生备选。

## 3. 可插拔边界

稳定类型位于 `lib/manga_ocr/`：

- `MangaImagePreprocessor`：只负责缩放、分块、重叠和坐标规划。
- `MangaTextDetector`：声明稳定 ID、版本和 helper 配置。
- `MangaTextRecognizer`：声明稳定 ID、版本和 helper 配置。
- `MangaOcrPipeline`：负责文件指纹、模型安装、helper、排序、OCR 缓存和翻译。
- `MangaOcrEngineRegistry`：按 ID 注册 detector/recognizer。
- `MangaPageOcrResult` / `MangaTextBlock`：页面、缓存和翻译共享的统一结果。

首版注册：

| 类型 | ID | 版本 |
|---|---|---|
| 预处理器 | `adaptive_page_preprocessor` | `1` |
| 检测器 | `ctd_onnx` | `beta-0.3` |
| 识别器 | `baberu_ocr_int4` | `step295000-int4-int8` |

页面只持有 `MangaOcrController` 和统一结果，不导入 CTD 或 Baberu 类。设置保存 detector/recognizer ID；注册新引擎后会自动出现在选择器中。

## 4. JSON Lines helper 协议

Flutter 启动一个持久化 `manga-ocr-helper` 子进程，每行一个 UTF-8 JSON。所有消息都包含 `protocolVersion` 和 `requestId`。当前协议版本为 1。

请求示例：

```json
{"protocolVersion":1,"requestId":"dart-3","method":"analyzePage","payload":{"imagePath":"/path/page.jpg","imageSha256":"…","pageIndex":0,"preprocessor":{"id":"adaptive_page_preprocessor","version":"1","maxWorkingEdge":2048,"longPageAspectRatio":3.0,"tileOverlap":0.1,"cropPadding":0.12,"lowConfidenceThreshold":0.45,"duplicateIouThreshold":0.55}}}
```

命令：

- `capabilities`：返回协议、命令和支持的引擎 ID。
- `loadModels`：传入模型根目录和选中的 detector/recognizer 配置；模型只加载一次并复用。
- `analyzePage`：完成准备、检测、OCR、一次高清重试并返回统一 blocks。
- `cancel`：设置当前任务取消标志；推理循环在分块与 token 生成边界检查。
- `shutdown`：取消任务并退出。

进度消息的 `type` 为 `progress`，stage 为 `preparing`、`tiling`、`detecting` 或 `recognizing`。最终响应使用 `ok/result` 或 `ok:false/error`。Dart 为请求设置超时；helper 崩溃、超时或取消失败时会终止进程，下一次请求重新创建。

## 5. 图片处理与内存规则

### 普通页面

1. 优先使用 `IllustStore` 当前显示页的本地文件；没有时使用现有 Pixiv 缓存下载当前画质 URL。
2. 流式读取文件计算 SHA-256，不一次性把文件读入 Dart 内存。
3. helper 解码后生成最长边不超过 2048px 的工作图。
4. CTD 使用右侧/底部留黑的 1024px letterbox 输入，输出框映射为整页 0–1 坐标。
5. 每个框增加 12% 上下文，从局部裁剪送入 Baberu。

### 超大页面与长条漫

宽高比大于 3:1 时，不生成一张被严重压缩的整页图。沿长轴生成最长边不超过 2048px 的块，步长为块长的 90%，即 10% 重叠。helper 一次只物化一个工作分块，检测后立即释放；不会同时保留全部分块或全部 OCR 裁剪。

每个 tile 内的框先映射到 tile 归一化坐标，再按 tile 在整页的位置反算。跨块结果要求方向相同，并以默认 IoU 0.55 合并；保留较高 OCR 置信度文本与较高检测置信度。

### 裁剪、补边和高清重试

- 同一 CTD block 作为一个气泡/文字区送入识别器；后续 detector 可以在 adapter 中合并相邻行。
- 裁剪四周默认增加框宽/高的 12%，并限制在页面范围。
- 保持宽高比，居中放入白色正方形，再缩放到 Baberu 224×224；不拉伸文字。
- 原文为空或 OCR 置信度低于 0.45 时只重试一次，并扩大少量上下文。仍失败的框保留，标记“识别失败/低置信度”。
- 当前跨平台 Rust 解码器会保留一份源页像素，再顺序创建单个工作 tile 和单个 OCR crop；不会保留“源页 + 全部 tile + 全部高清 crop”。benchmark 必须记录峰值。若超大 PNG 的源页解码峰值仍不可接受，下一步在 `MangaImagePreprocessor` 后增加 macOS ImageIO / Windows WIC 区域解码 adapter，不改变协议和页面。

这种方式回答了“大图是否应该先缩小”的问题：检测一定先用缩小工作图；只有小框或低置信度区域才回看局部高清内容，而不是整页都用原分辨率推理。

## 6. 方向、排序与显示

- 日文竖排：列从右到左，列内从上到下。
- 英文/横排：从上到下，同行从左到右。
- 自动模式以竖排 block 是否超过半数选择 RTL/LTR；设置可强制日漫 RTL 或 LTR。
- 低置信度、拟声词和标题不自动隐藏。条目展示原文、译文、语言、方向、检测置信度、OCR 置信度和高清重试标记。
- 桌面鼠标悬浮检测框时优先显示译文；尚无译文时回退显示 OCR 原文，提示延迟为 150ms。
- 坐标永久保存为 0–1，UI 根据实际 contain 区域换算。当前覆盖框对应图片适应窗口时的位置；未来若需要在 PhotoView 任意缩放/旋转时保持贴合，应把 PhotoView transformation matrix 注入 overlay，结果模型无需改变。

## 7. 翻译与隐私边界

新增 AI 场景 `manga_page_translation`，目标语言使用 `Localizations.localeOf(context).toLanguageTag()`。每个 block ID 由图片 SHA-256 与六位小数归一化坐标生成并保持稳定，批量文本使用 `⟪PXEZ_MANGA_BLOCK_ID⟫` 标记。AI 返回后按标记恢复；缺失块使用 block 资源键单独补译。

隐私边界：

- helper、工作图、OCR crop、模型与 OCR SQLite 全部在本机。
- AI client 只收到识别后的字符串、稳定分段标记和目标语言。
- 不向 AI 发送图片 URL、本地路径、图片二进制、坐标或作者账户信息。
- 未配置 AI 时 pipeline 捕获配置错误并正常返回 OCR 原文。

译文沿用 `AiResultCache`；OCR 数据使用 `manga_ocr_cache.db`，避免两类生命周期互相影响。

## 8. 模型 manifest、下载与升级

`assets/manga_ocr/model_manifest.json` 为版本 1，记录：

- engine ID、模型版本和 ONNX 架构；
- 每个文件的下载 URL、大小和 SHA-256；
- 许可证与上游项目 URL。

文件下载到应用支持目录 `manga_ocr/models/<engineId>/`。下载过程使用 `<file>.part`，已有部分通过 HTTP Range 续传；完成后校验长度与 SHA-256，校验成功才 rename 为正式文件。manifest、图片、预处理版本、引擎 ID 或模型版本变化都会生成新缓存键，不会错误复用旧 OCR。

设置页支持下载/修复、重新校验、删除和查看占用。默认只安装 `ctd_onnx` 和 `baberu_ocr_int4`。删除模型不删除 OCR 结果；再次使用相同版本仍可读缓存。

## 9. macOS 构建、沙盒与签名

helper crate 在 `native/manga_ocr_helper/`，当前使用 Rust 2024、`ort 2.0.0-rc.12` 与静态包含的 ONNX Runtime。构建：

```bash
./tool/build_manga_ocr_helper.sh
```

脚本构建 `aarch64-apple-darwin` release，输出 `assets/executables/manga-ocr-helper-macos-arm64`。当前二进制为 arm64，SHA-256 记录在 `assets/executables/README.md`。如果依赖版本导致动态 ONNX Runtime，脚本也会复制 dylib 并添加 `@executable_path` rpath。

Flutter embed 后，Xcode build phase 调用 `macos/Runner/sign_manga_ocr_helper.sh`，先签 dylib 和 helper，再重新签因资源变化而失效的 `App.framework`，最后由 Xcode 签整个 app。helper 位于 App.framework 的 flutter_assets；模型位于 Application Support 沙盒容器。现有 entitlement 已允许网络 client 进行模型/Pixiv 下载，OCR 不需要额外图片库权限，因为输入是应用已能访问的缓存或用户授权文件。

## 10. Windows 接入

在 VS 2022 Developer PowerShell 中执行：

```powershell
./tool/build_manga_ocr_helper_windows.ps1
```

输出名固定为 `assets/executables/manga-ocr-helper-windows-x64.exe`，协议与 Dart 路径解析不变。若 ONNX Runtime 是 DLL，脚本把 DLL 放在同一目录。发布前需要在 Windows x64 运行与 macOS 相同的 helper 契约、合成图片、模型下载/校验、切页/取消和 benchmark 集合，并把二进制 SHA-256 更新到 executable README。当前仓库已完成源码与构建脚本接入，Windows 二进制仍应由 Windows CI 产出和签名。

## 11. 缓存键与升级规则

OCR 缓存键是以下 canonical JSON 的 SHA-256：图片内容 SHA-256、页码、预处理器 ID/版本、detector ID/版本、recognizer ID/版本和全部预处理参数。缓存结果包含原图宽高、归一化框、原文、语言、方向、置信度、顺序、重试标记和模型版本，不缓存工作图或 crop。

坐标、检测和 OCR 的 schema 变化时提升 preprocessor/engine version；数据库 schema 变化时提升 SQLite version 并写迁移。旧行可保留到 LRU 清理，不应原地改写成新模型结果。

## 12. 测试与 benchmark

Flutter 单测覆盖缩放、分块、重叠、坐标映射、12% 补边、IoU 合并、缓存键、SQLite 往返、RTL/LTR 排序和翻译标记恢复。Rust helper 通过 `cargo check`；契约测试覆盖 `capabilities`、`shutdown`、超时、崩溃和异常输出。带模型 CI 数据集仍需持续覆盖 load、空白页、无文字页和执行中的取消。

合成/授权测试集至少包括日文竖排与横排、英文对白、日英混排、黑底白字、小字号、低分辨率、超高分辨率、长条漫、跨 tile 文字与重复框。测试图片和标注不能直接复制受版权保护的漫画页进仓库。

benchmark 工具：

```bash
dart tool/manga_ocr_benchmark.dart \
  --helper assets/executables/manga-ocr-helper-macos-arm64 \
  --models "$APPLICATION_SUPPORT/manga_ocr/models" \
  --dataset /path/to/annotations.json
```

标注格式：

```json
{
  "pages": [
    {
      "image": "images/page-001.png",
      "blocks": [
        {
          "bounds": {"left": 0.1, "top": 0.2, "right": 0.4, "bottom": 0.35},
          "text": "こんにちは"
        }
      ]
    }
  ]
}
```

工具以 IoU≥0.5 匹配标注，输出 detection recall、Unicode 字符 CER、逐页/总耗时、高清重试次数和 helper 峰值内存。冷启动需每次重启 helper；热启动在同一进程连续跑页面。首次下载、坏哈希、在线图片、本地图片、断网缓存、AI 未配置、切页与取消分别作为端到端用例。

## 13. 替换模型步骤

1. 为新 detector 或 recognizer 实现稳定接口，选择不可变 ID，并在 `MangaOcrEngineRegistry` 注册。
2. 在 manifest 增加版本、文件、大小、SHA-256、许可证和上游；不要覆盖旧版本内容。
3. 在 Rust helper 增加 capability、模型加载和 adapter；保持统一 block JSON。
4. 用相同数据集比较 recall、CER、耗时、重试和峰值内存。
5. 将新 ID 设为默认前先完成 macOS/Windows 冷热启动测试；已有页面、翻译和缓存代码无需修改。

预留 ID 为 `manga_ocr_onnx`、`paddleocr_vl_manga` 及 YSG 检测器。若未来运行时从 ONNX Runtime 换成 CoreML、DirectML 或其他子进程，只新增 `MangaOcrRuntime` 实现，不改变页面与结果 schema。
