#!/bin/sh
# snow.swift → XmasSnow.app (Dock 아이콘 없이 메뉴 막대 ❄︎ 만 뜬다)
set -e
cd "$(dirname "$0")"
APP="XmasSnow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
# 친구 맥에서도 돌게: 애플 실리콘 + 인텔 유니버설, macOS 13 이상
swiftc -O -target arm64-apple-macos13 snow.swift -o /tmp/snowfall-arm64
swiftc -O -target x86_64-apple-macos13 snow.swift -o /tmp/snowfall-x86_64
lipo -create /tmp/snowfall-arm64 /tmp/snowfall-x86_64 -output "$APP/Contents/MacOS/snowfall"
rm -f /tmp/snowfall-arm64 /tmp/snowfall-x86_64
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>snowfall</string>
  <key>CFBundleIdentifier</key><string>io.github.imhuijeong92-ui.xmas-snow</string>
  <key>CFBundleName</key><string>Xmas Snow</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
EOF
codesign --force --sign - "$APP"
echo "built $APP"
