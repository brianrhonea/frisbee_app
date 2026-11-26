# Security and database-cost review, November 2026

Reviewed on 2026-11-13 against `development` at `28ada48`. Nothing was
changed. Each finding gives where it is, what can go wrong or what it
costs, and a proposed fix. Pick the fixes you want and they'll go in as
separate changes, each with rules tests where the rules change.

Scope: `firebase/firestore.rules`, `firebase/storage.rules`, `apps/api`,
`firebase/functions` (`browse`, `api`, `notifications`, `follows`,
`account`, `meetings`, `discord`), `apps/mobile/lib/data`, `apps/web`
(`lib/live.ts`, `components/`), secrets in the tree and in git history.
No tests or emulators were run: everything below comes from reading the
code. Read and write counts are estimates from the code paths, not billing
data. Not covered: the app's view models were not checked for listeners
that re-subscribe on rebuild (the website's `lib/live.ts` hooks are keyed
correctly). The Cloud Functions other than those named above were only
skimmed for auth checks.

## Summary

| # | Severity | Finding |
|---|----------|---------|
| S1 | High | A private profile's posts, comments and post photos can be read by anyone signed in |
| S2 | High | A user's email address can become their public name |
| S3 | High | A spoofed `X-Forwarded-For` header gets around the per-visitor limit on public pages, and each spoofed request adds a new `limits` doc |
| S4 | Medium-high | Any free account can download the whole people directory, every post and every comment |
| S5 | Medium | App Check isn't enforced anywhere yet |
| S6 | Medium | A private school or club community's posts and events show on the public website |
| S7 | Medium | The roster endpoint shows any team's members to anyone signed in (needs a decision) |
| S8 | Medium | Storage uploads have no quota: anyone can fill the bucket |
| S9 | Medium | Signed-in API routes have no rate limit (invite-code guessing, invite spam, paging scrapes) |
| S10 | Low-medium | Players publish their own stats, and player rankings are built from them |
| S11–S18 | Low | Smaller gaps, listed below |
| C1 | High | Each chat message or post costs 3–4 operations per recipient in notification fan-out |
| C2 | High | Likes and reposts are arrays on the post, so every like rewrites the post and resends it to every open feed |
| C3 | High | `GET /v1/me/home` reads every follow, plus up to ~700 docs per load |
| C4 | Medium-high | The app's home feed listens to 50 posts for every 30 people followed |
| C5 | Medium | Roster: one profile read per member on every view; the community Teams tab loads the whole roster to show a list of team names |
| C6 | Medium | Public pages read up to 60 extra docs per request, plus one rate-limit read and write |
| C7 | Medium | `/v1/posts/state` reads every post in the feed a second time |
| C8 | Medium | Each public photo load runs Storage rules that cost 2–4 Firestore reads |
| C9 | Medium | Unbounded live queries on the website |
| C10–C15 | Low | Smaller costs, listed below |

Secrets: nothing to fix (see "Secrets" at the end).

---

## Security and user data

### S1 (High). A private profile's posts, comments and photos can be read by anyone signed in

> **Status 2026-11-17: phase A on `fix/private-posts`.** Single posts,
> comments, likes, reposts and photos follow the author's privacy (rules
> deployed to dev; API checks the same). Still open: `allow list` (phase
> B, `canListPost`) after functions:follows, the backfill and app 0.0.29.

- `firebase/firestore.rules:2170` `match /posts/{postId}`: `allow read: if signedIn();`
- `firebase/firestore.rules:2234` comments: `allow read: if signedIn();`
- `firebase/storage.rules:151` user post photos: `allow get: if request.auth != null || publicAuthor();`

Private profiles say only accepted followers see past the name, username
and photo. The website and API respect that (`publicPosts` filters out
private authors), but the database rules don't. Anyone with an account can
run `posts where authorId == <private uid>` through the Firebase SDK, using
the public web key, and read every post, workout (including the GPS route
in `workout.route`), comment and photo. The app's UI hides them, but that's
the only thing hiding them.

