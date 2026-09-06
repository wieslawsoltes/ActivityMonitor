#!/bin/bash
set -euo pipefail
set +x
: "${RUNNER_TEMP:?GitHub runner temporary directory is required}"
trap 'rm -f "$RUNNER_TEMP/activity-monitor-certificate.p12" "$RUNNER_TEMP/activity-monitor-notary.p8"' EXIT
KEYCHAIN_PATH="$RUNNER_TEMP/activity-monitor-signing.keychain-db"
if [[ -f "$KEYCHAIN_PATH" ]]; then
  security delete-keychain "$KEYCHAIN_PATH"
fi
