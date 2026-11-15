# Stall 10 API changelog

The API's version is `version` in `apps/api/package.json`. Bump it with
every change to the API (patch for fixes, minor for new endpoints or
behaviour, major once clients depend on a breaking change) and add an
entry here; `pnpm test` fails without one (`scripts/check-versions.mjs`).
The running version is in `GET /health` and in every response's
`x-stall10-api-version` header.

## 0.20.1 — 2026-11-14

**Fixed** (security review of 0.14.0–0.19.0)
- League teams: a team already at a league team's id is kept only if the
  league made it (league, host and captain match); otherwise creating
  teams fails with 412. The rules now refuse client-made team ids that
  start with `league_`, and drafted-team ids can't start with it either.
  The `createLeagueTeams` callable has the same check.
- Deleting a stats tournament or a video folder, and reading group or
  hosted tournament games, query only ids or the fields needed
  (`DocQueries`), with no caps on how many there are.
- Hosted and group tournament operations check permission before reading
  games, entries or divisions; group `advance` refuses people not playing.
- Publishing a schedule is limited to 5 a minute and 50 a day, reconcile
  to 20 a minute, and failed draft picks and controls count toward the
  any-write limit.
- Group tournament listings must belong to the same group and tournament;
  delete removes only the tournament's own listing.
- Deleting a tournament removes every subcollection, however large,
  checking permission on each batch; removing a division deletes all its
  games.
- Stats games up to the 900 KB limit and hosted schedules up to 2,100
  games are accepted (per-route body limits).
- Playbook permission checks run inside the write transaction; failed
  video file deletes are logged.

## 0.20.0 — 2026-11-14

**Added**
- Meeting and voice channel tokens:
  `POST /v1/teams/:teamId/meetings/:meetingId/token` and
  `POST /v1/teams/:teamId/voice-rooms/:roomId/token`, ports of the
  `meetings-joinToken` and `meetings-voiceToken` callables (same checks,
  grants, messages and 6 h lifetime), 30 a minute per caller. They answer
  412 until `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` are
  set (see DEPLOY.md).
- Meetings (`/v1/teams/:teamId/meetings`): schedule, edit, cancel, RSVP,
  start and end; join requests (ask, take back, let in or turn away);
  watch together state (`playback/current`, 60 a minute); the call's chat.
  Each ports the `match /meetings` rules.

## 0.19.0 — 2026-11-14

**Added**
- Hosted tournaments and leagues (`/v1/tournaments`): create, edit,
  publish and delete events; status steps; divisions; seeds; team
  entries with the host's approval, invites and captains; publishing the
  schedule; captains report and confirm scores and the host sets final
  scores; seeding the bracket; and a host-only reconcile (bracket
  catch-up, going live, final places, withdrawn teams, captains).
- Every conjunct of the tournament rules is ported, with one test each;
  the scheduling engine is shared (`packages/shared/src/tournament_engine.ts`).

## 0.18.0 — 2026-11-14

**Added**
- Group tournaments (`/v1/teams/:teamId/group-tournaments`): create,
  save, publish (the server builds the schedule with the app's engine,
  ported to `packages/shared`), delete, report, confirm and set scores,
  seed the bracket from pool standings, and catch up bracket moves.
- Every conjunct of the `groupTournaments`, `games` and
  `tournamentDirectory` rules is ported; the tournament's public listing
  is kept in step.

## 0.17.0 — 2026-11-14

**Added**
- Team stats: create, save whole and delete stats games
  (`/v1/teams/:teamId/stats-games`) and stats tournaments
  (`.../stats-tournaments`); deleting a tournament deletes its games.
- Roster spots (`.../roster-players`): admins add, edit (with the paid
  mark) and remove them; members claim or let go of their own spot
  (`PUT .../roster-players/:id/link`).
- Every conjunct of the statsGames, statsTournaments, roster and
  rosterStatus rules is ported, with bounds on nested game shapes and
  size. Stats writes have their own limit of 90 a minute per member.

## 0.16.0 — 2026-11-14

