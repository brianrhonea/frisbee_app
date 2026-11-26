<!-- Converted from Stall10_18_Deployment_Testing_Scalability.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# Deployment, Testing & Scalability

DOCUMENT 18  /  VERSION 1.0  /  25 NOVEMBER 2026

Approved product direction • Engineering and operations specification

### Purpose

Release Stall10 safely and repeatedly as a solo-developed, multi-sport platform. Preserve the existing Flutter, Next.js, Fastify, Firebase and Cloud Run architecture; add controls that reduce operational risk without premature infrastructure complexity.

### Operating principles

Automate routine checks; isolate environments; protect financial and youth workflows; use measured capacity rather than registered-user counts; keep essential operations available during cost or security incidents. Initial infrastructure target: $50–$150 per month.

### Reading guide

02–03 Approved decisions and repository baseline; 04–06 environments, release pipeline and mobile; 07–08 migrations and testing; 09–10 performance and scaling; 11–12 jobs, security and monitoring; 13–14 costs and recovery; 15 launch gates and implementation; 16 source register.

### Status

All 16 product decisions are approved. Numeric thresholds beyond previously agreed objectives are proposed engineering defaults, not measured results or contractual guarantees. Source review is limited to selected development-branch files. No tests, live deployments or recovery drills were executed.

## 02  Approved operating decisions

| Area | Approved requirement |
|---|---|
| Environments | Two persistent cloud environments; local emulators and temporary previews; staging later if justified. |
| Cadence | Continuous development releases; weekly or as-needed production releases with explicit approval. |
| Branch protection | Pull requests and automated checks for main; owner approval initially, independent review as staffing grows. |
| Rollout | Staged API traffic, synthetic smoke tests, monitored promotion/rollback; phased mobile releases. |
| Mobile channels | TestFlight and Google Play internal/closed testing before public release. |
| Compatibility | Current and previous two minor releases; at least 90 days for breaking changes; mandatory updates only when necessary. |
| Testing | Risk-based coverage, mandatory security/payment tests, browser E2E and shared fixtures. |
| Devices | Emulators plus representative physical iOS/Android and major desktop/mobile browsers. |
| Load | 10, 50 and 100 concurrent-user scenarios before launch; larger scenarios with growth. |
| Scaling | Scale to zero and current caps initially; measured warm capacity increases. |
| Infrastructure | Gradual infrastructure-as-code adoption, retain deployment workflows. |
| Recovery | Daily backups, proposed 30-day retention, quarterly restore drills; independent financial reconciliation. |
| Monitoring | Cloud Monitoring, crash reporting, immediate critical alerts; evaluate unified tracking; no 24/7 promise. |
| Budget | $50–$150 target; forecast alerts; restrict optional expensive workloads, protect essentials. |
| Migrations | Expand/contract, dry runs, resumable backfills, explicit production approval. |
| Launch gates | Functional, security, recovery, payment, performance and operations; separate paid-hosting and youth gates. |

## 03  Repository baseline and priorities

| Observed source | Required improvement |
|---|---|
| ci-node.yml: Node 22, pnpm frozen lock, typecheck, tests, builds, API emulator and nonroot container smoke/SIGTERM. | Keep; add required web and Firebase rule checks. Root test excludes web; web package has no test script. |
| Firebase functions: Vitest and separate server/rules emulator scripts. Backend deploy builds and runs npm test. | Run rules and server suites explicitly before deployment; pin Firebase CLI; review function groups and rollback compatibility. |
| API deploy: image digest, release tags, WIF or key fallback, all traffic before smoke. | Candidate revision first; staged traffic and secure rollback; remove long-lived credentials. |
| Backend deploy: service account JSON, rules/indexes/storage/hosting and selected functions. | Migrate to WIF; validate target project and rules/index readiness. |
| Codemagic: Flutter 3.41.2, iOS dev TestFlight and main App Store manual release. | Add Android pipeline, PR checks, reproducible Xcode/pods and environment assertions. |
| Cloud Run: probes, secrets, KMS, scaling; App Check default false. | Verify production KMS provisioning, App Check, CORS, scheduler identities and host-risk payout policy. |
| Monitoring scripts: legacy Firebase hosting/function uptime and read/error/flood/mute alerts. | Monitor actual Cloud Run and Vercel endpoints; test alert delivery and job/financial health. |

