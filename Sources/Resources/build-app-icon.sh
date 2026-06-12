#!/bin/bash
#
# Renders Sources/Resources/AppIcon.svg into the asset catalog at every
# required size.
#
#   Sources/Resources/build-app-icon.sh
#
# Uses Quick Look's WebKit renderer (qlmanage), which handles SVG gradients
# and clips faithfully, then resamples with sips.

set -euo pipefail
cd "$(dirname "$0")/../.."

SVG="Sources/Resources/AppIcon.svg"
OUT="Sources/Resources/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null
MASTER="$TMP/$(basename "$SVG").png"
[ -f "$MASTER" ] || { echo "render failed" >&2; exit 1; }

render() { # pixels filename
    sips -z "$1" "$1" "$MASTER" --out "$OUT/$2" >/dev/null
}

render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
cp "$MASTER" "$OUT/icon_512x512@2x.png"

echo "wrote icons to $OUT"
