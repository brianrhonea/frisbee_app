<!-- Converted from Stall10_19_Product_Roadmap_Launch_Strategy.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# Product Roadmap & Launch Strategy

DOCUMENT 19  /  VERSION 1.0  /  25 NOVEMBER 2026

Approved product direction • Founder execution plan

### Executive decision

Launch a controlled, feature-rich adult ultimate frisbee platform within three months, targeting February 2027. Stabilize existing functionality rather than implement every approved specification. At 20 hours per week, six two-week sprints provide 240 hours, including contingency. The date is a target, not permission to bypass release gates.

### Product positioning

Stall10 is the home for your sporting life: find your community, manage your team, compete, improve and stay connected. Start with DFW adult club teams, pickup communities and tournament organizers; expand across Texas and then nationally. Keep sport-neutral light/dark design and extensible sport contracts.

### Operating model

Solo founder, two-week sprints, GitHub Projects, free core platform, verified-host transaction pilot and later premium subscriptions. Infrastructure target $50–$150/month; organic marketing $0–$100/month. Paid hosting and youth participation have independent gates.

### Reading guide

02 Approved decisions • 03–04 Implementation assessment • 05 Scope • 06–07 Sprint plan • 08–09 Backlog and dependencies • 10 Release gates • 11 Beta • 12 Acquisition • 13 Monetization • 14 Revenue • 15 Metrics • 16 Expansion and risks • 17 Operating cadence and sources.

## 02  Approved strategic decisions

| Decision | Approved direction |
|---|---|
| Capacity / timing | 20 hours/week; accelerated public launch within three months, reduced scope. |
| MVP | Feature-rich controlled MVP; stabilize existing features, defer major additions. |
| Market / audience | DFW → Texas → national ultimate; adult club teams, pickup communities, organizers. |
| Beta | 3–5 teams, 2–3 communities, 2–3 organizers, 100–250 athletes. |
| Platforms | Coordinate public web, iOS and Android around readiness. |
| Paid hosting | Invite-only verified-host pilot after financial safeguards; controlled expansion. |
| Subscriptions | Free core and transaction revenue initially; premium after retention and usage validation. |
| Acquisition | Founder-led onboarding, partnerships, referrals, organic content. |
| Founding incentives | Early access, recognition, proposed 50% first-year premium discount. |
| Marketing | Organic-first $0–$100/month; expand only with retention evidence. |
| Year-one targets | 2,500 registered athletes; 1,000 MAU; 75 active teams; 25 communities; 50 paid tournaments. |
| Success | Weekly meaningful activity, team retention, organizer repeat usage, transaction revenue, contribution margin. |
| Expansion | Validate ultimate; select next sport by demand, relationships and implementation cost. |
| Staffing | Solo initially; two-week sprints and GitHub Projects; specialist contracts when justified. |

## 03  Implementation baseline: 00–09

Source-based assessment as of November 25, 2026. Substantial means meaningful existing code, not verified readiness. Partial means material gaps. Release evidence must be recorded separately.

| Doc / area | Assessment and remaining work |
|---|---|
| 00 Blueprint | Substantial: integrated product structure; validate complete journeys. |
| 01 Architecture | Substantial: Flutter, Next.js, Fastify, Firebase; close sensitive direct-write paths. |
| 02 Identity | Partial: auth/profile/privacy present; guardian verification and historical identity incomplete. |
| 03 Social | Substantial: follows, posts, workouts; refine audiences, feed and private training. |
| 04 Teams | Substantial: roster, roles, invites; season identities, recruitment and finance extensions. |
| 05 Communities | Substantial: groups, pickup and hosting; recurring events, waitlists, guest policy. |
| 06 Messaging | Substantial: team channels, DMs, mentions; verify web parity, privacy and moderation. |
| 07 Calendar | Partial: shared calendars and RSVP; verify ICS, recurrence and canonical events. |
| 08 Discovery | Partial: search and browsing; local relevance, personalization and saved searches. |
| 09 Marketplace | Substantial: registration, seeds, brackets, results; real-event validation and capacity checks. |

