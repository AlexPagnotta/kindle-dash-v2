#!/bin/sh
# Kindle Dash: fetch a server-rendered PNG and draw it on the e-ink panel.
# Runs on stock jailbroken firmware, no Linux, no browser.

set -u

ROOT=$(cd "$(dirname "$0")" && pwd)
[ -f "$ROOT/dash.conf" ] && . "$ROOT/dash.conf"

DASH_URL="${DASH_URL:-http://192.168.1.50:6800/api/dash.png}"
INTERVAL="${INTERVAL:-300}"
FULL_REFRESH_EVERY="${FULL_REFRESH_EVERY:-12}"
SUSPEND="${SUSPEND:-0}"
STOP_FRAMEWORK="${STOP_FRAMEWORK:-0}"
POWER_EXIT="${POWER_EXIT:-1}"
POWER_EXIT_WINDOW="${POWER_EXIT_WINDOW:-6}"
FBINK="${FBINK:-$ROOT/fbink}"
IMAGE=/tmp/dash.png
LOG="${LOG:-$ROOT/dash.log}"
PIDFILE=/tmp/kindle-dash.pid

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null || LOG=/tmp/dash.log
  # Keep the log from eating the tiny rootfs
  if [ "$(wc -c < "$LOG")" -gt 524288 ]; then
    tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  fi
}

# Upstart on most firmware, systemd on the newest
framework() {
  if command -v "$1" >/dev/null 2>&1; then
    "$1" lab126_gui >/dev/null 2>&1 && return 0
  fi
  systemctl "$1" lab126_gui >/dev/null 2>&1 || true
}

cleanup() {
  log "stopping"
  [ -n "${WATCH_PID:-}" ] && kill "$WATCH_PID" 2>/dev/null
  [ "$STOP_FRAMEWORK" = "1" ] && framework start
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1
  rm -f "$PIDFILE"
  exit 0
}
trap cleanup INT TERM
# Interrupts the sleep between cycles, so "Refresh now" redraws immediately
trap 'log "manual refresh"' USR1

# With the UI stopped there is no KUAL and so no way out from the device. The power button is read
# straight from the kernel: with the framework down, powerd stops publishing its lipc events.
power_device() {
  awk '
    /^N: Name=/ { name = tolower($0) }
    /^H: Handlers=/ {
      if (name ~ /power/ && match($0, /event[0-9]+/)) {
        print "/dev/input/" substr($0, RSTART, RLENGTH)
        exit
      }
    }
  ' /proc/bus/input/devices 2>/dev/null
}

power_watch() {
  DEV=$(power_device)

  if [ -z "$DEV" ] || [ ! -r "$DEV" ]; then
    log "no readable power input device, stop it over SSH or reboot"
    log "inputs: $(grep -i '^N: Name=' /proc/bus/input/devices 2>/dev/null | tr '\n' ' ')"
    return
  fi

  log "watching $DEV, press power twice within ${POWER_EXIT_WINDOW}s to stop"
  LAST=0

  # Blocks until the button reports something. One press emits several events, so a short
  # debounce collapses them into one.
  while dd if="$DEV" bs=16 count=1 > /dev/null 2>&1; do
    NOW=$(date +%s)
    log "power pressed"

    if [ "$LAST" != "0" ] && [ $((NOW - LAST)) -le "$POWER_EXIT_WINDOW" ]; then
      log "power pressed twice, stopping"
      kill -TERM "$MAIN_PID" 2>/dev/null
      return
    fi

    LAST=$NOW
    sleep 1
  done

  log "power watch ended"
}

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
  # fbink writes its device detection to stderr, so only a non-zero exit is worth logging
  if [ $((COUNT % FULL_REFRESH_EVERY)) -eq 0 ]; then
    ERR=$("$FBINK" -q -f -c -g file="$IMAGE" 2>&1 >/dev/null) || log "fbink failed: $ERR"
  else
    ERR=$("$FBINK" -q -g file="$IMAGE" 2>&1 >/dev/null) || log "fbink failed: $ERR"
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

# Run it from /tmp: FAT keeps no exec bit, and a USB cable unmounts /mnt/us under a running script
setup_fbink() {
  [ -f "$FBINK" ] || { log "no fbink at $FBINK, run device/build-fbink.sh"; return 1; }

  cp "$FBINK" /tmp/fbink 2>/dev/null || return 1
  chmod +x /tmp/fbink

  # A build without image support passes every other check and then refuses to draw, so the
  # test is a real draw
  if ! /tmp/fbink -g file="$IMAGE" > /dev/null 2>&1; then
    log "fbink cannot draw here, rebuild it with device/build-fbink.sh"
    return 1
  fi

  FBINK=/tmp/fbink
  return 0
}

echo $$ > "$PIDFILE"
log "starting: refresh every ${INTERVAL}s from $DASH_URL"

if [ "$STOP_FRAMEWORK" = "1" ]; then
  # Otherwise the Kindle UI redraws over the dashboard as soon as KUAL exits.
  # Stopping it signals everything in that session, so deafen ourselves while it happens.
  log "stopping the Kindle UI"
  trap '' TERM HUP
  framework stop
  sleep 5
  trap cleanup TERM
  log "Kindle UI stopped"
fi

lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1

MAIN_PID=$$
if [ "$POWER_EXIT" = "1" ]; then
  power_watch &
  WATCH_PID=$!
fi

COUNT=0
READY=0
while true; do
  wifi 1
  if fetch; then
    # Checking fbink needs a real PNG, so it waits for the first successful fetch
    if [ "$READY" = "0" ]; then
      setup_fbink || cleanup
      READY=1
    fi

    draw
    log "refreshed (cycle $COUNT)"
  else
    log "fetch failed, keeping previous image"
  fi
  wifi 0

  COUNT=$((COUNT + 1))
  rest
done
