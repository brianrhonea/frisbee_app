<!-- Converted from Stall10_03_Social_Feed_Engagement.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# Social Feed & Engagement

PRODUCT SPECIFICATION  /  DOCUMENT 03  /  VERSION 1.0

Approved product direction • Pre-launch • Ultimate-first, multi-sport ready

### Executive summary

Stall10 connects athletes, teams and communities through a social feed integrated with competition, training and events. Preserve the existing dashboard and chronological following experience while adding ranked discovery, granular audiences and private training records. Core social features remain free.

### Approved requirements (1–6)

| ID | Requirement |
|---|---|
| SF-01 | Chronological Following and ranked Explore feeds. |
| SF-02 | Retain the dashboard above the social feed. |
| SF-03 | Public, followers-only, selected team/community and only-me post audiences. |
| SF-04 | Add game recaps, results, achievements, recruitment, polls and highlights. |
| SF-05 | Generate suggested posts; require user approval before publishing. |
| SF-06 | Short native video and external video links, with limits. |

### Scope and status

Approved describes the target product, not shipped functionality. Existing means observed in selected development-branch source or architecture documentation. Proposed means an engineering choice or sequencing recommendation that remains subject to review.

## 01 / Requirements & baseline

| ID | Approved requirement |
|---|---|
| SF-07 | Private training logs, GPS, strength and sport-specific workouts. |
| SF-08 | Apple Health, Health Connect and other integrations after launch. |
| SF-09 | Bookmarks, mentions, hashtags, mute and hide controls. |
| SF-10 | Rank discovery by sport, location preferences, interests, relevance and recency. |
| SF-11 | Defer stories and dedicated short-video feeds. |
| SF-12 | Free core social features; premium analytics and expanded media limits. |

### Existing functionality

Architecture documentation describes HomeFeed merging followed athletes, joined teams, followed teams and followed tournament content, with live pages of 20 per source and older-page loading. Public browse offers recent public posts; signed-in browsing supports pagination. Team pages place pinned posts first. [1, 2]

PostEditor supports text, photos, links, workouts and shared events; PostService supports likes and one repost per user per original, with optional commentary. Comments support one level of replies. Existing documentation describes GPS run/ride recording, notifications, flood controls and cleanup triggers. [1, 3–5]

### Existing limits

Editor documentation specifies 5,000 text characters, four photos and five links. Interaction service describes a 20,000-user reaction/repost cap. Private posts cannot be reposted; self-reposts are refused. The documented comment view is capped at the newest 100. Native video is not supported by the reviewed personal-post editor. [1, 3, 4]

## 02 / Experience & content

### Home and Explore

Home retains upcoming events, team information and other dashboard modules above Following. Following orders eligible posts newest first, with a stable ID tie-breaker; deduplicate posts across sources. Explore ranks eligible public content and suggests relevant athletes, teams, communities and competitions. Provide a clear switch between feeds, loading, empty, offline and retry states.

On Flutter use existing view models and repositories; on Next.js use the same API contracts and responsive cards. Support keyboard navigation, accessible labels, captions and reduced-motion preferences. GPS capture remains device-dependent; manual workout entry should be available on web.

### Content and workflows

| Content | Target behavior |
|---|---|
| Text, photo, link, repost | Retain existing composer and interactions; validate attachments and original access. |
| Game recap / result | Reference canonical game or tournament result; show score and permitted statistics. |
| Achievement / recruitment | Reference profile or team; distinguish self-reported and verified claims. |
| Poll | Question, options, close time; enforce one vote per user unless explicitly configured otherwise. |
| Highlight | Short video or external link; show processing and failure states. |
| Workout / event | Reference permitted source record; never expose private event or route details. |

### Suggested activity sharing

After a game, workout, achievement or team milestone, offer a draft card. The user previews, edits, selects an audience and explicitly publishes. Dismissing a suggestion creates no public post. Source updates must not silently broaden access.

## 03 / Privacy & engagement

### Audience policy

| Audience | Eligible readers |
|---|---|
| Public | Visitors and members, subject to account privacy, youth safety and blocks. |
| Followers-only | Author and accepted followers. |
| Selected team/community | Author and authorized current members of selected entities. |
| Only me | Author only; no discovery or public share. |

