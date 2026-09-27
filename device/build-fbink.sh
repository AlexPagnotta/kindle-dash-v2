#!/bin/sh
# Cross-compiles FBInk for a Kindle, into device/fbink.
#
# Needed because upstream ships no binaries, and the build bundled with KOReader is compiled
# without image support: it answers every probe and then fails with
# "Image support is disabled in this FBInk build".
#
# Static, so the Kindle's old glibc cannot get in the way. Requires Docker.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)

command -v docker > /dev/null 2>&1 || { echo "Docker is required" >&2; exit 1; }

docker run --rm -v "$HERE:/out" debian:bookworm sh -c '
  set -e
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    build-essential git ca-certificates gcc-arm-linux-gnueabihf libc6-dev-armhf-cross > /dev/null
  git clone --depth 1 --recursive -q https://github.com/NiLuJe/FBInk.git /src
  cd /src
  make CROSS_TC=arm-linux-gnueabihf KINDLE=1 static > /dev/null 2>&1
  arm-linux-gnueabihf-gcc -O2 -static -LRelease -o /out/fbink \
    Release/fbink_cmd.o -l:libfbink.a -lm
'

chmod +x "$HERE/fbink"
echo "Built $HERE/fbink"
