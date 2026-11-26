<!-- Converted from Stall10_01_System_Architecture.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# System Architecture & Infrastructure

STALL10  /  DOCUMENT 01  /  VERSION 1.0

Status: proposed engineering baseline incorporating owner-approved requirements. Source: development branch, reviewed 25 November 2026. Repository tree SHA: 39c8a534451a885bb9995b6b5d0e31b8bf39395b (tree response; not asserted to be a commit).

## 1. Executive summary

Stall10 is a social sports ecosystem combining athlete profiles, feeds, teams, communities, communication, calendars, discovery and competition hosting. Launch with ultimate frisbee, while keeping the core architecture reusable for other sports. Retain the existing modular monolith and Firebase platform to minimize operational burden for a solo developer.

| Owner-approved requirement | Direction |
|---|---|
| Data access | All application writes through API; authorized direct Firebase reads for real-time features. |
| Clients | Flutter iOS/Android and Next.js web; practical feature parity. |
| Market | Ultimate first; sport-agnostic foundations. |
| Stage and staffing | Active development, pre-launch; solo developer. |
| Budget and scale | $50–$150/month infrastructure; first-year user count unknown. |

### Scope and evidence

This specification separates observed repository behavior, approved requirements and proposed implementation. It is a static review, not a production audit. No tests were executed, no live cloud settings were inspected, and no repository changes were made.

## 2. System design

Target request flow: Flutter / Next.js → Firebase Auth ID token → Fastify API → domain service → repository / Firebase Admin SDK → Firestore. Authorized real-time listeners read Firestore directly. Firebase Auth, FCM and LiveKit retain their specialized client protocols. Signed media uploads are a proposed explicit exception to API-only application writes: the API authorizes and finalizes the upload; the client transfers bytes directly.

| Component | Observed implementation / responsibility |
|---|---|
| apps/mobile | Flutter MVVM: services, repositories, view models, widgets; API client and feature flags. |
| apps/web | Next.js 16, React 19; package description specifies API writes and member Firestore reads; Vercel hosting. |
| apps/api | Node 22+, Fastify 5, Zod, API v0.48.0; app.ts dependency injection and route registration. |
| packages/shared | Shared TypeScript contracts, schemas and pure logic; cross-language fixtures documented. |
| firebase | Firestore, Auth, Storage, Functions, rules and indexes; triggers and scheduled work. |
| External services | Stripe payments; LiveKit meetings and voice; Cloud KMS, Secret Manager. |

### Service boundaries

Keep account, profiles, follows, posts, browse, teams, hub, messages, calendar, tournaments, drafts, stats, playbook, videos, payments and moderation as domain modules in one deployable API. Use transactions for multi-document invariants and server-owned derived data. Extract services only when measured scaling or isolation needs justify it.

## 3. Current-state assessment

The API registers a broad set of domain services and tests exist for many of them. However, API availability does not mean all mobile callers have migrated. The architecture migration table and feature flags explicitly describe fallback paths.

| Area | Observed status / migration concern |
|---|---|
| Teams and profiles | API paths exist; use_api_teams, membership and profiles flags default on but retain direct-write fallback. |
| Social and follows | API services exist; architecture notes mobile direct writes for comments and follows. |
| Calendar and chat | API services exist; notes identify direct mobile personal events, RSVP and message writes. |
| Tournaments / drafts | API and payment modules exist; tournament flag retains fallback; notes identify direct saves, scores, signups and draft paths. |
| Media / video / stats | API modules exist; migration notes identify remaining direct callers and upload work. Verify current call sites before closure. |
| Rules | Direct client writes are permitted in sampled users, events, follows, devices, teams and membership paths. |
| Security | Bearer token verification and optional App Check; requireCaller helper. Memory write limiter is per instance. |
| Deployment | Cloud Run YAML and GitHub deployment/rollback workflows; separate dev/prod projects documented. |

The migration table contains historical statements (including “not yet: payments”) that conflict with newer registered payment code. Treat it as a lead, not a definitive feature-completion record. Payment readiness requires its own review.

## 4. API-only write migration

