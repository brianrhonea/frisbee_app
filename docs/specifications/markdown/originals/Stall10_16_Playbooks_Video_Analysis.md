<!-- Converted from Stall10_16_Playbooks_Video_Analysis.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# Playbooks & Video Analysis

DOCUMENT 16  /  VERSION 1.0  /  25 NOVEMBER 2026

Approved product direction • Engineering specification • Pre-launch

### Purpose

Connect tactical instruction, team film, verified game statistics and athlete development in a sport-extensible coaching platform. Preserve existing ultimate playbook and video functionality while improving integrity, access control and media economics.

### Scope

Flutter mobile, Next.js web, Fastify API, Firestore, Cloud Storage and asynchronous media workers. Ultimate first; future sport modules share geometry, animation, resource permissions and film services. No UI mockups until Document 17.

### Release strategy

Prioritize secure native uploads, quota enforcement, revision-safe playbooks, manual game-video linking and free coaching assignments. Defer expensive automation and collaborative editing until core reliability and demand are established.

### Reading guide

02 Approved requirements; 03 Repository baseline; 04 Tactical engine; 05 Ownership and revisions; 06 Coaching; 07 Video library; 08 Media pipeline; 09 Economics; 10 Film analysis; 11 Statistics integration; 12 Collaboration and safety; 13 Data and API; 14 Delivery and tests; 15 Sources.

Status convention: approved = confirmed product direction; baseline = selected development-branch source evidence; proposed = implementation detail requiring validation. No repository changes or live tests performed.

## 02  Approved product requirements

| Decision | Approved direction |
|---|---|
| Ownership | Personal, team and authorized organization/community playbooks; independent copies, optional attribution. |
| Fields | Versioned standard ultimate, five-player, half-field and configurable layouts; extensible sport definitions. |
| Animation | Preserve existing animations; configurable timing, simultaneous movement, possession; branches later. |
| Organization | Folders, custom categories, tags, favorites, season archives and reusable templates. |
| Editing | Durable offline drafts, revision history, conflict protection; simultaneous editing later. |
| Public library | Private initially; opt-in moderated public templates post-launch. |
| Assignments | Free play/film assignments, acknowledgments, deadlines and discussion; premium advanced reports. |
| Sources | Native uploads and authorized YouTube playback; other providers later. |
| Quality | Standardized maximum 1080p/30 FPS; adaptive streaming and higher frame rates later. |
| Originals | Delete temporary originals after processing and safety checks; optional premium retention later. |
| Clips | Reference-based clips and collections; authorized native exports and rendered reels later. |
| Telestration | Free basic paused-frame drawings post-launch; advanced timed/moving annotations premium. |
| Statistics | Manual event links and start alignment initially; multiple anchors, suggestions and multi-camera later. |
| Collaboration | Expand synchronized playback, host controls, reconnection and discussion; advanced collaboration later. |
| Sharing | Private workspace footage, controlled sharing, restricted youth access, external privacy warnings. |
| AI | Future opt-in premium/usage-based analysis; human confirmation and additional youth safeguards. |

## 03  Repository baseline and gaps

| Source | Observed behavior / implication |
|---|---|
| shared/playbook.ts; playbook/service.ts | Normalized coordinates, elements, arrows, steps, whiteboards; team-scoped create/save/delete with manageTeam. Whole-document replacement lacks expected revision check. |
| web whiteboard_state.ts | Freehand drawing, geometry and undo. Existing cross-platform fixtures provide migration baseline. |
| shared/videos.ts; videos/service.ts | Team videos and folders, YouTube IDs, native files; 500 MiB per file and 5 GiB team quota described as app-enforced. Native upload integration incomplete. |
| videos/extras.ts | Member comments, timestamp notes and time-range clips; event tagging with audience checks; author/manager deletion. Timestamp ceiling 24 hours, not actual duration. |
| shared/media.ts; media/transcode.ts | MP4/H.264/AAC standard and poster generation; supported types differ from legacy video contract. Atomic job claiming and durable cleanup recommended. |
| mobile synced_video_player.dart | Existing synchronized player, native media_kit and mobile YouTube player; platform fallback requires parity review. |

### Priority gaps

Version field definitions, add revision checks and granular coaching permissions, unify uploads and quotas, validate duration, use durable job leases and cleanup, and connect canonical game IDs. Existing source is not proof of deployed behavior.

