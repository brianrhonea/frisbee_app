# Security review: Stall10 at 39c8a53 (read-only)

Scope: `firebase/firestore.rules`, `firebase/storage.rules`, `apps/api/src`, `firebase/functions/src` callables, and client link handling (`apps/mobile`, `apps/web`). **CONFIRMED** means confirmed by reading the code at file:line. **SUSPECTED** means it depends on runtime or configuration I could not see. I ran no tests, made no live requests and did not check the deployed rules. Nothing rises to Critical from the code alone.

## Findings

| ID | Sev | Status | Layer | Where | Issue | Fix |
|---|---|---|---|---|---|---|
| SEC-1 | High | CONFIRMED (absent) | API + rules | `messages/service.ts:107-121`; `firestore.rules` `allowedStart` (~2886); no `minor`/`adultAge` check outside `personal/service.ts:99` | Nothing restricts adult-to-minor contact. Accounts aged 13–17 default to `messagePolicy: everyone`, can be found in profile search and get DM requests from any account, including script-made ones. This breaks spec SP-04 and the youth release gate in doc 13 §05. | Decide the launch policy. If adult-only, enforce 18+ on the server (see SEC-2). If not, add a server-set age-band claim and block DM requests, group adds and discovery between adults and minors who aren't on a shared team. |
| SEC-2 | High | CONFIRMED | API + rules + functions | No `beforeUserCreated`; no birthday or `email_verified` check on any write path; `personal/service.ts:87-104` | **P4 is still open.** The 13+ (and any adult-only) gate exists only in the sign-up form. A REST sign-up with no birthday can post, message and join. The birthday can be rewritten at will (20 a day), so the club 16+ check is a self-declaration. The spec's verified-email requirement before posting or messaging (doc 13 §03) is also absent. | Add a blocking function or API step that sets an `ageOk` claim only after a valid birthday, and require it plus `email_verified` in the rules (`notMuted()` is a natural place) and in `requireCaller`. Lock the birthday once set, with changes through support. Enforce App Check. |
| SEC-3 | High | CONFIRMED | API | `server.ts:72` (`verifyIdToken` without `checkRevoked`); `moderation/service.ts:312`; `payments/service.ts:201-203` | `staff` is one boolean claim with no MFA, no scopes and no append-only audit log (C-27). Revoked or suspended tokens, or a removed `staff` claim, keep working for up to an hour. A phished staff session can suspend users, remove content and release payouts. | `verifyIdToken(token, true)` on `/v1/staff/*` and money routes. Require MFA (`firebase.sign_in_second_factor`) and a recent `auth_time` for staff actions. Add scoped claims and an append-only `staffAudit` collection. |
| SEC-4 | Medium | CONFIRMED | rules | `firestore.rules:641-648` (`editDetails` allows `level`) | The club 16+ rule can be bypassed. Anyone creates a non-club team, takes in under-16s by code or invite, then sets `level: 'club'` with a direct write. The owner is never age-checked. `club_age.ts:7` accepts that changing the level "removes no one". | Drop `level` from client `editDetails`. Change level only through the API, which re-checks every member, or refuse while any member is under 16. |
| SEC-5 | Medium | CONFIRMED | rules + client | `firestore.rules:227-235, 1274, 1330, 1645, 2516, 2583, 2995`, `addsOnly` memberNames; rendered at `message_thread_view.dart:535` | Display names are spoofable. `authorName`, `replyTo.{authorId,authorName,text}`, `memberNames[uid]` and `invitedByName` are free text up to 80 characters, and the app shows them as written. A member can post as "Coach Dana" or forge a quote. This matters most in youth team chats. The P6 fix covers only API writes. | In the rules, tie `authorName` to `team.memberNames[uid()]` or `conversation.names[uid()]`, and check `replyTo` against `get()` of the quoted message. Or render names from the member map, not the message. |
| SEC-6 | Medium | CONFIRMED | storage | `storage.rules:126-135, 163-171, 206-220` | **P3 is partly open.** The type allow-list is fixed, but direct uploads still have no per-user count or byte quota (S8). DM files only check that the uid is in `convId`, not that the conversation exists, is accepted or is unblocked. Team videos take 500 MB each with no limit on how many. | Route uploads through `/v1/uploads` and set direct `create` to `false`, or at least require that the conversation exists, isn't a pending request and isn't blocked. Add a budget alert. |
| SEC-7 | Medium | CONFIRMED | rules + API | `firestore.rules:408-420`; `teams/membership.ts:263-281` | Team and group invites ignore blocks and mutes on both layers. A blocked or muted user who manages any team can keep sending invites (and the notifications they trigger) to the person who blocked them. | Add `!blockedWith(userId) && notMuted()` to the rule, and `checkNotBlocked` and `checkNotMuted` to `invite()`. |
| SEC-8 | Medium | CONFIRMED | rules + functions | `profiles` rule (2637-2709), `rankings/players.ts:88`; roster self-claim `firestore.rules:964-971` | **P7 is open.** Players write their own `stats`, which feed `playerRankings`. Any member can also link themselves to any unlinked roster spot and claim that spot's stats. | Compute profile stats on the server from `statsGames`, and require admin approval to claim a roster spot. |
| SEC-9 | Low | CONFIRMED | rules | `firestore.rules:2696` | Profiles can be listed 50 at a time and paged without limit, which sidesteps the rate-limited `search` callable. That allows bulk scraping of names, photos and usernames, including minors'. | Make `list` require a `keywords array-contains` filter, or move search fully to the callable or API and deny `list`. |
| SEC-10 | Low | CONFIRMED | rules | `firestore.rules:1820-1828, 1882` | The tournament director's `email` and `phone` (possibly a third party) are readable by any signed-in account once the event is published. The public API exposes only the name. | Move contact details into a subdocument readable by entrants and managers, or serve them through the API. |
| SEC-11 | Low | CONFIRMED | API | `moderation/service.ts:108-109, 288-292` | The team report queue gives anyone with `manageTeam` or `moderate` the snapshots of messages from rooms they can't read, such as a coaches-only room. The rules require `canReadRoom` for moderator deletes. | Filter `teamMessage` reports by `canReadRoom` (owners excepted). |
| SEC-12 | Low | CONFIRMED | functions | `account/functions.ts:52`; `api/model.ts:36` | **P10 is half open:** sign-in is limited per username, not per IP. Anyone unauthenticated can lock any username out for 15 minutes with 10 bad tries, and can create `limits/signIn_*` documents. | Add a per-IP bucket, using the real IP as in S3. Consider limiting only failed attempts per username. |
| SEC-13 | Low | SUSPECTED | rules | `firestore.rules:2499-2515` | A post created without `private` (older builds) passes `get` through `get('private', false)` until the follows function stamps it. A private author's new post is briefly readable by anyone who knows its ID. | Require `private` on create once old builds are retired. |
| SEC-14 | Low | SUSPECTED | API | `cors.ts:32` | **P8 is open in code.** `*` still expands to `[a-z0-9-]+`, so a `frisbee*-…vercel.app` pattern still matches lookalikes. The deployed values live in GitHub variables I couldn't see. | Use exact origins in prod. In dev, use `frisbeeapp-git-*-…` with a fixed prefix. |
| SEC-15 | Low | SUSPECTED | functions | `meetings/functions.ts:73, 80, 112, 119` | LiveKit tokens last 6 hours, and nothing removes someone already in a voice room when they're taken off the team or room. Listen-only voice participants keep `canPublishData`. | Shorter TTL. On member removal, call `RoomService.removeParticipant`. Set `canPublishData: canSpeak`. |
| SEC-16 | Low | CONFIRMED | rules vs API | `firestore.rules:313`; `messages/service.ts:68-71` | The rules accept any string for `messagePolicy` and treat unknown values like "following". The API treats unknown values as "everyone". The layers disagree. | Restrict the rule to `in ['everyone','followers','following','nobody']`. |
| SEC-17 | Low | SUSPECTED | API/infra | `calendar/routes.ts:110-115` | The feed token is in the URL path. Fastify skips logging it, but Cloud Run's request logs record the full URL. | Accept that the token is a bearer credential: limit log access or retention, or move the token to a query string and exclude it from logs. |