**Fix:**
1. Stamp a `private` flag on every post (the API writes it from the
   author's profile; the `follows` functions update the author's posts when
   their privacy changes, in batches of 500).
2. Rules: `allow list` only for queries filtered `where('private', '==', false)`
   (rules can check that a query is constrained). `allow get` when
   `!private || author == me || followsUser(authorId)`. Apply the same
   check to comments, through a `get` on the parent post.
3. Followed private authors appear in the home feed through `/v1/me/home`
   (API, already server-side) rather than a direct query.
4. Storage: user post photos follow the post (`firestore.get` the post's
   `private` flag; let the owner and followers through via the follows doc).

This also removes the per-request profile reads in C6.

### S2 (High). A user's email address can become their public name

- `apps/mobile/lib/domain/models/app_user.dart:36`: `label` falls back to
  `email` when there's no display name.
- The app writes `label` as the public name in many places:
  `profile_repository_firebase.dart:75,211,384` (`profiles/{uid}.name`,
  which is searchable, shown on `/v1/public/players/:uid` and on the
  website), `user_post_repository_firebase.dart:172,218` (`authorName` on
  public posts), `post_comment_repository_firebase.dart:44`, chat, DM
  `names`, `memberNames`, `invitedByName`, `requestedByName`.
- The API does the same through `callerLabel` (`apps/api/src/auth.ts`):
  `ProfileService.who` (`profiles/service.ts:49`) writes it to
  `profiles.name` **and** `keywords` (`:58`), which makes the email's
  words searchable. `MembershipService.label` (`membership.ts:98`) uses it
  for `memberNames` and for invite and join-request names.
  `posts/author.ts:24` already avoids it ("Never their email").

Email sign-up sets a display name, but only after the account is created
(`auth_service.dart:33-40`). Google and Apple sign-in can also arrive with
no name. Any profile, team or post write in that window, or by an account
that never set a name, may store the email address as the person's
public, searchable name. I didn't confirm that it has happened. The
read-only scan in the fix below would show it.

**Fix:** `label` falls back to `@username`, then "Player", never the email
(same in `callerLabel`). Run a one-off script to find `profiles`,
`posts.authorName` and `teams.memberNames` values that contain `@` and
rewrite them. Add a rules check that `profiles.name` doesn't match
`.*@.*\..*`. First, run the script read-only on dev and prod to see how
many accounts are affected.

### S3 (High, abuse and cost). A spoofed `X-Forwarded-For` gets around the public rate limit

- `apps/api/src/browse/model.ts:29` `clientIp` takes the **first**
  `X-Forwarded-For` entry. That entry is whatever the client sent. Google's
  front end appends the real address at the end.
- `apps/api/src/browse/routes.ts:36` passes the raw header, not `req.ip`,
  which `trustProxy: trustHops(1)` already resolves correctly.
- Same bug in the Cloud Functions: `firebase/functions/src/browse/model.ts:24`,
  `functions.ts:53`.

A scraper that sends a random `X-Forwarded-For` with each request gets a
fresh limit key every time, so there is no limit. Each request also costs
a rate-limit transaction (1 read and 1 write, plus 1 more read in the
functions' `admit`), creates a `limits/ip_*` doc that never expires, and
does the page's own reads (C6: up to ~60). 10 requests a second for a day
comes to about 50M reads and 1M stray `limits` docs.

**Fix:** use `req.ip` in the API and the last trusted hop in the
functions. Add an `expiresAt` field to `limits` docs and a TTL policy, as
`inviteCodes` already has. Move the visitor limit into memory (a
per-instance token bucket) so it costs no Firestore reads or writes. Cloud
Run's `maxInstances` bounds the total.

### S4 (Medium-high). Any free account can download the directory, posts and comments

> **Status 2026-11-17: step 2 merged (27c9f9c, web 0.39.1), rules
> deployed to dev.** List queries capped: `profiles` 50, `posts/*/comments` 100,
> `teamDirectory` 200; `followCounts` and `playerRankings` get-only. The
> `posts` cap (50) comes with S1 phase B: app 0.0.28 queries posts by id
> without a limit. Left open on purpose: `rankings`, `tournamentDirectory`
> (public, derived data). Still open: step 1 (App Check, S5), step 3, and
> `workout.route` in direct reads.

`allow read: if signedIn()` includes `list`, and nothing limits it, on:
`profiles` (`firestore.rules:2333`), `posts` (`:2170`), `posts/*/comments`
(`:2234`), `teamDirectory` (`:1955`), `tournamentDirectory` (`:1986`),
`followCounts`, `rankings`, `playerRankings`. The comments in `api.search`
and the `browse` functions say they're rate limited "so profiles can't be
scraped in bulk", but that limit only covers those endpoints. A script
using the public web key, signed in to a throwaway account, can page
through the whole `profiles` collection directly. Each profile includes
`keywords` and `tags`, and `teams` and `stats` on public profiles. Direct
reads also return fields the website deliberately removes: for example,
every workout post's GPS track (`workout.route`, up to 80 KB of encoded
path, `firestore.rules:2050`). `postView` drops that field for visitors,
but the rules give it to any account.

