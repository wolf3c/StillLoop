#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${STILLLOOP_APP_STORE_OUTPUT_DIR:-$ROOT_DIR/.build/app-store}"
APP_DIR="$OUTPUT_DIR/StillLoop.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
RUNTIME_SOURCE_DIR="$ROOT_DIR/Sources/StillLoop/Resources/Runtime"
RUNTIME_SOURCE="$ROOT_DIR/Sources/StillLoop/Resources/Runtime/llama-server"
STATIC_ENTITLEMENTS_FILE="$ROOT_DIR/Config/StillLoop-AppStore.entitlements"
ENTITLEMENTS_FILE="$OUTPUT_DIR/StillLoop-AppStore.generated.entitlements"
HELPER_ENTITLEMENTS_FILE="$OUTPUT_DIR/StillLoop-Helper.generated.entitlements"

: "${STILLLOOP_APP_SIGN_IDENTITY:?Set STILLLOOP_APP_SIGN_IDENTITY to the Mac App Store app signing identity}"
: "${STILLLOOP_INSTALLER_SIGN_IDENTITY:?Set STILLLOOP_INSTALLER_SIGN_IDENTITY to the Mac App Store installer signing identity}"
: "${STILLLOOP_PROVISIONING_PROFILE:?Set STILLLOOP_PROVISIONING_PROFILE to the downloaded Mac App Store provisioning profile path}"

BUNDLE_IDENTIFIER="${STILLLOOP_BUNDLE_IDENTIFIER:-com.super-tree.stillloop}"
TEAM_IDENTIFIER="${STILLLOOP_TEAM_IDENTIFIER:-FUNQ8PQ8CX}"
MARKETING_VERSION="${STILLLOOP_MARKETING_VERSION:-1.0}"
BUNDLE_VERSION="${STILLLOOP_BUNDLE_VERSION:-1}"
APP_CATEGORY="${STILLLOOP_APP_CATEGORY:-public.app-category.productivity}"
PKG_PATH="$OUTPUT_DIR/StillLoop-$MARKETING_VERSION.pkg"

cd "$ROOT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

if [[ ! -f "$STILLLOOP_PROVISIONING_PROFILE" ]]; then
  echo "Provisioning profile not found: $STILLLOOP_PROVISIONING_PROFILE" >&2
  exit 1
fi

rm -rf "$APP_DIR" "$PKG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$HELPERS_DIR"
plutil -lint "$STATIC_ENTITLEMENTS_FILE" >/dev/null
cp "$BIN_DIR/StillLoop" "$MACOS_DIR/StillLoop"
cp "$ROOT_DIR/Sources/StillLoop/Resources/StillLoop.icns" "$RESOURCES_DIR/StillLoop.icns"
if [[ ! -f "$RUNTIME_SOURCE" ]]; then
  echo "Bundled llama-server not found: $RUNTIME_SOURCE" >&2
  exit 1
fi
cp "$RUNTIME_SOURCE" "$HELPERS_DIR/llama-server"
cp -R "$RUNTIME_SOURCE_DIR"/lib*.dylib "$HELPERS_DIR"/
find "$HELPERS_DIR" -type f \( -name "llama-server" -o -name "lib*.dylib" \) -exec chmod 755 {} \;
cp "$STILLLOOP_PROVISIONING_PROFILE" "$CONTENTS_DIR/embedded.provisionprofile"

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
  <string>StillLoop</string>
  <key>CFBundleDisplayName</key>
  <string>StillLoop</string>
  <key>CFBundleIconFile</key>
  <string>StillLoop</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>$BUNDLE_VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>$APP_CATEGORY</string>
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

cat > "$ENTITLEMENTS_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.application-identifier</key>
  <string>$TEAM_IDENTIFIER.$BUNDLE_IDENTIFIER</string>
  <key>com.apple.developer.team-identifier</key>
  <string>$TEAM_IDENTIFIER</string>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.automation.apple-events</key>
  <true/>
  <key>com.apple.security.device.camera</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.network.server</key>
  <true/>
</dict>
</plist>
PLIST
plutil -lint "$ENTITLEMENTS_FILE" >/dev/null
cat > "$HELPER_ENTITLEMENTS_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.inherit</key>
  <true/>
</dict>
</plist>
PLIST
plutil -lint "$HELPER_ENTITLEMENTS_FILE" >/dev/null
/usr/bin/xattr -cr "$APP_DIR"
find "$HELPERS_DIR" -type f \( -name "llama-server" -o -name "lib*.dylib" \) -exec /usr/bin/codesign --force --options runtime --sign "$STILLLOOP_APP_SIGN_IDENTITY" --entitlements "$HELPER_ENTITLEMENTS_FILE" {} \;
/usr/bin/codesign --force --deep --options runtime --sign "$STILLLOOP_APP_SIGN_IDENTITY" --entitlements "$ENTITLEMENTS_FILE" "$APP_DIR"
/usr/bin/codesign --verify --strict --deep --verbose=2 "$APP_DIR"
/usr/bin/productbuild --sign "$STILLLOOP_INSTALLER_SIGN_IDENTITY" --component "$APP_DIR" /Applications "$PKG_PATH"

echo "Built $PKG_PATH"
