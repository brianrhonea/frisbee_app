# January release audit

**Status: findings and proposal, awaiting owner approval.** No application
code has been changed and nothing has been deployed.

- **Baseline:** `39c8a53` (`development` and `feature/platform-payments`; app 0.0.55, web 0.59.5, API 0.48.0). `main` is still `090e7b4`, the pre-monorepo MVP.
- **Method:** on 2026-11-25, seven independent read-only audits:
  - Flutter
  - website
  - backend
  - security
  - UI/UX
  - QA/testing
  - release/infrastructure

  None of them ran test suites, opened secret files or contacted live services. Their full reports, with every file:line, are in [`audit/`](audit/). I re-checked the highest-impact claims myself (marked ✔ below).
- **Evidence levels:**
  - **CONFIRMED**: read in code at the cited line.
  - **SUSPECTED**: depends on runtime, device or console state that couldn't be seen.
  - **Unverified**: anything in GitHub, GCP, Vercel, Codemagic or Stripe consoles.
- **Scope rule:** specifications describe long-term intent. Anything below marked *feature (needs approval)* is not an approved task.

Builds on [`readiness-assessment.md`](readiness-assessment.md) and
[`development-plan.md`](development-plan.md). The audit corrects them in
several places (§1).

---

## 1. Corrections to the earlier assessment

| Earlier claim | Corrected finding | Evidence |
|---|---|---|
| About 619 hardcoded colours (C-35, U2 10 h) | Most of those were `AppColors.of(context)` token calls. Real literals are about 30 `Color(0x…)` plus about 75 `Colors.white/black/transparent`. **The real UI debt is typography and spacing:** 776 literal `fontSize` values in 23 sizes, 912 numeric `EdgeInsets`, no spacing or type-scale tokens | `audit/uiux.md` §1, `audit/mobile.md` correction 1 |
| CI lacks Flutter | Flutter analyze and test run **only after merge**, inside the paid Codemagic build (`codemagic.yaml:95-98`). They never gate a PR | `audit/testing.md` CI matrix |
| The 2 failing rules tests | Both are **test bugs**: a reused doc id at `firestore.rules.test.ts:3558`, and a batch built across Firestore instances at `:3608-3623`. Because of that, the repost and shared-event rules currently have **no passing coverage** | `audit/testing.md` |
| Moderation is tested | The 9 moderation tests **run nowhere**. `firebase/functions/package.json:12` leaves out `test/moderation` ✔ | `audit/testing.md`, `audit/backend.md` B-B2 |
| App search uses the callable | `use_api_search` defaults to **false** (`feature_flags.dart:22`) ✔, so search reads Firestore directly unless `meta/flags` turns it on | `audit/mobile.md` |
| Removing `use_api_*` fallbacks closes team writes | Roster create, link and delete are **direct-only** and bypass the flags (`team_repository_firebase.dart:1105-1165`) | `audit/mobile.md` correction 4 |
| Support link and blocked list missing (F5, redesign F11) | Both exist (`guide_screens.dart:11,125`; `blocked_accounts_screen.dart`). F5 shrinks to adding the link in Settings | `audit/mobile.md` correction 2 |
| P1, P2, P3, P5, P6, P10 "fixed" | P1 and P2 are fixed. **P3, P5, P6 and P10 are partly fixed; P4, P7 and P8 are still open** in code | `audit/security.md` pentest table |

---

## 2. Feature readiness

App (A), web (W), backend (B). The ratings are Ready, Fix, Gate and Off, as in the readiness assessment.

