#!/bin/sh
# Installs the device side over a USB cable, no SSH needed.
# Plug the Kindle in, wait for it to mount as a drive, then run this.
# Usage: ./install-usb.sh [/path/to/mounted/kindle]   (default: /Volumes/Kindle on macOS)

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
VOLUME=${1:-/Volumes/Kindle}

if [ ! -d "$VOLUME" ]; then
  echo "No Kindle mounted at $VOLUME" >&2
  echo "Plug it in, wait for the drive to appear, or pass the path as an argument" >&2
  exit 1
fi

# The drive root is /mnt/us on the device, and every Kindle has these
if [ ! -d "$VOLUME/documents" ] && [ ! -d "$VOLUME/system" ]; then
  echo "$VOLUME does not look like a Kindle" >&2
  exit 1
fi

if [ ! -f "$HERE/fbink" ]; then
  echo "Missing $HERE/fbink, run ./get-fbink.sh first" >&2
  exit 1
fi

mkdir -p "$VOLUME/kindle-dash" "$VOLUME/extensions"
cp "$HERE/dash.sh" "$HERE"/fbink* "$VOLUME/kindle-dash/"

if [ -f "$HERE/dash.conf" ]; then
  cp "$HERE/dash.conf" "$VOLUME/kindle-dash/"
else
  echo "No dash.conf found, copy dash.conf.example and set DASH_URL"
fi

rm -rf "$VOLUME/extensions/kindle-dash"
cp -R "$HERE/kual/kindle-dash" "$VOLUME/extensions/"

# FAT keeps no exec bit, dash.sh copies fbink to /tmp and chmods it there
chmod -R a+rx "$VOLUME/kindle-dash" "$VOLUME/extensions/kindle-dash" 2>/dev/null || true

echo "Copied to $VOLUME"
echo "Now eject the Kindle, then open KUAL -> Kindle Dash -> Start dashboard."