Tree review found 317 files matching TypeScript/Dart test naming conventions; this is not a passing test count. No dedicated browser E2E, load-test or backup automation was established in reviewed files. Production console settings remain unverified.

## 04  Environments and infrastructure

| Layer | Local / preview | Development | Production |
|---|---|---|---|
| API | Local Fastify | Dev Cloud Run | Prod Cloud Run |
| Data/auth | Emulators; preview uses dev | Dev Firebase | Prod Firebase |
| Web | Local / Vercel preview | Dev web | stall10.app |
| Mobile | Simulator/device | TestFlight / Play test | App Store / Play |
| Payments | Mocks/test | Stripe test | Stripe live |
| Media/jobs | Emulator or mocks | Dev buckets/queues | Prod buckets/queues |

Use separate project identities, secrets, buckets, webhook endpoints, KMS keys and scheduler audiences. Synthetic data only in nonproduction; never copy real athlete data or live payment credentials. Preview deployments must not reach production writes. Verify project and provider mode at build and startup; fail closed on mismatch.

### Cloud Run baseline

| Setting | Existing default |
|---|---|
| CPU / memory | 1 vCPU / 512 MiB |
| Min / max instances | 0 / dev 3, prod 10 |
| Concurrency / timeout | 80 / 60 seconds |
| Region | us-central1; verify Firestore locality |
| CPU / probes | Request-based, startup boost; /ready and /health |

Keep modular monolith and separate heavy media jobs. Adopt IaC incrementally: inventory/import existing resources, plan changes, review drift, protect state and avoid destructive recreation. Prioritize IAM, secrets references, queues, schedulers, alerts and backup policies. Keep service.yaml authoritative until migration.

## 05  Release engineering

### Branch and artifact policy

Short-lived feature/fix branches → development → protected main. Hotfix from production-compatible revision; merge back into development. Required checks on main; solo owner explicitly approves production without claiming independent review. Release weekly or as needed. Serialize deployments per environment; cancel superseded development builds only when safe.

| Stage | Required evidence |
|---|---|
| PR | Lint/typecheck, unit/contract, security scans, emulator rules, affected builds. |
| Development | Deploy compatible backend and web; seed synthetic data; smoke, E2E, device and payment test-mode checks. |
| Candidate | Immutable digest and commit, migration plan, index readiness, release notes, rollback reference. |
| Approval | Owner records gate results and known exceptions; critical security/financial failures block. |
| Promotion | Validate candidate before traffic; proposed 5%, 25%, 50%, 100% stages; synthetic checks at low volume. |
| Completion | Record metrics, version matrix, approver, timestamps and incident/rollback references. |

Release manifest: commit, API image digest, Vercel deployment ID, Firebase rules/index/function versions, iOS build, Android version code, migrations and relevant flags. Build once and promote immutable artifacts where feasible; environment-specific mobile/web builds must share verified source and lockfiles. Pin toolchains and action revisions; retain at least 15 known-good API images subject to recovery needs.

### Rollback

Pause promotion on critical security, payment discrepancy, sustained error/latency regression or failed synthetic checks. Route to previous compatible Cloud Run revision; restore Vercel deployment; redeploy reviewed compatible Firebase rules/functions. Do not restore insecure direct writes. Code rollback does not reverse data or Stripe effects. Mobile uses feature restrictions and corrective builds. Record reason, reconcile and verify recovery.

## 06  Mobile and browser release policy

Keep existing iOS TestFlight development and manual App Store release. Add Android signed AAB builds, Play internal/closed testing, explicit production approval and staged rollout. Protect signing credentials; verify artifact existence, environment, version monotonicity and deep links. Separate dev app identity where practical to avoid accidental production sessions.

### Compatibility

