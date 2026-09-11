#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
MODE="${1:-run}"
case "$MODE" in
  run|--verify|--debug|--logs|--telemetry) ;;
  *) echo "usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
pkill -x ActivityMonitor >/dev/null 2>&1 || true
swift build
APP_BUNDLE="$PWD/dist/Activity Monitor Debug.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$(swift build --show-bin-path)/ActivityMonitor" "$APP_BUNDLE/Contents/MacOS/ActivityMonitor"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ActivityMonitor</string>
<key>CFBundleIdentifier</key><string>com.wieslawsoltes.ActivityMonitor.debug</string>
<key>CFBundleName</key><string>Activity Monitor Debug</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
case "$MODE" in
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/ActivityMonitor" ;;
  *)
    /usr/bin/open -n "$APP_BUNDLE"
    case "$MODE" in
      --verify) sleep 1; pgrep -x ActivityMonitor >/dev/null ;;
      --logs) /usr/bin/log stream --info --style compact --predicate 'process == "ActivityMonitor"' ;;
      --telemetry) /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.wieslawsoltes.ActivityMonitor"' ;;
    esac
    ;;
esac
