#!/usr/bin/env sh
set -eu

expected_colour="${1:?Usage: smoke-test.sh <colour> <version>}"
expected_version="${2:?Usage: smoke-test.sh <colour> <version>}"

attempt=1
while [ "$attempt" -le 10 ]; do
  response="$(docker exec healthconnect-router wget -qO- http://127.0.0.1:8080/version 2>/dev/null || true)"
  case "$response" in
    *"\"deployment\":\"$expected_colour\""*"\"version\":\"$expected_version\""*)
      echo "POST-DEPLOYMENT SMOKE TEST PASSED: $expected_colour version $expected_version"
      exit 0
      ;;
  esac
  sleep 1
  attempt=$((attempt + 1))
done

echo "Post-deployment smoke test failed for $expected_colour version $expected_version." >&2
exit 1
