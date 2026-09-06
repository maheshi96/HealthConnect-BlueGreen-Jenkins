#!/usr/bin/env sh
set -eu

colour="${1:?Usage: wait-for-health.sh <blue|green> <expected-version>}"
expected_version="${2:?Usage: wait-for-health.sh <blue|green> <expected-version>}"
container="healthconnect-$colour"

attempt=1
while [ "$attempt" -le 30 ]; do
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null || true)"
  response="$(docker exec "$container" wget -qO- http://127.0.0.1:3000/health 2>/dev/null || true)"

  case "$response" in
    *"\"deployment\":\"$colour\""*"\"version\":\"$expected_version\""*)
      if [ "$health" = healthy ]; then
        echo "HEALTH CHECK PASSED: $colour version $expected_version"
        exit 0
      fi
      ;;
  esac

  echo "Health attempt $attempt/30 for $container: $health"
  sleep 2
  attempt=$((attempt + 1))
done

docker logs --tail 100 "$container" || true
echo "Health check failed for $container." >&2
exit 1
