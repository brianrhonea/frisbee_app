# Development plan: January 4 beta, January 18 public release

**Status: proposal, awaiting owner approval.** No application code changes
until it's approved (decision D-3). Based on
[`readiness-assessment.md`](readiness-assessment.md) and
[`conflicts.md`](conflicts.md). Both dates are Mondays: closed beta
**Mon Jan 4, 2027**, public release **Mon Jan 18, 2027**.

## 1. Principles

1. **Feature freeze from Nov 30.** Build nothing new beyond this list; finish, harden and test what exists (Doc 19 §02).
2. **Priorities, in your order:** UI modernization, existing functionality, security, reliability, automated testing. Tests are written with each item, not saved for the end. One exception to the order: the Doc 19 P0 safety and recovery controls are **release gates**. When time runs short, UI and P1/P2 items are cut first, never a gate (Doc 19 §07 weekly rule).
3. **Free-only launch.** Paid hosting, youth accounts and subscriptions stay off on the server, keep their data, and get their own gates later.
4. **Parity per item.** Every behaviour change ships on the app and the website with mirrored tests and both versions bumped (`CLAUDE.md`).
5. **App code freeze Fri Jan 8**, so the App Store submission goes in on Jan 9. After that, only website, API, rules and ops changes, plus critical app hotfix builds.
6. **Nothing reaches prod, `development` or `main` without your OK** (paid Codemagic builds; production deploys).

## 2. UI modernization: concepts against today's screens

The approved UI-updated concepts (Option A in each appendix) compared with
the current app and website. The palette already matches: app `theme.dart`
and web `site.css` both use ink/board navy `#0F1A2A` and accent green
`#12805C`.

| Concept element | Today | Work |
|---|---|---|
| Navy header band, green accent figures, light cards, 16-px radius | Turf & Disc restyle: navy "board" header, green accent, cards (app and web) | Consistency only (U2) |
| Bottom tabs Home · Discover · Teams · Schedule · Chat | Home · Discover · **Schedule · Teams** · Chats | Reorder (U1, if Q2 is approved) |
| Home: "Upcoming practice • 21 attending" card above the feed | "What's up next" card above the feed tabs on narrow screens, beside the feed on wide ones (`home_screen.dart`); tournament-day card | Exists. Add the attending count and an RSVP chip (U3) |
| Home: Following feed with activity posts | Your teams / Following / Everyone tabs | Exists |
| Athlete profile: @handle, followers \| teams counts, season stats, team history, Follow/Message | Profile with followers, posts, stats sections | Align the header and add season and team-history cards (U4) |
| Team dashboard: season, players, attendance %, next practice, tools | Team home with feed, schedule, chat, roster sections | Header summary and next-practice card (U5). **Attendance % needs attendance tracking, which doesn't exist (Doc 04 R06): show RSVP count instead** |
| Tournament discovery: dates, divisions, team bid, itemized checkout | Tournament lists with spots left (F10); Pay screen | Itemized fee card when payments turn on (U6, after launch) |
| Option B screens (Discovery hub, career-first profile, organization console, host console) | Partly (Discover, Explore) | After launch |
| Responsive: stacked cards and bottom tabs on mobile; persistent rail or sidebar on desktop; loading, empty and error states | Tablet rail, desktop sidebar exist (`app_shell.dart`) | State audit in U7 |

Open questions still waiting in `docs/redesign-plan.md` ("Waiting for you",
37 items) are design and behaviour details from the November redesign. None
of them blocks this plan, but #5 (logo) and #10 / F11 (blocked accounts
list) affect launch polish. Answer them alongside Q1–Q13.

## 3. Workstreams and estimates

Hours are solo-developer estimates including tests. **P0** = release gate or
must-ship; **P1** = should ship; **P2** = moves after launch first.
"Gate" is the date it must be done by.

### UI modernization (U)

