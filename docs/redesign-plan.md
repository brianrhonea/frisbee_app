# Redesign plan ("Turf & Disc")

Mockups: the private canvas "Stall 10 hub redesign"
(https://claude.ai/artifact/MDRhhxToR9MRdmq9W5WUgf), every app screen
and web page in light and dark. Shared spec for the mockups:
`DESIGN_SPEC.md` (copied below in short).

Branch: `feature/redesign` (from `feature/team-first`).

## Rules for the build

- The existing screen and its tests define the features; the mockup is
  only the look. Never drop a field or action because a mockup lacks it
  (mockups show the top of each screen and simplified some forms).
- Restyle in place. Change test finders only for intentional renames.
- Shared files are edited by the lead only: `theme.dart`, `routes.dart`,
  `router.dart`, `app_shell.dart`, pubspec, versions, changelogs.
- No directory-wide `dart format`; keep CRLF; no commits by subagents.
- Each subtask: `flutter analyze` + that area's tests. Full suites when
  the build is ready.
- Parity (CLAUDE.md): look-only changes can be per platform; navigation
  changes and new features land on web too (see "Parity" below).

## Visual language

- Turf green = actions, links, selected. Scoreboard navy = live/today.
  Disc amber = only "yours to do" (Report score, RSVP needed, unread).
  Red = only live games. Team blue / personal magenta = event types.
- Inter + Barlow Condensed 800 (scores, big numbers, date badges,
  wordmark). Radii: cards 16, controls 12, chips 999.

| token | light | dark |
|---|---|---|
| bg | #F5F6F1 | #0B121D |
| card | #FFFFFF | #152030 |
| field | #EEF0EA | #1B2838 |
| line | #E1E4DC | #24324A |
| line2 | #D5D9CF | #2E3D55 |
| ink | #0F1A2A | #EAF0F5 |
| ink2 | #3B4352 | #C4CDD8 |
| muted | #5E6573 | #93A0B2 |
| turf | #12805C | #3DBE8B |
| onTurf | #FFFFFF | #06281B |
| turfSoft | #E3F2EA | #133528 |
| turfInk | #0B5E43 | #7FDDB4 |
| board | #0F1A2A | #1A2940 |
| onBoard | #FFFFFF | #FFFFFF |
| boardMuted | #B7C0CE | #A9B6C8 |
| board2 | #22324A | #26385A |
| disc | #FFB627 | #FFC24D |
| onDisc | #2A1B00 | #2A1B00 |
| discSoft | #FFF1D1 | #3A2C0E |
| discInk | #8A5A00 | #FFC24D |
| live | #D93636 | #FF5A5A |
| liveSoft | #FDE7E7 | #3A1A1E |
| liveInk | #B42323 | #FF8A8A |
| team | #2C6FB7 | #7FB0EE |
| personal | #A8407A | #E08BB8 |

## Subtasks (one at a time, each ends testable)

1. **Foundation** (lead): palette + new tokens in `AppColors`, Barlow
   Condensed asset, radii, shared widgets (scoreboard card, section
   header, live pill, date badge, stat tile, team dot), clear hardcoded
   colours, nav labels Discover / Schedule / Inbox. Light + dark
   screenshots.
2. **Navigation**: Discover merges Explore + Find events (old routes keep
   working); Teams tab opens a single team straight away (plan item 4);
   lighter feed with "Your teams" default (plan item 5). Web too.
3. **Restyle by area** (one subagent each, no new features):
   a. Tournaments & leagues  b. Teams & communities  c. Schedule &
   meetings  d. Inbox & chat  e. Home, Discover, profiles, notifications
   f. Sign in & settings  g. Playbook & videos  h. Hat drafts & stats.
4. **New features**, one vertical slice each (shared schema → API/rules →
   app → web → tests). See the inventory.

## New-feature inventory (drawn in the mockups, not in the code)

| # | Feature | Where | Needs |
|---|---|---|---|
| F1 | Live running scores (captains update mid-game) | tournaments | shared + API + rules — built |
| F2 | Pinned messages in chat rooms | chat | API (team rooms; no rules change) — built |
| F3 | Event and poll cards posted into chat | chat | API — built (event cards); chat polls → backlog F33 |
| F4 | Video timestamped notes / clips | videos | data model + rules |
| F5 | Video comments | videos | data model + rules |
| F6 | Tag a video to a game | videos | data model |
| F7 | Note on an RSVP | schedule | data model + rules |
| F8 | Audience picker on posts (Everyone / followers / a team) | posts | verify; maybe API |
| F9 | Learn progress ("3 of 9 read") | learn | local per device (shared `learnLessons`) — built |
| F10 | Spots left on tournament lists | tournaments | API `spots` on the public list, from division caps — built |
| F11 | Blocked accounts list in Privacy | settings | verify block feature — not built: blocking doesn't exist yet; design note waiting for approval |
| F12 | "Public team page" switch | team settings | verify; rules — built (app + web): `publicPage` on team + listing, `PUT /v1/teams/:id/public-page`, rules + public reads honour it |
| F13 | Email notifications (beside push) | settings | email provider + secret |
| F14 | Download your data | account | API export — built (app + web): `GET /v1/me/export` JSON, once per 10 min |
| F15 | Discord import: pick channels | teams | app only |
| F16 | Schedule month view | schedule | app only |
| F17 | Meetings list screen | meetings | app only |
| F18 | Team quick stat tiles (going, new in chat, record) | team page | app only |
| F19 | Visitors search Discover without signing up | web | product decision |
| F20 | Clinic event type (shown as "Soon") | host chooser | later |

| F21 | New teams start simple: sections off by default, role presets, one Host button (team-first item 6) | teams | shared + API + rules |
| F22 | Team header: compact (actions row in header, no tall banner) | team page | app + web |
| F23 | Roster: role on rows, O/D line grouping, "Edit lines", invites pending | roster | data model |
| F24 | Posts: pinned posts, comment counts, inline "Post to the team" box | feed | API |
| F25 | Roles: preset list + per-person permission switches | roles | rules |
| F26 | Team join requests (communities have them today; teams don't) | teams | API + rules |
| F27 | Community page: RSVP on the next pickup card, chat + organizers sections | community | app + web |
| F28 | More: row subtitles, Manage group, Leave button | team More | app + web |

| F29 | App Discover lists public team events (pickup games) via `/v1/public/events`, as the web does | discover | app — built |
| F30 | Tournament extras: standalone bracket page, stepper score entry, week stepper for leagues, full-screen enter-a-team, form wizard with Save draft / Publish, Share | tournaments | app + web |

| F31 | Playbook whiteboard mode: a switch on the playbook page between Plays and Whiteboard. Whiteboard = a blank field to sketch freely (pen, colours, players/disc/cones, eraser, undo, clear), for chalk talks; can be saved as a play (or as a whiteboard) or thrown away | playbook | app + web (+ data if saved) — built |

| F33 | Polls posted into chat (a standalone poll; event polls live inside events and need RSVP "going", so F3 shipped event cards only) | chat | shared + API + app + web |

Web parity follow-ups from the app restyle (do in W4 or sooner):
- Live tournament days open on the Schedule tab (app 3a).
- Host checklist title "Next steps"; host chooser "What are you hosting?" /
  "Host as", order Tournament · League · Hat; Teams tab "Accept
  applications above"; publish card shows games as a stat.

Decisions (user, 2026-11-19):
- Parity: each navigation change and new feature ships on app and web
  together; the restyle itself goes app first.
- New teams start with only Feed, Schedule, Chat and Roster; Playbook,
  Videos, Stats and Meetings off by default (owners turn them on).
- F19 yes: visitors can search Discover; player search stays signed-in.
- F1 live running scores: build it.
- F13 email notifications: not now (no provider). Leave out of the UI.

Additional mockup-only items from the web team hub (W3): team Visibility
switch, section on/off switches in team settings, roster Status column,
chat reactions/pins panel, team schedule List/Calendar toggle.

Also fix in the real app: the sign-up details intro still mentions
USA Ultimate membership.

## Parity

Restyle subtasks are per platform (each keeps its own design). Subtask 2
and every F-slice include the website. The web restyle follows once the
app restyle is done.

## Waiting for you (decisions collected overnight)

1. **Form error colour.** The playbook/video restyle (3g) turned the video
   editor's link/file warnings and the >90% storage bar amber ("yours to
   fix") instead of the theme's red. Every other form still shows field
   errors in red. Pick one for the whole app: red for errors (red then
   means "live" or "error"), or amber for anything you need to fix.
   Same question for destructive confirm buttons (`confirmDialog(destructive:
   true)`: delete post, clear notifications, discard workout), which are
   are now solid ink (dark) instead of red, and event-type colours are turf
   (field time) or neutral (other). Until decided: left as 3g did it.
2. **Play diagram colours.** 3g changed defence players from red to navy
   (so diagrams don't use the live red) and nudged offence blue and the
   cone orange. Kept; say if you want the old red/blue.
3. **App vs web: public pickup games.** The website's Discover lists
   public team events (pickup games) from `/v1/public/events`; the app's
   doesn't (F29 adds it to the app). Done: F29 built (product-spec
   §8.1 item 34).


4. **Team colours.** Team badges now show initials coloured by kind (team
   blue, pickup community turf, school/club navy). The mockups give each
   team its own colour, which needs a team colour field (owners pick one).
   Add it? (backlog F32)

5. **Logo.** `apps/web/public/logo.png` (and the app icon) is still the old
   purple "10" mark; the wordmark is now the italic condensed STALL 10.
   A new mark in turf/navy needs your design call (or a designer).
6. **Team chat bubbles.** Team rooms show messages as rows (both
   platforms, as the mockups do); only direct messages use bubbles.
   Say if you want bubbles in team rooms too.
7. **development pushed.** `development` was fast-forwarded to
   `feature/redesign` (app 0.0.36, web 0.45.0) on 2026-11-20 — that
   also brought in `fix/ui-wording`, `feature/profile-team-stats` and
   `feature/team-first`, which weren't on development before.

8. **Old app builds and RSVP notes.** Under the new rule, an app build
   older than the one with RSVP notes can't take back an answer that has
   a note (it doesn't delete the note). Only matters for TestFlight
   testers who don't update; fine to accept?
9. **Sections are display only.** A section switched off (F21) is
   hidden, but the server doesn't refuse playbook/video/stats writes and
   deep links still open. Enforce server-side too?

10. **F11 blocking: not built — needs your approval.** There is no block
    feature anywhere yet. Proposed (your 'full block' decision): block docs
    `users/{uid}/blocks/{other}` (owner-read, API-written) + a mirrored
    `blockedBy` lookup for rules; PUT/DELETE/GET `/v1/me/blocks`. A block
    stops DMs both ways, removes follows both ways and refuses follow
    requests, hides each other's posts/comments/likes, stops mentions and
    pushes; shared teams keep working. Hard part: feeds and comments are
    read straight from Firestore, so hiding them per viewer means either
    `exists()` checks on every read (costly; list queries can't filter) or
    moving those reads behind the API. Then Settings › Privacy › Blocked
    accounts on both platforms. Go ahead, and which read approach?
11. **Public page off also hides from public tournaments/rankings.** A
    team that turns its public page off (F12) is treated like a private
    group for signed-out visitors: its hosted public tournaments and its
    ranking rows disappear for them too. Keep, or limit the switch to the
    team page only (one line in `apps/api/src/browse/visibility.ts`)?

## Status when the overnight run stopped (2026-11-20)

- Committed and pushed to `development`: the full app + website restyle
  (app 0.0.36, web 0.45.0).
- Committed on `feature/redesign` (app 0.0.37, web 0.46.0, api 0.34.0,
  2026-11-20) after a full check run: F1 live scores, F21 start simple,
  F31 whiteboard, F7 RSVP notes, F16 month view, F17 meetings list, F2
  pins, F3 event cards, F12 public page switch, F14 download data, F9
  Learn progress, F10 spots left, F29 app pickup games.
- Next: deploy to dev in this order:
  Firestore + Storage rules → API → functions groups `notifications`,
  `browse`, `tournaments`, `account` (ask first), then merge to
  `development`.
- Not started: F4–F6 videos, F8 audience picker, F15 Discord channels,
  F18 team stat tiles, F22 done, F23 roster lines, F24 pinned posts,
  F25 role presets, F26 team join requests, F27 community page, F28
  More subtitles, F30 tournament extras, F11 blocking (needs approval),
  F33 chat polls.
