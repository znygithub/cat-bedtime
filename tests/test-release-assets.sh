#!/usr/bin/env bash
# Regression: release builds must include the lock-screen animation video.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANIMATION="$ROOT_DIR/assets/cat-bedtime.mov"
APP_BUILD="$ROOT_DIR/src/app/build.sh"
CLI_RELEASE="$ROOT_DIR/scripts/release-cli-macos.sh"
GITIGNORE="$ROOT_DIR/.gitignore"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[ -s "$ANIMATION" ] || fail "assets/cat-bedtime.mov is missing or empty"

if git -C "$ROOT_DIR" check-ignore -q "$ANIMATION"; then
  fail "assets/cat-bedtime.mov is ignored by git"
fi

grep -Fq 'Missing required lock-screen animation: assets/cat-bedtime.mov' "$APP_BUILD" \
  || fail "app build does not fail fast when cat-bedtime.mov is missing"

grep -Fq 'Build error: app bundle is missing Resources/assets/cat-bedtime.mov' "$APP_BUILD" \
  || fail "app build does not verify bundled cat-bedtime.mov"

grep -Fq 'Missing required lock-screen animation: assets/cat-bedtime.mov' "$CLI_RELEASE" \
  || fail "CLI release does not fail fast when cat-bedtime.mov is missing"

grep -Fq 'Build error: CLI archive stage is missing assets/cat-bedtime.mov' "$CLI_RELEASE" \
  || fail "CLI release does not verify staged cat-bedtime.mov"

grep -Fq '!assets/cat-bedtime.mov' "$GITIGNORE" \
  || fail ".gitignore does not unignore assets/cat-bedtime.mov"

echo "OK release assets"