## What held up

- Webhook signature: `stripe.ts:211`.
- Scheduler OIDC check: `jobs.ts:29-40`.
- Revalidate key.
- DM and group membership checks in both layers.
- Blocks on DMs, follows, comments and likes.
- `personalDetails`, `reports`, `calendarFeeds` and `blocks` are closed to clients.
- `deleteFilesUnder` is restricted to the folder prefix.
- Youth and private-page rosters are hidden in `roster.ts:70-81, 132-137`.
- Link handling allows only `http(s)`, with in-app paths for `/join`, `/g` and `/p`.
- The payouts WebView is pinned to `/embed/payouts`.
- No obvious token or PII logging in Dart.
- Errors are generic.
- Request bodies are capped at 64 KB.

## Pentest status re-checked (in code at 39c8a53, not re-tested live)

| # | Status | Evidence |
|---|---|---|
| P1 | Fixed in code | `firestore.rules:2504` `capped(50) && canListPost` (but see SEC-13) |
| P2 | Fixed | `apps/api/package.json:26` `^0.35.5`; lockfile `sharp@0.35.5` |
| P3 | Partial | Type allow-list at `storage.rules:24-28`; quota and direct writes open (SEC-6) |
| P4 | Open | SEC-2; `ENFORCE_APP_CHECK` still defaults to false (`options.ts`, `server.ts`) |
| P5 | Partial | `next.config.ts:10, 33-37` headers set; no `script-src`/`default-src` CSP |
| P6 | Fixed on the API | `auth.ts:56`; client-written names still free text (SEC-5) |
| P7 | Open | SEC-8 |
| P8 | Open or unverified | SEC-14 |
| P9 | Not verifiable from code | Restrict the key in the GCP console |
| P10 | Partial | `users/{uid}` fields whitelisted at `firestore.rules:304-314`; per-IP sign-in limit open (SEC-12) |

