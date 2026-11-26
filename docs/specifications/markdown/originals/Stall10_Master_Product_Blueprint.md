<!-- Converted from Stall10_Master_Product_Blueprint.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# Stall10

## Master Product & Technical Architecture Blueprint

Everything sports, connected.

Product vision • Platform capabilities • Technical direction • Growth strategy

### Executive summary

Stall10 is a social sports ecosystem where athletes connect, discover opportunities, manage teams, communicate and coordinate their sporting lives. Tournament hosting and payments are important marketplace features, not the entire product. Ultimate frisbee is the initial market; the underlying platform should support additional sports over time.

### Product pillars

| Pillar | Purpose |
|---|---|
| Connect | Athlete profiles, social feeds, followers, messaging and communities. |
| Compete | Discover teams, players, leagues, tournaments, tryouts and pickup games; register and participate. |
| Organize | Team management, unified calendars, attendance, statistics, playbooks and meetings. |

### Guiding principles

Keep everyday social and organizational tools accessible. Make discovery free. Build trust into paid events. Use one shared backend for mobile and web. Design for multiple sports without prematurely building sport-specific features.

### Document scope

This is the master reference for product and engineering discussions. The separate Stall10 Tournament Marketplace Blueprint remains the detailed specification for organizer onboarding, registration, payment and fraud workflows. Proposed pricing, architecture choices and rollout priorities are planning assumptions, not validated commitments.

# 01  /  Product experience

The mobile experience should encourage daily use through social updates, upcoming events and conversations, while making deeper team and competition tools easy to reach.

| Navigation | Primary experience |
|---|---|
| Home | For You, Following and My Teams feeds; upcoming event card, RSVP, posts and announcements. |
| Discover | Search players, teams, communities, leagues, tournaments and local events; filter by sport, location and date. |
| Teams | Roster, roles, attendance, team feed, statistics, playbooks, video and meetings. |
| Schedule | Unified agenda and calendar; source filters, RSVP, event details and reminders. |
| Chat | Direct messages, group conversations, team and community channels. |

Profile, notifications, account settings and subscriptions remain accessible from global navigation. The Next.js website should expose equivalent capabilities through a desktop-friendly sidebar, with a separate role-protected administration area.

### Social and community experience

Athletes can maintain profiles, sports history, achievements and statistics; follow others; publish workouts, photos, videos and updates; and react, comment or mention teammates. Communities support membership, posts, channels and events without requiring a formal team structure.

### Team experience

Captains and coaches manage membership, permissions, practices, attendance, statistics, playbooks, video analysis and meetings. Players access their teams and schedules from the same account. Organizations may manage multiple teams.

### Discovery and competition

Public listings can include independent and sanctioned events, free activities and externally registered competitions. Verified organizers can offer paid registration through Stall10. Teams can recruit players, and athletes can indicate that they are looking for teams.

# 02  /  Unified events & calendar

Use a central event service as the authoritative source for personal events, shared invitations, team practices, community activities, tournaments and leagues. External calendar integration is a later extension.

### Event model

| Field group | Suggested contents |
|---|---|
| Identity | eventId, sportId, eventType, ownerType, ownerId, createdBy |
| Timing | startAt, endAt, timeZone, recurrenceRule, status |
| Access | visibility, audience references, invitation policy |
| Participation | RSVP policy, capacity, registration reference |
| Display | title, description, location, updatedAt, version |

### Implementation workflow

1. A captain creates or edits an event through the API. The server checks team permissions and writes the canonical event.  
2. A background job updates user calendar references and schedules notifications.  
3. Mobile and web request the user’s calendar for a date range. The API resolves references and checks current access.  
4. RSVP changes update attendance records, not duplicate events. Team membership changes revoke access and trigger index cleanup.

### Consistency and synchronization

Use UTC timestamps with an IANA time zone for display and recurring events. Deduplicate by event ID and occurrence ID. User calendar indexes may contain minimal query fields such as start time and source, but the canonical event remains authoritative. Make fan-out jobs idempotent and handle cancellations, rescheduling and stale indexes.

For external calendars, start with optional read-only export or subscription before implementing two-way sync. External sync requires explicit consent, secure token storage and conflict handling.

# 03  /  System architecture

Recommended starting architecture: a modular monolith behind the existing shared API. Avoid separate microservices until operational scale justifies them.

| Layer | Responsibility |
|---|---|
| Flutter | iOS and Android UI, Firebase sign-in, API client, local cache, push handling. |
| Next.js | Web experience, server-rendered public discovery, admin dashboard and shared API client. |
| Shared API | Verify Firebase ID tokens; authorize resource access; validate requests; apply rate limits; execute business rules. |
| Firebase / Firestore | Application records, membership, events, messages and projections. |
| Cloud Storage / FCM | Media storage and push notifications. |
| Background jobs | Cloud Tasks or equivalent for fan-out, reminders, indexing and reconciliation. |
| Search service | Typesense or Algolia for full-text discovery when needed. |
| Stripe Connect | Marketplace onboarding, payments, transfers and payout integration. |

### Backend module boundaries

Users & profiles; social feed; teams & organizations; communities; messaging; events & calendar; discovery; competitions; payments; subscriptions; notifications; moderation & administration. Each module owns its routes, validation, services and repositories.

