# Repository Guidelines

## Project Scope

StillLoop is a macOS app project. Keep repository guidance focused on native app work unless the user explicitly adds another runtime or service. Do not introduce web, server, or SDK scaffolding without a concrete request.

## Project Structure

Use the native project layout once app files are added:

- App source should live in the Xcode project or Swift package structure chosen for the app.
- Keep reusable domain logic separate from view code when practical.
- Keep tests next to the owning target or in the matching test target.
- Store product notes or implementation plans in `docs/` only when the task needs durable documentation.

Avoid relying on generated files, local IDE state, or machine-specific paths as project source.

## Agent Workflow Guardrails

- The user may provide multiple requirements in one message. Unless there is an obvious dependency, decompose them and execute in parallel where safe, including using subagents for disjoint subtasks.
- For independent subtasks, prefer dispatching them to separate subagents and merge only the results that do not overlap files or flow assumptions.
- Start every functional adjustment from the relevant product documentation, so the intended behavior, user-facing contract, and code stay aligned throughout the task.
- Reflect carefully on every requirement and proposed change before implementation. If requirements, existing product behavior, documentation, or technical constraints conflict, stop and confirm the tradeoff with the user before editing production code.
- Implement behavior changes with TDD: write or update a focused failing test first, confirm it fails for the expected reason, then make the smallest production change that turns it green.
- When testing is complete and a test app is running, do not close it immediately. Tell the user it is ready for their manual test, keep it running, and close it only after the user confirms the behavior passed.
- After finishing an implementation item (done + verified), commit directly unless the user explicitly asks to delay it.

## Error Ledger

Add entries here only when a mistake reveals a reusable rule for future work.

