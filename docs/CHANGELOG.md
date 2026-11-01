# UltiUP version log

Each feature branch bumps the version by one. The version lives in
`pubspec.yaml` (`version: X.Y.Z+N`, where `N` is the build number) and in
`appVersion` in `lib/ui/core/ui/brand.dart`; `test/version_test.dart`
fails if they drift apart or this log has no entry for the version.

Versions stay at `0.0.x` until the first App Store release. Codemagic
picks iOS build numbers on its own (see `docs/ios-release.md`).

| Version | Date       | Branch                                  | Commits             |
|---------|------------|-----------------------------------------|---------------------|
| 0.0.8   | 2026-10-31 | `feature/follows-feed`                  | (this branch)       |
| 0.0.7   | 2026-10-31 | `feature/community-groups`              | `9f19c55` and later |
| 0.0.6   | 2026-10-30 | `feature/team-videos`                   | `d623748` and later |
| 0.0.5   | 2026-10-30 | `feature/team-meetings`                 | `1b2e424` and later |
| 0.0.4   | 2026-10-29 | `feature/ultiup-schedule`               | `06830cc` and later |
| 0.0.3   | 2026-10-29 | `feature/roster-import`                 | `5620a1d`           |
| 0.0.2   | 2026-10-29 | `feature/stats-mockup`                  | `7556460`           |
| 0.0.1   | 2026-10-28 | `feature/team-calendar-animated-plays`  | `fd59d92`           |
| 0.0.0   | 2026-10-28 | `development` (MVP baseline)            | `090e7b4`–`04d4109` |

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

**Changed**
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