### API conventions

Use versioned endpoints, consistent error responses, cursor pagination and server-generated identifiers. Examples: GET /v1/feed, GET /v1/discover, GET /v1/calendar, POST /v1/events, POST /v1/events/{id}/rsvp, POST /v1/conversations/{id}/messages. Use authenticated real-time subscriptions or a controlled streaming layer for chat and updates; do not bypass authorization.

Firebase Admin SDK operations bypass Firestore security rules: the API must enforce permissions itself. Deny direct client writes to protected data. Keep credentials and payment secrets server-side.

# 04  /  Data model & platform operations

| Domain | Logical Firestore collections |
|---|---|
| Identity & social | users, profiles, follows, posts, comments, reactions |
| Teams & groups | organizations, teams, team_memberships, communities, community_memberships |
| Events | events, event_attendees, user_calendar, tournaments, leagues, registrations |
| Communication | conversations, messages, notifications |
| Commerce | hosts, payments, ledger_entries, subscriptions, transfers, payouts, refunds, disputes |
| Trust & safety | reports, risk_flags, audit_logs, host_verifications |

These are logical collections, not a migration plan. Messages and other high-volume child records may be subcollections. Choose indexes based on actual query patterns; paginate feeds and conversations and avoid unbounded listeners.

### Social feed and messaging

Begin with chronological feeds and cursor pagination. Add personalized ranking and materialized feeds only when needed. Enforce visibility and blocking rules on every read. For messaging, check conversation membership, use stable message IDs, track read state and send push notifications without exposing private content unnecessarily.

### Search and media

Index only fields eligible for discovery; remove or update indexed records when visibility changes. Use authorized uploads, media size limits and access-controlled storage. Track storage and bandwidth costs, especially for team video.

### Security and reliability

Support role-based access, reporting, blocking, moderation queues, account deletion, audit trails, backups and recovery tests. Monitor API latency, errors, Firestore reads, job retries and notification delivery. Add integration tests for cross-team access, private calendar events and duplicate operations.

# 05  /  Marketplace & monetization

The tournament marketplace extends discovery into registration and payments. Anyone can submit a listing; collecting money requires organizer and event verification. Hosts set their bid fees, and the platform can add a clearly disclosed service fee so the organizer receives the agreed amount.

### Payment and trust principles

Use Stripe Connect and server-verified webhooks. Separate registration, payment, transfer and payout states. Review new paid events, verify venue arrangements, restrict early payouts and independently verify completion. Maintain an auditable ledger, refund and dispute workflows, and reconciliation. Do not treat held funds as escrow. Confirm processor holding limits, liability, applicable law and app-store rules before launch.

### Proposed monetization

| Revenue stream | Illustrative starting price |
|---|---|
| Individual premium | $4.99/month — advanced athlete analytics and personal features. |
| Team premium | $19.99/month — advanced management, analytics and video storage. |
| Organization premium | $49.99/month — multi-team administration. |
| Marketplace service fee | 4.5–6% combined fee on paid registrations, subject to cost validation. |

Keep profiles, social feed, messaging, discovery, unified calendar, basic team management and community creation free. Premium features should add value rather than restrict core participation. Prices are hypotheses; validate willingness to pay, processing costs, storage costs, refunds and chargeback exposure. Digital subscriptions and real-world event payments may have different app-store requirements.

### Growth cycle

Athletes join → find friends and teams → organize activities → hosts create competitions → teams register and compete → participants share results and invite others. Marketplace activity creates acquisition opportunities, while social, calendar and messaging features support retention.

# 06  /  Delivery roadmap & reference library

| Phase | Suggested deliverables |
|---|---|
| 1. Foundation | Shared identity, profiles, team/community membership, API authorization and core event model. |
| 2. Daily engagement | Social feed, chat, notifications, unified calendar and RSVP. |
| 3. Discovery | Search, public event listings, team recruitment and community submissions. |
| 4. Marketplace pilot | Verified hosts, checkout, ledger, refunds and manually reviewed payouts with known organizers. |
| 5. Premium & scale | Entitlements, advanced analytics, video limits, trust automation and additional sports. |

Sequence these phases against existing functionality rather than rebuilding completed modules. Track weekly active users, retention, team activation, RSVP engagement, successful registrations, repeat hosts, dispute rates and net transaction contribution.

### Recommended documentation library

00 Master product vision • 01 System architecture • 02 Authentication & athlete profiles • 03 Social feed & engagement • 04 Teams & organizations • 05 Communities • 06 Messaging • 07 Events & unified calendar • 08 Discovery & search • 09 Tournament & league marketplace • 10 Payments & fraud prevention • 11 Subscriptions • 12 Notifications • 13 Security & moderation • 14 Administration • 15 Deployment & scalability.

### Open decisions before implementation

Confirm current API language and deployment, existing Firestore schema, real-time transport, privacy defaults, moderation policy, initial sports taxonomy, search provider, premium pricing and payment processor approval. Validate data migration and performance against the existing app.

### Product north star

Give athletes a reason to open Stall10 every day, not only when registering for a tournament. Build the social and organizational foundation first, and use competition infrastructure to deepen participation and generate sustainable revenue.
