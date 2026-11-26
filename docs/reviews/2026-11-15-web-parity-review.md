# feature/web-parity: full review checklist (2026-11-15)

Scope: everything on `feature/web-parity` since `e75bc21` (79 commits, ~355
files), at `92eb2bf` (api 0.24.0, web 0.28.0, app 0.0.23). Four read-only
reviews: API + shared, website code, app + parity, website UI. CONFIRMED =
the code path was read; PLAUSIBLE = inferred. Nothing here is fixed yet.

## 1. Fix first (bugs users would hit)

- [ ] **Meeting call keeps running after access is lost** (web, High, CONFIRMED).
  `apps/web/components/team/meetings/MeetingRoom.tsx:261` (and 137-142): if the
  viewer signs out in another tab, is removed, or loses `canSee`, the page
  switches to "members only" with no hang-up while mic/camera stay live. Hang
  up when `member` goes null or `canSee` fails, as `VoiceProvider.tsx:229` does.
- [ ] **Home feed silently drops posts** (API, High, CONFIRMED).
  `apps/api/src/me/service.ts:134-136`: `more` is true only if one source
  returned a full page; three short sources can merge past 20, the page is cut
  and `next` is null. Use `more = merged.length > feedPageSize || anyFull`.
- [ ] **Hosted game confirm doesn't check the score** (API, Med, CONFIRMED).
  `apps/api/src/tournaments/service.ts:760`: the rule's
  `d.scoreA == g.report.scoreA` (`firestore.rules:1751`) isn't ported, so a
  re-filed report is confirmed unseen. Take `{scoreA, scoreB}` and compare (as
  `group_tournaments/service.ts:378`); send it from `TournamentGames.tsx:171`.
- [ ] **Upload complete vs delete race** (API, Med, CONFIRMED).
  `apps/api/src/media/service.ts:214, 293, 348`: status read outside a
  transaction, then a blind update: a concurrent `DELETE /v1/uploads/:id` is
  undone (orphaned file) and two completes both run. Re-read in the final
  transaction; if not pending, clean up.
- [ ] **Deleting a team strands its hosted tournaments** (API, Med, CONFIRMED).
  `apps/api/src/teams/deletion.ts:79`: tournaments with that `hostId` can then
  never be edited or deleted. Refuse while it hosts unfinished events, or
  cascade. Check the app's delete too.
- [ ] **Home "Upcoming events" can be empty for community members** (API, Med,
  CONFIRMED). `apps/api/src/me/service.ts:85-87` reads 5 per team before the
  audience filter, and skips events already under way. Over-read, filter, cut.
- [ ] **Post page spins forever** on any non-404 error (web, Med, CONFIRMED).
  `apps/web/components/PostPage.tsx:44,57`. Add an error state with retry.
- [ ] **Stats game page never shows its error** (web, Med, CONFIRMED).
  `apps/web/components/team/stats/GamePage.tsx:57`: check `error` before `!loaded`.
- [ ] **App voice join race** (app, Med, CONFIRMED by reading).
  `apps/mobile/lib/data/repositories/voice/voice_repository_livekit.dart:94-95`:
  `++_attempt` after `await _hangUp()`, so switching channels quickly can land
  you in the first one and leak watchers (`_watch` ~141 doesn't cancel old
  ones). Bump before the await; cancel watches first. Also: a null team drops
  at once while a null room waits for `everSeen` (~160-170), and a clean
  `onDone` never resubscribes (~270-300).
- [ ] **App drafts can be lost at sign-in** (app, Low, PLAUSIBLE).
  `message_draft_repository.dart`: a save before the load finishes overwrites
  stored drafts. Await the load before the first write.

## 2. Parity gaps (web vs app)

- [ ] **Home "Community" tab is website-only** (High, CONFIRMED).
  `apps/web/components/Dashboard.tsx:21-25` vs the app's two tabs
  (`home_screen.dart:371`). Spec §8.1 item 7 says feed tabs are done. Decide:
  add Community to the app's Home, or drop it from the website.
- [ ] **Inbox search is app-only** (Med). `inbox_screen.dart:308`; the
  website's `Messages.tsx` has no search. Add a filter box.
