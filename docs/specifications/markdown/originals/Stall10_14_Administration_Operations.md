<!-- Converted from Stall10_14_Administration_Operations.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# Administration & Operations

DOCUMENT 14  /  VERSION 1.0  /  25 NOVEMBER 2026

Approved product direction • Engineering specification • Pre-launch

### Purpose

Operate Stall10 as a sustainable sports ecosystem with a single owner initially and granular staff responsibilities as the business expands. Automate routine work, prioritize exceptions and preserve human oversight of significant financial, safety and enforcement decisions.

### Scope

Expand the existing Next.js /staff portal and Fastify API. Administration is web-first, accessible through mobile browsers. Platform staff, organization administrators and workspace administrators have separate authorization boundaries. Essential support and safety remain free. UI mockups are excluded until Document 17.

### Release strategy

Core staff permissions, support, moderation, audit, health and emergency controls precede public launch. Host review and financial controls precede paid hosting; youth-specific operations precede youth access; subscription operations precede premium billing.

### Reading guide

02 Approved requirements; 03 Repository baseline; 04 Accounts and support; 05 Competition and finance; 06 Staff and moderation; 07 Operational controls; 08 Monitoring and analytics; 09 Architecture and contracts; 10 Delivery and acceptance; 11 References and validation.

Status convention: approved = confirmed product policy; baseline = selected development-branch source evidence; proposed = engineering detail requiring validation. No production verification or repository changes performed.

## 02  Approved requirements

| Decision | Approved direction |
|---|---|
| Platform | Expand Next.js /staff; web-first with mobile browser access. |
| Dashboard | Unified business metrics, health and prioritized actionable exceptions. |
| Support | Native tickets integrated with business email and account context. |
| Support access | Read-only diagnostics; audited corrective actions; no unrestricted impersonation. |
| Workspace oversight | Policy violations, verified ownership recovery and exceptional support; preserve autonomy. |
| Financial approvals | Automate eligible routine settlements; human review for high risk; dual approval when staffing permits. |
| Host review | Dedicated verification and risk queue; documented decisions and ongoing monitoring. |
| Complimentary access | Time-limited audited grants separate from provider subscriptions. |
| Staff organization | Single owner initially; granular assignable roles and future separation of duties. |
| Feature management | Audited global, environment, platform, sport, workspace and cohort flags; server enforcement. |
| Incidents | Partial restrictions, emergency switches and targeted maintenance announcements. |
| Jobs | Central registry, health, failures and authorized idempotent retries. |
| Reporting | Daily internal summary, immediate critical alerts, weekly business reports. |
| Analytics | First-party aggregate growth, retention, engagement, finance and infrastructure; CSV exports. |
| Budgets | Configurable 50/75/90/100% alerts; controlled restrictions on optional costly workloads. |
| Automation | Automate routine tasks and triage; human review of significant safety, financial and enforcement decisions. |

## 03  Repository baseline and gaps

| Reviewed source | Evidence and implication |
|---|---|
| apps/web/app/staff/page.tsx | MembersOnly wrapper, StaffQueue and StaffPayments; noindex is not authorization. |
| apps/web/components/StaffQueue.tsx | Checks moderation access; loads open reports; dismiss, warn, suspend, unsuspend, remove; optional notes and confirmation dialogs. |
| apps/web/components/payments/StaffPayments.tsx | Recent charges, event filter, review queue, approve, release eligible funds, reconciliation issues and last check. Card and bank details remain with Stripe. |
| apps/api/src/payments/reconcile.ts | Pure comparison of internal charge facts against provider payment and transfer state; detects mismatches, missing refunds/transfers, disputes and stuck releases. |
| apps/api/src/moderation/routes.ts | Existing /v1/staff/reports GET and report action POST; workspace-specific routes and report limits. |
| apps/mobile/lib/data/services/feature_flags.dart | Live meta/flags document and defaults; mobile rollback controls. |
| apps/api/DEPLOY.md | Cloud Run, separate dev/prod, production approval, health/readiness checks, digest rollback and legacy use_api_* fallback. |
| apps/web/components/team/CommunityAdmin.tsx | Linked team creation, affiliation requests, role mapping and removal; workspace scoped. |

### Priority gaps

Expand coarse staff claims into current granular permissions and MFA; require reasons for significant actions; add case ownership, support tickets, audit history, host reviews, job tracking and analytics. Do not permit rollback to insecure legacy writes. Dedicated billing administration is planned, not established. Selected files do not establish live deployment status.