- `YYYY-MM-DD`: What went wrong. Root cause. Future rule to prevent recurrence.
- `2026-05-13`: Added only a prose testing constraint without a runnable command. Root cause: documented intent but not the exact agent action. Future rule: when test configuration is requested, include the concrete command or environment variables agents should run.
- `2026-05-13`: Left the new skip-download launch setting out of this guide. Root cause: updated the script and test but not the reusable agent instructions. Future rule: when changing development or testing commands, update `AGENTS.md` in the same task.
- `2026-05-14`: Rebuilt an App Store package with `CFBundleVersion=2` after App Store Connect had already accepted build `2`. Root cause: treated the local package as the source of truth and did not account for server-side uploaded build numbers. Future rule: before every upload retry, set `STILLLOOP_BUNDLE_VERSION` to one greater than the highest build number already accepted by App Store Connect for that marketing version.
- `2026-05-15`: Treated the local HTTP model as the default development path after the built-in model was already available. Root cause: over-constrained `AGENTS.md` launch guidance with `STILLLOOP_USE_LOCAL_LLM=1`, which made agents preserve stale manual model settings. Future rule: default development runs should use the app's selected/built-in model; only enable local HTTP when explicitly testing manual model configuration or HTTP-model behavior.
- `2026-05-15`: Described "关闭手动 HTTP 模型" as "模型评估已关闭". Root cause: reused `useLocalLLM` for both manual HTTP selection and overall evaluator availability. Future rule: keep model source, runtime state, and current evaluation path as separate states in code and UI copy.
- `2026-05-16`: Analyzed the focus analysis progress cards but did not implement the confirmed fix before moving on. Root cause: treated diagnosis as enough after the thread shifted to a later runtime issue. Future rule: when a user raises a product defect and asks to reflect on correctness, either implement the confirmed fix in that work item or explicitly call out that it remains pending.
- `2026-05-17`: Replaced the nudge overlay's straight-corner window shadow with a custom layer shadow that created a large rectangular gray haze. Root cause: verified only window structure instead of the actual rendered visual. Future rule: for visual fixes, keep the first change visually minimal and confirm the rendered app before committing.
- `2026-05-17`: Shipped nudge-overlay visibility fixes that changed Space and window-level behavior while the actual regression came from replacing `.hudWindow` material with a custom-layer `.popover` visual effect view. Root cause: tested layer properties instead of rendered visibility and kept guessing at window ordering. Future rule: when a visual regression starts at a specific commit, first restore the last known-good rendering primitive and write tests for that primitive before changing window levels or Space behavior.
- `2026-05-17`: Repeatedly diagnosed a missing nudge overlay as visual styling or window ordering while the live panel was actually stuck offscreen at its entry-animation origin. Root cause: did not inspect live `CGWindow` bounds before changing presentation code. Future rule: for overlay visibility bugs, inspect `CGWindow` bounds, alpha, and onscreen state first, then add a regression test that the entry animation settles inside `NSScreen.visibleFrame`.
- `2026-05-17`: Registered a login item from the XCTest host and made the new setting visually overweight. Root cause: bound the real `SMAppService` manager to module-level app state without excluding test bundles, and verified only the presence of the settings row instead of the rendered layout. Future rule: system-setting integrations must use a bundle-aware inert test path, and settings UI changes must be checked in the rendered app for density and scrolling before commit.
- `2026-05-17`: Removed the optional contact field from the Settings feedback entry after TraceMind diff validation flagged email-like names. Root cause: treated explicitly submitted feedback contact as ordinary analytics properties and did not re-confirm the product tradeoff. Future rule: when a confirmed user-facing field has privacy risk, keep the capability with explicit consent and SDK-supported feedback contact handling, or ask the user before removing it.
- `2026-05-19`: Added a prompt rule that singled out Codex/AI assistants as insufficient novel-writing evidence. Root cause: encoded a failing sample's app name instead of the general product principle. Future rule: fix evaluator mistakes with general evidence requirements and consistency checks, not sample-specific app exclusions that mask real product quality.
- `2026-05-20`: Blurred the focus evaluator's away boundary by treating screen activity as a substitute for camera presence. Root cause: patched prompt/guard semantics before investigating whether camera capture, image ordering, or photo processing caused the user to be missed. Future rule: for away false positives, first inspect the camera capture pipeline and saved diagnostic metadata, then adjust evaluator semantics only if capture evidence is sound.
- `2026-05-21`: Stored App Store marketing screenshots only under ignored `.build/app-store-marketing`, then submitted stale images that referenced a page not present in the app. Root cause: treated generated build output as durable release metadata and did not verify each screenshot against a reachable app path before submission. Future rule: App Store screenshots must live in a stable marketing directory with a manifest mapping each image to a real app entry point, and metadata must be checked for stale feature names before submission.
- `2026-05-25`: Let multiple bundled `stillloop-llama-server` helpers survive across focus task restarts. Root cause: treated readiness success as enough and did not verify the helper process table after stop/restart paths. Future rule: model-runtime lifecycle changes must include tests that duplicate helpers are cleaned, stubborn helpers block relaunch, and a manual process check confirms only one helper remains.
- `2026-05-25`: Tried to justify `com.apple.security.network.server` for a localhost model helper after App Review questioned it, but App Review still required removal. Root cause: optimized for technical accuracy of the helper architecture instead of Apple's minimum-entitlement review standard. Future rule: Mac App Store builds must omit `network.server` unless the shipped UI exposes a clear user-facing incoming-server feature that App Review can locate.
- `2026-05-25`: Created a separate sandbox no-server test app and changed its path/signing while testing a permission-sensitive flow. Root cause: optimized for entitlement isolation but ignored macOS TCC identity continuity, so existing Screen Recording and Camera grants no longer mapped cleanly to the running binary. Future rule: for macOS privacy-permission verification, preserve the existing authorized bundle identifier, bundle path, and signing requirement; if a new app identity is unavoidable, state upfront that TCC must be reauthorized and do not use it for final UI verification.

## Design And Behavior Changes

For every optimization or behavior-changing improvement, apply the global pre-edit checklist plus these StillLoop-specific additions:

- Update or draft the relevant product documentation first, then implement code to match that documented behavior. If no durable product doc is needed, state why it is out of scope before editing code.
- Check all relevant surfaces for the change: macOS app UI, persistence, background work, permissions, notifications, network calls, and tests. Mark any surface out of scope explicitly.
- Re-check the request, current implementation, and documentation for contradictions before implementation. Confirm with the user when a conflict or ambiguous tradeoff appears.

## Build And Test Commands

Use the commands that match the project once the app scaffold exists. Prefer repository scripts when present.

- Swift Package: `swift test`
- Xcode project: `xcodebuild test -scheme <Scheme> -destination 'platform=macOS'`
- Format or lint only when the project has an established formatter or linter.

For local development and verification, prefer these concrete commands.

Confirm the local LM Studio-compatible service is available before launching model-backed app flows:

```sh
curl --noproxy '*' http://127.0.0.1:8080/v1/models
```

Run automated tests:

```sh
swift test
```

Build a signed Mac App Store package only after the Apple Developer agreement is accepted, the App Store bundle ID exists, and local Mac App Store signing identities are installed. Keep the Mac App Store provisioning profile outside the repository; the preferred local path is `$HOME/AppleStore/Signing/StillLoop/StillLoop_Mac_App_Store.provisionprofile`.