| ID | Work | Docs | Gate | Pri | Hours |
|---|---|---|---|---|---|
| U1 | Tab order Home · Discover · Teams · Schedule · Chats on app tabs, rail and web sidebar; deep links unchanged | UI-updated, 17 §05 | Beta | P0 | 3 |
| U2 | Token clean-up on the five tab screens, profile and team home: hardcoded colours → theme tokens (the app has up to about 619 uses, counting `Colors.white` and `transparent`), checked in light and dark | 17 §04, §13 | Beta | P0 | 10 |
| U3 | Home "next up" card: attending count and RSVP chip, app and web | UI-updated 00/03, SF-02 | Beta | P0 | 4 |
| U4 | Athlete profile header plus season and team-history cards | UI-updated 02, PRO-03 | App freeze | P1 | 8 |
| U5 | Team home summary (season, players, RSVP count, next practice, tool shortcuts) | UI-updated 04 | App freeze | P1 | 6 |
| U6 | Itemized tournament checkout card | UI-updated 09, 17 §10 | After launch | P2 | 6 |
| U7 | Accessibility and state pass on core screens: contrast pairs, 200% text, screen-reader labels, 48-px targets, reduced motion, loading/empty/error | 17 §12 | App freeze | P0 | 6 |

### Existing functionality, release and store (F)

| ID | Work | Docs | Gate | Pri | Hours |
|---|---|---|---|---|---|
| F1 | **Android release pipeline**: Codemagic Android workflow, upload key, AAB to Play internal and closed tracks | 18 §06 | **Dec 13** (closed test must start by about Dec 21, §6) | P0 | 8 |
| F2 | Simpler sign-up: birth date (adult check), name and username; other personal details only when a feature needs them | 02 §2 | Beta | P1 | 6 |
| F3 | Core-journey device pass (Doc 19 M2): two accounts on physical iOS, Android and web; invite → join → RSVP → chat → post → free tournament | 19 M2 | Beta | P0 | 6 |
| F4 | Paid hosting off on prod: server flag hides Pay and Set up payouts; "We'll pay another way" keeps working | 10, 19 | Beta | P0 | 3 |
| F5 | Support and feedback: "Contact support / Send feedback" on app and web (mailto support@ with app version) | 14, 19 P0-09 | Beta | P0 | 3 |
| F6 | Legal and store content: fill the terms and privacy placeholders; App Store privacy labels; Play data safety; listings and screenshots | 13 SP-16, 19 P0-09 | **Jan 8** | P0 | 6 |
| F7 | Beta defects (reserve) | 19 §06 | Public | P0 | 16 |
| F8 | **Native video uploads off**: the app uploads team videos straight to Storage today (`video_repository_firebase.dart`), with no screening or quota. Hide upload behind a server flag (YouTube links stay) until the media pipeline passes | 16, 19 P0-05 | Beta | P0 | 2 |

### Security (S)

| ID | Work | Docs | Gate | Pri | Hours |
|---|---|---|---|---|---|
| S1 | Adult-only on the server: API and rules refuse sign-up and profile completion under 18; hide youth and guardian UI | 19 P0-04 | Beta | P0 | 6 |
| S2 | **Staff MFA, roles and audit**: upgrade Auth to Identity Platform and enrol staff in TOTP MFA; the API requires the token's `firebase.sign_in_second_factor` and a recent `auth_time` for staff routes; server-only staff roles; append-only `staffAuditLogs` with a required reason | 13 SP-12, 14, 19 P0-11 | Public | P0 | 10 |
| S3 | Email verification gate: posting, messaging, creating teams, events or tournaments need `email_verified`; banner plus "resend" on app and web; reports, blocks and recovery stay open | 13 SP-01 | App freeze (client) / Public | P0 | 5 |
| S4 | Close direct writes, phase 1: the app's posts, comments, likes and follows, team chat and DM sends, and events/RSVPs move to the existing API endpoints; remove the `use_api_teams/membership/profiles` fallbacks | 01 §4, 19 P0-02 | Beta build | P0 | 24 |
| S5 | Minimum-version gate: `meta/flags` minimum build, "Update required" screen | 18 §06 | Beta | P0 | 3 |
| S6 | Rules lockdown for the phase-1 paths once every beta build has S4; deny-matrix tests (cross-team, former member, blocked) | 01 §4, 13 | Public | P0 | 5 |
| S7 | Photo screening fails closed: on a SafeSearch error the photo stays hidden and is retried | 13 SP-09, 19 P0-05 | Beta | P0 | 4 |
| S8 | App Check registered on prod (App Attest, Play Integrity, reCAPTCHA Enterprise); monitor, then enforce | 01, 18, pentest P4 | Public | P1 | 4 |
| S9 | Player rankings count only team-recorded stats (or are hidden) | pentest P7, 15 | Public | P1 | 3 |

