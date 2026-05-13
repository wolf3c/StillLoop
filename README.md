# StillLoop

StillLoop is a privacy-first local macOS focus companion. It helps a user start a focus session with a concrete task, watches lightweight local context, and gives short, gentle nudges when the current activity appears to drift away.

Slogan: **跑偏？回来。**

## Requirements

- macOS 13 or later
- Xcode command line tools with Swift 5.9 or later

## Install Dependencies

No third-party dependencies are required for the current MVP.

```sh
swift package resolve
```

## Local Development

For permission testing, run the development app bundle:

```sh
STILLLOOP_SKIP_MODEL_DOWNLOAD=1 scripts/run-app.sh
```

The script wraps the SwiftPM executable as `.build/StillLoop.app`, which allows macOS privacy permissions to appear under StillLoop in System Settings.
Remove `STILLLOOP_SKIP_MODEL_DOWNLOAD=1` when you want to exercise the automatic Hugging Face model download.

For quick compiler-only launch without permission testing:

```sh
STILLLOOP_SKIP_MODEL_DOWNLOAD=1 swift run StillLoop
```

To test local model inference without using StillLoop's built-in model downloader, point StillLoop at an OpenAI-compatible local server:

```sh
STILLLOOP_SKIP_MODEL_DOWNLOAD=1 \
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
- Session summaries are stored locally under `Application Support/StillLoop/session-summaries.json`.

## Local Model And Inference

The built-in llama.cpp model is:

https://huggingface.co/mradermacher/Qwen3.5-0.8B-heretic-ara-high-kld-v3-i1-GGUF

Use the `Qwen3.5-0.8B-heretic-ara-high-kld-v3.i1-IQ4_NL.gguf` file for the local model runtime.

StillLoop stores built-in downloaded models under:

```sh
~/Library/Application Support/StillLoop/Models/
```

The llama.cpp target path is:

```sh
~/Library/Application Support/StillLoop/Models/Qwen3.5-0.8B-heretic-ara-high-kld-v3-i1-GGUF/Qwen3.5-0.8B-heretic-ara-high-kld-v3.i1-IQ4_NL.gguf
```

Current MVP behavior:

- `FocusEvaluator` remains the deterministic fallback.
- `LLMFocusEvaluator` can call any local OpenAI-compatible `/v1/chat/completions` endpoint.
- If local LLM evaluation fails, StillLoop falls back to the heuristic evaluator instead of blocking the focus session.

### LM Studio Server

In LM Studio, start the local server with OpenAI-compatible API enabled, then launch StillLoop with:

```sh
STILLLOOP_SKIP_MODEL_DOWNLOAD=1 \
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
  -m "$HOME/Library/Application Support/StillLoop/Models/Qwen3.5-0.8B-heretic-ara-high-kld-v3-i1-GGUF/Qwen3.5-0.8B-heretic-ara-high-kld-v3.i1-IQ4_NL.gguf" \
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
STILLLOOP_SKIP_MODEL_DOWNLOAD=1 \
STILLLOOP_USE_LOCAL_LLM=1 \
STILLLOOP_LLM_BASE_URL=http://127.0.0.1:17631/v1 \
STILLLOOP_LLM_MODEL=qwen3.5-0.8b-heretic-ara-high-kld-v3-i1-iq4_nl \
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
- Add a real model download and MLX inference pipeline behind the existing evaluator boundary.
- Expand `MacLocalContextProvider` with browser URL/title adapters.
- Add screenshot and camera analysis that keeps raw images in memory only.
- Add UI tests for the full start, nudge, end, and review flow.
