#!/usr/bin/env bash
# Build the drag-to-Applications macOS app DMG for website distribution.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/Cat Bedtime"
RW_DMG_PATH="$DIST_DIR/Cat-Bedtime-rw.dmg"
DMG_PATH="$DIST_DIR/Cat-Bedtime-macOS.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-cat-bedtime-notary}"
TEAM_ID="${APPLE_TEAM_ID:-LGQX6KS72C}"

source "$ROOT_DIR/src/signing.sh"

cleanup_stage() {
  rm -rf "$STAGE_DIR" "$RW_DMG_PATH"
}
trap cleanup_stage EXIT

developer_identity="$(macos_find_developer_id_identity || true)"
if [ -z "$developer_identity" ]; then
  cat >&2 <<'EOF'
Public website distribution requires a Developer ID Application certificate.

This Mac currently has no Developer ID Application signing identity in Keychain.
Install one from Apple Developer, then run this script again.

After the certificate is installed, save notarization credentials once:
  xcrun notarytool store-credentials cat-bedtime-notary --apple-id 1339975893@qq.com --team-id LGQX6KS72C

Use an app-specific password at the secure prompt. Do not paste that password into chat.
EOF
  exit 1
fi

export CODE_SIGN_IDENTITY="$developer_identity"
export REQUIRE_DEVELOPER_ID=1

echo "Using Developer ID identity: $CODE_SIGN_IDENTITY"

mkdir -p "$DIST_DIR"
rm -rf "$STAGE_DIR" "$RW_DMG_PATH" "$DMG_PATH"

"$ROOT_DIR/src/overlay/build.sh" "$ROOT_DIR/bin/zzz-overlay"
"$ROOT_DIR/src/app/build.sh" "$ROOT_DIR/bin"

mkdir -p "$STAGE_DIR"
ditto "$ROOT_DIR/bin/Cat Bedtime.app" "$STAGE_DIR/Cat Bedtime.app"
ln -s /Applications "$STAGE_DIR/Applications"
find "$STAGE_DIR" -name .DS_Store -delete

xattr -cr "$STAGE_DIR/Cat Bedtime.app" 2>/dev/null || true

codesign --verify --deep --strict --verbose=2 "$STAGE_DIR/Cat Bedtime.app"
codesign --verify --verbose=2 "$STAGE_DIR/Cat Bedtime.app/Contents/Resources/bin/zzz-overlay"

hdiutil create \
  -volname "Cat Bedtime" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG_PATH"

mount_output="$(hdiutil attach "$RW_DMG_PATH" -readwrite -noverify -noautoopen)"
mount_dir="$(printf '%s\n' "$mount_output" | sed -n 's#.*\(/Volumes/.*\)#\1#p' | tail -n 1)"

if [ -d "$mount_dir" ]; then
  /usr/bin/osascript <<APPLESCRIPT || true
tell application "Finder"
  tell disk "Cat Bedtime"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    try
      set pathbar visible of container window to false
    end try
    set bounds of container window to {160, 120, 620, 390}
    set arrangement of icon view options of container window to not arranged
    set icon size of icon view options of container window to 88
    set position of item "Cat Bedtime.app" of container window to {145, 140}
    set position of item "Applications" of container window to {315, 140}
    update without registering applications
    close
  end tell
end tell
APPLESCRIPT
  sync
  hdiutil detach "$mount_dir"
  while hdiutil info | grep -Fq "$RW_DMG_PATH"; do
    sleep 1
  done
fi

hdiutil convert "$RW_DMG_PATH" -format UDZO -o "$DMG_PATH" -ov
rm -f "$RW_DMG_PATH"

codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "Skipping notarization because SKIP_NOTARIZE=1"
  echo "Unsigned-by-Apple release image: $DMG_PATH"
  exit 0
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  cat >&2 <<EOF
Notarization profile '$NOTARY_PROFILE' is not available or failed validation.

Create it once with:
  xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id 1339975893@qq.com --team-id "$TEAM_ID"

Use an app-specific password at the secure prompt. Then rerun:
  scripts/release-macos.sh
EOF
  exit 1
fi

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -t open --context context:primary-signature -vvv "$DMG_PATH"

echo "Release ready: $DMG_PATH"