| Area | A | W | B | Beta Jan 4 | Public Jan 18 | Key findings |
|---|---|---|---|---|---|---|
| Sign-up, sign-in, recovery | Fix | Fix | Gate | **Gate** | **Gate** | Age, Terms and verified email are enforced only in the clients. The web `PersonalGate` fails open on API errors (W-B1 ✔). The API doesn't check Terms, age or verification on writes (SEC-2) |
| Profiles, follows | Fix | Ready | Fix | Ready | Fix | Self-written team history and stats appear on public profiles (mobile correction 5, SEC-8) |
| Feed, posts, comments | Fix | Ready | Ready | Ready | Fix | About 15 direct app writes. Repost rules untested |
| Teams, roster, roles | Fix | Fix | Ready | Ready | Fix | Club 16+ can be bypassed by editing `level` (SEC-4 ✔). Roster writes are direct-only. Client-side migrations (M-B5) |
| Communities, hat, drafts | Ready | Ready | Ready | Ready | Ready | Draft steps run on the server |
| Chat, DMs | Fix | Fix | Ready | Ready | Fix | Display names can be spoofed (SEC-5/M-B3). Logging out leaves unsent messages in browser storage (W-B2) |
| Voice, meetings | Fix | Ready | Ready | Fix | Fix | Android background mic likely drops (M-B7, device). LiveKit tokens last 6 h and survive removal (SEC-15) |
| Schedule, RSVP, ICS | Ready | Ready | Ready | Ready | Ready | RSVPs use field-path updates. A failed "New calendar" clears the form (W-B5) |
| Discover, search, rankings | Fix | Fix | Fix | Ready | Fix | Rankings use self-reported stats (P7). Profile list scraping (SEC-9) |
| Tournaments, leagues (free) | Fix | Ready | Fix | Ready | Fix | Deleting a sole owner's account orphans hosted tournaments (B-B1) |
| Paid registration, payouts | — | — | — | **Off** | **Off** | Hidden until the server says available. `service.yaml:73-87` requires Stripe secrets even when payments are off (INF-8) |
| Notifications | Fix | Fix | Fix | Fix | Fix | **A signed-out user's push device can stay registered, so the next person on that phone gets their DM previews** (M-B1). Counts can double on trigger redelivery (B-B7) |
| Moderation, report, block | Ready | Ready | Fix | Ready | Fix | Invites ignore blocks (SEC-7). Team reports show rooms the admin can't read (SEC-11) |
| Staff portal | — | Gate | Gate | Fix | **Gate** | No MFA, scopes, revocation check or audit log (SEC-3) |
| Stats tracker | Fix | Fix | Fix | Fix | Fix | Last write wins; a deleted game can come back (M-B4, M-B12) |
| Playbook, video | Fix | Fix | Ready | Fix | Fix | App uploads 500 MB files directly; download links are bearer URLs (M-B6, SEC-6) |
| Account deletion, export | Ready | Ready | **Fix** | Fix | **Gate** | Deletion leaves likes, follow requests, signups, counters and `orgMembers` (B-B3). Export misses calendars, signups, payments, notifications and uploads (B-B4) |
| Legal and store | — | Gate | — | Fix | **Gate** | Draft banners and `[placeholders]`. Terms describe paid fees (W-B3) |
| UI, design system | Fix | Fix | — | Fix | Fix | §4 |
| Environments, release | Gate | Gate | Gate | **Gate** | **Gate** | §6 |
| Reliability, operations | Gate | Gate | Gate | **Gate** | **Gate** | No backups, crash reporting, minimum-version gate or correct alerts (INF-2…5) |

---

## 3. Confirmed bugs and incomplete workflows

The ones that matter for January, most severe first. Every item is
CONFIRMED unless marked otherwise. Full lists are in each report.

