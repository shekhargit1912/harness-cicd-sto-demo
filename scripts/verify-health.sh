#!/usr/bin/env bash
# Post-deploy validation: poll the app's /health endpoint until it returns
# HTTP 200, or fail after a fixed number of retries. Used both for manual
# local testing (after `kubectl port-forward`) and as a Harness pipeline step.
set -uo pipefail

URL="${HEALTH_URL:-http://localhost:8080/health}"
MAX_RETRIES="${MAX_RETRIES:-10}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-3}"

echo "Checking ${URL} (up to ${MAX_RETRIES} attempts, ${RETRY_DELAY_SECONDS}s apart)"

for attempt in $(seq 1 "$MAX_RETRIES"); do
  status=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
  if [ "$status" = "200" ]; then
    echo "Attempt ${attempt}: OK (HTTP ${status})"
    exit 0
  fi
  echo "Attempt ${attempt}: got HTTP ${status:-none}, retrying in ${RETRY_DELAY_SECONDS}s..."
  sleep "$RETRY_DELAY_SECONDS"
done

echo "FAILED: ${URL} did not return HTTP 200 after ${MAX_RETRIES} attempts"
exit 1
