#!/usr/bin/env sh
set -eu

target_colour="${1:?Usage: switch-traffic.sh <blue|green>}"
case "$target_colour" in blue|green) ;; *) echo "Colour must be blue or green." >&2; exit 2 ;; esac

router="healthconnect-router"
target="healthconnect-$target_colour"
backup="$(mktemp)"
trap 'rm -f "$backup"' EXIT

health="$(docker inspect --format '{{.State.Health.Status}}' "$target" 2>/dev/null || true)"
[ "$health" = healthy ] || { echo "Refusing cutover: $target is not healthy." >&2; exit 1; }
docker exec "$target" wget -qO- http://127.0.0.1:3000/health >/dev/null

docker cp "$router:/etc/nginx/conf.d/default.conf" "$backup" >/dev/null
docker cp "nginx/$target_colour.conf" "$router:/etc/nginx/conf.d/default.conf" >/dev/null

if ! docker exec "$router" nginx -t; then
  docker cp "$backup" "$router:/etc/nginx/conf.d/default.conf" >/dev/null
  echo "Invalid Nginx configuration; previous route restored." >&2
  exit 1
fi

docker kill --signal HUP "$router" >/dev/null

attempt=1
while [ "$attempt" -le 15 ]; do
  response="$(docker exec "$router" wget -qO- http://127.0.0.1:8080/version 2>/dev/null || true)"
  case "$response" in
    *"\"deployment\":\"$target_colour\""*)
      echo "TRAFFIC SWITCH SUCCESSFUL: $target_colour is active."
      exit 0
      ;;
  esac
  sleep 1
  attempt=$((attempt + 1))
done

docker cp "$backup" "$router:/etc/nginx/conf.d/default.conf" >/dev/null
docker kill --signal HUP "$router" >/dev/null || true
echo "Traffic confirmation failed; previous route restored." >&2
exit 1