**Added**
- Player signups: sign up, edit, sign back up, withdraw; the host's
  accept, waitlist and decline, and marking a player's fee paid
  (`/v1/tournaments/:id/signups/...`), ports of the signups and payments
  rules.
- Saving a division's drafted teams (`PUT .../divisions/:d/drafted-teams`):
  the division rule plus the app's pre-save checks.
- The captains' draft: start, pick, control (pause, resume, undo,
  autopick, cancel) and finish, ports of the `startDraft`, `draftPick`,
  `draftControl` and `finishDraft` callables; and creating a league's
  teams from its drafted teams, a port of `createLeagueTeams`. The app
  keeps the callables until it switches.
- Draft writes have their own buckets (picks and controls 240 a minute,
  signup decisions 120, other draft writes 30); picks and controls skip
  the 120-a-minute any-write count so a host can auto-pick a full draft.

## 0.15.0 — 2026-11-14

**Added**
- Team videos: `POST/PATCH/DELETE /v1/teams/:teamId/videos[/:videoId]`
  add YouTube videos, edit them, move them between folders and remove
  them (an uploaded video's file is deleted too, only from its own
  folder).
- Video folders: `POST/PATCH/DELETE /v1/teams/:teamId/video-folders[/:folderId]`;
  deleting a folder moves its videos to Unsorted first, as the app does.
- The `videos` and `videoFolders` rules are ported whole (`validVideo`,
  `validFile` on the resulting document), on the hub write limit.

## 0.14.1 — 2026-11-14