| ID | Sev | Where | Failure scenario |
|---|---|---|---|
| M-B1 | **P1** | `agree_terms_viewmodel.dart:16`, `choose_username_viewmodel.dart:39`, `personal_details_viewmodel.dart:21,85`; `notification_repository_firebase.dart:279-288` | Signing out from an onboarding screen doesn't unregister push. The next account on the same phone receives the first user's DM previews |
| W-B1 | **P0** | `apps/web/components/PersonalGate.tsx:63-80` ✔ | An API error sets status to `null`, and the gate only blocks on `false`/`required`. Combined with no server check, Terms and birth date can be skipped |
| B-B1 | P1 | `firebase/functions/src/account/functions.ts:302-318` vs `apps/api/src/teams/deletion.ts:44-80` | A sole owner deleting their account deletes the team without the API's cascade. Hosted tournaments are left with no host and can't be managed |
| B-B3 | P1 | `account/functions.ts:114-134, 232-252` | Deletion leaves the uid in likes and reposts, follow requests (with name and photo), signups, `limits`, `followCounts` and `orgMembers`. *Owner decision: delete, anonymise or keep* |
| B-B2 | P1 | `firebase/functions/package.json:12` ✔ | Moderation filter tests never run, so drift between the functions and shared filters goes undetected |
| W-B2 | P1 | `apps/web/lib/outbox.ts:29,121-124` | Unsent DMs and posts stay in IndexedDB after Log out, readable on a shared computer |
| W-B9 / M-B14 | P1 | `app/error.tsx`, no `global-error.tsx`; `main.dart:66-68` | Render and startup failures are never reported. A Firebase init failure gives a blank screen |
| M-B4 / M-B12 | P2 | `game_tracker_viewmodel.dart:55-64, 759-761`; `stats_repository_firebase.dart:93-98` | Two scorekeepers overwrite each other. A deleted game comes back after a pending debounced save |
| B-B4 | P2 | `apps/api/src/export/service.ts:280-330` | "Download your data" is incomplete, although it claims to cover everything |
| B-B5 | P2 | `apps/api/src/account/service.ts:83-127` | A rename or new photo isn't copied to copies elsewhere; old posts point at a deleted photo (broken images SUSPECTED) |
| B-B6 | P2 | 11 create routes (teams, tournaments, events…) | No idempotency key, so a retry after a timeout creates a duplicate |
| B-B7 | P2 | `follows/functions.ts:20,99,115` | SUSPECTED: a redelivered trigger double-counts, and nothing recounts |
| M-B2 | P2 | `notification_repository_firebase.dart:300-308` | Signing out while offline waits on a server delete and hangs |
| M-B5 | P2 | `team_repository_firebase.dart:839-888, 1073-1098` | Client-side, non-atomic data migrations run when an admin views the roster |
| M-B7 | P2 | `AndroidManifest.xml:12-13,82` | SUSPECTED (device): no microphone foreground service, so Android 14+ voice drops in the background |
| M-B8 | P2 | `ios/Runner/Runner.entitlements` | No Associated Domains entitlement, so `stall10.app/join/<code>` opens Safari. Beta invites will feel broken |
| W-B8 | P2 | `lib/api.ts:19`; `app/api/revalidate/route.ts:9` | A team switched to youth or private still serves its cached public roster for at least 60 s |
| Home feed | P2 | `apps/mobile/lib/ui/posts/view_models/home_feed.dart:53,67` | Stream errors are swallowed, and a failed load shows as "You're all caught up" |
| W-B3 | **P0** | `content/privacy.html`, `terms.html` (lines in `audit/web.md`) | Public legal pages show "Draft" banners and `[bracketed]` placeholders |
| Smaller items | P3 | `audit/mobile.md` M-B9–B13; `audit/web.md` W-B4–B7, B10; `audit/backend.md` B-B8–B15 | Swallowed errors, `notifyListeners` after dispose in debug, the unread badge caps at 100 |

No TODO, FIXME or `UnimplementedError` markers exist in `lib/`, the API, the
functions or the rules. Mobile and web both have consistent error
handling at most call sites.

---

## 4. UI modernization opportunities

The palette already matches the approved UI-updated concepts. These are
ranked by user impact against effort. *Visual only* means existing data
and logic, so no product change is needed.

| # | Opportunity | Platforms | Type | Hours | Evidence |
|---|---|---|---|---|---|
| 1 | **Type-scale and spacing tokens**, applied to the 5 tab screens, profile and team home (776 literal font sizes, 912 numeric insets) | App (web has 86 distinct CSS font sizes) | Visual only | 10 | `audit/uiux.md` §1 |
| 2 | **Contrast fixes:** status pills (`ToneTag`, `core/ui/tone.dart`) 3.1–4.2:1, amber unread dot 1.75:1, input borders 1.29:1, Stripe form green in dark 3.33:1 (`Payments.tsx:187`) | Both | Visual only | 3 | `audit/uiux.md` contrast table |
| 3 | Tab order Home · Discover · Teams · Schedule · Chats (Q2). The web also has a 6th "Learn" tab and a top bar on phones, which needs a decision | Both | Visual only | 3 | `audit/uiux.md` §6 |
| 4 | "Up next" card: attending count on the app; the web already shows RSVP | App | Visual only | 3 | `audit/uiux.md` |
| 5 | Tap targets ≥48 dp ("Undo last" while scoring is about 32 dp, `stats/widgets/game_screen.dart:386`) and text-scale clipping (chat rows fixed at 52, `chat_tab.dart:930`) | App | Visual only | 4 | UX findings |
| 6 | Web errors announced: 166 hand-made `form-error` paragraphs → shared `<ErrorNote role="alert">`; focus ring on the composer (W-B10) | Web | Visual only | 4 | `audit/uiux.md`, `audit/web.md` |
| 7 | Consolidate 24 pill/badge variants and 41 private card widgets into shared components | App | Visual only | 8 | `audit/uiux.md` §2 |
| 8 | Profile header (handle, counts) and team summary card (RSVP count) from the UI-updated Option A | Both | Visual only (but **team history must not show self-reported data**, SEC-8) | 12 | development-plan U4/U5 |
| 9 | Replace 67 `window.confirm` and about 10 `alert` calls with the themed `Dialog`; 49 raw `AlertDialog`s → `confirm_dialog.dart` | Both | Visual only | 8 | `audit/web.md`, `audit/mobile.md` |
| 10 | Playbook colours aligned between web (`app.css:1011-1049`) and app (`FieldColors`) | Web | Visual only | 1 | `audit/uiux.md` |
| — | Attendance %, team colours, Option B screens, itemized checkout | — | *Feature (needs approval)* | — | Not for January |

