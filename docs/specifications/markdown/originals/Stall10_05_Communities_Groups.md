<!-- Converted from Stall10_05_Communities_Groups.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# 05  Communities & Groups

PRODUCT & ENGINEERING SPECIFICATION  /  VERSION 1.0

Approved product scope • Proposed implementation details • Development branch baseline

### Executive summary

Communities are the low-friction entry point to Stall10: athletes discover local sports, join groups, attend pickup events, build relationships and progress into tournaments or competitive teams. Core participation remains free. Optional premium tools and verified paid activities support sustainable operations.

### Scope and dependencies

Reuse the shared team entity, membership, chat, social feed, calendar and notification infrastructure. Launch with ultimate; design for multiple sports. All application writes go through the API; authorized real-time reads may use Firebase directly. Maintain practical Flutter and Next.js parity. UI mockups are deferred to Document 17.

### Reading guide

| Section | Subject |
|---|---|
| 02 | Approved requirements |
| 03 | Repository baseline |
| 04 | Membership, discovery and affiliations |
| 05 | Events and guest participation |
| 06 | Tournaments, engagement and monetization |
| 07 | Data and API architecture |
| 08 | Security, testing and rollout |
| 09 | References and open decisions |

Status convention: approved = user-selected product requirement; baseline = observed source or documented behavior; proposed = implementation recommendation, not a confirmed existing feature.

## 02  Approved product requirements

| ID | Approved requirement |
|---|---|
| CG-01 | Flexible categories on one shared community entity. |
| CG-02 | Multiple sport affiliations; ultimate only at launch. |
| CG-03 | Independent public, private and unlisted visibility and separate join policies. |
| CG-04 | Recurring events, occurrence edits, capacity, waitlists and minimum attendance. |
| CG-05 | Limited organizer-enabled guest registration, subject to eligibility. |
| CG-06 | Map and list discovery with distance, sport, skill, activity and cost filters. |
| CG-07 | Configurable hat tournament skill, position and eligibility balancing; manual overrides. |
| CG-08 | Verified payments for events, tournaments, optional dues, clinics and contributions. |
| CG-09 | Rules, membership questions, temporary restrictions, bans, reports and moderation logs. |
| CG-10 | Announcements, polls, resources, challenges and optional participation milestones. |
| CG-11 | Free basic aggregate analytics; premium advanced reporting. |
| CG-12 | Free core functionality with optional community premium plan. |
| CG-13 | Mutual affiliations and cross-promotion without inherited access or membership. |
| CG-14 | Organizer-selected members-only, approval-required or public event registration. |

Additional requirements: none. Detailed thresholds, limits and release sequencing below are proposed, not additional approved product decisions.

## 03  Repository baseline

The development branch uses teams/{id} with kind: community for informal groups and kind: organization for schools and clubs. Shared infrastructure avoids duplicating team services.

| Area | Observed or documented behavior |
|---|---|
| Creation [1] | Group description, requiresApproval and location; directory projection omits location for approval groups. General text room and three voice rooms created by default. |
| Membership [2] | Authenticated routes for direct join, requests, approval, invites, removal, roles, ownership and listing. |
| Community experience [3,4] | Events, chat, tournaments and members; next pickup card with RSVP for members and join action for outsiders. Nominatim and OpenStreetMap documented. |
| Tournaments [5] | Create, update, publish schedule, captain report, opponent confirm, organizer correction, seed and advance bracket. |
| Organization links [6,7] | Mutual team linking, role mirroring and removal of organization-added members; club-level automatic additions blocked because encrypted age cannot be verified. |
| Events and chat [3] | Shared events, public projections, RSVP, polls, reminders, role audiences, room access, voice and Discord template import documented. |

### Gaps to validate

Independent join and visibility controls, recurrence, guest registration, capacity/waitlist transactions, advanced balancing, community-specific analytics and paid activities were not established in the reviewed sources. Treat these as target capabilities pending a broader code audit. Existing tests were located but not executed.

## 04  Membership, discovery and affiliations

### Entity and membership

Community categories are configurable metadata (pickup, local sports, training, recreational, youth, alumni, interest, fan or tournament). sportIds supports multiple sports, constrained to ultimate at launch. Owners and delegated organizers manage membership using shared custom roles; event hosts and moderators receive scoped permissions. Confirm ownership transfers on both sides per Document 04.