**Fixed** (security review of 0.11.0–0.13.0)
- `DELETE /v1/teams/:teamId` now checks everything the rule checks:
  `ownerId` must be the caller (a `members` entry of "owner" is no longer
  enough), the owner must be the only member (412 until the others are
  removed or it's handed over), and a team that plays in an unfinished
  league can't be deleted. Stored community and linked-team ids are
  checked before they're used in paths.
- Notification settings: at most 200 teams with their own settings (the
  rules' cap); resetting a team now really removes its settings (it used
  a merge, which kept the key).
- `PUT /v1/me/identity` refuses one upload for both pictures, and an
  unreadable old picture URL no longer fails the request after saving.
- Visitors' profile views only pass on pictures from Firebase Storage or
  Google, so a profile can't point visitors' browsers at another server.
- Chat folder ids refuse `.`, `..` and Firestore's reserved names; failed
  file clean-ups after deleting a team or room are logged.
- Test fakes: `merge` now merges nested maps as Firestore does.

## 0.14.0 — 2026-11-14

**Added**
- Team playbooks: `POST /v1/teams/:teamId/plays`, `PUT` and `DELETE
  /v1/teams/:teamId/plays/:playId` (`apps/api/src/playbook`), the plays
  rule ported. Members who manage the team save whole plays, checked by
  `savePlayRequestSchema` (pieces, arrows, steps, their limits, and steps
  only moving pieces on the field); `updatedBy` is the caller.

## 0.13.0 — 2026-11-14

**Added**
- `PUT /v1/conversations/:id/typing`: a participant marks or clears their
  typing (`conversations/{id}/typing/{uid}`, as the typing rule).
- `PUT /v1/me/read-receipts`: `users/{uid}.readReceipts`.

## 0.12.0 — 2026-11-14

Team admin for the website on its own.

**Added**
- Chat rooms and folders (`src/hub/rooms.ts`, ports of the `chats` and
  `chatFolders` rules, manageChats): `POST|PATCH|DELETE
  /v1/teams/:teamId/chat-rooms[/:roomId]`, `POST|PATCH|DELETE
  .../chat-folders[/:folderId]` and `PUT .../chat-layout` (order and
  folders). Access lists are capped as the rules cap them, writers must
  be readers, and single members must be on the team. A room's kind never
  changes; General can't be deleted; a deleted room takes its messages
  and files, and only someone who can read it may delete it. A deleted
  folder's rooms move out of it.
- `DELETE /v1/teams/:teamId`: the owner deletes a team, group or
  community, typing its name (checked here too). As the app's deleteTeam:
  `deletingAt` first, then every document under the team
  (`recursiveDelete`), its Storage folder, its directory listing and its
  tournaments' listings. It also leaves its community's list, and a
  deleted community's teams are freed.

## 0.11.0 — 2026-11-14

The member's own account, for the website on its own.

**Added**
- `PUT /v1/me/identity`: change your name, profile picture and header
  photo (`src/account`). The name and picture go on the Auth record (what
  the app reads), `users/{uid}` and the profile's directory fields with
  fresh search keywords; the header on the profile. Pictures are the
  caller's own finished `avatar` uploads, given a lasting download URL
  (`MediaStorage.downloadUrl`); replaced or removed ones are deleted, and
  only from the caller's own `users/{uid}/profile/` folder.
- Notification settings (`users/{uid}/settings/notifications`, as the
  app's NotificationPreferences): `PUT /v1/me/notification-settings/category`
  (a kind for every team, or a per-team kind for one team), `DELETE
  .../teams/:teamId` (back to the defaults), `PUT .../mute` (one team chat
  room or conversation; at most 500).
- Player profiles' card includes `headerUrl` (shown even when private, as
  in the app), here and in the `browse` functions.

## 0.10.0 — 2026-11-14

Website parity (`docs/product-spec.md` §8.1) and visitors limited to team
and community pages. Needs the `browse` functions from the same change
for the Flutter web site.

**Added**
- Team hub writes (`src/hub`), each re-checking its Firestore rule in a
  transaction, with zod schemas in `packages/shared/src/hub.ts`:
  - Team posts: `POST /v1/teams/:teamId/posts`, `PATCH|DELETE
    .../posts/:postId` (manageTeam; words or a photo, 5 links, 4 photos
    from the caller's `teamImage` uploads for this team and post).
  - Team events: `POST /v1/teams/:teamId/events`, `PATCH|DELETE
    .../events/:eventId` (manageEvents; validEvent, a community's
    audience, the `publicEvents` copy kept in step, votes reset when the
    poll changes; a hosted tournament's event keeps its link).
  - Answers: `PUT .../events/:eventId/rsvp`, `/reaction`, `/votes`
    (members who see the event change only their own entries; reactions
    and votes only while going; votes must be poll options).
  - Team chat: `POST /v1/teams/:teamId/chats/:roomId/messages` (members who
    may write in the room, not muted; attachments from the caller's
    `chat` uploads for this room and message; a reply's quote is copied
    from the room by the server), `PUT .../messages/:id/reaction` (one of
    the offered emoji, as the caller) and `DELETE .../messages/:id`
    (authors, the owner, and moderators or chat managers who can read the
    room).
- Direct and group messages (`src/messages`, schemas in
  `packages/shared/src/messages.ts`), porting the conversations rules:
  `POST /v1/conversations` (straight to their inbox if they follow you,
  else a request where their message policy allows one, else refused),
  `POST /v1/conversations/groups`, `PATCH /v1/conversations/:id` (rename),
  `POST|DELETE .../members` (only people who follow the adder and take
  messages, up to 10; leave, or the creator takes someone out),
  `POST .../messages` (with the inbox preview and the sender's read time;
  not while a request waits on the sender; attachments from `chat`
  uploads for this conversation and message), `PUT|DELETE
  .../messages/:id` (react; authors delete), `POST .../read` (their read
  time, and the shared receipt unless turned off or a request waits on
  them), `PUT .../request` (accept or decline), `PUT .../archive` and
  `POST .../clear`. Outsiders get 404 for every conversation.
- A per-member, per-instance write limit on those routes
  (`MemoryRateLimiter`: 30 posts/events, 60 messages and 120 answers a
  minute), a first step on security review S9.
- Author names on these writes never fall back to an email (review S2).

**Changed**
- `GET /v1/public/players/:uid`, `/v1/public/events` and
  `/v1/public/search` need a signed-in caller (401 otherwise, even with
  the website's server key) and App Check like other member routes, are
  limited per uid in memory (so heavy browsing can't trip the shared
  mute on chat and posts), and answer `cache-control: private, no-store`.
  The feed, posts and team pages stay open to visitors.
- Every signed-in write is rate limited per caller (120 a minute, in
  memory per instance; `src/limits/writes.ts`), with tighter limits on
  joining by code, invites, join requests, new teams, uploads and new
  conversations or groups (also a best-effort daily cap, reset when an
  instance restarts) (security review S9). `buildApp({ writeLimits: false })`
  turns them off for tests.

**Fixed**
- A school or club community that approves who joins is a private group
  on public pages, like a group: its posts and events no longer show to
  visitors (security review S6).
- Editing a community event without an `audience` keeps its audience
  instead of opening it to everyone.
- Deleting a team chat message as a non-member says only that the room
  isn't found, whether or not the message exists.

## 0.9.2 — 2026-11-14

**Fixed**
- Photo uploads on Cloud Run: `service.yaml` never set `STORAGE_BUCKET`,
  so `/v1/uploads` wasn't registered and the website said "No such
  endpoint." It's now `<project>.firebasestorage.app`. The bucket also
  needs CORS for the website (`deploy/storage-cors.dev.json` /
  `.prod.json`; DEPLOY.md).

## 0.9.1 — 2026-11-14

**Fixed**
- `WEB_SERVER_KEY` is trimmed when read, so a secret saved with a trailing
  newline still matches the website's copy. On dev the site refused every
  cache refresh (401 "Website revalidate refused") although both sides
  came from the same key.

## 0.9.0 — 2026-11-13

Live pages and instant refreshes for the website (fixes from the
two-person web test).

**Added**
- `GET /v1/players/:uid` (signed in, never cached): a player's page as the
  caller may see it. A private profile comes back in full, with its
  private details and posts, to the player and the people whose follow
  they accepted; anyone else gets `locked: true` and only the card
  (`MemberProfilePage` in `@stall10/shared`). Posts by private authors, or
  reposts of their posts, are left out unless the caller follows them.
- `GET /v1/posts/:id` (signed in, never cached): one post, if the caller
  may see it; 404 "This post was deleted." once it's gone.
- The website's cached public pages are expired the moment they change:
  after a profile's details, visibility, privacy or username change, and
  after a post is created, edited, deleted, reposted or a repost undone,
  the API calls the site's `POST /api/revalidate` with cache tags
  (`player:<uid>`, `post:<id>`, `posts`, `feed`, `search`;
  `web/revalidate.ts`). Awaited with a 1.5 s timeout (Cloud Run throttles
  CPU after the reply) and never fails the write. Needs `WEB_SITE_URL`
  (repository variable `API_WEB_SITE_URL_DEV/_PROD` on Cloud Run) and
  `WEB_SERVER_KEY`; without them pages refresh within a minute, as do
  changes the app still writes straight to Firestore (its stats summary).
- `MeRepository.profiles(ids)`.

## 0.8.0 — 2026-11-13

Core features on both apps.

**Added**
- `GET` / `PUT /v1/me/message-policy`: who can start a conversation with
  the caller (`everyone`, `followers`, `following`, `nobody`;
  `messagePolicyRequestSchema`). Stored in `users/{uid}.messagePolicy`,
  as the app already does; unset reads as `everyone`.
- `POST /v1/posts` takes an optional `workout` (`workoutSchema`: activity,
  whole minutes, distance, effort, up to 20 exercises; no GPS route),
  checked as `validWorkout` checks it and stored as `Workout.toMap` does.
  `PATCH` refuses to change a workout.
- Calendars, as in Outlook or Apple Calendar (requirements U11, D4;
  `calendar/`). `calendars/{id}` holds the owner, name, color, `members`
  (`{uid: owner|edit|view}`, mirrored in `memberIds`) and `pending`
  invites. "My calendar" has the owner's uid for id, is made the first
  time it's needed, and keeps its events in `users/{uid}/events`; others
  keep theirs in `calendars/{id}/events`.
  - `GET` / `POST /v1/me/calendars` (up to 20 owned), `PATCH` / `DELETE
    /v1/calendars/:id` (owner; My calendar can't be deleted; deleting
    takes its invites and events with it).
  - Invites: `POST /v1/calendars/:id/invites` (`{uid, role}`; also changes
    a pending invite's role; up to 50 people; not while muted), `DELETE
    /v1/calendars/:id/invites/:uid`. The invitee's copy is
    `users/{uid}/calendarInvites/{id}`; nothing is shared until `POST
    /v1/me/calendar-invites/:id/accept`, which checks the calendar still
    has them pending. `GET /v1/me/calendar-invites`, `.../decline`.
  - Members: `PATCH` / `DELETE /v1/calendars/:id/members/:uid` (Can view or
    Can edit; the owner removes people, anyone leaves).
  - Events: `GET /v1/me/calendar-events?from=&to=` (up to 92 days, every
    calendar the caller is on), `POST /v1/calendars/:id/events`, `GET` /
    `PATCH` / `DELETE /v1/calendars/:id/events/:eventId` (owner or Can
    edit; `calendarEventSchema` checks `validMine`, and My calendar's
    events are saved as the app saves them). Viewers never get notes.
  - Subscription feed: `GET` / `POST` / `DELETE /v1/me/calendar-feed` (a
    private link, reset or turned off) and `GET /v1/ical/:token.ics`
    (public; iCalendar of every calendar the link's owner is on, a month
    back and a year ahead; membership checked on each fetch; rate-limited
    per link; logged at warn only, since the path holds the token). Links
    are stored as a SHA-256 hash (`calendarFeeds`, `calendarFeedOwners`,
    both closed to clients). `PUBLIC_API_URL` sets the links' address.
  - `FirestoreCalendarRepository`: `memberIds` array-contains, `ownerId`
    and date-range queries (single-field indexes only).
- Empty `204` answers for calendar changes.

## 0.7.0 — 2026-11-13

Personal details at sign-up: legal name, birthday, phone, gender, mailing
address and, under 18, a parent or guardian. Only the player reaches them.

**Added**
- `GET /v1/me/personal/status` (`complete`, `required`: accounts made from
  `personalDetailsRequiredSince` on must give them first). Reads no
  ciphertext.
- `GET` / `PUT /v1/me/personal`: the caller's own details, replaced whole.
  Validated by `personalDetailsSchema` (`@stall10/shared`); under 13 is
  refused (`failed_precondition`) and nothing is saved; a guardian is
  required under 18 and dropped at 18 and over. Ages count on the date in
  UTC+14, so a birthday today anywhere counts. Responses are
  `private, no-store`.
- Stored in `personalDetails/{uid}` as one Cloud KMS ciphertext
  (`PERSONAL_DETAILS_KMS_KEY`), bound to the document's path; nothing is
  kept in the clear. Without a key the routes are off. `LocalCipher`
  (`PERSONAL_DETAILS_LOCAL_KEY`) works with the emulators only.
- `UserLookup` returns the account's creation time.

**Fixed**
- A profile write for an account with no display name no longer lists
  the account's email as its public name; the username (or "Player")
  stands in.

**Deploy**
- Create the KMS key and grant `api-runtime` Encrypter/Decrypter first
  (`DEPLOY.md`, step 4). Done for dev; not yet for prod.

## 0.6.0 — 2026-11-13

Communities and their teams.

**Added**
- `GET /v1/teams/:id/roster` also lists a community's teams (`teams`: id,
  name, division), sorted by name; a team's list is empty.
- `POST /v1/teams/:id/invites`: a community's member managers (Manage
  members there) may invite people to any team it has accepted and still
  lists, as well as the team's own. `firestore.rules` (`teamInvites`)
  allow the same for the direct path.

## 0.5.0 — 2026-11-12

Website parity, slice W2 (`docs/product-spec.md` §8.1): team pages.

**Added**
- `GET /v1/teams/:id/roster`: who's on a team, for anyone signed in, not
  only its members: the roster's players (name, number, position, and the
  linked member's public card) and the members (public card, tier and
  custom role names). Nothing else from the team doc (permissions, stats
  keepers, paid marks) goes out. A private group (a community or
  organization that approves joins) shows its members only to members.

## 0.4.0 — 2026-11-12

Website parity, slice W1 (`docs/product-spec.md` §8.1): what the website
needs to post, comment and follow. The app still writes these directly.

**Added**
- Posts: `POST /v1/posts` (a text post, with photos from the caller's
  finished `post` uploads for that post id), `PATCH /v1/posts/:id` (the
  author changes the words, links or photos; a repost only its note;
  dropped photos are deleted from Storage), `DELETE /v1/posts/:id` (with
  its photos; a repost also leaves the original's `repostedBy`). The posts
  rule's checks: 5,000 characters, 5 http(s) links, 4 photos, words or a
  photo, the author only, the flood mute.
- Comments: `POST /v1/posts/:id/comments` (replies one level deep, with
  `replyToName` when answering a reply; not on reposts), `PATCH` and
  `DELETE /v1/posts/:id/comments/:commentId` (its author edits; its author
  or the post's author deletes), `PUT|DELETE .../like`.
- Follows: `PUT /v1/follows` (players, teams, tournaments, with the
  target's own name and photo; a private profile gets a follow request),
  `PATCH|DELETE /v1/follows/:key`, `DELETE /v1/follows/requests/:owner`,
  `POST /v1/me/follow-requests/:uid/accept`,
  `DELETE /v1/me/follow-requests/:uid`, `DELETE /v1/me/followers/:uid`.
- Notifications: `POST /v1/me/notifications/read` and `/delete` by id.

## 0.3.0 — 2026-11-11

**Added**
- Likes and reposts (`PUT|DELETE /v1/posts/:id/like`,
  `PUT|DELETE /v1/posts/:id/repost` with an optional note), with the posts
  rule's checks: only the caller added or removed, 20,000 at most, no
  reposting your own post, the flood mute, and the repost
  (`r_{original}_{uid}`, the fields the app writes) and the original's
  `repostedBy` in one transaction. Liking or reposting a repost acts on its
  original, as in the app.
- `GET /v1/posts/state?ids=`: the caller's likes and reposts of up to 50
  posts, for the website's buttons.
- `GET /v1/feed?before=`: the community feed a page at a time, for members.

**Changed**
- Reposts carry their original (`original`, null once deleted) in the
  public reads and `/v1/me/home`.

## 0.2.0 — 2026-11-11

**Added**
- `GET /v1/me/home`: the signed-in member's dashboard. Their own profile
  (private details included, and `needsUsername` for new accounts), their
  teams with their role, upcoming events they may see (firestore.rules
  `sees(e)`), and a paged feed of their own posts and the people they follow.
- The version in `GET /health` and the `x-stall10-api-version` header.

**Changed**
- Uploads save processed files in the app's Storage folders (e.g.
  `users/{uid}/posts/{postId}/{uploadId}/{uploadId}.jpg`) instead of
  `media/{uid}/`, so `storage.rules` guard reads as before.
  `POST /v1/uploads` takes `itemId` (the post, video or message) for every
  purpose but `avatar`.
- `/v1/public/feed` and `/v1/public/players/:uid` return one page and no
  cursor: visitors see the newest posts; members page through their own
  feed.

## 0.1.0 — 2026-11-11

First version on the `monorepo` branch.
- Team creation (`POST /v1/teams`).
- Team membership and management, communities, invite codes; profiles and
  usernames; media uploads with server-side compression (step 5 of the
  migration; ARCHITECTURE.md §10).
- Public reads for the website (`/v1/public/*`).
- Cloud Run deployment: Dockerfile, CORS allow-list, Cloud Logging,
  readiness, graceful shutdown (`DEPLOY.md`).