**Fix (in order of value):**
1. Turn on App Check enforcement for Firestore and Storage in the Firebase
   console (S5). This blocks simple scripts. On the web it relies on
   reCAPTCHA, which makes scraping harder but won't stop a scraper driving
   a real browser, so steps 2 and 3 still matter.
2. Split `allow get` from `allow list`, and cap list queries with
   `request.query.limit <= 50` on `profiles`, `posts`, `comments`,
   `teamDirectory`. Paging is still possible but slower and visible.
3. Longer term: search only through the API or callable (already rate
   limited per user), with `allow list: if false` on `profiles` except the
   `keywords` query the app needs.

### S5 (Medium). App Check isn't enforced yet

- API: `ENFORCE_APP_CHECK` comes from repo variables
  `API_ENFORCE_APP_CHECK_DEV/_PROD` (`.github/workflows/_deploy-api.yml:75`).
  `false` on dev. Prod isn't set up yet, so its value can't be checked from
  the repo.
- Callables: `firebase/functions/src/options.ts` reads `ENFORCE_APP_CHECK`
  from `functions/.env.<project>`, which isn't in the repo.
- Firestore and Storage enforcement is a console setting that the repo
  doesn't record.

Until it's on, every rule above is the only line of defence, and scripts
can do anything a signed-in user can. **Fix:** before prod launch, turn on
enforcement for Firestore, Storage, callables and the API (prod first,
once the App Store build sends tokens). Then add a line to `CLAUDE.md`
saying which are on. The `browse` callables and `/v1/public/*` stay open
by design (`config.public`).

### S6 (Medium). A private school or club community's posts and events show on the public website

- `apps/api/src/browse/model.ts:139` and
  `firebase/functions/src/browse/model.ts:134`:
  `isPrivateGroup = listing.kind === "community" && requiresApproval`.
- The rules (`firestore.rules:147`), Storage (`storage.rules:108`) and the
  roster service (`roster.ts:42`) treat `organization` the same way.

So an organization that approves who joins still has its public-marked
posts and upcoming public events served to signed-out visitors by
`/v1/public/teams/:id`, `/v1/public/events` and `browse-team`/`events`.
**Fix:** one line in both copies (`kind === "community" || kind ===
"organization"`), plus a test in `browse.model.test.ts`.

### S7 (Medium, needs a decision). The roster endpoint shows any team's members to anyone signed in

`GET /v1/teams/:id/roster` (`apps/api/src/teams/roster.ts`) returns names,
usernames, photos, tiers, custom role names, jersey numbers and positions
for any team that isn't a private group. `teamDirectory` is listable (S4),
so every team id is easy to find. The rules keep `teams/{id}` and
`roster/*` to members, so this is a deliberate widening (team hubs). Worth
confirming, especially for `level: youth` teams, where minors' names and
numbers become visible to any account.

**Options:** (a) keep it, (b) members only, plus a public card count, (c)
let each team choose a "public roster" setting, off by default for youth.

### S8 (Medium, cost and abuse). Storage uploads have no quota

