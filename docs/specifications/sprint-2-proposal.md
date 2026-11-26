# Sprint 2 (Nov 27 – Dec 11, 2026)

**Status:** approved by the owner on 2026-11-26, together with **Q19** (minimum-version gate and video-upload flag) and **Q15** (Crashlytics in the app, Cloud Error Reporting on the website; no new vendor).

**Baseline:** `feature/jan-4-release` at `344b2eb`. The #3a client work starts from `hold/3a-account-gate` at `9865cd4`, which is the release branch plus #3a.

**Capacity:** the owner has about 20 h a week, about 40 h for the sprint, of which about 15 h goes to reviews and device checks and about 6 h is held for defects. Agent work is about 55 h.

## Items

| # | Item | P | Lane | h | Depends on | Done when |
|---|---|---|---|---|---|---|
| 3a-S | Fixes from the #3a security review, on the held branch | P0 | A | 3 | Review | Reviewer re-checks |
| 3a-C | App and website handle `account_incomplete`: status call, token refresh, one retry, then route to verify email, birth date or Terms. A dead-end 18+ screen. Sign-up forms for 18+ only, no guardian step. The birth date is read-only once saved. Token refresh after email verification | P0 | B + C | 10 | Contract (approved) | Widget and component tests per error. **Owner device check:** new sign-up, verify, post |
| 3a-R | Release #3a to dev: merge, then API, then TestFlight build and website, then rules last | P0 | Orchestrator | 2 | 3a-C, 3a-S | Owner OK for each deploy |
| 14 | Photo screening fails closed; DM attachments checked against the conversation and blocks | P0 | A | 6 | — | Rules and functions tests |
| 6 | Minimum-version gate: `meta/flags.minBuild` and an "Update required" screen on the app and website | P0 | A + B + C | 5 | Q19 ✔ | Unit and widget tests |
| 13 | Native video upload behind a server flag (`meta/flags.videoUploads`); short-lived signed URLs | P0 | A + B | 3 | Q19 ✔ | Widget and rules tests |
| 7 | Crash reporting: Crashlytics in the app, startup guard; `global-error.tsx` plus Cloud Error Reporting on the website | P0 | B + C | 6 | Q15 ✔ | A forced test crash shows up (device) |
| K6 / K7 | Text, spacing, corner and motion tokens on both platforms | P1 | B + C | 6 | — | K8 has 0 skips; goldens and screenshots reviewed |
| C1–C4 | Status pill, buttons, segmented tabs and chips, avatar and team logo, on both platforms | P1 | B + C | 12 | K6/K7, **owner visual OK on K2–K5** | Widget, golden and component tests; UI review |
| 24 | Home feed shows load errors instead of "caught up" | P2 | B | 1 | — | Widget test |
| INF-1 | Turn off App Store auto-submit in `codemagic.yaml` | P0 | Release | 1 | — | Config reviewed |

## Lanes (at most 3 implementation agents; no shared files)

| Lane | Owns |
|---|---|
| A, backend | `apps/api`, `firebase/**`, `packages/shared` |
| B, Flutter | `apps/mobile` |
| C, website | `apps/web` |
| Release | `codemagic.yaml` |

**Order:**
- The `meta/flags` contract comes before the clients' parts of #6 and #13.
- 3a-S lands on the held branch before 3a-R.
- K6/K7 come before C1–C4.

## Owner answers (2026-11-26)

