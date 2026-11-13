# Stall 10 API changelog

The API's version is `version` in `apps/api/package.json`. Bump it with
every change to the API (patch for fixes, minor for new endpoints or
behaviour, major once clients depend on a breaking change) and add an
entry here; `pnpm test` fails without one (`scripts/check-versions.mjs`).
The running version is in `GET /health` and in every response's
`x-stall10-api-version` header.

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