Already in good shape: tooltips on app icon buttons, labels and alt text
on the web, a global focus ring, reduced motion, offline banners on both,
and a shared loading/error/empty widget library used 50–60 times each.

---

## 5. Security vulnerabilities and risks

From `audit/security.md`, an independent review of the rules and API. There are
no Critical findings from code alone.

| ID | Sev | Layer | Issue | Fix |
|---|---|---|---|---|
| SEC-2 | **High** | API, rules | Age (13+ or 18+), Terms and verified email are enforced only in client forms. A REST-created account with no birthday can post, message and join. The birthday can be changed 20 times a day, which defeats club 16+ (pentest P4 open) | Server-set `ageOk` claim; rules and `requireCaller` require it plus `email_verified`; lock the birthday once set; App Check |
| SEC-1 | **High** | API, rules | With 13–17 accounts allowed, nothing limits adult-to-minor DMs or discovery (Doc 13 SP-04). `messages/service.ts:107-121` | **Adult-only launch (Q6) removes this risk.** Otherwise, age-band limits *(feature)* |
| SEC-3 | **High** | API | Broad `staff` claim, no MFA, no scopes, no audit log. Revoked or removed claims keep working up to 1 h (`server.ts:72`, no `checkRevoked`) | Revocation check on staff and money routes, TOTP MFA (Q12), scoped claims, append-only audit |
| SEC-4 | Medium | rules | `level` is editable by managers (`firestore.rules:641-648` ✔), so a team can collect under-16s and then switch to club | Remove `level` from client edits; change it through the API with an age re-check |
| SEC-5 | Medium | rules | `authorName`, quotes, `memberNames` and inviter names are free text, so people can impersonate a coach in chat | Rules compare against member names, or the client shows names from the roster |
| SEC-6 | Medium | storage | Direct uploads have no quota. DM attachments only check that the uid is in the conversation id; videos are 500 MB each (P3 partial) | F8 (video off), conversation checks, quotas or route through `/v1/uploads` |
| SEC-7 | Medium | rules, API | Team and group invites ignore blocks and mutes (`firestore.rules:408-420`, `teams/membership.ts:263-281`) | Add block and mute checks |
| SEC-8 | Medium | rules, functions | Self-written profile stats feed rankings; any member can claim any unlinked roster spot (P7 open) | Hide or derive on the server; approval for claims |
| SEC-9…17 | Low | various | Profile list scraping (50 per page with unlimited paging); director email and phone readable; team reports leak room snapshots; sign-in lockout per username not per IP (P10 partial); posts without the `private` flag from old builds; CORS wildcard (P8); LiveKit token lifetime; message-policy values; calendar token in Cloud Run URLs | See the report |
| INF-7 | Medium | CI | Backend deploy and rollback use `prod && PROD \|\| DEV`, so an unset prod secret silently deploys with dev's credentials (`deploy-backend.yml:32-33`) | Fail if the prod secret is missing |
| INF-6 | Medium | API | `server.ts:37` falls back to the dev project when `FIREBASE_PROJECT_ID` is unset; no startup environment check | Assert the project and Stripe key mode at startup |

What held up: the Stripe webhook signature check, the scheduler OIDC check, conversation membership in both layers, blocks on DMs, follows, comments and likes, private collections closed to clients, youth and private rosters hidden, generic API errors with a 64 KB body cap, and no secrets in tracked files.

---

## 6. Release and infrastructure