- **Q9:** the Jan 4 beta runs on **dev**. Prod stand-up (#9, #11, #12) is needed only for the Jan 18 public release, so it moves to Sprint 3–4.
- **Q14: yes**, separate dev and prod iOS bundle IDs before the beta. This is planned for Sprint 3 and needs owner console steps:
  - a new App ID and TestFlight app;
  - the iOS app registered in the dev Firebase project;
  - its config file placed by the owner.
- **Android:** not in the beta. #10 moves after the beta.

## Still open

- Visual OK on K2–K5.
- Q16 and Q17 for later sprints.

## Not in this sprint

- #9 prod stand-up, #11 backups, #12 alerts: Sprint 3, after Q9.
- #17 and #25 (writes through the API, rules lockdown): Sprint 3–4.
- #26, #27, #29, #30.
- Shells S1–S3, navigation N1–N12, screens H/Q/L.
- #10 Android.
- New board features (L3).

## #3a security review (2026-11-26): OK to merge with fixes

**Fixes queued as 3a-S** (lane A, on the held branch, after lane A's current work):
- **F1 High:** accounts without `ageOk`, including refused minors, can still publish a searchable profile that adults can DM. Profile, username, avatar and identity writes will require `ageOk`. The app and website lanes were told to write the profile only after `ageOk`.
- **F2 High:** the LiveKit call callables (`joinToken`, `voiceToken`) and the draft and league callables don't check the account. They get the same check as the API.
- **F3 Medium:** an under-18 refusal isn't remembered, so the person can retry with an adult date. The refusal will be remembered server-side, and a different date refused afterwards. `PUT /v1/me/personal` gets a rate limit.
- **F4 Medium:** the status endpoint can run up KMS and Auth costs. It gets a rate limit, and `setClaims` will skip writes that change nothing.
- **F5 Medium (pre-existing):** clients can skip the photo check with metadata, and `photoUrl`/`headerUrl` accept any URL. Clients will be denied that metadata, and photo URLs limited to our bucket.
- **F6:** the rules will check the current Terms version as a literal, with a test that keeps it in step with `termsVersion`.
- **F8 and F9:** the API refuses to start without the cipher when a store is configured. A decrypt failure during backfill grants nothing but no longer breaks status.
- **Test gaps:** the "someone else's records" test, an incomplete-token decryption test, `oldterms` at the current version minus 1, and a static test that every rules write is gated or on the exempt list.

**Owner, 2026-11-26:**
- **Disable on under-13:** yes. An under-13 refusal also disables the Firebase Auth account.
- **Safer rollout:** yes, in this order:
  1. API with enforcement **report-only**, controlled by an environment flag;
  2. a one-off Admin SDK claim backfill on dev;
  3. the app and website updates;
  4. enforcement on;
  5. rules and the callable fixes last.

## Progress

- **On `feature/jan-4-release`:**
  - INF-1 (`ce84d11`).
  - Lane A (`cd015cb`): the `meta/flags` contract (`9695521`); #13 video uploads behind `videoUploads`; #14 photo screening fails closed and DM attachments are checked; API 0.50.0.
  - Lane C (`8eb2941`): K6/K7 on the website, with the layout pixel-identical before and after (52 of 64 screenshots identical; the rest differ only by loading timing); #7 error pages and the reporter to `POST /v1/client-errors`.
- **On `hold/3a-account-gate`:** the 3a-C website work (`58c46b6`), and the release branch merged in (`2a8c5a8`). Rules 523, API 1,485, shared 927, web 263.
- **Running:**
  - 3a-S, the security fixes plus the report-only switch and the claim backfill;
  - 3a-C in the app;
  - #13 on the website.
- **Next:**
  - the `POST /v1/client-errors` endpoint (API);
  - the app's update-required gate (#6), video flag (#13), Crashlytics (#7), K6/K7 and #24.

**Decisions from lane A for the owner:**
- **D17:** when Vision errors, the API now refuses the photo (503, retry) instead of letting it through. This is in #14's scope as "fails closed". Confirm?
- **D18:** video playback uses Firebase download tokens that never expire. Moving to short-lived signed playback URLs needs a design (Sprint 3?).
- **D19:** a photo uploaded straight to Storage is visible for a few seconds until `photoCheck` runs. Closing that window needs a "pending" marker, which is a data-shape change. Do it, or accept the window?

**Owner, 2026-11-26:**
- **D17:** yes, refuse the photo when Vision errors.
- **D18:** short-lived playback URLs move to Sprint 3.
- **D19:** the few-second window before `photoCheck` runs is accepted; no pending marker.

## Approved (owner, 2026-11-26)

The owner reviewed everything and approved it: "it all looks good".
- Approved: K2–K8 and C1–C4, with the open choices kept as built:
  - legacy danger buttons stay ink;
  - the 48 px band on the website;
  - scrolling bars;
  - logos coloured by kind;
  - profile routes lenient in report-only mode.
- The `ageRefusals` collection and contract §9 are accepted.
- Still to do: the #3a rollout steps, #7 Crashlytics and the device checks. These carry into Sprint 3 (`sprint-3-proposal.md`).

## Resumed and integrated (2026-11-26, owner away)

The owner asked for the work to be finished with the orchestrator's recommended defaults, and for UI to review by end of day. All local merges into `feature/jan-4-release` were made by the orchestrator. Nothing was pushed or deployed.

**Release branch now at `cc4fb3a`:** API 0.52.2, web 0.61.0, app 0.0.59.

**Later the same day:**
- **A second security review**, of everything after `0136df0`: OK. Its Low findings 3.1, 4.1 (a, c, d) and 5.1 are fixed in API 0.52.2 (`475cc3a`).
- **A full scan of 48 app before/after screens** found three layout regressions from the 48 px buttons. They are fixed (`cc4fb3a`):
  - the Schedule title (Today and New event became icons on phones);
  - the join-request rows;
  - the organization teams rows.
- **Open Low items (follow-up):**
  - legacy profile-photo copies in calendar, membership, roster, the meetings function, rankings, notifications and browse;
  - lh3 path breadth;
  - the 4.1b race;
  - the unreadable refusal-date branch;
  - the Dart `code` cast in `api_client.dart:204`.
- **Pre-existing failures:** three screenshot generators (home, play, tournaments registration) fail when run with `--dart-define=SCREENSHOTS`.
- **One flaky run:** a root `pnpm test` run during parallel Flutter tests had 19 API failures. Two reruns passed 1596/1596.

**Earlier in the day:** API 0.52.1, web 0.61.0, app 0.0.58, at `b471e30`.
- **Web C1–C4** (`959d6e3`, review fixes `9484518`): StatusPill, Button, SegmentedTabs and FilterChips, Avatar/TeamLogo/AvatarStack, and a `/dev/ui` gallery that returns 404 in production. #6 on the web needs no change, because the contract has no web build gate.
- **App lane B** (`0bd9569`, review fixes `d5d5e71`):
  - K6/K7 finished, so K8 runs with 0 skips;
  - C1–C4;
  - #24: home feed errors;
  - #6: minimum-build gate and "Update required" screen;
  - #13: video upload behind the flag in the app.
- **#3a** (`f5e6085`): 3a-C app and web, 3a-S fixes, and the re-check fixes for N1–N4, N6 and N7. Then `b471e30`: app callables follow the `account_incomplete` contract (QA Medium).
- **Reviews:**
  - Security re-check of #3a: OK to merge. Its new Medium findings N1–N3 are fixed.
  - UI reviews of web and app C1–C4: one app blocker (clipped team header buttons) and the should-fix items are fixed.
  - Independent QA on the integrated branch: pass.
- **Tests at `b471e30`:**
  - from earlier runs on this branch: shared 929, API 1587, web unit 385, rules 626, functions 361 + 30 server, API emulator 56 (+1 expected fail), Playwright 64 passed (48 env-gated skips), `next build` OK;
  - at `b471e30` itself: Flutter 1819 passed and 68 skipped (screenshot generators), `flutter analyze` clean, version check OK.
- **Rollout runbook:** `3a-rollout-runbook.md`.

**Waiting for the owner:**
- Visual OK on K2–K8 and C1–C4. The before/after gallery is at https://claude.ai/artifact/MmDZmm4GTs21mUjCypBQya.
- Confirm the `ageRefusals/{uid}` collection (a new data shape for F3).
- Retention policy for disabled under-13 accounts. Decide whether `ageRefusals` belongs in the data export, and whether to clean up legacy 13–17 profiles.
- **#7 app Crashlytics:** not started. It needs native setup (dSYM upload, plist) that only the owner can do.
- **3a-R:** every deploy step in the runbook. Device checks.
- **Product calls:**
  - whether legacy `.btn-danger` (ink) becomes red;
  - whether live meetings use the live (red) or accent tone;
  - whether Google photos on lh4–lh6 should be trusted as well as lh3;
  - the iOS App Store or TestFlight link for the "Update required" button (`--dart-define=IOS_UPDATE_URL`).

**Follow-ups (not done, not in scope):**
- move app screens onto `AppText`, and the ~15 raw Material chip and segment uses onto the components;
- other raw `profiles.photoUrl` reads in the API (calendar, membership, roster, browse);
- N5: the lh3 path restriction;
- `checkRevoked` on writes;
- multi-select chips in the app.

## Paused (owner, 2026-11-26)

- **Release branch:** at `a8eb380`, with lanes A and C, #13 web and the `/v1/client-errors` endpoint merged. **The #3a branch** `hold/3a-account-gate` is at `502176d`, with 3a-C web and app and #13 web merged.
- **Stopped mid-task**, with the work left in their worktrees and not merged:
  - 3a-S, the #3a security fixes and rollout switch, in `.claude/worktrees/agent-a3352841a43c9f2e6` on `sprint2/3a-fixes`;
  - lane B (app: K6/K7, #6, #13, #24) in `.claude/worktrees/agent-ad82cff501485ca43`.
- **To do on resume:**
  - review the partial work, then re-run or continue 3a-S and lane B;
  - then the app's Crashlytics (#7) and an up-front account check matching the website (on the #3a branch);
  - C1–C4, once the owner has given the visual OK on K2–K5;
  - a full regression, then the #3a rollout runbook.
- Nothing pushed. The only deploys are the ones listed earlier (dev).