```sh
NEXT_BUILD_NUMBER=3

STILLLOOP_BUNDLE_IDENTIFIER=com.super-tree.stillloop \
STILLLOOP_APP_SIGN_IDENTITY="Apple Distribution: Jinchun Chen (FUNQ8PQ8CX)" \
STILLLOOP_INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: Jinchun Chen (FUNQ8PQ8CX)" \
STILLLOOP_PROVISIONING_PROFILE="$HOME/AppleStore/Signing/StillLoop/StillLoop_Mac_App_Store.provisionprofile" \
STILLLOOP_MARKETING_VERSION=1.0 \
STILLLOOP_BUNDLE_VERSION="$NEXT_BUILD_NUMBER" \
scripts/build-app-store-package.sh
```

Set `NEXT_BUILD_NUMBER` to one greater than the highest build number already accepted by App Store Connect for the same `STILLLOOP_MARKETING_VERSION`. Increment it for every App Store Connect upload, including retries after a failed processed build. Do not infer the next upload number from the local `.pkg` filename or the current local `.build/app-store/StillLoop.app`; the script overwrites those files and names the package by marketing version only.

To avoid repeat App Store packaging failures, use this order:

1. From a normal local Terminal, confirm the app signing identity is visible before packaging:

```sh
security find-identity -v -p codesigning
```

The expected app identity is `Apple Distribution: Jinchun Chen (FUNQ8PQ8CX)`. If Codex reports `0 valid identities found` but Terminal shows this identity, treat it as Codex shell sandbox or Keychain visibility, not a missing certificate. Request an approved unsandboxed Codex command for the package build instead of reinstalling certificates.

2. If needed, inspect an existing package to recover the installer identity:

```sh
pkgutil --check-signature .build/app-store/StillLoop-1.0.pkg
```

The expected installer identity is `3rd Party Mac Developer Installer: Jinchun Chen (FUNQ8PQ8CX)`.

3. Run the package script as an approved unsandboxed command when the Codex shell hits SwiftPM cache, clang module cache, `sandbox-exec: sandbox_apply`, readonly `.build/build.db`, or Keychain identity visibility errors. These are environment permission blockers; do not diagnose app code from them.

4. If Transporter reports `The provided entity includes an attribute with a value that has already been used (-19232)` or says the bundle version must be higher than a previous value, do not retry the same `.pkg`. Rebuild immediately with `STILLLOOP_BUNDLE_VERSION` set to that previous value plus one.

5. After packaging, verify the actual artifact, not just command success:

```sh
codesign --verify --deep --strict --verbose=2 .build/app-store/StillLoop.app
codesign -d --entitlements - .build/app-store/StillLoop.app
plutil -p .build/app-store/StillLoop.app/Contents/Info.plist
pkgutil --check-signature .build/app-store/StillLoop-1.0.pkg
shasum -a 256 .build/app-store/StillLoop-1.0.pkg
```

Confirm `CFBundleIdentifier` is `com.super-tree.stillloop`, `CFBundleShortVersionString` matches `STILLLOOP_MARKETING_VERSION`, `CFBundleVersion` matches the incremented `STILLLOOP_BUNDLE_VERSION`, and the signed app entitlements do not contain `com.apple.security.network.server`. The script writes `.build/app-store/StillLoop-$STILLLOOP_MARKETING_VERSION.pkg`; `STILLLOOP_BUNDLE_VERSION` changes the upload build number, not the package filename.

If the provisioning profile was newly downloaded, move it into the preferred local signing directory before packaging and keep that directory out of git:

```sh
mkdir -p "$HOME/AppleStore/Signing/StillLoop"
mv "$HOME/Downloads/StillLoop_Mac_App_Store.provisionprofile" "$HOME/AppleStore/Signing/StillLoop/"
chmod 700 "$HOME/AppleStore/Signing/StillLoop"
chmod 600 "$HOME/AppleStore/Signing/StillLoop/StillLoop_Mac_App_Store.provisionprofile"
```

If the app is already running, stop the old process before launching a fresh build:

```sh
killall StillLoop
```

Launch the development app with the normal in-app model selection. By default, do not set `STILLLOOP_USE_LOCAL_LLM`, `STILLLOOP_LLM_BASE_URL`, or `STILLLOOP_LLM_MODEL`; those variables force the manual HTTP model path and can mask built-in-model behavior.

```sh
cd /Users/wolf3c/Project/StillLoop
STILLLOOP_SKIP_MODEL_DOWNLOAD=1 \
scripts/run-app.sh
```

