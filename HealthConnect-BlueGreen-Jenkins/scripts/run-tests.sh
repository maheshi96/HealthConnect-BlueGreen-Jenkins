#!/usr/bin/env sh
set -eu

suite="${1:?Usage: run-tests.sh <unit|integration|security> <test-image> [target-colour] [version]}"
test_image="${2:?Usage: run-tests.sh <unit|integration|security> <test-image> [target-colour] [version]}"
target_colour="${3:-}"
expected_version="${4:-}"
container="healthconnect-$suite-test-${BUILD_NUMBER:-local}"
output_name="junit-$suite.xml"

docker rm -f "$container" >/dev/null 2>&1 || true

set -- docker create --name "$container" \
  --label "healthconnect.ci.build=${BUILD_NUMBER:-local}" \
  -e JEST_JUNIT_OUTPUT_DIR=/app/reports \
  -e "JEST_JUNIT_OUTPUT_NAME=$output_name"

if [ "$suite" != unit ]; then
  [ -n "$target_colour" ] && [ -n "$expected_version" ] || {
    echo "Target colour and version are required for $suite tests." >&2
    exit 2
  }
  set -- "$@" --network healthconnect_net \
    -e "TARGET_URL=http://healthconnect-$target_colour:3000" \
    -e "EXPECTED_DEPLOYMENT=$target_colour" \
    -e "EXPECTED_VERSION=$expected_version" \
    -e "HEALTHCONNECT_API_TOKEN=${HEALTHCONNECT_API_TOKEN:-}"
fi

set -- "$@" "$test_image" npm run "test:$suite"
"$@" >/dev/null

set +e
docker start -a "$container"
test_exit=$?
set -e

mkdir -p reports
docker cp "$container:/app/reports/." reports
docker rm -f "$container" >/dev/null
exit "$test_exit"