## 04  Accounts, workspaces and support

### Account directory

Search by username, ID or authorized email. Return permission-filtered status, verification, affiliations, support history, restrictions and entitlements. Financial information is finance-scoped. Birth dates, addresses and guardian information remain restricted. Recovery, session revocation, export and deletion invoke authoritative services with recent authentication where required.

### Workspace oversight

Search teams, communities and organizations; view permitted ownership, visibility, membership counts and restrictions. Intervene only for policy violations, exceptional support or verified recovery. Ownership disputes require evidence, existing administrator and membership history, affected-party notice and documented decisions. Preserve private chats, playbooks and ordinary roster autonomy.

### Native support

Integrate business email (mailbox and provider to confirm) with authenticated in-app/web tickets. Support account access, profiles, teams, competitions, payments, subscriptions, technical issues, feedback and privacy. Route safety cases to dedicated moderation, not ordinary support. Email intake must verify requester identity before exposing account data; sanitize attachments and prevent spoofed threading.

| Lifecycle / priority | Proposed operation |
|---|---|
| Lifecycle | Submitted → triaged → assigned → in progress → waiting for user/provider → resolved → closed/reopened. |
| Critical | Urgent escalation; no promise of continuous staffing. |
| Financial/account blocking | First response target: one business day. |
| Technical/general | Two / three business days respectively. |
| Feedback | Acknowledge and classify into backlog. |

Collect app version, OS, sanitized route, error and correlation ID; optional user-provided screenshots and consent-based redacted diagnostics. Never automatically attach messages or tokens. Link engineering issues in GitHub without customer PII. Separate internal notes from requester-visible replies. No unrestricted impersonation.

## 05  Competition and financial operations

### Competition oversight

Track draft, published, active, completed and canceled competitions; registration anomalies, schedules, participant complaints, independent completion evidence and financial exposure. Organizers retain ordinary sporting decisions. Staff intervene for fraud, safety, platform error or policy violations.

### Host review

Invite-only paid beta, then broader verified-host access. Record provider verification, organizer history, risk tier, evidence, decision, limits and next review. Provisional, established, trusted and restricted tiers remain distinct. First three events enhanced review; proposed $1,500 collection cap and risk-based refundable deposit (initially consider $200). No universal deposit.

### Settlement and refund controls

Apply Document 10: verified completion, proposed 3-day established and 14-day provisional holds, justified 10–20% reserves up to 90 days, bank/owner change MFA and proposed 72-hour freeze with renewed approval. No manual release bypass. Full mandatory-fee refund for host cancellation, fraud or platform error; disclosed withdrawal policy otherwise. Partial early settlement only for eligible established hosts after launch.

| Module | Operational requirement |
|---|---|
| Transactions / balances | Separate host principal, platform fees, processing, held/eligible/transferred funds, refunds and liabilities. |
| Disputes / debt | Track deadlines, evidence, reversals, shortfalls and recovery. |
| Reconciliation | Daily and on demand; compare provider records; open exception cases, never silently overwrite history. |
| Approvals | Routine eligible settlements automated; high-risk human review with evidence and recent authentication; future dual approval. |
| Accounting | Authorized exports, immutable ledger adjustments and reconciliation history. |

Illustrative annual volume: 100 tournaments × 32 teams × $500 = $1.6M host principal; 3% platform fee = $48,000 gross platform fees before refunds, expenses and taxes. Processing charges separate; principal is not earned revenue.

## 06  Staff, moderation and subscriptions

| Role | Scoped responsibility |
|---|---|
| Owner | Exceptional administration and ownership; no routine bypass. |
| Support | Tickets and limited diagnostics. |
| Moderator / safety reviewer | Scoped cases, enforcement, appeals; restricted youth evidence. |
| Financial reviewer | Host review, refunds, settlements and reconciliation. |
| Operations administrator | Job controls, health and flags. |
| Product analyst / auditor | Aggregate analytics / authorized read-only audit. |
| Security administrator | Staff permissions, access revocation and incidents. |

Use existing staff claim only as coarse eligibility. Resolve current capabilities server-side; require staff MFA, recent authentication and reason for sensitive operations. One owner may hold multiple roles initially; introduce separation of duties and dual approval as staffing permits. Revocation must take effect for subsequent protected actions.

### Moderation operations

