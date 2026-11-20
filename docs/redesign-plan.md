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
   working); Teams tab opens a single team straight away (plan item 4;
   reversed by F34: the tab always shows the list);
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
| F3 | Event and poll cards posted into chat | chat | API — built (event cards); chat polls → F33 (built) |
| F4 | Video timestamped notes / clips | videos | data model + rules — built |
| F5 | Video comments | videos | data model + rules — built |
| F6 | Tag a video to a game | videos | data model — built |
| F7 | Note on an RSVP | schedule | data model + rules |
| F8 | Audience picker on posts (Everyone / followers / a team) | posts | verified (product-spec §8.1 item 40): Everyone and a team you manage on both platforms; Followers not built (decision 25) |
| F9 | Learn progress ("3 of 9 read") | learn | local per device (shared `learnLessons`) — built |
| F10 | Spots left on tournament lists | tournaments | API `spots` on the public list, from division caps — built |
| F11 | Blocked accounts list in Privacy | settings | verify block feature — not built: blocking doesn't exist yet; design note waiting for approval |
| F12 | "Public team page" switch | team settings | verify; rules — built (app + web): `publicPage` on team + listing, `PUT /v1/teams/:id/public-page`, rules + public reads honour it |
| F13 | Email notifications (beside push) | settings | email provider + secret |
| F14 | Download your data | account | API export — built (app + web): `GET /v1/me/export` JSON, once per 10 min |
| F15 | Discord import: pick channels | teams | app + web — built (both platforms already had the template import; picker on both, shared `pickRooms`; no API change) |
| F16 | Schedule month view | schedule | app only |
| F17 | Meetings list screen | meetings | app only |
| F18 | Team quick stat tiles (going, new in chat, record) | team page | app + web — built (going + new in chat; no record: results aren't cheap to read) |
| F19 | Visitors search Discover without signing up | web | product decision |
| F20 | Clinic event type (shown as "Soon") | host chooser | later |

| F21 | New teams start simple: sections off by default, role presets, one Host button (team-first item 6) | teams | shared + API + rules |
| F22 | Team header: compact (actions row in header, no tall banner) | team page | app + web |
| F23 | Roster: role on rows, O/D line grouping, "Edit lines", invites pending | roster | data model — built (app + web): `line` on roster spots via `PUT /v1/teams/:id/roster-lines`; `GET`/`DELETE /v1/teams/:id/invites` |
| F24 | Posts: pinned posts, comment counts, inline "Post to the team" box | feed | API — built (app + web): pins (3 a team, swap) and comments on team posts, API-only; `commentCount` by the `follows` functions; product-spec §8.1 item 40 |
| F25 | Roles: preset list + per-person permission switches | roles | rules — built (app + web): presets (Member, Stat keeper, Captain, Coach, Admin; groups: Member, Moderator, Organizer, Admin) + a switch per permission, "Custom" when no preset matches; owner only, `memberGrants` via `PUT /v1/teams/:id/members/:uid/permissions`; product-spec §8.1 item 41 |
| F26 | Team join requests (communities have them today; teams don't) | teams | API + rules — built (app + web): "Allow join requests" (off by default) via `PUT /v1/teams/:id/allow-join-requests`; Request to join / Cancel; approve runs the club age rule; pushes to admins and on approval; product-spec §8.1 item 42 |
| F27 | Community page: RSVP on the next pickup card, chat + organizers sections | community | app + web — built (no new data or API: next-event card with the schedule's RSVP, Chat rooms with unread dots, Organizers with Message; product-spec §8.1 item 44) |
| F28 | More: row subtitles, Manage group, Leave button | team More | app + web — built |

| F29 | App Discover lists public team events (pickup games) via `/v1/public/events`, as the web does | discover | app — built |
| F30 | Tournament extras: standalone bracket page, stepper score entry, week stepper for leagues, full-screen enter-a-team, form wizard with Save draft / Publish, Share | tournaments | app + web — built (product-spec §8.1 item 35) |

| F31 | Playbook whiteboard mode: a switch on the playbook page between Plays and Whiteboard. Whiteboard = a blank field to sketch freely (pen, colours, players/disc/cones, eraser, undo, clear), for chalk talks; can be saved as a play (or as a whiteboard) or thrown away | playbook | app + web (+ data if saved) — built |

| F33 | Polls posted into chat (a standalone poll; event polls live inside events and need RSVP "going", so F3 shipped event cards only) | chat | shared + API + app + web — built (votes on the message, API-only, no rules change; not anonymous; product-spec §8.1 item 39) |
| F34 | Teams tab always opens the Your teams list, even with one team (user, 2026-11-20; reverses the redesign 2 "opens your only team" shortcut, `useSingleTeam` on web) | navigation | app + web — built (product-spec §8.1 item 37) |
| F35 | "Add to calendar" adds the event to a calendar the person picks instead of only downloading an .ics (user, 2026-11-20). App: native calendar insert (e.g. `add_2calendar` / device calendar picker); web: menu with Google Calendar / Outlook links plus .ics for Apple | schedule | app + web — built (`add_2_calendar` native editor, .ics fallback; shared `calendar_links.ts`; product-spec §8.1 item 37) |

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
12. **F30: app links for tournaments.** The app doesn't claim
    `/tournaments/` links (AndroidManifest/AASA list only `/join`, `/g`,
    `/p`), so a shared tournament link opens the website. Claim them so
    the app opens its own page?
13. **F30: week numbering.** The navy header's "Week N of M" counts
    calendar weeks; the new league week stepper counts game nights, so
    they differ after a skipped week. Make the header count nights too?
14. **F30: Share on a private group's event** shows a link visitors
    can't open (members-only prompt). Hide Share there?
15. **F30 (fixed, no decision needed):** on the website a failed
    Publish of a new event used to open the draft without the error; it
    now stays on the form showing the error and the next save updates
    the draft it created (as the app does).
16. **F4–F6 video notes/comments, as built:** no per-video cap (page
    shows the newest 500; adding is rate-limited like chat); notes and
    comments can be deleted but not edited; only comments push (to the
    video's author), notes don't. The website's video page now plays
    YouTube through YouTube's IFrame API so notes can seek (falls back to
    the plain embed). OK as is?
17. **F35 iOS contacts string.** `add_2_calendar`'s README says the
    iOS event editor's location autocomplete can crash without
    `NSContactsUsageDescription`, so Info.plist now has "Suggest places
    when you add an event to your calendar." App Review sees it. Keep?
18. **F35 on iOS 15–16:** if someone refuses calendar access, the plugin
    can't tell that from Cancel, so nothing happens (no .ics offered).
    Accept, or show a "Use a file instead" snackbar after a cancel?
    Also to try on a real device: the editor on iOS 17+, Android's insert
    screen, and the website's Google/Outlook links from a non-UTC zone.
19. **F23 lines and older app builds.** An app build from before roster
    lines rewrites the whole roster spot when an admin edits a player, so
    the rules let a client drop a spot's line (never set or change one):
    editing a player from an old build clears their line. Accept, or
    refuse such writes (old builds then can't edit a player who has a
    line)?
20. **F23 invites pending** lists only invites sent after this change
    (they now carry `teamId`); older pending invites don't show until
    re-sent. Backfill them with a one-off script, or let them age out?
21. **F18 record tile** left out: no cheap source of a team's W–L (stats
    games are large documents; tournament results are per division).
    Want one kept on the team doc (updated when a game is finalised)?
22. **F33 anonymous polls** aren't built: votes sit on the poll's
    message, which everyone in the room reads, so "See votes" shows who
    picked what. Anonymous polls would need votes kept elsewhere (a
    server-only store with counts on the message). Want them?
23. **F33 votes after leaving a team** stay on the polls (as RSVPs do);
    deleting the account removes them. Remove a member's votes when
    they leave or are removed too?
24. **F24 team post comments, as built:** members only (even on public
    posts; outsiders see no count), flat (no replies), no likes, no
    editing, no pushes; the author or a team admin deletes. Want likes,
    or a push to the post's author ("<team>: <name> commented on your
    post", as video comments do)? Counts read "Comment" until the
    `follows` functions are deployed (new posts count from then on;
    nothing to backfill, since team posts had no comments before).
25. **F8 "Followers" audience: not built.** Both platforms offer
    Everyone or a team; a per-post "Followers only" needs more than a
    field: the create rule ties `private` to the profile, both `follows`
    functions (`postPrivacy`, `profilePrivacy`) restamp it from the
    profile, the API's public pages hide posts by the author's profile
    (not the post), and the app's multi-author queries and the API
    feeds ask for `private == false`, so followers of a public profile
    would miss such a post unless every feed reads followed authors one
    at a time. Proposed: an `audience: "followers"` field that can't
    change after posting; `private = profile private || followers`, kept
    by the rule and both functions; the API's public pages and feeds
    check the post's flag; followers' feeds add one query per followed
    author who posts followers-only (or move feeds behind the API).
    Build it? Also: "a team" in the picker means only teams you manage
    (admins post for a team); should members post to their team too?
26. **F24 "New post" buttons:** the app's New post buttons (the phone's
    floating button and the wide screen's header button) are replaced by
    the "Post to the team…" box at the top of the posts. On a phone the
    posts come after Coming up and the members card, so the box is
    further down than the floating button was. Keep it, or bring the
    floating button back beside the box?
27. **F25 who sets permissions:** only the owner, as only the owner edits
    roles. Should admins with Manage members set them too (never above
    their own, never on the owner)? The API refuses a legacy coach's or
    captain's switches (412: "make them a player first"), since their tier
    already grants more.
28. **F25 no Treasurer preset:** there's no payments permission yet, so a
    Treasurer would be a Member. Add one when payments land?
29. **F25 old app builds:** an older build that saves roles or migrates
    tiers recomputes `memberPerms` without the person's own permissions,
    which takes them away (never gives extra) until the next save from a
    new build or the API. An old build with no API can't remove a member
    who has their own permissions (the rule wants `memberGrants` cleared).
    Fine for dev; ship the new builds before prod.
30. **F26 default off:** "Allow join requests" starts off on every team
    (invite-only stays the norm). Turning it off declines (deletes) the
    requests waiting, after a confirm. Keep both?
31. **F26 approval push:** "You're in: <team>" goes to the requester when
    their request is deleted and they're now a member, so it also fires
    if they joined some other way (an invite) while a request waited.
    Acceptable, or approve-only?
32. **F26 groups notify all approvers now:** a new request (group or
    team) pushes to the owner, coaches and captains, and everyone with
    Manage members, not just the owner as groups did before. OK?
33. **F26 caps and bans:** approval runs the same server checks as any
    join: already a member, the flood mute and the club age rule (16+,
    birth date needed). There are no team size caps or bans anywhere in
    the product yet, so there's nothing more to check. Want either?
34. **F15 was "app only", built on both.** The website already had the
    Discord template import (Settings, through the API), so parity meant
    adding the channel picker there too; no web Discord import decision
    is needed. As built: only text channels are picked (roles always all
    come across; voice channels are skipped as before); a category whose
    channels are all unticked isn't made, but one that has no channels in
    the template still is. Want roles pickable too, or empty categories
    left out?
35. **F27 stat tiles on a community page.** The next pickup card now
    shows the Going count and answers, and the Chat section marks unread
    rooms, so a community member's "N going" and "N new in chat" tiles
    repeat both. Kept them (item 38); drop the tiles on communities?
36. **F27 who counts as an organizer:** the owner, a coach or captain
    tier, and anyone with Manage team, Manage members or Manage events.
    A Moderator (Manage chats + Moderate only) isn't listed. Include
    moderators, or narrow it to Admin and Organizer presets only?
37. **F27 the card on a school or club** reads "Next event" / "No
    events scheduled" (their events are of every kind); a pickup
    community's reads "Next pickup". It shows the next event of any type
    the member can see, not only pickup games. OK?

## Status (2026-11-20, evening)

- On `development`: the restyle (app 0.0.36, web 0.45.0) and the first
  feature batch (app 0.0.37, web 0.46.0, api 0.34.0; deployed to dev).
- Second batch committed and pushed to `development` (app 0.0.38, web
  0.47.0, api 0.35.0) after a full check run: F30 tournament extras,
  F4–F6 video notes/comments/tags, F34 Teams tab list, F35 Add to
  calendar, F18 stat tiles, F23 roster lines + invites pending, F28 More
  subtitles, F33 chat polls, F24 pinned posts + team post comments, F8
  verified (Followers not built, item 25), F25 role presets, F26 team
  join requests, F15 Discord channel picker, F27 community page.
- Deployed to dev for batch 2: Firestore rules and indexes only.
  Waiting for the user's OK: the API (0.35.0) and functions groups
  `notifications`, `follows`, `communities`, `account`, `browse`. Until
  then the new API-backed features (video notes, polls, pins, roster
  lines, permissions, join requests) fail on dev.
- Left: F11 blocking (needs approval, item 10), F32 team colours (item
  4), F8 Followers audience (item 25); F13 email and F20 clinics are
  out for now. Decisions 1–37 above.
