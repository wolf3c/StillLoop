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