### Existing tactical limits

Name 100 characters; notes 5,000; 100 elements and arrows; 30 steps; 200 points per arrow; 48 waypoints per element per step; labels 20 characters; step notes 200; 100 drawings of 200 points. Web undo history 100 states. Retain compatible bounds and validate serialized size.

## 04  Sport-extensible tactical engine

### Geometry

Store normalized coordinates with immutable field definition ID, dimensions, unit, markings, orientation and ruleset version. Legacy ultimate field is 40 × 110 yards with 20-yard end zones; preserve this definition for migrated plays. Support seven-player, five-player, half-field and validated custom layouts. Future soccer pitches, basketball courts and volleyball courts use the same engine with sport-specific markings, roles and equipment.

### Movement and rendering

Retain legacy interpolation version; new plays calculate physical distance using field width and length. Support straight/curved paths, simultaneous movement, configurable step duration and delays, playback speed, pause/restart/step navigation, mirror/rotate view, freehand drawings, zones, labels and undo/redo. Possession is explicit: object holder, pass path, release and reception; validate references and timing. Conditional branches later.

### Organization

Folders with bounded nesting, custom categories, tags, favorites, pinned plays, season filters, archived seasons and templates. Ultimate presets: vertical/horizontal/side stack, initiation, continuation, resets, end zone, person/zone/transition defense, pull coverage, special situations and drills. Categories are configuration, not hardcoded universal enums.

### Whiteboard

Keep quick sketches distinct from formal animated plays. Save or convert to independent structured draft. Local whiteboards free; meeting-linked shared board and multi-user contributions later. Preserve existing drawing data and cross-platform rendering fixtures.

## 05  Ownership, permissions and revisions

| Scope | Access and lifecycle |
|---|---|
| Personal | Creator owns private drafts and plays; explicit copy into workspace. |
| Team | Authorized members view published resources; editors manage drafts; season archive preserves history. |
| Organization/community | Explicit linked-team or member audience; no automatic inherited access. |
| Public template | Post-launch opt-in publication, rights confirmation, moderation and independent copies. |

Copy creates a new resource ID with optional source attribution and no live dependency. A departing coach cannot take private team resources automatically. Archive by default; deletion follows retention, references and authorization policies.

### Granular permissions

Introduce playbook.view/create/edit/publish/assign/share/archive/delete/managePermissions and video.view/upload/edit/annotate/assign/share/delete, with custom team roles from Document 04. Check membership, audience, account restrictions and entitlement independently. Existing manageTeam maps to compatible editor privileges during migration.

### Revision workflow

Draft → validate → publish immutable revision → archive or revise. Persist local drafts in SQLite/IndexedDB, scoped to account/workspace; recover after restart. API compares expected revision transactionally; return conflict with current revision and preserve local work for merge or duplicate. Published revisions record author, timestamp, change note and schema version. One active editor recommended initially; simultaneous editing later. Revalidate offline access on reconnect; clear or quarantine revoked caches.

## 06  Coaching assignments and development

### Unified assignments

Assign plays, exact published revisions, videos, clips or collections to athletes, positional groups, lines or teams. Include deadline, instructions, optional event reference and discussion. Snapshot intended recipients; explicitly manage roster changes. States: assigned, in progress, acknowledged, submitted, reviewed, archived. Acknowledgment is self-confirmed review, not proof of understanding; playback progress is resume assistance only.

### Athlete feedback

Tag stable roster participant IDs, link relevant game events and plays, record strengths and development opportunities, and permit authorized athlete response. Integrate private evaluations from Document 15; never automatically publish coaching feedback to athlete profiles. Respect youth supervision and guardian consent from Document 13.

### Notifications and collaboration

Use Document 12 durable notifications for assignment, due reminder, changed revision, response and review; respect quiet hours and sensitive previews. Use Document 06 discussion and meeting references, not duplicated chat records. Basic assignments and completion tracking free; advanced reports, recurring programs and quizzes premium later.

### Historical integrity

Assignments reference a specific revision or asset version. If access is revoked or footage removed, preserve authorized completion metadata and mark resource unavailable. Do not expose deleted content through notifications or cached previews.

## 07  Video library and source policy

