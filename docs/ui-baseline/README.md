# UI before-pictures (board task P7)

These pictures show what the P0 pages looked like before the UI rework (baseline `39c8a53`, app 0.0.55, web 0.59.5). Every later change is reviewed against them.

## App: `app/light`, `app/dark`

- **Pages:** 25 P0 pages at 390 × 844.
- **Source:** the opt-in screenshot tests in `apps/mobile/test/screenshots`, run on fake data.
- **Full set:** all 406 pictures are kept locally in `app-full/`, which git ignores. Regenerate them with:
  ```
  flutter test test/screenshots --dart-define=SCREENSHOTS=<dir> --dart-define=SHOT_THEME=light|dark
  ```
- **Already failing before the rework:** three screenshot tests. These tests are skipped in normal runs, and the pictures were still written.
  - `home_test`: a WorkoutRecorder is used after dispose, at teardown.
  - `tournaments_test`, "registration, as a team admin": no GoRouter in the test app.

## Website: `web/light`, `web/dark`

- **Pages:** 8 pages, signed out, at phone (375) and desktop (1440) width.
- **Source:** `apps/web/tests/e2e/baseline.spec.ts`. Regenerate with:
  ```
  BASELINE=1 pnpm exec playwright test baseline --project=phone --project=desktop
  ```
- **Limits:**
  - The local API was not running, so sections that load from it show as empty.
  - Member pages need a signed-in test account, which isn't set up yet.
