# Backend audit: API, shared, Cloud Functions (read-only, `39c8a53`, API 0.48.0)

This audit only read code. Nothing was edited, run or deployed. Findings already covered by the readiness assessment, conflicts register or pentest (C-23, C-26, C-27, C-31, C-36, C-38, C-39/P7, P3–P5, P8–P10) aren't repeated here. **Verified fixed:** P1 (`firestore.rules:2504`, posts `list` now `capped(50) && canListPost`), P2 (`sharp ^0.35.5` in `apps/api/package.json`), P6 (`callerLabel` in `auth.ts` no longer falls back to email).

## Route inventory

**Method:** I counted `app|scope.get/post/put/patch/delete` registrations in `apps/api/src`. There are **267 across 35 files**. That includes `/health`, the Stripe webhook and the 2 scheduler job routes. `/ready` is a hook, not a route. Most modules register only when `deps.store` is set (`app.ts:205-277`).

**Auth model:** `registerAuth` (`auth.ts:62`) only fills in `req.caller`; it doesn't deny anything by default. Each handler has to call `requireCaller`/`caller(req…)` itself. I compared registrations with auth calls file by file:

- Every route has an auth call except the intended public ones: browse (6 of 9), the 3 `/v1/public/tournaments*` routes, `/v1/public/rankings`, the calendar `.ics` feed (token), the webhook (Stripe signature) and the jobs (Google OIDC, `payments/jobs.ts:25`).
- The apparent gaps in `posts/routes.ts`, `calendar/routes.ts` and `me/routes.ts` turned out to use `readCaller(...)`, which wraps `requireCaller`.

**Writes:** every write goes through `store.transact` (`store.ts:20-45`). No module writes outside a transaction. All ids go through `docIdParam`, and bodies through `parseBody`/`safeParse` with the zod schemas in `@stall10/shared`.

| Module (routes) | Authz pattern | Tx / idempotency | Depth |
|---|---|---|---|
| teams: membership 29, routes 3, share 4, deletion 1 | `can`/`isOwner`/`requirePermission` in `teams/access.ts`; club-age gate | 34 tx; join-by-code in tx | read |
| tournaments 20 + public 3 | `manages`/`managed`/`visible`/`captainOf`, re-checked inside the tx | 24 tx; server ids | read |
| payments 16 + jobs 2 | team `manageTeam`, `requireStaff`; host/payer from stored docs | 27 tx; Stripe idempotency keys; `stripeEvents/{id}` | webhook, settle, release read; refund/clawBack skimmed |
| calendar 20 | owner/edit/view roles (`calendar/service.ts:58-95`) | 16 tx; server ids | grep-level |
| meetings 15 | `can`/member checks (21) | 12 tx | grep-level |
| posts 14 | `checkSeesPost`, `refuseBlocked` | client id + `tx.create` (idempotent) | read |
| messages 13, hub 13 + rooms 7 + extras 10 | `canReadRoom`/`canWriteRoom`, participants | client message ids (idempotent) | read |
| stats 10, videos 9, group_tournaments 9, drafts 9, moderation 9, browse 9, follows 9, account 7, profiles 6 | per-module checks present | tx everywhere | grep-level (follows read) |
| personal 4, media 3, me 3, playbook 3, discord 2, tournament_chats 2, export 1, rankings 1 | self-scoped or `manageTeam` | — | grep-level |

## Bugs & incomplete workflows