Store title, description, source/provider ID, sport, owner scope, season, competition, canonical game, calendar event, camera angle, recording date, duration, tags, processing state, visibility and rights confirmation. Existing eventId remains a migration anchor. Support folders, search and authorized sharing across explicitly linked workspaces.

| Source | Policy |
|---|---|
| Native | Private storage; resumable authorized upload; screening, standardized output and signed playback access. |
| YouTube | Store validated provider ID; authorized embed/playback. Public/unlisted references allowed with privacy warnings; no unauthorized downloading or rehosting. |
| Other providers | Post-launch provider adapter; verify terms, embedding and privacy capabilities. |
| Live streams / cameras | Future; independent authorization and cost review. |

Unlisted YouTube is not private Stall10 storage: anyone obtaining the link may view it. External provider availability, permissions and deletion are outside Stall10 control. Handle unavailable, restricted and removed videos gracefully. Recommend external links for long recordings only where rights and privacy permit.

### Format compatibility

Legacy video list includes AVI, WMV and MPEG in addition to MP4/MOV/MKV/WebM/3GP; shared media accepted list is narrower. Consolidate contracts around tested decoder support, MIME sniffing and explicit rejection; do not promise all legacy formats until verified.

## 08  Secure media processing

Authorize upload → reserve quota → resumable private temporary upload → validate actual bytes/type/duration → quarantine and screen → durable transcode job → validate output and safety approval → publish atomically → reconcile quota and clean temporary files. Do not publish pending or failed screening. Use bounded retries and human escalation per Document 13.

| Output property | Initial standard |
|---|---|
| Container / codecs | MP4, H.264 High Profile, AAC |
| Resolution / FPS | Longest edge ≤ 1920 px, no upscaling; max 30 FPS |
| Quality | CRF 23, video bitrate cap 5 Mbps, audio 128 kbps |
| Playback | Fast-start MP4; range requests where supported |
| Poster / metadata | JPEG poster max 480 px; strip sensitive metadata; verify implementation |

### Reliability

Atomic job claim with lease/fencing token, bounded worker concurrency, resource/time limits, retry backoff and dead-letter review. Idempotent output paths and publication; validate source ownership and checksum. Reconcile failed reservations and orphaned objects. Delete originals only after successful processing and required safety checks; preserve legal holds separately. Optional original retention later. Sandbox untrusted decoders and avoid arbitrary remote URL fetching.

### Future quality

Adaptive bitrate, 60 FPS and additional renditions only after measured playback demand and cost review. No 4K launch commitment. Both clients use same API lifecycle; direct storage upload only with scoped authorization, never direct metadata publication.

## 09  Storage, costs and monetization

| Scope | Free | Premium |
|---|---|---|
| Personal | 250 MB | 2 GB |
| Community | 1 GB | 5 GB |
| Team | 5 GB | 25 GB |
| Organization | — | 100 GB pooled |
| Per upload | 500 MB | 1 GB |

Document 11 proposed allowances; standardize decimal vs binary units before enforcement (legacy 500 MiB/5 GiB). Reserve original upload capacity, reconcile processed bytes and thumbnails; count temporary storage and exports in infrastructure cost. External references do not consume native media quota. Alerts at 75/90/100%; no automatic overage. Preserve core records and apply approved proposed 90-day excess-media transition after downgrade.

### Cost model

Illustrative decimal GB = (video Mbps + 0.128 audio Mbps) × seconds / 8,000. At 3 Mbps video, 60 minutes ≈ 1.41 GB; a 5 GB allowance holds about 3 such processed recordings, 25 GB about 17. Original upload limits still apply. 1,000 viewers × 60 minutes at 2 Mbps + audio ≈ 958 GB delivery. At illustrative $0.12/GB delivery and $0.02/GB-month for 250 GB storage, subtotal ≈ $120/month before processing, requests and other costs. Not verified provider rates.

### Entitlements

Free: play creation, whiteboard, basic revisions, organization, assignments, external references, notes, clips, manual game links and later basic paused-frame drawings. Premium: expanded storage, advanced reports/telestration, rendered reels, multi-camera and future AI allowances. Individual Plus $4.99, Community Pro $9.99, Team Pro $19.99, Organization Pro $49.99 monthly. Monitor storage, delivery, processing and contribution margin against initial $50–150 infrastructure budget. Entitlement never grants resource access.

