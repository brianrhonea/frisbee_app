# Sprint 3 proposal

**Status:** approved by the owner on 2026-11-26. It starts now (Nov 27 – Dec 11).

**Owner answers (2026-11-26):**
- **S3-1:** start now.
- **Q17:** yes. Keep the payment ledger rows; delete everything else the cascade needs to.
- **D-AR:** yes. `ageRefusals` is deleted with the account and left out of the data export.
- **D-U13:** yes. Delete disabled under-13 accounts and their data after 30 days.
- **D-1317:** yes. Hide legacy 13–17 profiles from search and DMs when enforcement turns on.
- **D11:** yes, the `fidOwners` map and trigger.
- **Q12 (staff MFA): held for later.** The owner is the only staff member. #26 leaves the January plan.
- **Q13:** yes, the two-week beta exit criteria.
- **Q16:** yes, one scorekeeper at a time (lease) for January.
- **D9, D-PT, D-LIVE, D-LH:** as recommended:
  - neutral status tags;
  - `previewTemplate` stays ungated;
  - live meetings keep indigo;
  - only `lh3` Google photos are trusted.

**Baseline:** `feature/jan-4-release` at `bde38aa` or later. That holds the Sprint 2 work the owner approved on 2026-11-26.

**Dates:** Sprint 2 finished in its first day. I propose Sprint 3 takes the Sprint 2 slot, **Nov 27 – Dec 11**, and Sprint 4 runs Dec 11 – 25. That leaves Sprint 4 to finish the app's screen work before the **Jan 8** submission freeze, with Jan 4 for the beta and Jan 18 for launch.

**Capacity:** the owner has about 20 h a week, so about 40 h this sprint:
- about 15 h for reviews and device checks;
- about 8 h for the console and deploy steps below;
- about 6 h held for defects (15%).

Agent work is about 70 h, in three lanes.

## Approach

