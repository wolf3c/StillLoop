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
- Before behavior changes, state the current behavior, target behavior, affected modules, risks, verification plan, and concise implementation plan.
- Keep changes minimal and aligned with existing product semantics. Avoid opportunistic refactors and broad cleanup.
- Preserve user work in a dirty tree. If existing changes affect the task, work with them instead of reverting them.
- After finishing implementation work, suggest one or more accurate git commit messages.
- If the user points out an agent mistake, add a short Error Ledger entry explaining the root cause and future rule.

## Error Ledger

Add entries here only when a mistake reveals a reusable rule for future work.

- `YYYY-MM-DD`: What went wrong. Root cause. Future rule to prevent recurrence.

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

If a command cannot run in the current environment, report the exact blocker and what remains unverified.

## Coding Style

Match the existing project style. For Swift code, prefer clear names, small single-purpose types, explicit access control where useful, and straightforward async/error handling. Keep UI code readable and avoid hiding simple behavior behind unnecessary abstractions.

## Testing Guidelines

Add focused tests for behavior changes. Place tests in the target that owns the behavior, and prefer behavior-oriented names. For UI-sensitive changes, verify the rendered state or interaction path when the project has UI test support.

## Git Guidelines

Use concise imperative commit messages, such as `Initialize macOS app repository` or `Add StillLoop agent guidelines`. Do not create commits, branches, tags, or remotes unless the user asks for them.

## Security And Configuration

Do not commit local secrets, credentials, provisioning files, generated archives, or machine-specific IDE state. Keep credentials and tokens out of client code and logs. When adding diagnostics, avoid collecting PII, raw user content, full URLs with query strings, secrets, headers, cookies, authorization values, or request/response bodies.
