# StillLoop

StillLoop is a privacy-first local macOS focus companion. It helps a user start a focus session with a concrete task, watches lightweight local context, and gives short, gentle nudges when the current activity appears to drift away.

Slogan: **跑偏？回来。**

## Requirements

- macOS 13 or later
- Xcode command line tools with Swift 5.9 or later

## Install Dependencies

The app bundles a signed llama.cpp `llama-server` runtime for the built-in model path. Swift package resolution is still enough for source builds.

```sh
swift package resolve
```

## Local Development

For permission testing, run the development app bundle:

```sh
scripts/run-app.sh
```

The script wraps the SwiftPM executable as `.build/StillLoop.app`, which allows macOS privacy permissions to appear under StillLoop in System Settings.

For quick compiler-only launch without permission testing:

```sh
swift run StillLoop
```

To test local model inference, point StillLoop at an OpenAI-compatible local server:

```sh
STILLLOOP_USE_LOCAL_LLM=1 \
STILLLOOP_LLM_BASE_URL=http://127.0.0.1:1234/v1 \
STILLLOOP_LLM_MODEL=local-model \
scripts/run-app.sh
```

## Build And Test

```sh
swift build
swift test
```

## Mac App Store Packaging

StillLoop is currently a SwiftPM macOS app. App Store Connect submission needs an App Store app record, an accepted Apple Developer Program agreement, a registered bundle ID, and Mac App Store signing identities installed in the local keychain.

Build a signed App Store `.pkg` after those prerequisites are ready:

```sh
STILLLOOP_BUNDLE_IDENTIFIER=com.super-tree.stillloop \
STILLLOOP_APP_SIGN_IDENTITY="Apple Distribution: Example Team (TEAMID)" \
STILLLOOP_INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: Example Team (TEAMID)" \
STILLLOOP_PROVISIONING_PROFILE="$HOME/Downloads/StillLoop_App_Store.provisionprofile" \
STILLLOOP_MARKETING_VERSION=1.0 \
STILLLOOP_BUNDLE_VERSION=1 \
scripts/build-app-store-package.sh
```

Increment `STILLLOOP_BUNDLE_VERSION` for each App Store Connect upload, including replacements after a failed processing attempt.

The package script embeds the Mac App Store provisioning profile, signs the application identifier entitlement, clears downloaded-file quarantine attributes from the app bundle, and applies the sandbox capabilities from `Config/StillLoop-AppStore.entitlements`. Screen recording still uses the system Screen Recording permission prompt and requires clear user consent in the app and App Review notes.

## MVP Flow

1. Open StillLoop.
2. Continue through the welcome and permission guide.
3. Enter one current task.
4. Start a focus session.
5. Watch the focus screen update the current state, latest local context, last nudge, and timeline.
6. Pause, resume, or end the focus period.
7. Review total duration, estimated focused duration, off-track events, nudges, feedback, and common app statistics.

The task setup screen includes a `使用模拟上下文` toggle. Keep it enabled for a deterministic demo, or disable it to use the macOS local context provider.

## Architecture

- `Sources/StillLoopCore/ContextProvider.swift`: replacable context capture protocol and mock provider.
- `Sources/StillLoop/MacLocalContextProvider.swift`: macOS provider for frontmost app, best-effort window title, screenshot availability, and camera permission status.
- `Sources/StillLoopCore/FocusEvaluator.swift`: local heuristic focus evaluator.
- `Sources/StillLoopCore/NudgeGenerator.swift`: short, gentle nudge text generation.
- `Sources/StillLoopCore/SessionStore.swift`: local JSON session summary storage.
- `Sources/StillLoop/AppModel.swift`: session lifecycle, timer, notification dispatch, and screen state.
- `Sources/StillLoop/StillLoopView.swift`: SwiftUI welcome, permissions, task setup, focus, review, and privacy screens.
- `Sources/StillLoop/AppDelegate.swift`: macOS menu-bar status item.

## Privacy Model

- No cloud AI calls.
- No cloud sync.
- No employee monitoring or team dashboard.
- No app or website blocking.
- Screenshots are captured in memory, downscaled, compressed, summarized, and then discarded; original screenshots are not written to disk.
- Camera photos are captured in memory, downscaled, compressed, summarized, and then discarded; original frames are not written to disk.
- Session summaries and evaluation events are stored locally under `Application Support/StillLoop/session-summaries.json` and `Application Support/StillLoop/session-events.json`; images, photos, and screenshots are not written to disk.

