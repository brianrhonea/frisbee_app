<!-- Converted from Stall10_12_Notifications_Reminders.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# 12  Notifications & Reminders

PRODUCT & ENGINEERING SPECIFICATION  /  VERSION 1.0

Approved product scope • Development branch baseline • Proposed engineering contracts

### Executive summary

Stall10 notifications should help athletes act on meaningful sporting activity without creating unnecessary interruptions. Retain Firebase Cloud Messaging (FCM), Firestore feeds and Cloud Functions; introduce reliable scheduling, channel-specific preferences and durable delivery. Launch with ultimate while keeping notification contracts sport-agnostic.

### Scope and dependencies

Document 01 establishes API-only application writes and authorized direct real-time reads. Documents 03–08 define social, workspace, messaging, calendar and discovery events; 09–11 define competition, financial and subscription events. Document 13 governs safety and privacy; Document 17 owns UI design. No UI mockups are included.

### Reading guide

| Section | Subject |
|---|---|
| 02 | Approved requirements |
| 03 | Repository baseline |
| 04 | Channels, priority and preferences |
| 05 | Calendar and participation reminders |
| 06 | Messaging, social and competition |
| 07 | Financial and organizer communications |
| 08 | Delivery architecture and scheduling |
| 09 | Data, API and device lifecycle |
| 10 | Security, retention and operations |
| 11 | Acceptance, rollout and references |

Status convention: approved = user-confirmed requirement; baseline = observed source behavior; proposed = engineering or policy parameter requiring validation.

## 02  Approved product requirements

| ID | Approved requirement |
|---|---|
| NR-01 | Mobile push and in-app; essential transactional email at launch; browser push later. |
| NR-02 | Independent in-app, push and email preferences; workspace, conversation and event overrides. |
| NR-03 | Actionable defaults enabled; grouped social activity; promotional opt-in. |
| NR-04 | Four priorities; restricted critical classification. |
| NR-05 | Event-specific defaults and user-customizable reminder offsets. |
| NR-06 | RSVP, registration, waitlist and response-aware reminders. |
| NR-07 | Timezone-aware quiet hours with eligible urgent exceptions. |
| NR-08 | All messages, mentions-only or muted; configurable personal and role mention exceptions. |
| NR-09 | Full, sender-only or generic previews; conservative sensitive-content defaults. |
| NR-10 | Follow competitions, divisions, teams or games; selectable milestones. |
| NR-11 | Optional daily and weekly digests after launch. |
| NR-12 | Authorized RSVP, invitation, waitlist and other notification actions. |
| NR-13 | 60-day ordinary history; separate delivery, financial and security retention. |
| NR-14 | Permission-controlled targeted announcements and rate limits; premium automation later. |
| NR-15 | Durable outbox, scheduled jobs, bounded workers, retries and idempotency. |
| NR-16 | Free core notifications and reminders; premium organizer automation and aggregate analytics. |

Additional requirements: none. Exact timing, quotas, provider selection and operational targets below are proposed, not additional approved decisions.

## 03  Repository baseline

| Area | Observed behavior |
|---|---|
| Model [1] | Eight categories: chat, directMessages, eventChanges, eventReminders, teamActivity, meetings, posts, social. Missing preferences default on; team overrides and room/conversation mutes. |
| Delivery [2] | Per-recipient preference check before feed write; transactional grouping, distinct social items (max 50), 10-minute suppression for eligible repeats; moderation filter; FCM sendEach to installation IDs; invalid target cleanup. |
| Triggers [3] | Chat, DMs, team events, meetings, plays, video comments, invitations, join requests, posts and social interactions. Recurrence bulk-write suppression; retraction of supported social entries. |
| Reminders [3] | Hourly query for starts 23–24 hours ahead; personal, shared and team events; marker created before delivery. Feed cleanup 60 days, markers 3 days; 450 records per query per run. |
| Competition [3–5] | Invites, missing roster/payment deadline alerts, published schedule and final scores; league drafts and signup decisions. Schedule fan-out queries up to 200 accepted entries. |
| Clients [6–9] | Flutter feed, preferences, device registration and route opening; web settings use API category endpoint. Chat entries hidden from general mobile notification list; Android/iOS/macOS push, Windows unsupported. |

### Gaps and risks

Current preference gate suppresses both feed and push. Fixed UTC offset may become stale. Reminder markers can suppress retries after failure; narrow scheduler windows can miss events. Recipient fan-out is unbounded and failures are logged rather than durably retried. Browser push, transactional email, outbox and advanced preferences are target capabilities, not established by reviewed files.

