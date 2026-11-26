<!-- Converted from Stall10_07_Events_Unified_Calendar.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# 01  /  Events & Unified Calendar

Approved product requirements | Development branch assessment | Version 1.0

### Executive summary

Stall10 provides one consolidated sporting schedule across personal and shared calendars, teams, communities, tournaments, training and meetings. Each event retains one authoritative source; other views reference it rather than create independently editable copies. Launch focuses on ultimate, with sport-agnostic contracts and practical Flutter/Next.js parity.

### Scope and constraints

All application writes go through the authenticated API. Authorized direct Firebase reads remain available for real-time features; shared calendar reads retain the existing API permission boundary until rules are verified. Solo developer; overall infrastructure planning budget $50–$150/month. No UI mockups: design system deferred to Document 17.

### Success measures (proposed)

Track calendar adoption, weekly active schedule users, RSVP completion, duplicate-event rate, reminder delivery, registration failures, feed errors and query latency. Establish beta baselines before committing numerical targets.

### Reading guide

02 Approved requirements • 03 Repository baseline • 04 Calendar behavior • 05 Recurrence and time • 06 Participation • 07 Integrations • 08 Technical contracts • 09 Security and operations • 10 Delivery and references. Approved requirements are binding product direction; implementation choices and release sequencing are proposals unless explicitly approved.

## 02  /  Approved requirements

| ID / topic | Approved direction |
|---|---|
| EC01 Views | Agenda, day, week, month, year and season; phased. |
| EC02 Classification | Sport-agnostic presets and optional custom classifications. |
| EC03 Aggregation | One authoritative event with unified references. |
| EC04 Sharing | Owner, editor, viewer and availability-only. |
| EC05 Invitations | Personal event invitations, acceptance and RSVP. |
| EC06 Recurrence | Custom intervals, multiple weekdays, exceptions, end dates and occurrence edits. |
| EC07 Time | All-day, multi-day, timezone-aware and local display options. |
| EC08 Conflicts | Private warnings; travel-aware detection later. |
| EC09 Availability | Polls and privacy-preserving aggregate availability. |
| EC10 External | Free ICS at launch; imports later; two-way sync future. |
| EC11 Feeds | Independently revocable feeds filtered by calendar, event and RSVP. |
| EC12 Tournaments | Automatic confirmed games, provisional schedules and bracket assignments. |
| EC13 Cancellation | Preserve canceled records, notify and retain authorized history. |
| EC14 Preferences | Cross-device colors, visibility and display preferences. |
| EC15 Monetization | Free core calendar and subscriptions; premium advanced scheduling/reporting. |

Additional requirements: none. Prior approved community capacity, waitlists, attendance, payment and communication requirements remain applicable.

## 03  /  Repository baseline

| Reviewed component | Established behavior |
|---|---|
| Calendar service and routes | Create/list/rename/delete calendars; invitations, role changes, acceptance, removal; event CRUD; feed create/reset/disable. |
| Shared calendar schema | Default calendar cannot be deleted; owner/edit/view; viewers omit notes; 20 owned calendars, 50 members plus invites, 92-day query window, 300 events per calendar/request. |
| Recurrence engine | Daily, weekly, biweekly, monthly; bounded to one year; deterministic occurrence IDs; one/following edits; wall-clock conversion. |
| Team hub service | manageEvents authorization; public projections; member RSVP notes, reactions and polls; reactions/votes require Going; series edits preserve RSVPs. |
| Mobile calendar service | Native event editor on iOS/Android; ICS fallback; documented pending future on iOS 17+ plugin version. |
| Web utilities | ICS download/share, local hidden-calendar preferences; shared subscription links for Apple, Google and Outlook. |
| Tests | Calendar API/emulator and shared recurrence fixtures exist; execution not verified. |

### Gaps to verify

External imports, two-way sync, all-day semantics, cross-source deduplication, availability-only access, registration and attendance integration are target capabilities, not established by the selected files. The existing calendar-events contract selects starts within a window; verify overlap behavior. Public projection safety and mobile/web parity require tests.

## 04  /  Calendar behavior and permissions

### Aggregation and navigation

Normalize source records into a common schedule projection with stable composite source identity. Include personal, shared, team, community, tournament, meeting and training sources. Filters: calendar, sport, entity, type, RSVP and date. Agenda/day/week/month first; year and season later. Store per-user display preferences across devices; hiding a calendar never changes membership or source permissions.

### Event classification

Retain practice, game, tournament, scrimmage, workout, social, other and pickup; add tryout, meeting, film review, clinic, travel, volunteer, personal and custom classifications. Optional capability flags enable registration, attendance, payment, scorekeeping or meeting links; validate allowed combinations server-side.