Support current and previous two minor releases and at least 90 days for breaking changes. Use additive API contracts, tolerant readers, versioned schemas and capability flags. Maintain minimum supported version and recommended version separately. Prompt optional updates first; mandatory only for security, integrity or unavoidable incompatibility. Never strand unsynced statistics or playbook drafts without a safe recovery path.

| Test surface | Representative coverage |
|---|---|
| iOS | Current and oldest supported OS; physical device, notifications, backgrounding, permissions, offline recovery. |
| Android | Current and oldest supported OS; physical device, low-memory conditions, notification permissions, background restrictions. |
| Web | Chromium, Firefox, WebKit; desktop and mobile viewport; physical Safari/Chrome checks. |
| Accessibility | Keyboard, screen reader, reduced motion, contrast, touch targets and outdoor readability per Doc 17. |
| Network | Slow connection, airplane mode, reconnect, interrupted upload and expired auth. |

### Release sequencing

Deploy additive backend and rules before dependent clients; keep features disabled until compatible versions and data are ready. Test older clients against new backend. Store rollout timing is provider-controlled; do not assume immediate mobile rollback.

## 07  Data migration and compatibility

Every production data change requires a versioned migration plan, owner approval and recovery strategy. Firestore is schemaless but contracts, indexes and permissions are not. Use expand → compatible reads/writes → resumable backfill → validate → flag activation → observe → contract only after compatibility window.

| Migration control | Acceptance condition |
|---|---|
| Dry run | Counts, estimated reads/writes, sample transformations, affected scope; no mutation. |
| Execution | Bounded batches, deterministic IDs, checkpoint, lease and retry; explicit environment confirmation. |
| Validation | Compare counts, invariants, provenance and sampled records; report ambiguous cases. |
| Recovery | Preserve original data or reversible mapping; prefer forward correction; no destructive rollback by default. |
| Financial | Append audited corrections, reconcile provider IDs and amounts; no silent ledger overwrite. |
| Security | Rules compatible with both clients without broadening unauthorized access; indexes ready before activation. |

Proposed migration registry: migrationId, schemaVersion, environment, sourceCommit, state, dryRunSummary, checkpoint, counts, lease, startedAt, completedAt, approver, errorSummary. Store audit references, not private payloads. Apply to canonical games/statistics (Doc 15), playbook revisions (Doc 16), media and billing entitlements. Preserve sport/ruleset versions and stable IDs across migrations.

## 08  Automated testing standards

| Layer | Tools / requirements |
|---|---|
| Unit and shared contracts | Existing Vitest and Dart tests; deterministic fixtures for scoring, permissions, fees, dates and sport rules. |
| API integration | Fastify injection and Firebase emulators; auth, storage, transactions, concurrency and idempotency. |
| Rules | Firestore and Storage emulator allow/deny matrix; cross-workspace, youth, staff and financial paths. |
| UI components | Flutter widgets/goldens; proposed React Testing Library/Vitest; light/dark and accessibility. |
| E2E | Proposed Playwright and Flutter integration tests; critical user journeys; synthetic accounts. |
| Security | Dependency, secret and image scanning; authorization abuse, malformed payloads, rate limits. |
| Performance | Proposed k6 API tests plus separate Firestore listener and media workloads. |

### Proposed line-coverage targets

| Risk area | Target |
|---|---|
| Payments | 95% |
| Authorization / statistics calculations | 90% |
| Shared business logic | 85% |
| API services | 80% |
| General UI | 70% |

Coverage is a guide, not proof of correctness. Critical cases must pass regardless of coverage. Track branch coverage for financial and permission decisions. No flaky-test bypass for critical gates; quarantine noncritical flaky tests with owner, reason and expiry. Use fixed clocks, deterministic seeds and isolated test resources. Never run destructive tests against production.

## 09  Critical regression matrix

