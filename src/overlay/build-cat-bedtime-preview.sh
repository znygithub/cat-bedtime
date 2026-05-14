#!/usr/bin/env bash
# Build and optionally run the safe cat bedtime lockscreen preview.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${OUTPUT:-/tmp/timetosleep-cat-bedtime-preview}"

echo "Compiling cat bedtime preview..."

swiftc -O \
  -framework Cocoa \
  -framework QuartzCore \
  -framework ScreenCaptureKit \
  -o "$OUTPUT" \
  "$SCRIPT_DIR/CatBedtimePreview.swift"

chmod +x "$OUTPUT"
echo "Built: $OUTPUT"

if [[ "${1:-}" == "--build-only" ]]; then
  exit 0
fi

echo "Running preview... press ESC to exit."
exec "$OUTPUT" "$@"
