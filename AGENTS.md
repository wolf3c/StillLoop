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

- Work only on files required for the current task. Do not modify, revert, reformat, stage, or clean up unrelated files.
- The user may provide multiple requirements in one message. Unless there is an obvious dependency, decompose them and execute in parallel where safe, including using subagents for disjoint subtasks.
- For independent subtasks, prefer dispatching them to separate subagents and merge only the results that do not overlap files or flow assumptions.
- Before behavior changes, state the current behavior, target behavior, affected modules, risks, verification plan, and concise implementation plan.
- Implement behavior changes with TDD: write or update a focused failing test first, confirm it fails for the expected reason, then make the smallest production change that turns it green.
- Keep changes minimal and aligned with existing product semantics. Avoid opportunistic refactors and broad cleanup.
- Preserve user work in a dirty tree. If existing changes affect the task, work with them instead of reverting them.
- When testing is complete and a test app is running, do not close it immediately. Tell the user it is ready for their manual test, keep it running, and close it only after the user confirms the behavior passed.
- After finishing an implementation item (done + verified), commit directly unless the user explicitly asks to delay it.
- If behavior changes are completed and test-verified, include one or more accurate commit-message options in the handoff.
- If the user points out an agent mistake, add a short Error Ledger entry explaining the root cause and future rule.

## Error Ledger

Add entries here only when a mistake reveals a reusable rule for future work.

- `YYYY-MM-DD`: What went wrong. Root cause. Future rule to prevent recurrence.
- `2026-05-13`: Added only a prose testing constraint without a runnable command. Root cause: documented intent but not the exact agent action. Future rule: when test configuration is requested, include the concrete command or environment variables agents should run.
- `2026-05-13`: Left the new skip-download launch setting out of this guide. Root cause: updated the script and test but not the reusable agent instructions. Future rule: when changing development or testing commands, update `AGENTS.md` in the same task.

## Design And Behavior Changes

For every optimization or behavior-changing improvement, do the design work before editing production code:

- Identify current behavior, target behavior, affected modules, risks, and verification plan.
- Check all relevant surfaces for the change: macOS app UI, persistence, background work, permissions, notifications, network calls, and tests. Mark any surface out of scope explicitly.
- Write a concise implementation plan before changing code.
- Treat tests passing as insufficient by itself; confirm the implementation, docs, and verification all match the requested behavior.

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

If the app is already running, stop the old process before launching a fresh build:

```sh
killall StillLoop
```

Launch the app with the local HTTP model prefilled:

```sh
cd /Users/wolf3c/Project/StillLoop
STILLLOOP_SKIP_MODEL_DOWNLOAD=1 \
STILLLOOP_USE_LOCAL_LLM=1 \
STILLLOOP_LLM_BASE_URL=http://127.0.0.1:8080/v1 \
STILLLOOP_LLM_MODEL=qwen3.5-0.8b \
scripts/run-app.sh
```

The launch script rebuilds `.build/StillLoop.app` and signs the development bundle with stable identifier `local.StillLoop.dev` plus a matching designated requirement. This keeps macOS privacy permissions tied to the development app across rebuilds. If an older build was authorized before this signing behavior existed, the first run after the change may still require turning the StillLoop screen-recording permission off and on once, then restarting StillLoop.

Run the app launch command from a normal local shell or an approved unsandboxed Codex command. If it fails inside the Codex shell sandbox with SwiftPM cache, clang module cache, or readonly `.build/build.db` errors, treat that as an environment permission blocker and rerun outside the sandbox before diagnosing app code.

If a command cannot run in the current environment, report the exact blocker and what remains unverified.

## Coding Style

Match the existing project style. For Swift code, prefer clear names, small single-purpose types, explicit access control where useful, and straightforward async/error handling. Keep UI code readable and avoid hiding simple behavior behind unnecessary abstractions.

## Testing Guidelines

Add focused tests for behavior changes. Place tests in the target that owns the behavior, and prefer behavior-oriented names. For UI-sensitive changes, verify the rendered state or interaction path when the project has UI test support.

When testing model-backed behavior locally, use the local HTTP model endpoint `http://127.0.0.1:8080/v1` with model `qwen3.5-0.8b`. Configure local app runs with `STILLLOOP_SKIP_MODEL_DOWNLOAD=1` so tests use the local HTTP model instead of downloading or relying on the built-in model.

Every completed requirement implementation must be verified in two ways before reporting it done:

- Run the relevant automated tests, and broaden to `swift test` when the behavior is shared or cross-target.
- Use the Computer tool to exercise the app behavior through the macOS UI and confirm the implemented path works. If Computer verification cannot run in the current environment, report the exact blocker and what remains unverified.

## Git Guidelines

Use concise imperative commit messages, such as `Initialize macOS app repository` or `Add StillLoop agent guidelines`. Do not create commits, branches, tags, or remotes unless the user asks for them.

## Security And Configuration

Do not commit local secrets, credentials, provisioning files, generated archives, or machine-specific IDE state. Keep credentials and tokens out of client code and logs. When adding diagnostics, avoid collecting PII, raw user content, full URLs with query strings, secrets, headers, cookies, authorization values, or request/response bodies.

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