| Role | Access |
|---|---|
| Owner | Manage calendar, invitations, permissions and events. |
| Editor | Read full details and create/edit/delete eligible events. |
| Viewer | Read title, time, type and location; no private notes. |
| Availability only | Busy intervals only; no title, location, participant or source identifiers. |

### Personal event invitations

Invite eligible individuals without granting access to the entire calendar. Pending invitations reveal only permitted event fields. Accept/decline and RSVP are separate actions; revoke access on removal. Apply blocks and youth safeguards. Non-default shared calendar ownership transfer is proposed with dual confirmation; default calendar remains nontransferable.

## 05  /  Recurrence, time and conflicts

### Series lifecycle

Retain materialized occurrences and deterministic IDs initially. Extend recurrence rules with interval, selected weekdays, end date or count, exceptions and series extension. Keep series identity and occurrence identity stable when editing; support one, following and entire-series scopes, preserving completed records. Skip dates via exceptions; cancel occurrences without erasing attendance or payment history. Use a rolling generation horizon for long-running series, with idempotent jobs and bounded writes.

### Time model

Store UTC start/end instants and IANA event timezone. All-day events use local start date and exclusive end date; do not encode solely as UTC midnight. Show device-local or event-local time; tournament venue time must be explicit. Validate end after start for timed durations; define missing end as a point event. Preserve local wall-clock recurrence across DST; propose explicit resolution of ambiguous/nonexistent times with user confirmation where needed.

### Window semantics

Timed intervals overlap when start &lt; windowEnd and end &gt; windowStart. Point events use start within [windowStart, windowEnd). All-day events compare local date intervals. Paginate dense windows with stable timestamp + ID cursor; never silently truncate.

### Availability and conflicts

Warn privately for overlapping events without blocking acceptance. Only authorized busy intervals enter shared availability calculations; aggregate poll counts without revealing personal event details. Participants may submit explicit availability independently. Avoid small-group inference by limiting granular reporting. Travel-aware warnings are future scope; no location tracking required for basic conflict detection.

## 06  /  Participation and event operations

| Record | Proposed states and rules |
|---|---|
| RSVP | Going, maybe, cannot go, no response; intent only. |
| Registration | Requested, confirmed, waitlisted, canceled; eligibility and capacity enforced transactionally. |
| Attendance | Present, late, excused/unexcused absence, unrecorded; authorized staff corrections audited. |
| Payment | Not required, pending, paid, refunded; authoritative payment service only. |

### Capacity and waitlists

Apply shared registration capabilities to pickup, clinics, tryouts and eligible events. Check membership/guest policy, age, waiver, capacity and payment before confirmation. Use transactionally reserved slots, idempotency keys and expiring paid offers. Promote next eligible waitlisted participant; free events may auto-promote if enabled. Release expired reservations and reconcile late payment webhooks without overselling. Minimum attendance can trigger organizer review and cancellation, not automatic forfeiture.

### Event lifecycle

Draft → scheduled/provisional → confirmed → completed or canceled. Preserve cancellation reason, actor, time and version; remove from active participation views but retain authorized history. Notify affected users once per material change; coordinate refunds with Document 10. Reconfirm RSVPs after material changes when configured.

### Attendance and communication

Separate actual attendance from RSVP; private athlete/staff reporting, configurable denominator and excused-absence policy. Link event discussions and announcements to existing communication channels. Suggested reminders: practice 24h/1h; game 24h/2h; tournament 7d/24h/2h; meeting 15m. Defaults are proposals, subject to Document 12 preferences and quiet hours.

## 07  /  External and tournament integrations

### Calendar subscriptions

Keep individual ICS exports and free read-only subscription feeds at launch. Exports are snapshots; subscribed clients refresh on their own schedule, not guaranteed instantly. Support independent feed tokens with calendar, event-type and RSVP filters. Generate high-entropy credentials, store lookup hashes, redact URLs from logs, rate limit retrieval and support immediate revocation. Preserve stable ICS UIDs and appropriate update/cancellation semantics; verify client behavior. Never export notes or restricted location beyond caller permissions. Previously downloaded copies cannot be revoked.

### External imports and future sync

Post-launch: opt-in provider imports or busy-only access using least-privilege OAuth, encrypted refresh tokens, incremental sync and disconnect/delete controls. Imported events retain provider identity and source ownership. Future two-way sync only for eligible personal events, with version checks, loop prevention, deletion handling and explicit conflict resolution; team and tournament sources remain authoritative.

### Tournament integration

Aggregate tournament date ranges, confirmed game assignments, provisional slots, travel and related meetings. Display provisional assignments distinctly; update on bracket progression without duplicate events. Tournament module owns game assignments, results and venue changes. Use stable game IDs and authorized team membership; avoid exposing unpublished or youth-restricted schedules.

### Training and meetings

