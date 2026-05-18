#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/StillLoop.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
RUNTIME_SOURCE_DIR="$ROOT_DIR/Sources/StillLoop/Resources/Runtime"
RUNTIME_SOURCE="$ROOT_DIR/Sources/StillLoop/Resources/Runtime/llama-server"
HELPER_EXECUTABLE_NAME="stillloop-llama-server"
BUNDLE_IDENTIFIER="local.StillLoop.dev"
CODESIGN_IDENTITY="${STILLLOOP_CODESIGN_IDENTITY:--}"
DESIGNATED_REQUIREMENT="=designated => identifier \"$BUNDLE_IDENTIFIER\""

export STILLLOOP_SKIP_MODEL_DOWNLOAD=1

cd "$ROOT_DIR"
swift build

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$HELPERS_DIR"
cp "$ROOT_DIR/.build/arm64-apple-macosx/debug/StillLoop" "$MACOS_DIR/StillLoop"
cp "$ROOT_DIR/Sources/StillLoop/Resources/StillLoop.icns" "$RESOURCES_DIR/StillLoop.icns"
if [[ -f "$RUNTIME_SOURCE" ]]; then
  cp "$RUNTIME_SOURCE" "$HELPERS_DIR/$HELPER_EXECUTABLE_NAME"
  cp -R "$RUNTIME_SOURCE_DIR"/lib*.dylib "$HELPERS_DIR"/
  find "$HELPERS_DIR" -type f \( -name "$HELPER_EXECUTABLE_NAME" -o -name "lib*.dylib" \) -exec chmod 755 {} \;
else
  echo "Warning: bundled llama-server not found at $RUNTIME_SOURCE" >&2
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>StillLoop</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_IDENTIFIER</string>
  <key>CFBundleName</key>
  <string>StillLoop Dev</string>
  <key>CFBundleDisplayName</key>
  <string>StillLoop Dev</string>
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
  <key>NSAppleEventsUsageDescription</key>
  <string>StillLoop reads the active browser tab title and URL as local focus context when available.</string>
</dict>
</plist>
PLIST

CODESIGN_ARGS=(--force --deep --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_IDENTIFIER")
if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  CODESIGN_ARGS+=(--requirements "$DESIGNATED_REQUIREMENT")
fi
if [[ -f "$HELPERS_DIR/$HELPER_EXECUTABLE_NAME" ]]; then
  find "$HELPERS_DIR" -type f \( -name "$HELPER_EXECUTABLE_NAME" -o -name "lib*.dylib" \) -exec /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" {} \;
fi
/usr/bin/codesign "${CODESIGN_ARGS[@]}" "$APP_DIR"

if [[ "${STILLLOOP_BUILD_ONLY:-0}" == "1" ]]; then
  exit 0
fi

OPEN_ARGS=(
  -n
  -W
  "$APP_DIR"
  --env "STILLLOOP_SKIP_MODEL_DOWNLOAD=$STILLLOOP_SKIP_MODEL_DOWNLOAD"
)

if [[ -n "${STILLLOOP_USE_LOCAL_LLM:-}" ]]; then
  OPEN_ARGS+=(--env "STILLLOOP_USE_LOCAL_LLM=$STILLLOOP_USE_LOCAL_LLM")
fi

if [[ -n "${STILLLOOP_LLM_BASE_URL:-}" ]]; then
  OPEN_ARGS+=(--env "STILLLOOP_LLM_BASE_URL=$STILLLOOP_LLM_BASE_URL")
fi

if [[ -n "${STILLLOOP_LLM_MODEL:-}" ]]; then
  OPEN_ARGS+=(--env "STILLLOOP_LLM_MODEL=$STILLLOOP_LLM_MODEL")
fi

/usr/bin/open "${OPEN_ARGS[@]}"
