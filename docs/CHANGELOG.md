# UltiUP version log

Each feature branch bumps the version by one. The version lives in
`pubspec.yaml` (`version: X.Y.Z+N`, where `N` is the build number) and in
`appVersion` in `lib/ui/core/ui/brand.dart`; `test/version_test.dart`
fails if they drift apart or this log has no entry for the version.

Versions stay at `0.0.x` until the first App Store release. Codemagic
picks iOS build numbers on its own (see `docs/ios-release.md`).

| Version | Date       | Branch                                  | Commits             |
|---------|------------|-----------------------------------------|---------------------|
| 0.0.5   | 2026-10-30 | `feature/team-meetings`                 | `1b2e424` and later |
| 0.0.4   | 2026-10-29 | `feature/ultiup-schedule`               | `06830cc` and later |
| 0.0.3   | 2026-10-29 | `feature/roster-import`                 | `5620a1d`           |
| 0.0.2   | 2026-10-29 | `feature/stats-mockup`                  | `7556460`           |
| 0.0.1   | 2026-10-28 | `feature/team-calendar-animated-plays`  | `fd59d92`           |
| 0.0.0   | 2026-10-28 | `development` (MVP baseline)            | `090e7b4`–`04d4109` |

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