| Domain | Required scenarios |
|---|---|
| Identity and safety | Email verification, recovery, MFA, restrictions, guardian consent, adult/minor communication, block/report, deletion/export. |
| Social and workspaces | Feed audiences, private media, custom roles, ownership transfer, membership revocation, chat, community registration. |
| Calendar and competition | Timezone/recurrence, RSVP/waitlist, registration capacity, score conflicts, bracket progression, cancellation. |
| Payments | Duplicate checkout/webhooks, out-of-order events, provider success with DB failure, concurrent payout jobs, refunds, disputes, bank change freeze, unverified host, emergency pause. |
| Statistics and coaching | Offline restart, stale recorder lease, duplicate sync, corrections, sport fixtures, playbook revision conflict, media screening, clip permissions, assignments. |
| Notifications | Device registration, quiet hours, deduplication, retry, reminder timing and sensitive previews. |
| Operations | Old clients, flags, migration resume, restore drill, alert delivery, job retry, degraded provider and accessibility. |

Payment tests use mocks or Stripe test mode. Verify balanced ledger and reconciliation, host principal, buyer fees, risk-tier holds and reserves, refund rules and audit records from Doc 10. No real production charge/refund/transfer in automated smoke checks. Production synthetic accounts must be isolated and nonfinancial.

### Evidence

Record suite version, environment, commit, results, failed cases and artifacts. Redact logs and screenshots. Manual tests include device/browser, steps, expected/actual result and tester. Critical defects block the relevant release gate.

## 10  Capacity and performance

| Scenario | Concurrent virtual users / purpose |
|---|---|
| Baseline | 10; normal early usage |
| Beta | 50; small community |
| Launch | 100; required prelaunch |
| Tournament | 250; later burst validation |
| Growth | 500; later bottleneck discovery |
| Stress | 1,000+; explicit cost approval |

Proposed test protocol: ramp 2–5 minutes, steady 15 minutes, ramp down, repeat after changes; longer soak and burst tests later. Seed realistic team, chat, feed, game and competition sizes. Mix 35% feed/discovery, 25% team/calendar, 15% chat, 15% competition, 5% stats, 5% other writes; adjust from telemetry. Model direct listeners separately. Measure throughput, latency, errors, CPU, memory, instance count, read/write amplification and cost. Abort on unsafe cost or error escalation.

| Objective | Initial target |
|---|---|
| API availability | 99.5% monthly; internal objective |
| Warm API latency | p95 &lt;750 ms; proposed p99 &lt;2 s |
| Cold start / unexpected errors | Proposed p95 &lt;3 s / &lt;1% |
| Web vital targets | p75 LCP ≤2.5 s, INP ≤200 ms, CLS ≤0.1 |
| Mobile | Proposed ≥99.5% crash-free sessions |
| Notifications | Urgent processing p95 ≤30 s; reminders within 5 min |
| Recovery | RPO/RTO ≤24 h; financial reconciliation separate |

Define availability using eligible requests and synthetic probes; exclude expected client validation errors, not server failures. Segment warm/cold and external operations. At low traffic use synthetic checks; do not claim SLO compliance without adequate samples.

## 11  Scaling and background work

### Capacity model

Illustrative: 10,000 MAU × 30% daily active × 10% peak simultaneous = 300 concurrent users; six API requests/minute each = 30 requests/sec. This excludes direct Firestore listeners, background jobs and bursts. Ten instances × 80 configured concurrency = 800 nominal in-flight slots, not tested throughput or user capacity.

### Firestore and caching

Use bounded cursor queries, shared repository subscriptions across screens, date windows, indexes, cached public pages and materialized statistics/standings. Listen only to active chat/relevant records. Store binary media outside Firestore. Avoid hot counters and unbounded arrays; shard or aggregate only when measured contention warrants it. Never cache stale authorization or financial balances as authoritative.

### Durable jobs

Cloud Scheduler triggers periodic work; durable outbox and Cloud Tasks for bounded processing; Cloud Run Jobs for transcode and long migrations. Persist jobId, type, scope, idempotencyKey, state, attempt, lease/fence, nextAttemptAt, correlationId and safe error. Transactional claim, exponential backoff with jitter, bounded retries, dead-letter review and authorized replay. Reconcile duplicates and abandoned leases. Separate worker identities and quotas; prioritize payments/security over optional media.

