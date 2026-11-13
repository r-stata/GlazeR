#!/bin/zsh
# GlazeR 分发 DMG：分别产出 arm64 与 x86_64 安装包
# 用法: zsh native/build_dmg.sh  →  build/dist/GlazeR-arm64.dmg / GlazeR-x86_64.dmg
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
DIST="$ROOT/build/dist"

if [ ! -f "$ROOT/build/icon.icns" ] || [ ! -f "$ROOT/build/glazer-doc.icns" ]; then swift "$ROOT/build/make_icons.swift" >/dev/null; fi
rm -rf "$DIST"
mkdir -p "$DIST"

sign() {
  local signed=0 ident
  for ident in "GlazeR Dev" "DataWheel Dev"; do
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$ident"; then
      codesign --force --deep --sign "$ident" "$1" && return 0
    fi
  done
  echo "  (未找到自签名证书，回退 ad-hoc)"
  codesign --force --deep --sign - "$1"
}

make_app() {
  local arch="$1" app="$2"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  echo "① 编译 $arch Swift…"
  swiftc -O -swift-version 5 -disable-sandbox -parse-as-library \
    native/Sources/*.swift \
    -o "$app/Contents/MacOS/GlazeR" \
    -target "$arch-apple-macos13.0"
  echo "② 写入 Info.plist 与资源…"
  cp native/Info.plist "$app/Contents/Info.plist"
  cp build/icon.icns "$app/Contents/Resources/icon.icns"
  cp build/glazer-doc.icns "$app/Contents/Resources/glazer-doc.icns"
  cp build/menubar.png "$app/Contents/Resources/menubar.png"
  ditto "$ROOT/engine" "$app/Contents/Resources/engine"
  echo "③ 签名…"
  sign "$app"
}

make_dmg() {
  local app="$1" dmg="$2" stage="$app.dmgstage"
  rm -rf "$stage"; mkdir -p "$stage"
  ditto "$app" "$stage/GlazeR.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "GlazeR" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
  rm -rf "$stage"
}

echo "==== arm64 (Apple Silicon) ===="
make_app arm64 "$DIST/GlazeR-arm64/GlazeR.app"
make_dmg "$DIST/GlazeR-arm64/GlazeR.app" "$DIST/GlazeR-arm64.dmg"

echo "==== x86_64 (Intel) ===="
make_app x86_64 "$DIST/GlazeR-x86_64/GlazeR.app"
make_dmg "$DIST/GlazeR-x86_64/GlazeR.app" "$DIST/GlazeR-x86_64.dmg"

rm -rf "$DIST/GlazeR-arm64" "$DIST/GlazeR-x86_64"

echo "---- 产物校验 ----"
hdiutil attach "$DIST/GlazeR-arm64.dmg" -mountpoint /tmp/gz_dmg_arm -quiet
echo "arm64 二进制: $(lipo -archs /tmp/gz_dmg_arm/GlazeR.app/Contents/MacOS/GlazeR)"
codesign -dv /tmp/gz_dmg_arm/GlazeR.app 2>&1 | head -2
hdiutil detach /tmp/gz_dmg_arm -quiet
ls -lh "$DIST"/*.dmg
echo "完成: $DIST"
