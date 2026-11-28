# Post-launch backlog (Jan 19 – Mar 1, 2027)

**Status:** a planning draft, written 2026-11-27 at `feature/jan-4-release` `21d6857`. **Nothing here is approved for implementation.** The owner chooses what gets built. Major features stay frozen until the owner approves them (CLAUDE.md §2 and §14), and anything involving money also needs the financial gate (section G).

**Re-check before scheduling.** Sprints 3 and 4 and the January release will change this picture, so check every "exists in part" entry again on Jan 19.

**Evidence tags:**
- **V:** confirmed in the code at the path given.
- **D:** stated in a doc, not re-checked in code.
- **A:** assumed.

**Sizes** (agent effort, tests included):
- S: 8 h or less.
- M: 9–24 h.
- L: more than 24 h.

**Priorities** (used in this document only):
- P1: in the Jan 19 – Mar 1 window.
- P2: Mar–Apr.
- P3: future, or needs product approval first.

**Platforms.** Any App + Web item ships as two parity tasks, one per lane.

**Excluded entirely:**
- USA Ultimate data or features.
- Other sports, and renaming.
- Paid memberships or subscriptions, including the "first-year premium discount".
- AI coaching, sponsorships and a public tactics library.

## 1. Carry-overs (only if they're unfinished on Jan 18)

- #25 rules lockdown and #17-B app switch. The lockdown has to wait until `minBuild` is raised.
- #18 names and invites checked by the rules.
- #21 stats lease, #23 website outbox, #29 end-to-end tests.
- #9 prod stand-up, #11 backups, #12 alerts, #30 load test (see conflict C2).
- #26 staff MFA, which is held (see C1).
- D18, short-lived playback URLs. It was moved to Sprint 3 but is missing from the Sprint 3 table (C5).

## 2. Backlog by theme

### A. Product features from the specs and mock-ups (each needs owner approval)

| ID | Objective | Exists in part? | Platforms | Size | Priority and reason |
|---|---|---|---|---|---|
| PL-A0 | Read-only audit of `product-spec.md` build steps 2–4: the News tab, community types and location, Near me, Masters, leagues limited to official hosts | Unclear (A) | All (read) | S | **P1.** It decides whether A4 and A5 are real gaps |
| PL-A1 | Profile career highlights and season stat cards (board 1) | Stats exist; no achievements model | App + Web | M/L | P2, after B4 (stats provenance) |
| PL-A2 | Team statistics dashboard: win %, trends, possession (board 2) | Stats tracker exists; no cheap W–L | App + Web | L | P3 |
| PL-A3 | Attendance tracking | No | All | L | P3. New feature and schema |
| PL-A4 | Near You, plus suggested athletes, teams and communities in Discover | Partial (A) | App + Web + API | M–L | P2. Helps empty feeds; needs a location privacy review |
| PL-A5 | Notification filter tabs | No | App + Web | S–M | P3 |
| PL-A6 | Chat: edit, search, forward | No (D) | All + rules | L | **P2.** The biggest chat gap in the specs |
| PL-A7 | Desktop chat channel sidebar and member panel; unread divider | Partial | Web, then App | M | P3 |
| PL-A8 | Bookmark, mute or hide posts | No | All | M | P3 |
| PL-A9 | "Followers only" post audience | No | All + functions | L | P3. High privacy risk |
| PL-A10 | Video: website upload, transcoding, video in posts | The app uploads behind a flag | All | L | P2, after B2/B8 and a cost and screening review |
| PL-A11 | Drawn video annotations and clips | Notes and tags exist | App + Web | M | P3 |
| PL-A12 | Seasons, recruiting, team finances and dues | No | All | L | P3. Money gate |
| PL-A13 | Community waitlists, guest policy, capacity | No | All | M | P3 |
| PL-A14 | External calendar sync (OAuth) | ICS feed exists | All | L | P3 |
| PL-A15 | Organisation console, host wizard and dashboard (board 4) | The form wizard exists | App + Web | L | P3 |
| PL-A16 | Team colour field | No (schema) | All | S–M | P3. Needs approval for the field |
| PL-A17 | Redesign leftovers: anonymous polls, vote removal, team-post likes and pushes, roster search, clinic type, opening `/tournaments` links in the app | No | All | M | P3 (the `/tournaments` link claim is P2) |
| PL-A18 | CSV roster import and assisted setup | Discord import exists | All | M | P2 |
| PL-A19 | Profile and Discover items the owner liked (2026-11-27, board Q7): career highlights and achievements (with PL-A1), a verified badge with a review process, team trend charts and career stats tiles (with PL-A2 and deeper analytics), suggested athletes with Follow and Near you (with PL-A4) | Partial | App + Web + API | L | P1/P2. Each needs its own design and approval |
| PL-A20 | **Seasons by team level** (owner, 2026-11-27: shortly after launch, first post-launch batch; board SEA1). Club teams of every division, masters included, use the calendar year (season about May to October); college uses July 1 to June 30, labelled '2026–27' (season about August to May); leagues use their own season; pickup has no season stats; youth split still to decide. One shared rule and fixture for server, app and website; profile stats, Team history and team season stats; read old year keys during the change. Later: admin-defined team seasons | Partial (calendar-year seasons today) | App + Web + API | M | **P1** |

