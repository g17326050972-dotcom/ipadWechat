#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$PROJECT_ROOT/build"
xcrun --sdk iphoneos clang \
  -arch arm64 -miphoneos-version-min=15.0 \
  -fobjc-arc -fblocks -dynamiclib \
  -framework Foundation -framework UIKit -framework CoreGraphics \
  -install_name @executable_path/Frameworks/LocalPadMode.dylib \
  "$PROJECT_ROOT/src/WeChatPadMode.m" \
  -o "$PROJECT_ROOT/build/LocalPadMode.dylib"
printf 'Built: %s\n' "$PROJECT_ROOT/build/LocalPadMode.dylib"