## Launch blockers

1. **SEC-2 / P4:** server-side age enforcement and App Check. COPPA exposure.
2. **SEC-1:** adult-to-minor messaging controls, or a server-enforced adult-only launch.
3. **SEC-3:** staff MFA, token revocation on staff routes, and an audit log (C-27, P0-11).
4. **SEC-4:** the club 16+ level-change bypass (a stated policy that isn't enforced).
5. **SEC-6:** upload quotas before public sign-up, as a cost and abuse ceiling.

SEC-5 and SEC-7 should land before youth teams are invited.

## Suggested issues

| Title | Pri | Hours |
|---|---|---|
| Enforce 13+/adult and verified email on server (claim + rules + API) | P0 | 12 |
| Turn on App Check enforcement (rules, callables, API) after builds ship tokens | P0 | 6 |
| Adult-to-minor DM and discovery restrictions (or adult-only enforcement) | P0 | 16 |
| Staff MFA, `checkRevoked`, scoped claims, append-only staff audit log | P0 | 14 |
| Club level changes through the API with age re-check; remove `level` from rules | P1 | 4 |
| Tie `authorName`/`replyTo`/`memberNames` to server-known names | P1 | 6 |
| Direct Storage uploads: quotas, DM conversation checks, plan to route through `/v1/uploads` | P1 | 8 |
| Block and mute checks on team invites (rules + API) | P1 | 2 |
| Server-computed profile stats; approval for roster-spot claims | P2 | 10 |
| Profiles `list` constraint; director contact privacy; team report room filter | P2 | 5 |
| Per-IP sign-in limit; exact CORS origins; `messagePolicy` enum; LiveKit revocation | P2 | 6 |

## Tests needed

Rules tests (emulator, `npm run test:rules`), each pair allowed or denied:

- **teams:** a manager changing `level` to `club` is denied. Editing `name`/`city` is allowed.
- **teams/chats/messages:** `authorName` not equal to `memberNames[uid]` is denied. A forged `replyTo` is denied. A correct name is allowed.
- **users/{u}/teamInvites:** an inviter blocked by, or blocking, the invitee is denied. A muted inviter is denied. A normal manager invite is allowed.
- **conversations storage:** upload to a non-existent conversation is denied. Upload while a request awaits the uploader is denied. Upload between blocked users is denied. An accepted participant is allowed.
- **profiles list:** without a `keywords` filter, denied. `array-contains` with `limit(50)`, allowed. `limit(51)`, denied.
- **tournaments:** a non-entrant reading `director.email` is denied (after the change). A manager is allowed.
- **posts:** `list` with `private == false` is allowed. An unfiltered list is denied. A follower's single-author list of a private author is allowed, a stranger's denied. `get` of a post with no `private` field by a private author is denied.
- **users/{uid}:** `messagePolicy: "x"` is denied. A valid enum value is allowed. Writing `agreedTerms` or `staff` is denied.
- **profiles:** writing `stats` is denied once moved server-side. Roster self-claim without approval is denied.

API tests (Fastify inject with fakes):

- `/v1/staff/*`: no claim gives 403. A revoked token or no MFA gives 401/403. A staff token with MFA succeeds and writes an audit row.
- Writes (posts, messages, joins, follows) without `ageOk` or `email_verified` give 403. With them, they succeed.
- `POST /v1/conversations`: an adult to a 13–17 stranger is refused. Same team is allowed.
- `POST /v1/teams/:id/invites`: blocked either way gives 403. Muted gives 429.
- Team `editTeam` to `club` with an under-16 member is refused. All 16+ is allowed.
- `GET /v1/teams/:id/reports`: a `manageTeam` holder without room access doesn't see `teamMessage` snapshots from that room.
- `signInEmail`: the per-IP limit trips across many usernames.
- CORS: a lookalike origin gets no `access-control-allow-origin`.

Physical device: LiveKit removal mid-call. Deep links `/join/*` on iOS (TestFlight).

Secrets hygiene: no secret files are tracked, and the local secret files (`secrets.local.json`, the `.env` files, `google-services.json`, `GoogleService-Info.plist`, `key.properties`) are git-ignored. The tracked `*.env.example`, `secrets.example.json` and Xcode `*.plist` files were left unopened. A pattern scan of tracked source found no secrets.
