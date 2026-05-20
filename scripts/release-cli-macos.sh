#!/usr/bin/env bash
# Build the standalone CLI distribution archive.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
CLI_STAGE="$DIST_DIR/cat-bedtime-cli"
ARCHIVE_PATH="$DIST_DIR/cat-bedtime-cli-macos.tar.gz"

source "$ROOT_DIR/src/signing.sh"

cleanup_stage() {
  rm -rf "$CLI_STAGE"
}
trap cleanup_stage EXIT

mkdir -p "$DIST_DIR"
rm -rf "$CLI_STAGE" "$ARCHIVE_PATH"

"$ROOT_DIR/src/overlay/build.sh" "$ROOT_DIR/bin/zzz-overlay"

mkdir -p "$CLI_STAGE/bin"
install -m 755 "$ROOT_DIR/install.sh" "$CLI_STAGE/install.sh"
install -m 644 "$ROOT_DIR/README.md" "$CLI_STAGE/README.md"
if [ -f "$ROOT_DIR/README_EN.md" ]; then
  install -m 644 "$ROOT_DIR/README_EN.md" "$CLI_STAGE/README_EN.md"
fi
if [ -f "$ROOT_DIR/LICENSE" ]; then
  install -m 644 "$ROOT_DIR/LICENSE" "$CLI_STAGE/LICENSE"
fi

install -m 755 "$ROOT_DIR/bin/zzz" "$CLI_STAGE/bin/zzz"
ditto "$ROOT_DIR/bin/zzz-overlay" "$CLI_STAGE/bin/zzz-overlay"
ditto "$ROOT_DIR/lib" "$CLI_STAGE/lib"
mkdir -p "$CLI_STAGE/src"
ditto "$ROOT_DIR/src/cli" "$CLI_STAGE/src/cli"
mkdir -p "$CLI_STAGE/locales"
install -m 644 "$ROOT_DIR/locales/messages.json" "$CLI_STAGE/locales/messages.json"
mkdir -p "$CLI_STAGE/assets"
rsync -a --exclude '*.backup-*' "$ROOT_DIR/assets/" "$CLI_STAGE/assets/"

codesign --verify --verbose=2 "$CLI_STAGE/bin/zzz-overlay"

(
  cd "$DIST_DIR"
  tar -czf "$ARCHIVE_PATH" cat-bedtime-cli
)

echo "CLI release ready: $ARCHIVE_PATH"
