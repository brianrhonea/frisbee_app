<!-- Converted from Stall10_06_Messaging_Communication.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# 01  Messaging & Communication

Version 1.0  |  Approved product requirements  |  Pre-launch specification

### Executive summary

Stall10 communication connects athletes, teams, communities, organizations and tournament participants through a unified messaging hub and contextual entry points. The product combines private conversations, permission-controlled channels, drop-in voice and scheduled meetings with sports-native collaboration. Core messaging is free; premium capacity, recording and storage support sustainable operations.

### Architecture constraints

Retain Flutter and Next.js clients, Fastify on Cloud Run, Firebase Auth, Firestore live reads, FCM notifications, Cloud Storage and LiveKit. All application writes pass through the API; authorized real-time reads may use Firebase directly. Launch with ultimate, using sport-agnostic structures. Maintain practical web/mobile parity and a $50–$150 monthly infrastructure planning budget.

### Scope and dependencies

Documents 01–05 establish infrastructure, athlete privacy, social sharing, entity permissions and community participation. Documents 07, 09–13 and 16 define calendar, tournament, payments, subscriptions, notifications, safety and film details. Document 17 owns visual design; no UI mockups are included here.

### Evidence convention

Approved = user-confirmed product scope. Existing = supported by selected development-branch source or repository documentation, not proof of deployed behavior. Proposed = engineering recommendation requiring validation. No additional product requirements were supplied.

## 02  Approved requirements

| ID | Approved requirement |
|---|---|
| MC01 | Unified hub with contextual access from entities. |
| MC02 | Editing, replies, forwarding, mentions, pinning and mark as unread. |
| MC03 | Group creator, delegated administrators and configurable permissions. |
| MC04 | Text, voice, announcements, forums, event and tournament channels. |
| MC05 | Sport-specific and custom templates; Discord import. |
| MC06 | Interactive events, polls, profiles, playbooks, film, results and payment requests. |
| MC07 | Direct and group audio/video calls after launch. |
| MC08 | Short voice messages with storage limits. |
| MC09 | Premium recording with consent and retention controls. |
| MC10 | Authorized search by text, sender, date and attachment type. |
| MC11 | Configurable group history; permission-controlled team history. |
| MC12 | User deletion, edited indicators, time-limited moderation evidence. |
| MC13 | Encryption in transit and at rest, audited access; evaluate E2EE later. |
| MC14 | Free core messaging; premium meeting and storage allowances. |
| MC15 | Recording, transcription, summaries, breakout rooms and collaboration. |

Approval establishes feature scope, not specific numerical quotas, retention periods, prices or launch dates beyond MC07. Those remain engineering or policy decisions.

## 03  Repository baseline

| Area | Observed source behavior |
|---|---|
| Personal conversations [1,2] | Direct and group creation, requests, reactions, deletion, read state, typing, archive and per-user clear. Group additions check follow relationship, policy and block; creator removes others; any member can rename. |
| Channels [3,4] | Room/folder creation, editing, deletion and ordering; role/person access; General retained. Pins, event sharing, polls, votes and closure. |
| Meetings [5,6] | Create/edit/cancel, RSVP, start/end, lobby decisions, playback, chat and token issuance. Meeting and voice tokens use six-hour TTL. |
| Attachments [7,8] | Server upload reference and cleanup helpers; architecture documents compressed images and 10 MB chat files. |
| Client behavior [8] | Documented live recent pages and historical pagination, room mute, Discord template import, LiveKit voice, Android screen sharing and synchronized film review. |

### Gaps to validate

Message edit, forwarding, search, group admin roles, history controls, recording and direct calls were not established by the reviewed routes. Documentation may lag current code; do not treat absence from this review as proof of absence. Verify mobile and web implementations, Firestore rules, media access and actual deployment configuration.

### Migration principle

Extend current conversation, hub and meeting modules rather than replace them. Preserve existing IDs, message history and deep links. Retire legacy direct-write paths only after both clients and rules are verified.

## 04  Conversation and channel behavior

### Personal conversations

A sender opens a conversation through the API; recipient policy, blocks and youth restrictions determine whether it opens, becomes a request or is denied. Accepting a request enables normal messaging. Group invitations must respect recipient consent and eligibility. Proposed roles: creator assigns administrators and transfers ownership; admins manage members and pins; member invitation and rename permissions are configurable. Creator departure requires transfer or an explicit closure workflow.