| Control | Proposed behavior |
|---|---|
| Visibility | Public: discoverable safe projection. Private: limited listing if opted in. Unlisted: no search listing; link reveals only safe metadata. |
| Join policy | Open, approval or invite-only, independent of visibility. Ban and eligibility checks always take precedence. |
| Directory and location | Separate member-directory and exact-location policies; private athlete and youth restrictions override group settings. |
| Affiliations | Mutual request/accept/revoke; cross-promotion only. No inherited roles, membership, private data or event access. |

### Discovery and workflows

Athlete searches by city or optional location and filters by radius, sport, category, skill, activity, cost, age eligibility and upcoming events. Return the same privacy-filtered results for map and list. Rank using proximity, interests, upcoming events, activity and social connections; weights remain tunable. Never require continuous location access.

Join workflow: validate policy, eligibility and ban state; create membership or pending request atomically; notify organizers; approve or decline; update authorized projections. Leaving revokes access and cancels future member-only registrations according to event policy. Keep permitted historical attendance records.

## 05  Events and guest participation

### Recurring event lifecycle

Organizer defines timezone, recurrence, start/end, venue, minimum and maximum participants, registration window, eligibility, audience, cost and guest policy. Generate bounded future occurrences with stable IDs. Edit one occurrence, this and future, or entire series; preserve past attendance and paid registrations. Handle daylight saving time in the event timezone.

### Registration and capacity

Separate event visibility from registration policy: members-only, approval-required or public. A public event does not grant community membership. Going consumes a seat; Maybe does not. Use transactions to enforce capacity, deduplicate registrations and promote eligible waitlisted participants in order. For paid events, reserve seats with expiring holds and confirm only after verified payment. Notify on promotion, cancellation and changes.

### Guests and eligibility

Organizer may enable limited guests with a configurable per-registration limit. Collect only necessary guest information and consent; use a guest record rather than a fabricated athlete account. Enforce age and waiver rules, count guests toward capacity, and restrict guest access to event-specific information. Do not expose private community content. Require verified guardian consent where applicable; legal requirements remain to be established.

### Attendance and cancellation

Track RSVP separately from actual attendance; organizers record or correct check-ins with audit history. At a configurable minimum-attendance deadline, notify organizers or apply their chosen automatic cancellation policy. Cancellation releases seats, updates calendars and initiates applicable refunds. Avoid automatic cancellation of paid events without an approved refund policy.

Acceptance example: two simultaneous registrations for the final seat yield one confirmed registration and one waitlist entry; cancellation promotes exactly one eligible participant. A single-occurrence edit does not alter other dates.

## 06  Tournaments, engagement and monetization

### Hat tournaments

Reuse the existing group tournament service. Register individuals, capture optional skill/position preferences and eligibility, generate balanced teams, allow authorized manual overrides, assign captains and publish schedules. Use configurable balancing constraints; hard eligibility rules cannot be overridden. Keep skill ratings private. Record algorithm inputs/version and organizer changes for reproducibility. Preserve captain reporting, opponent confirmation and organizer dispute resolution; lock dependent bracket games against unsafe score edits.

### Engagement and moderation

Reuse posts, chat, polls and notifications. Add announcements, resources, challenges and opt-in participation milestones. Organizers configure rules and membership questions; moderators may restrict or ban members, remove content and record reasons. Provide reporting and platform escalation. Community bans do not automatically suspend platform accounts. Prevent banned users from rejoining through invite or guest pathways.

### Payments and subscriptions

Free core: creation, membership, chat, posts, recurring events, RSVP, waitlists, basic attendance and aggregate analytics. Optional premium: advanced reports, expanded media, automation and advanced balancing. Exact entitlements and prices belong to Document 11. No individual subscription is required for basic participation.

Verified hosts may collect event fees, tournament entry, optional dues, clinics and contributions through the approved payment architecture. Use provider-managed onboarding, payment confirmation, refunds and payouts; no Stall10-operated wallet. Record offline payments separately. Do not imply tax-deductibility for contributions. Document 10 defines risk controls and payout rules.

### Analytics

Free aggregate counts: members, active participants, events and attendance. Premium reports: retention cohorts, repeat attendance, RSVP conversion and cancellations. Define active participant by recorded attendance within the reporting window; suppress small cohorts where privacy requires it. No public individual attendance or skill ranking.

## 07  Data and API architecture

Proposed target model; reconcile names with current collections before migration. Keep canonical events in the shared calendar architecture.

