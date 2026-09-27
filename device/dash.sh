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
  pkill -f lipc-wait-event 2>/dev/null
  [ "$STOP_FRAMEWORK" = "1" ] && framework start
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1
  rm -f "$PIDFILE"
  exit 0
}
trap cleanup INT TERM
# Interrupts the sleep between cycles, so "Refresh now" redraws immediately
trap 'log "manual refresh"' USR1

# With the UI stopped there is no KUAL and so no way out from the device. powerd keeps running
# though, so two power presses in quick succession stop the dashboard and bring the UI back.
power_watch() {
  SEEN=0
  LAST=0

  while true; do
    lipc-wait-event -m -s 0 com.lab126.powerd '*' 2>/dev/null | while read -r EVENT; do
      # The first few are logged so the event names can be checked against a real device
      if [ "$SEEN" -lt 8 ]; then
        log "power event: $EVENT"
        SEEN=$((SEEN + 1))
      fi

      case "$EVENT" in
        *creenSaver* | *uspend* | *owerButton*)
          NOW=$(date +%s)

          if [ "$LAST" != "0" ] && [ $((NOW - LAST)) -le "$POWER_EXIT_WINDOW" ]; then
            log "power pressed twice, stopping"
            kill -TERM "$MAIN_PID" 2>/dev/null
            exit 0
          fi

          LAST=$NOW
          ;;
      esac
    done

    sleep 2
  done
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
  if [ $((COUNT % FULL_REFRESH_EVERY)) -eq 0 ]; then
    ERR=$("$FBINK" -f -c -g file="$IMAGE" 2>&1 >/dev/null) || true
  else
    ERR=$("$FBINK" -g file="$IMAGE" 2>&1 >/dev/null) || true
  fi

  [ -n "$ERR" ] && log "fbink: $ERR"
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
if [ "$POWER_EXIT" = "1" ] && command -v lipc-wait-event > /dev/null 2>&1; then
  power_watch &
  WATCH_PID=$!
  log "press power twice within ${POWER_EXIT_WINDOW}s to stop"
else
  log "power exit unavailable, stop it over SSH or reboot"
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
