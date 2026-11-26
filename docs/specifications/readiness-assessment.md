# Feature readiness: January 4 beta and January 18 public release

Assessed 2026-11-25 against `development` at `39c8a53` (app 0.0.55,
web 0.59.5, API 0.48.0), the 25 specifications, `ARCHITECTURE.md` §10,
`docs/requirements.md` (audited 2026-11-13, partly stale), the pentest of
2026-11-21 and the security fixes since then.

## Test evidence (run 2026-11-25 on this machine)

| Suite | Result |
|---|---|
| `pnpm typecheck` (shared, API, web) | Pass |
| `pnpm test`: `@stall10/shared` | 922 / 922 pass (58 files) |
| `pnpm test`: API (fakes) | 1,307 / 1,307 pass (50 files) |
| `flutter analyze` | No issues |
| `flutter test` | 1,522 pass, 68 skipped |
| `firebase/functions` `npm test` | 276 / 276 pass |
| `firebase/functions` `npm run test:rules` (emulator) | 375 / 377. **2 fail**: "user posts › validates shared events" and "user posts › lets people repost someone's post, once, with a note" (known since earlier sessions) |
| `pnpm test:api:emulator`, `npm run test:server` | Not run in this assessment (run in CI / by hand) |
| Website component tests, browser E2E, Flutter integration tests, load tests, golden/visual tests | **None exist** |

Passing unit suites show the logic is well covered. They don't show that the
user journeys work end to end on devices, and nothing tests the app's direct
Firestore writes except the rules suite.

## Rating key

- **Ready**: exists on app and web; only device verification is left.
- **Fix**: exists, but has a gap a beta tester or the public would hit; the fix is small and named.
- **Gate**: a required control is missing; it must be built before that date.
- **Off**: not in scope for that date; must be hidden or disabled **on the server**, keeping existing data.

## 1. Readiness by area

| # | Area (docs) | App | Web | API / backend | Jan 4 beta | Jan 18 public | What's left (evidence) |
|---|---|---|---|---|---|---|---|
| 1 | Sign-in, sign-up, recovery (02, 13) | Email/username, Google, Apple | Same | Account, agreement, personal routes; account deletion callable | **Fix** | **Gate** | No email-verification gate (C-26). Sign-up demands full personal details (C-25). Adult-only gate is form-only (C-24, pentest P4). Web Apple sign-in needs console setup (requirements U1). Data export exists (`apps/api/src/export`); confirm it on both clients. |
| 2 | Profiles, privacy, follows (02) | Done | Done | API (`profiles`, `follows`) | **Ready** | **Fix** | The app writes follows and some settings directly (C-23). Pentest P1 (private posts listable) fixed in 4b8ed81. |
| 3 | Home feed, posts, comments, workouts (03) | Done: For you / Following / teams, photos, workouts, GPS | Done (typed workouts only) | API for posts, likes, reposts, comments | **Ready** | **Fix** | The app writes posts and comments directly (C-23). Two failing rules tests sit on exactly this path (reposts, shared events) and must be fixed or explained. Bookmarks, mute and hide (SF-09) are missing: post-launch. |
| 4 | Teams, roster, roles, invites (04) | Done | Done | API with flag fallback | **Ready** | **Fix** | Remove the direct-write fallback once the API is required (C-23). Seasons, recruiting and finances (R01, R05, R07) are post-launch. |
| 5 | Communities, pickup, hat tournaments (05) | Done | Done | API (`group_tournaments`, `drafts`) | **Ready** | **Fix** | The app writes group tournaments and drafts directly. Guest registration, waitlists and paid activities are off. |
| 6 | Team chat, DMs, mentions, pins, polls (06) | Done | Done (since the Nov 15 review) | API | **Ready** | **Fix** | The app sends messages directly (C-23). Editing, search and forwarding (MC02, MC10) are post-launch. |
| 7 | Voice rooms and meetings, LiveKit (06) | Done | Done | API tokens; callables kept | **Fix** | **Fix** | Watch the LiveKit plan limit (5,000 project-wide participant minutes, `cloud-limits.md`); set a quota alert. Recording is off. |
| 8 | Schedule, calendars, RSVP, ICS (07) | Done | Done | API (`calendar`, `hub`) | **Ready** | **Fix** | The app writes My-calendar events and RSVPs directly. All-day/multi-day semantics and overlap queries need a device check. |
| 9 | Discover, search, learn, rankings (08) | Done | Done | API `/v1/public/*`; the app still uses the `api-search` callable | **Ready** | **Fix** | Player rankings fed by self-written stats (pentest P7, C-39): hide them or count team-recorded stats only before launch. |
| 10 | Hosted tournaments and leagues: brackets, scores, live scores (09) | Done | Done | API (the app sends some steps directly) | **Ready** | **Fix** | Real free-event pilot during beta (Doc 19 M3). Score disputes and bracket locks need an E2E run. |
| 11 | **Paid registration and host payouts** (09, 10) | Built | Built | Stripe Connect SC&T, webhooks, reconcile, staff payments | **Off** | **Off** (recommended) | Paid-hosting gate (Doc 19 P0-10) isn't met: refunds exclude fees (C-28), $2,000 review instead of the $1,500 cap and 14-day provisional hold (C-29), bank-change freeze missing, no receipt email, no legal review of the host agreement. Turn off with a server flag in prod; keep the code. Decision Q4. |
| 12 | Subscriptions (11) | — | — | Not built | **Off** | **Off** | Post-launch per Doc 11. |
| 13 | Notifications (12) | Feed + push | Feed; web push later | Functions triggers, 23–24 h reminder | **Ready** | **Fix** | Reminder retries can be lost (marker before delivery) and competition fan-out stops at 200 (C-31). Fine for beta size; fix the marker order before launch. |
| 14 | Report, block, screening (13) | Done | Done | API-only moderation; photo SafeSearch | **Ready** | **Fix** | Photo-check failure leaves the photo live; quarantine-on-failure needed (P0-05). Direct Storage uploads were tightened (P3 fixed). |
| 15 | Staff portal (14) | — | `/staff` queue and payments | Broad `staff` claim | **Fix** | **Gate** | Staff MFA, scoped roles and an audit log (C-27, P0-11). Support route: a published support@ address plus an in-app "Contact support" link. |
| 16 | Stats tracker (15) | Done | Done | API (the app writes directly) | **Fix** | **Fix** | Whole-document saves can overwrite (C-38). Beta rule: one recorder per game; show "saved" state. |
| 17 | Playbook, whiteboard, videos (16) | Done; **the app uploads native team videos straight to Storage** (`video_repository_firebase.dart`) | Done; uploads wait on transcode | API refuses video uploads until the transcode job is wired | **Fix** | **Fix** | App video uploads skip screening and quotas (P0-05). Hide them behind a flag and keep YouTube links (plan F8). |
| 18 | **UI / design system** (17, UI-updated) | Turf & Disc restyle, light/dark/system theme, 5 tabs, tablet rail, desktop sidebar | Turf & Disc tokens, theme switch | — | **Fix** | **Fix** | Palette already matches the navy + green concepts. Gaps: tab order (C-03); concept layouts for Home dashboard, athlete profile, team dashboard, tournament card and checkout; about 619 hardcoded colours (C-35); no accessibility audit; no visual regression tests. |
| 19 | Environments and release (18) | iOS TestFlight via Codemagic | Vercel dev | Cloud Run dev | **Gate** | **Gate** | **Production isn't set up**: no prod API, prod Vercel site, prod rules deploy or clean prod database. Prod Stripe secrets pending. No Android pipeline (C-34). No minimum-version gate in the app, so rules can't be locked down without breaking old builds. |
| 20 | Reliability and operations (18, 19) | — | — | — | **Gate** | **Gate** | No backups or restore drill (C-30). No crash reporting (C-32). No alerts on Cloud Run or Vercel. No load test. CI lacks Flutter and rules jobs (C-33). No branch protection evidence. |
| 21 | Legal and store (13, 19) | — | Terms and privacy drafts with placeholders | — | **Fix** | **Gate** | Fill the placeholders (5 in privacy, 4 in terms), lawyer review, App Store privacy labels, Play data-safety form, store listings and screenshots. |

