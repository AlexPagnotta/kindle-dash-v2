#!/bin/sh
# Pushes the device side to a Kindle reachable over USB networking or Wi-Fi.
# Usage: ./install.sh [kindle-ip]   (default 192.168.15.244, the USBNet address)

set -e

KINDLE="${1:-192.168.15.244}"
HERE=$(cd "$(dirname "$0")" && pwd)

if [ ! -f "$HERE/fbink" ]; then
  echo "Missing $HERE/fbink"
  echo "Download the static binary for your device from https://github.com/NiLuJe/FBInk/releases"
  exit 1
fi

echo "Installing to root@$KINDLE"
ssh "root@$KINDLE" "mkdir -p /mnt/us/kindle-dash /mnt/us/extensions"
scp "$HERE/dash.sh" "$HERE/fbink" "root@$KINDLE:/mnt/us/kindle-dash/"
scp -r "$HERE/kual/kindle-dash" "root@$KINDLE:/mnt/us/extensions/"

if [ -f "$HERE/dash.conf" ]; then
  scp "$HERE/dash.conf" "root@$KINDLE:/mnt/us/kindle-dash/"
else
  echo "No dash.conf found, copy dash.conf.example and set DASH_URL"
fi

ssh "root@$KINDLE" "chmod +x /mnt/us/kindle-dash/dash.sh /mnt/us/kindle-dash/fbink /mnt/us/extensions/kindle-dash/bin/*.sh"
echo "Done. Open KUAL on the Kindle and pick Kindle Dash > Start dashboard."
