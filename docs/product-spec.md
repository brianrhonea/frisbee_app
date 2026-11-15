# Stall 10 product and navigation spec

The plan the app (`apps/mobile`) and the website (`apps/web`) are reworked
against. Agreed with the product owner on 2026-11-12. How the system is
built is in [ARCHITECTURE.md](../ARCHITECTURE.md); this says what it does.

## 1. Goal

Be the home of ultimate, so players and teams choose Stall 10 over the
existing governing-body sites. Stall 10 wins on what those sites don't
have: a good mobile app, a social side that keeps people coming back
during the season, and team management, all in one place.

In one line: **a social feed for ultimate, with a team hub and a
competition platform.** Every screen belongs to one of three areas:

1. **Social:** profiles, posts, follows, search, direct messages, and
   official news.
2. **Teams and communities:** where you belong and what's happening there.
3. **Events:** tournaments and leagues, the ones you're in and the ones you
   can find.

Nothing here uses another organization's data or branding (see CLAUDE.md).

## 2. Principles

- **Easy to reach, easy to navigate.** Anything a player does weekly is at
  most two taps from a tab. No screen exists only to hold links to other
  screens.
- **One structure everywhere.** The app and the website use the same five
  areas, the same names and the same order, so people learn it once.
- **A team and a community work the same way.** Same hub, same sections.
- **Free to play socially.** An account, the feed, teams and communities
  cost nothing. Money only comes in with sanctioned competition (§7).

## 3. Navigation

Five tabs: the app's bottom bar and the website's left sidebar, in this
order.

