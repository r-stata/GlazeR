#!/bin/zsh
# GlazeR 原生 SwiftUI 版本地构建脚本
# 用法: zsh native/build_native.sh  →  build/GlazeR.app
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="build/GlazeR.app"

echo "① 生成图标（若缺失）…"
if [ ! -f "$ROOT/build/icon.icns" ] || [ ! -f "$ROOT/build/menubar.png" ] || [ ! -f "$ROOT/build/glazer-doc.icns" ]; then
  swift "$ROOT/build/make_icons.swift" >/dev/null
fi

echo "② 编译 Swift…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -disable-sandbox -parse-as-library \
  native/Sources/*.swift \
  -o "$APP/Contents/MacOS/GlazeR" \
  -target arm64-apple-macos13.0

echo "③ 写入 Info.plist 与资源…"
cp native/Info.plist "$APP/Contents/Info.plist"
cp build/icon.icns "$APP/Contents/Resources/icon.icns"
cp build/glazer-doc.icns "$APP/Contents/Resources/glazer-doc.icns"
cp build/menubar.png "$APP/Contents/Resources/menubar.png"
ditto "$ROOT/engine" "$APP/Contents/Resources/engine"

echo "④ 签名（稳定自签名身份保证辅助功能授权跨重编译有效）…"
SIGNED=0
for IDENT in "GlazeR Dev" "DataWheel Dev"; do
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENT"; then
    codesign --force --deep --sign "$IDENT" "$APP" && echo "  签名: $IDENT" && SIGNED=1 && break
  fi
done
if [ "$SIGNED" -eq 0 ]; then
  echo "  (未找到自签名证书，回退 ad-hoc——辅助功能授权将随重编译失效)"
  codesign --force --deep --sign - "$APP"
fi

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
killall Finder Dock 2>/dev/null || true

echo "完成: $ROOT/$APP"
