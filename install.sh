#!/bin/sh
set -e
cd "$(dirname "$0")"

LABEL=local.KeyboardChatterBlocker
APP=/Applications/KeyboardChatterBlocker.app
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

./build.sh

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x KeyboardChatterBlocker 2>/dev/null || true

rm -rf "$APP"
cp -R build/KeyboardChatterBlocker.app "$APP"

mkdir -p "$(dirname "$AGENT")"
cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/KeyboardChatterBlocker</string>
        <string>--background</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "Installed $APP and started it with launch agent $LABEL"