### Reliability and operations (R)

| ID | Work | Docs | Gate | Pri | Hours |
|---|---|---|---|---|---|
| R1 | **Production environment** (with you at the consoles). (a) `main` doesn't have the monorepo yet, so merge `development` → `main` first; that starts a paid Codemagic App Store build, so it needs your OK. (b) Prod database clean-up (your precondition). (c) Prod rules, indexes, functions groups; API on Cloud Run (one-time `DEPLOY.md` setup); prod Vercel on `main`; Auth domains; secrets; payments flag off. (d) **A prod beta build path**: TestFlight and Play closed builds from `main` against prod (today `development` → TestFlight runs against dev). (e) Exact CORS origins (pentest P8) and API-key restrictions (P9). (f) Environment assertion at API start | 18 §04, 19 P0-01 | **Dec 19** | P0 | 20 |
| R2 | Backups: daily Firestore backup schedule, 30-day retention on prod; restore drill into an isolated project; measured RPO/RTO | 18 §14, 19 P0-07 | Beta (schedule) / Public (drill) | P0 | 5 |
| R3 | Crashlytics in the app; website error reporting; uptime checks on the prod API and site; budget alerts 50/75/90/100%; alert delivery tested | 18 §12, 19 P0-08 | Beta | P0 | 6 |
| R4 | Emergency switches (uploads, meetings, sign-ups, payments) checked end to end | 14 §07, 13 SP-14 | Public | P0 | 3 |
| R5 | Reminder marker written after delivery; competition fan-out paged past 200 | 12 | Public | P1 | 4 |
| R6 | Stats safety: one recorder per game (claim/handoff), visible saved state | 15, 19 P1-09 | Beta | P1 | 6 |
| R7 | Incident runbook, rollback steps, release manifest, signed release checklist | 18 §05, §12, 19 §10 | Public | P0 | 3 |
| R8 | Load test 10/50/100 virtual users (k6) against dev with synthetic data | 18 §10, 19 §10 | Public | P0 | 5 |

### Automated testing (T)

| ID | Work | Docs | Gate | Pri | Hours |
|---|---|---|---|---|---|
| T1 | CI: add `flutter analyze` + `flutter test`, functions tests and the rules emulator suite; **fix the 2 failing rules tests first**; required checks on `main` once it has the monorepo | 18 §03, 19 P0-06 | Beta | P0 | 7 |
| T2 | Web E2E smoke (Playwright, emulators): sign in, create team, invite and join, event and RSVP, chat, post | 18 §08 | Public | P0 | 8 |
| T3 | App integration smoke (Flutter `integration_test`) of the same journey on an Android emulator | 18 §08 | Public | P1 | 6 |
| T5 | Website component tests (Vitest + Testing Library) for the S1, S3 and F2 forms | 18 §08 | Public | P2 | 4 |
| T7 | Account deletion and data export tests: API and emulator, both clients' entry points | 19 P0-03 | Public | P0 | 3 |

## 4. Totals, capacity and cut line

| Group | P0 | P1 | P2 |
|---|---|---|---|
| UI | 23 | 14 | 6 |
| Functionality and release | 44 | 6 | — |
| Security | 57 | 7 | — |
| Reliability | 42 | 10 | — |
| Testing | 18 | 6 | 4 |
| **Total** | **184** | **43** | **10** |

Available planned hours from Nov 30 to Jan 17, with about half of the two beta weeks going to support:

| Hours per week | Available | Fits |
|---|---|---|
| 20 (Doc 19 assumption) | about 115 | **Not all P0.** Needs the cuts below |
| 30 | about 170 | P0 nearly; P1 cut |
| 35 | about 200 | All P0 and some P1 |

If capacity is below about 35 h/week, cut in this order (Doc 19 §07: cut
P2/P3, then optional P1, then move the date, never a gate):

1. All P2 items and U4–U5 (‑24 h).
2. S4 narrowed to posts/comments/follows and chat; events/RSVP move to the week after launch with today's rules (‑8 h).
3. T3 dropped; S8 and S9 move after launch (‑13 h).
4. R1(d) simplified: the beta runs on dev, prod is set up during the beta, and beta accounts are re-created on prod at launch (‑6 h, but testers lose beta data; Q9).
5. Still short: **release web and iOS on Jan 18, Android when Play grants production access**, rather than dropping a gate.