Evidence: development tree contains corresponding API services and web routes. Release notes describe registration and roster completion, roles, chat mentions and calendar sharing. Requirements audit dated November 13 predates recent changes; do not treat its missing-web-messaging row as current truth.

## 04  Implementation baseline: 10–18

| Doc / area | Assessment and remaining work |
|---|---|
| 10 Payments | Partial: Stripe platform charges, host payouts, refunds and reauthentication documented; risk tiers, independent completion, reconciliation and refund policy gaps. |
| 11 Subscriptions | New development: provider billing, server entitlements, usage quotas and premium catalog. |
| 12 Notifications | Substantial: push/feed and reminders; durable outbox, retry and preference improvements. |
| 13 Safety | Partial: report/block, terms and privacy; guardian approval, fail-closed screening and incident response. |
| 14 Administration | Partial: staff moderation/payment tools; support and operational queues. |
| 15 Statistics | Substantial: tracker and summaries; durable offline sync, canonical games, revisions and provenance. |
| 16 Coaching | Substantial: play editor, whiteboard, video notes/clips; secure media pipeline, revisions and assignments. |
| 17 Design | Partial: existing theme and redesign work; neutral palette, shared tokens, accessibility and consistency. |
| 18 Deployment | Release validation: existing CI, Cloud Run and iOS workflows; Android, required checks, load and restore evidence. |

### Immediate contradictions to resolve

Release 0.0.51 describes refunds excluding service/processing fees; Doc 10 requires full mandatory-fee refunds for host cancellation, fraud and platform errors. Fix before paid hosting. Existing beta checklist contains provisioning placeholders and older UI wording; verify current state rather than assume outstanding or complete. Current brand assets include turf-green; Doc 17 supersedes that visual direction.

## 05  Scope and cut line

| Ship if validated | Defer or disable until ready |
|---|---|
| Adult identity, privacy, block/report, account recovery and deletion | Youth onboarding until guardian and communication safeguards pass. |
| Posts, follows, comments, core feed and workout sharing | Advanced ranking, fitness integrations, stories and independent training expansion. |
| Teams, roles, roster, invitations, chats, schedules and RSVP | Advanced recruitment, season migration beyond safe minimum, complex recurrence. |
| Communities, local discovery, free event hosting and basic competition results | Advanced automation, saved searches, guest registration extensions. |
| Existing stats and playbook workflows with safe persistence | Advanced ratings, collaborative editing, assignments and public templates. |
| Authorized YouTube; native media only if screening, ACL and quotas pass | Advanced video, AI, rendered reels, expensive meetings without cost controls. |
| Web, iOS and Android with core parity | Desktop native apps, broad redesign beyond core tokens and critical journeys. |
| Essential staff operations and free platform | Premium billing and advanced dashboards; paid hosting separately gated. |

Scope reductions must be explicit and server-enforced where applicable. Hide unsupported controls, retain existing data and provide safe read/export access. Do not disable account recovery, moderation, essential notifications or financial reconciliation to meet a date. If reliable statistics or media cannot be made safe within budget, restrict recording/upload rather than ship data-loss or privacy defects.

## 06  Twelve-week execution plan

Proposed dates assume kickoff November 30, 2026. Each sprint has 32 planned hours and 8 hours for defects, support and uncertainty. Total 192 planned + 48 reserve = 240 hours. Holidays and store approvals may extend elapsed time.

| Sprint / dates | Planned work (32h each) | Exit evidence |
|---|---|---|
| 1 • Nov 30–Dec 13 | Inventory and flags 6h; auth/rules 12h; CI/env 10h; incident setup 4h. | Release registry; verified dev isolation; critical deny tests. |
| 2 • Dec 14–27 | Sensitive writes 12h; media safety 8h; recovery 8h; support 4h. | No unsafe enabled paths; restore evidence; support route. |
| 3 • Dec 28–Jan 10 | Neutral tokens 8h; onboarding 8h; team/chat/calendar fixes 12h; accessibility 4h. | Core journeys pass on web and devices. |
| 4 • Jan 11–24 | Beta onboarding 8h; competition tests 8h; stats/playbook safety 8h; notification fixes 8h. | Real cohort using core workflows; defects triaged. |
| 5 • Jan 25–Feb 7 | Load/CI 10h; beta defects 10h; store builds 8h; launch content 4h. | 10/50/100 load evidence; candidate builds submitted. |
| 6 • Feb 8–21 | Regression 12h; operational drills 8h; release promotion 8h; launch onboarding 4h. | Owner gate approval; coordinated release if ready. |