## 2. Summary by gate

### January 4 closed beta (3–5 teams, 2–3 communities, 100–250 adults)

The features are there. The blockers are environment and safety, not features:

1. **Where the beta runs.** If testers are real people whose data should carry into launch, the beta must run on **production** (Doc 18: never copy real athlete data from dev). Prod then has to be live before Jan 4. Decision Q9.
2. Adult-only enforcement on the server (P0-04).
3. Store channels: TestFlight external testing needs a Beta App Review (allow 1–2 days, longer over the holidays). For Android, a Play closed-testing track needs the pipeline in §19.
4. Backups switched on and crash reporting in the builds, so beta data and defects are captured.
5. A support and feedback route.

### January 18 public release

On top of the beta gate:

1. Direct-write scope decision and its rules lockdown (C-23, Q3).
2. Staff MFA, scoped staff and an audit log (P0-11).
3. Email verification before posting, messaging and organizing (SP-01), or an explicit decision to defer it.
4. Legal review complete; store submissions approved.
5. Load test at 10/50/100 users, a restore drill, alert delivery tested, and the release checklist signed (Doc 19 §10).
6. Paid hosting and youth stay off unless their separate gates are approved.

## 3. External critical path (not code)

| Item | Latest safe date | Why |
|---|---|---|
| Decide beta environment (dev vs prod) | Nov 30 | Everything else depends on it |
| Prod Firebase rules, indexes and functions; prod API on Cloud Run; prod Vercel; Auth domains; prod secrets | Dec 19 | Two weeks of soak before beta |
| Google Play: developer account type and the closed-testing rule | Check now | New personal accounts must run a closed test with at least 12 opted-in testers for 14 continuous days, then apply for production access, and that application is reviewed. Start the closed test **about Dec 21** so it ends Jan 4 and leaves review time before Jan 18, or Android launches later. Organization accounts are exempt. Verify in Play Console. |
| Android signing key and AAB pipeline | Dec 20 | First closed-test build before the holidays |
| TestFlight external group and Beta App Review | Dec 29 | Apple review over the holidays is slower |
| Lawyer review of terms and privacy | Dec 31 | Store listings need the privacy URL |
| App Store submission (manual release) | Jan 9 | Review time plus one resubmission |
| Play production rollout (staged) | Jan 18 | After the 14-day closed test |
| Domain email support@stall10.app working | Dec 19 | Support route and store listings |

## 4. Capacity check

Doc 19 planned 240 hours over 12 weeks at 20 h/week. With the new dates and
the same 20 h/week:

| Window | Weeks | Hours at 20 h/wk |
|---|---|---|
| Nov 30 – Jan 3 (includes holidays) | 5 | about 90–100 |
| Jan 4 – Jan 17 (beta; about half goes to support and defects) | 2 | about 40 (20 for planned work) |
| **Total planned work** | | **about 110–120** |

The development plan's P0 list is about 184 hours (plan §4). That fits at
about 35 h/week, **not at 20**. The plan gives the cut order for lower
capacity. Decision Q10.
