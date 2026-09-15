#!/bin/sh
# One-time setup on a ZimaOS box, after cloning the repo to /DATA/AppData/kindle-dash.
# Run it there: ssh <box> /DATA/AppData/kindle-dash/deploy/init.sh
# Safe to re-run: it skips whatever is already in place.

set -e

APP=kindle-dash
ROOT=/DATA/AppData/$APP
REGISTRY_DATA=/DATA/AppData/registry/data

# ZimaOS points $HOME at a root-owned /DATA, so the Docker CLI plugins need a config it can read
export DOCKER_CONFIG=$ROOT/.docker
mkdir -p "$DOCKER_CONFIG"

if docker ps -a --format '{{.Names}}' | grep -qx registry; then
  echo "registry container already exists"
else
  echo "Starting a registry on port 5000, the ZimaOS UI can only install images it can pull"
  mkdir -p "$REGISTRY_DATA"
  docker run -d --name registry --restart unless-stopped -p 5000:5000 \
    -v "$REGISTRY_DATA:/var/lib/registry" registry:2 > /dev/null
  sleep 3
fi

curl -sf http://127.0.0.1:5000/v2/ > /dev/null || {
  echo "Registry is not answering on port 5000" >&2
  exit 1
}

"$ROOT/deploy/update.sh"

cat <<TXT

Next, in the ZimaOS UI: Apps -> "+" -> Install a customized app, and import
  $ROOT/deploy/zimaos.compose.yml
TXT