Paid-host pilot preparation may use reserve only after core blockers are resolved. The financial work is not assumed to fit inside 240 hours. Start provider/store enrollment and external review in sprint 1; track waiting time separately.

## 07  Milestones and scope control

| Milestone | Acceptance / decision |
|---|---|
| M0 • Sprint 1 | Freeze new features; inventory deployed versions, flags, source and test status; confirm store accounts. |
| M1 • Sprint 2 | Adult-only safety boundary, recovery drill and secure core paths; disable unready optional features. |
| M2 • Sprint 3 | Internal alpha: two accounts on physical iOS/Android and web; complete invite → RSVP → chat journey. |
| M3 • Sprint 4 | Closed beta cohort invited; at least one real free event exercised; weekly feedback and defect review. |
| M4 • Sprint 5 | Release candidate: load tests, compatibility, privacy/legal review, store submission and rollback plan. |
| M5 • Sprint 6 | Public launch only after core gates pass; paid hosting and youth remain disabled unless separately approved. |
| M6 • Post-launch | 30-day retention review; prioritize reliability, host pilot and usage measurement before premium development. |

### Weekly decision rule

Re-estimate remaining work every Friday. If forecast exceeds remaining capacity, remove P2/P3 work first, then disable optional P1 features with safe fallbacks. Never trade away P0 controls. If mandatory work still exceeds capacity, move the launch date. Do not interpret a three-month target as a guarantee.

### After launch

First 30 days: support, retention and defects. Months 4–6: controlled paid-host pilot if ready, durable stats and calendar improvements, entitlement design. Months 6–12: premium rollout after validation, regional organizer acquisition, advanced coaching and discovery. Timing is conditional, not committed.

## 08  P0 backlog: mandatory controls

| ID / docs | Task and acceptance evidence |
|---|---|
| P0-01 • 01/18 | Verify production Firebase, KMS, storage, API, secrets and provider modes; environment assertions pass. |
| P0-02 • 01/13 | Sensitive writes API-authoritative; cross-workspace deny tests; no insecure fallback. |
| P0-03 • 02/13 | Auth, recovery, verified email, account isolation and deletion/export tests. |
| P0-04 • 02/13 | Adult-only launch enforcement; youth routes and direct writes cannot bypass gate. |
| P0-05 • 03/13/16 | Private media ACL, screening and quotas; quarantine failures; disable unsafe uploads. |
| P0-06 • 18 | Required PR checks, security and payment suites, core E2E and shared fixtures. |
| P0-07 • 18 | Daily backup configuration; successful isolated restore; measured RPO/RTO. |
| P0-08 • 14/18 | Alerts, emergency flags, job health, incident and rollback drill. |
| P0-09 • 13/18 | Review terms, privacy, store disclosures and support contact; record approval. |
| P0-10 • 09/10 | Separate paid gate: ledger, verified host, holds, refunds, disputes, reconciliation and risk tests. |
| P0-11 • 13/14 | Report/block, staff MFA and scoped audit; support queue and escalation. |
| P0-12 • 17/18 | No critical release defects; device/browser, accessibility and load evidence. |

## 09  P1–P3 backlog and dependencies

| Priority / ID | Deliverable |
|---|---|
| P1-01–04 | Neutral tokens; onboarding/deep links; compact Home; Discord-inspired channels (02/03/06/17). |
| P1-05–08 | Roster/roles; calendar/RSVP; local discovery; free tournament hosting (04/05/07/08/09). |
| P1-09–12 | Safe stats sync; playbook/media protection; notification reliability; device/browser parity (12/15/16/18). |
| P2-01–04 | Billing/entitlements; advanced analytics; recruitment; personalized discovery (02/04/08/11/15). |
| P2-05–08 | Film/coaching; organizer finance automation; fitness integrations; storage/meeting add-ons (06/09/10/11/14/16). |
| P3 | Additional sports, AI coaching, public tactical library, sponsorships and advanced search. |

