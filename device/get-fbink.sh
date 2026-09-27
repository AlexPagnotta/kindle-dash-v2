#!/bin/sh
# Downloads the fbink binary this project needs, into device/fbink.
#
# Upstream (github.com/NiLuJe/FBInk) publishes source only, so this takes the build that ships
# inside KOReader's Kindle bundle: same upstream binary, compiled for the right ABI.
#
# Usage: ./get-fbink.sh [variant]
#   kindlepw2  (default) Paperwhite 2 and every later model, including the basic Kindles
#   kindlehf             newest hard-float models (Kindle 11th gen, Paperwhite 5, Scribe)
#   kindle               Kindle 4, 5, Touch, Paperwhite 1
#   kindle-legacy        Kindle 2, 3, DX

set -e

VARIANT=${1:-kindlepw2}
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

TAG=$(curl -fsSL https://api.github.com/repos/koreader/koreader/releases/latest |
  sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
[ -n "$TAG" ] || { echo "Could not read the latest KOReader release" >&2; exit 1; }

URL="https://github.com/koreader/koreader/releases/download/$TAG/koreader-$VARIANT-$TAG.zip"
echo "Fetching $VARIANT fbink from KOReader $TAG"
curl -fL --progress-bar -o "$TMP/ko.zip" "$URL"

unzip -o -q -j "$TMP/ko.zip" koreader/fbink -d "$TMP"
[ -f "$TMP/fbink" ] || { echo "No fbink in that bundle" >&2; exit 1; }

mv "$TMP/fbink" "$HERE/fbink"
chmod +x "$HERE/fbink"
echo "Saved to $HERE/fbink"
file "$HERE/fbink" 2>/dev/null || true
