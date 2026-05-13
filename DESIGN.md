# Design System: StillLoop

**Product:** Local-first macOS focus companion  
**Reference:** VoltAgent `awesome-design-md/design-md/apple`

## 1. Visual Theme & Atmosphere

StillLoop should feel like a quiet native macOS utility, not a productivity dashboard. The visual language is calm, local, and precise: the app stays out of the user's way until it needs to gently bring them back.

Borrow from Apple's design grammar where it fits a desktop app:

- Near-invisible chrome and system-native controls.
- SF system typography with confident 600-weight headings and readable 400-weight body text.
- One clear interactive accent: Action Blue.
- Light surfaces, soft separators, and material blur instead of decorative gradients.
- Status clarity through symbols, concise labels, and restrained color.

StillLoop is not a marketing site. Do not copy Apple's edge-to-edge product-tile rhythm into the app shell. The app should preserve a focused work surface: compact, readable, trustworthy, and privacy-forward.

## 2. Color Palette & Roles

### Core Colors

- **Action Blue** (`#0066CC`): Primary actions, focused links, keyboard focus intent, and the strongest interactive affordance.
- **Focus Blue** (`#0071E3`): Focus rings and selected states when the platform does not provide a native focus treatment.
- **Sky Link Blue** (`#2997FF`): Links or actions on dark surfaces only.
- **Near-Black Ink** (`#1D1D1F`): Primary text and icon color on light surfaces.
- **Muted Ink** (`#7A7A7A`): Secondary text, explanatory copy, metadata, and disabled-adjacent states.
- **Canvas White** (`#FFFFFF`): Main window and form surface when the platform appearance is light.
- **Parchment Gray** (`#F5F5F7`): Secondary panels, review background bands, and non-modal grouped surfaces.
- **Pearl Surface** (`#FAFAFC`): Quiet inline cards and local status containers.
- **Hairline Gray** (`#E0E0E0`): One-pixel dividers and card outlines.
- **Soft Divider** (`#F0F0F0`): Extremely subtle internal separators.
- **Near-Black Surface** (`#272729`): Rare dark presentation surface for high-emphasis privacy or session-state summaries.
- **Pure Black** (`#000000`): Avoid in app content except system-provided menu bar or media voids.
- **On Dark** (`#FFFFFF`): Text and symbols on dark surfaces.

### Semantic Status Colors

Use status color sparingly and never as the only signal.

- **Focused:** Prefer SF Symbol `checkmark.circle` with system green.
- **Uncertain:** Prefer SF Symbol `circle.lefthalf.filled` with muted or secondary tint.
- **Distracted:** Prefer SF Symbol `exclamationmark.triangle` with system orange.
- **Stuck:** Prefer SF Symbol `questionmark.circle` with system yellow or secondary tint.
- **Resting:** Prefer SF Symbol `cup.and.saucer` with secondary tint.
- **Paused:** Prefer SF Symbol `pause.circle` with muted tint.

Action Blue remains the only brand interaction color. Status colors explain state; they do not compete with primary actions.

## 3. Typography Rules

Use native SwiftUI system fonts so the app resolves to SF Pro on macOS.

| Token | SwiftUI guidance | Role |
| --- | --- | --- |
| `display` | `.system(size: 32-34, weight: .semibold)` | Welcome, permissions, task setup, review titles |
| `panel-title` | `.system(size: 18-21, weight: .semibold)` | Header brand, major panel headings |
| `task-title` | `.system(size: 28, weight: .semibold)` | Active focus task and large user-entered task text |
| `body` | `.system(size: 17, weight: .regular)` or platform `.body` | Main explanatory copy |
| `body-strong` | `.system(size: 17, weight: .semibold)` | Metric values and row titles |
| `caption` | `.caption` / 12-14 regular | Metadata, evaluation loop details, permission descriptions |

Rules:

- Use weight 600 / `.semibold` for titles, not heavy bold.
- Use body copy at Apple-like 17pt where the surface is explanatory.
- Keep captions quiet with `.secondary` foreground.
- Avoid negative letter spacing in SwiftUI app surfaces unless a marketing screen is explicitly requested.
- Use Chinese copy that is short, concrete, and gentle. StillLoop's voice is "跑偏？回来。": direct, not scolding.

## 4. Component Styling

### App Shell

- Main window minimum should remain around `820 x 560` or larger.
- Background should be native `windowBackgroundColor`.
- Header should stay thin and calm: brand on the left, compact utility actions on the right.
- Avoid a heavy sidebar until the app has enough persistent navigation to justify it.

### Buttons

