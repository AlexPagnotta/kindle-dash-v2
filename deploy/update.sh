#!/bin/sh
# Rebuilds the image on the box and restarts the ZimaOS app.
# Run it there: ssh <box> /DATA/AppData/kindle-dash/deploy/update.sh

set -e

APP=kindle-dash
ROOT=/DATA/AppData/$APP
IMAGE=localhost:5000/$APP:latest
COMPOSE=/var/lib/casaos/apps/$APP/docker-compose.yml

# ZimaOS points $HOME at a root-owned /DATA, so the Docker CLI plugins need a config it can read
export DOCKER_CONFIG=$ROOT/.docker

cd "$ROOT"
git pull

docker build -t "$IMAGE" .
docker push "$IMAGE"

if [ -f "$COMPOSE" ]; then
  docker compose -f "$COMPOSE" up -d --force-recreate
  echo "Updated and restarted $APP"
else
  echo "Image published. Install the app from the ZimaOS UI first, then this will restart it too."
fi