`storage.rules` checks the size of each file but not the total:
- Chat attachments, 100 MB each (`:78`). Team videos, 500 MB each (`:128`).
  Anyone can create a team and become its owner. The 5 GB per-team cap is
  only in the app (`firestore.rules:1159`).
- DM attachments, 100 MB each (`:176`). Anyone can create a group
  conversation with only themselves in it (`firestore.rules:2535`).
- Post photos (`:144`) and profile images (`:163`) can be uploaded with no
  post, and old profile images are never deleted.

One script could upload terabytes. **Fix:** send all uploads through
`/v1/uploads` (it already issues signed URLs and checks the type), keep a
per-user and per-team byte total in Firestore and refuse past the quota,
and make the direct-write rules `false` for those paths once the app and
site use the API. Add a bucket lifecycle rule that deletes
`uploads/raw/**` after a day.

### S9 (Medium). Signed-in API routes have no rate limit

Only `/v1/public/*` calls the limiter. Some writes check the flood mute
(`checkNotMuted`) but nothing counts calls. Examples:
- `POST /v1/teams/join` (`membership.ts:143`): unlimited code guesses.
  Each 6-character code lives 45 s in a space of 32⁶ ≈ 1.07 billion, so
  guessing is unlikely to succeed, but every guess is a billed transaction
  read.
- `POST /v1/teams/:id/invites` (`membership.ts:236`): a team manager can
  invite any uid over and over. Each invite triggers a notification.
- `GET /v1/feed?before=` pages the whole `posts` collection. Roster,
  `/v1/me/home` and `/v1/posts/state` are expensive reads (C3, C5, C7).

**Fix:** an in-memory per-uid token bucket as a Fastify hook, with
tighter buckets for `join`, `invites` and `uploads`.

### S10 (Low-medium). Players publish their own stats, and player rankings are built from them

`profiles.stats`, `teams` and `games` are written by the player's own app
(`firestore.rules:2292`). The rule checks shapes but not values.
`firebase/functions/src/rankings/players.ts:1-4` builds
`playerRankings/all` from `profiles/{uid}.stats`, so anyone can put
themselves at the top. They can also list
themselves on any team in `profiles.teams`. **Fix:** compute the stats
summary in a function from `statsGames` the player is linked to (`roster`
`userId`), and have rules refuse client writes to `stats`, `games` and
`teams`.

### S11–S18 (Low)

- **S11:** `users/{uid}` root doc: the owner can write anything
  (`firestore.rules:221`), with no field list or size limit.
  `messagePolicy` can be any string; the rules treat unknown values like
  `everyone`. Fix: whitelist `messagePolicy`, `readReceipts` and the
  fields the app writes, with validation.
- **S12:** A private profile's main doc isn't enforced to be card-only.
  `validProfile` (`:2293`) allows `bio`, `teams`, `stats` and so on even
  when `private == true`, and relies on the app to move them to
  `private/details`. Fix: `!p.private || p.keys().hasOnly([card fields])`.
- **S13:** Browsing quickly mutes you everywhere. The browse limiter
  writes `mutedUntil` to the same `limits/{uid}` doc that `notMuted()`
  checks (`apps/api/src/limits/limiter.ts:27`), so a member who loads
  more than 120 public pages a minute can't chat or post for 10 minutes.
  Fix: a separate `browseMutedUntil` field (or in-memory limits, S3).
- **S14:** Username enumeration and password spraying.
  `usernames/{name}` is readable signed out (`:2403`), and
  `account-signInEmail` limits per username only
  (`account/functions.ts:50`). Fix: also limit per IP, using the real IP
  as in S3, and require App Check.
- **S15:** `GOOGLE_DESKTOP_CLIENT_SECRET` is set in both secrets files, so
  it's compiled into every iOS and Android build, although desktop builds
  were removed (`data/services/google_desktop_oauth.dart:20`). Fix: delete
  the desktop OAuth code and key, and rotate the client in Google Cloud.
- **S16:** Team post photos: a signed-in non-member can fetch a private
  group's public-post photo. The Storage `get` (`storage.rules:113`)
  allows `publicPost()` without the `showsPublic` check that Firestore
  has. Fix: `publicPost() && (isMember || !privateGroup)`.