Approved policy: application mutations must be authorized and executed by the API. Server-side triggers and jobs may perform internal writes. Firebase Auth SDK operations and push token generation are not application document writes. Register device tokens, preferences and read receipts through API endpoints.

### Inventory

Map every mobile and web set/add/update/delete/batch/transaction, callable and upload to its domain, API endpoint and rule path. Include offline outbox, typing, presence and settings.

### Migrate

Use existing repository interfaces; replace direct mutation implementations with API calls. Add missing endpoints, Zod validation and service authorization. Keep listeners for approved real-time reads.

### Verify

Run emulator tests for valid and denied operations, compare mobile/web outcomes, and test retries and offline replay. Use idempotency keys for payment and other non-repeatable actions.

### Enforce

After clients are migrated, deny client document writes in rules, remove legacy callable paths where replaced, and require API_BASE_URL for release builds. Review overlapping rules because any matching allow can grant access.

### Rollback

Replace direct-write fallback with feature disablement or rollback to a compatible API revision. Do not reopen broad client writes during an incident.

Acceptance: every application mutation is mapped to an API endpoint; direct client writes fail in emulator tests; authorized listeners still work; no missing API configuration silently enables legacy writes.

## 5. Data, privacy and security

### Read policy

Use direct listeners for scoped chat, live scores, notifications and calendar updates where rules can enforce membership and visibility. Use API reads for public discovery, cross-entity aggregation, sensitive projections and expensive search. Do not expose private fields in documents readable by broad audiences. Bound queries, paginate histories, unsubscribe on navigation and share subscriptions.

### Authorization and trust boundaries

Firebase ID tokens identify callers; services must check membership, role, ownership and object visibility on each operation. Admin SDK bypasses Firestore rules. App Check is defense in depth, not authorization. Enforce it on supported protected clients after testing; public routes and signed service callbacks require their own controls. Verify Stripe webhook signatures and scheduler identity. Never trust client-supplied prices, roles or payment states.

### Data integrity and abuse

Use transactions for membership, registration capacity and payment state transitions. Keep payment records server-only, with idempotent webhook processing and reconciliation. Use durable quotas for financial or abuse-sensitive actions; the existing in-memory limiter resets and scales per instance. Keep secrets server-side; verify least privilege, KMS availability, log redaction, account deletion and export. Test youth and private-profile access explicitly.

### Media

Authorize upload purpose, ownership, size and type; issue short-lived scoped URLs; validate actual bytes and finalize metadata through the API. Quarantine unverified files, apply safety checks and remove abandoned uploads. Verify video transcoding and signed URL behavior before enabling large uploads.

## 6. Multi-sport and client parity

Recommendation: introduce a stable sportId for teams, competitions and sport-specific records, with ultimate as the default for migrated data. Keep identity, follows, messaging, calendars, payments and moderation independent of sport. Do not force a sport onto personal events or general posts.

| Shared core | Sport-specific extension |
|---|---|
| Team identity, membership, roles | Roster positions, divisions, eligibility |
| Competition lifecycle, registration | Scoring, rules, standings, bracket constraints |
| Game identity and timestamps | Stat definitions, scoring events, game periods |
| Playbook storage and permissions | Field geometry, symbols and sport-specific plays |

Define sport adapters in shared TypeScript logic and equivalent Dart models only where client behavior requires it. Version stat definitions and rules; preserve historical results. Backfill sportId in dev, verify indexes and query compatibility, then migrate production with a rollback plan. Do not build a second sport until core ultimate workflows are stable.

### Parity contract

Maintain a feature matrix with mobile/web status, API contract, permission checks and acceptance tests. Both clients should support core social, team, calendar, competition and payment workflows. Allow justified device-specific differences such as GPS workout recording, push permissions and native calendar integration. Prefer shared API behavior over duplicated business logic; use cross-language fixtures for Dart/TypeScript validation.

## 7. Infrastructure, cost and reliability

Observed Cloud Run template: 1 CPU, 512 MiB, concurrency 80, 60-second request timeout, minimum zero instances and configurable maximum. Deployment guide documents defaults of 3 dev / 10 prod instances, health and readiness probes, release tags and rollback. Mobile API client has a 20-second default timeout. Align timeouts and make long operations asynchronous where appropriate.

