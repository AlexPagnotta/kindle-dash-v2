#!/bin/sh
# Kindle Dash: fetch a server-rendered PNG and draw it on the e-ink panel.
# Runs on stock jailbroken firmware, no Linux, no browser.

set -u

ROOT=$(cd "$(dirname "$0")" && pwd)
[ -f "$ROOT/dash.conf" ] && . "$ROOT/dash.conf"

DASH_URL="${DASH_URL:-http://192.168.1.50:3000/api/dash.png}"
INTERVAL="${INTERVAL:-300}"
FULL_REFRESH_EVERY="${FULL_REFRESH_EVERY:-12}"
SUSPEND="${SUSPEND:-0}"
STOP_FRAMEWORK="${STOP_FRAMEWORK:-0}"
FBINK="${FBINK:-$ROOT/fbink}"
IMAGE=/tmp/dash.png
LOG="${LOG:-$ROOT/dash.log}"
PIDFILE=/tmp/kindle-dash.pid

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
  # Keep the log from eating the tiny rootfs
  if [ "$(wc -c < "$LOG")" -gt 524288 ]; then
    tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  fi
}

cleanup() {
  log "stopping"
  [ "$STOP_FRAMEWORK" = "1" ] && start lab126_gui >/dev/null 2>&1
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1
  rm -f "$PIDFILE"
  exit 0
}
trap cleanup INT TERM
# Interrupts the sleep between cycles, so "Refresh now" redraws immediately
trap 'log "manual refresh"' USR1

wifi() {
  lipc-set-prop com.lab126.cmd wirelessEnable "$1" >/dev/null 2>&1
  [ "$1" = "0" ] && return 0

  WAITED=0
  while [ "$WAITED" -lt 30 ]; do
    STATE=$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)
    [ "$STATE" = "CONNECTED" ] && return 0
    sleep 2
    WAITED=$((WAITED + 2))
  done
  log "wifi not connected after ${WAITED}s, trying anyway"
}

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -sfS -m 90 -o "$IMAGE.tmp" "$DASH_URL" >/dev/null 2>&1 || return 1
  else
    wget -q -T 90 -O "$IMAGE.tmp" "$DASH_URL" >/dev/null 2>&1 || return 1
  fi

  # A truncated or HTML error body must never reach the panel
  [ -s "$IMAGE.tmp" ] || return 1
  head -c 4 "$IMAGE.tmp" | grep -q "PNG" || return 1

  mv "$IMAGE.tmp" "$IMAGE"
}

draw() {
  if [ $((COUNT % FULL_REFRESH_EVERY)) -eq 0 ]; then
    "$FBINK" -q -f -c -g file="$IMAGE"
  else
    "$FBINK" -q -g file="$IMAGE"
  fi
}

rest() {
  if [ "$SUSPEND" = "1" ] && [ -w /sys/power/state ]; then
    lipc-set-prop com.lab126.powerd rtcWake "$INTERVAL" >/dev/null 2>&1
    echo mem > /sys/power/state
  else
    sleep "$INTERVAL"
  fi
}

if [ ! -x "$FBINK" ]; then
  echo "fbink not found at $FBINK" >&2
  exit 1
fi

echo $$ > "$PIDFILE"
log "starting: refresh every ${INTERVAL}s from $DASH_URL"

[ "$STOP_FRAMEWORK" = "1" ] && stop lab126_gui >/dev/null 2>&1
lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1

COUNT=0
while true; do
  wifi 1
  if fetch; then
    draw
    log "refreshed (cycle $COUNT)"
  else
    log "fetch failed, keeping previous image"
  fi
  wifi 0

  COUNT=$((COUNT + 1))
  rest
done