For prompt-cache A/B performance testing only, add `STILLLOOP_DISABLE_PROMPT_CACHE=1` to the same launch command. Do not use it as the default development path unless the task is specifically testing llama.cpp prompt-cache behavior.

The default built-in-model path uses the bundled llama.cpp helper under `Sources/StillLoop/Resources/Runtime/`. `scripts/run-app.sh` copies it into `.build/StillLoop.app/Contents/Helpers/stillloop-llama-server` with its `lib*.dylib` dependencies, signs the helper files, and StillLoop starts the helper lazily during a focus session. The built-in helper listens on a per-app Unix domain socket in the temporary directory, not a TCP localhost port, so Mac App Store builds do not need `com.apple.security.network.server`. The helper starts with `--mlock` to reduce memory-compression or swap-related inference tail latency, at the cost of higher resident memory pressure. If the focus screen shows a built-in runtime failure, check `pgrep -fl "stillloop-llama-server|llama-server|StillLoop"` before falling back to manual HTTP testing.

Only launch with a local HTTP model when the task explicitly requires manual model configuration, HTTP endpoint checks, or fallback behavior:

```sh
cd /Users/wolf3c/Project/StillLoop
STILLLOOP_SKIP_MODEL_DOWNLOAD=1 \
STILLLOOP_USE_LOCAL_LLM=1 \
STILLLOOP_LLM_BASE_URL=http://127.0.0.1:8080/v1 \
STILLLOOP_LLM_MODEL=qwen3.5-0.8b-mlx \
scripts/run-app.sh
```

The launch script rebuilds `.build/StillLoop.app`, displays the development bundle as `StillLoop Dev`, and signs it with stable identifier `local.StillLoop.dev`. macOS privacy permissions for the development bundle are separate from the App Store bundle `com.super-tree.stillloop`; authorize `StillLoop Dev` once in Screen Recording instead of expecting the production app's permission to transfer. By default the script uses ad-hoc signing; set `STILLLOOP_CODESIGN_IDENTITY` to an installed Apple Development identity when testing macOS privacy permissions across rebuilds. If an older development build was authorized before this signing behavior existed, the first run after the change may still require turning the StillLoop Dev screen-recording permission off and on once, then restarting StillLoop Dev.

Run the app launch command from a normal local shell or an approved unsandboxed Codex command. If it fails inside the Codex shell sandbox with SwiftPM cache, clang module cache, or readonly `.build/build.db` errors, treat that as an environment permission blocker and rerun outside the sandbox before diagnosing app code.

If a command cannot run in the current environment, report the exact blocker and what remains unverified.

## Coding Style

For Swift code, prefer clear names, small single-purpose types, explicit access control where useful, and straightforward async/error handling. Keep UI code readable and avoid hiding simple behavior behind unnecessary abstractions.

## Testing Guidelines

Place tests in the target that owns the behavior, and prefer behavior-oriented names. For UI-sensitive changes, verify the rendered state or interaction path when the project has UI test support.

When testing model-backed behavior locally, prefer the app's built-in model path and the model source selected in the UI. Use `STILLLOOP_SKIP_MODEL_DOWNLOAD=1` to avoid re-downloading during development, assuming the built-in model is already present under the app's Application Support model directory. Do not force `STILLLOOP_USE_LOCAL_LLM=1` unless the test specifically covers manual/local HTTP model configuration.

Every completed requirement implementation must be verified in two ways before reporting it done:

- Run the relevant automated tests, and broaden to `swift test` when the behavior is shared or cross-target.
- Use the Computer tool to exercise the app behavior through the macOS UI and confirm the implemented path works. If Computer verification cannot run in the current environment, report the exact blocker and what remains unverified.

## Git Guidelines

Use concise imperative commit messages, such as `Initialize macOS app repository` or `Add StillLoop agent guidelines`.

## Security And Configuration

Keep StillLoop signing and release artifacts out of the repository, including local provisioning files, generated archives, and machine-specific IDE state.

## TraceMind Instrumentation Rules

TraceMind Skill fallback installation:

- Skill URL: `https://tracemind.sandbox.galaxycloud.app/agents/tracemind/SKILL.md`
- Manifest URL: `https://tracemind.sandbox.galaxycloud.app/agents/tracemind/manifest.json`
- Guidance version: `2026.05.09.1`
- Core workflow: verify the bound TraceMind project through MCP, check current agent guidance, run platform-specific capture setup, search existing event names before proposing manual events, validate payloads/diffs through MCP, and keep captured data free of PII, secrets, raw content, prompts, tool arguments/results, source diffs, request/response bodies, headers, cookies, authorization values, and full query URLs.