| Proposed monthly allocation | Planning envelope, not a provider quote |
|---|---|
| Firestore / Auth / Functions | $15–$40 |
| Cloud Run / jobs / registry | $5–$20 |
| Storage / media / egress | $10–$35 |
| Web hosting | $0–$20 |
| LiveKit / monitoring / other | $5–$15 |
| Contingency | $15–$20 |
| Total | $50–$150 |

Payment processing, taxes and exceptional usage are excluded. Actual provider pricing, free tiers and commercial hosting eligibility must be verified. Budget alerts are not hard spending caps. Video and live calls can exceed this envelope; set quotas and monitor usage before launch.

### Operational targets (proposed)

Track API p95 latency, 5xx rate, Firestore reads per active user, storage/egress, payment reconciliation lag and monthly spend. Start with p95 under 750 ms for ordinary warm API requests, 99.5% monthly availability, daily backups and a tested restore target of 24 hours; validate against actual traffic. Alert at 50%, 80% and 100% of budget. Load-test 10, 50 and 100 concurrent simulated users as scenarios, not forecasts.

## 8. Delivery plan and acceptance

| Sequence | Exit criteria |
|---|---|
| P0 — Inventory and baseline | Mutation map, read allowlist, feature parity matrix; verify dev/prod configuration and secrets. |
| P0 — Secure write migration | Core social/team/calendar/chat writes through API; remove fallback and deny direct writes after migration. |
| P0 — Financial and privacy gates | Payment lifecycle review, durable controls, authorization and youth/private visibility tests. |
| P1 — Media and parity | Verified upload pipeline; core workflows pass on both clients. |
| P1 — Sport abstraction | Ultimate defaults and migration tests; sport-neutral core models. |
| P1 — Launch operations | CI green, emulator tests, load tests, monitoring, backup restore and rollback rehearsal. |

CI should run shared/API typechecks and unit tests, Firebase emulator and rules tests, Flutter analysis/tests, and Next.js typecheck/build. Add cross-client end-to-end smoke tests for sign-in, team join, message, RSVP, tournament registration and payment sandbox. Use development for validation and approved production releases. Keep schema changes backward compatible across mobile release lag.

### Open decisions

Confirm permitted signed-upload exception; select durable quota mechanism after measurement; set retention and backup policies; determine launch traffic targets and commercial hosting costs. Validate actual App Check enforcement, KMS, Stripe, LiveKit and production deployment status. No implementation dates are assumed.

## 9. Repository evidence and review limitations

All paths below refer to the development branch. Use the repository history to pin a commit before implementing or approving changes. The review used a tree listing and selected file contents; it did not exhaustively inspect all frontend call sites or run tests.

Target architecture and migration notes — ARCHITECTURE.md  
https://github.com/brianrhonea/frisbee_app/blob/development/ARCHITECTURE.md

Domain registration, dependency injection, request limits — apps/api/src/app.ts  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/app.ts

Bearer token and App Check handling — apps/api/src/auth.ts  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/auth.ts

Per-instance rate limiting — apps/api/src/limits/memory.ts  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/limits/memory.ts

Runtime, dependencies and test scripts — apps/api/package.json  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/package.json

Deployment, rollback and configuration guidance — apps/api/DEPLOY.md  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/DEPLOY.md

Cloud Run template — apps/api/deploy/service.yaml  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/deploy/service.yaml

Web stack and declared access strategy — apps/web/package.json  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/web/package.json

API transport and missing-base-URL fallback — apps/mobile/lib/data/services/api_client.dart  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/mobile/lib/data/services/api_client.dart

Migration flags and direct-write fallback — apps/mobile/lib/data/services/feature_flags.dart  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/mobile/lib/data/services/feature_flags.dart

Sampled direct-write and read permissions — firebase/firestore.rules  
https://github.com/brianrhonea/frisbee_app/blob/development/firebase/firestore.rules

Next specification: Authentication & Athlete Profiles. Review profile models, privacy controls, onboarding and account lifecycle before asking the owner for unresolved product decisions.
