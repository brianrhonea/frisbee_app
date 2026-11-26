# Phase-1 writes through the API (release-audit #17, Sprint 3 item 17-C)

**Status:** APPROVED by the owner on 2026-11-26 (Sprint 3 gate 17-C). Decisions D1–D11 in §12 were all taken as recommended.

**Estimates revised:**
- 17-W (website): about 1 h, a verification pass only.
- 17-B (app): about 12–15 h, including the `/v1/uploads` client and the outbox mapping.

**Baseline:** `feature/jan-4-release` at `0a012d4`.

**Builds on:**
- development-plan Q3: phase 1 is social, chat and events, plus roster. Phase 2 follows right after, with today's rules in between.
- S4, S6 and P0-02.
- release-audit #17, #18, #25, SEC-5, SEC-6 and B-B6.
- `account-gate.md` (approved as D14).

**Evidence tags:**
- **[V]:** verified in the code at the place cited.
- **[A]:** an assumption, or something not seen. QA or 17-A must confirm it before merge.

## 0. Summary

This is mostly a ratification of what exists, plus a short list of changes.

- **The website already writes through the API for every phase-1 write [V].** No direct Firestore writes exist in `apps/web`. Its uploads go through `/v1/uploads` (`apps/web/lib/upload.ts:68-111`). 17-W is therefore a check that the website's calls match this contract, with mirrored tests.
- **Almost every phase-1 write already has a `/v1` route [V]** (`apps/api/src/{posts,follows,hub,messages,stats,calendar}/routes.ts`). The app doesn't call most of them.
- **The main work is in the app (17-B).** The app writes Firestore and Storage directly, and it has no client for `/v1/uploads` [V].
- **17-A is a short list of changes** (§6).
- **[SHARED]** marks anything that changes a data shape or shared contract beyond adding routes. They are listed in §11.

## 1. Rules of the contract

1. **No new paths where a route exists.** §3 ratifies each existing route, body and behaviour.
2. **The account gate applies to every route below, unchanged** (`account-gate.md` §3).
   - It requires `email_verified`, `ageOk` and `terms >= termsVersion`; otherwise the write gets 403 `account_incomplete`.
   - **`ACCOUNT_GATE_MODE` must be `enforce` on the target environment before any client switch ships.** Otherwise moving writes behind the API would weaken the gate.
3. **The server is the author.** The API writes `authorId`, `authorName`, `authorPhotoUrl`, `private`, `createdAt` and `updatedAt`, and clients never send them (`posts/author.ts:30-41`). This closes SEC-5, and #18 for the API paths.
4. **Idempotency comes from a client-chosen document id**, not an `Idempotency-Key` header.
   - Create routes that accept an optional `id` use `tx.create`, so a replay gets 409 `already_exists`.
   - The outbox already treats `already_exists` as sent (`packages/shared/src/outbox.ts:50-52,64`).
   - PUT and DELETE routes are idempotent by nature.
5. **Authorization is decided on the server, from stored data.** Nothing in the body is trusted. Outsiders get `not_found` where the API already hides that a thing exists.
6. **Reads stay direct** (Firestore snapshots on both platforms). Only writes move.

## 2. Error codes

These are the existing `apiErrorCodes` (`packages/shared/src/api.ts:5-36`). The codes `blocked`, `muted`, `rate_limited` and `forbidden` do **not** exist. Clients show the `message` as written.

| Situation | Code (HTTP) |
|---|---|
| Missing email verification, birth date or Terms | `account_incomplete` (403), with `fields` |
| Not signed in, or the session was revoked | `unauthenticated` (401) |
| One of the two people blocked the other | `permission_denied` (403), "You can't do that: one of you blocked the other." |
| Muted for flooding | `resource_exhausted` (429); the message says how long |
| Suspended | `permission_denied` (403), `suspendedMessage` |
| A rate limit was hit | `resource_exhausted` (429) |
| A missing role or ownership | `permission_denied` (403) |
| Missing, deleted, or hidden from this caller | `not_found` (404) |
| A replay of an id that already exists | `already_exists` (409) |
| A state refusal (request still pending, private repost, series, poll, club age) | `failed_precondition` (412) |
| A bad body | `invalid_argument` (400), with `fields` |

## 3. Write inventory and contract

**Notation:**
- **App-direct** means the Flutter repository writes Firestore or Storage itself.
- **(S)** means the rules path becomes server-only in #25.
- Every route also falls under the any-write limit (120 a minute per caller, per instance) and the account gate.