## TraceMind Project Binding

- Project name: `StillLoop`
- Project ID: `xfa9KrbSD9p62oRrq`
- Expected MCP server: `tracemind-62orrq`

Before using any TraceMind MCP tool in this repository, use MCP server `tracemind-62orrq`, call `tracemind.project_info`, and continue only if the returned `projectId` equals `xfa9KrbSD9p62oRrq`. If it does not match, stop and ask the user to configure the correct TraceMind MCP server. Do not use another `tracemind-*` MCP server for this repository unless the user explicitly confirms the project switch.

When adding or modifying TraceMind analytics instrumentation in this project:

1. Use the TraceMind MCP before writing analytics code.
2. Call `tracemind.agent_guidance` to check the current guidance version.
3. If multiple TraceMind MCP servers exist or the project is unclear, call `tracemind.project_info` or inspect MCP tool descriptions to confirm the project.
4. Verify TraceMind setup before manual custom events by calling `tracemind.capture_setup`; Web uses the returned `captureSnippet`, while iOS, macOS, Android, React Native, MCP Node, MCP Python, Agent Skill, and server application targets pass the matching `platform` (`ios`, `macos`, `android`, `react_native`, `mcp_node`, `mcp_python`, `agent_skill`, `server_node`, `server_python`, or `server_http`) and follow the returned `installCommands`, `filesToEdit`, `initLocation`, `idempotencyChecks`, and one-line `initSnippet`. The public project key is only for capture writes.
5. Search for an existing event before creating a new event.
6. Use only approved event names and properties returned or validated by the MCP.
7. Do not invent event names.
8. If no existing event matches, create a draft custom event proposal instead of treating it as approved.
9. For manual capture, follow the returned `manualCaptureWorkflow`, use `identifySnippet` after login when a stable internal `userId` exists, and keep `properties`/`context` values to supported primitives: string, number, and boolean.
10. Never send PII, personal contact fields, secrets, credential values, raw prompts, raw user content, input values, or full URLs with query strings.
11. After changing analytics code, validate the diff or project instrumentation through the TraceMind MCP before finishing.
12. When the developer finds a product issue or idea, ask whether they want to submit feedback unless they explicitly requested submission; if yes, call `tracemind.submit_feedback` with a sanitized summary and evidence references.

For product app and MCP targets, verify Auto Capture before manual custom events. Ordinary server applications are the exception in v1: use manual capture only.

For native SDK setup, do not duplicate existing dependencies or `TraceMind.start(...)` calls. iOS and macOS initialize from `App.swift` or `AppDelegate`, Android initializes from `Application.onCreate()`, and React Native initializes from the app bootstrap while keeping event `platform` as `ios` or `android` and marking `react_native` in framework metadata. macOS uses the existing Swift package and records window or screen level Auto Capture with `platform: "macos"` and `sourceType: "macos"`.

Manual native events are for stable business outcomes that Auto Capture cannot infer. The SDKs sanitize and omit nulls, nested objects, arrays, PII-like keys, credential values, raw prompts/content, input values, and full query URLs.

For third-party MCP servers, use `mcp_node` or `mcp_python`. Auto Capture records safe server metadata for tool calls, resource reads, and prompt requests with `platform: "server"` and `sourceType: "mcp_server"`. Do not capture raw prompts, tool arguments, tool results, resource content, source code, diffs, secrets, tokens, or full query URLs.

For Agent Skills, use `agent_skill`. A static Skill file cannot auto-capture by itself; only instrument executable host agent runtime lifecycle hooks, or keep the Skill as a tutorial and place manual capture in the MCP server/runtime that performs the work.

For ordinary server applications, use `server_node`, `server_python`, or `server_http`. The first version is manual capture only, not request Auto Capture. Add events only for stable server-side business outcomes such as payment succeeded, invoice paid, workspace created, job completed, or sync completed. Use `platform: "server"` and `sourceType: "server_app"`, and never capture request bodies, response bodies, headers, cookies, authorization values, raw logs, secrets, tokens, prompts, or full query URLs.

For developer feedback, use `tracemind.submit_feedback`; do not send feedback through `/api/capture` or manual `custom` events. Prefer event IDs, raw behavior IDs, paths, `actionKey`, `targetHash`, session/device IDs, time windows, and short sanitized examples over raw copied content. Never submit PII, secrets, tokens, raw prompts, raw user content, source code, diffs, request/response bodies, headers, cookies, authorization values, tool arguments/results, resource content, or full query URLs.