### Dependency order

| Prerequisite | Dependent capability |
|---|---|
| Identity, authorization, workspace membership | All private social, chat, team and coaching actions. |
| Stable team/season/event/game IDs | Calendar, competition, verified stats and athlete history. |
| Host verification, ledger, completion evidence | Live payments, transfers and refunds. |
| Media reservation, screening, ACL and cleanup | Native uploads, clips, film review. |
| Usage measurement and server entitlements | Premium billing and add-ons. |
| Versioned sport definitions and fixtures | New sports, scoring and tactical layouts. |

Create one GitHub issue per testable deliverable. Split work exceeding eight hours into smaller tasks; record dependency IDs, owner, estimate, acceptance, flag, test evidence and release milestone. P0-10 is mandatory for paid hosting, not a blocker for a free-only launch.

## 10  Release gates and operating safeguards

| Gate | Required evidence |
|---|---|
| Core functional | Critical journeys pass web/iOS/Android; old clients compatible; no unresolved critical defects. |
| Security / privacy | Auth and rules tests, staff MFA, account deletion, moderation, private media and incident response. |
| Performance / recovery | 10/50/100 concurrent-user tests; warm p95 &lt;750ms objective; 99.5% monthly availability objective; daily backups, 24h RPO/RTO target, restore drill. |
| Operations | Alerts delivered, support contact, release manifest, rollback, budget thresholds and emergency switches. |
| Paid hosting (independent) | Stripe verification, risk review, independent completion evidence, ledger, refund policy, bank-change controls, dispute handling, reconciliation and test-mode failure scenarios. |
| Youth (independent) | Verified guardian consent, age restrictions, supervised communication, privacy defaults, escalation and policy review. |

Document 10 controls remain binding: proposed first-three-event enhanced review and $1,500 collection cap, established/provisional 3/14-day post-verification holds, justified reserves, bank-change freeze and mandatory full refunds in specified cases. No real financial tests in automated production smoke checks. Financial reconciliation remains independent of backup restoration.

Release owner signs each applicable gate with commit, environment, evidence links, date and decision. Store review or failed gate may delay a platform; communicate availability accurately. No 24/7 support promise.

## 11  Closed beta and organizer pilot

### Recruitment

Target 3–5 adult competitive teams, 2–3 pickup communities, 2–3 organizers and 100–250 athletes. These are targets, not confirmed participants. Recruit through existing DFW relationships; obtain permission before using names, logos or testimonials.

| Week of beta | Activity |
|---|---|
| Before access | Confirm adult eligibility, invite contacts, consent to feedback, explain beta limitations and support. |
| Week 1 | Assisted roster import or manual setup, team invites, schedule and first RSVP; record activation friction. |
| Week 2 | Observe practice/pickup event; test chat, notifications, stats and free competition workflow. |
| Week 3 | Repeat workflows, test offline/reconnect, collect captain and organizer interviews. |
| Week 4 | Review retention, defects and readiness; publish changes and thank participants. |

### Proposed beta exit criteria

At least three active teams, two active communities and one completed free competition; 60% seven-day activation target; no unresolved critical safety/data-loss defects; all applicable release gates pass. Small samples are directional. If recruitment is slower, extend beta rather than manufacture activity.

### Paid pilot

After separate approval, onboard verified hosts individually, start with limited collection exposure, monitor registration through settlement and reconcile every transaction. Expand only after repeat successful events and reviewed fraud/support burden. Free events and offline fee tracking may continue independently.

## 12  Acquisition and market entry