| ID | Sev | Finding | Evidence |
|---|---|---|---|
| INF-1 | **P0** | `main` lacks the monorepo, so no deploy or rollback workflow can run from it. The first `development` → `main` merge will **start a paid App Store submission (`submit_to_app_store: true`, `codemagic.yaml:148`) and a Vercel prod build at the same time**, before prod exists | `audit/infra.md` |
| INF-2 | **P0** | No Firestore backups or PITR | — |
| INF-3 | **P0** | No crash reporting (app or web) | M-B14, W-B9 |
| INF-4 | **P0** | Alerts probe the old `web.app` site and the functions health check, not Cloud Run `/health` or Vercel (`setup-alerts.sh:65-66`) | — |
| INF-5 | **P0** | No minimum-version gate | `audit/mobile.md` |
| INF-8 | P1 | Prod can't deploy with payments off unless all three Stripe secrets exist (`service.yaml:73-87`) | — |
| INF-10 | P1 | No Android pipeline, and **release builds are signed with the debug key** (`android/app/build.gradle.kts:36`) | — |
| — | P1 | Dev and prod iOS builds share one bundle ID (`codemagic.yaml:46`), so TestFlight-dev and the App Store build are the same app | Q14 below |
| — | P1 | The web silently falls back to `localhost` API URLs when Vercel env vars are missing (`apps/web/lib/api.ts:8`, `lib/client.ts:7`) | — |
| — | P2 | Unpinned `firebase-tools@latest` and `xcode: latest`; no `Podfile.lock`, CODEOWNERS or Dependabot; Node 22 reaches end of life Apr 2027 | — |
| — | P2 | Rate limiter is per instance (limit × up to 10 instances); LiveKit free plan, 100 concurrent, no per-room cap | — |

The ordered prod stand-up sequence, separating automatable steps from your
console steps, is in `audit/infra.md` "Prod stand-up sequence" (12 steps).

---

## 7. Existing automated test inventory

| Package | Framework | Files | Run total (today) | Notes |
|---|---|---|---|---|
| packages/shared | Vitest 5 | 58 | 922 pass | Logic plus cross-platform fixture vectors |
| apps/api (fakes) | Vitest 5 + inject | 50 | 1,307 pass | `FakeStore` has **no transaction contention**, so concurrency results are weak evidence |
| apps/api (emulator) | Vitest + emulators | 13 | not run today | Runs in CI. No payments or registration coverage |
| firebase/functions unit | Vitest 4 | 22 | 276 pass | Runs only in the manual deploy workflow |
| functions rules | rules-unit-testing | 5 | 375/377 | **Runs in no pipeline.** 2 test bugs |
| functions server | Vitest + emulator | 4 | not run | Runs in no pipeline |
| functions moderation | Vitest | 2 | never run | Left out of the script |
| apps/mobile | flutter_test + mocktail | 165 | 1,522 pass, 68 skip | The 68 skips are screenshot generators with no assertions. They aren't golden tests |
| apps/web | none | 0 | — | Root `pnpm test` excludes the web |
| Golden, integration_test, Maestro, Playwright, load | — | 0 | — | None exist |

**CI:** `ci-node.yml` covers shared, API (fakes and emulator) and web typecheck/build. Changes to `firebase/**` or `apps/mobile/**` trigger nothing on PRs. Rules deploy without `test:rules` (`_deploy-backend.yml:110`).

## 8. Missing critical tests

From `audit/testing.md`, plus security and backend additions.

| ID | P | Layer | Test | Hours |
|---|---|---|---|---|
| T-1 | P0 | rules | Fix the 2 test bugs and re-verify the repost and shared-event rules | 2 |
| T-2 | P0 | CI | Rules, server and moderation suites on PRs touching `firebase/**`; gate rules deploys on them | 4 |
| T-3 | P0 | CI | `flutter analyze` and `flutter test` on PRs in GitHub Actions (not paid Codemagic) | 3 |
| T-4/5 | P0 | rules | **Deny matrix**: signed-out, outsider, other team, other community admin, blocked and former member against every team and community subcollection, plus storage | 12 |
| T-6/7 | P0 | functions emulator, clients | Account deletion end to end (cascade, ownership hand-off, idempotent retry); export and delete UI paths | 9 |
| SEC tests | P0 | rules, API | Age and verified-email gate on writes; staff without MFA or revoked refused; club level change refused; invites blocked; author-name spoof refused (`audit/security.md` "Tests needed") | 8 |
| T-15 | P1 | E2E web | Playwright core journey on the emulator with synthetic users | 16 |
| T-16 | P1 | E2E mobile | Flutter `integration_test` core journey (simulator and emulator) | 16 |
| T-8 | P1 | API emulator | Real-transaction concurrency: last division spot, double checkout, payout sweep | 8 |
| T-10 | P1 | functions | Reminder idempotency (twice gives one notice) | 4 |
| T-12/13 | P1 | API | Chat dedupe and deny cases; payments-off configuration | 5 |
| T-17 | P1 | load | k6 at 10/50/100 virtual users, p95 < 750 ms, isolated environment | 12 |
| T-11 | P1 | — | Stats concurrent edits: **needs a product decision** (lease or merge) first | 3 |
| T-18/19 | P2 | API, web | Age edge cases; web component tests | 11 |