Proposed rule: apply the most restrictive of account, post, source-object and youth policies. Private profiles cannot publish publicly. Reposts, previews, notifications, media URLs and cached pages must respect original visibility. Recheck membership and blocks on access; revoke stale cached access after privacy changes.

### Engagement

Keep likes, comments and reposts. Add private bookmarks, @mentions, normalized hashtags, mute and hide. Mentions notify only eligible recipients; hashtags index public eligible content only. Muting hides an account from personal feeds without unfollowing; hiding suppresses a single post. Blocking prevents interactions according to the platform-wide policy.

Provide report actions for posts, comments and media, with moderation queue, audit trail and appeal workflow coordinated with Document 13. Authors can remove their own content; post authors can remove comments as supported today. Preserve evidence only under a defined retention policy.

### Youth and location

Apply Document 02 minor-private defaults and additional restrictions. Do not expose precise location or routes by default. Use coarse, explicitly selected location preferences for discovery. Do not suggest public recruitment or unrestricted adult-to-minor interactions where youth policy forbids them.

## 04 / Training & media

### Private training records

Separate workouts from posts. A workout is private by default and can be saved without sharing. Support GPS running and cycling, manual duration and distance, strength exercises (sets, reps, weight), sport-specific drills and conditioning. Permit corrections to private records; published snapshots must be updated explicitly or removed.

Provide history, basic weekly summaries and optional sharing. Record units and timestamps consistently; distinguish recorded, imported and manual activity. GPS permission denial must allow manual entry. Route redaction should hide sensitive start/end points before any sharing.

### Integrations after launch

Plan Apple Health, Health Connect and additional providers only after launch. Request minimum scopes, explicit consent and revocation; deduplicate imports by provider and external ID. Do not publish imported health data automatically.

### Media pipeline

Use API-authorized signed uploads to Cloud Storage, with ownership, purpose, size and content-type checks. Process images/video asynchronously, strip unnecessary metadata, generate thumbnails and screen content. Publish only ready media; clean up failed and abandoned uploads. External links require safe URL validation and privacy-aware previews.

| Proposed launch defaults | Decision pending validation |
|---|---|
| Native video | 60 seconds, 50 MB input, one clip per post; tune after cost and device tests. |
| Playback | Compressed adaptive or standardized rendition; no autoplay on cellular by default. |
| Quota | Free basic media allowance; expanded premium limits. Exact quotas and pricing TBD. |

These numerical limits are proposed, not approved requirements. Existing team video storage is a separate feature.

## 05 / Architecture & data

### Target service flow

Flutter / Next.js → authenticated Fastify API → domain services → Firestore and Storage. Authorized direct Firestore listeners may remain for real-time reads. All application mutations go through API; signed media byte uploads are the controlled exception proposed in Document 01. Cloud Functions may handle trusted asynchronous counters, notifications and cleanup.

### Existing vs proposed storage

| Path / field | Status and purpose |
|---|---|
| posts/{postId} | Existing: author, kind, body, links, images, workout/event, private, timestamps. |
| posts/{postId}/comments/{id} | Existing: comments and one-level replies. |
| likedBy / repostedBy | Existing arrays; transactionally updated, bounded. |
| posts/{id}/likes/{uid} | Proposed: per-user engagement record; aggregate count. |
| posts/{id}/reposts/{uid} | Proposed: relationship to existing deterministic repost document. |
| users/{uid}/savedPosts/{id} | Proposed: private bookmark. |
| users/{uid}/hiddenPosts/{id} | Proposed: private suppression. |
| users/{uid}/mutedAccounts/{id} | Proposed: private account mute. |
| users/{uid}/workouts/{id} | Proposed: private canonical workout. |
| posts/{id}/votes/{uid} | Proposed: poll vote, with aggregate counts. |

Add audience type, authorized entity IDs, sport ID, canonical source reference and media processing state. Avoid duplicating sensitive fields in public documents. Use deterministic IDs and idempotency keys for retries; reconcile counters during migration. Proposed indexes: audience/createdAt/ID, author/createdAt/ID, sport/createdAt/ID and normalized hashtag/createdAt/ID; validate actual query shapes before deployment.

## 06 / API & scaling

### Existing API contracts [5]