### Scaling triggers

Measure cold starts before adding warm instances; tune concurrency/CPU/memory when sustained saturation or queuing occurs. Increase caps with cost approval. Dedicated search, distributed caching, analytics warehouse and regional expansion only after measured need. No Kubernetes or broad microservice split at launch. Sport-specific rules/configuration remain modular, not separate infrastructure per sport.

## 12  Security, monitoring and incident response

Use WIF for CI and ADC for runtime; remove key fallback after validation. Scope IAM per API, job and deployment identity; pin dependencies and scan artifacts. Verify production KMS and retained key versions, Secret Manager access, CORS, proxy configuration, App Check enforcement and webhook signatures. Mandatory staff MFA and audited access per Doc 13. Block exploitable critical findings; time-limit lower-risk exceptions.

| Signal | Action / proposed threshold |
|---|---|
| Availability | Cloud Run and Vercel synthetic probes; immediate alert on confirmed outage. |
| API latency/errors | Track p50/p95/p99, cold starts and release regressions; alert on sustained SLO breach. |
| Firestore | Reads/writes, spikes, listener amplification and quota; tune existing thresholds from baseline. |
| Jobs | Queue age, failed retries, lease expiry; urgent financial/security jobs escalate immediately. |
| Payments | Webhook failures, ledger discrepancies, payout exceptions; pause affected settlement. |
| Media | Queue duration, failed screening, storage/egress and quota reservations. |
| Clients | Firebase Crashlytics mobile; evaluate unified error tracking; web vitals and browser errors. |

Structured logs: correlation ID, release, route, status, duration, job ID and redacted error; no credentials, private messages, full payment details or sensitive youth data. Retention follows Doc 13 (ordinary diagnostics proposed 30 days; security audit 12 months).

### Incident runbook

Detect → classify → contain → preserve evidence → restore → reconcile → notify as required → document corrective actions. Owner receives immediate critical alerts but no 24/7 staffing promise. Use targeted maintenance and emergency flags from Doc 14; restrict payouts or media independently. Test alert delivery before launch and after changes.

## 13  Budget and resource governance

| Illustrative monthly allocation | USD |
|---|---|
| Firestore / database operations | 30 |
| Cloud Run / functions | 20 |
| Media storage / delivery | 35 |
| Web hosting | 20 |
| Meetings / communications | 15 |
| Monitoring / backups / security | 10 |
| Contingency | 20 |
| Total planning ceiling | 150 |

Allocation is illustrative, not a provider quote or hard spending cap. Initial target $50–$150; excludes transaction fees, app-store fees, legal and labor. Verify actual regional rates and provider plans. Track cost per active user, media GB, participant-minute, tournament and job. Example: 1,000 DAU × 3 sessions × 100 reads × 30 days = 9 million reads; at illustrative $0.06/100k = $5.40 gross read cost, excluding writes, index reads, storage, egress and allowances.

| Budget threshold | Response |
|---|---|
| 50% | Informational alert |
| 75% | Review forecast and workload trends |
| 90% | Investigate abnormal use |
| 100% / forecast breach | Immediate alert; approve capacity or restrict optional workloads |

Budget alerts are not spending caps. Enforce server-side quotas and reservations per Docs 11/16; limit new large uploads, optional exports, expensive analysis and future AI before essential operations. Never automatically disable authentication, safety reports, financial reconciliation or required recovery. Record overrides and expiry; monitor abuse and provider costs daily.

## 14  Backup and disaster recovery

| Resource | Recovery policy |
|---|---|
| Firestore | Daily managed backup or export; proposed 30-day retention; verify restore capability and region. |
| Storage | Appropriate soft-delete/retention; inventory assets and reconcile metadata; respect deletion/legal holds. |
| Auth | Document supported secure export/recovery; protect credentials and identity mappings. |
| KMS / secrets | Retain necessary key versions; controlled secret recovery/rotation; do not destroy required keys. |
| Code / configuration | Immutable images, web deployments, versioned rules/indexes, DNS and IAM inventory. |
| Stripe / ledger | Daily and event-driven reconciliation; reconstruct missing records from authoritative provider events. |

