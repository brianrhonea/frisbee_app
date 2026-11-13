# Stall 10 version log

Each feature branch bumps the version by one. The version lives in
`pubspec.yaml` (`version: X.Y.Z+N`, where `N` is the build number) and in
`appVersion` in `lib/ui/core/ui/brand.dart`; `test/version_test.dart`
fails if they drift apart or this log has no entry for the version.

Versions stay at `0.0.x` until the first App Store release. Codemagic
picks iOS build numbers on its own (see `docs/ios-release.md`).

Plain-language notes for testers are in
[release-notes.md](release-notes.md); add to both when you bump.

| Version | Date       | Branch                                  | Commits             |
|---------|------------|-----------------------------------------|---------------------|
| 0.0.16  | 2026-11-12 | `development`                           | `9ba6ea0` and later |
| 0.0.15  | 2026-11-12 | `feature/leagues`, `monorepo`           | `e3bac8b` and later |
| 0.0.14  | 2026-11-06 | `development`                           |                     |
| 0.0.13  | 2026-11-05 | `hardening/scale-and-abuse`             | `09d17af` and later |
| 0.0.12  | 2026-11-05 | `development`                           |                     |
| 0.0.11  | 2026-11-04 | `development`                           | `6d50dc5`–`ea081ac` |
| 0.0.10  | 2026-11-03 | `development`                           | `bfcf7f4`–`b80e854` |
| 0.0.9   | 2026-11-02 | `feature/gps-workouts`                  | `41a03bc`           |
| 0.0.8   | 2026-10-31 | `feature/follows-feed`                  | `1f81f45` and later |
| 0.0.7   | 2026-10-31 | `feature/community-groups`              | `9f19c55` and later |
| 0.0.6   | 2026-10-30 | `feature/team-videos`                   | `d623748` and later |
| 0.0.5   | 2026-10-30 | `feature/team-meetings`                 | `1b2e424` and later |
| 0.0.4   | 2026-10-29 | `feature/ultiup-schedule`               | `06830cc` and later |
| 0.0.3   | 2026-10-29 | `feature/roster-import`                 | `5620a1d`           |
| 0.0.2   | 2026-10-29 | `feature/stats-mockup`                  | `7556460`           |
| 0.0.1   | 2026-10-28 | `feature/team-calendar-animated-plays`  | `fd59d92`           |
| 0.0.0   | 2026-10-28 | `development` (MVP baseline)            | `090e7b4`–`04d4109` |

## 0.0.16 — New navigation: five tabs and a five-tab team page

Step 1 of the rework in `docs/product-spec.md` (§3, §4). No data changes.

**Changed**
- **Tabs** (`ShellSection`): Home, Explore, **Events**, Teams, Messages.
  The profile keeps its shell branch but has no tab; on phones an avatar
  (`ProfileButton`) at the top left of each tab's first page opens it,
  and no tab looks selected there.
