#!/bin/sh
# Rebuilds the image on the box and recreates the running app.
# Run it there: ssh <box> /DATA/AppData/kindle-dash/deploy/update.sh

set -e

APP=kindle-dash
ROOT=/DATA/AppData/$APP
REGISTRY_IMAGE=localhost:5000/$APP:latest
LOCAL_IMAGE=$APP:local

# ZimaOS points $HOME at a root-owned /DATA, so the Docker CLI plugins need a config it can read
export DOCKER_CONFIG=$ROOT/.docker

cd "$ROOT"
git pull

# Both tags, because an app installed from the UI may reference either one
docker build -t "$REGISTRY_IMAGE" -t "$LOCAL_IMAGE" .
docker push "$REGISTRY_IMAGE"

# The ZimaOS UI names the compose project itself, so ask the container where its compose file is
PROJECT=$(docker inspect "$APP" -f '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || true)
CONFIG=$(docker inspect "$APP" -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null || true)

if [ -z "$CONFIG" ]; then
  echo "Image published. Install the app from the ZimaOS UI first, then this will recreate it too."
  exit 0
fi

COMPOSE=$CONFIG
if [ ! -r "$CONFIG" ]; then
  # Those files are root-only, and sudo needs a password here, so read it through a container
  COMPOSE=$ROOT/.cache/casaos-compose.yml
  mkdir -p "$ROOT/.cache"
  docker run --rm -v "$(dirname "$CONFIG")":/app:ro alpine:3 \
    cat "/app/$(basename "$CONFIG")" > "$COMPOSE"
fi

docker compose -p "$PROJECT" -f "$COMPOSE" up -d --force-recreate
echo "Updated and recreated $APP (compose project: $PROJECT)"
