#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE_IMAGE="${1:-Assets/AppLogo.png}"
OUTPUT_ICON="${2:-Assets/AppIcon.icns}"
if [ ! -f "$SOURCE_IMAGE" ]; then
    printf 'Logo image not found: %s\n' "$SOURCE_IMAGE" >&2
    exit 1
fi
TASK_ICON_DIR=$(mktemp -d)
trap 'rm -rf "$TASK_ICON_DIR"' EXIT
mkdir -p "$TASK_ICON_DIR/AppIcon.iconset"
for SIZE in 16 32 128 256 512; do
    sips --setProperty format png --resampleHeightWidth "$SIZE" "$SIZE" "$SOURCE_IMAGE" --out "$TASK_ICON_DIR/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE_SIZE=$((SIZE * 2))
    sips --setProperty format png --resampleHeightWidth "$DOUBLE_SIZE" "$DOUBLE_SIZE" "$SOURCE_IMAGE" --out "$TASK_ICON_DIR/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil --convert icns "$TASK_ICON_DIR/AppIcon.iconset" --output "$OUTPUT_ICON"
