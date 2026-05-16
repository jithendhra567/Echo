#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Echo/Assets.xcassets/AppIcon.appiconset"
MASTER="$DEST/_master.png"

swift "$ROOT/scripts/render_app_icon.swift" "$MASTER"
cd "$DEST"
sips -z 16 16 _master.png --out icon_16x16.png >/dev/null
sips -z 32 32 _master.png --out icon_16x16@2x.png >/dev/null
sips -z 32 32 _master.png --out icon_32x32.png >/dev/null
sips -z 64 64 _master.png --out icon_32x32@2x.png >/dev/null
sips -z 128 128 _master.png --out icon_128x128.png >/dev/null
sips -z 256 256 _master.png --out icon_128x128@2x.png >/dev/null
sips -z 256 256 _master.png --out icon_256x256.png >/dev/null
sips -z 512 512 _master.png --out icon_256x256@2x.png >/dev/null
sips -z 512 512 _master.png --out icon_512x512.png >/dev/null
sips -z 1024 1024 _master.png --out icon_512x512@2x.png >/dev/null
rm -f _master.png
echo "App icon installed in $DEST"
