#!/usr/bin/env sh
set -eu

target_colour="${1:?Usage: run-zap.sh <blue|green> <zap-image>}"
zap_image="${2:?Usage: run-zap.sh <blue|green> <zap-image>}"
container="healthconnect-zap-${BUILD_NUMBER:-local}"

docker rm -f "$container" >/dev/null 2>&1 || true
docker create --name "$container" \
  --label "healthconnect.ci.build=${BUILD_NUMBER:-local}" \
  --network healthconnect_net \
  "$zap_image" \
  zap-baseline.py \
  -t "http://healthconnect-$target_colour:3000" \
  -c zap-baseline.conf \
  -r zap-report.html \
  -J zap-report.json >/dev/null

set +e
docker start -a "$container"
zap_exit=$?
set -e

mkdir -p reports
docker cp "$container:/zap/wrk/zap-report.html" reports/zap-report.html
docker cp "$container:/zap/wrk/zap-report.json" reports/zap-report.json
docker rm -f "$container" >/dev/null

# ZAP baseline: 0 = pass, 1 = policy FAIL, 2 = warnings only, 3 = scan error.
if [ "$zap_exit" -eq 1 ] || [ "$zap_exit" -eq 3 ]; then
  echo "OWASP ZAP failed with exit code $zap_exit." >&2
  exit "$zap_exit"
fi

if [ "$zap_exit" -eq 2 ]; then
  echo "OWASP ZAP completed with reviewed warnings and no blocking failures."
else
  echo "OWASP ZAP baseline passed."
fi
