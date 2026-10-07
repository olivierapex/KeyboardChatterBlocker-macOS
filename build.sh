#!/bin/sh
set -e
cd "$(dirname "$0")"

# The SwiftUI macro plugins ship with Xcode, not with the Command Line Tools.
if [ -z "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

APP=build/KeyboardChatterBlocker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/"
xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macos15.0" Sources/*.swift -o "$APP/Contents/MacOS/KeyboardChatterBlocker"
codesign --force --sign - "$APP"
echo "Built $APP"
