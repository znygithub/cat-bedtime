#!/usr/bin/env bash
# Build and optionally run the safe cat video lockscreen preview.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${OUTPUT:-/tmp/timetosleep-cat-video-preview}"

echo "Compiling cat video preview..."

swiftc -O \
  -framework AVFoundation \
  -framework Cocoa \
  -framework CoreImage \
  -framework QuartzCore \
  -framework ScreenCaptureKit \
  -o "$OUTPUT" \
  "$SCRIPT_DIR/CatVideoBedtimePreview.swift"

chmod +x "$OUTPUT"
echo "Built: $OUTPUT"

if [[ "${1:-}" == "--build-only" ]]; then
  exit 0
fi

echo "Running preview... press ESC to exit."
exec "$OUTPUT" "$@"