- **S17:** Hosted tournaments with `visibility: 'inviteOnly'` are readable
  by anyone signed in once published (`firestore.rules:1562`). Confirm
  this is intended.
- **S18:** Download URLs carry a token that skips Storage rules. Profile
  images use them by design (`attachment_storage.dart:66`). If chat or DM
  attachments ever store download URLs, removed members keep access.
  Verify that chat and DM attachments stay path-based (they appear to,
  via `getDownloadURL` at read time, which rechecks the rules).

### What held up

- The API takes the caller from the ID token everywhere. No route reads a
  uid or author from the body. Zod schemas are strict and ids are checked
  (`docId`, `^[A-Za-z0-9_-]{1,128}$` for posts).
- The services I read against their rules match closely, each inside a
  transaction: `MembershipService`/`access.ts` (join, invite, community
  invites, remove, roles, ownership, links), `FollowService`,
  `PostService`/`PostEditor` (author-only edits and deletes, self-only
  likes), and `ProfileService.claimUsername` (format, reserved names,
  once per account, claim and profile written together). The
  community-invite path matches the new `teamInvites` rule. `media/` was
  only skimmed.
- CORS is an explicit allow-list with no credentials, and preflights are
  answered before auth.
- `/v1/public/*` and `browse` use allow-lists (`postView` drops GPS
  routes, profiles honour `visibility`, no emails), except for S6.
- Rules have no write path that lets a user give themselves a role or
  join without a code, invite or approval. Owner-only paths check
  `ownerId`. `memberPerms` is owner-written only.

---

## Database reads and writes (cost)

Rough counts are per action. R = room readers or team members, F = people
followed or followers.

### C1 (High). Notification fan-out per chat message, DM and post

`notifications/triggers.ts:69` (`chatMessage`), `:99`, `:314`
(`userPost`), with `deliver.ts:34-63`. For each recipient: 1 read of
notification prefs, a transaction on the collapsed feed entry (1 read and
1 write), and 1 `devices` list read when pushing. For each message: team
and room reads (2), plus the flood trigger's transaction (1 read and 1
write, `api/functions.ts:79`). On top of that, the client's create is
checked by `notMuted()` (`firestore.rules:17-20`), which reads
`limits/{uid}` with `exists` and `get` (about 2 reads).

- A message in a 30-member room comes to about **4 + 30×4 ≈ 125
  operations**. 1,000 messages a day is about 125k.
- A post by someone with 500 notifying followers comes to about 2,000
  operations.

**Fix:**
1. Keep device tokens on the prefs doc (`users/{uid}/settings/notifications`),
   so each recipient costs 1 read instead of 2–3.
2. For chat and DMs, skip the feed entry. Unread state already comes from
   the room or `dmReads`, so the transaction and write go away. Push only.
3. For large rooms, use an FCM topic per room (no per-recipient reads),
   with mutes applied on the client.

Together: roughly 125 → 30 operations per message, or ~4 with topics.

### C2 (High). Likes and reposts are arrays on the post doc