- **Events tab** (`/schedule`): My schedule (moved from Home's branch) and
  Find events (`?view=find`, the tournaments and leagues list), under
  `EventsTabs`. `/tournaments` still opens on its own.
- **Team and community pages** (`TeamTab`): Feed, Schedule, Chat, Roster,
  More, over the unchanged `TeamSection`s and their links. Roster opens on
  members, with a Members / Players switch on teams; More
  (`?section=more`) lists Playbook, Videos, Stats, Tournaments and, for
  schools/clubs, Teams. "Team Events" is now Schedule everywhere.
- Breadcrumbs say Home, Events and Teams; the desktop sidebar drops its
  Team calendar link.

## 0.0.15 — Leagues and hat tournaments; monorepo; API paths

**Added**
- **Leagues and hat tournaments**: a `HostedTournament` with
  `kind: league`, team or player entry (`entryType`), set weeks, and a
  balanced (self-rating) or captains' live draft
  (`/tournaments/:id/live-draft/:divisionId`, callables in
  `functions/src/tournaments/draft.ts`). Mixed entry: teams reserve spots,
  free agents are drafted into the rest. **Host an event** picker
  (League / Tournament / Hat) and a Tournaments & leagues find page.
- **Official hosts**: `Team.official` (console only) and
  `HostedTournament.hostOfficial`, shown with a verified badge.
- Shared event format (`HostedTournament.format`) and points or time
  scoring.
- **API paths** for team create, membership and profiles/usernames
  (`apps/api`), behind `use_api_teams`, `use_api_membership` and
  `use_api_profiles`. Builds without `API_BASE_URL` keep writing Firestore
  directly.

**Changed**
- The repo is a monorepo: the app lives in `apps/mobile` (Codemagic builds
  from there).

**Removed**
- The `web/`, `macos/` and `windows/` targets. The app is iOS and Android
  only; the website is `apps/web` (Next.js). Local runs use an Android
  emulator or a device.

## 0.0.14 — Hosted tournaments; USA Ultimate data removed

**Removed**
- All USA Ultimate data and features (events, rankings, team pages and
  search, team linking and roster sync, the `onUsau` flag, USAU event
  follows, the Home card and the `functions/src/usau` scrapers). We don't
  have rights to the data; see CLAUDE.md.

**Added**
- **Hosted tournaments** at `tournaments/{id}` (`HostedTournament` in
  `lib/domain/models/hosted_tournament.dart`), with `divisions/{id}/games`,
  `entries/{teamId}` and `payments/{teamId}`. Any team, group or
  school/club hosts from its Tournaments section; members with Manage
  events run it. Draft → registration → seeding → scheduled → live →
  final. Public or invite-only; published tournaments are readable by
  anyone signed in, payments only by managers and the team's admins.
- Divisions (division × level, team cap, format, game rules), team
  applications and invites with captains, accept/waitlist/decline/
  withdraw, a recorded bid fee marked paid by hand (unpaid and overdue
  filters), drag-to-seed, publish per division, captain score reporting,
  results with final placements, news (public host posts tagged with the
  tournament's follow key) and following.
- Engine: `TournamentFormat.poolsPlacement` (pools, then brackets where
  every team plays for a final place), `GameStage.crossover` and
  `placement`, `GroupGame.place`, `placementsOf`, `suggestedPools` /
  `suggestedFormat`, `scheduleFor(teams, settings)`.
- Routes `/tournaments` (find), `/tournaments/new?host=`,
  `/tournaments/:id`, `/tournaments/:id/edit`; Explore → **Find a
  tournament**. Signed-in web gets the same routes; visitors sign in.
- `firestore.rules`: `tournaments` block; game docs (both kinds) may
  carry `place`. Index: `tournaments` (status, startsOn). Rules and
  indexes deployed to dev.

**Changed**
- Teams and schools/clubs get a Tournaments section; groups list hat
  tournaments under their hosted ones. Tournament follows open
  `/tournaments/:id?host=`, which falls back to the hat tournament.

## 0.0.13 — Flood protection, paging, smaller photos, push fix

Branch `hardening/scale-and-abuse`, merged into `development`.

**Added**
- **Flood control** (`functions/src/api`, deployed as `api`): create
  triggers count each person's messages, posts, comments, follows, join
  requests and new teams in `limits/{uid}`; past the limit the extra item
  is deleted and `mutedUntil` set 10 minutes ahead. `firestore.rules`
  checks `notMuted()` on those creates. The app shows "You're going too
  fast". Username sign-in is limited to 10 tries per 15 minutes.
- **`api-search`** callable (people, players, teams; rate limited), off
  until `meta/flags.use_api_search` is true. **`api-health`** for uptime
  checks.
- **App Check** in the app (`AppCheck.activate()`, `X-Firebase-AppCheck`
  on HTTPS calls); callables enforce it when `ENFORCE_APP_CHECK=true`.
  `APP_CHECK_DEBUG_TOKEN` added to the secrets files.
- **Kill switches** in `meta/flags` (`FeatureFlags`): `use_api_search`,
  `compress_images`.
- **Photo compression** (`ImageCompressor`): ≤ 1920 px, JPEG 80, EXIF
  baked in, before upload; picks up to 50 MB. Uploads get a year-long
  `Cache-Control`. `functions/scripts/compress-existing-images.ts` for
  old uploads.
- **Cursor paging** for chat, DMs, meeting chat (`fetchOlderMessages`)
  and the home feed (`fetchPostsBefore`): older pages load one at a time.
- **Deploy / Roll back backend** GitHub Actions workflows, and
  `scripts/monitoring/setup-alerts.sh` for SMS alerts.
- Docs: `ARCHITECTURE.md` restructured, `cloud-limits.md`, `rollback.md`,
  `monitoring.md`, `app-check.md`.

**Changed**
- The chat Send button shows at every width (it was hidden at 720 px and
  up, so tablets couldn't send).
- Notification rows are compact (no category icons; one line each for
  title and message); the notifications button is a flying disc
  (`DiscIcon`) instead of a bell.
- `fieldOverrides` stop indexing large unqueried fields; hosting sends CDN
  cache headers; `maxInstances: 10` for every function.

**Fixed**
- **iPhone push never registering**: `PushService.register` waited for
  `onRegistered`, which iOS can fire at launch before anything listens,
  so it timed out and no device was saved. It now waits for the APNs
  token, registers, and reads the FID from Firebase Installations
  (`firebase_app_installations`). Failures throw
  `PushRegistrationException` and show in Notification settings with
  **Try again**; the server logs "Push sent" / "No push devices".

## 0.0.12 — School and club communities, private profiles, username sign-in

Straight on `development`.

**Added**
- **School or club communities** (`TeamKind.organization`, noun
  "community"): one community with several full teams (e.g. Woof and
  Whiplash). Teams link both ways: the team sets `orgId`/`orgName`, the
  community lists it in `linkedTeams.{teamId}` `{name, division, roles}`.
  A team asks to join (`teams/{orgId}/linkRequests/{teamId}`) and the
  community accepts, or the community creates the team inside itself.
  The admin picks which community roles get onto each team; holders join
  it automatically and leave when the role is taken away (only people the
  community added, tracked in `orgMembers`). **Teams** tab on the
  community; **School or club** in the team ⋮ menu and a chip on the team
  home.
- **Community events by role**: an organization's event has an `audience`
  (role ids / `everyone`); only those roles see it. Queries use
  array-contains per held id (`Team.eventAudienceOf`), with a composite
  index (audience CONTAINS, startsAt ASC). Event editor: **Who sees it**.
- **Discord import into teams**: on a community with teams, rooms only one
  team's roles read go to that team's chat (`DiscordTeamSplit`), shared
  rooms stay in the community, each room can be overridden. Each team
  gets copies of the community roles that grant it (`Team.orgRoles`,
  team role → community role) and the community function keeps who holds
  them in step. Rooms already in the community chat from an earlier
  import are moved (deleted there after a confirm).
- **Sign in with username or email** (`account-signInEmail` callable,
  checks the password through the Identity Toolkit REST API with the
  `WEB_API_KEY` secret, then returns the email).
- **Private profiles**: Settings → Privacy → **Private profile**. Only
  name, username and photo stay in `profiles/{uid}`; the rest moves to
  `profiles/{uid}/private/details`, readable by the owner and accepted
  followers. Following one sends a request
  (`profiles/{owner}/followRequests/{uid}`); **Follow requests** in
  Settings accepts or declines.
- **Change password** in Settings → Account (current, new, confirm;
  "Forgot it?" sends a reset link).
- **In-app notification bubble** while the app is open, from the feed, on
  every platform; repeats in the same chat update it in place. iOS and
  macOS no longer show a system banner in the foreground.

**Changed**
- Playbook on phones: a 44 px minimum grab radius and a small drag
  threshold so fingers pick up dots; touching the field hides the step
  note keyboard.
- Notification settings explain when push is off on the phone, with
  **Turn on notifications** / **Check again**.

**Infrastructure**
- New Cloud Function `communities-sync` (`onDocumentWritten teams/{id}`):
  membership by role, catch-up for teams linked earlier, role copies
  (`mirrorUpdate`). `notifications` use `eventViewers` (audience) and
  honor custom roles in `roomReaders`; `account-signInEmail` added and
  join-request cleanup covers both group kinds. All deployed to dev.
- Rules: organizations, `validOrgRef`, `linkRequests`, `orgMembers`,
  `orgRoles` (map ≤ 50), event `audience`, private profiles and follow
  requests, with rules tests. Rules and indexes deployed to dev.
- Secret `WEB_API_KEY` set on dev and prod.

## 0.0.11 — Usernames, Settings, search everywhere and polish

Straight on `development`.

**Added**
- **Usernames.** Unique, 3–20 of `a-z 0-9 _ .` (no leading, trailing or
  double periods; a few reserved). Sign-up asks for first and last name,
  username (live availability check), email, password and confirmation.
  Google, Apple and older accounts are sent to **Pick your username**
  (`/welcome/username`) by `authRedirect` before anything else. Shown as
  @name on profiles, in people search, Explore, the send-post sheet and
  the invite dialog; search matches it.
- **Password policy**: 8–128 characters, a letter and a number, no
  leading or trailing space, not a common password. Strength meter and
  checklist on sign-up; show/hide on every password field.
- **Settings page** (`/settings`, gear at the top right of your profile)
  sliding over the page, a 440 px panel on wide windows: General
  (theme), Notifications, Privacy (read receipts), People you follow,
  Account (display name, username, email, delete account), Sign out and
  the version. Sub-pages `/settings/general`, `/privacy`, `/account`.
  Replaces the profile's Settings card.
- **Read receipts**: "Seen" under your last message once the other person
  reads it; off in Settings → Privacy (then you don't see theirs).
- **Notification offers**: once at first sign-in, on joining a team, and
  on following someone. Declining a team turns off its per-team
  categories.
- **One search**: Home has a search bar on phones; the top bar's box
  says "Search Stall 10". Explore searches players, teams, groups and
  upcoming USA Ultimate events (chips: All, Players, Teams, Groups,
  Events; three events in All with "See all"). `/teams/search` redirects
  to Explore. A shared `AppSearchField` everywhere.
- **Command menu**: Ctrl K / ⌘K from anywhere (a `HardwareKeyboard`
  handler, so focus doesn't matter): sections, your teams, common
  actions, and "Search Stall 10 for …". Ctrl 1–5 switch sections, from
  inside the menu too. Key-cap hints in the top bar, menu and rail
  tooltips.
- **Undo instead of "Are you sure?"** for deleting feed posts, comments
  and chat messages: hidden at once, deleted after 5 s
  (`PendingRemovals`), or when the screen closes.
- Skeleton placeholders instead of spinners (`LoadingView` and the
  feed, profile, Explore, sheets and photos); photos fade in.
- Balanced headlines (`BalancedText`) on page and auth titles.

**Changed**
- **Roles**: built in are Owner and Player only; owners create the rest.
  Coach and captain tiers migrate to custom roles (Coach and Captain
  with every permission on teams, Organizer on groups) the first time
  the owner opens the team; rooms that admitted a tier admit the new
  role. Nobody can be made coach or captain any more.
- Notifications: per-room mute moved into the room's ⋮ menu; a person's
  post notifications into the **Following ▾** menu.
- Phones: portrait only (iPhone `Info.plist`, Android under 600 dp), and
  the bottom bar has every section.
- Direct messages on phones have a back arrow to Messages instead of the
  conversations drawer (team chat keeps its drawer).
- Sign-in and sign-up fit a phone screen without scrolling.
- Theme: `RoundedSuperellipseBorder` corners, tabular figures in all
  text, drag handles on swipeable sheets, predictive back on Android
  (`enableOnBackInvokedCallback`), Cupertino slides on iOS and macOS and
  fade-forwards elsewhere. `slideOverPage` (with an edge shadow) for
  Settings and notification settings.

**Infrastructure**
- New Firestore data: `usernames/{name}` → `{uid, createdAt}`, claimed in
  the same transaction that sets `profiles/{uid}.username` (set once);
  `users/{uid}.firstName`, `.lastName`, `.readReceipts`; private read
  marks `users/{uid}/dmReads/{conversationId}`. Rules and rules tests
  for all of them, and for the role migration (deployed to dev).
- `account-deleteAccount` frees the user's username, and ownership
  passes to coach, then captain, then a member with Manage team
  (deployed to dev).

## 0.0.10 — Comments and sending posts

Straight on `development`; feature branches are retired for the beta.

**Added**

- **Comments** on people's posts. **Comment** under a post (with the
  count) opens its page at the comment box; comments show oldest first
  with who and when, and links in them are tappable. Commenting on a
  repost comments on its original. Delete your own comment, or any
  comment on your post.
- The post's author is notified ("Zed commented on your post"; comments
  on one post fold together), in the **Likes, reposts and followers**
  category.
- **Send** under a post: pick someone you've messaged (listed first) or
  search for anyone, and tap **Send**. It goes as a direct message with a
  line about the post and its link, which opens the post in the app.
  **Copy link** and **Share to other apps** are there too.
- **Post links** (`…web.app/p/<id>`) open the post in Stall 10 on phones
  with the app, or a page with an **Open in Stall 10** button. Signing in
  from one returns to the post.

**Infrastructure**

- New Firestore data: `posts/{id}/comments/{commentId}`; rules and rules
  tests (anyone signed in comments as themselves, up to 1000 characters,
  not on a repost; the commenter or the post's author deletes; nobody
  edits; nobody writes `commentCount`). A collection-group exemption on
  `comments.authorId` for account deletion.
- New Cloud Functions: `follows-commentCount` keeps each post's
  `commentCount`; `notifications-postCommented` tells the post's author.
  `follows-userPostDeleted` now deletes a post's comments too, and
  `account-deleteAccount` deletes the user's comments.
- `/p/*` added to the hosting rewrites, the iOS
  `apple-app-site-association` and the Android App Links filter.

**Also in 0.0.10** (`b80e854`)
- Discord-style **custom roles** with permissions (Manage team, Manage
  members, Manage chats, Manage events, Moderate, Keep stats) for teams
  and groups; rooms take role-based access and live in reorderable
  folders.
- **Import roles and channels from a Discord server template** link
  (`discord-previewTemplate` function).
- **Voice channels** on LiveKit (`meetings-voiceToken`), listen-only for
  members who can read but not write.
- Discord-style message rows and composer; drag to rearrange channels and
  folders.
- Faster back navigation: shared message streams, and the native iOS page
  so swipe-back works.
- A separate **dev Firebase project** (`frisbee-app-brianrhonea-dev`):
  `FIREBASE_ENV` picks the project; `development` builds TestFlight against
  dev, `main` builds the App Store against production.

## 0.0.9 — Record runs and rides with GPS

Branch `feature/gps-workouts`.

**Added**
- **Record** (Home and Profile, on phones): record a run, ride, walk or
  hike with GPS. A live map draws the route, with the time, distance,
  average pace and current pace (speed for rides). Start, Pause, Resume,
  Finish or Discard. Recording keeps going with the screen locked (an
  Android notification; iOS background location) and while you use the
  rest of the app; the Record button shows the clock.
- **Finish** opens the composer with the time, distance and route filled
  in. **Hide your start and finish** (on by default) cuts the first and
  last 200 m from the posted map; the stats are unchanged.
- Recorded workouts show the route map on the post. Opening the post
  shows **splits**: the time for each mile or kilometre, with the part
  left over, and elevation gain.
- New activities: Ride, Walk and Hike.

- **New sign-in and sign-up screens.** A disc is thrown across an ultimate
  field while the wordmark counts the stall (Stall 1… 9) and is caught as
  the "0" of the logo: Stall 10. Then the form slides up. Plays once per
  launch, not at all with reduced motion; tap the field to throw again. The
  field sits above the form on phones and beside it on wide screens.
- **Share an event with followers.** A switch on new events posts the
  event (date, time, place, team) to your profile with an optional note.
  A shared team event also shows in the feed of everyone on that team.
- **Likes and reposts** on people's posts, with counts. A repost shows
  your note over the original, which stays live (edits show; a deleted
  original says so). One repost per person per post; tap **Reposted** to
  take it back.
- **Notifications** when someone likes or reposts your post (likes on a
  post fold together) or starts following you, with **Follow back** right
  in the list. A new **Likes, reposts and followers** category turns them
  off.

**Changed**
- **Add event** moved from the post composer to **Coming up**, asks which
  schedule first, and opens over the page like the composer instead of on
  a page of its own. Saving offers **View**; closing with changes asks
  first.
- The post composer on wide screens is only as tall as its content.
- From a post's own page, tapping a person or team switches to their tab
  instead of crashing with duplicate page keys.
- Signing in or up always lands on **Community**, instead of the page you
  were on. Invite links (`/join/…`, `/g/…`) still return to the link so
  you can finish joining.
- Distances, paces and speeds show in miles in the US and UK, kilometres
  elsewhere. The manual workout distance field uses the same unit.
- Workouts store `durationSeconds` and a `route` (encoded polyline, splits
  per mile and per km, elevation gain); `validRoute` in `firestore.rules`.
- Codemagic builds the iOS app and uploads it to TestFlight on every push
  to `development`.

## 0.0.8 — Follows, the home feed and workout posts

Branch `feature/follows-feed`.

**Added**
- **Follow** people, teams, community groups, group tournaments and USA
  Ultimate events. The button is on team and group pages, tournament and
  event pages, and people's profiles. It shows the follower count.
- A **bell** next to Following turns on notifications for that one's new
  posts (push where the device allows, and always in Notifications). A new
  **Posts you follow** notification category turns them all off.
- **Home feed**: your posts, every post from your teams and groups, public
  posts from teams you follow, posts by people you follow, and posts
  tagged with a tournament you follow. Newest first, with **Show older
  posts**. On phones, Home is now the week, your team, then the feed.
  Playbook, events and rankings moved to the side column on wide screens,
  and they're still in their tabs.
- **Your own posts**: text, up to 4 photos and 5 links, optionally tagged
  with a tournament or event you follow.
- **Workouts**: share a run, sprints, throwing, gym, agility or mobility
  session. Add the time, an optional distance (pace is worked out for
  runs), effort 1–10 and up to 20 exercises with sets, reps and weight. The
  feed shows it as a stat card.
- **Profiles** (`/people/:uid`): name, photo, followers and following
  counts, Follow, Message and their posts. Open one from a post's author,
  a team's Members list, or **View profile** in people search.
- **Following** (Profile → Following, or **Following** on the feed):
  everything you follow, with each bell and Unfollow.
- Group pages list the group's tournaments for people outside the group.
  Someone who isn't playing in a tournament sees a public summary with
  Follow.
- **Invite links.** The invite dialog (team Members) shows the team's link
  to copy or **Share** to any app: Messages, WhatsApp, email. Tapping it
  opens Stall 10 at a Join screen naming the team; without the app, a page
  on Firebase Hosting (`hosting/`) has an Open in Stall 10 button.
  Inviting someone found by search also sends them the link as a direct
  message. Groups' links open their page. Links in messages are now
  tappable, and Stall 10's own open in the app.
- **Invite codes rotate; links expire.** Admins tap **Show code** on
  Members for a code that changes every 30 seconds (each works for 45).
  Team links last 1 hour, 1 day, 7 days (default) or 30 days, picked in
  the invite dialog. Codes and link tokens are `inviteCodes` docs with
  `createdAt` + `ttl`, checked by `join()` in `firestore.rules` on the
  server's clock; a TTL policy on `expiresAt` (`firestore.indexes.json`)
  deletes them. Coaches and captains can now mint codes, not just the
  owner. Permanent codes (`private/invite`, team-doc `inviteCode`) no
  longer work, and new teams get none.

**Changed**
- **The app is now Stall 10**, with a new logo: a "10" whose "0" is a
  flying disc. `tool/brand/stall10_logo.py` draws it and every launcher
  icon (Android, iOS, macOS, Windows). Bundle ids and the package name
  are unchanged.
- **Team pages have tabs.** Home, Team Events, Chat, Roster, Playbook,
  Videos, Stats and Members (groups: Home, Events, Chat, Tournaments,
  Members) sit in a tab bar under the team name. Switching tabs changes
  only the content below it; back leaves the team. This replaces the
  section tiles and the separate page for each section.
- **USA Ultimate tournament and team pages open over the current tab.**
  Tapping a tournament or ranked team on Home, Events, Rankings or
  Following no longer switches you to the Events or Rankings tab, and
  back returns to where you were. Opened from a link, back goes to
  Events or Rankings.

**Infrastructure**
- New Firestore data: `users/{uid}/follows/{key}`, `posts/{id}`,
  `followCounts/{key}` and `tournamentDirectory/{groupId_tournamentId}`.
  Team posts get an optional `tournamentKey`, which the tournament
  announcement sets. Rules and rules tests are written for all of them,
  plus Storage `users/{uid}/posts/…`; the rules tests need Java and the
  emulator to run.
- New Cloud Functions:
  - `notifications-userPost` and `notifications-teamPost` notify followers
    who turned the bell on.
  - A new `follows` group: `followCount` keeps `followCounts`;
    `profileDeleted`, `teamDeleted` and `groupTournamentDeleted` drop
    follows of deleted targets; `userPostDeleted` removes a deleted
    post's photos.
- New composite indexes: `posts` by `authorId` and by `tournamentKey`,
  each with `createdAt`. Also a collection-group index on `follows`
  (`key`, `notify`).
- Deleting an account also deletes the user's follows and posts.

## 0.0.7 — Community groups and pickup tournaments

Branch `feature/community-groups`.

**Added**
- **Community groups**: open pickup communities, alongside teams. No
  roster, playbook, videos or stats; instead Events, Chat, Tournaments and
  Members. Roles are Owner, Organizer and Member.
- Find groups in Teams search (filter All, Teams or Groups). Anyone can
  **Join**; if the owner turns on **Approve new members**, people **Ask to
  join** and organizers approve or decline requests on the Members page.
- A group's description and location. Organizers search for an address
  (OpenStreetMap / Nominatim) and fine-tune it on the map; the home page
  shows the map with a **Directions** button.
- **Pickup** events. Tournament events in groups take **Attending**,
  **Planning to attend** and **Not able to make it :(** RSVPs.
- **Tournaments** for groups: organizers set the format, rules and number
  of teams (Team 1, Team 2…, renamable) first, publish the schedule, and
  add players before or after. Players come from a Tournament event's
  attending and planning-to-attend RSVPs, or by hand; **Assign teams**
  deals them evenly into the teams with a random captain each.
- Formats: round robin, pool play + single elimination, single
  elimination and double elimination (with an if-needed final). Settings
  for 3v3 to 7v7, game length, breaks, score cap, timeouts per half,
  fields and an ideal end time.
- **Multi-day tournaments**: first and last date, with a start time for
  each day. The generated schedule splits games evenly over the days, in
  bracket order, and warns if it runs past the ideal end.
- The tournament page: schedule, pool standings, bracket and teams, plus
  "You're on…" with your captain and next game. Teams are private to the
  tournament's players and organizers.
- Captains **report** scores; the other captain **confirms**, or reports
  their own score instead. Organizers can set or correct any score.
  Confirmed results move teams on in the bracket; organizers seed the
  bracket from pool standings when pools finish.

**Infrastructure**
- Groups are `teams/{id}` with `kind: 'community'`. Firestore rules for
  group creation (no invite code), open join, `joinRequests` and
  approvals, group details and location, `groupTournaments` and their
  `games` (captain reports and confirmations, and bracket advancement
  checked against the source game with `getAfter`). Rules tests are
  written; they need Java and the emulator to run.
- Pure-Dart tournament engine in `lib/domain/tournament_engine/`
  (team builder, schedule generator, standings, bracket progress).
- New packages: `flutter_map`, `latlong2`.

## 0.0.6 — Team videos

Branch `feature/team-videos`.

**Added**
- A **Videos** section on each team for YouTube videos: meeting
  recordings, game film, anything uploaded to YouTube (Unlisted works).
  Thumbnails in a grid, newest first; tap one to play it in the app.
- Owners, coaches and captains add videos by pasting a link. UltiUP checks
  it with YouTube, shows the thumbnail, fills in the title, and warns if
  the video is private or doesn't allow embedding. They can edit the
  title and description, or remove a video (it stays on YouTube).
- YouTube's embedded player on Android, iOS and macOS, and on Windows in
  an Edge WebView2.
- **Upload a video file** (MP4, MOV, MKV, WebM, AVI, WMV, MPEG or 3GP)
  instead of a link: up to 500 MB per file and 5 GB per
  team, with an upload progress bar. Admins see how much of the team's
  space is used. Uploads play in the app with media_kit; removing one
  deletes the file.
- **Watch together** in meetings: an admin picks a team video (by folder)
  and it plays for everyone in the call, in sync, on their own device at
  full quality, instead of a screen share. Play, pause and seek follow the
  presenter; another admin can take control; Stop returns to the call.
  YouTube links and uploads both work, on Windows too (YouTube's IFrame
  API in WebView2).
- **Folders** to organize videos, like Film review, Game film and
  Highlights. Filter with chips (All, a folder, Unsorted); owners, coaches
  and captains create, rename and delete folders and move videos with
  **⋮ → Move to folder**. Deleting a folder moves its videos to Unsorted.

**Infrastructure**
- Firestore rules for `teams/{id}/videos`: members read; owners, coaches
  and captains write; only an 11-character YouTube id is stored, never a
  URL, or a video file record (deployed). Deleting a team removes its
  videos and their files.
- Storage rules for `teams/{id}/videos/{videoId}/{name}`: members read;
  owners, coaches and captains upload `video/*` files up to 500 MB (deployed).
- Firestore rules for `meetings/{id}/playback/current`: people in the
  call read; admins write as themselves, while live, for a team video
  (deployed). Ending or deleting a meeting clears it.
- Firestore rules for `teams/{id}/videoFolders` and a video's
  `folderId` (deployed). Deleting a team removes its folders.
- New packages: `media_kit`, `media_kit_video`, `media_kit_libs_video`.

## 0.0.5 — Team meetings

Branch `feature/team-meetings`.

**Added**
- Team meetings: owners, coaches and captains schedule a meeting for
  chosen roles and/or people, with an optional "Require admin approval to
  join". Meetings show on the schedule only for invitees.
- Meeting page with Attending / Not attending RSVP and a link to the
  meeting room.
- Meeting room lobby: pick microphone, speaker and camera, camera preview,
  meeting volume. Admins start the meeting (early if they like) and admit
  or deny people waiting to join.
- Video calls on LiveKit Cloud: camera or profile photo per person, a
  speaking highlight, screen share (Windows, macOS, Android), in-call
  chat, and mic / camera / sound / leave controls. Admins can end the
  meeting for everyone.
- Tap a person to set their volume (0–200%) or mute them, just for you.
  Devices and volumes are remembered on the device.
- Notifications for meeting invites, cancellations and starts; an in-app
  banner with **Join** when a meeting you're attending starts.

**Fixed**
- Opening notifications one after another (for example a play, then a
  team's events) could break navigation with a red screen.
- Leaving the play editor could throw an error while the page closed.
- Deleting a team now deletes its meetings too.

**Infrastructure**
- Firestore rules for meetings, join requests and meeting chat (deployed).
- `meetings` Cloud Functions group (`joinToken`, `closeRoom`), using the
  `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` secrets
  (deployed, with the updated `notifications` group).
- `--dart-define=FIRESTORE_MEMORY_CACHE=true` lets a second copy of the
  desktop app run on the same computer, for testing two accounts.

**Also since 0.0.4** (branches that didn't bump the version)
- USA Ultimate event schedules and brackets on tournament pages (`6f9e179`).
- Team chat rooms and direct messages (`bb69f04`).
- Notifications: push, in-app feed and settings (`106087f`).
- Team home pages, posts and team search (`d10353c`).
- Stat undo history, game and tournament delete, bigger player tiles
  (`96cc7b4`).

## 0.0.4 — UltiUP home, personal schedule, privacy by role

Branch `feature/ultiup-schedule`.

**Added**
- UltiUP branding: logo, wordmark and the Barlow Condensed heading font.
- Team-first Home: a "This week" outlook, your team (or a join/create card),
  a playbook preview, "Coming up" events with a USA Ultimate toggle, and a
  2-1-3 rankings podium with ranks 4–10 and division chips.
- Personal schedule: add your own events (same types as team events).
  Owners, coaches and captains choose which schedule a new event goes on.
- Schedule tab: a week at a time, day by day, with All / Team / Personal
  filters. Team events are blue and personal events purple, with tags.
- Swipe right on the Schedule tab to delete, with a 4-second Undo.
  Personal events always; team events only for owners, coaches and captains.
- Workout and Scrimmage event types.
- Search USA Ultimate teams from the Teams tab (ranked teams, filter by
  ranking list) and open a team's page.
- Light / Dark / System theme setting on Profile, remembered on the device.
- App version shown on Profile.

**Changed**
- Events tab shows USA Ultimate tournaments only; team and personal events
  moved to Schedule.
- Profile opens from the avatar on Home instead of the bottom bar.
- Event pages open over the current tab, so back returns where you were.

**Security and privacy**
- Players see only names, numbers and positions on the roster. Paid and
  USA Ultimate status moved to `teams/{id}/rosterStatus`, readable by
  owners, coaches and captains only.
- The team invite code moved off the team record to
  `teams/{id}/private/invite` (owners, coaches and captains only). Join
  proofs moved to `teams/{id}/joins/{uid}` so the code no longer lingers on
  the team record. Older teams are migrated the first time an admin opens
  them.
- Personal events in `users/{uid}/events`, private to their owner.

**Fixed**
- New-event pages had no way back; a stale Roster page could hijack event
  links; personal events didn't show on Home.

**Infrastructure**
- USA Ultimate scraping Cloud Functions set to run every two months, but
  left undeployed: the app scrapes live on the device until the user base
  grows.

## 0.0.3 — USA Ultimate roster import

Branch `feature/roster-import`.

- Link a team to its USA Ultimate page by searching the rankings or pasting
  the link.
- Preview a roster sync, then apply it: new players added, numbers and
  positions updated, players missing from USA Ultimate flagged. Nobody is
  removed; players are matched by name.
- On/Not on USAU and an admin-set Paid mark per player, a confirmed count
  and an "Unconfirmed only" filter.
- Team page parser updated for USA Ultimate's real layout.

## 0.0.2 — Live stats and team roles

Branch `feature/stats-mockup`.

- Stats tab: tournaments as folders of games, lines of 7, live O/D tracking
  with a pull timer, subs, timeouts and a point log.
- Stat sheets with O efficiency, break rate and ratings, plus a glossary;
  season stats.
- Roles: owner, coach, captain and player, with stats access as an add-on
  the owner grants to players. Owners can transfer ownership; only the
  owner sets roles and regenerates invite codes.

## 0.0.1 — Team calendar and animated plays

Branch `feature/team-calendar-animated-plays`.

- Team Schedule tab: month calendar and upcoming list; owners and coaches
  create, edit and delete events.
- RSVPs (Going / Maybe / Can't go) with a no-reply list, emoji reactions and
  optional single- or multi-choice polls. Only members going may react or
  vote.
- Playbook animation steps: drag players to record cuts and the disc to
  record throws, then play them back with scrubbing, speed and captions.

## 0.0.0 — MVP baseline

Branches `main` and `development`.

- Sign in with email/password, Google and Apple.
- Teams with a roster, members and invite codes.
- Playbook with a drawable field editor.
- USA Ultimate tournaments, rankings and team pages.
- iOS release setup through Codemagic; the web target was dropped.