## 04  Channels, priority and preferences

| Priority | Policy |
|---|---|
| P0 Critical | Security compromise, sensitive payout changes, serious safety incidents. Backend-classified; essential email where appropriate; no promise of OS bypass. |
| P1 Time-sensitive | Cancellation, venue change, waitlist claim, deadlines. Prompt delivery; eligible urgent exception only. |
| P2 Standard | Messages, invitations, mentions, ordinary reminders. Respect quiet hours and channel preferences. |
| P3 Low | Likes, follows, recommendations and promotions. Group or digest; promotional opt-in. |

### Channel policy

In-app is persistent and available without push permission. Mobile push is interruptive and device-specific. Essential transactional email is separate from marketing consent; use verified addresses and appropriate provider/legal requirements. Browser push is post-launch; SMS only a future exceptional option. No ordinary SMS reminders.

### Preference resolution

First check current recipient authorization, blocks, eligibility and source state. Resolve explicit event/conversation overrides, workspace overrides, then global category/channel defaults. Device permission and user device settings constrain push. Conversation mute wins unless the user permits personal or role mention exceptions. Quiet hours defer or suppress ordinary push; recheck relevance before release. Essential security/financial records remain accessible independently of optional activity preferences.

Use IANA timezone identifiers for quiet hours and digest schedules, including overnight intervals, weekends and daylight saving changes. Proposed default quiet hours 10 PM–7 AM only if enabled by the user. Never imply critical alerts bypass OS permissions or Do Not Disturb.

### Notification center

Support unread/category/workspace filters, mark read/all read, dismiss, grouped activity and safe deep links. Chat unread state remains in messaging. Actions such as RSVP, accept invitation or claim a seat call the authoritative API, rechecking access, expiry, capacity and recent authentication when needed.

## 05  Calendar and participation reminders

Use canonical event IDs and versions from Document 07; references in personal calendars must not create duplicate reminders. Store UTC instants and event IANA timezone; render in venue or user-selected timezone. All-day reminders use local date rules. Proposed default offsets:

| Event | Reminder offsets before start/deadline |
|---|---|
| Practice / scrimmage / pickup / clinic | 24 hours and 1 hour |
| Game / tryout | 24 hours and 2 hours |
| Tournament | 7 days, 24 hours and 2 hours |
| Meeting | 15 minutes |
| Personal event | User-configurable |
| RSVP deadline | 24 hours; optional final reminder |
| Payment / registration deadline | 3 days and 24 hours |

### Recipient policy

Going: attendance reminders. Maybe: confirmation prompt. No response: RSVP reminder. Not going: suppress ordinary attendance reminders. Waitlisted: promotion and claim expiry. Registered: competition updates; canceled registration: suppress ordinary reminders. Changes and cancellations reach affected eligible participants; paid registrants receive applicable transactional communications.

### Lifecycle and edge cases

Create reminder jobs per occurrence, offset and recipient policy; evaluate current membership and RSVP at dispatch. Rescheduling invalidates obsolete versions and regenerates future jobs. Cancellation suppresses attendance reminders and sends one cancellation update. Preserve historical records. Series creation or bulk changes generate one summary rather than one push per occurrence. Catch up missed jobs only while actionable; never send an expired waitlist claim or reminder after event start. Personal overrides follow the canonical occurrence, not duplicated calendar references.

## 06  Messaging, social and competition

### Messaging

Keep grouped feed entries per conversation and separate unread indicators in chat. Direct messages default to prompt push; group and team rooms support all, mentions-only or muted. Personal/role mention exceptions are configurable; @everyone requires scoped permission and respects mute. Edits do not create ordinary pushes; deletion updates in-app state where possible. Incoming call alerts follow post-launch calling support. Private previews default to generic or sender-only; user may choose full where safe.

### Social and discovery

Retain distinct-item grouping, retraction and repeat suppression. Follow requests and replies/mentions are actionable; likes and new followers are grouped or quiet. Followed-account posts require explicit subscription. Saved search matches and optional daily/weekly digests arrive after launch; honor hidden recommendations, opt-outs and reset preferences. Promotions require explicit opt-in and clear labeling. Already delivered device notifications cannot reliably be recalled.

### Competition milestones