Physical-device-only: push on sign-out and account switch (M-B1), APNs timing, LiveKit in the background and on removal, GPS background, iOS limited photos, the payment sheet, and universal and app links. Some iOS `Info.plist` checks were out of scope under the secret-file rule; please confirm the usage strings and background modes yourself.

---

## 9. Technical debt (January-relevant only)

- **Very large files:**
  - App: `hosted_tournament_screen` 3,010 lines, `team_home_screen` 2,820, `message_thread_view` 2,585.
  - API: `payments/service.ts` 1,808, `tournaments/service.ts` 1,485.
  - Rules: `firestore.rules` 3,081.
  - Web: `app.css` 1,859, `TournamentPage.tsx` 1,043.

  Don't split before launch; it raises regression risk.
- **About 291 direct Firestore write sites in the app** (team 69, hosted tournament 42, DM 23, chat 22, events 19…). Every `use_api_*` flag is also a fallback, so those rules can't be locked down while it exists.
- **Duplication:** callables duplicate API routes (drafts, league teams, meeting tokens, search); shared filters are copied by hand into the functions; team deletion differs between the API and the functions.
- **Hygiene:** no ESLint on the web (17 `eslint-disable` comments do nothing); vitest 4 vs 5; Stripe API version unpinned (`stripe.ts:25`); all 4xx come back as 400.
- **Copies of names and photos** that never update (B-B5); counters with no recount (B-B7).
- **Not urgent:** no l10n (758 string literals), ad-hoc breakpoints, 202 of 318 web files are client components.

---

## 10. January release blockers

**Must be done before the Jan 4 beta:**
1. Production environment, or the decision to run the beta on dev (Q9). This includes a safe `main` merge plan (INF-1), Stripe secrets optional with payments off (INF-8), a startup environment check, and the deploy-secret fallback fix (INF-6/7).
2. Server-side gate for age, Terms and verified email, with the web gate failing closed (SEC-2, W-B1). Adult-only (Q6) also removes SEC-1.
3. Club 16+ bypass closed (SEC-4).
4. Push device unregistered on every sign-out (M-B1).
5. Backups on, and crash reporting in both clients (INF-2, INF-3).
6. Minimum-version gate (INF-5), so the rules can be tightened later without breaking beta builds.
7. Native video upload off (F8/SEC-6) and photo screening failing closed.
8. Android pipeline with a real upload key (INF-10), if Android is in the beta.
9. Rules and Flutter tests in CI; the 2 rules test bugs fixed (T-1…T-3).

**Must be done before the Jan 18 public release:**
10. Staff MFA, revocation checks, scoped claims and an audit log (SEC-3).
11. Account deletion cascade and export completeness (B-B1, B-B3, B-B4), after your decision on leftovers.
12. Legal pages finished and aligned with a free-only launch (W-B3); store disclosures.
13. Deny-matrix and account-deletion tests; web E2E smoke; load test; restore drill.
14. Alerts retargeted and budget alerts on (INF-4).
15. Phase-1 direct writes moved to the API and the rules locked (development plan S4/S6), including the roster writes.

---

## 11. Proposed GitHub issues

Format per CLAUDE.md §5. **"Feature"** marks a new capability that needs your explicit approval even
though it serves a release gate. Sprint = the plan's week (W1 = Nov 30).
Hours include tests. Plan IDs refer to [`development-plan.md`](development-plan.md).

