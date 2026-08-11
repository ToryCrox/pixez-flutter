#!/bin/sh

set -eu

TOOL_PATH="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Resources/flutter_assets/assets/executables/cwebp-macos"

if [ ! -f "$TOOL_PATH" ]; then
  exit 0
fi

chmod 755 "$TOOL_PATH"

# cwebp 是应用包内的子可执行文件。先单独签名，再由 Xcode 签名整个 app，
# 这样在沙盒和已公证的 macOS 应用中都可以通过 Process.run 调用。
if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$TOOL_PATH"
fi
