#!/usr/bin/env sh
set -eu

image_reference="${1:?Usage: ensure-infrastructure.sh <image-reference> <version>}"
version="${2:?Usage: ensure-infrastructure.sh <image-reference> <version>}"
export APP_IMAGE_REF="$image_reference"
export APP_VERSION="$version"

if docker inspect healthconnect-router >/dev/null 2>&1; then
  docker start healthconnect-router >/dev/null || true
  attempt=1
  while [ "$attempt" -le 20 ]; do
    if docker exec healthconnect-router wget -qO- http://127.0.0.1:8080/version >/dev/null 2>&1; then
      echo "EXISTING ROUTER READY: current production route is reachable."
      exit 0
    fi
    sleep 2
    attempt=$((attempt + 1))
  done
  echo "The existing router could not reach its current production environment." >&2
  exit 1
fi

# A blue baseline is created only on the first run. Later runs preserve live state.
if ! docker inspect healthconnect-blue >/dev/null 2>&1; then
  echo "No blue baseline exists; creating the initial known-good environment."
  docker compose up -d --no-deps blue
else
  docker start healthconnect-blue >/dev/null || true
fi

./scripts/wait-for-health.sh blue "$version"

echo "Creating the Nginx router with blue as the initial target."
docker compose up -d --no-deps --build router

attempt=1
while [ "$attempt" -le 20 ]; do
  if docker exec healthconnect-router wget -qO- http://127.0.0.1:8080/health >/dev/null 2>&1; then
    echo "BASELINE READY: router and blue environment are reachable."
    exit 0
  fi
  sleep 2
  attempt=$((attempt + 1))
done

echo "The Nginx router did not become ready." >&2
exit 1