| Milestone | Audience |
|---|---|
| Invite / acceptance / roster deadline | Authorized captains, administrators, registrants with outstanding actions |
| Published schedule / field or time change | Affected registered teams and participants |
| Bracket assignment / game start / final | Affected participants and opted-in followers |
| Cancellation / completion verification | Affected registrants, organizers, eligible independent participants |
| Live score updates | Real-time data listeners; no push per score change |

Allow following competition, division, team or game with selectable milestones. Deduplicate overlapping subscriptions; never grant private event access through following. Preserve draft and signup decision notifications. Paginate all eligible competition entries; do not silently truncate at 200.

## 07  Financial and organizer communications

| Trigger | Delivery policy |
|---|---|
| Payment receipt / refund | In-app and essential email; optional push for receipt, prompt push for refund. |
| Payment failure / dispute / debt | In-app, prompt push and transactional email to authorized payer or host. |
| Host verification / payout restriction | In-app, prompt push and essential email; no sensitive details in preview. |
| Transfer approval / payout confirmed | In-app and email; optional push. |
| Bank or ownership change | Immediate security notice to appropriate verified contacts; follow Document 10 freeze and review policy. |
| Subscription trial / renewal / cancellation | Verified billing events; proposed trial reminder 3 days before expiry, renewal notices as required. |
| Usage / downgrade | Proposed 75%, 90%, 100% thresholds once per period; notify before excess-media transition ends. |

Use authoritative payment, ledger and entitlement events; deduplicate provider webhooks and never trust client purchase success. Receipts and security records survive notification dismissal. Subscription notices launch with premium billing after launch; essential financial and security email is a launch dependency.

### Organizer communication

Allow scoped organizers to send announcements to authorized audiences (team, role, event participants or competition division). Validate recipients at delivery, enforce per-sender and workspace quotas, audit author and audience, and reject unauthorized critical classification. Rate-limit mass mentions and repeated announcements. Premium automation and aggregate engagement reports are post-launch; ordinary announcements and reminders remain free. No paywall for security or financial communications.

## 08  Delivery architecture and scheduling

### Durable processing

Authoritative API mutation → domain event/outbox → bounded worker → recipient authorization and preferences → feed, FCM or email → delivery status. Use a Firestore transaction to commit domain mutation and outbox together where possible; verified external webhooks and legacy triggers use deterministic source event IDs. Avoid dual publishing during migration. A reconciliation sweeper recovers missing jobs.

Use Firestore-backed outbox and Cloud Tasks as proposed initial infrastructure. Claim jobs with transactional leases and lease expiry; bounded concurrency, pagination and per-channel rate limits protect the database and provider. Use exponential backoff with jitter, maximum attempts, expiry and dead-letter review. Retry transient errors; classify permanent failures and remove invalid installations. Do not retry expired or unauthorized notices.

### Idempotency and state

Key recipient delivery by source event ID, recipient, channel and target installation where applicable; reminder keys include occurrence, source version and offset. Feed grouping key is distinct from delivery idempotency key. State: pending → leased → accepted / retry / suppressed / expired / failed. Record provider acceptance separately from user read state. A crash after provider acceptance but before persistence may duplicate push; exactly-once external delivery is not guaranteed. All notification actions must be idempotent.

### Scheduling

Query indexed pending jobs by nextAttemptAt and due time, including overdue actionable jobs. Use a proposed five-minute sweeper and configurable catch-up window. Recheck source version, status, membership and preferences immediately before send. Cancel or supersede stale jobs; never mark an entire reminder complete before recipient delivery state is durable. Preserve existing recurrence suppression and grouping behavior.

Migration: introduce shared contracts and shadow job generation; compare recipient sets and dedupe keys; enable new workers by category; disable corresponding legacy delivery only after validation. Keep rollback flags and prevent double-send across old and new paths.

## 09  Data, API and device lifecycle

| Collection / path | Purpose |
|---|---|
| users/{uid}/notifications/{id} | Existing feed; add type, priority, source reference/version, readAt, dismissedAt, expiresAt. |
| users/{uid}/settings/notifications | Existing settings; add channel, scope, quiet hours, timezone, previews, digest and schema version. |
| users/{uid}/devices/{installationId} | Existing FID target; platform, permission, lastSeenAt, association status. |
| notificationEvents/{id} | Immutable event identity, source and recipient policy. |
| notificationOutbox/{id} | Due time, lease, attempt, nextAttemptAt, expiry and state. |
| notificationDeliveries/{id} | Recipient/channel/target, acceptance and failure classification. |
| scheduledNotifications/{id} | Occurrence, version, offset, due time, expiry and state. |
| notificationTemplates/{id}; notificationMetrics/{period} | Versioned templates and aggregate operational metrics. |

