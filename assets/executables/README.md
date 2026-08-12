# libwebp 工具说明

图片整理页使用 libwebp 1.4.0 的 `cwebp` 转换静态图片。

- `cwebp.exe`：Windows x64，SHA-256 `499c4e54474851137de79636062490f7ea031c8245cdac98cdd03499c27f1d1c`
- `cwebp-macos`：由官方 macOS arm64 与 x86_64 二进制合成的 universal 可执行文件，SHA-256 `98e773268c6ae6a0946334424d2d3b946c7cabb4f86801388f1cae590e1e343a`

下载来源：[WebP 官方二进制目录](https://storage.googleapis.com/downloads.webmproject.org/releases/webp/index.html)。

源归档 SHA-256：`61f873ec69e3be1b99535634340d5bde750b2e4447caa1db9f61be3fd49ab1e5`。
许可文本见同目录 `libwebp-COPYING` 与 `libwebp-PATENTS`。

## 漫画 OCR helper

`manga-ocr-helper` 是 PixEz 源码内构建的本地 Rust 子进程，使用 JSON Lines 协议调用 ONNX Runtime。helper 本身不包含 CTD 或 Baberu 权重；模型依据 `assets/manga_ocr/model_manifest.json` 首次使用时下载。

- `manga-ocr-helper-macos-arm64`：Apple Silicon arm64，签名前 SHA-256 `deed71845a2a5baca44361ed894c369ca8c11986ccb409995493724f3b90b336`（应用包内副本签名后哈希会变化）
- 构建来源：`native/manga_ocr_helper/`，命令 `./tool/build_manga_ocr_helper.sh`
- Rust/ONNX Runtime：Rust 1.92.0，`ort 2.0.0-rc.12`；当前产物静态包含 ONNX Runtime，不依赖外置 dylib
- 签名：Flutter embed 后由 `macos/Runner/sign_manga_ocr_helper.sh` 使用 Xcode 的 `EXPANDED_CODE_SIGN_IDENTITY` 签 helper 并重新签 `App.framework`，随后由 Xcode 签外层 app
- helper 许可证：GPL-3.0-or-later（与 PixEz 项目许可证一致）；第三方 Rust crate 许可证由发布构建的依赖审计清单管理

Windows x64 使用 `tool/build_manga_ocr_helper_windows.ps1` 构建，目标文件名为 `manga-ocr-helper-windows-x64.exe`。Windows CI 产出并签名后，必须在此补充 SHA-256、Rust/ORT 版本和签名证书来源，不应复用 macOS 哈希。

模型许可证和上游来源不写入此二进制清单，以 manifest 为准：Baberu OCR 是 Apache-2.0；CTD 代码为 GPL-3.0，默认权重再分发前需要独立完成来源与许可复核。