`firestore.rules:2153` (`likedBy`/`repostedBy`, up to 20,000 uids),
`apps/api/src/posts/service.ts:85`. Every like:
- rewrites the post doc, which can grow to hundreds of KB;
- sends the whole doc again to **every live listener** whose feed
  contains that post (the app's `_watchIn`, the web feed), at 1 read per
  listener per like;
- fires `postLiked` (`triggers.ts:334`) on every post update, including
  reposts and edits, and that reads the liker's profile.

A post with 200 likes, open in 300 feeds, costs about 60k reads in
re-deliveries. **Fix:** move likes to `posts/{id}/likes/{uid}` (1 write
each) and keep `likeCount`/`repostCount` on the post, updated by a trigger
or batched every few seconds. The caller's own like state comes from one
`get` (or from the API feed response, C7). The website and API already
expose counts only, so the public shape doesn't change.

### C3 (High). `GET /v1/me/home` on every dashboard load

`apps/api/src/me/service.ts:40`, `me/repository.ts:46-86`.
`Cache-Control: no-store`, and the whole thing runs again for every
`?before=` page.

| Read | Docs |
|---|---|
| profile + private details | 2 |
| `teams where memberIds array-contains` (≤30 full team docs) | ≤30 |
| `users/{uid}/follows where type == user` (**no limit**) | F |
| events, 5 per team | ≤150 |
| posts, 20 per chunk of 30 authors | ⌈F/30⌉×20 |
| repost originals, one `get` each | ≤20 |

For F = 300 that's about **700 reads per load**, of which 20 posts are
shown. **Fix:**
1. Keep the followed uids in one doc (`users/{uid}/private/following`,
   maintained by `followCount`): 1 read.
2. Split the dashboard (teams and events, cacheable for a minute) from
   the feed. Page the feed without reloading the dashboard.
3. Feed: query the newest N authors who posted recently, or a
   fan-out-on-write timeline (`users/{uid}/timeline`, written by the
   `userPost` trigger that already reads followers). Each page is then
   about 20 reads.

### C4 (Medium-high). The app's home feed listens to 50 posts per 30 people followed

`apps/mobile/lib/data/repositories/user_post/user_post_repository_firebase.dart:85-110`
(`_watchIn`, `limit: 50` per chunk). Following 300 people means
10 listeners × 50 = **500 reads per open**, and every like re-delivers
(C2). Fix: give each chunk `ceil(limit / chunks) + slack`, or read once
and page with `fetchPostsBefore`. Or use the timeline from C3.

### C5 (Medium). The roster reads one profile per member per view

`apps/api/src/teams/roster.ts:47-50, 88-90`: the team doc, `roster/*` (up
to `rosterMax` = 500), then one `get` per member and linked player. A
40-person team is about 80 reads per view, by any viewer, with no cache.
- `apps/web/components/team/CommunityTeams.tsx:28` calls the full roster
  only to read `teams` (a community's `linkedTeams`). For members, that
  map is already in the team doc that `TeamContext.tsx:54` holds live.
- The team hub reads `teams/{id}` live and the roster API reads it again
  (1 extra read per page; minor).

**Fix:** keep a short (30–60 s) in-memory cache of roster responses per
team on each API instance. Add `GET /v1/teams/:id/teams` (team doc only,
1 read) for the community Teams tab, or read `linkedTeams` from the live
doc when the viewer is a member. Note that `getAll` only saves round
trips, not billed reads.

### C6 (Medium). Public pages do extra reads on every request

`apps/api/src/browse/service.ts:51-58` (and the `browse` functions): 20
posts, then up to 40 profile reads to check privacy, then one `get` per
repost original, plus the rate-limit transaction (S3). That's about
60–80 operations per feed or profile view. `s-maxage=60` helps only if a
CDN caches the response.
**Fix:** the `private` flag on posts from S1 removes the profile reads.
Read repost originals with one `getAll`. Use the in-memory limiter from
S3. On the website, cache `/v1/public/feed` with `revalidate: 60` so each
region calls the API once a minute.

### C7 (Medium). `/v1/posts/state` reads the feed a second time

`apps/api/src/posts/service.ts:162`: up to 50 `get`s, plus each repost's
original (up to 100 reads), for posts the client just loaded from
`/v1/feed` or `/v1/me/home`. **Fix:** return `liked`, `reposted` and the
counts inside the feed responses. The API already has the docs (or, after
C2, read `likes/{uid}` for the page's posts with one `getAll`).

### C8 (Medium). Each public photo load costs Firestore reads

Visitors load photos through `firebasestorage.googleapis.com/...?alt=media`
(`apps/api/src/server.ts:96`), which runs `storage.rules` on every
request. That's `exists` and `get` on the profile (2 reads) for a user
post photo, and 3–4 for a team post photo. A feed page with 20 photos
costs 40–80 Firestore reads per visitor, with no CDN in front. **Fix:**
when the API finalizes an upload (`media/service.ts`), copy public photos
to a public path served with `Cache-Control: public, max-age=86400`
(Firebase Hosting or a bucket CDN), so rules aren't evaluated per view.
Or set `cacheControl` metadata on upload so repeat views come from the
browser cache.

### C9 (Medium). Unbounded live queries on the website

No `limit()` on:
- `components/team/TeamMore.tsx:93` plays, `:165` videos, `:203`
  `statsGames` (large docs, every game ever), `:271` all group
  tournaments for managers.
- `components/team/TeamSchedule.tsx:52`: past events, every one since the
  team started.
- `components/settings/FollowingSettings.tsx:35` (all follows) and
  `FollowRequests.tsx:23`.
- `components/MyTeams.tsx:36`: full team docs, including member maps,
  live. `/v1/me/home` reads the same teams again.

**Fix:** add limits and "Show more" buttons (as `Comments.tsx` and
`Notifications.tsx` already do). Read `statsGames` once with `getDocs`
instead of a listener.

### C10–C15 (Low)

- **C10:** The rate limiter's own cost. Each public request does 1 read
  and 1 write, and `limits/ip_*` docs pile up forever. Fixed by S3
  (in memory, plus TTL).
- **C11:** The team-name check reads up to 200 directory listings on
  every create and rename (`apps/api/src/teams/service.ts:61`,
  `membership.ts:131`), and the app runs the same check first. Fix:
  claim docs `teamNames/{kind}_{division}_{nameKey}`, so each check is 1
  read, written in the create transaction.
- **C12:** Deleting a team is a client-side cascade. The app reads every
  doc in every subcollection, then deletes them one by one
  (`team_repository_firebase.dart:789-902`). Billed deletes are the same
  either way, but `firestore.recursiveDelete` in a function saves the
  client reads and finishes if the phone goes offline. It would also let
  rules stop granting owners delete on every subcollection.
- **C13:** Duplicate implementations. Visitor reads exist twice: the
  `browse` callables (used by the Flutter web build,
  `browse_repository_functions.dart:38`) and the API's `/v1/public/*`,
  with `model.ts` copied between them. The community feed exists five
  times (app `_watchIn`, `/v1/feed`, `/v1/me/home`, `/v1/public/feed`,
  `browse-feed`). Once `apps/web` replaces the Firebase Hosting site,
  retire the `browse` group and the Flutter web browse screens, which
  also removes the duplicate S3 and S6 code. Every API route has at least
  one caller in `apps/mobile` or `apps/web`, so there are no dead routes.
- **C14:** `communities-sync` runs on every `teams/{id}` write (every
  join, role change and so on). Check that it returns before any reads
  when `orgId`, `orgLinked` and `linkedTeams` didn't change.
- **C15:** `userPost` notifications are the same per-recipient pattern as
  C1, so the C1 fix covers them.

---

## Secrets

- `git log -p --all` checked for the CLAUDE.md patterns
  (`AIza…`, private keys, `"private_key"`) and for common token formats
  (`sk_live`, `xox[bp]-`, `ghp_`, client secrets, LiveKit and Discord
  tokens): no matches.
- The secrets files, `GoogleService-Info*.plist`, `build/`,
  `firebase/build` and the debug logs at the repo root are all
  gitignored. The only tracked env or secret files are the four
  templates, which have empty values.
- `APP_CHECK_DEBUG_TOKEN` is empty in both local secrets files, so no
  debug token is compiled into builds. Keep it that way for prod builds
  (Codemagic's `SECRETS_LOCAL_JSON` can't be checked from here).
- The LiveKit and web API keys in the functions use `defineSecret`. The
  API uses ADC, with no key files.
- The only finding is S15: the desktop OAuth client secret is compiled
  into mobile builds.

## Suggested order

1. **S3 + C10** (real-IP limiter in memory, TTL on `limits`): small,
   stops the cheapest abuse.
2. **S6**: one line in two files.
3. **S2**: label fallback, plus a read-only scan of dev and prod for
   names containing `@`.
4. **S1 + C6**: `private` flag on posts, rules, Storage, backfill.
5. **S5**: App Check enforcement plan for prod launch.
6. **C1, C2, C3**: the large recurring costs.
7. The rest as time allows. S7 needs your decision first.
