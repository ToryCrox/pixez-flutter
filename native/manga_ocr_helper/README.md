# manga-ocr-helper

桌面端漫画 OCR 的本地 Rust 子进程。它通过 stdin/stdout 的 JSON Lines 协议接收
`capabilities`、`loadModels`、`analyzePage`、`cancel` 和 `shutdown` 请求，图片路径只在
本机读取。

```bash
cargo build --manifest-path native/manga_ocr_helper/Cargo.toml --release
```

构建和打包脚本见 `tool/build_manga_ocr_helper.sh`。helper 本身不包含模型权重；模型由
Flutter 端根据 `assets/manga_ocr/model_manifest.json` 首次使用时下载并校验。