| ID | Sev | Status | Where | Scenario |
|---|---|---|---|---|
| B-B1 | P1 | CONFIRMED | `firebase/functions/src/account/functions.ts:232-245, 302-318` vs `apps/api/src/teams/deletion.ts:44-80` | Account deletion's `deleteTeam` skips every safeguard the API enforces. Example: the sole owner of a team that hosts an unfinished tournament, holds Stall 10 money (`payoutAccounts/{team}.owedCents`, unreleased charges), plays in an unfinished league or is linked to a community deletes their account. The team tree is deleted anyway. The tournament keeps a `hostId` with no team behind it, so nobody passes `manages()` and nobody can run, edit or delete it. Charges and payout accounts are orphaned, the community's `linkedTeams` keeps a stale id, and `tournamentDirectory` listings stay. |
| B-B2 | P1 | CONFIRMED | `firebase/functions/package.json:12` | `npm test` names its test folders explicitly and leaves out `test/moderation`. No vitest config picks it up either. `photo_check.test.ts` and `word_filter.test.ts` never run, in the deploy workflow (`_deploy-backend.yml:84-89`) or anywhere else, and aren't among the 276 passing tests. They are the drift guards for the copied `safe_search.ts`/`word_filter.ts` (`moderation/safe_search.ts:1-2`). |
| B-B3 | P1 | CONFIRMED | `account/functions.ts:114-134, 232-252` | Account deletion leaves the person's identifiers behind (I grepped all of `functions/src`): their uid in other people's posts' `likedBy`/`repostedBy`; follow requests they sent (`profiles/{other}/followRequests/{uid}`, which hold name, username and photo); tournament `signups/{uid}`, entry `captainIds`, division `captains`, `tournaments/{t}/payments/{uid}`; `limits/{uid}`; `followCounts/user_{uid}`. `leaveTeams` also skips `orgMembers`, which the API's `removeMember` strips (`teams/access.ts:119`). Apart from `leaveCalendars`, the cascade has no emulator test. |
| B-B4 | P2 | CONFIRMED | `apps/api/src/export/service.ts:280-330` | "Download your data" leaves out: calendars they own or share and their events, hosted-tournament signups, entries and payments, `charges`/`paymentLog` rows where they're the payer, their notification feed, likes and reposts they gave, follow requests they sent, and uploads. This conflicts with the file's own promise of "everything Stall 10 keeps about the caller" (line 1). |
| B-B5 | P2 | CONFIRMED (drift) / SUSPECTED (broken images) | `apps/api/src/account/service.ts:83-127` | A rename or new photo updates only Auth, `users/{uid}` and `profiles/{uid}`. No trigger copies the change to `teams.memberNames`, post or comment `authorName`/`authorPhotoUrl`, `conversations.names`, follow docs or follow requests. `forget()` (line 121) then deletes the old photo, while old posts still serve the stored URL (`browse/model.ts:61`). |
| B-B6 | P2 | CONFIRMED | `teams/membership.ts:670`, `tournaments/service.ts:332`, `hub/service.ts:223`, `meetings/service.ts:144`, `calendar/service.ts:525`, `stats/service.ts:93`, `playbook/service.ts:57`, `videos/service.ts:100`, `group_tournaments/service.ts:250`, `hub/team_post_extras.ts:100`, `videos/extras.ts:68` | These creates generate the id on the server and take no idempotency key. A client that retries a POST after a timeout creates a duplicate team, event, meeting, game and so on. Posts, comments, DMs, chat messages and team posts already accept client ids. |
| B-B7 | P2 | SUSPECTED | `follows/functions.ts:20, 99, 115` | `commentCount` and `followCounts` are kept with `FieldValue.increment` in triggers, with no check on the event id. Firestore triggers are delivered at least once, so a redelivery double-counts, and no job ever corrects the counts. |
| B-B8 | P3 | CONFIRMED | `limits/writes.ts:16-34`; `tournaments/routes.ts:61` | `PUT /v1/tournaments/:id/schedule` (publish all divisions, 4 MB body) has no `routeWriteLimits` entry. The per-division publish is capped at 5 a minute and 50 a day, so the all-divisions route sidesteps that cap. Only the 120/min any-write limit and the 30/min hub limit apply. |
| B-B9 | P3 | CONFIRMED | `errors.ts:45-47` | Every Fastify 4xx (413 body too large, 415, …) comes back as `invalid_argument`/400, so clients can't tell "too large" apart from bad input. No internals leak: 5xx errors become a generic message. |
| B-B10 | P3 | SUSPECTED | `limits/memory.ts:19` | The limiter only sweeps above 50,000 keys. Daily-window keys live for 24 h, so once there are more than 50k live keys, every write does a full O(n) sweep. |
| B-B11 | P3 | CONFIRMED | `export/repository.ts:110-125`; `account/functions.ts:321-340` | Each export and each account deletion reads every approval group and every team that takes requests, platform-wide, to find one person's join requests. The cost grows with the platform, not with the user. |
| B-B12 | P3 | SUSPECTED | `notifications/triggers.ts:652, 714-718, 832` | `eventReminders` queries with no limit and runs sequentially within a 300 s timeout. Pruning removes at most 450 docs per collection per hour, so a backlog builds past about 10.8k a day. `entryDeadlineReminders` silently skips tournaments beyond `.limit(500)`. |
| B-B13 | P3 | SUSPECTED | `follows/service.ts:77-99` | Following a team or tournament checks no visibility. Anyone who has a private group's id, or the id of one of its tournaments, can follow it and get its name stored. |
| B-B14 | P3 | SUSPECTED | `payments/service.ts:515-541` | Two checkouts submitted at the same moment both see no open session and create two Stripe sessions. If both are paid, `settle` marks the second a duplicate and refunds it in full, so no money is lost, but the first link stays live. Payments are off at launch. |
| B-B15 | P3 | CONFIRMED | `teams/repository.ts:63-68` vs `account/functions.ts:302-318` | The two team-delete cascades differ. The API leaves `inviteCodes`, and the functions path leaves `tournamentDirectory` listings. Joining with an orphaned code is refused, so the impact is small. |

TODO/FIXME markers: none in `apps/api/src`, `firebase/functions/src`, `packages/shared/src` or the rules.

## Data integrity