### B. Deferred security and hardening

| ID | Objective | Exists in part? | Size | Priority and reason |
|---|---|---|---|---|
| PL-B1 | **Phase-2 writes through the API, then lock the rules:** stats, playbook, videos, meetings, drafts, tournaments | Phase 1 is done or in progress. `use_api_*` fallbacks remain in 6 app files (V) | L | **P1** (P0 under CLAUDE.md if left open, because Doc 19 P0-02 is a launch gate) |
| PL-B2 | **Storage lock:** chat, DM and post photos only through `/v1/uploads` | `storage.rules:146,186,235,288` still allow direct uploads (V) | M | **P1**, after 17-B and a `minBuild` raise |
| PL-B3 | Staff MFA, narrower staff claims, revocation checks, append-only audit log (#26) | `server.ts:94` doesn't check revocation; `:104` trusts the broad `staff` claim (V) | L | P1. **P0 the day a second staff member joins** |
| PL-B4 | Rankings only from team-recorded stats, plus approval for roster claims (#28) | `rankings/players.ts:81-89` uses self-reported stats; `firestore.rules:997` allows self-claims (V) | M | **P1.** Rankings are the competitive pitch |
| PL-B5 | Enforce App Check | `ENFORCE_APP_CHECK` is off (D) | M | P1. Run in monitor mode first |
| PL-B6 | Invites honour blocks and mutes; names checked by the rules (#18) | Partial | S–M | P2 |
| PL-B7 | Low security batch (#31): SEC-9 to SEC-17. Do SEC-12 (username lockout) and SEC-15 (a removed member staying in voice) first | SEC-9 is partly covered by the adult rule | M | P2 |
| PL-B8 | Short-lived signed playback URLs for team film (D18) | No. Download tokens never expire | M | **P1.** A removed member keeps access to team film |
| PL-B9 | Idempotency on the remaining 11 create routes, plus a counter recount job (#32) | Partial | M | P2 |
| PL-B10 | Server-side kill switches (uploads, meetings, sign-ups, payments) | Partly in `meta/flags` | S–M | P2 |
| PL-B11 | Rules leftovers: chat rooms, folders and layout writes; removing `use_api_*`, the old migrations, and SEC-13/16 | Partial | M | P2 |
| PL-B12 | Youth (13–17) accounts with guardian consent | No. The launch is adult-only | L | P3. Needs a legal review and an owner decision |

### C. Reliability and operations

| ID | Objective | Size | Priority and reason |
|---|---|---|---|
| PL-C1 | A recurring restore drill into an isolated project, measuring RPO and RTO | S per drill | **P1** (see C2) |
| PL-C2 | **Android release (#10):** a real upload key (`build.gradle.kts:36` uses the debug key, V), Play tracks, a microphone foreground service, a device pass | M–L | **P1.** The long pole for Android users |
| PL-C3 | Windows PC: first as a hand-run test machine with a golden baseline, later as a runner | S / M | P2 / P3 |
| PL-C4 | Finish the Mac route: Codemagic manual-only, then removed; commit `Podfile.lock` (it's missing, V); prod builds after #9 | S | **P1.** Codemagic still costs money |
| PL-C5 | CI hygiene: CODEOWNERS, Dependabot, branch protection, pinned Xcode. **Node 22 reaches end of life in Apr 2027** | S–M | P2. Upgrade Node in March |
| PL-C6 | Test debt: Flutter `integration_test` and Maestro core journeys, real transaction tests, reminder idempotency, age edge cases, the 3 screenshot-generator failures | L | **P1** |
| PL-C7 | A k6 load round at 100+ virtual users: the rate limiter per instance, LiveKit's 100 concurrent, hot docs | M | P2, before any marketing |
| PL-C8 | Reminders: offsets by type, a durable outbox, fan-out beyond 200 | M | P2 |
| PL-C9 | Stats: after the lease, ordered batch sync and a durable offline queue | L | P2 |
| PL-C10 | Job registry and a job-health view for staff | M | P2 |
| PL-C11 | Crash and error triage routine, incident runbook, a rollback rehearsal | S | **P1** |

### D. UX left over from the redesign

| ID | Objective | Size | Priority |
|---|---|---|---|
| PL-D1 | **Restyle the screens H1–H10 don't cover:** Discover and Explore, the athlete profile, post detail, community, organisation, competition, stats, playbook, film, meetings, the host editor, staff pages (about 97 h) | L | **P1.** Otherwise launch day shows two designs |
| PL-D2 | Move all screens onto `AppText`; replace raw Material chips | L | P2 |
| PL-D3 | Accessibility finish: 48 dp targets everywhere, 200% text, `meetsGuideline`, the remaining raw `AlertDialog`s | M–L | **P1** |
| PL-D4 | Check navigation motion on a real device (N13) | S | P2 |
| PL-D5 | Parity gaps that `product-spec.md` marks "Not yet": invitations on app Home, web search rows, personal events on Home, distance units, the group Tournaments tab, team rooms on the web | M | **P1** |
| PL-D6 | Danger-button colour and live-meeting tone (decisions) | S | P3 |
| PL-D7 | Logo and app icon, held until the name is decided | S–M | P2 |
| PL-D8 | Localisation, a token generator, shared breakpoints | L | P3 |
| PL-D9 | Option B screens: discovery hub, career-first profile, organisation and host consoles | L | P3 |
| PL-D10 | **Website-native rework** (owner, 2026-11-27: keep today's style for January, rework quickly after launch). Same features as the app, laid out like a website: persistent side menu with your teams; breadcrumb and Ctrl K search; team header with sections as top links and every action in one row; roster and stats as sortable tables with hover row actions; side columns (roles, invite link, next event, Needs you, your teams, season stats); a Home week strip and a reading-width feed; three-pane team chat (rooms, messages, members) with hover message actions and a new-messages line; keyboard shortcuts; ⋯ menus instead of bottom sheets; side panels instead of full pages; a shareable URL for every view. Mock-ups: https://claude.ai/artifact/WL8jtM5sasNacNBbBi39SV. Online status and the chat team-switcher rail are new features (see PL-A7). Board task W1 | L | **P1** |
| PL-D11 | Website team header: the Settings gear on the same row as the other actions at phone width (owner prefers one row; board FX2) | S | P2 |

### E. Low follow-ups from the reviews

| ID | Objective | Evidence | Priority |
|---|---|---|---|
| PL-E1 | Comment likes aren't removed when an account is deleted. This needs a collection-group index (owner approval) | `account/functions.ts:314-319` (V) | P2 |
| PL-E2 | Claims freshness: the adult-claim cache lasts 5 minutes; tokens can be up to an hour old; there's no revocation check | `adult_visibility.ts:16`, `server.ts:94` (V) | P2 (revocation folds into B3) |
| PL-E3 | Costs that grow with users: deletion and export scan private profiles and tournaments; reminders have no limit | `account/functions.ts:337-394` (V) | P2, before user numbers get large |
| PL-E4 | Conversations keep a deleted user's uid in `participants` and `createdBy` | `account/functions.ts:371-374` (V) | P3. But **P1 for the privacy-policy wording** |
| PL-E5 | Old profile-photo copies; renames and photo changes don't reach copied fields | 3a-F | P2 if unfinished |
| PL-E6 | Small #3a leftovers: the breadth of lh3 paths; lh4–lh6 | D | P3 |
| PL-E7 | Counter drift; team deletion leaving hosted tournaments orphaned | B-B1, B-B7, B-B15 | P2 |
| PL-E8 | Error-handling batch for app and website; W-B8 cached roster after switching to youth (privacy, 60 s) | D | P3 (W-B8 is P2) |

### F. Growth and onboarding

| ID | Objective | Size | Priority |
|---|---|---|---|
| PL-F1 | Measure activation and retention without invasive tracking (7-day activation, the 30-day review). There is no analytics package now (V) | M | **P1.** Needs an owner decision on how |
| PL-F2 | Deep links: Associated Domains and Android app links so `/join/<code>` opens the app | S–M | **P1.** The main growth loop |
| PL-F3 | Referral and share attribution, with consent | M | P2 |
| PL-F4 | Assisted roster setup and a first-week activation flow | M | P2 |
| PL-F5 | Re-engagement: notification preferences, push priming, "what's new". No email | M | P2 |
| PL-F6 | Seed empty states: suggested people, communities and nearby pickup | S–M | P2 |
| PL-F7 | Share quality for public pages: share cards, sitemap | S–M | P2 |
| PL-F8 | A "founding team" badge | S | P3 |
| PL-F9 | In-app feedback that attaches the app version | S | P2 |

### G. Money: gated, not scheduled

- **PL-G1, paid-host pilot (Doc 10).** It needs:
  - full refunds, including fees;
  - a payout cap (spec $1,500, code $2,000);
  - payment holds;
  - a freeze on bank changes;
  - receipts;
  - a legal review of the host agreement;
  - the Stripe failure test suite;
  - then an invite-only start.

  P2. Needs explicit owner approval and a security review.
- **PL-G2:** receipts, an itemised checkout, add-ons. P3.
- **PL-G3:** team dues and tax. P3.
- **PL-G4:** prod Stripe secrets, the `tournamentDeleted` function, automatic refunds when a team is declined. These are part of G1.

## 3. Conflicts between sources (not resolved here)

| # | Conflict |
|---|---|
| C1 | **Staff MFA:** held in `sprint-3-proposal.md:12`, but still listed for Sprint 4 and as required before launch (`release-audit.md:251`) |
| C2 | **The first restore drill and the first k6 run** are pre-launch gates in the audit. Only their recurring and scale versions belong in this backlog |
| C3 | **Navigation:** `product-spec.md` and the mock-up boards show other tab sets (Explore, Events, Inbox, Profile, Compete, More). The approved UI-Q11 tab set governs. Anything taken from the boards beyond it waits for a decision |
| C4 | **Home feed tabs:** the spec's Following, Community and News, against the shipped Your teams, Following and Everyone |
| C5 | **D18 signed URLs** were moved into Sprint 3 but are missing from its table |
| C6 | **"Blocked accounts":** `redesign-plan.md` says it isn't built, but block, report and the blocked list exist. That doc is out of date |
| C7 | **IDs reused** with different meanings across docs: D9, H1, S1/S2, R1–R3, F and Q numbers. Always cite the file |
| C8 | **Danger buttons:** keep ink (approved), against the redesign doc's red |
| C9 | **Week view:** `ui-migration-plan.md:165` says it doesn't exist, but `product-spec.md` says it's built |
| C10 | **Token generator:** comes after launch, which is consistent with the plan |
| C11 | **Beta length:** two weeks (Q13) against Doc 19's four. The 30-day retention review still applies |
| C12 | **Phase-2 writes:** accepted for launch, against Doc 19 P0-02 |

## 4. Proposed order for the first three sprints after launch

**Owner time:** about 20 h a week. The first sprint keeps about half of it free for support and defects; later sprints keep about 30%.

**Lanes:**
- A: API and Firebase.
- B: the app, plus iOS and Android config.
- C: the website, CI and docs.

**Sprint 5, Jan 19 – Feb 1: stabilise.**
- **Owner:**
  - review the PL-A0 audit;
  - decide whether to keep B3 (MFA) held;
  - decide how to measure activation and retention (F1);
  - set up the Play Console and keystore;
  - set up the Apple console for deep links;
  - run one restore drill.
- **Lane A:** A0, B4, E2 with revocation checks, E1, B8 design.
- **Lane B:** C2 Android, F2 deep links, D3 accessibility in the app.
- **Lane C:** C11, C5, D3 on the website, D5 parity on the website, more Playwright tests.
- **Exit:**
  - no critical or data-loss defects;
  - a restore drill logged;
  - an Android internal-track build running on a device.

**Sprint 6, Feb 2 – 15: harden and finish the design.**
- **Owner:**
  - approve the phase-2 contract (B1);
  - do an Android device pass;
  - review the UI;
  - pick a feature.
- **Lane A:** the B1 contract, then the stats and playbook routes; B5 in monitor mode; SEC-12 and SEC-15; E3 and B2 designs.
- **Lane B:** D1 app restyles, the C6 integration test, D5 parity in the app.
- **Lane C:** D1 on the website, F7, and the golden baseline on the PC (C3 i).

**Sprint 7, Feb 16 – Mar 1: close the loop.**
- **Owner:**
  - raise `minBuild`;
  - approve the rollout order;
  - review the 30-day retention report;
  - pick the first feature.
- **Lane A:** the remaining B1 routes, the B2 Storage lock, B6, B9, E3.
- **Lane B:** the rest of D1; F3 or F4; the first approved feature (likely A6 or A4).
- **Lane C:** C7 load test, F1 dashboards, the website side of the feature, C8.

**Not in these three sprints:** section G, A3, A9, A12, A14, B12, D8, D9, and anything that needs email.

**Rollout order** for any rules or Storage change:
1. the API;
2. the app and website;
3. `minBuild`;
4. the rules;
5. Storage.

Each step is a deploy the owner approves.

## 5. Decisions for the owner

| # | Decision | Recommendation |
|---|---|---|
| 1 | Staff MFA (B3) | Keep it held while you're the only staff member, but add revocation checks and an audit log now |
| 2 | Order of the phase-2 areas | Stats and playbook first; videos with B8 |
| 3 | The Storage lock (D9) | Lock after the `minBuild` raise |
| 4 | D18 signed playback URLs | Still wanted |
| 5 | How to measure activation and retention (F1) | First-party counters only; no ad tech |
| 6 | Email | Keep it off until the paid-host gate |
| 7 | The first feature from theme A | A6 (chat edit and search) or A4 (Near You), after A0 |
| 8 | Android timing | Ship iOS and the website on launch day; Android staged |
| 9 | Runners | The PC as a hand-run machine first |
| 10 | Youth accounts | Stay adult-only |
| 11 | Connected Accounts and calendar sync | Not now |
| 12 | Conversation uids kept after deletion | Keep them and document it |
| 13 | Paid-host pilot | Not before the 30-day retention review |
| 14 | The UI labels "L1–L3" and "Q1–Q4" | Define them in the UI plan |
| 15 | Logo and name | Hold |
| 16 | Items from the boards beyond UI-Q11 | Add nothing until navigation is decided |

**Not checked:**
- the UI task-board artifact;
- Docs 11, 14 and 15 line by line;
- the second half of `product-spec.md`;
- the GitHub, GCP, Vercel, Play and Stripe consoles.

**Only checkable on a physical device:** C2, F2, D4, A4 and A10.