| Path / projection | Purpose |
|---|---|
| teams/{id} | kind, sportIds, category, owner, visibility, joinPolicy, branding, safe location settings |
| teams/{id}/members/{uid} | Roles, grants, status, joinedAt; migrate legacy maps incrementally |
| joinRequests/{uid}, bans/{uid} | Pending approvals, restrictions and expiry |
| recurringSeries/{id}, events/{id} | Recurrence rules and canonical occurrences |
| events/{id}/registrations/{id} | Participant or guest reference, status, hold expiry, payment reference |
| events/{id}/attendance/{id} | Actual attendance and correction metadata |
| affiliations/{id}, moderationLogs/{id} | Mutual link state; append-only actions |
| teamDirectory/{id} | Privacy-filtered discovery projection; geospatial index |
| analytics/{periodId} | Aggregated metrics; restricted access |

### API contracts

Existing routes: POST /v1/teams/:id/members; POST /v1/teams/:id/join-requests; POST /v1/teams/:id/join-requests/:uid/approve; POST /v1/teams/:id/invites; PUT /v1/teams/:id/roles; PATCH /v1/teams/:id.

Proposed extensions: GET /v1/communities/discover; PUT /v1/teams/:id/visibility and /join-policy; POST /v1/teams/:id/recurring-series; PATCH /v1/teams/:id/recurring-series/:seriesId; POST /v1/teams/:id/events/:eventId/registrations and /check-in; PUT/DELETE /v1/teams/:id/bans/:uid; GET /v1/teams/:id/analytics. Add mutual affiliation request/accept/revoke operations.

Validate shared Zod contracts; verify Firebase ID token and scoped permissions; use idempotency keys for retries, transactions for capacity and membership, cursor pagination for discovery, and server timestamps. Return safe projections rather than raw private documents.

## 08  Security, testing and rollout

### Security and operations

Apply API-only application writes and least-privilege Firebase read rules. Trusted backend triggers may maintain projections and notifications. Test private locations across search, event responses, caches and notifications; revoke access on membership removal. Rate-limit joins, invites, guest registration and reports. Audit financial and moderation actions. Use bounded recurrence generation and paginated membership reads to control cost.

| Acceptance area | Required outcome |
|---|---|
| Visibility / youth | Private and unlisted groups never leak restricted location or member data; age checks fail closed. |
| Membership / affiliation | Concurrent approvals are idempotent; bans block invites; affiliation never grants access. |
| Events | DST, occurrence exceptions, capacity, waitlist and cancellation work across clients. |
| Guests / payments | Eligibility and capacity enforced; expired holds release; duplicate webhooks do not double-confirm; refunds reconcile. |
| Tournaments | Hard constraints enforced; score disputes and simultaneous confirmation preserve bracket integrity. |
| Moderation / analytics | Role revocation immediate for new requests; audit records restricted; aggregates do not expose private participants. |

### Proposed rollout

Launch: existing functionality, API migration, categories, geographic discovery, independent privacy, recurrence, capacity/waitlists, attendance, basic moderation and existing hat tournaments. Post-launch: guest registration, paid activities, advanced balancing, affiliations, challenges and premium analytics. Future: weather integrations, sponsorship and additional sports. Gate paid features on Document 10 readiness and guest features on eligibility/consent readiness.

## 09  References and open decisions

Source baseline: brianrhonea/frisbee_app, development branch, reviewed during Document 05 assessment. References below identify the exact reviewed files; branch contents may change.

[1] https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/teams/documents.ts

[2] https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/teams/membership_routes.ts

[3] https://github.com/brianrhonea/frisbee_app/blob/development/docs/ARCHITECTURE.md

[4] https://github.com/brianrhonea/frisbee_app/blob/development/apps/mobile/lib/ui/teams/widgets/community_sections.dart

[5] https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/group_tournaments/service.ts

[6] https://github.com/brianrhonea/frisbee_app/blob/development/firebase/functions/src/communities/model.ts

[7] https://github.com/brianrhonea/frisbee_app/blob/development/apps/web/components/team/CommunityAdmin.tsx

### Open implementation decisions

Confirm guest limits, waitlist promotion timeout, recurring horizon, retention periods, geospatial indexing approach, analytics thresholds, payment eligibility and subscription entitlements during implementation. These are not unresolved product requirements; they are proposed engineering and policy parameters. Document 07 owns canonical calendar behavior; 08 owns discovery; 10–11 own payments and pricing; 13 owns platform safety; 17 owns UI design.

### Review limitations

Selected source review only; no application execution, automated tests, full Firebase rules audit or complete mobile/web parity verification. Existing features may extend beyond the reviewed files. Proposed API paths and schemas are not claims of current implementation. No repository changes were made. UI mockups intentionally omitted.
