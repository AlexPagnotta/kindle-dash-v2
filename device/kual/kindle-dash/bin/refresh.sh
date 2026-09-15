#!/bin/sh
# Forces one redraw without waiting for the next cycle
[ -f /tmp/kindle-dash.pid ] && kill -USR1 "$(cat /tmp/kindle-dash.pid)" 2>/dev/null
