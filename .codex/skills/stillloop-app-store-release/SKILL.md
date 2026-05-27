---
name: stillloop-app-store-release
description: Use when packaging, validating, uploading, delivering, submitting, or drafting release notes for the StillLoop macOS app on App Store Connect, especially requests like "打包正式版上传", "提交审核", "整理发版说明", "App Store release", "release notes", "Transporter", "altool", build-number retries, signing, provisioning, or Mac App Store distribution for /Users/wolf3c/Project/StillLoop.
---

# StillLoop App Store Release

## Overview

Use this skill for StillLoop's Mac App Store release path. Treat it as a guarded release runbook: protect build-number correctness, verify artifacts, prepare accurate release notes, avoid leaking Apple credentials, and separate local signing/toolchain blockers from product-code failures.

## Scope

- Repository: `/Users/wolf3c/Project/StillLoop`
- Bundle ID: `com.super-tree.stillloop`
- Default marketing version: `1.0`
- Export compliance: user confirmed on 2026-05-19 that StillLoop's App Store Connect export compliance declaration can be answered `No` for this app.
- Expected app signing identity: `Apple Distribution: Jinchun Chen (FUNQ8PQ8CX)`
- Expected installer identity: `3rd Party Mac Developer Installer: Jinchun Chen (FUNQ8PQ8CX)`
- Expected profile path: `$HOME/AppleStore/Signing/StillLoop/StillLoop_Mac_App_Store.provisionprofile`
- Package output: `.build/app-store/StillLoop-$STILLLOOP_MARKETING_VERSION.pkg`

Do not store Apple credentials in the repo or this skill. Use App Store Connect API keys from `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`, environment variables, Keychain items, or an already-authenticated Transporter/App Store Connect UI session.

## Release Workflow

1. Inspect the repo state and release inputs.
   - Run `git status --short --branch`.
   - Confirm marketing version, target action, whether release notes are needed, and whether the user wants upload only or submit for review too.
   - If source changes are present, do not modify, revert, stage, or commit them unless the user requested that.

2. Draft release notes when requested or when submitting a new App Store version.
   - Determine the previous release timestamp from App Store Connect version history when possible. If App Store Connect access is unavailable, use a repo release tag/date only if it clearly represents the last public release; otherwise ask the user for the last release date/time.
   - Use all commits from the previous release timestamp through now, not only the last tag range, unless the user explicitly asks for a tag-to-tag summary.
   - Record the exact window, timezone, command, commit count, and first/last commit hashes used for the draft.
   - Prefer chronological review for facts and user-facing grouping for the final copy:

```sh
git log --since='<previous-release-time>' --date=iso-strict --pretty=format:'%h%x09%ad%x09%s'
```

   - If the previous release is represented by a known commit or tag, cross-check the timestamp-based set against the ref-based set before drafting:

```sh
git log <previous-release-ref>..HEAD --date=iso-strict --pretty=format:'%h%x09%ad%x09%s'
```

   - Filter out purely internal build, signing, CI, test, dependency, and agent-instruction changes unless they affect users, review metadata, privacy/compliance, or App Store acceptance.
   - Merge related commits into concise user-facing bullets. Do not expose commit hashes, branch names, internal prompt text, private paths, credentials, or raw diagnostics in App Store copy.
   - Produce a short Chinese draft by default, with optional English if the user asks. Keep App Store release notes plain and benefit-oriented, usually 3-6 bullets.
   - Separately report notable internal/release-engineering changes that should not go into public App Store notes.

3. Determine the next build number from App Store Connect, not the local package name.
   - Preferred: query App Store Connect or inspect the App Store Connect build list for the same marketing version.
   - If live query is unavailable, ask for the highest accepted build number or use the highest known local artifact only as a provisional lower bound.
   - Set `STILLLOOP_BUNDLE_VERSION` to one greater than the highest build number already accepted by App Store Connect.
   - If upload reports duplicate/reused build number, immediately rebuild with the reported previous value plus one; never retry the same `.pkg`.

4. Confirm local prerequisites.
   - Check the provisioning profile exists at the expected path.
   - Check signing identities with `security find-identity -v -p codesigning`.
   - If Codex reports `0 valid identities found` but a normal Terminal has them, treat it as sandbox or Keychain visibility. Request an approved unsandboxed build command instead of reinstalling certificates.

5. Build the formal package with the selected build number.

