#!/bin/bash
# Regenerates README images in docs/images/ by rendering the real SwiftUI views offscreen.
# No screen capture or Screen Recording permission needed.
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

OUTPUT_DIR="$DIR/docs/images"
mkdir -p "$OUTPUT_DIR"

echo "==> Rendering README images to $OUTPUT_DIR..."
RECLITE_README_IMAGES="$OUTPUT_DIR" \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    swift test --filter ReadmeImageTests

echo "==> Done:"
ls -1 "$OUTPUT_DIR"