| Tab | What's in it |
|---|---|
| **Home** | The feed, with three tabs: **Following** (people and teams you follow), **Community** (everyone's public posts) and **News** (official Stall 10 posts). A compose button. |
| **Explore** | One search for **people, teams, communities and events**, with a **Near me / zip code** filter. Suggested people and communities when the search is empty. |
| **Events** | **My events** (registered, hosting, upcoming games) and **Find events** (tournaments and leagues by date, place and division). The personal schedule calendar lives here. |
| **Teams** | Your teams and communities in one list, then each one's hub (§4). Start a team and find a community at the top. |
| **Messages** | Direct and group messages, with an unread badge. |

- **Your profile and settings** open from your avatar in the top corner,
  not from a tab.
- **Notifications** open from a bell next to the avatar.
- **Website:** left sidebar (the five tabs, then profile), content in the
  middle, and a right column with upcoming events, News and people to
  follow. Signed-out visitors get the same layout, read-only, with sign-up
  prompts where they'd act.

## 4. The team and community hub

Five sections, down from nine today:

| Section | What's in it |
|---|---|
| **Feed** | The team's posts and announcements. |
| **Schedule** | Practices, games and events, with RSVPs and polls. |
| **Chat** | The team's chat rooms. |
| **Roster** | Members, roles, invites and join requests (today's Roster and Members, merged). |
| **More** | Playbook, Videos, Stats, and Tournaments (hosted and entered). |

A community uses the same hub. It also lists the teams that belong to it,
under Roster or More.

Who sees what (decided 2026-11-12): anyone signed in sees a team's
roster and members, each linking to their profile, and its public posts
and events; everything else in the hub is for members. A private group
(one that approves joins) keeps its members, posts and events to itself.

## 5. Teams and communities

- **Team:** a roster that competes, with a level (club, college, masters,
  youth, pickup) and a gender division.
- **Community:** everything else people belong to. Today's community
  groups and schools/clubs become one kind, with a **type**:

  | Type | Examples |
  |---|---|
  | College | a university's program |
  | School / youth | a high school or youth program |
  | Club organization | a club that fields several teams |
  | Pickup | a weekly pickup game |
  | Rec league | a city or rec league |
  | Church / faith | a church group |
  | Other | anything else |

- A community has a location (place or zip code), is listed in Explore's
  Near me search, and has the same features as a team: chat, events,
  posts and tournaments.
- **Eligibility comes from the team, backed by its community.** A team
  that belongs to a **College** community can enter college divisions;
  other levels work the same way once sanctioning exists (§7).
- **Masters** is a new level (today's levels are club, college, youth,
  league and pickup).

## 6. News

- An official, verified **Stall 10** account that admins post from. Its
  posts fill Home's **News** tab, and admins can pin one to the top of
  every feed (season updates, results, announcements).
- Admins are people with Stall 10 admin access, not anyone on a team.
- Later, if needed: longer articles (headline, image, body) on the website.

## 7. Events, competition and money

| | Who can create it | Rules |
|---|---|---|
| **League** | Stall 10 admins (official hosts) only | Today any team can; restrict to official hosts. |
| **Tournament** | Anyone (team, community, or Stall 10) | Free events are allowed. Hosts set divisions, dates, place, caps and format. |
| **Sanctioned division** (college, club, masters) | Stall 10 | Every rostered player must hold a paid yearly membership, or the team can't register. |

**Payments come last** (§8, step 5), close to release:
- Bid fees and dues are paid through Stall 10, which keeps a platform fee
  and pays the rest out to the host. Until then, hosts collect themselves
  and mark teams paid, as today.
- Yearly memberships are sold only once Stall 10 sanctions events.
- Likely built on Stripe Connect. Fees, refunds, tax and app-store rules
  are decided when we get there.

## 8. Build order

1. **Navigation and the hub:** the five tabs on the app and the website,
   profile behind the avatar, the five-section hub. Mostly UI, on today's
   view models and repositories.
2. **News:** the official account, the News tab, pinned posts.
3. **Communities:** one community kind with types; location or zip; Near
   me search in Explore; masters level.
4. **Events tab:** tournaments, leagues and the schedule together; leagues
   restricted to official hosts.
5. **Payments and sanctioning:** platform fees on bid fees and dues, then
   memberships and roster checks for sanctioned divisions. The last big
   feature before release.

Each step ships to TestFlight and the dev website from `development`
before the next one starts.

### 8.1 Website parity

Signed-in members can do everything on the website that they can in the
app (ARCHITECTURE.md §11 decision 4: the website is the desktop app). It
runs alongside steps 2–5: each of those adds its website side once parity
reaches its area.

**Built for the web, not a copy of the app.** No porting of widgets or
view models: pages are written for a mouse, a keyboard and a wide screen,
with logic in hooks over `@stall10/shared` types.
- The URL holds the state: tabs, filters, the open thread or section are
  linkable and survive a reload.
- Use the width: lists beside details (messages and rooms beside the
  thread, the schedule beside the event), tables for rosters, stats and
  standings, the right column for context.
- Quick edits in place: inline composers, popovers and dialogs instead of
  a new page for every form; drag and drop for uploads and the playbook.
- Hover and focus states, keyboard shortcuts (`n` new post, `/` search,
  `j`/`k` through lists, `Esc` closes).
- Phones still work (the bottom tab bar), but desktop comes first.

**Data.** Writes go through the API (ported rules, zod schemas in
`packages/shared`, fakes and emulator tests: ARCHITECTURE.md §10's
playbook). The app keeps writing directly and switches to each endpoint
later behind its `use_api_*` flag, so slices aren't doubled; until then
the Firestore rules stay as they are. Reads (decided 2026-11-12): the
browser reads Firestore directly like the app, with listeners for live
data, since the rules already guard reads; API GETs stay for the
server-rendered public pages (`/v1/public/*`) and anything the rules
can't express.

**Slices**, each shipped end to end (API, website, ARCHITECTURE.md §10
status, versions and changelogs):

| # | Slice | Website | API work |
|---|---|---|---|
| W1 | Home and people | Home feed with tabs, compose (text, photos, video), comments, follow and requests, notifications, edit profile, settings | Create/edit/delete posts, comments, follows; first caller of `/v1/uploads` (§6). Built (api 0.4.0, web 0.5.0) except feed tabs, video in posts (waits on the transcode job, ARCHITECTURE.md §10 item 4) and changing your name and photo |
| W2 | Teams hub | Feed, Schedule, Chat, Roster, More; join, invites, roles, settings; create a team or community | Team posts; membership is already in the API. Built (api 0.5.0, web 0.6.0): the hub's five sections read live; the roster for anyone signed in (`GET /v1/teams/:id/roster`); join or ask to join a group. Api 0.6.0, web 0.7.0: Teams grouped by community, a community's Teams tab, invites by name (team admins, and community admins for its teams). Api 0.10.0, web 0.11.0: team posts, sending chat (photos, replies, reactions, deletes), creating a team, group or community, joining with a code, and a Settings tab (details, invite links, join requests, roles, removing, handing over, leaving). Api 0.12.0, web 0.13.0: custom roles and permissions, chat rooms and folders. Web 0.21.0 (api 0.20.0): voice rooms. Built |
| W3 | Events | My schedule and a calendar, create and edit events, RSVPs, polls | Events, RSVPs, polls. Built (api 0.10.0, web 0.11.0) in the team Schedule: create, edit, delete, RSVPs, reactions, poll votes, organization audiences |
| W4 | Messages | DMs and team rooms side by side, reactions, edits, folders, read receipts | Send, edit, react; rooms and folders (reads stay listeners). Built (api 0.10.0, web 0.11.0): `/messages` with inbox, requests and archive, direct and group conversations, photos, reactions, deletes, read receipts. Not yet: editing messages, team rooms beside DMs, folders |
| W5 | Tournaments and leagues | Find, host, register, divisions, schedules, standings, hat drafts | Move the tournament callables into the API. Built: player signups and captains' drafts (api 0.16.0, web 0.17.0), communities' own tournaments (api 0.18.0, web 0.19.0), hosted tournaments and leagues (api 0.19.0, web 0.20.0). Not yet: payments from the website |
| W6 | Playbook, videos, stats, workouts | Play editor (drag on a field), video library and player, stat entry and tables, workout log | Plays, videos, stats, workouts |
| W7 | Meetings and voice | Join team meetings and voice rooms (LiveKit web SDK) | LiveKit tokens from the API instead of a callable |
| W8 | Cut over | Move the domain to Vercel; keep `/join/:code`, `/g/:id`, `/p/:id` working | Fold the `browse` callables (removable after the next hosting deploy); the Flutter web code (`main_web.dart`, `lib/ui/web`, `lib/ui/browse`, `web_router.dart`) is removed and `build_site.sh` only copies the static pages |

**Website on its own (2026-11-14).** Signed-in members must be able to do
everything the app does on the website alone, styled like the website
(not copies of the app's screens). Remaining gaps, built in this order
(tick each when it ships):

1. Account: [x] change name, photo and header photo; [x] notification
   settings and muting chats (api 0.11.0, web 0.12.0).
2. Team admin: [x] custom roles and permissions; [x] chat rooms and
   folders; [x] adding teams to a community; [x] deleting a team
   (api 0.12.0, web 0.13.0; both type the name to confirm and delete
   through `DELETE /v1/teams/:id`, the app's direct cascade only with
   `use_api_membership` off). Roster players (people without accounts,
   for stats) come with stats.
3. Messages: [x] typing indicators and read receipts (api 0.13.0, web
   0.14.0). The app has no message editing and keeps team rooms out of
   its inbox, so neither is needed.
4. W6: [x] stats (games, live stat entry, season tables, roster
   players; api 0.17.0, web 0.18.0); [x] playbook
   (play editor on a field, drag to draw; api 0.14.0, web 0.15.0); [x] videos (library, links, folders, player;
   api 0.15.0, web 0.16.0; uploading from the website waits on the
   transcode job); [x] workouts (both post typed-in workouts; GPS
   recording needs a phone's location, so it stays in the app).
5. W5: [x] communities' own tournaments (api 0.18.0, web 0.19.0);
   [x] player signups and captains' drafts (api 0.16.0, web 0.17.0);
   [x] hosted tournaments and leagues (find, host, register,
   divisions, schedules, scores, standings; api 0.19.0, web 0.20.0;
   payments from the website still to come). The draft callables'
   logic is ported into the API; the app keeps the callables until it
   switches.
6. W7: [x] team meetings and voice rooms (LiveKit web SDK, tokens from
   the API; api 0.20.0, web 0.21.0; needs the LiveKit secrets on Cloud
   Run). Recording stays deferred. [x] device pickers (speaker where
   the browser can switch output), lobby camera preview, meeting
   volume, mute audio, per-person volume to 200%; [x] a voice call that
   stays up across pages, with a voice bar (web 0.24.0); [x] older call
   chat (web 0.25.0). [x] Both platforms re-check a voice channel while
   connected: losing read access or the team drops it, losing write
   access mutes and keeps listening, signing out hangs up (app
   `test/data/voice_repository_test.dart`). [x] Meetings on the team schedule
   beside events, with New meeting (the website keeps its Meetings tab
   too; the app has none).
7. Posts: [ ] video in posts (waits on the transcode job); [x] feed tabs
   (For you / Community / Your teams on both; Community pages through
   `GET /v1/feed`, app `test/ui/home_test.dart`);
   [x] Discord import (api 0.21.0, web 0.22.0); [x] sharing My calendar
   and shared-calendar events with followers (as the app's editor does;
   the API checks the caller can edit that calendar).
8. Small gaps: [x] notifications open the matching website page for
   every app route (tournaments, signups, drafts, plays, videos, stats
   games, group tournaments, meetings); [x] one draft URL scheme
   (`draft/:div` is the host's balanced draft, `live-draft/:div` the
   captains', as in the app); [x] change password, with the app's
   password policy (`@stall10/shared`, on sign-up too); [x] a System
   theme choice beside Light and Dark.
9. Explore: [x] tournament search beside players, teams and groups, the
   app's All / Players / Teams / Groups / Tournaments filters (`?only=`),
   upcoming tournaments and leagues, recent results, a rankings preview
   and the Jump in shortcuts (web 0.24.0). Not yet: player rows show
   only @username (the app adds team, school and hometown; the public
   search returns neither).
10. Messaging: [x] accepting and declining team invites (Teams page and
    home); [x] any file in team chat and DMs (videos and files stored as
    sent, as the app stores them; videos play, files download with their
    name and size); [x] older messages in DMs, team rooms and the call
    chat; [x] Message on player pages (`/messages?to=<uid>`); [x] unsent
    drafts per conversation and room (kept in the browser; web 0.25.0,
    api 0.23.0). Both platforms: a conversation is started only by
    tapping Message (a `?to=` link shows the person and "Message
    <name>"); drafts are kept per member and cleared on sign-out.
    Website only: a daily chat-upload quota (200 files / 2 GB), and
    Remove in the composer deletes the unsent file (the website uploads
    as files are picked; the app uploads to Storage itself when the
    message is sent, so it has no unsent files to delete).
11. My schedule: [x] every team's events and meetings beside the
    member's calendars, merged soonest first, with the app's All / Team /
    Personal filter, team-name tags when on several teams, and Delete for
    event managers (live Firestore reads under the team schedule's
    rules; the merge and the over rule are in `@stall10/shared`
    `schedule.ts`). The website keeps its upcoming list over the
    calendars' 92-day window (the app pages a week at a time). Not yet:
    home's Upcoming events card lists only team events from
    `/v1/me/home` (the app's home merges personal ones in), and adding a
    team event from My schedule (the app's editor offers the teams the
    member manages) stays on the team's page. The subscribe feed
    (`/v1/ical/:token.ics`) is calendars only on both platforms.
12. Team pages and inviting: [x] one invite dialog on both, opened from
    the team header (and, on the website, the roster, the feed's member
    card and Settings): the link is made when it opens (a week by
    default; a group's link is its page), Copy and Share; people search
    for every kind; a group's join requests to approve or decline, with
    a count badge on Invite; who was invited while it's open (neither
    platform can list or cancel older pending invites: they're stored
    under each invitee). Tests: app `test/ui/invites_test.dart`,
    `test/ui/team_home_test.dart`. The rotating code to read out is in
    the website's dialog and on the app's Members tab. [x] Members see
    the member count; a team's outsiders are told it's invite-only and
    can join with a code; only schools/clubs have a Teams section.
    Website only (layout): six tabs, More ▾ and a Settings gear, with
    Playbook, Videos, Stats and Tournaments at their own URLs.
13. Home: [x] post to Everyone or a team you manage from Home (one
    composer with an audience chip on the website; "Team post" in the
    app); [x] the Your teams tab is a feed of your teams' posts; [x] a
    team strip with New / Join under the composer; [x] a Get started
    checklist on an empty For you feed (same four steps on both:
    username, join with a code, find a team, follow people); [x] Needs
    you: join requests for groups you approve. Tests: app
    `test/ui/home_test.dart`. Not yet: the app's Home doesn't list
    invitations (the website's does). Website only (layout): feeds load
    as you scroll (the app keeps "Show older posts"), and a floating
    Post button on phones.

Out of scope: payments, meeting recording, USA Ultimate data.

Libraries the website may add (none today): a small data cache for API
reads and mutations, the Firestore web SDK for listeners, and LiveKit's
web SDK in W7. Components stay hand-written CSS on the site's tokens.

## 9. Open questions

- Before W1: if App Check is enforced for Firestore in the console,
  browser reads need the reCAPTCHA site key (`NEXT_PUBLIC_RECAPTCHA_SITE_KEY`).

- News articles: are official posts enough, or is a longer article format
  wanted for the website? (Start with posts.)
- Which community types need their own rules beyond College (for example,
  youth safeguarding for School / youth)?
- What happens to existing groups and schools/clubs: migrate each to a
  community type automatically, or ask their admins to pick one?