### Proposed API contracts

GET /v1/me/notifications; PUT /v1/me/notifications/:id/read; POST /v1/me/notifications/read-all; DELETE /v1/me/notifications/:id; GET /v1/me/notification-settings; PUT /v1/me/notification-settings/{category,channels,quiet-hours,digest}; POST /v1/me/devices; DELETE /v1/me/devices/:id; PUT /v1/me/events/:id/reminders; POST /v1/me/notifications/test. Category PUT is referenced by existing web code; reconcile all routes before implementation.

### Device lifecycle

Associate installation on sign-in and permission grant; rotate IDs, revoke association on logout/account switch, remove invalid or user-revoked targets. Enforce unique active account association per installation and recheck it at send. Sync permission and timezone on resume. Test endpoint targets caller devices only and is rate-limited. API-only client writes; authorized direct feed listeners remain supported.

## 10  Security, retention and operations

### Security and privacy

Recheck source access, blocks, audience, membership and youth restrictions before delivery; redact private locations and sensitive financial/security details. Use allowlisted internal route types, authenticate on open and reauthorize actions. Restrict worker service accounts and device records; redact logs and avoid storing raw sensitive payloads. Retain moderation filtering for user-generated previews without suppressing essential system notices. Separate marketing consent and unsubscribe from transactional communication.

| Record | Retention policy |
|---|---|
| Ordinary feed | 60 days (approved). |
| Delivery diagnostics / failures | Proposed 30 days; redact payloads. |
| Completed reminder jobs | Proposed 7–30 days; dedupe horizon must cover retry window. |
| Inactive installations | Proposed review after 90 days; revoke sooner on logout or invalidation. |
| Financial / security records | Separate policies under Documents 10 and 13; not deleted with feed. |

### Operational objectives (proposed)

P95 processing under 30 seconds for time-sensitive and 60 seconds for standard notices; reminders within five minutes of due time. Measure provider acceptance, not assumed device delivery. Alert on overdue queue backlog, retry/dead-letter rate, invalid installations, email bounces, cleanup backlog and duplicate rates. Track opt-outs and RSVP completion rather than maximizing opens.

Budget: preserve initial $50–$150/month overall infrastructure target. Example: 5,000 daily active users × 10 notices × 30 days = 1.5M recipient operations; at 70% push eligibility and 1.3 devices, about 1.365M push attempts before retries. Not a cost forecast. Measure Firestore operations, workers, email and queue costs; use pagination, grouping and bounded fan-out. No provider pricing validated.

## 11  Acceptance, rollout and references

### Release gates

Physical Android/iOS foreground, background, terminated, offline, denied permissions and deep links; APNs configuration and installation rotation; account switch and revoked access; channel overrides, mention exceptions, preview redaction, DST and quiet hours; duplicate triggers and retry after failure; missed scheduler recovery, reschedule/cancel and recurrence suppression; &gt;200 competition entries; verified payment events, threshold dedupe, retention and authorized actions. Extend existing model, tournament, league, mention, post, server and Flutter UI tests.

### Rollout

Launch: existing feed/push, channel preferences, outbox and reminder jobs, quiet hours, device safeguards, transactional email, privacy, competition milestones and authorized actions. Post-launch: browser push, digests, saved-search alerts, subscription lifecycle, calls and premium organizer automation. Future: exceptional SMS and advanced optimization. Email provider, quotas, precise retention and SLOs require validation.

### Source references

Repository: github.com/brianrhonea/frisbee_app, development branch. Exact reviewed paths (append to https://github.com/brianrhonea/frisbee_app/blob/development/):

[1] firebase/functions/src/notifications/model.ts

[2] firebase/functions/src/notifications/deliver.ts

[3] firebase/functions/src/notifications/triggers.ts

[4] firebase/functions/src/notifications/tournament.ts

[5] firebase/functions/src/notifications/league.ts

[6] apps/mobile/lib/data/repositories/notification/notification_repository_firebase.dart

[7] apps/mobile/lib/domain/models/notification.dart

[8] apps/mobile/lib/data/services/push_service.dart

[9] apps/web/components/settings/NotificationSettings.tsx

Review limits: selected source inspection only; tests not executed, live Firebase/APNs and physical devices not verified, no comprehensive security or parity audit. No repository modifications. UI mockups deferred to Document 17.