### 3.1 User posts, reposts, likes and comments

| Write | Today | Route |
|---|---|---|
| Create a post (text, workout, shared event, photos) | App-direct `user_post_repository_firebase.dart:398-407`; website through the API | `POST /v1/posts` `{ id?, body, links, uploadIds, workout?, shareEvent?, tournament? }` → 201 `{ id, images }` |
| Edit a post | App-direct `:409-413` | `PATCH /v1/posts/:id` `{ body, links, keepImages?, uploadIds, tournament? }` → `{ id, images }`. The workout and shared event can't change |
| Delete a post | App-direct `:476-484` | `DELETE /v1/posts/:id` (204 even if it's already gone) |
| Like and unlike | App-direct `:430-436` | `PUT` / `DELETE /v1/posts/:id/like` → `{ liked, likeCount }` |
| Repost and undo | App-direct `:439-473` | `PUT` / `DELETE /v1/posts/:id/repost` `{ note? }` → `{ reposted, repostCount }`. The repost's id is `r_{original}_{uid}` |
| Comment: add, edit, like, delete | App-direct `post_comment_repository_firebase.dart:64-149` | `POST /v1/posts/:id/comments` `{ id?, body, replyTo? }` → 201 `{ id }`. Then `PATCH` and `DELETE .../comments/:commentId`, and `PUT` / `DELETE .../like` |

**Authorization:**
- Any complete account that isn't muted or suspended can create.
- Only the author edits or deletes a post.
- Liking and commenting need `canSeePost` and no block with the author.
- A repost must be of someone else's post, not of a repost, not private, and not across a block.
- Comments go on the original post, never on a repost.
- A comment can be deleted by its author or by the post's author, and edited only by its author.

**Validation:**
- Body up to 5,000 characters.
- Up to 5 links, 500 characters each.
- Up to 4 photos of 10 MB each, taken only from the caller's own finished `post` uploads.
- Comments up to 1,000 characters.

**Idempotency:**
- Post and comment creates take a client `id` (`[A-Za-z0-9_-]{1,128}`; the `r_` prefix is refused).
- Toggles are idempotent.

**Rate limits:** new per-route limits, from §6 A4.

**After #25:** posts and comments become (S).

### 3.2 Follows and follow requests

| Write | Today | Route |
|---|---|---|
| Follow a user, team or tournament (a private profile makes it a request) | App-direct `follow_repository_firebase.dart:54-88` | `PUT /v1/follows` `{ type, targetId, groupId?, notify }` → `{ key, status }` |
| Unfollow | App-direct `:66-67` | `DELETE /v1/follows/:key` |
| Turn notifications on or off | App-direct `:70-71` | `PATCH /v1/follows/:key` `{ notify }` |
| Cancel my request | App-direct `:91-92` | `DELETE /v1/follows/requests/:owner` |
| Accept a request | App-direct `:111-129` | `POST /v1/me/follow-requests/:uid/accept` |
| Decline a request | App-direct `:132-133` | `DELETE /v1/me/follow-requests/:uid` |
| Remove a follower | Website only | `DELETE /v1/me/followers/:uid` |

**Authorization:**
- You can't follow yourself.
- The caller must not be muted.
- Following a user checks for blocks.
- Accepting checks blocks again and writes the follow and removes the request in one transaction.
- The follow's name and photo come from the server's own copy of the target.

**Idempotency:** everything is idempotent except accept. A second accept gets `not_found`, which the client treats as done.

**After #25:** `users/{uid}/follows` and `profiles/{owner}/followRequests` become (S).

### 3.3 Team chat messages

| Write | Today | Route |
|---|---|---|
| Send | App-direct batch `chat_repository_firebase.dart:394-442`, through the outbox | `POST /v1/teams/:teamId/chats/:roomId/messages` `{ id?, text, uploadIds, replyTo? }` → 201 `{ id }` |
| React | App-direct `:445-456` | `PUT .../messages/:messageId/reaction` `{ emoji \| null }` |
| Delete | App-direct `:459-466` | `DELETE .../messages/:messageId` |
| Polls, event shares, pins, votes | Already through the API | Unchanged |

**Authorization:**
- The sender must be a team member who can read and write the room, and not muted.
- Someone who can't read the room gets `not_found`.
- A member who can read but not write gets `permission_denied`.
- Messages can be deleted by their author, or by the owner, a moderator or a chat manager.

**Validation:**
- Text up to 4,000 characters.
- Up to 10 attachments, from the caller's own finished `chat` uploads.
- `replyTo` is a message id. The server builds the quote, clipped to 200 characters.

**Idempotency:** a client `id` (`^[A-Za-z0-9]{1,40}$`). A replay gets 409.

**Rate limit:** the hub `chat` limit, 60 a minute.

**After #25:** messages become (S).

### 3.4 Direct messages and conversations

| Write | Today | Route |
|---|---|---|
| Open a 1:1 conversation | App-direct transaction with a fallback, `direct_message_repository_firebase.dart:194-223` | `POST /v1/conversations` `{ with }` → `{ id, status }` |
| Create a group | App-direct `:226-245` | `POST /v1/conversations/groups` → 201 `{ id, notAdded }` |
| Add members, remove or leave, rename | App-direct `:248-300` | `POST /:id/members`, `DELETE /:id/members/:uid`, `PATCH /:id` |
| Send | App-direct batch `:394-478`, through the outbox | `POST /v1/conversations/:id/messages` → 201 `{ id }` |
| React, delete a message | App-direct `:480-497` | `PUT` / `DELETE .../messages/:messageId[/reaction]` |
| Answer a request | App-direct `:323-340` | `PUT /:id/request` `{ accept }` |
| Mark read, with a receipt | App-direct `:500-515` | `POST /:id/read` |

**Authorization:**
- A 1:1 conversation needs no block in either direction, respects the other person's message policy, and the caller must not be muted.
- Adding someone to a group requires that they follow the person adding them, accept messages, and haven't blocked them.
- Only participants can read or write. Others get `not_found`.
- You can't send while a request to you is unanswered (`failed_precondition`).
- Only a group's creator can remove other members.

**Validation:**
- A group has at most 10 members and a name up to 60 characters.
- Messages follow the same limits as team chat.

**Idempotency:**
- Opening a 1:1 conversation uses a deterministic id.
- Sending uses a client `id`.
- Creating a group mints its id on the server, which §6 A2 fixes.

**Rate limits:** the existing `dm-write`, `dm-chat` and `dm-respond` limits, plus the per-route limits already on opening conversations and creating groups.

**After #25:** conversations and messages become (S).

### 3.5 Team events and RSVPs, personal and calendar events

| Write | Today | Route |
|---|---|---|
| Create a single event or a series | App-direct `event_repository_firebase.dart:110-156`, which also writes `publicEvents` | `POST /v1/teams/:teamId/events` → 201 `{ id }` |
| Edit (one, or `?scope=following`) | App-direct `:157-178` | `PATCH .../events/:eventId` |
| Delete (one, or `?scope=following`) | App-direct `:259-284` | `DELETE .../events/:eventId` |
| RSVP with a note | App-direct `:290-319` | `PUT .../events/:eventId/rsvp` `{ status \| null, note? }` |
| React, vote in a poll | App-direct `:322-348` | `PUT .../reaction` `{ reaction, on }`, `PUT .../votes` `{ optionIds }` |
| Personal and calendar events | App-direct `:365-415`; website through the API | `POST /v1/calendars/:id/events`, `PATCH`, `DELETE` ("My calendar" is the caller's uid) |

**Authorization:**
- Creating, editing and deleting team events need `manageEvents`.
- An RSVP needs a team member who can see the event.
- Reacting and voting need an RSVP of "going".
- Personal events belong to the caller. A shared calendar needs its owner, or someone with "can edit".

**Validation:**
- Title 1–100 characters.
- Notes up to 5,000 characters.
- Location up to 200 characters.
- RSVP note up to 140 characters.
- The end can't be before the start.
- A repeating event needs a `timeZone`.

**Idempotency:** creating an event mints its id on the server, which §6 A1 fixes. Everything else is idempotent.

**After #25:** `teams/{t}/events` and `publicEvents` become (S). `users/{uid}/events` depends on D5.

### 3.6 Roster

| Write | Today | Route |
|---|---|---|
| Create or save a spot, including whether they've paid | App-direct `team_repository_firebase.dart:1115-1123` | `POST /v1/teams/:teamId/roster-players` → 201 `{ id }`, `PUT .../roster-players/:playerId` |
| Link or unlink an account | App-direct `:1163-1167` | `PUT .../roster-players/:playerId/link` `{ userId \| null }` |
| Delete a spot and its status | App-direct `:1170-1176` | `DELETE .../roster-players/:playerId` |

**Authorization:**
- Create, edit and delete need `manageTeam`.
- When an admin links a spot, the account must belong to a current member.
- Any member may claim an unlinked spot for themselves, or release their own. That is today's rule, and approving claims (#28) is out of scope.

**Validation:**
- Name 1–80 characters.
- Number 0–99,999, or none.
- Position: `handler`, `cutter` or `hybrid`.

**Idempotency:** creating a spot mints its id on the server, which §6 A3 fixes.

**After #25:** `roster` and `rosterStatus` become (S). This breaks the app's `_moveLegacyStatus` migration (D7).

### 3.7 Team posts (`teams/{t}/posts`)

- **Today:** create, edit and delete are App-direct (`team_post_repository_firebase.dart:197,205,232`).
- **Route:** `POST /v1/teams/:teamId/posts` `{ id?, title, body, location, links, public, uploadIds, tournamentKey? }` → 201 `{ id }`, then `PATCH` and `DELETE`.
- **Comments and pins** on team posts already go through the API.
- **Idempotency:** a client `id`.
- **After #25:** (S).
- **Included in phase 1 if D1 is approved.**

## 4. The offline outbox

**How it works today:**
- There are five kinds of job: `directMessage`, `teamChat`, `userPost`, `teamPost` and `comment`.
- Each job's `id` is the id of the document it creates, so it is the same on every try.
- Jobs send oldest first, and a waiting job holds back the rest for the same chat or post. That keeps the order.
- A job is skipped if its document already exists.
- Error handling: 409 counts as sent; 5xx and 429 retry with back-off; no connection waits; anything else fails permanently.

**What the switch needs:**
1. **Every kind sends its job id as the `id`.** All five routes accept one, so replays are safe.
2. **Attachments go through `/v1/uploads` (new in the app):**
   1. create the upload (`post`, `teamImage` or `chat`, the target, and the job id as the item);
   2. upload the file to the signed URL;
   3. mark the upload complete;
   4. send the message with its `uploadIds`.

   The job saves its ready upload ids, so a replay doesn't upload the files again. [A] 17-A confirms what happens to uploads that never get attached.
3. **`account_incomplete`** is handled first by the API client (status check, token refresh, one retry). Only if that fails does the job fail permanently, with its message.
4. **Jobs queued by older builds must still send.** Their payloads are mapped to the new bodies:
   - comment: `parentId` becomes `replyTo`;
   - chat and DM: the `replyTo` object becomes its `.id`;
   - post: the editable fields are mapped to the request body.

   A job that can't be mapped is marked failed ("Couldn't be sent"), never dropped. New jobs carry a payload version.
5. **`createdAt`** is the server's receipt time, the same as the Firestore commit time today.
6. **Offline writes that aren't queued** (likes, RSVPs, follows, edits, deletes) fail with a retry instead of waiting for the Firestore SDK (D8).

## 5. Authorization summary

- **Account gate:** applied centrally to every write.
- **Blocks:** checked on post likes, reposts and comments, user follows and accepts, and DM opens, sends and group adds. Team chat and team events don't check blocks, which is today's behaviour.
- **Mutes and suspensions:** checked on creates only, matching the rules' `notMuted()`.

## 6. Changes for 17-A

These are all additions. Anything beyond them needs approval.

| # | Change | Shared change? |
|---|---|---|
| A1 | An optional `id` on `POST /v1/teams/:teamId/events`. Series occurrences become `{id}_{index}` | **[SHARED]** `saveTeamEventRequestSchema` |
| A2 | An optional `id` on `POST /v1/conversations/groups` (`g-` followed by letters and digits) | **[SHARED]** `createGroupRequestSchema` |
| A3 | An optional `id` on `POST /v1/teams/:teamId/roster-players` | **[SHARED]** `saveRosterPlayerSchema` |
| A4 | Per-route limits: `POST /v1/posts` 10 a minute and 200 a day; comments 30 a minute; reposts 20 a minute; `PUT /v1/follows` 30 a minute and 300 a day | No (configuration) |
| A5 | Tests for each route: authorized, unauthorized, blocked, muted, suspended, `account_incomplete`, rate-limited, replay (409) and a bad body. Replay and accept get emulator tests | No |

Replaying A1–A3 returns 409 `already_exists`, the same as the other create routes.

## 7. What stays direct

**Phase-1 data that stays direct by design (D6):**
- Read markers: `chatReads` and `dmReads`, including archive and clear.
- Typing indicators.
- The user's own preference documents.

**Chat rooms, folders and layout** are written directly by the app today, although routes exist. If they stay direct, they can't be locked in #25 (D6).

**Phase 2 stays direct at launch** (Q3): stats, playbook, videos, meetings, drafts, and saves for group and hosted tournaments.

**Storage uploads** made directly by the app are covered by D9.

## 8. Rollout order

Every step is a deploy the owner approves.

0. The #3a rollout is finished, with `ACCOUNT_GATE_MODE=enforce` and the account-gate rules deployed.
1. This contract is approved.
2. 17-A ships to dev.
3. 17-B ships in separate merges per area:
   1. social;
   2. chat and DMs, with the upload client;
   3. events;
   4. roster;
   5. team posts.

   No direct-write fallback ships. 17-W is a verification pass.
4. A TestFlight build with all the switches. Then raise `meta/flags.minBuild` **before** step 5.
5. #25, the rules lockdown (Sprint 4), with its deny matrix.
6. #18 still applies, but only to paths left direct.

**Rollback:** before #25, revert the client or the API. After #25, redeploy the previous rules, separately from the client changes.

## 9. Behaviour differences (no schema changes)

- **`authorName`:** this changes visibly. It no longer falls back to the email address; it uses the display name, then the profile name, then `@username`, then "Player".
- **Author and follow photos:** only trusted photos are used.
- **`private`:** derived on the server.
- **Reply quotes, attachment metadata and comment reply fields:** built by the server.
- **Event series:** occurrences are computed on the server from `repeat` and `timeZone`. [A] Needs a fixture test showing they match the app's.
- **Opening a DM:** the server decides whether it's a conversation or a request.
- **Blocked-word filter:** the server uses the shared `clean()`. [A] Confirm it matches the app's filter.

## 10. Tests

- **API:** the matrix in A5.
- **Rules (#25):** the deny matrix on every (S) path, after fixing the two known rules-test bugs.
- **App:**
  - outbox payload mapping, including old jobs;
  - upload then send, including a partial failure;
  - each repository's API call;
  - the error messages;
  - a device test: send offline, then turn airplane mode off.
- **Website:** mirrored tests for A1–A3.

## 11. Changes beyond adding routes

1. **[SHARED]** Optional `id` fields on three strict schemas (A1–A3).
2. **[SHARED, optional]** An `error.reason` field (D2b; not recommended).
3. **[SHARED, optional]** A new way for the outbox to classify `account_incomplete` (D3; not recommended).
4. New per-route rate limits.
5. A visible change: `authorName` no longer falls back to the email address.
6. A new app capability: the `/v1/uploads` client.
7. Old app builds must be retired with `minBuild` before #25.

## 12. Decisions for the owner

| # | Decision | Recommendation |
|---|---|---|
| D1 | Include team posts (§3.7) in phase 1 | Yes |
| D2 | Keep the existing error codes, or add `error.reason` | Keep them |
| D3 | `account_incomplete` in the outbox: let the job fail after the API client's retry, or hold it | Fail it after the retry |
| D4 | The per-route rate limits in A4 | Yes, and tune them later |
| D5 | Include personal and calendar events | Yes |
| D6 | Read markers, typing, archive and clear stay direct. Chat rooms, folders and layout move in phase 1 if there's time, otherwise they're a known gap | Yes |
| D7 | The roster legacy migration (`_moveLegacyStatus`) | Remove it, or run it once through the API |
| D8 | Offline likes, RSVPs, follows and edits fail with a retry in January, rather than being queued | Yes |
| D9 | Lock chat, DM and post photo uploads to server-signed uploads in #25 | Not for January; decide in Sprint 4 |
| D10 | No direct-write fallback and no new kill switch; the existing `use_api_*` flags are removed from these writes | Yes |
| D11 | Add the optional ids (A1–A3) | Yes |

## 13. Verified vs assumed

**Verified:**
- the routes and bodies;
- that the website makes no direct writes;
- the outbox rules;
- the rules line numbers;
- the error codes;
- the rate limits;
- that there is no `Idempotency-Key` header;
- that the app has no `/v1/uploads` client.

**Assumed, and must be checked:**
- the flood-mute trigger also counts posts written by the API;
- the post and attachment shapes match;
- the event series match;
- the blocked-word filters match;
- uploads that are never attached expire;
- the exact team-post permission;
- the error code that `checkNotBlocked` returns;
- whether the app has any UI to remove a follower.
