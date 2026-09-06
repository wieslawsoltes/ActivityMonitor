#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.1.0}"
APP='dist/Activity Monitor.app'
for ARCH in arm64 x86_64; do
  lipo "$APP/Contents/MacOS/ActivityMonitor" -verify_arch "$ARCH"
done
codesign --verify --deep --strict "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")" == "$VERSION" ]]
(cd dist && shasum -a 256 -c SHA256SUMS)
hdiutil verify "dist/ActivityMonitor-$VERSION-universal.dmg"
STAGE="$(mktemp -d)"
MOUNT="$STAGE/mount"
cleanup() {
  hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
  rm -rf "$STAGE"
}
trap cleanup EXIT
hdiutil attach "dist/ActivityMonitor-$VERSION-universal.dmg" -readonly -nobrowse -mountpoint "$MOUNT"
[[ "$(readlink "$MOUNT/Applications")" == /Applications ]]
cmp INSTALL.md "$MOUNT/Read Me.txt"
codesign --verify --deep --strict "$MOUNT/Activity Monitor.app"
cmp "$APP/Contents/MacOS/ActivityMonitor" "$MOUNT/Activity Monitor.app/Contents/MacOS/ActivityMonitor"
ditto -x -k "dist/ActivityMonitor-$VERSION-universal.zip" "$STAGE/zip"
codesign --verify --deep --strict "$STAGE/zip/Activity Monitor.app"
cmp "$APP/Contents/MacOS/ActivityMonitor" "$STAGE/zip/Activity Monitor.app/Contents/MacOS/ActivityMonitor"
echo 'Universal app, DMG, ZIP, version and checksums verified.'
