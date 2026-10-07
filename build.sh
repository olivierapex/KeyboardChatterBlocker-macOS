#!/bin/sh
set -e
cd "$(dirname "$0")"

APP=build/KeyboardChatterBlocker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/"
xcrun swiftc -O -target "$(uname -m)-apple-macos15.0" Sources/*.swift -o "$APP/Contents/MacOS/KeyboardChatterBlocker"
codesign --force --sign - "$APP"
echo "Built $APP"
