#!/usr/bin/env bash
# Compile the Cat Bedtime SwiftUI app as a .app bundle (universal binary)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${1:-$SCRIPT_DIR/../../bin}"
APP_BUNDLE="$BIN_DIR/Cat Bedtime.app"

echo "Compiling Cat Bedtime app (universal: arm64 + x86_64)..."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc -O -target arm64-apple-macos12 \
  -o "$TMP_DIR/zzz-app.arm64" \
  -framework Cocoa -framework SwiftUI \
  "$SCRIPT_DIR/CatBedtimeApp.swift"

swiftc -O -target x86_64-apple-macos12 \
  -o "$TMP_DIR/zzz-app.x86_64" \
  -framework Cocoa -framework SwiftUI \
  "$SCRIPT_DIR/CatBedtimeApp.swift"

lipo -create -output "$TMP_DIR/zzz-app" \
  "$TMP_DIR/zzz-app.arm64" \
  "$TMP_DIR/zzz-app.x86_64"

# ── Create .app bundle ──
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$TMP_DIR/zzz-app" "$APP_BUNDLE/Contents/MacOS/zzz-app"
chmod +x "$APP_BUNDLE/Contents/MacOS/zzz-app"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>zzz-app</string>
  <key>CFBundleIdentifier</key>
  <string>com.timetosleep.app</string>
  <key>CFBundleName</key>
  <string>Cat Bedtime</string>
  <key>CFBundleDisplayName</key>
  <string>Cat Bedtime</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1.0.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSUIElement</key>
  <false/>
</dict>
</plist>
PLIST

echo "Built: $APP_BUNDLE"
lipo -info "$APP_BUNDLE/Contents/MacOS/zzz-app"