## 5. Week-by-week schedule (the 35 h/week version)

| Week (Mon–Sun) | Build | Your action |
|---|---|---|
| **Nov 30 – Dec 6** | T1 CI + rules fixes · S5 min-version · S1 adult-only · R3 crash and alerts · F4 payments flag · U1 tabs (28 h) | Approve the plan; answer Q1–Q13; check the Play account type; start the lawyer review |
| **Dec 7 – Dec 13** | R1 prod environment, parts a–c and e · F1 Android pipeline · F2 sign-up (34 h) | OK the `main` merge; prod DB clean-up; Play app, signing, testers list; support@ mailbox |
| **Dec 14 – Dec 20** | R1(d) prod beta builds, R1(f) · R2 backups · F5 support · U2 tokens · U3 next-up card · F8 video upload off · S7 photo screening (32 h) | Recruit 3–5 teams, 2–3 communities, 2–3 organizers; **12+ Android testers opted in** |
| **Dec 21 – Dec 27** (holiday) | S4 direct writes, social + chat + events (24 h) · **Android closed test starts Dec 21** with the current build | — |
| **Dec 28 – Jan 3** | F3 device pass · S3 email verification · U7 accessibility · U4 profile · U5 team home · R6 stats safety · beta build to TestFlight and Play closed (35 h) | **TestFlight beta review submitted by Dec 29**; beta welcome note |
| **Jan 4 – Jan 10** (beta week 1) | F7 defects · F6 store content by Jan 8 · **app freeze Jan 8** · S6 rules lockdown · S2 staff MFA and audit (29 h) | Onboard teams; **App Store submission Jan 9** (manual release); apply for Play production access when the 14-day test completes |
| **Jan 11 – Jan 17** (beta week 2) | F7 defects (web/API) · R8 load test · R2 restore drill · R4 switches · R7 runbook · T2 web E2E · T7 deletion/export tests · S9 · R5 (34 h + 3 h) | Sign the release checklist |
| **Mon Jan 18** | Web live; iOS released manually; Android staged rollout if Play production access is granted | Announce |

## 6. External critical path

| Item | Date | Note |
|---|---|---|
| Play account type and closed-testing rule | **Check now** | New personal Play accounts must run a closed test with at least 12 opted-in testers for 14 continuous days, then **apply** for production access, and that application is reviewed. Start the closed test about Dec 21, so it ends Jan 4 and leaves review time before Jan 18. Organization accounts are exempt. Verify the exact current rule in Play Console. |
| `development` → `main` merge (paid Codemagic build) | Dec 7–13 | Needed for prod deploy workflows and prod builds |
| Prod environment live | Dec 19 | Beta on prod (Q9) |
| TestFlight external testing review | Submit by Dec 29 | Holiday review times |
| Lawyer review of terms and privacy | Dec 31 | Store listings need the URLs |
| App Store submission | Jan 9 | Manual release on Jan 18 |

## 7. Coverage of the approved launch gates

How each binding gate from Doc 19 §08/§10 and the general-launch gates in
Docs 13 §11 and 14 §10 is covered.