### Recovery exercise

Before launch and quarterly: choose recovery point, isolate target, restore data, validate counts and access rules, verify KMS decryption, reconcile storage references and payment ledger, test representative workflows, measure RPO/RTO, record gaps and destroy temporary copies securely. No live payments or notifications from restore environment. Verify backup freshness daily and alert on failure.

### Incident recovery

Contain writes or isolate affected module; preserve evidence; identify last consistent point; restore into isolated environment; validate authorization, financial invariants and data integrity; approve controlled cutover; reconcile subsequent writes/provider events; monitor and communicate. Target RPO/RTO 24 hours initially, not guaranteed. Financial recovery cannot accept a day of lost transactions. Reapply deletion requests and restrictions after restore to prevent resurrection of removed data.

## 15  Delivery plan and launch gates

| Phase | Implementation and acceptance |
|---|---|
| 1 — CI hardening | Required main checks; web tests, Firebase rules/server suites, Android builds, pinned tools, scans, WIF. |
| 2 — Production readiness | Verify IAM/KMS/App Check/CORS, secrets, scheduler, provider modes; candidate rollout and rollback; release manifest. |
| 3 — Reliability | Durable jobs, alerts, crash reporting, backups, restore drill, migration registry, cost dashboards. |
| 4 — Launch validation | 10/50/100 load scenarios, browser/device regression, accessibility, operational runbooks, explicit owner signoff. |
| 5 — Growth | Tournament spikes, warm instances if justified, IaC expansion, dedicated staging/search/cache as needed. |

### Independent release gates

Core: all critical functional/security checks, recovery exercise, load objectives, monitoring delivery, support and incident procedures, policies reviewed. Paid hosting: verified host controls, risk-tier settlement, refunds/disputes, reconciliation and emergency pause proven in test mode. Youth: consent, age restrictions, supervised communication, privacy and moderation tested before access. Do not enable gated features merely because core release passes.

### Proposed repository additions

.github/workflows/ci-mobile.yml, ci-firebase-rules.yml, ci-security.yml, ci-e2e.yml; tests/e2e, tests/load, tests/fixtures; infra/environments, monitoring, backup, recovery; scripts/migrations, seed, release, verification; docs/operations/deployment.md, rollback.md, incident-response.md, disaster-recovery.md, release-checklist.md. Reuse existing paths and workflows; names are proposed.

Release checklist record: gate, evidence link, result, owner, timestamp, exception and expiry. Critical failures block; lower-risk exceptions documented. No repository modifications are included in this specification.

## 16  Source register and validation limits

Repository: github.com/brianrhonea/frisbee_app — development branch, reviewed 25 November 2026. Source paths below resolve under https://github.com/brianrhonea/frisbee_app/blob/development/.

.github/workflows/ci-node.yml

.github/workflows/_deploy-api.yml

.github/workflows/_deploy-backend.yml

apps/api/DEPLOY.md

apps/api/deploy/service.yaml

codemagic.yaml

firebase/.firebaserc

firebase/docs/monitoring.md

package.json

apps/api/package.json

apps/web/package.json

firebase/functions/package.json

### Related specifications

01 Architecture; 10 Payments & Fraud Prevention; 11 Subscriptions & Monetization; 12 Notifications; 13 Security, Privacy & Moderation; 14 Administration & Operations; 15 Statistics; 16 Playbooks & Video; 17 UI/UX. Approved decisions are carried forward from the requirements workshop.

### Validation limitations

Selected source files and tree were reviewed, not a complete repository audit. Live cloud configuration, CI execution results, provider pricing, throughput, coverage, backups, alert delivery and recovery were not verified. Numeric rollout stages, coverage targets, workload mix, allocation and test durations are engineering proposals. Verify all before production promotion. No legal or provider compliance certification is implied.
