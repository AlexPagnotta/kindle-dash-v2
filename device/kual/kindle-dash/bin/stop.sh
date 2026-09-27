#!/bin/sh
PIDFILE=/tmp/kindle-dash.pid
[ -f "$PIDFILE" ] || exit 0
kill "$(cat "$PIDFILE")" 2>/dev/null
echo "$(date '+%Y-%m-%d %H:%M:%S') stop requested" >> /mnt/us/kindle-dash/start.log 2>/dev/null
