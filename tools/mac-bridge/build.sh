#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"
swift build -c release
app="${root}/FoloVibeBridge.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/.build/release/FoloVibeBridge" "$app/Contents/MacOS/FoloVibeBridge"
cp "$root/Info.plist" "$app/Contents/Info.plist"
echo "built $app"
echo "run: open \"$app\""
echo "grant Accessibility + Bluetooth, set Typeless dictation to F19 and mic to BlackHole 2ch"