## 10  Film annotations and clip collections

### Annotation model

Preserve existing comments, timestamp notes and clips as compatible records. Extend with athlete IDs, tactical tags, game event IDs, play/revision references, visibility and coaching feedback. Validate nonnegative start, end &gt; start, and known duration; unknown external duration marked unverified. Paginate rather than relying on existing 500-comment list ceiling. Existing comment body limit 1,000 characters.

### Telestration

Post-launch free paused-frame pen, arrow, circle, rectangle, line, shaded zone and text. Store normalized vector coordinates against video content rectangle, timestamp, orientation and asset version; never burn into source by default. Premium timed/moving annotations, keyframes and tracked objects later. Validate point counts, duration and bounds.

### Clip collections

Reference source asset and start/end, title, tags, author and ordering. Reuse across collections and assignments without copying media. Recheck source permission for every view; collection cannot widen access. If asset removed or replaced, mark clip unavailable or require explicit remapping. Authorized native exports and rendered reels later, with rights checks, quota reservations and durable jobs; no unauthorized external video exports.

### AI analysis

Future opt-in suggestions for highlights, chapters, transcription, tracking, formations and statistical events. Require authorized human confirmation before verified statistics change. Additional youth safeguards, processing consent, provider review, cost allowances and deletion controls. No launch dependency or accuracy guarantee.

## 11  Statistics-to-video synchronization

Document 15 canonical game identity owns matchup/result; team observations own detailed statistical events; calendar owns scheduling; video assets own footage. Link stable game and event IDs without changing statistics or verification. Multiple videos may reference one game; avoid duplicating game records.

### Initial synchronization

Manual event-to-video timestamp association and game-start alignment. Store explicit event ID, video ID, video position in integer milliseconds, author, source and version. A single offset maps elapsed game time to video position only for continuous recordings; label estimated links and allow manual correction. Use known duration bounds and distinguish wall-clock, elapsed game and video time.

### Later synchronization

Multiple anchors support drift and recording gaps; use piecewise mapping only within valid segments, never extrapolate across missing footage silently. Camera angle and independent anchor sets support multi-camera analysis. Automatic clip suggestions are derived, not verified events. Corrected statistics preserve stable event identity or mark superseded references; revalidate links after revisions.

| Example action (fictional) | Video position | Review range |
|---|---|---|
| Point begins | 02:10 | 02:10–02:25 |
| Block | 03:42 | 03:35–03:50 |
| Throwaway | 05:16 | 05:05–05:25 |
| Goal | 07:48 | 07:35–07:55 |

Coaches navigate from authorized statistics to footage and back; no public video exposure through a public result or leaderboard.

## 12  Collaborative review and safety

### Watch together

Expand existing synchronized player with host-authorized play/pause/seek, playback rate where supported, readiness, reconnect and discussion. Session state includes asset ID, host ID, sequence, playback position, server timestamp and status. Clients independently load authorized footage; estimate drift and correct within tested tolerances. Recheck membership on join/reconnect, expire sessions and transfer host explicitly. Meeting voice/video uses Document 06 and Document 11 allowances. Live annotations and consent-controlled recording later.

### Privacy and rights

Personal plays creator-only; team published plays and footage authorized members; drafts editors; feedback selected athletes and coaches; organization resources explicit audience. Youth footage restricted, no unrestricted public links or public athlete tagging. Require rights confirmation, reporting and copyright complaint process. Apply guardian consent, supervised communication and moderation from Document 13.

### Access revocation

Short-lived authorized native playback URLs; verify resource access before issuance and avoid persistent public download tokens. Revoke new access after membership change, purge authorized caches where possible; existing signed URLs may remain valid until expiry. Previously downloaded copies and external links cannot be recalled. Staff access least privilege, MFA and audited exceptional investigation. Quarantine unapproved media and do not expose via thumbnails or search.

## 13  Proposed data and API architecture

Flutter and Next.js → Fastify authoritative writes → tactical, film, coaching and media services → Firestore metadata, Cloud Storage, Cloud Run workers and external providers. Authorized real-time reads remain scoped. Extend existing team paths with compatibility adapters; do not duplicate authoritative records.

