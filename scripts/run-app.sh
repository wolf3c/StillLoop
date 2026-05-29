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
MLX_RUNTIME_DIR="$ROOT_DIR/.build/mlx-runtime"
BUNDLE_IDENTIFIER="local.StillLoop.dev"
CODESIGN_IDENTITY="${STILLLOOP_CODESIGN_IDENTITY:--}"
DESIGNATED_REQUIREMENT="=designated => identifier \"$BUNDLE_IDENTIFIER\""
RUN_APP_STORE_SANDBOX="${STILLLOOP_RUN_APP_STORE_SANDBOX:-0}"
ENTITLEMENTS_FILE="$ROOT_DIR/.build/StillLoop-run.generated.entitlements"
HELPER_ENTITLEMENTS_FILE="$ROOT_DIR/.build/StillLoop-run-helper.generated.entitlements"

export STILLLOOP_SKIP_MODEL_DOWNLOAD=1

cd "$ROOT_DIR"
swift build
BIN_DIR="$(swift build --show-bin-path)"
RESOURCE_BUNDLE="$BIN_DIR/StillLoop_StillLoop.bundle"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$HELPERS_DIR"
cp "$BIN_DIR/StillLoop" "$MACOS_DIR/StillLoop"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "SwiftPM resource bundle not found: $RESOURCE_BUNDLE" >&2
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
find "$RESOURCES_DIR/StillLoop_StillLoop.bundle" -type f \( -name "llama-server" -o -name "lib*.dylib" \) -delete
cp "$ROOT_DIR/Sources/StillLoop/Resources/StillLoop.icns" "$RESOURCES_DIR/StillLoop.icns"
cp "$RUNTIME_SOURCE_DIR/LICENSE.llama.cpp" "$RESOURCES_DIR/LICENSE.llama.cpp"
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

CODESIGN_ARGS=(--force --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_IDENTIFIER")
if [[ "$RUN_APP_STORE_SANDBOX" != "1" ]]; then
  CODESIGN_ARGS+=(--deep)
fi
if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  CODESIGN_ARGS+=(--requirements "$DESIGNATED_REQUIREMENT")
fi
if [[ "$RUN_APP_STORE_SANDBOX" == "1" ]]; then
  cat > "$ENTITLEMENTS_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.automation.apple-events</key>
  <true/>
  <key>com.apple.security.device.camera</key>
  <true/>
  <key>com.apple.security.network.client</key>
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
  CODESIGN_ARGS+=(--entitlements "$ENTITLEMENTS_FILE")
fi
if [[ -f "$HELPERS_DIR/$HELPER_EXECUTABLE_NAME" ]]; then
  if [[ "$RUN_APP_STORE_SANDBOX" == "1" ]]; then
    find "$HELPERS_DIR" -type f \( -name "$HELPER_EXECUTABLE_NAME" -o -name "lib*.dylib" \) -exec /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --entitlements "$HELPER_ENTITLEMENTS_FILE" {} \;
  else
    find "$HELPERS_DIR" -type f \( -name "$HELPER_EXECUTABLE_NAME" -o -name "lib*.dylib" \) -exec /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" {} \;
  fi
fi
/usr/bin/codesign "${CODESIGN_ARGS[@]}" "$APP_DIR"

if [[ "${STILLLOOP_BUILD_ONLY:-0}" == "1" ]]; then
  exit 0
fi

if [[ -x "$MLX_RUNTIME_DIR/bin/python3" ]]; then
  export PATH="$MLX_RUNTIME_DIR/bin:$PATH"
fi

OPEN_ARGS=(
  -n
  -W
  "$APP_DIR"
  --env "PATH=$PATH"
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

if [[ -n "${STILLLOOP_RUN_PROMPT_CACHE_PROBE:-}" ]]; then
  OPEN_ARGS+=(--env "STILLLOOP_RUN_PROMPT_CACHE_PROBE=$STILLLOOP_RUN_PROMPT_CACHE_PROBE")
fi

if [[ -n "${STILLLOOP_DISABLE_PROMPT_CACHE:-}" ]]; then
  OPEN_ARGS+=(--env "STILLLOOP_DISABLE_PROMPT_CACHE=$STILLLOOP_DISABLE_PROMPT_CACHE")
fi

for VAR_NAME in \
  STILLLOOP_LLAMA_CTX_SIZE \
  STILLLOOP_LLAMA_PARALLEL \
  STILLLOOP_LLAMA_BATCH_SIZE \
  STILLLOOP_LLAMA_UBATCH_SIZE \
  STILLLOOP_LLAMA_FLASH_ATTN \
  STILLLOOP_LLAMA_PROMPT_CACHE \
  STILLLOOP_LLAMA_CACHE_REUSE \
  STILLLOOP_LLAMA_CACHE_RAM
do
  if [[ -n "${!VAR_NAME:-}" ]]; then
    OPEN_ARGS+=(--env "$VAR_NAME=${!VAR_NAME}")
  fi
done

if [[ -n "${STILLLOOP_BUNDLED_RUNTIME:-}" ]]; then
  OPEN_ARGS+=(--env "STILLLOOP_BUNDLED_RUNTIME=$STILLLOOP_BUNDLED_RUNTIME")

  if [[ "$STILLLOOP_BUNDLED_RUNTIME" == "rapidMlx" ]]; then
    OPEN_ARGS+=(--env "STILLLOOP_RAPID_MLX_EXECUTABLE=$MLX_RUNTIME_DIR/bin/rapid-mlx")
    if [[ ! -x "$MLX_RUNTIME_DIR/bin/rapid-mlx" ]] && ! command -v rapid-mlx >/dev/null; then
      echo "Preparing rapid-mlx runtime under $MLX_RUNTIME_DIR"
      STILLLOOP_INSTALL_RAPID_MLX=1 "$ROOT_DIR/scripts/setup-mlx-runtime.sh"
    fi
  fi
fi

if [[ -n "${STILLLOOP_RAPID_MLX_MODEL:-}" ]]; then
  OPEN_ARGS+=(--env "STILLLOOP_RAPID_MLX_MODEL=$STILLLOOP_RAPID_MLX_MODEL")
fi

/usr/bin/open "${OPEN_ARGS[@]}"