- Primary actions should use native bordered-prominent styling where appropriate, tinted by Action Blue.
- Secondary actions should use native bordered/plain controls.
- Destructive or session-ending actions should be explicit in copy, not over-styled.
- Use 44px minimum hit targets for icon-only or compact toolbar controls.
- Prefer SF Symbols inside icon buttons when a symbol exists.

### Cards And Containers

- Use cards only for repeated items, metrics, local context, permissions, model readiness, and review summaries.
- Preferred card radius: 8px for compact utility cards; up to 12px for larger panels.
- Use `.thinMaterial` or Pearl Surface for calm grouping.
- Use a 1px hairline or material contrast before adding shadows.
- Avoid drop shadows on cards, buttons, or text. Depth should come from system material, separators, and spacing.

### Inputs

- Task entry should feel important and uncluttered: large plain text field, 8px radius outline, generous horizontal padding.
- Search-like or filter inputs, if added, should be pill-shaped only when they are compact utility controls.
- Validation should be inline and specific. Do not show modal alerts for ordinary form guidance.

### Metrics

- Metrics should be compact, scan-friendly, and stable in size.
- Title uses secondary caption; value uses semibold body or headline.
- Do not use oversized dashboard numbers unless a review screen becomes analytics-heavy.

### Timeline

- Timeline events should remain secondary to the current task.
- Use clear timestamp, state label, and context snippet.
- Keep nudge text short and visually subordinate.
- Avoid dense charts unless the user explicitly asks for deeper analytics.

### Status Item

- Status item copy must remain short enough for the menu bar.
- Always pair status text with an SF Symbol.
- Prefer current symbols:
  - `circle.dotted` idle
  - `checkmark.circle` focused
  - `circle.lefthalf.filled` uncertain
  - `exclamationmark.triangle` distracted
  - `questionmark.circle` stuck
  - `cup.and.saucer` resting
  - `pause.circle` paused
  - `chart.bar` review

## 5. Layout Principles

- Base spacing rhythm: 8px, with structural steps at 12, 16, 20, 24, 32, and 40.
- Form and setup screens should use 40px outer padding.
- Focus-running surfaces can use tighter 32px padding to show task, metrics, context, and timeline at once.
- Keep important content left-aligned. Centering should be rare and reserved for empty states or onboarding moments.
- Use `Spacer()` for native breathing room, not decorative blocks.
- Keep the timeline narrow enough to support the primary focus content, around 260px unless content forces a redesign.

## 6. Interaction Principles

- The app should interrupt only when the session state warrants it.
- Nudges should be short, specific, and non-judgmental.
- Permission requests should explain local purpose before asking.
- Local model readiness should be visible but not block task entry unless a behavior truly depends on it.
- Pause, resume, end, and feedback actions should be reversible or low-risk where possible.
- Ending a session should take the user to review immediately; review should make the value of the focus period visible without feeling like surveillance.

## 7. Privacy Design Rules

Privacy is part of the interface, not only documentation.

- Prefer "本地" and "不保存" wording where it directly clarifies behavior.
- Never imply employee monitoring, cloud sync, app blocking, or hidden surveillance.
- Do not display raw screenshots, camera frames, headers, cookies, full URLs with query strings, or request/response bodies unless the user explicitly requests a diagnostic tool and the data stays local.
- When showing context, summarize the signal: active app, window title, browser title, screenshot availability, camera availability.
- Make permission-denied states usable. The user should still be able to test the core flow with limited signals.

## 8. Do's And Don'ts

### Do

- Use Action Blue (`#0066CC`) for primary interactive intent.
- Use native macOS materials, colors, and controls before custom decoration.
- Keep copy compact and calm.
- Use SF Symbols for state and utility actions.
- Keep cards flat and low-contrast.
- Make privacy assurances concrete and behavior-linked.

### Don't

- Do not introduce a second brand accent color.
- Do not add decorative gradients, ornamental blobs, or marketing-style hero art inside the app shell.
- Do not add shadows to cards or controls.
- Do not turn the focus screen into a dense analytics dashboard.
- Do not expose internal model, prompt, or raw capture details in primary UI unless the surface is explicitly diagnostic.
- Do not add web, server, or SDK design assumptions to the native app without a concrete product request.

## 9. Implementation Notes For Future UI Work

- Keep SwiftUI view code readable and close to the existing structure until repetition proves a component is worth extracting.
- Reuse native styles first: `.buttonStyle(.borderedProminent)`, `.controlSize(.large)`, `.foregroundStyle(.secondary)`, `.background(.thinMaterial)`.
- Prefer `Label` with SF Symbols for permission, privacy, status, and summary rows.
- If adding design tokens, keep them small and semantic: `BrandColor.actionBlue`, `Surface.card`, `Spacing.panel`.
- Before behavior-changing UI work, check the macOS app window, status item, permissions, notifications, persistence, local model state, and tests.