| # | Title | Epic | P | Deps | h | Sprint | Testing |
|---|---|---|---|---|---|---|---|
| 1 | Fix 2 rules test bugs; run rules, server and moderation tests on PRs; gate rules deploys | Testing | P0 | — | 6 | W1 | Rules suite green; CI run shown |
| 2 | Flutter analyze and test on PRs (GitHub Actions) | Testing | P0 | — | 3 | W1 | CI run shown |
| 3 | Server age, Terms and verified-email gate (claim + rules + `requireCaller`); `PersonalGate` fails closed; birthday locked once set | Security | P0 | Q5, Q6 | 14 | W1–W2 | Rules and API allow/deny; web gate on error |
| 4 | Club level change only through the API with an age re-check | Security | P0 | — | 4 | W1 | Rules deny, API allow/deny |
| 5 | Unregister the push device on every sign-out; clear other uids' docs for the same FID; non-blocking sign-out | Mobile | P1→**P0** (privacy) | — | 4 | W1 | Unit tests; **device: account switch** |
| 6 | Minimum-version gate (`meta/flags`) with an "Update required" screen — *feature* | Release | P0 | — | 5 | W1 | Unit and widget tests |
| 7 | Crash reporting: Crashlytics and startup guard (app); `global-error.tsx` and reporting (web) — *new dependency* | Reliability | P0 | Q15 | 6 | W1 | Forced test crash on device |
| 8 | Payments-off without Stripe secrets; startup environment assertion; deploy-secret fallback fix | Release | P0 | — | 6 | W1 | API unit tests; workflow dry run |
| 9 | Safe `main` merge plan (pause the App Store auto-submit, Vercel prod env) and prod stand-up steps 1–12 | Release | P0 | Q9, your console steps | 20 | W2 | Smoke tests on prod |
| 10 | Android pipeline with an upload key; Play internal and closed tracks | Release | P0 | Play account | 8 | W2 | Build on Play internal |
| 11 | Firestore backups, PITR, restore drill | Reliability | P0 | #9 | 5 | W3 / W7 | Restore to an isolated project |
| 12 | Retarget alerts to Cloud Run and Vercel; budget alerts | Reliability | P0 | #9 | 3 | W3 | Alert delivery test |
| 13 | Native video upload behind a server flag; short-lived signed URLs | Security | P0 | — | 3 | W3 | Widget and rules tests |
| 14 | Photo screening fails closed; DM attachment conversation and block checks | Security | P0 | — | 6 | W3 | Rules and functions tests |
| 15 | Legal pages: placeholders, draft banners, free-only terms | Legal | P0 | Lawyer | 4 | W3–W5 | Manual review |
| 16 | UI tokens: type scale and spacing; contrast fixes; tab order | UI | P0 | Q2 | 16 | W3 | Golden or screenshot review, light and dark |
| 17 | Phase-1 writes through the API (posts, comments, follows, chat, DMs, events, **roster**); remove fallbacks | Security | P0 | #6 | 28 | W4 | API tests; rules deny tests |
| 18 | Author and member names checked by the rules; invites honour blocks and mutes | Security | P1 | #17 | 8 | W4 | Rules allow/deny |
| 19 | Accessibility pass: tap targets, text scaling, web error announcements, focus | UI | P0 | #16 | 8 | W5 | Widget tests; axe in Playwright |
| 20 | Profile header and team summary (no self-reported history) | UI | P1 | #16 | 12 | W5 | Widget tests |
| 21 | Stats: one recorder per game, show remote changes, no deleted-game revival — *needs decision* | Reliability | P1 | Q16 | 6 | W5 | Unit tests |
| 22 | iOS Associated Domains; Android background mic service | Mobile | P1 | Apple console | 5 | W5 | **Device** |
| 23 | Web: clear the outbox on logout; show swallowed errors; cache tags for team visibility | Web | P1 | — | 8 | W5 | Component tests |
| 24 | Home feed shows load errors instead of "caught up" | Mobile | P2 | — | 1 | W5 | Widget test |
| 25 | Rules lockdown for phase-1 paths and the deny matrix | Security | P0 | #17 | 12 | W6 | Deny matrix |
| 26 | Staff MFA (Identity Platform TOTP), revocation checks, scoped claims, audit log | Security | P0 | Q12 | 14 | W6 | API allow/deny |
| 27 | Account deletion cascade aligned with the API; export completeness | Data integrity | P0 | Q17 | 12 | W6 | Functions emulator end to end |
| 28 | Rankings from team-recorded stats only; roster-claim approval | Security | P1 | — | 6 | W7 | Rules and functions tests |
| 29 | Web Playwright core journey; Flutter integration core journey | Testing | P1 | #9 | 24 | W6–W7 | Self |
| 30 | k6 load test at 10/50/100 VU | Testing | P1 | #9 | 12 | W7 | Report |
| 31 | Low security items: profile listing, director contacts, team reports, per-IP sign-in limit, CORS, LiveKit removal | Security | P2 | — | 10 | After launch | Rules and API tests |
| 32 | Idempotency keys on create routes; counter recount job | Data integrity | P2 | — | 8 | After launch | API tests |

