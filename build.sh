#!/bin/bash
# ./build.sh            build, install to ~/Applications and start at every login (LaunchAgent)
# ./build.sh uninstall  stop it and remove the app and the LaunchAgent (your to-dos stay)
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-release}"
ID="io.github.rasyachremony.TouchDo"
DEST="$HOME/Applications/TouchDo.app"
AGENT="$HOME/Library/LaunchAgents/$ID.plist"

if [ "$MODE" = uninstall ]; then
    launchctl bootout "gui/$(id -u)/$ID" 2>/dev/null || true
    pkill -f "$DEST/Contents/MacOS/TouchDo" || true   # a copy opened by hand
    defaults delete "$ID" 2>/dev/null || true             # saved keep-awake state; to-dos are kept
    rm -rf "$DEST" "$AGENT"
    rm -f "$HOME/Library/Application Support/$ID/usage.json"*
    echo "removed TouchDo (to-dos kept in ~/Library/Application Support/$ID)"
    exit 0
fi
if [ "$MODE" != release ]; then
    echo "usage: ./build.sh [uninstall]" >&2
    exit 2
fi

APP="build/TouchDo.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 main.swift Draft.swift ClaudeChat.swift Sessions.swift Plan.swift Limits.swift -o "$APP/Contents/MacOS/TouchDo"
sed "s/__BUNDLE_ID__/$ID/" Info.plist > "$APP/Contents/Info.plist"
swift icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc, but with a designated requirement on the bundle id so the Accessibility grant survives rebuilds.
codesign --force --sign - -r="designated => identifier \"$ID\"" "$APP"

launchctl bootout "gui/$(id -u)/$ID" 2>/dev/null || true
pkill -f "$DEST/Contents/MacOS/TouchDo" || true   # a copy opened by hand would make the new one exit
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$ID</string>
  <key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/TouchDo</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "installed $DEST, starts at login"