- **Counters:** likes and reposts are derived from the `likedBy`/`repostedBy` arrays, so they can't drift. `commentCount` and `followCounts` are kept only by triggers. The app no longer writes them, but they can drift (B-B7).
- **Denormalized fields that can drift:** names and photos (B-B5), `memberNames`, `orgMembers`/`orgRoles` (mirrored by `communities.sync`), the `teams/{t}/tournamentEntries` and tournament events (`tournaments/functions.ts:34-127`, errors swallowed with `.catch(() => undefined)`), and the Captains' channel participants (capped).
- **Account deletion removes:** authored posts, comments and messages with their files, roster links, conversation names, team memberships (with hand-off to an heir), join requests, calendars, blocks, `users/{uid}`, usernames, profile, `personalDetails` and the user's Storage folder. **It leaves** what B-B3 lists, plus reports they filed and notifications about them in other people's feeds. Keeping some of this may be intended (reports, payment ledger rows for accounting). **Owner decision needed:** which of these to delete, anonymize or keep.
- **Export completeness:** see B-B4.

## Test coverage gaps

- **Count:** API 63 test files (13 `*.emulator`), shared 58, functions 24 (rules 5, server 4, notifications 5, tournaments 5, others 1–2 each). **CI** runs the API and shared tests plus the API emulator suite. Functions tests run only in the deploy workflow, without `test/moderation` (B-B2), `test:server` or `test:rules`.
- **Unauthorized cases:** these are string counts, so treat them as a heuristic. Files with no 401/403 assertions are follows, profiles, personal, data_export, public_*, me and home_feed. Follows and personal only act on the caller's own data, but none of these files checks that a stranger can't follow a private group (B-B13) or change someone else's follow request. Every module has a test file.
- **Missing:** an emulator test of the full `deleteAccount` cascade; a test that account deletion refuses, or safely hands off, a team that hosts events (B-B1); retried creates (B-B6); trigger redelivery for the counters (B-B7); a test pinning the write-limit keys to the registered routes (`write_limits.test.ts` has 4 tests).

## Tech debt

- **Largest files:** `payments/service.ts` 1,808 lines; `tournaments/service.ts` 1,485; `firestore.rules` 3,081; functions `notifications/model.ts` 1,184 and `triggers.ts` 886; shared `tournaments.ts` 1,068 and `stats.ts` 940.
- **Duplicated logic between the API and functions:**
  - Draft callables (`tournaments/draft.ts`: start, pick, control, finish) vs `apps/api/src/drafts`.
  - `createLeagueTeams` callable vs the API route.
  - `meetings.joinToken`/`voiceToken` vs the API token routes.
  - `browse.*` and `api.search` callables vs `/v1/public/*`.
  - Team deletion (B-B1/B-B15).
  - Hand copies of shared code (`word_filter`, `safe_search`, `mentions`, the rankings levels, `draft_model`), all unguarded once B-B2 is counted.
- **Shared-package drift:** functions are CommonJS and import `@stall10/shared` only in a few model files. Vitest is `^4` in functions vs `^5` in the API and shared.
- **Dependencies:**
  - `firebase-admin ^14.5.0` (both), `firebase-functions ^7.4.0`, `fastify ^5.12.0`, `zod ^4.6.0`, `stripe 23.1.0` pinned.
  - No deprecated FCM or functions calls: `deliver.ts:128` uses `sendEach`, and there's no `functions.config()` or v1 import.
  - `new Stripe(key, …)` (`stripe.ts:25`) doesn't pin `apiVersion`, so it relies on the SDK default and an SDK bump silently changes the API version.

## Suggested issues

| Title | Priority | Hours |
|---|---|---|
| Account deletion: apply the API's team-delete guards (hosted events, held money, league, community unhook), or refuse and ask the person to hand the team on (B-B1) | P1 | 6 |
| Run `test/moderation` in functions `npm test`; add a functions/rules job to CI (B-B2) | P1 | 2 |
| Account deletion: remove likes, reposts, sent follow requests, signups, captain entries, `limits`, `followCounts`, `orgMembers`; add an emulator test of the full cascade (B-B3) | P1 | 8 |
| Data export: add calendars, tournament signups and payments, notifications, likes and sent requests (B-B4) | P2 | 5 |
| Propagate renames and photo changes (trigger or lazy read), and keep old avatars until nothing references them (B-B5) | P2 | 6 |
| Client-supplied ids or an `Idempotency-Key` on the remaining create routes (B-B6) | P2 | 8 |
| Dedupe counter triggers by event id, plus a nightly recount job (B-B7) | P2 | 4 |
| Write limit for `PUT /tournaments/:id/schedule`; a test that every limit key matches a registered route (B-B8) | P3 | 1 |
| Error handler keeps 413/415/429 status codes (B-B9); time-bucketed limiter sweep (B-B10) | P3 | 2 |
| Indexed join-request lookup (`users/{uid}/joinRequests` mirror) for export and deletion (B-B11) | P3 | 4 |
| Paginate reminder queries and pruning; log truncation (B-B12) | P3 | 3 |
| Visibility check when following teams and tournaments (B-B13) | P3 | 1 |
| Pin the Stripe `apiVersion`; expire the superseded checkout session on concurrent submits (B-B14) | P3 | 2 |
| Retire the duplicate callables once the app calls the API only (C-23 follow-up) | P3 | 8 |
