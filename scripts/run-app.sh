#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/StillLoop.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/arm64-apple-macosx/debug/StillLoop" "$MACOS_DIR/StillLoop"
cp "$ROOT_DIR/Sources/StillLoop/Resources/StillLoop.icns" "$RESOURCES_DIR/StillLoop.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>StillLoop</string>
  <key>CFBundleIdentifier</key>
  <string>local.StillLoop.dev</string>
  <key>CFBundleName</key>
  <string>StillLoop</string>
  <key>CFBundleDisplayName</key>
  <string>StillLoop</string>
  <key>CFBundleIconFile</key>
  <string>StillLoop</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSCameraUsageDescription</key>
  <string>StillLoop uses camera availability as a local focus context signal and does not save frames.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>StillLoop uses screen availability as a local focus context signal and does not save screenshots.</string>
</dict>
</plist>
PLIST

export STILLLOOP_SKIP_MODEL_DOWNLOAD="${STILLLOOP_SKIP_MODEL_DOWNLOAD:-1}"
if [[ "${STILLLOOP_BUILD_ONLY:-0}" == "1" ]]; then
  exit 0
fi

"$MACOS_DIR/StillLoop"
