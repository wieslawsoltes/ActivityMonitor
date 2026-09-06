#!/bin/bash
set -euo pipefail
set +x
umask 077
: "${RUNNER_TEMP:?GitHub runner temporary directory is required}"
: "${GITHUB_ENV:?GitHub environment file is required}"
: "${DEVELOPER_ID_P12_BASE64:?Missing Developer ID certificate}"
: "${DEVELOPER_ID_P12_PASSWORD:?Missing certificate password}"
: "${DEVELOPER_ID_IDENTITY:?Missing Developer ID identity}"
: "${APP_STORE_CONNECT_KEY_P8:?Missing notarization API private key}"
: "${APP_STORE_CONNECT_KEY_ID:?Missing notarization API key ID}"
: "${APP_STORE_CONNECT_ISSUER_ID:?Missing notarization API issuer ID}"
[[ "$DEVELOPER_ID_IDENTITY" == 'Developer ID Application:'* ]] || { echo 'Expected a Developer ID Application identity' >&2; exit 1; }
[[ "$DEVELOPER_ID_IDENTITY" != *$'\n'* && "$DEVELOPER_ID_IDENTITY" != *$'\r'* ]] || exit 1
KEYCHAIN_PATH="$RUNNER_TEMP/activity-monitor-signing.keychain-db"
CERTIFICATE_PATH="$RUNNER_TEMP/activity-monitor-certificate.p12"
API_KEY_PATH="$RUNNER_TEMP/activity-monitor-notary.p8"
KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
echo "::add-mask::$KEYCHAIN_PASSWORD"
printf '%s' "$DEVELOPER_ID_P12_BASE64" | base64 --decode > "$CERTIFICATE_PATH"
printf '%s' "$APP_STORE_CONNECT_KEY_P8" > "$API_KEY_PATH"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 7200 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
xcrun notarytool store-credentials activity-monitor-ci --keychain "$KEYCHAIN_PATH" \
  --key "$API_KEY_PATH" --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID"
rm -f "$CERTIFICATE_PATH" "$API_KEY_PATH"
{
  echo "SIGNING_IDENTITY=$DEVELOPER_ID_IDENTITY"
  echo "SIGNING_KEYCHAIN=$KEYCHAIN_PATH"
  echo 'NOTARY_PROFILE=activity-monitor-ci'
  echo "NOTARY_KEYCHAIN=$KEYCHAIN_PATH"
} >> "$GITHUB_ENV"
