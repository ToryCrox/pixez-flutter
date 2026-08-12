#!/bin/sh

set -eu

ASSET_DIR="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Frameworks/App.framework/Versions/A/Resources/flutter_assets/assets/executables"
HELPER_PATH="$ASSET_DIR/manga-ocr-helper-macos-arm64"

if [ ! -f "$HELPER_PATH" ]; then
  exit 0
fi

chmod 755 "$HELPER_PATH"

if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ]; then
  for DYLIB in "$ASSET_DIR"/libonnxruntime*.dylib; do
    if [ -f "$DYLIB" ]; then
      chmod 755 "$DYLIB"
      /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$DYLIB"
    fi
  done
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$HELPER_PATH"

  # Flutter Assemble 已经生成并可能签过 App.framework。修改其中的资源后必须
  # 重新封装该 framework；外层 app 会由后续的 Xcode CodeSign 步骤签名。
  APP_FRAMEWORK="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Frameworks/App.framework"
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$APP_FRAMEWORK"
fi
