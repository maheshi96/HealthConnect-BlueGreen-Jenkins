#!/usr/bin/env sh
set -eu

previous="${1:?Usage: rollback.sh <previous-colour> <failed-colour>}"
failed="${2:?Usage: rollback.sh <previous-colour> <failed-colour>}"
mkdir -p reports

printf '%s ROLLBACK STARTED: %s -> %s\n' "$(date -u +%FT%TZ)" "$failed" "$previous" | tee -a reports/rollback.log
./scripts/switch-traffic.sh "$previous"
docker stop "healthconnect-$failed" >/dev/null || true
printf '%s ROLLBACK SUCCESSFUL: %s restored; %s stopped\n' "$(date -u +%FT%TZ)" "$previous" "$failed" | tee -a reports/rollback.log
