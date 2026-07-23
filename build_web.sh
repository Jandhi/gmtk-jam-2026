#!/usr/bin/env bash
# Export the Web build and zip it for itch.io upload.
set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"

rm -rf build/web build/web.zip
mkdir -p build/web
"$GODOT" --headless --export-release Web build/web/index.html
(cd build/web && zip -qr ../web.zip .)

echo "Done: build/web.zip"
echo "Upload to itch.io (mark as 'This file will be played in the browser'),"
echo "or: butler push build/web YOUR_USER/YOUR_GAME:html5"