### Message lifecycle

Client submits a stable message ID and validated content; API checks current membership, restrictions, history boundary and rate limits, then atomically creates the message and inbox preview. Retry returns the same result. Clients display pending, sent or failed state and reconcile against live reads. Edits are author-only and marked edited; replies reference an authorized original; forwarding must not bypass original audience or attachment permissions. Mentions notify only eligible recipients. Mark unread changes personal state, not another user’s receipt.

### Channel configuration

Text and voice rooms retain existing folders and read/write grants. Announcements are read-many/write-restricted presets; forum channels add topics and replies; event and tournament channels reference canonical entities. Staff channels are restricted presets. Templates contain roles, room types and access settings, never member identities or messages. Discord import previews changes, validates permissions and applies via API; repeated imports must not duplicate rooms.

### History and sharing

Group history policy may allow all history or messages after joining. Team channel history is permission-controlled; membership removal revokes future reads and attachment access. Shared sports objects resolve by ID under original authorization; payment requests open the verified checkout flow, never expose financial details in chat.

## 05  Voice, meetings and film collaboration

Retain LiveKit as the media plane; Firestore stores meeting metadata, invitations, chat and playback state. The API authorizes token issuance and controls room lifecycle. Voice rooms are drop-in; scheduled meetings support RSVP, lobby, host start/end and invited participants. Direct and group calls are explicitly post-launch.

### Proposed meeting workflow

Schedule → invite → RSVP → host starts → authorize lobby entry → issue scoped token → connect/reconnect → host ends → close room and finalize attendance. Host controls mute/removal, participant list and screen sharing where supported. Short-lived initial tokens, permission rechecks and provider-side participant removal are recommended; token expiry alone does not eject an active participant.

### Film collaboration

Retain documented synchronized playback: participants play the selected video locally, presenter state is stored in playback/current, heartbeat every 10 seconds and seek correction when drift exceeds 1.5 seconds. Validate these values under latency and reconnect. Extend with presenter handoff, timestamped notes, annotations, bookmarks, speed and frame controls; Document 16 owns detailed requirements. Enforce original video permissions.

### Recording and advanced features

Premium recording is opt-in, with clear participant notice and consent before capture; handle late joiners and consent withdrawal. Restrict playback/download, define retention and deletion, audit access. Transcription and summaries require separate disclosure and appropriate consent; breakout rooms inherit meeting access and must not expose private conversations. Defer advanced collaboration until core calls are reliable.

## 06  Data model and API contract

Proposed target paths (reconcile with existing schema before migration):

| Path | Purpose |
|---|---|
| conversations/{id}/messages/{mid} | Message, type, author, timestamps, reply reference, attachment IDs, deletion state |
| conversations/{id}/members/{uid} | Role, join time, history boundary, status |
| teams/{id}/chats/{rid}/messages/{mid} | Entity messages; existing room permissions retained |
| teams/{id}/chatFolders/{fid} | Folder order and access |
| teams/{id}/meetings/{mid} | Invites, requests, messages, playback/current, attendance |
| users/{uid}/conversationPreferences/{id} | Mute, archive, pin, read cursor, history cutoff |
| communicationReports/{id} | Restricted evidence, case status, expiry and audit |

### Existing routes [2–5]

POST /v1/conversations, /groups, /:id/messages, /:id/members, /:id/read, /:id/clear; PATCH /:id; PUT /:id/request, /typing, /archive and message reaction; DELETE member/message. Team chat room/folder CRUD and layout routes; meeting lifecycle, lobby, playback, chat and token routes; voice-room token route.

### Proposed extensions

Under /v1/conversations/:id: PATCH messages/:mid; GET search; PUT preferences, pin and members/:uid/role; POST ownership-transfer and calls; POST calls/:callId/token. Extend equivalent authorized entity-channel routes for edits, search and threads. Reuse existing moderation and media modules. Validate schemas with shared Zod contracts; enforce caller identity, idempotency and consistent errors (403/404, 409, 429).

## 07  Privacy, security and moderation

### Authorization and youth safety