- [ ] **Delete team: typed name on web, plain confirm in the app** (Med).
  `TeamSettings.tsx:383-417` + API `deletion.ts:58` vs
  `team_home_screen.dart:293`. And the app deletes client-side with its own
  subcollection list (`team_repository_firebase.dart:813-900`) instead of
  `DELETE /v1/teams/:id`; lists can drift. Move the app to the API.
- [ ] **Groups and communities can't invite by name on the website**
  (PLAUSIBLE): `TeamRosterView.tsx` `canInvite` needs `kind === "team"`, while
  the app shows "Invite members" on every team home (`team_home_screen.dart:1231`).
- [ ] **Limits enforced only by the API while the app still writes directly**:
  chat rooms 200 / folders 50 (`shared/hub.ts:184`), roster 500, calendar
  events 300; the website-only daily chat-upload quota. Add to rules or
  migrate the app writes.
- [ ] **Draft order tie-break**: `PlayerSignup.compareByName` /
  `signupOrder` have no tie-break; Dart's sort is unstable over 32 items. Tie
  on uid in both and add a fixture.
- [ ] **Website-only, decide**: keyboard shortcuts and URL state (fine as web
  design), `/events` (contents not compared with the app's Find events), the
  Meetings tab (meetings are on both schedules).
- [ ] **Remove follower**: `DELETE /v1/me/followers/:uid` has no caller on
  either platform. Build it on both or remove it.
- [ ] **Already known "not yet"** (spec §8.1): video in posts, video upload
  from the website, website payments, GPS workouts (app only), Explore player
  rows (team/school/hometown), personal events in home's Upcoming card, adding
  a team event from My schedule on the website.

## 3. Other logic and robustness

- [ ] **Unbounded listeners/reads** (web, Med): `Messages.tsx:93-94` (all
  conversations), `TeamSchedule.tsx:70-72` (all past events, sliced to 50),
  `meetings/model.ts:71` (admins read every meeting), `stats/data.ts:47,53,60`,
  `useForYou.ts:74` and `FollowingSettings.tsx:41` (all follows),
  `TeamVideos.tsx:38`, `WatchTogether.tsx:44`, `drafts/data.ts:97,101`,
  `CommunityAdmin.tsx:76`, `TournamentEditor.tsx:40`. Add limits/windows, page
  the past.
- [ ] **Unrated expensive API reads** (Med): `GET /v1/teams/:id/roster` (up to
  ~1,000 profile reads, no limit; C5 in the earlier review), `/v1/posts/state`,
  `/v1/me/calendars`, `/v1/me/calendar-events`. Per-caller read bucket; `getAll`.
- [ ] **`reconcile` reads everything** (API, Med): `tournaments/service.ts:833`
  reads every entry, game and division in one transaction, 20×/min per
  manager. Query by `divisionId`; `DocQueries.fields()` needs a `where`
  (`queries.ts:17`).
- [ ] **Non-chat video uploads never finish** (API, Low): they queue
  `transcodeJobs` but no job exists. Reject until it ships.
- [ ] **Transactions with reads outside them** (API, Low): drafts
  (`drafts/service.ts:228,290`), Discord counts (`discord/service.ts:204,276`).
  Closing a division deletes at most 400 games (`tournaments/service.ts:332`).
  Group tournament `save()` demotes `done` (`group_tournaments/service.ts:281`).
- [ ] **Misleading error codes** (API, Low): Discord unreachable → 500 (no
  `unavailable` code); missing team → permission_denied
  (`discord/service.ts:82,147`); `stats/service.ts:238` wording.
- [ ] **Dates without an offset** accepted by `isoDate` in `shared/hub.ts:91`,
  `meetings.ts:189`, `stats.ts:251` (UTC on Cloud Run). One shared,
  offset-required `isoDate`.
- [ ] **Fake store allows reads after writes** (`apps/api/test/fakes.ts:150`);
  real Firestore rejects them. Make the fake throw.
- [ ] **Web small ones** (Low): `Composer.tsx:153` object URLs not revoked;
  `?c=` and route ids not validated (`Messages.tsx:97`); `Messages.tsx:140`
  keydown effect re-registers every render; `useForYou.ts:193` error leaves
  `loaded` false; `PlayerPage.tsx:46` signal key; `TeamRosterView.tsx:29` no
  cancel/refetch; `TeamContext.tsx:101` any error = outsider;
  `PersonalGate.tsx:51` stale response; sign-in return paths drop context
  (`settings/layout.tsx`, signups `?division`, `TeamNav.tsx:161`);
  `Dashboard.tsx:106` drops `?tab=`; `AppFrame.tsx:39,75` shortcut targets.
- [ ] **Missing pieces** (web, Low): post page says "see replies in the app" to
  members too (`app/posts/[postId]/page.tsx:44`); entry fee shows with no pay
  action (`PlayerSignups.tsx:169`); `UpcomingAside.tsx:36` tournament rows go to
  `/events`; `?event=` for a past event opens nothing (`TeamSchedule.tsx:141`);
  `/teams/:id/stats`, `/plays`, `/videos`, `/tournaments` have no index (404).
- [ ] **Docs out of date**: ARCHITECTURE.md:416 row 9 has no status; spec §8.1
  W2 still lists custom roles / rooms / voice as "not yet"; W5 not marked built.

## 4. Redundant or unneeded code

**App**
- [ ] Flutter-web member site (~3,700 lines) can't be built any more but is
  still compiled and tested: `lib/main_web.dart`, `lib/routing/web_router.dart`,
  `lib/ui/web/`, `lib/ui/browse/`, `lib/data/repositories/browse/`,
  `test/ui/web_test.dart`, `kIsWeb` branches in 10 files. With it go the six
  `browse-*` Cloud Functions (only that code calls them) once the last Hosting
  deploy is retired, and `firebase/scripts/build_site.sh`'s Flutter step.
- [ ] Desktop leftovers after `windows/`/`macos/` were removed:
  `google_desktop_oauth.dart` (+ `auth_service.dart:13-20,112`),
  `PlatformSupport.desktopGoogleSignIn`, Windows options in
  `firebase_options.dart:63`, `app_check.dart:21`, desktop branches in
  `meeting_call_livekit.dart:66-88` and `message_thread_view.dart:676`.
- [ ] `lib/ui/core/ui/win_colors.dart` (unused); `mock_stats_repository.dart`
  (tests only → `test/testing/`).
- [ ] USA Ultimate remnants: `_legacyStatusKeys ['onUsau','paid']`
  (`team_repository_firebase.dart:127,968`), `Follow.isKnown` for old `event`
  follows. One-off data clean-up, then delete. `migrateTiersToRoles` once all
  teams are migrated.

**API / shared / functions**
- [ ] Two TypeScript ports of the tournament engine: `shared/group_tournaments.ts`
  (`groupEngine`) and `shared/tournament_engine.ts` (~35 same functions). Merge
  into one with thin adapters (the shared fixtures make this safe).
- [ ] Duplicated access rules: `media/service.ts:116 checkRoom` vs
  `hub/access.ts:24 canWriteRoom`; `me/service.ts:23 seesEvent` vs
  `hub/access.ts:28`; "stats counts as player" in five places.
- [ ] Helper copies: `parse<S>()` ×14 and the "too fast" limiter closure ×14
  (→ `parseBody`, `limited()`); `clip` ×3 (+2 variants); `safeId` ×3;
  `mapOf/asMap/isMap` ×6; `validId` ×2; `isoDate` ×6.
- [ ] Server copies to keep in step: `api/src/browse/model.ts` vs functions';
  `discord/template.ts` in both; draft logic in shared + functions.
- [ ] Unused shared exports: `eventReactionEmoji`, `meetingInvitees` (tests
  only), `entryActive`, `hasPools`, `gameStageLabels`, `planEndsAt`, ~25
  request/input type aliases. `ChatAdmin` built twice in `app.ts:174-175`.

**Website**
- [ ] Delete `components/ListingCard.tsx`, `lib/client.ts:21 getPublicInBrowser`,
  `lib/theme.ts:18 currentTheme`, `team-draft/[divisionId]` redirect page,
  probably `app/home/page.tsx`, `draftHrefs.signups` and its stale comments;
  `SignupsSlot.tsx` unused `uid` prop, nested `MembersOnly`, hand-built draft links.
- [ ] Dead CSS in `app/app.css`: `.post-repost`, `.profile-head`,
  `.settings-who`, `.video-file`.
- [ ] Duplicates: `startOfToday` ×4 (+`midnight`), `toLocalInput` ×3
  (+`localInput`), ad-hoc date formatting in 15 files with mixed locales, the
  "my teams" query ×8 (`useMyTeams` exists), `/v1/public/events` fetched twice
  on `/events`, `e instanceof ApiError ? …` ×24, `typing()` ×2, initials ×2,
  `message()` ×2, Composer vs TeamPostComposer media markup, four hand-rolled
  dialogs (one with `aria-modal`, none with focus trap). ~20 exports used only
  in their own file.

## 5. UI: home and team pages

Goal: a modern social home and team pages that are easy to move around and
add members to. Ranked by impact vs effort.

**Quick wins**
1. Team banner: an **Invite** button (managers), member count with avatars,
   description capped at 2 lines (`app/teams/[teamId]/layout.tsx`, `TeamNav.tsx`).
2. Team tabs: fix the sticky offset (`top: 0` vs the 64px top bar; check in a
   browser) and add a scroll-edge fade so hidden tabs are discoverable.
3. Home: composer first; replace the slogan h1 / date pill with one greeting line.
4. Phones: Invitations and the next event above the feed; a floating Post button.
5. Global `:focus-visible` ring for buttons, nav, tabs and icon buttons.
6. Invite links: "Copied" feedback and a Share button (`navigator.share`).

**Bigger changes**
7. One **Invite dialog** for every team kind: Share a link (created on open:
   Invite → Copy = 2 clicks) · Search people · Requests (n), plus pending
   invites with Cancel. Reuse `InvitePeople`, `InviteLinks`, `JoinRequests`.
   Today invites are split between Roster and Settings (4-5 steps), groups and
   communities can't invite by name, and join requests have no badge.
8. Team nav: 6 tabs + "More ▾" + a Settings gear (today 10 tabs in a hidden-
   overflow row); give Playbook / Videos / Stats real routes so detail pages
   highlight their tab.
9. Home: a horizontal team strip under the composer; make "Your teams" a
   team-posts feed instead of a fourth copy of the team list.
10. One composer with an audience chip (Everyone / a team) instead of two.
11. Infinite scroll with a sentinel (three "Older posts" buttons today).
12. New-user checklist card; a "Suggested" teams/people card; at most one promo.
13. Shared `<Loading>`, `<EmptyState action>`, `<ErrorNote>` and skeletons
    (three styles each today).
14. Kind consistency: hide "Teams" for plain groups; consistent narrow-tab
    labels; "Invite-only — have a code?" for outsiders of a team.
15. "Your spaces" + opens create/join; replace the team feed's "People" card
    with a member preview + Invite.

Proposed home:

```
+-top bar: STALL 10 | search ................. theme | bell(3) | me -+
| NAV        | [avatar] What's happening?  [To: Everyone v] | INVITATIONS
| Home       | [photo][poll][event]              [Post]     | UPCOMING (mine)
| Explore    | (o)Team A (o)Team B (o)Group C (+)New/Join   | NEEDS YOU (managers)
| Teams      | For you | Community | Teams                  | SUGGESTED
| Messages   | post / post / … auto-loads                   | one promo, last
+------------+----------------------------------------------+-------------+
```

Proposed team header and nav:

```
| (AV) Seattle Sockeye          [Invite] [Following v] [Share] [gear]
|      Club · Open · Seattle · 27 members (avatars)   Captain
|      One-line description… more
| Feed | Schedule | Chat | Roster | Playbook | Stats | More v   (sticky)
```

Items 7, 9, 10 and 14 change behaviour, so per CLAUDE.md they need the
matching app change (or confirmation the app already does it).

## 6. Not fixed from earlier security reviews (need a decision)

- [ ] Voice and meeting access is enforced only by our clients: LiveKit tokens
  last 6 h and nothing server-side removes a participant on team removal, role
  change or room deletion. Needs the API to call LiveKit's server API.
- [ ] Meeting room names `${teamId}_${meetingId}` are ambiguous; changing them
  needs the callable, `closeRoom` and the API together.
- [ ] No sweeper for ready chat uploads no message uses (scheduled function;
  deploy approval needed).
- [ ] Posts are readable by anyone signed in (rules), so the app's home feed
  can't hide a private author's original behind a repost; only the API does.
- [ ] A shared-calendar editor can publish any event on that calendar to
  followers (republication; accept or restrict to the creator).