```sh
NEXT_BUILD_NUMBER=<one-greater-than-App-Store-Connect-highest>

STILLLOOP_BUNDLE_IDENTIFIER=com.super-tree.stillloop \
STILLLOOP_APP_SIGN_IDENTITY="Apple Distribution: Jinchun Chen (FUNQ8PQ8CX)" \
STILLLOOP_INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: Jinchun Chen (FUNQ8PQ8CX)" \
STILLLOOP_PROVISIONING_PROFILE="$HOME/AppleStore/Signing/StillLoop/StillLoop_Mac_App_Store.provisionprofile" \
STILLLOOP_MARKETING_VERSION=1.0 \
STILLLOOP_BUNDLE_VERSION="$NEXT_BUILD_NUMBER" \
scripts/build-app-store-package.sh
```

6. Verify the artifact, not just command success.

```sh
codesign --verify --deep --strict --verbose=2 .build/app-store/StillLoop.app
plutil -p .build/app-store/StillLoop.app/Contents/Info.plist
codesign -d --entitlements - .build/app-store/StillLoop.app
pkgutil --check-signature .build/app-store/StillLoop-1.0.pkg
shasum -a 256 .build/app-store/StillLoop-1.0.pkg
swift test
```

Confirm:
- `CFBundleIdentifier` is `com.super-tree.stillloop`
- `CFBundleShortVersionString` matches `STILLLOOP_MARKETING_VERSION`
- `CFBundleVersion` matches `NEXT_BUILD_NUMBER`
- the app deep-signature verification passes
- the package signature names the expected installer identity
- tests pass

If `pkgutil` reports `signed by untrusted certificate` but shows the expected installer identity, report it as local trust-chain state and rely on `altool` validation or Transporter for App Store acceptance. If `spctl` reports `internal error in Code Signing subsystem`, do not diagnose app code from that alone.

7. Validate and upload.

JWT path:

```sh
xcrun altool --validate-app .build/app-store/StillLoop-1.0.pkg \
  --api-key "$ASC_API_KEY_ID" \
  --api-issuer "$ASC_API_ISSUER_ID" \
  --output-format json

xcrun altool --upload-package .build/app-store/StillLoop-1.0.pkg \
  --api-key "$ASC_API_KEY_ID" \
  --api-issuer "$ASC_API_ISSUER_ID" \
  --wait \
  --show-progress \
  --output-format json
```

Username path:

```sh
xcrun altool --validate-app .build/app-store/StillLoop-1.0.pkg \
  --username "$ASC_USERNAME" \
  --password @keychain:<keychain-item-name> \
  --provider-public-id "$ASC_PROVIDER_PUBLIC_ID" \
  --output-format json

xcrun altool --upload-package .build/app-store/StillLoop-1.0.pkg \
  --username "$ASC_USERNAME" \
  --password @keychain:<keychain-item-name> \
  --provider-public-id "$ASC_PROVIDER_PUBLIC_ID" \
  --wait \
  --show-progress \
  --output-format json
```

If CLI credentials are unavailable but Transporter is installed, open the package for manual authenticated delivery:

```sh
/usr/bin/open -a Transporter .build/app-store/StillLoop-1.0.pkg
```

8. Monitor processing.
   - Capture the delivery ID from upload output when available.
   - Use `xcrun altool --build-status --delivery-id <id> --wait --output-format json` when supported.
   - If only UI processing is available, check App Store Connect or Transporter and report that CLI monitoring is unavailable.

9. Deliver/select the processed build and submit for review only when requested.
   - Confirm the build number selected in App Store Connect equals the uploaded `CFBundleVersion`.
   - Complete required App Store Connect metadata, public release notes, export-compliance, privacy, review notes, and screenshot checks.
   - If App Store Connect asks whether StillLoop uses export-compliance encryption, use the user-confirmed answer `No`. Do not generalize this answer to other apps or projects.
   - Do not invent answers for compliance/privacy questions. Ask the user when required data is unavailable.
   - Before final submission, summarize the exact version/build and ask for confirmation unless the user's latest instruction explicitly includes submitting for review.

## Failure Handling

- `The provided entity includes an attribute with a value that has already been used (-19232)`: rebuild with a higher `STILLLOOP_BUNDLE_VERSION`; do not retry the same package.
- `Either JWT ... or username and app password ... authentication is required`: credentials are missing. Ask for API key/issuer and `.p8`, or use Transporter.
- SwiftPM cache, clang module cache, readonly `.build/build.db`, `sandbox-exec`, or Keychain identity visibility errors: rerun the build as an approved unsandboxed command.
- `altool` cache or `Defaults.properties` errors in Codex sandbox: rerun `xcrun altool ...` as an approved unsandboxed command.
- Missing provisioning profile: ask the user to download it or move it to the expected signing directory; do not commit it.

## Handoff

Report:
- package path
- marketing version and build number
- release notes source window, commit count, and final public draft when prepared
- internal changes intentionally excluded from public release notes
- signing and Info.plist verification results
- SHA-256
- test result
- upload delivery ID or Transporter/manual status
- whether the build was selected for the version and whether review was submitted
- any blockers with the exact command/error text
