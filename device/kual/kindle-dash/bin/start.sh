#!/bin/sh
# Launched by KUAL. Logs to start.log, since KUAL shows nothing when a menu action fails.
ROOT=/mnt/us/kindle-dash
LOG=$ROOT/start.log
PIDFILE=/tmp/kindle-dash.pid

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null; }

say "start requested"

if [ -f "$PIDFILE" ]; then
  PID=$(cat "$PIDFILE" 2>/dev/null)
  # A stale pidfile used to block every later start with no sign of it anywhere
  if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
    say "already running as $PID, restarting it"
    kill "$PID" 2>/dev/null
    sleep 2
    kill -9 "$PID" 2>/dev/null
  fi
  rm -f "$PIDFILE"
fi

# Through sh, so a missing exec bit on FAT cannot stop it
nohup sh "$ROOT/dash.sh" >> "$LOG" 2>&1 &
say "launched pid $!"
