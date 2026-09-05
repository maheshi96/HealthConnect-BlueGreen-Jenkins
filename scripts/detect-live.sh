#!/usr/bin/env sh
set -eu

router="healthconnect-router"
docker inspect "$router" >/dev/null 2>&1 || {
  echo "HealthConnect router is not running." >&2
  exit 1
}

response="$(docker exec "$router" wget -qO- http://127.0.0.1:8080/version 2>/dev/null || true)"
case "$response" in
  *'"deployment":"blue"'*) printf '%s\n' blue; exit 0 ;;
  *'"deployment":"green"'*) printf '%s\n' green; exit 0 ;;
esac

configuration="$(docker exec "$router" cat /etc/nginx/conf.d/default.conf 2>/dev/null || true)"
case "$configuration" in
  *healthconnect-blue*) printf '%s\n' blue ;;
  *healthconnect-green*) printf '%s\n' green ;;
  *) echo "Unable to determine the active environment." >&2; exit 1 ;;
esac