| Proposed collection | Core fields |
|---|---|
| sportFieldDefinitions/{id} | sportId, version, dimensions, unit, markings, ruleset |
| playbooks/{id}/plays/{id}/revisions/{id} | ownerScope, audience, fieldId, schemaVersion, status, revision, elements, paths, notes |
| videoAssets/{id} | ownerScope, source, providerId/path, durationMs, gameId, eventId, status, assetVersion |
| filmAnnotations/{id} | videoId, startMs, endMs, type, vectors, athleteIds, gameEventIds, playRevisionIds, audience |
| clipCollections/{id}/clips/{id} | assetId/version, range, order, title, tags |
| gameVideoLinks/{id}/anchors/{id} | gameId, videoId, eventId, elapsedMs, videoMs, syncVersion |
| coachingAssignments/{id}/responses/{id} | resourceRefs, recipients, dueAt, state, response, reviewer |
| filmReviewSessions/{id}; mediaUsage/{id} | host/state/sequence; reservedBytes, usedBytes, quotaVersion |

Use bounded subcollections, indexes and pagination; enforce ownership and audience on every reference. Proposed modules: shared tactical/core + sports/ultimate, film, coaching; API playbook/revisions, videos/annotations/collections/synchronization, coaching/assignments, media/quotas/screening/cleanup.

## 14  API, migration and acceptance

| Method | Proposed route family |
|---|---|
| GET | /v1/sports/:sportId/fields |
| POST / GET | /v1/playbooks; /v1/playbooks/:id |
| POST / PUT | /v1/playbooks/:id/plays; /v1/plays/:id/draft |
| POST / GET | /v1/plays/:id/publish; /v1/plays/:id/revisions |
| POST | /v1/videos/uploads; /v1/videos/uploads/:id/complete |
| GET / POST | /v1/videos/:id/playback; /v1/videos/:id/annotations |
| POST / PUT | /v1/games/:id/video-links; /v1/game-video-links/:id/anchors |
| POST / GET | /v1/coaching/assignments; /v1/me/coaching/assignments |
| POST | /v1/clip-collections; /v1/film-review/sessions |

### Migration

Inventory legacy plays and videos; backfill field/version and owner metadata idempotently; preserve IDs, timestamps, comments and event links. Compare legacy/new render fixtures. Introduce API quota reservations and disable legacy write bypass only after client compatibility. Reconcile actual storage, handle orphan files and verify private playback. Feature flags and rollback adapters preserve existing reads; never discard unsynced drafts.

### Acceptance gates

Test legacy geometry, cross-platform animation, field variations, offline restart, revision conflict, permissions and revoked access; upload quota races, resumability, quarantine, duplicate jobs, cleanup, duration bounds, clip references, game links and corrected events; youth restrictions, external playback failures, reconnect, downgrade and entitlement isolation. Test actual deployed rules and signed URL expiry before release.

## 15  Delivery sequence and source register

| Phase | Deliverables |
|---|---|
| Launch | Existing editor/whiteboard; versioned fields, organization, personal/team resources, drafts/revisions, permissions, secure video pipeline, quotas, notes/clips/collections, assignments, manual game links. |
| Post-launch | Organization/community shared libraries, public moderated templates, basic free telestration, expanded synchronized review, multiple anchors, advanced reports, exports/reels, adaptive streaming as justified. |
| Future | Collaborative editing, advanced moving annotations, multi-camera, additional sports, opt-in AI, optional original retention. |

### Repository references

Development branch, selected source review. Base URL: https://github.com/brianrhonea/frisbee_app/blob/development/

packages/shared/src/playbook.ts

packages/shared/src/videos.ts

packages/shared/src/media.ts

apps/api/src/playbook/service.ts

apps/api/src/videos/service.ts

apps/api/src/videos/extras.ts

apps/api/src/media/service.ts

apps/api/src/media/transcode.ts

apps/web/components/team/playbook/whiteboard_state.ts

apps/mobile/lib/ui/videos/widgets/synced_video_player.dart

packages/shared/fixtures/playbook (directory)

### Validation and dependencies

Documents 01–15 govern architecture, team roles, privacy, meetings, calendar, monetization, notifications, administration and statistics. No tests, FFmpeg jobs, deployed permissions or provider cost verification performed. Proposed endpoint names, schema, quota units, worker policies and release sequencing require engineering validation. UI mockups deferred to Document 17.