| Channel | Founder action / measurement |
|---|---|
| Captains | Personal outreach, 20-minute setup, invite roster; measure activated teams. |
| Pickup organizers | Publish real recurring activities and public discovery links; measure RSVP and repeat events. |
| Tournament directors | Assist event setup and scheduling; measure completed events and repeat hosts. |
| College clubs | Approach adult club leadership after local validation; youth gate still applies. |
| Referrals | Shareable team/event links, attribution and consent; measure accepted invites. |
| Organic content | Short product demos, coaching tips and event recaps with permission; measure activated users, not views. |
| Search | Index eligible public event/community pages; never expose private or youth data. |
| Partnerships | Local leagues and clubs; no implied official affiliation without agreement. |

Proposed weekly outreach: five captain/organizer conversations, two onboarding sessions and one useful product demonstration. Allocate support time within the 20-hour cap. Marketing budget $0–$100/month initially; no significant paid acquisition until retention and conversion are measured.

### Founding incentives

Early access, optional founding recognition and proposed 50% first-year premium discount. Confirm eligibility, expiration and provider support before advertising; no lifetime premium or permanent fee waiver. Keep core free. Measure referral conversion without invasive tracking.

## 13  Monetization sequence

| Plan | Monthly | Proposed annual |
|---|---|---|
| Free | $0 | $0 |
| Individual Plus | $4.99 | $49.99 |
| Community Pro | $9.99 | $99.99 |
| Team Pro | $19.99 | $199.99 |
| Organization Pro | $49.99 | $499.99 |

Launch free core social, team, calendar, messaging and basic competition tools. Verified-host transactions earn 3% of host principal, with separately disclosed processing costs paid by buyers under normal settlement. Host principal is not revenue. Premium monetizes advanced analytics, automation and resource capacity, not basic participation.

### Premium readiness

Before billing: demonstrate retention, measure storage/egress/meeting costs, enforce server-owned entitlements and quotas, validate provider policies, test purchase/restore/cancellation/refunds and preserve core data on downgrade. Target at least 60% contribution margin. Use Doc 11 pricing, trial and grace policies; annual exact prices and add-ons remain proposed.

### Later opportunities

League and community payments after financial expansion; premium storage and meeting capacity after measurement; Tournament Pro pass, sponsored opportunities and AI usage-based features only after validation. No general ads at launch.

## 14  Revenue scenarios and cost discipline

Illustrative transaction scenarios assume 32 paying teams/event × $500 bid fee × 3% platform fee. Excludes free entries, refunds, disputes and fee waivers.

| Paid events/year | Host principal (GMV) | Gross service fees |
|---|---|---|
| 10 | $160,000 | $4,800 |
| 25 | $400,000 | $12,000 |
| 50 | $800,000 | $24,000 |
| 100 | $1,600,000 | $48,000 |
| 250 | $4,000,000 | $120,000 |

### Illustrative subscription mix

200 Individual Plus + 20 Community Pro + 50 Team Pro + 5 Organization Pro = $2,447.25 monthly gross, or $29,367 annualized. Combined with 50 paid events: $53,367 gross annualized platform revenue. This is a sensitivity scenario, not the year-one adoption forecast; assumes constant average paid counts and no discounts.

### Costs and margin

Infrastructure $50–$150/month ($600–$1,800/year); marketing $0–$100/month ($0–$1,200/year). At upper budgets, illustrative combined revenue less these two categories is $50,367, not profit. Excludes labor, legal, taxes, store/billing commissions, refunds, fraud, payment costs borne by platform, support and other variable expenses. Costs may rise with usage.

Track contribution margin = (recognized revenue less attributable variable costs) / recognized revenue. Separate host liabilities, provider balances, fees and refunds. Forecast cash flow and reserves independently. Use budget alerts at 50/75/90/100%; restrict optional expensive workloads, never essential safety or settlement.

## 15  Success metrics and year-one scorecard

| Metric | Conservative / target / stretch |
|---|---|
| Registered athletes | 500 / 2,500 / 10,000 |
| Monthly active athletes | 200 / 1,000 / 4,000 |
| Active teams | 15 / 75 / 250 |
| Active communities | 5 / 25 / 100 |
| Paid tournaments | 10 / 50 / 100 |
| Gross service fees* | $4,800 / $24,000 / $48,000 |

*Same illustrative 32-team, $500 fee assumption. Targets are not validated forecasts. Year one means first 12 months after public launch.

