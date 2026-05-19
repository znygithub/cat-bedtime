#!/usr/bin/env bash
# Compile the LockScreen Swift binary
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${1:-$SCRIPT_DIR/../../bin/zzz-overlay}"

source "$SCRIPT_DIR/../signing.sh"

echo "Compiling LockScreen overlay (universal: arm64 + x86_64)..."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc -O -target arm64-apple-macos11 \
  -o "$TMP_DIR/zzz-overlay.arm64" \
  -framework AVFoundation -framework Cocoa -framework CoreGraphics -framework CoreImage -framework QuartzCore \
  "$SCRIPT_DIR/LockScreen.swift"

swiftc -O -target x86_64-apple-macos11 \
  -o "$TMP_DIR/zzz-overlay.x86_64" \
  -framework AVFoundation -framework Cocoa -framework CoreGraphics -framework CoreImage -framework QuartzCore \
  "$SCRIPT_DIR/LockScreen.swift"

lipo -create -output "$OUTPUT" \
  "$TMP_DIR/zzz-overlay.arm64" \
  "$TMP_DIR/zzz-overlay.x86_64"

chmod +x "$OUTPUT"
echo "Built: $OUTPUT"
lipo -info "$OUTPUT"
macos_codesign_target "$OUTPUT"
