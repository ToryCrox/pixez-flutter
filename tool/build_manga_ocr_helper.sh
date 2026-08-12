#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MANIFEST="$PROJECT_DIR/native/manga_ocr_helper/Cargo.toml"
TARGET="aarch64-apple-darwin"
OUTPUT_DIR="$PROJECT_DIR/assets/executables"
BUILD_DIR="$PROJECT_DIR/native/manga_ocr_helper/target/$TARGET/release"

rustup target add "$TARGET"
cargo build --manifest-path "$MANIFEST" --release --target "$TARGET"

cp "$BUILD_DIR/manga-ocr-helper" "$OUTPUT_DIR/manga-ocr-helper-macos-arm64"
chmod 755 "$OUTPUT_DIR/manga-ocr-helper-macos-arm64"

ORT_DYLIB=$(find "$BUILD_DIR" -name 'libonnxruntime*.dylib' -type f | head -n 1 || true)
if [ -n "$ORT_DYLIB" ]; then
  cp "$ORT_DYLIB" "$OUTPUT_DIR/$(basename "$ORT_DYLIB")"
  chmod 755 "$OUTPUT_DIR/$(basename "$ORT_DYLIB")"
fi

if ! otool -l "$OUTPUT_DIR/manga-ocr-helper-macos-arm64" | grep -q '@executable_path'; then
  install_name_tool -add_rpath '@executable_path' "$OUTPUT_DIR/manga-ocr-helper-macos-arm64"
fi

echo "macOS arm64 helper 已生成到 assets/executables"