**Totals:** P0 about 187 h, plus the 16 h beta-defect reserve, so about
203 h. P1 is about 81 h and P2 about 19 h. The audit found new P0 work:
SEC-2's server gate, SEC-4, M-B1, INF-1/8, the deletion cascade and the rules
test bugs. Some plan items shrank (U2, F5) or folded into these issues, so
the result is close to the plan's 184 h plus the defect reserve.

## 12. Sprint recommendations

The plan's weekly structure holds (`development-plan.md` §5); the issue
numbers above fit into it. Changes the audit calls for:

- **W1 (Nov 30):** security and CI first: #1–#8. These are small, independent and unblock everything else.
- **W2:** prod stand-up (#9) and Android (#10). **Before any `main` merge, turn off `submit_to_app_store` or hold the merge** until prod is configured (INF-1).
- **W3–W4:** operations (#11–#14), UI tokens (#16), phase-1 writes (#17). The S4 estimate grows because roster writes are included.
- **W5:** UI polish (#19, #20), device-dependent fixes (#22), beta build.
- **W6–W7 (beta):** staff MFA, the deletion cascade, the lockdown, E2E, the load test.
- **Capacity:** P0 plus the defect reserve is about 203 h. At 35 h/week, about 200 h are available before Jan 18, so **P1 work fits only if capacity rises.** At 20–30 h/week, some P0 must move. Proposed moves if needed:
  - #20 (P1) moves after launch.
  - The #29 Flutter half moves after launch.
  - #26 ships with revocation checks and an audit log, but MFA only if Identity Platform is approved in W1.

  Never cut #3, #4, #5, #9, #11 or #27.

## 13. Parallel implementation

The CLAUDE.md limit is three concurrent implementation agents, each in its own Git worktree off the same starting commit. Proposed lanes with **file ownership** that doesn't overlap:

| Lane | Owns | W1 issues | W3–W4 issues |
|---|---|---|---|
| A: Backend and security | `apps/api/**`, `firebase/firestore.rules`, `firebase/storage.rules`, `firebase/functions/**`, `packages/shared/**` | #3 (server part), #4, #8 | #14, #17 (API side), #18, #25 |
| B: Flutter | `apps/mobile/**`, `codemagic.yaml` | #5, #6 (client), #7 (app) | #13, #16 (app), #17 (client switch) |
| C: Web, CI and ops | `apps/web/**`, `.github/workflows/**`, `DEPLOY.md`, `docs/**` | #1, #2, #3 (`PersonalGate`), #7 (web) | #11, #12, #15, #16 (web) |

**Contracts to fix first**, before the lanes start:
1. The `ageOk` claim name and the error code returned by gated writes (A → B, C).
2. The `meta/flags` fields: `minBuild`, `videoUploads`, `paymentsEnabled` (A → B, C).
3. The API endpoints for roster create, link and delete (A → B).

QA and security review stay **independent** of these lanes: a separate read-only reviewer per PR. Lane A changes to shared files merge first; B and C rebase onto them.

Serial only: #9 (prod stand-up, with your console steps), any `main` merge, and every deploy, each needing your OK.

---

## 14. Decisions needed

Q1–Q13 from [`development-plan.md`](development-plan.md) §11 still stand. The audit adds:

| # | Question | Recommendation |
|---|---|---|
| Q14 | Give dev and prod iOS builds separate bundle IDs (e.g. `app.stall10.dev`) so TestFlight-dev and the App Store app can coexist? | Yes, before the beta |
| Q15 | Approve Firebase Crashlytics (app) and an error reporter for the web (Crashlytics has no web SDK; options: Sentry free tier, or Cloud Error Reporting through an API endpoint)? | Crashlytics plus Cloud Error Reporting (no new vendor) |
| Q16 | Stats with two scorekeepers: one-recorder lease (simple), or field-level merge? | Lease for January |
| Q17 | Account deletion leftovers: delete likes, reposts, follow requests, `orgMembers` and counters; anonymise tournament signups; keep payment ledger rows and reports for accounting? | Yes |
| Q18 | The website's 6th "Learn" tab and phone top bar versus the app's 5 tabs: keep it as a web-specific design, or match the app? | Keep (each platform keeps its own design) |
| Q19 | Approve the minimum-version gate (#6) and video-upload flag (#13) as small features that serve release gates? | Yes |