## Local Model And Inference

The built-in llama.cpp model is:

https://huggingface.co/twinblade02/Qwen3.5VL-0.8B-ImageExplainer-GGUF

Use both files for the local model runtime:

- `Qwen3.5-0.8B-Base.Q4_K_M.gguf`
- `Qwen3.5-0.8B-Base.BF16-mmproj.gguf`

StillLoop stores built-in downloaded models under:

```sh
~/Library/Application Support/StillLoop/Models/
```

The llama.cpp target path is:

```sh
~/Library/Application Support/StillLoop/Models/Qwen3.5VL-0.8B-ImageExplainer-GGUF/Qwen3.5-0.8B-Base.Q4_K_M.gguf
~/Library/Application Support/StillLoop/Models/Qwen3.5VL-0.8B-ImageExplainer-GGUF/Qwen3.5-0.8B-Base.BF16-mmproj.gguf
```

Current runtime behavior:

- `FocusEvaluator` remains the deterministic fallback.
- When the built-in model is selected, StillLoop starts the bundled `stillloop-llama-server` helper during a focus session, preferring `http://127.0.0.1:17631/v1` and automatically trying ports through `17640` if needed.
- Runtime readiness requires both text completion and an image-input probe. If the bundled model cannot accept `image_url`, StillLoop reports the built-in runtime as unavailable and falls back to the heuristic evaluator.
- `LLMFocusEvaluator` can still call any user-configured OpenAI-compatible `/v1/chat/completions` endpoint when manual model configuration is selected.
- If model evaluation fails, StillLoop falls back to the heuristic evaluator instead of blocking the focus session.

The bundled runtime files live under `Sources/StillLoop/Resources/Runtime/` and are copied into `Contents/Helpers/stillloop-llama-server` by the development and App Store packaging scripts. The included llama.cpp binary package is the macOS arm64 `b9060` release from `ggml-org/llama.cpp`; keep `LICENSE.llama.cpp` with the runtime files.

### LM Studio Server

In LM Studio, start the local server with OpenAI-compatible API enabled, then launch StillLoop with:

```sh
STILLLOOP_USE_LOCAL_LLM=1 \
STILLLOOP_LLM_BASE_URL=http://127.0.0.1:17631/v1 \
STILLLOOP_LLM_MODEL=qwen3.5-0.8b \
scripts/run-app.sh
```

`STILLLOOP_LLM_MODEL` only needs to match what the local server accepts.

### llama.cpp Server

After installing or building llama.cpp, run:

```sh
llama-server \
  -m "$HOME/Library/Application Support/StillLoop/Models/Qwen3.5VL-0.8B-ImageExplainer-GGUF/Qwen3.5-0.8B-Base.Q4_K_M.gguf" \
  --mmproj "$HOME/Library/Application Support/StillLoop/Models/Qwen3.5VL-0.8B-ImageExplainer-GGUF/Qwen3.5-0.8B-Base.BF16-mmproj.gguf" \
  --host 127.0.0.1 \
  --port 17631 \
  --ctx-size 32768 \
  --parallel 1 \
  --n-gpu-layers 99 \
  --cache-type-k f16 \
  --cache-type-v f16
```

Then launch StillLoop:

```sh
STILLLOOP_USE_LOCAL_LLM=1 \
STILLLOOP_LLM_BASE_URL=http://127.0.0.1:17631/v1 \
STILLLOOP_LLM_MODEL=Qwen3.5-0.8B-Base.Q4_K_M.gguf \
scripts/run-app.sh
```

## Current Limitations

- Browser page title and URL are not yet read from browser automation APIs.
- The evaluator falls back to a transparent heuristic when no local HTTP model server is enabled or reachable.
- Camera support is limited to permission/status signaling in the MVP.
- The SwiftPM executable is a development build, not a signed `.app` distribution.
- Notification delivery depends on macOS notification permission.

## Next Steps

- Add a signed Xcode app target and app icon.
- Continue improving bundled model quality and local inference latency behind the existing evaluator boundary.
- Expand `MacLocalContextProvider` with browser URL/title adapters.
- Add screenshot and camera analysis that keeps raw images in memory only.
- Add UI tests for the full start, nudge, end, and review flow.