Extend existing reports into assigned severity-based cases, related reports, restricted evidence, separate notes, scoped enforcement, escalation and appeals. Preserve reporter confidentiality and proposed 30-day appeal window. Track oldest case, first review time, repeated violations and appeal outcomes. No unrestricted private-message access; audited exceptional investigation only.

### Subscription operations

At premium launch, display provider status, plan, billing period, entitlements, trial eligibility and usage. Reconcile verified provider events; never fabricate paid status. Complimentary grants must have scope, reason, issuer, expiry and revocation. Follow provider refund rules and Document 11 downgrade protections. Version catalog changes; preserve core records and free safety/support.

## 07  Feature controls, incidents and jobs

### Feature management

Support global, environment, platform, sport, workspace and cohort flags. Proposed deterministic percentage rollouts: internal, 5%, 10%, 25%, 50%, 100%. Evaluate errors and security before expanding. Backend checks are authoritative; client flags only affect presentation. Audit changes with reason, version, actor and environment. Default safely on missing configuration; never restore insecure direct writes.

### Maintenance and incidents

Allow partial restrictions for checkout, paid hosting, eligible payouts, uploads and compromised integrations. Preserve unrelated services. Follow Document 13 detect, contain, investigate, remediate, recover, communicate and review process. Maintain secure emergency access, incident timeline and required notifications. Target announcements by audience, schedule and expiry; promotional messages require opt-in.

### Central job registry

Track reconciliation, settlement, reminders, delivery, screening, transcoding, exports, deletion, billing reconciliation, indexing, retention and backups. Record job type, source reference, run ID, state, attempts, lease, next retry, timestamps and sanitized error. Use bounded workers, durable queues, idempotency keys and dead-letter handling. Operators may retry eligible failures, cancel safe pending work or pause selected workers; never blindly retry irreversible operations.

| Cadence | Proposed automated operations |
|---|---|
| Continuous | Security alerts, webhook processing, critical failures. |
| Hourly | Eligible settlement checks, overdue jobs and queue health. |
| Daily | Reconciliation, backups and secure operator summary. |
| Weekly | Growth, support and infrastructure trends. |
| Monthly / quarterly | Revenue and costs / permission review and recovery exercises. |

## 08  Health, costs and business analytics

### Monitoring

Use Google Cloud Monitoring and structured logs; link provider diagnostics rather than duplicate them. Summarize API, Firestore, Functions, Storage, Auth, FCM, Stripe, LiveKit, web hosting and workers. Display freshness and unknown state; alert on errors, latency, backlog and provider failures.

| Proposed target | Objective |
|---|---|
| API | 99.5% monthly availability; warm p95 under 750 ms. |
| Notifications | Time-sensitive processing p95 under 30 seconds; reminder delay within five minutes. |
| Recovery | Daily backup; eligible data RPO up to 24h and RTO within 24h; financial reconciliation separately. |
| Finance | Daily and on-demand reconciliation. |

### Cost management

Initial planning budget $50–$150/month. Configurable alerts at 50/75/90/100%; monitor Firestore operations, storage/egress, compute, functions, email, LiveKit participant minutes, media processing, hosting, backups and provider fees. Budgets are not hard caps. Restrict optional expensive workloads through controlled policy; preserve auth, safety, required financial operations and essential records.

### Metric definitions and reporting

Use centralized first-party definitions: registered accounts; activated accounts (proposed meaningful onboarding); DAU/WAU/MAU (unique qualifying activity); cohort D1/D7/D30 retention; active workspaces; competition counts; gross marketplace volume; earned fees; MRR normalized recurring revenue; ARR = 12 × MRR; paid conversion and churn; contribution margin; cost per active user. Define exact qualifying events and denominators before implementation. Aggregate by date, sport and region where privacy permits; suppress small youth cohorts. CSV exports are permission-filtered and audited. Daily summary and weekly reports link to authoritative records; critical alerts immediate.

## 09  Technical architecture and contracts

Extend apps/api/src/admin (routes, permissions, overview, accounts, workspaces, audit, operations, featureFlags), support (routes, service, notifications), apps/web/app/staff modules and packages/shared contracts. Reuse existing domain services; do not implement a second payment, moderation or billing engine.

