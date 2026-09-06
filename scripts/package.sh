#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.1.0}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected numeric MAJOR.MINOR.PATCH version" >&2; exit 1; }
if [[ -n "${NOTARY_PROFILE:-}" && "${SIGNING_IDENTITY:-}" != 'Developer ID Application:'* ]]; then
 echo 'Notarization requires a Developer ID Application signing identity.' >&2
 exit 1
fi
APP="dist/Activity Monitor.app"
mkdir -p dist
if [[ "${USE_PREBUILT_APP:-0}" != 1 ]]; then
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ActivityMonitor"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ActivityMonitor"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ActivityMonitor</string>
<key>CFBundleIdentifier</key><string>com.wieslawsoltes.ActivityMonitor</string>
<key>CFBundleName</key><string>Activity Monitor</string>
<key>CFBundleDisplayName</key><string>Activity Monitor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Wiesław Šoltes</string>
</dict></plist>
PLIST
swift scripts/icon.swift "$APP/Contents/Resources"
else
 # Signing jobs consume the verified build artifact; no project compilation runs with credentials.
 [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
 [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")" == "$VERSION" ]]
 lipo "$APP/Contents/MacOS/ActivityMonitor" -verify_arch arm64 x86_64
 codesign --verify --deep --strict "$APP"
fi
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
 SIGNING_ARGS=(--force --timestamp)
 if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then SIGNING_ARGS+=(--keychain "$SIGNING_KEYCHAIN"); fi
 codesign --options runtime "${SIGNING_ARGS[@]}" --sign "$SIGNING_IDENTITY" "$APP"
else
 codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
 # Staple the app before building either distribution container.
 ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/notary-app.zip"
 ./scripts/notarize.sh "$STAGE/notary-app.zip" dist/notary-app.json
 xcrun stapler staple "$APP"
 xcrun stapler validate "$APP"
 SIGNING_STATUS='Developer ID-signed and Apple notarized.'
elif [[ -n "${SIGNING_IDENTITY:-}" ]]; then
 SIGNING_STATUS='Signed, but not Apple notarized.'
else
 SIGNING_STATUS='Ad-hoc signed, not Apple notarized.'
fi
printf 'Activity Monitor %s\nSigning: %s\n\n' "$VERSION" "$SIGNING_STATUS" > dist/INSTALL.md
cat INSTALL.md >> dist/INSTALL.md
# Keep notarization submissions outside the DMG staging directory.
rm -f "$STAGE/notary-app.zip"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp dist/INSTALL.md "$STAGE/Read Me.txt"
hdiutil create -volname "Activity Monitor" -srcfolder "$STAGE" -ov -format UDZO "dist/ActivityMonitor-$VERSION-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/ActivityMonitor-$VERSION-universal.zip"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
 codesign "${SIGNING_ARGS[@]}" --sign "$SIGNING_IDENTITY" "dist/ActivityMonitor-$VERSION-universal.dmg"
 ./scripts/notarize.sh "dist/ActivityMonitor-$VERSION-universal.dmg"
 xcrun stapler staple "dist/ActivityMonitor-$VERSION-universal.dmg"
 xcrun stapler validate "dist/ActivityMonitor-$VERSION-universal.dmg"
fi
(cd dist && shasum -a 256 "ActivityMonitor-$VERSION-universal.dmg" "ActivityMonitor-$VERSION-universal.zip" > SHA256SUMS)