| Metric / proposed target | Definition |
|---|---|
| North star: weekly meaningful athletes | Distinct athletes with RSVP, team communication, workout, registration or team workflow in trailing 7 days; exclude passive opens. |
| Activation ≥60% | New eligible accounts completing meaningful action within 7 days / eligible new accounts. |
| D7 ≥35%; D30 ≥20% | Signup cohort returning for meaningful activity on respective day; report cohort size. |
| Team retention ≥80% | Prior-month active teams also active this month / prior-month active teams. |
| Organizer repeat ≥50% | Eligible hosts with another completed event within proposed 180 days / eligible hosts with full observation window. |
| Checkout ≥95% | Successful eligible checkout attempts / eligible initiated attempts; deduplicate retries. |
| Reconciliation 100% | All provider transactions accounted for; discrepancies tracked and resolved. |
| Premium margin ≥60% | Recognized premium revenue less attributable variable costs, divided by premium revenue. |

Review weekly in beta and monthly after launch. Track MAU using trailing 30-day meaningful activity; active workspace requires a meaningful organizational action. Report cohorts, sample size and measurement window; avoid vanity metrics.

## 16  Expansion and risk register

### Multi-sport gate

Validate ultimate first. Proposed readiness: sustained team retention, repeat organizer use, stable operations, positive contribution margin on monetized workflows and capacity for support. Interview organizers in candidate sports; compare demand, partner access, rules complexity and implementation cost. Volleyball, basketball and soccer are candidates, not commitments.

Each sport needs versioned scoring, positions, field/court definitions, competition formats, stats and fixtures. Reuse identity, teams, calendar, chat, payments and billing. Pilot one sport at a time with isolated flags and real organizers; no sport-specific forks of shared services.

| Risk | Mitigation / trigger |
|---|---|
| Scope / burnout | Cap 20h/week; reserve 20%; cut optional work when forecast slips. |
| Low retention / empty feed | Onboard groups; observe recurring workflows; defer ads. |
| Fraud / liquidity | Separate paid gate, limited exposure, reserves and reconciliation. |
| Media cost | Quota and screening, external video, budget alerts. |
| Competition errors | Deterministic fixtures and real free-event pilot. |
| Store delays | Early enrollment/submission; web access; communicate delays. |
| Youth safety | Adult-only launch until independent gate passes. |
| Operational overload | Limit cohorts, automate routine tasks, contract specialists if justified. |
| Premature expansion | Require evidence and one-sport pilot; preserve shared contracts. |

## 17  Execution governance and source register

GitHub Projects columns: Backlog → Ready → In progress → Review/test → Ready for release → Released → Validated. Limit work in progress to one main task plus urgent support. Each issue records doc reference, priority, dependencies, estimate, acceptance, platform scope, flag and evidence. Weekly review: capacity, defects, metrics, costs and next sprint. Monthly review: retention, revenue, risks and scope.

Definition of done: acceptance met; applicable web/mobile parity; server authorization; automated tests; offline/error states; accessibility; monitoring and documentation; release evidence. Founder approves releases; contract specialist legal, security or financial review where justified. No claim of independent review while solo.

### Source register

Approved Documents 00–18 and final Document 19 decisions are the product baseline. Repository assessment uses selected development-branch inventory and documentation reviewed November 25, 2026:

https://github.com/brianrhonea/frisbee_app/tree/development

https://github.com/brianrhonea/frisbee_app/blob/development/docs/CHANGELOG.md

https://github.com/brianrhonea/frisbee_app/blob/development/docs/release-notes.md

https://github.com/brianrhonea/frisbee_app/blob/development/docs/requirements.md

https://github.com/brianrhonea/frisbee_app/blob/development/docs/beta-test-checklist.md

Latest documented mobile version: 0.0.55 (November 24). Requirements audit: November 13. Source presence and release notes do not prove deployment or passing tests. No exhaustive audit, live infrastructure verification, test execution, market research or legal/provider validation was performed. No repository changes made. Sprint estimates, dates, thresholds and scenario assumptions are proposed planning defaults; update after actual evidence.