Five strands:
1. **Ship what's built.** Roll #3a out to dev, then do Crashlytics and the bundle IDs that only the owner can do.
2. **The biggest remaining security item:** sensitive writes go through the API (#17), with the account-deletion cascade (#27).
3. **The new shell and tab order**, on both platforms.
4. **The remaining shared components (C5–C10)**, so Sprint 4 can do the three January screens: Home, Schedule and Chats.
5. **Start the prod stand-up** (#9). Prod is needed by Jan 18.

## Items

| # | Item | P | Lane | h | Depends on | Done when |
|---|---|---|---|---|---|---|
| R1 | **#3a rollout to dev** (3a-R), following `3a-rollout-runbook.md`: data checks, API report-only, backfill, apps, enforce, rules and callables | P0 | Owner, with the orchestrator | 3 (owner) | — | Each step's check passes. Device checks done |
| R2 | **#7 app Crashlytics.** The orchestrator prepares the code, and the owner does the native steps (dSYM upload phase, Firebase console) | P0 | B, then owner | 3 | Q15 ✔ | A forced test crash shows up from TestFlight |
| R3 | **Q14 separate dev and prod iOS bundle IDs.** The orchestrator prepares the code and config, and the owner does the console steps (App ID, TestFlight app, Firebase iOS app, config file) | P0 | Release, then owner | 4 | Q14 ✔ | Dev and prod builds install side by side |
| 17-C | **Contract for phase-1 API writes:** endpoints for posts, comments, follows, chat, DMs, events and roster (create, link, delete); error codes; idempotency | P0 | A | 3 | — | **Owner approves the contract** (shared API change) |
| 17-A | **#17 API side:** those writes go through the API, with authorization, validation, block and mute checks, and rate limits | P0 | A | 18 | 17-C | API allow/deny tests per route; the emulator suite |
| 17-B | **#17 app switch:** the app calls the new routes and drops the direct-write fallbacks | P0 | B | 6 | 17-A merged | Widget and unit tests; offline outbox still works |
| 17-W | **#17 website switch** (most website writes already go through the API; this closes the rest) | P0 | C | 3 | 17-A merged | Component tests |
| 27 | **Account deletion cascade** aligned with the API: likes, reposts, follow requests, `orgMembers`, counters, `ageRefusals`; anonymise tournament sign-ups; keep ledger rows and reports. Export completeness | P0 | A | 12 | **Q17**, D-ageRefusals | Functions emulator end-to-end test |
| 3a-F | **#3a follow-ups (Low):** trusted photos on the remaining copy paths (calendar, membership, roster, meetings function, rankings, notifications, browse); narrow `imageUrl`; the unreadable-date branch fails closed; the 4.1b race; the app's `code` cast | P2 | A + B | 5 | — | Unit tests per path |
| S1 | **Tab bar in the new order** (Home · Discover · Teams · Schedule · Chats), with profile from the picture at the top right (UI-Q11 ✔) | P1 | B | 3 | — | N3 and N4 tests; goldens |
| S2 | **App shell at the guide's widths** (rail 600, sidebar 900, panel 1200, cap 1600) | P1 | B | 4 | S1 | N5 widget tests at 4 widths |
| S3 | **Website shell matching the boards:** sidebar on desktop, bottom tabs on phones, Learn under Discover (UI-Q5 ✔) | P1 | C | 8 | — | N9 Playwright at 4 widths; axe |
| C5–C10 | **Remaining shared components, both platforms:** cover header (C5), summary tiles (C6), list row (C7), event card and date badge (C8), empty, error and loading states (C9), text fields, search and confirm dialog (C10). Mechanical migration only | P1 | B + C | 18 | C1–C4 ✔ | Widget, golden and component tests; UI review |
| N | **Navigation tests:** N1, N2 (routes, sign-in redirect), N3, N4, N5, N8, N9, N10 (keyboard) | P1 | B + C | 12 | S1–S3 | The tests themselves |
| 9-P | **Prod stand-up, part 1:** a written plan and checklist for steps 1–12, the `main` merge plan, and Vercel prod environment variables. The orchestrator drafts it; console steps start once the owner approves | P0 | Release, then owner | 4 + owner | Q9 ✔ | Plan approved; first console steps done |

Totals:
- agents, about 70 h: A 38, B 25 counting the app halves, C 20;
- owner, about 10 h of console work and deploys, plus review.

## Lanes (at most 3 implementation agents; no shared files)

| Lane | Owns | Starts from | Hands over |
|---|---|---|---|
| A, backend | `apps/api`, `firebase/**`, `packages/shared` | The baseline | The 17-C contract first (owner gate), then 17-A. After that, #27 and 3a-F |
| B, Flutter | `apps/mobile` | The baseline | S1, S2, C5–C10 (app), the N tests, then 17-B once 17-A merges, and R2 code |
| C, website | `apps/web`, `.github/workflows` | The baseline | S3, C5–C10 (website), N8 and N9, then 17-W |
| Release | `codemagic.yaml`, `apps/mobile/ios` config (no secret files) | After lane B's S1 merges | R3 and the 9-P plan |

**Order:**
1. The 17-C contract is approved before 17-A starts. The client switches start only after 17-A merges.
2. S1 merges before S2. The shell merges before N3–N5.
3. Each of C5–C10 merges as its own change, so it can be reverted cleanly.
4. #27 waits for Q17.
5. R1 runs in parallel, but its step 5 (rules) runs **before** #17's rules changes, so the two rollouts don't mix.

**Reviews:**
- security-reviewer on 17-C, 17-A, #27 and 3a-F;
- ui-ux-reviewer on S1–S3 and C5–C10, with a full screen before/after scan, as in Sprint 2;
- QA on the integrated branch at the end.

## Risks

- **#17 is the largest item (about 30 h across lanes).** Phase-1 write paths are spread through the app, and the offline outbox must keep working. Mitigation: contract first, route by route, and each switch merged separately.
- **Owner time.** The rollout, Crashlytics, bundle IDs and prod stand-up all need console work in the same two weeks. If time runs short, 9-P moves to Sprint 4, but prod must be ready before Jan 18.
- **The rules lockdown (#25) must follow #17.** If #17 slips, #25 (Sprint 4) gets tight before launch.
- **The new tab order changes muscle memory for beta testers.** It needs to ship in the beta build, not after.

## Decisions needed

| # | Question | Recommendation |
|---|---|---|
| S3-1 | Start Sprint 3 now (Nov 27 – Dec 11) rather than Dec 11? | Yes |
| Q17 | Deletion cascade scope: delete likes, reposts, follow requests, `orgMembers` and counters; anonymise tournament sign-ups; keep ledger rows and reports for accounting | Yes |
| D-AR | Include `ageRefusals` in the deletion cascade (yes, already done) and leave it out of the user data export, because it only holds a refused date | Yes |
| D-U13 | Disabled under-13 accounts: delete the Auth account and all data after 30 days, by a scheduled function in Sprint 4 | Yes, 30 days |
| D-1317 | Legacy 13–17 profiles made before the gate: hide them from search and DMs at enforcement; the owner contacts them about deletion | Yes |
| D11 | #5 gap: server-only `fidOwners/{fid}` map plus a trigger, so a phone left on an old account stops getting its pushes. This is a new collection and a function group | Yes (Sprint 3 if approved, lane A, 4 h) |
| Q12 | Identity Platform for staff MFA (#26, Sprint 4) | Yes. It needs the owner to upgrade the project in the console |
| Q13 | Two-week beta exit criteria: 3 active teams, 1 community, 1 completed free event, no open critical safety or data-loss defect | Yes |
| Q16 | Stats with two scorekeepers: a one-recorder lease for January (#21, Sprint 4) | Lease |
| D9 | App tournament-status and team-kind tags become neutral, like the website | Yes, in C5–C10 |
| D-PT | `previewTemplate` callable stays ungated (read-only, no data written) | Yes |
| D-LIVE | Live meetings use the live (red) tone like live games | No, keep accent; red stays for live games only |
| D-LH | Trust only `lh3` Google photos | Yes; revisit if real accounts use `lh4`–`lh6` |

## Sprint 4 (Dec 11 – 25), for planning only

- **January screens:** H1 Home with summary tiles, H2 Schedule with Month, Week and List, H7 Chats with filters. Both platforms, each in its own design.
- **Security and data:** #25 rules lockdown, #26 staff MFA, #18 names checked by the rules.
- **Reliability and tests:** #21 stats lease, #23 website outbox, #29 core-journey end-to-end tests.
- **Ops:** prod stand-up part 2 (#9), backups (#11), alerts (#12), the k6 load test (#30).
- **Release:** app UI code freeze on Jan 8.

## Out of scope for Sprint 3

- Screens H1–H10 and Q1–Q4: Sprint 4 and after.
- #10 Android: after the beta.
- #20 profile header: after launch.
- #26 MFA and #25 lockdown: Sprint 4.
- #30 load test and #11/#12: after prod is up.
- L1–L3 and new features from the boards.
- The legal pages (#15) wait on the lawyer.
- Multi-select chips in the app, and turning legacy danger buttons red.

## Owner answers on resume (2026-11-26)

The owner accepted every recommendation:
- **D-U13 signal:** a non-secret marker on the `ageRefusals/{uid}` document records an under-13 refusal, and only those accounts are deleted after 30 days. This is approved as a small schema change.
- **Data export:** new additive keys on `DataExport` for liked posts, follow requests (both directions), tournament sign-ups, calendars and invites, and usernames. `ageRefusals` stays out.
- **Scheduler:** the first scheduled function goes in the `account` group. The owner does any Cloud Scheduler setup.
- **D-1317:** hiding uses the `ageOk` claim. The #3a backfill must run before enforcement, so adults aren't hidden.
- **Website Learn:** stays a bottom tab for signed-out visitors. Members reach it under Discover.
- **The #17 contract** (`contracts/phase1-writes.md`) is approved. 17-A goes to lane A after its current items.
