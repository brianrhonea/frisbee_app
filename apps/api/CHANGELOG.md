# Stall 10 API changelog

The API's version is `version` in `apps/api/package.json`. Bump it with
every change to the API (patch for fixes, minor for new endpoints or
behaviour, major once clients depend on a breaking change) and add an
entry here; `pnpm test` fails without one (`scripts/check-versions.mjs`).
The running version is in `GET /health` and in every response's
`x-stall10-api-version` header.

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
