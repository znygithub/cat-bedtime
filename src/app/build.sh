#!/usr/bin/env bash
# Compile the Cat Bedtime SwiftUI app as a .app bundle (universal binary)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${1:-$SCRIPT_DIR/../../bin}"
APP_BUNDLE="$BIN_DIR/Cat Bedtime.app"

source "$SCRIPT_DIR/../signing.sh"

echo "Compiling Cat Bedtime app (universal: arm64 + x86_64)..."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

L10N_SWIFT="$SCRIPT_DIR/../shared/L10n.swift"
LOCALES_SRC="$SCRIPT_DIR/../../locales"

swiftc -O -target arm64-apple-macos12 \
  -o "$TMP_DIR/zzz-app.arm64" \
  -framework Cocoa -framework SwiftUI -framework UserNotifications \
  "$L10N_SWIFT" "$SCRIPT_DIR/CatBedtimeApp.swift"

swiftc -O -target x86_64-apple-macos12 \
  -o "$TMP_DIR/zzz-app.x86_64" \
  -framework Cocoa -framework SwiftUI -framework UserNotifications \
  "$L10N_SWIFT" "$SCRIPT_DIR/CatBedtimeApp.swift"

lipo -create -output "$TMP_DIR/zzz-app" \
  "$TMP_DIR/zzz-app.arm64" \
  "$TMP_DIR/zzz-app.x86_64"

# ── Create .app bundle ──
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$TMP_DIR/zzz-app" "$APP_BUNDLE/Contents/MacOS/zzz-app"
chmod +x "$APP_BUNDLE/Contents/MacOS/zzz-app"

# ── Copy app icon ──
ICON_SRC="$SCRIPT_DIR/../../assets/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# ── Bundle runtime payload for drag-to-Applications installs ──
mkdir -p "$APP_BUNDLE/Contents/Resources/bin"
mkdir -p "$APP_BUNDLE/Contents/Resources/src"
cp "$SCRIPT_DIR/../../bin/zzz-overlay" "$APP_BUNDLE/Contents/Resources/bin/zzz-overlay"
cp -R "$SCRIPT_DIR/../../lib" "$APP_BUNDLE/Contents/Resources/lib"
cp -R "$SCRIPT_DIR/../../src/cli" "$APP_BUNDLE/Contents/Resources/src/cli"
cp -R "$SCRIPT_DIR/../../assets" "$APP_BUNDLE/Contents/Resources/assets"
mkdir -p "$APP_BUNDLE/Contents/Resources/locales"
cp "$LOCALES_SRC/messages.json" "$APP_BUNDLE/Contents/Resources/locales/messages.json"
chmod +x "$APP_BUNDLE/Contents/Resources/bin/zzz-overlay"
chmod +x "$APP_BUNDLE/Contents/Resources/src/cli/daemon.sh"

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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>NSUserNotificationAlertStyle</key>
  <string>banner</string>
  <key>LSUIElement</key>
  <false/>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>zh-Hans</string>
    <string>zh-Hant</string>
    <string>ja</string>
    <string>ko</string>
  </array>
</dict>
</plist>
PLIST

# Localized display name (bundle filename stays Cat Bedtime.app)
write_infoplist_strings() {
  local lproj="$1"
  local display_name="$2"
  mkdir -p "$APP_BUNDLE/Contents/Resources/$lproj"
  cat > "$APP_BUNDLE/Contents/Resources/$lproj/InfoPlist.strings" <<EOF
/* Localized bundle display name */
"CFBundleDisplayName" = "$display_name";
"CFBundleName" = "$display_name";
EOF
}
write_infoplist_strings "en.lproj" "Cat Bedtime"
write_infoplist_strings "zh-Hans.lproj" "猫猫困了"
write_infoplist_strings "zh-Hant.lproj" "貓貓困了"
write_infoplist_strings "ja.lproj" "Cat Bedtime"
write_infoplist_strings "ko.lproj" "Cat Bedtime"

echo "Built: $APP_BUNDLE"
lipo -info "$APP_BUNDLE/Contents/MacOS/zzz-app"
macos_codesign_target "$APP_BUNDLE"