| Proposed records | Purpose |
|---|---|
| staffPermissions/{uid}; adminAuditLogs/{id} | Current grants and append-only action history; reuse Document 13 audit domain rather than duplicate logs. |
| supportTickets/{id}/messages; activity | Requester conversation, internal notes separately, assignment and state. |
| operationalCases/{id}; hostReviews/{id} | References to authoritative cases, payment records and review evidence. |
| featureFlags/{id}; platformAnnouncements/{id} | Versioned policies and targeted notices; migrate meta/flags safely. |
| jobRuns/{id}; operationalMetrics/{period} | Job state and health summaries. |
| businessMetrics/{period}; administrativeGrants/{id} | Aggregate metrics and time-limited entitlements. |
| securityIncidents/{id} | Shared incident records from Document 13. |

### API contracts (proposed)

GET /v1/staff/{overview,accounts,workspaces,competitions,host-reviews,subscriptions,jobs,feature-flags,audit,analytics,health}; GET /v1/staff/accounts/:id; POST /v1/staff/host-reviews/:id/decision; POST /v1/staff/entitlement-grants; POST /v1/staff/jobs/:id/retry; PUT /v1/staff/feature-flags/:id; POST /v1/staff/announcements. GET /v1/staff/support/tickets; POST /v1/staff/support/tickets/:id/{assign,reply,resolve}; POST /v1/support/tickets; GET /v1/me/support/tickets. Reconcile existing routes before implementation.

Audit fields: actor, role, action, resource type/ID, reason, case and correlation IDs, result, timestamp and redacted before/after where needed. Server-only writes; proposed 12-month security retention, longer where required. Paginate all directories, validate inputs, enforce environment isolation and rate limits.

## 10  Delivery roadmap and acceptance

| Gate | Required capabilities |
|---|---|
| General launch | Staff MFA and granular authorization, overview/exception queue, account/workspace directory, native support, moderation/appeals, audit, flags, incident controls, job health and basic metrics. |
| Youth access | Guardian and safety review workflows, restricted evidence and escalation. |
| Paid hosting | Dedicated host reviews, completion checks, holds, reconciliation, refunds, disputes and financial audit. |
| Premium launch | Provider reconciliation, entitlement diagnostics, grants and usage controls. |
| Expansion | Advanced analytics, automated classification, multi-staff assignment, dual approval and forecasting. |

### Acceptance criteria (not executed)

- Ordinary users and workspace admins cannot access staff APIs; staff MFA and current granular permissions enforced; revocation tested.
- Diagnostics and support notes cannot expose private data; appeals preserve reporter identity; ownership recovery requires evidence.
- Payout holds cannot be bypassed; repeated requests and job retries do not duplicate transactions; reconciliation remains auditable.
- Complimentary grants expire; provider status cannot be fabricated; subscription does not override authorization.
- Backend flags enforce restrictions; rollback cannot restore insecure writes; dev cannot modify prod.
- Audit records resist ordinary modification; exports are scoped; metrics separate host principal and platform revenue.
- Test backup recovery, incident response, alerts, job leases, dead-letter recovery and partial service restrictions.

### Implementation order

First secure existing staff endpoints and establish audit; then add exception queue, directories and support; extend host/financial and safety workflows; integrate job health, flags and metrics; add billing administration with premium launch. Document 18 will define deployment and scalability testing in detail.

## 11  References and validation

Repository: brianrhonea/frisbee_app, development branch. Selected files reviewed during Document 14 assessment; branch may change. Source links:

https://github.com/brianrhonea/frisbee_app/blob/development/apps/web/app/staff/page.tsx

https://github.com/brianrhonea/frisbee_app/blob/development/apps/web/components/StaffQueue.tsx

https://github.com/brianrhonea/frisbee_app/blob/development/apps/web/components/payments/StaffPayments.tsx

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/payments/reconcile.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/payments/jobs.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/moderation/routes.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/mobile/lib/data/services/feature_flags.dart

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/DEPLOY.md

https://github.com/brianrhonea/frisbee_app/blob/development/apps/web/components/team/CommunityAdmin.tsx

https://github.com/brianrhonea/frisbee_app/blob/development/firebase/scripts/set-staff.mjs

### Dependencies

Documents 01–13: architecture, account privacy, workspace permissions, messaging, calendar, discovery, marketplace, payments, subscriptions, notifications and security. Document 17 covers UI; Document 18 covers deployment/testing; Document 19 covers launch strategy.

### Validation outstanding

No application execution, automated tests, live payment inspection, production IAM or infrastructure verification, or measured cost analysis. Exact support mailbox/provider, staffing coverage, response targets, metric definitions, job schema, flag rollout percentages, cost restrictions and approval thresholds are proposed implementation details. Validate provider constraints, legal retention and financial accounting before launch. No repository changes made.
