# Stall 10 API changelog

The API's version is `version` in `apps/api/package.json`. Bump it with
every change to the API (patch for fixes, minor for new endpoints or
behaviour, major once clients depend on a breaking change) and add an
entry here; `pnpm test` fails without one (`scripts/check-versions.mjs`).
The running version is in `GET /health` and in every response's
`x-stall10-api-version` header.

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