Reference scheduled workouts and LiveKit meetings without copying private workout logs or meeting credentials. Meeting access remains checked at join time. Link completion or recap workflows to Documents 03, 06 and 15.

## 08  /  Technical contracts and migration

### Source collections (existing paths)

users/{uid}/events/{eventId}; calendars/{calendarId}/events/{eventId}; teams/{teamId}/events/{eventId}; teams/{teamId}/publicEvents/{eventId}. Meeting and tournament sources retain their own module contracts.

### Proposed normalized projection

UnifiedEvent: sourceType, sourceId, sourceEventId, stable composite id, title, eventType, sportId, startsAt, endsAt, timeZone, allDay, localDates, location, visibility, status, seriesId, occurrenceId, registrationRequired, capacity, permissions, version. Projection is not a second writable source.

Under authoritative event paths, incrementally migrate RSVP, registration, attendance and waitlist records to subcollections; keep bounded counters and reconcile against records. Existing team RSVP/reaction/vote maps remain during migration. Use dual-read verification and server-controlled backfill before retiring old fields.

| Existing API surface | Operations |
|---|---|
| /v1/me/calendars; /v1/calendars/:id | List/create; patch/delete; invites and members. |
| /v1/me/calendar-events; /v1/calendars/:id/events | Window reads; event CRUD. |
| /v1/me/calendar-feed | Get/reset/disable subscription. |
| /v1/teams/:teamId/events | Create/edit/delete; RSVP, reaction, votes. |

### Proposed extensions

GET /v1/me/schedule and /schedule/conflicts; GET /v1/me/availability; POST /v1/availability-polls; PUT /v1/me/calendar-preferences; POST/DELETE /v1/me/calendar-feeds[/:feedId]; event-scoped registrations, attendance and cancellation; provider integration connect/disconnect. Reconcile naming with existing modules before coding.

## 09  /  Security, reliability and acceptance

| Risk / control | Acceptance criterion |
|---|---|
| Authorization and privacy | Nonmembers and pending invitees cannot retrieve private events; viewers never receive notes; busy-only responses omit identifying details; revocation blocks future reads and exports. |
| Public projections and youth | Restricted audiences and youth locations never leak through public views, search, notifications or feeds. |
| Concurrency | Concurrent registration cannot exceed capacity; repeated requests and payment callbacks do not duplicate reservations. |
| Recurrence | DST, leap dates, month-end, multi-weekday, exceptions and following edits pass shared Dart/TypeScript fixtures; completed attendance remains intact. |
| Aggregation | Same source event appears once; overlap queries include multi-day events; stable pagination handles equal timestamps. |
| Cancellation | One notification per affected participant per change; canceled record retained; paid cancellation routes to refund workflow. |
| External feeds | Revoked tokens fail; filtered feeds omit unauthorized data; stable UID and updates tested in supported clients. |
| Client parity | Flutter and web produce equivalent permissions, time calculations and event states; offline retries are idempotent. |

### Operational safeguards

Use bounded listeners and date windows, composite indexes, cursor pagination and server-side validation. Cache only permission-safe projections; invalidate on membership changes. Monitor query fanout, reads, write contention, feed fetch volume, failed reminders and job retries. Budget is platform-wide, not a dedicated calendar allocation; measure beta usage before adding paid providers. No live pricing verified.

## 10  /  Delivery plan and source references

### Proposed sequencing

Launch: harden existing calendars and recurrence; aggregate team/community/tournament/meeting sources; agenda/day/week/month; all-day and multi-day; preferences; private conflict warnings; capacity/waitlists and attendance; free scoped ICS feeds; cancellation and notifications. Post-launch: year/season, availability-only sharing and polls, advanced recurrence, personal event invitations if not ready at launch, external imports and training integration. Future: two-way sync, travel-aware conflicts, resource booking and scheduling optimization.

Free: core calendar, shared calendars, basic conflicts, RSVP, reminders, subscriptions and basic attendance. Premium: advanced scheduling automation, organization analytics, bulk scheduling and advanced reports. Exact limits/prices deferred to Document 11.

### Reviewed source references

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/calendar/service.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/calendar/routes.ts

https://github.com/brianrhonea/frisbee_app/blob/development/packages/shared/src/calendar.ts

https://github.com/brianrhonea/frisbee_app/blob/development/packages/shared/src/recurrence.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/hub/service.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/hub/routes.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/mobile/lib/data/services/device_calendar_service.dart

https://github.com/brianrhonea/frisbee_app/blob/development/apps/web/lib/calendar.ts

### Limitations

Selected development-branch source review only; no application execution, test run, complete rules audit, external provider verification or full parity validation. Proposed schema, endpoints, reminder defaults, migration and release sequence are engineering recommendations. No repository changes. Related documents: 01, 02, 04–06, 09–13, 15 and 17.
