---
name: review-ui
description: Reviews Hylite screens on the app and website against the approved UI guide, mock-up boards and accessibility rules, using goldens, Playwright screenshots and axe scans compared with the before-pictures. Use after UI changes, before approving a UI task, or when asked to check a screen's design.
argument-hint: "<screens or task code, e.g. 'Home' or 'K2'>"
---

# Review UI

Scope: $ARGUMENTS

## 1. References (approved)
Read:
- `docs/specifications/audit/Stall10_UI_Implementation_Guide.md`
- the decisions in `docs/specifications/ui-migration-plan.md` §8–9 (zinc + indigo, green only for success, tabs Home · Discover · Teams · Schedule · Chats, profile from the top-right picture, no dark card, cover header, body text 16)
- the mock-up boards (`docs/Stall10 *-1..4.png`)
- the before-pictures in `docs/ui-baseline/`

## 2. Capture current state
Run these yourself; the reviewer agent is read-only.

| Platform | Command | Notes |
|---|---|---|
| App goldens | `flutter test <changed tests>` in `apps/mobile`. Add `--update-goldens` only if the change is intended, and show the before/after images. | Goldens compare only on Windows. |
| App screenshots | `flutter test test/screenshots/<area>_test.dart --dart-define=SCREENSHOTS=<scratch dir> --dart-define=SHOT_THEME=light\|dark` | |
| Website | `pnpm exec playwright test` in `apps/web` | Add `BASELINE=1 ... baseline` for full pages, written to `docs/ui-baseline/web`. Copy them to a scratch folder first if you don't want to overwrite the before-pictures. |
| Accessibility | `expectAccessible` / `expectNoOverflowWithLargeText` (app) and `axeViolations` (website helpers) | |

## 3. Review
Use the ui-ux-reviewer agent, passing it the image paths and the changed file list. It checks:
- **Tokens:** semantic tokens are used, with no hard-coded colours (grep for `Color(0x` and `#` in changed UI files).
- **Type, spacing and corners:** they follow the scale.
- **Components:** shared components are reused rather than one-off widgets.
- **Themes:** light and dark both work. Contrast is at least 4.5:1 for text and 3:1 for outlines.
- **Accessibility:**
  - tap targets of 48 px
  - no overflow with text at 200%
  - labels, focus order and keyboard on the website
- **Layout:** it matches at phone, tablet and desktop widths.
- **Functionality:** nothing is lost compared with the before-pictures.
- **States:** loading, empty, error and offline are all covered.
- **Scope:** no features added that appear only in the mock-ups.

## 4. Report
For each screen, list findings with severity, screen, file:line and a screenshot reference. Mark which findings are **required by the approved design** and which are **optional suggestions**. Finish with a verdict: approve, approve with fixes, or changes needed.