| Method and path | Purpose |
|---|---|
| POST /v1/posts | Create post |
| PATCH / DELETE /v1/posts/:id | Edit or delete |
| PUT / DELETE /v1/posts/:id/like | Set or remove like |
| PUT / DELETE /v1/posts/:id/repost | Set or remove repost |
| GET /v1/posts/state | Batch interaction state |
| POST /v1/posts/:id/comments | Add comment or reply |
| PATCH / DELETE /v1/posts/:id/comments/:commentId | Edit or delete comment |
| PUT / DELETE …/comments/:commentId/like | Comment like |
| GET /v1/me/tag-tournaments | Eligible tournament choices |

### Proposed extensions (names provisional)

GET /v1/feed/following and /v1/feed/explore; PUT/DELETE /v1/posts/:id/bookmark and /hide; PUT/DELETE /v1/me/mutes/:uid; POST/GET /v1/me/workouts and PATCH/DELETE /v1/me/workouts/:id; PUT /v1/posts/:id/vote; POST /v1/posts/:id/report. Reuse existing endpoints where practical rather than duplicating contracts.

### Ranking and scale

Start with existing merged chronological feed and bounded public candidate queries. Rank Explore by sport match, coarse location preference, interests, relevance and recency; filter privacy and safety before scoring. Provide non-personalized fallback and avoid sensitive health data. Use stable cursor (timestamp, ID), bounded page sizes, listener disposal and cache invalidation. Move to selective materialization or hybrid fan-out only when measured read cost or latency warrants it. Monitor reads per session, active listeners, p95 latency, media bytes and error rates within the $50–$150 overall infrastructure budget.

## 07 / Security & acceptance

### Source-review findings (verify before release)

| Finding | Required verification / mitigation |
|---|---|
| Post state method lacks explicit visibility check | Authorize both repost and original before returning state. |
| Stored private flag | Test historical posts after profile privacy changes. |
| Comment likes | Reject missing parent posts; enforce block policy. |
| Best-effort photo cleanup | Retry orphan cleanup with ownership checks. |
| Request-supplied tournament tags | Resolve canonical IDs and names server-side. |
| Timestamp-only browse cursor | Test ties; migrate to stable composite cursor. |
| Reaction arrays | Load test contention; migrate with counter reconciliation. |

### Acceptance criteria

- A user cannot read, react to, share or fetch media for a post outside its audience; test anonymous, follower, blocked, former member and minor cases.
- Following returns eligible posts in stable chronological order without duplicates across pages; Explore excludes restricted posts before ranking.
- A suggested post is never published without confirmation; private workouts remain private unless explicitly shared.
- Repeated like, repost, vote and upload-finalize requests do not duplicate records or counts.
- Video limits, failed processing, cancellation and cleanup are enforced server-side.
- Flutter and web pass equivalent core workflows; emulator tests cover Firestore rules and API authorization; load tests record read cost and latency.

## 08 / Delivery & references

### Recommended sequencing

| Phase | Deliverables |
|---|---|
| Launch | Existing social parity, API-only writes, audience enforcement, chronological Following, basic ranked Explore, bookmarks/mute/hide, private training log, privacy-aware links and reporting. |
| Post-launch | Game/result and achievement cards, recruitment, polls, native video, hashtags and richer ranking; fitness integrations and premium analytics. |
| Future | Selective feed materialization, advanced media and deferred stories / dedicated short-video feed only if justified. |

Approved scope does not establish exact release dates. Core posting, following, engagement and basic training stay free. Premium analytics and expanded media limits are approved; pricing and entitlements belong in Document 11.

### Repository references

Branch: development. Base URL: https://github.com/brianrhonea/frisbee_app/blob/development/

[1] docs/ARCHITECTURE.md — feed, workout, notifications and storage overview.

[2] apps/api/src/browse/service.ts — public and member browsing.

[3] apps/api/src/posts/editor.ts — post/comment editing and media checks.

[4] apps/api/src/posts/service.ts — likes, reposts and state.

[5] apps/api/src/posts/routes.ts — registered endpoints.

[6] apps/api/src/posts/author.ts — author identity, privacy and mute checks.

[7] apps/api/src/browse/reposts.ts — original resolution and cursors.

### Review limitations

Based on selected source excerpts and the prior requirements assessment, not a full audit. The attempted home/service.ts lookup returned 404; HomeFeed details rely on architecture documentation. Tests, deployed configuration, actual usage and frontend parity were not verified. No repository files changed. Proposed schema, API names, quotas and rollout order require implementation validation.
