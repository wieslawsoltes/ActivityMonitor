#!/bin/bash
set -euo pipefail
: "${NOTARY_PROFILE:?A notarytool keychain profile is required}"
ARTIFACT="${1:?Pass the archive or disk image to notarize}"
ARGS=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then ARGS+=(--keychain "$NOTARY_KEYCHAIN"); fi
REPORT="${2:-$ARTIFACT.notary.json}"
xcrun notarytool submit "$ARTIFACT" "${ARGS[@]}" --wait --timeout 30m --output-format json > "$REPORT"
STATUS="$(plutil -extract status raw -o - "$REPORT")"
if [[ "$STATUS" != Accepted ]]; then
  SUBMISSION="$(plutil -extract id raw -o - "$REPORT")"
  xcrun notarytool log "$SUBMISSION" "${ARGS[@]}" "$REPORT.log.json" || true
  echo "Notarization was not accepted ($STATUS). See $REPORT and the adjacent log." >&2
  exit 1
fi
