#!/bin/sh
[ -f /tmp/kindle-dash.pid ] || exit 0
kill "$(cat /tmp/kindle-dash.pid)" 2>/dev/null