| Gate | Covered by | Not covered → needs your sign-off |
|---|---|---|
| P0-01 prod environment, provider modes | R1 | KMS key retention review is part of R1(c); no separate drill |
| P0-02 API-authoritative sensitive writes | S4, S6 (phase 1) | **Phase 2 paths stay direct at launch** (stats, playbook, videos, meetings, drafts, group/hosted tournament saves), protected by today's rules. Q3 |
| P0-03 auth, recovery, verified email, deletion/export tests | S3, T7, F3 | — |
| P0-04 adult-only | S1 | — |
| P0-05 private media ACL, screening, quotas | S7, F8 | Per-scope storage quotas (Doc 11) not built; uploads limited to photos with existing size limits |
| P0-06 required PR checks, E2E, fixtures | T1, T2 | Payment suites run in CI but payments are off |
| P0-07 backups and restore | R2 | — |
| P0-08 alerts, flags, job health, incident drill | R3, R4, R7 | Central job registry (Doc 14 §07) after launch; job health checked through logs |
| P0-09 terms, privacy, store disclosures, support contact | F5, F6 | Lawyer review is external |
| P0-10 paid-hosting gate | — (payments off, F4) | Separate gate after launch |
| P0-11 report/block, staff MFA, audit, support queue | S2, existing report/block | **Native support tickets (Doc 14) deferred**: support@ email instead. **Appeals (Doc 13 SP-11)**: by email to support, recorded in the staff audit log; no appeal UI at launch |
| P0-12 no critical defects; device, browser, accessibility, load evidence | F3, F7, U7, R8 | — |
| Doc 13 general launch: quarantine, export/deletion, incident controls, published policies | S7, T7, R4, F6 | Community, youth-safety and vulnerability-disclosure policies: short pages added under F6 |
| Doc 19 §11 beta exit criteria (4 weeks; 3 active teams, 2 communities, 1 completed free competition, 60% activation) | Two-week beta | **The criteria assume four weeks.** Proposed for two: at least 3 active teams, 1 community, 1 completed free pickup or hat event, no open critical safety or data-loss defect. Q13 |

## 8. Explicitly off at launch (server-enforced, data kept)

Paid registration and host payouts · youth (13–17) accounts and guardian
features · subscriptions and premium · native video uploads (YouTube links
stay) · meeting recording · transactional and notification email (Firebase
Auth verification and reset only) · username changes · seasons, recruiting,
attendance and team finances · bookmarks, mute and hide · saved searches ·
support tickets and appeal UI (email instead).

## 9. After launch (from Jan 19, in order)

1. Phase 2 direct-write migration and full rules lockdown.
2. Paid-host pilot gate (Doc 10): full fee refunds for host cancellation, fraud and platform errors; $1,500 provisional cap; 3/14-day holds; bank-change freeze and re-approval; receipt email; host agreement legal review; Stripe test-mode failure suite; then invite-only.
3. Reminder offsets per event type; durable notification outbox (Doc 12).
4. Stats event-batch sync and offline queue (Doc 15).
5. UI Option B concepts, desktop contextual panel, shared design-token values.
6. Support tickets and appeals UI (Docs 13, 14); youth gate (Doc 13 §05); subscriptions (Doc 11).

## 10. Specification updates (after approval)

- Doc 19 §01, §06, §07, §11: replace with §5 above, the two-week beta and the adjusted exit criteria.
- Doc 18 §15: map phases 1–4 onto the Jan 4 / Jan 18 gates.
- Doc 17: palette follows the UI-updated concepts; tab order per Q2.
- Docs 10 and 19: paid hosting off at launch (Q4).
- README decision log: the answers to Q1–Q13.

Edit the Word originals and regenerate the Markdown with
`tools/docx2md.py`, or treat the Markdown as the source from now on (Q11).

## 11. Decisions needed

| # | Question | Recommendation |
|---|---|---|
| Q1 | Palette: follow the UI-updated navy + green (today's Turf & Disc) and drop Doc 17's indigo? | Yes |
| Q2 | Tab order Home · Discover · **Teams · Schedule** · Chats (UI-updated), or keep Schedule before Teams (Doc 17, current)? | Switch; keep "Chats" |
| Q3 | Direct writes: phase 1 (social, chat, events) before launch, phase 2 right after, with today's rules in between? | Yes |
| Q4 | Paid hosting at launch? | Off; invite-only pilot after the Doc 10 gate |
| Q5 | Email at launch limited to Firebase Auth verification and reset? | Yes, for a free-only launch |
| Q6 | Adult-only (18+) at launch, enforced on the server? | Yes (Doc 19) |
| Q7 | Sign-up asks only for birth date, name and username? | Yes |
| Q8 | Shared design-token values, per-platform components, after launch? | Yes |
| Q9 | Beta on **production** (data carries into launch) or on dev? | Production, if R1 can land by Dec 19; otherwise dev with re-registration |
| Q10 | Weekly hours until Jan 18? | Sets the cut line in §4 |
| Q11 | After this, is Markdown or Word the source of truth for specs? | Markdown |
| Q12 | Upgrade Firebase Auth to Identity Platform for staff MFA (S2)? Today's projects use plain Firebase Auth | Yes (TOTP; no SMS cost) |
| Q13 | Two-week beta exit criteria as in §7? | Yes |