Enforce access on API writes, Firestore reads, search results, attachment delivery and LiveKit tokens. Use current membership and history cutoff, not cached client claims. Apply Document 02 privacy and minor defaults; restrict unrelated adult-to-minor DMs, group invitations and private calls. Authorized youth team channels are not blanket permission for private contact. Document 13 defines detailed thresholds and escalation.

### Deletion and retention

Archive and clear are personal actions; deletion removes visible message content for recipients. Preserve only necessary restricted evidence for reports or legal holds, with documented expiry and audit access. Define retention periods before launch; do not retain all deleted content indefinitely. Remove orphan attachments with retryable cleanup and reconcile search indexes. Account deletion follows platform policy.

### Security controls

Use TLS and encryption at rest; restrict staff access and audit investigations. No E2EE claim at launch. Evaluate E2EE later against moderation, multi-device recovery and search needs. Apply distributed abuse controls as usage grows beyond per-instance limits. Check blocks in group interactions, not just direct messages. Validate upload ownership, purpose, size and file content; scan or quarantine risky files. Use short-lived authorized download access for private media.

### Moderation workflow

Report → capture minimum necessary evidence → restrict access → authorized review → action and audit → appeal/escalation where appropriate → expire evidence. Group admins moderate their space, not platform accounts. Revoking membership or banning a participant must also remove active media access and prevent reconnection.

## 08  Operating model and monetization

### Free versus premium

Free: direct/group messaging, channels, replies, reactions, search, permissions, basic voice and meetings, polls, sharing and all safety controls. Premium: expanded meeting capacity and participant-minutes, storage, recording and advanced collaboration. Team and organization allowances are shared; no per-athlete subscription is required to participate in an authorized meeting. Document 11 sets pricing.

### Proposed launch limits

10 MB per approved chat file or image before compression; voice notes up to five minutes; native short video up to 50 MB subject to Document 03 policy. These are recommendations, not confirmed limits across all clients. Upload directly to scoped storage, validate server-side, then attach finalized references. Do not proxy large media through Cloud Run.

### Illustrative usage model

| Metric | Example / calculation |
|---|---|
| Message delivery reads | 1,000 daily senders × 20 messages × 5 listener deliveries × 30 days = 3,000,000 reads. |
| Read cost assumption | $0.06 per 100,000 reads → $1.80 (30 × $0.06). Excludes all other usage and allowances. |
| Meeting participant-minutes | 25 teams × 4 meetings × 20 participants × 60 minutes = 120,000. |
| Illustrative media cost | 120,000 × $0.001 = $120 before plan, bandwidth, recording and allowances. |

Unit prices are hypothetical, not verified provider rates. Track reads, writes, listener reconnects, storage, egress, participant-minutes and recording separately. Set usage alerts and configurable quotas; do not disable text messaging when a video quota is reached. Limit listeners to active views and paginate history.

## 09  Delivery, acceptance and references

### Proposed delivery sequence

Launch: stabilize existing messaging, channels, voice, meetings and film; complete API-only writes, youth/privacy checks, editing/replies, mentions, templates, basic search and usage monitoring. Post-launch: direct/group calls, voice notes, forums, recording and richer search/collaboration. Future: transcription, summaries and breakout rooms. Priorities other than post-launch calls are proposed.

### Acceptance criteria

Retry send produces one message; concurrent sends preserve stable pagination; unauthorized user cannot read, search or download private content; blocked or ineligible invitations fail; history cutoff applies to queries and attachments; role removal revokes reads and active calls; edited/deleted content reconciles across devices; report evidence expires; recording cannot start without required consent; quotas reject excess media without blocking text; reconnect restores authorized state. Run API, rules emulator, mobile/web integration and load tests before release.

### Source references — development branch

[1] https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/messages/service.ts

[2] https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/messages/routes.ts

[3] https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/hub/rooms.ts

[4] https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/hub/chat_extras.ts

[5] https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/meetings/service.ts

[6] https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/meetings/livekit.ts

[7] https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/hub/uploads.ts

[8] https://github.com/brianrhonea/frisbee_app/blob/development/docs/ARCHITECTURE.md

Review limitations: selected source inspection only; no application execution, test runs, complete rules audit, production configuration verification or parity certification. No repository changes. Finalize retention periods, quotas, provider pricing and detailed youth policy before launch.
