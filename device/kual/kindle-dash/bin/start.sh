#!/bin/sh
[ -f /tmp/kindle-dash.pid ] && kill -0 "$(cat /tmp/kindle-dash.pid)" 2>/dev/null && exit 0
nohup /mnt/us/kindle-dash/dash.sh >/dev/null 2>&1 &
