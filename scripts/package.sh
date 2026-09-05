#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected numeric MAJOR.MINOR.PATCH version" >&2; exit 1; }
APP="dist/Activity Monitor.app"
mkdir -p dist
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
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Wiesław Šoltes</string>
</dict></plist>
PLIST
swift scripts/icon.swift "$APP/Contents/Resources"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
 codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
 codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp INSTALL.md "$STAGE/Read Me.txt"
hdiutil create -volname "Activity Monitor" -srcfolder "$STAGE" -ov -format UDZO "dist/ActivityMonitor-$VERSION-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/ActivityMonitor-$VERSION-universal.zip"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
 xcrun notarytool submit "dist/ActivityMonitor-$VERSION-universal.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
 xcrun stapler staple "dist/ActivityMonitor-$VERSION-universal.dmg"
fi
(cd dist && shasum -a 256 "ActivityMonitor-$VERSION-universal.dmg" "ActivityMonitor-$VERSION-universal.zip" > SHA256SUMS)
