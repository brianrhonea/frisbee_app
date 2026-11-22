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
- **Club teams are for players 16 and over** (decided 2026-11-15). A
  club team is a team (not a group) at the club level. Anyone becoming a
  member of one, by code, link or invite, or by starting one, must be 16
  or over that day, counted from the date of birth in their personal
  details (`clubMinimumAge`, `clubJoinProblem` in
  `packages/shared/src/personal.ts`). Without a date of birth on file
  they're asked to add it in About you first. The API checks it
  (`apps/api/src/teams/club_age.ts`; it never shows anyone the date),
  so `firestore.rules` refuses direct joins and creates of club teams.
  Invites can still be sent (an invitee's age is private); accepting is
  checked. People already on a club team stay, and changing a team's
  level to club removes no one. Community roles don't add anyone to a
  club team: its players join with an invite. Free-text roster spots
  aren't accounts, so they aren't checked; linking a spot only links an
  existing member. Groups and other levels (college, youth, league,
  pickup) are open to everyone.

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

**Tournament fees online (built 2026-11-16, api 0.40.0, web 0.53.0, app
0.0.44; off until Stripe is set up):**
- Stripe Connect. The host team's or community's **owner** connects the
  host's own Stripe account (Stripe collects its card fee from the host
  and covers losses; the host has the full Stripe Dashboard).
- A team's admins pay its bid or spot fee and a signed-up player pays
  their entry fee through Stripe Checkout: a direct charge on the host's
  account, with Stall 10's fee taken as the application fee. The fee is
  a server setting (`PLATFORM_FEE_BPS`, `PLATFORM_FEE_FIXED_CENTS`),
  1% + $1 to start, included in the amount, never added on top. US
  dollars only; at least 50 cents, and more than the fee.
- Hosts see what reaches them before they set a price: under each fee
  in the event form and on the payout card, the fee less Stall 10's fee
  and Stripe's usual card fee (2.9% + 30¢, an estimate; `GET
  /v1/payments/fees`, `feeBreakdown`). $100 → about $94.80.
- Hosts can have payers cover the fees (`payerCoversFees`): the charge
  is grossed up so the host gets the whole fee ($100 → $105.41), shown as
  a "Processing fee" line, the same for card and bank. Check card-network
  and state rules on passing fees on before production.
- Bank payments (ACH) where the host switches them on in Stripe; they
  show as processing until they clear, and a failed one can be paid
  again.
- Paying another way: payers can say they'll pay by check, PO or the
  host's own way ("Paying another way" on the host's lists), and hosts
  add a note to any payment. Hosts mark teams' fees on the website too.
- A permanent payment history (`paymentLog`, server only) records every
  change with who, when, amount and Stripe's ids, for disputes.
- A payer who loses their connection: Pay again reuses the open
  checkout, and coming back asks Stripe directly (as well as the
  webhook), so nobody is shown a second Pay button for a fee they paid.
- Paying marks the same payment record hosts mark by hand, so their
  instructions and the paid switch still work beside it. A second
  payment for something already paid is refunded in full.
- Refunds and disputes are handled in the host's Stripe Dashboard. A full
  refund un-marks the fee and Stall 10 gives its fee back.
- The app opens Stripe's pages in the browser: entry fees are for
  real-world events, which store rules allow outside in-app purchase.
- Not yet: team dues (a dues amount a team sets; today only a paid
  checkbox), refunding from inside Stall 10, memberships, tax.

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
| W5 | Tournaments and leagues | Find, host, register, divisions, schedules, standings, hat drafts | Move the tournament callables into the API. Built: player signups and captains' drafts (api 0.16.0, web 0.17.0), communities' own tournaments (api 0.18.0, web 0.19.0), hosted tournaments and leagues (api 0.19.0, web 0.20.0), paying fees online (api 0.40.0, web 0.37.0) |
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
   divisions, schedules, scores, standings; api 0.19.0, web 0.20.0);
   [x] paying fees online and the host connecting Stripe (api 0.40.0,
   web 0.53.0, app 0.0.44). The draft callables'
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
   [x] Rankings filters (both platforms): the Rankings page picks a
   team ranking with two filters, Level (Club, College, League, Pickup;
   never Youth) and Division (Mixed, Open, Women, Masters), showing
   only levels with a ranking and the divisions ranked at the level
   picked. Opens on Club Mixed, else the first ranking (by level, then
   division); a level keeps the division picked if it has one, else
   takes its first. The website keeps them in the URL
   (`/rankings?level=club&division=mixed`; the old
   `?division=club-mixed` still opens), and so does the app's route
   (also the old `?d=`). The note under the table says "Youth teams
   aren't ranked." and under player ratings "Players on youth teams
   aren't rated." Explore's preview (both) still opens on the
   member's team's division, else the biggest. Logic in
   `@stall10/shared` `rankings.ts`, mirrored by the app's
   `RankingChoice`, checked on the shared vectors
   `fixtures/rankings/choice.json`. Tests: shared
   `test/rankings_fixtures.test.ts`; app `test/ui/explore_test.dart`,
   `test/data/ranking_repository_test.dart`,
   `test/shared_fixtures/rankings_fixtures_test.dart`.
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
    [x] Follow on the team header only for people not on the team (a
    member's feed already has every post; web `showsFollow`, app
    `TeamHomeViewModel.follow`). Note: team-post pushes go to followers
    with notifications on, so a member who doesn't follow gets none.
    [x] One Settings gear for members (beside the tabs on the website).
    Website only (layout): six tabs, More ▾ and a Settings gear, with
    Playbook, Videos, Stats and Tournaments at their own URLs; the
    feed's roster card for people not on the team (`rosterCardText`:
    visitors only for a public adult roster, "See who's on the team.";
    none for a youth team or private group).
13. Home: [x] post to Everyone or a team you manage from Home in one
    inline composer on both (type and Post; Photo and Workout open
    inside the box; a "To" chip for teams you manage, whose posts add
    Title, Where and Public, no Public for a private group, no Workout or
    tournament tag; app `InlineComposerViewModel`,
    `test/ui/inline_composer_test.dart`). The app also has Take photo and
    Record; editing posts keeps the full-screen editor. [x] No link tool
    on either platform (Home, post editor, team post editor): web
    addresses in a post's text show as links (app `LinkifiedText`,
    website `LinkedText`); older posts keep their `links`, shown and
    removable when edited. Left:
    the app types distances in the country's unit where the website has
    a km/mi picker. [x] the Your teams tab is a feed of your teams' posts;
    [x] a team strip with New / Join under the composer; [x] a Get
    started checklist on an empty For you feed (same four steps on both:
    username, join or create a team (done once on any team; "Join or
    create" opens the create-or-join choice), find a team, follow
    people); [x] Needs
    you: join requests for groups you approve. Tests: app
    `test/ui/home_test.dart`. Not yet: the app's Home doesn't list
    invitations (the website's does). Website only (layout): feeds load
    as you scroll (the app keeps "Show older posts"), and a floating
    Post button on phones.
14. Visitors (signed out): [x] website only; the app has no signed-out
    mode, so this isn't a parity gap. Visitors see Learn (rendered on
    the server), Events (`GET /v1/public/events`), tournaments, the
    community feed's first page, a team finder on Teams (`GET
    /v1/public/teams?q=`: listings only, never players; the top bar's
    search lands there), and team and group pages with public posts and
    events, and team rankings (`/rankings`, below). A youth team
    (`isYouthTeam` on its team doc or its listing)
    shows visitors its card only (name, city, description, division and
    level; no posts, events or location, in the finder and Events too),
    with "Youth teams share their posts and schedule with members only."
    Signed-in people who aren't on it see its public posts and events,
    in the app and on the website. A team's roster is public only for an
    adult team: `rosterIsPublic` in `@stall10/shared` (kind team, level
    club, college, league or pickup; youth, no level and every group
    stay private), checked by the API on the team doc and its listing
    (`GET /v1/public/teams/:id/roster`: players' names, numbers and
    positions, plus a public profile's username and photo; no ids, no
    members list, no links to players' pages). A spot linked to a
    private profile, or one that hides its teams, shows as "Player"
    with its number and position only. A league's drafted teams
    (`league_…`) are out of the finder, show as "League team" and have
    no public roster; nor does a team in a league's youth division.
    Players (and player ratings), search, Explore, messages and My
    schedule stay members-only. Signed in: a youth team's roster (`GET
    /v1/teams/:id/roster`) is only for its members and the member
    managers of the school or club community that accepted it; everyone
    else sees "Rosters of youth teams are private: only members see
    them." in its place, in the app and on the website. Adult teams'
    rosters stay open to anyone signed in. Tests: API
    `test/browse.test.ts`, `test/roster.test.ts`,
    `test/browse.emulator.test.ts`; shared
    `test/team_roster_public.test.ts`; app `test/ui/team_home_test.dart`
    (the youth roster note).
    [x] Rankings: visitors see the team rankings at `/rankings`,
    server-rendered from `GET /v1/public/rankings` (rank, team, rating,
    wins and losses; teams link to their public pages); the Players tab
    asks them to sign up. Youth is never ranked, for anyone: the
    `rankings` functions skip youth divisions and youth teams (by team
    doc or listing) in adult divisions, delete stale `rankings/youth-*`
    docs, and rate nobody on a youth team but its owner and coaches;
    the API also drops youth keys, youth and private-group teams, and
    drafted league teams, and the members' live reads (app and website)
    drop youth keys. Tests: API `test/public_rankings.test.ts` (and the
    emulator test); functions `test/rankings`.
15. Visitors: tournaments (website only; the app needs an account).
    [x] Signed-out visitors (parents, friends) browse `/tournaments` and
    follow any published tournament's or league's page: overview,
    divisions, the accepted teams, the schedule, scores, standings,
    brackets and the host's news, server-rendered from
    `GET /v1/public/tournaments` and `/v1/public/tournaments/:id`
    (another division with `?division=`; live events reread every
    minute). [x] A community group's tournament shows outsiders' public
    listing (`/v1/public/group-tournaments/:groupId/:id`). Hidden from
    visitors: drafts (the rules' `visible()`), private groups' events,
    who signed up and the draft, captains, fee instructions and other
    payment details, and player names (drafted teams always show as
    "Team N"). The tournament form (app and website) says "The location
    and About are public: anyone can see them once it's published, even
    without an account." Entering a team, signing up,
    following and the sub-pages (signups, drafts, editing, hosting) need
    an account: visitors get "Sign up free or log in", which comes back
    to the page. Tests: API `test/public_tournaments.test.ts` (and the
    emulator test); app `test/ui/host_event_test.dart` (the form's
    hint). Not yet: a group's Tournaments tab and a host's
    hosted list for visitors.
16. Sign-up with Google or Apple: [x] "Your name and username" on both
    (website `UsernameStep` in `PersonalGate` and the Home card; app
    `ChooseUsernameScreen`): first and last name, prefilled by splitting
    the provider's name (`splitDisplayName` / `PersonName.split`; an
    email-looking name is ignored) and required, with the sign-up form's
    limits (`personNameLimits`, 30 each, on both sign-up forms too), then
    the username suggested from the name until edited. Email accounts that
    have a name see only the username. A new account with no usable name
    is held at the step even with a username ("Your name"); older accounts
    keep today's rules (asked when the username is missing). The name is
    saved as each platform renames (website `PUT /v1/me/identity`, app the
    Auth record), then the username is claimed. "About you" follows and
    starts the legal name from the names just typed (in memory only),
    else the display name split. Tests: `packages/shared/test/profile.test.ts`
    (fixtures `profile_names.json` `displayNames`, written by the app's
    `test/data/shared_fixtures_test.dart`), app
    `test/ui/choose_username_test.dart`. The email sign-up form's
    birthday is saved right after the account is made
    (`PUT /v1/me/personal/birth-date`, encrypted like the details, under
    13 refused, never blocking sign-up), and "About you" starts from that
    copy (`GET /v1/me/personal`'s `signUpBirthDate`), else the one in
    memory, so a reload, restart or other device isn't asked again. It
    doesn't complete the details and is refused once they're saved.
    Tests: API `test/personal.test.ts`, app
    `test/ui/personal_details_test.dart` ("the sign-up birthday").
17. Club teams, 16 and over (§5): [x] the API refuses joins (code,
    link, invite) and starts of club teams for under-16s or anyone with
    no date of birth on file, with the same words on both ("Club teams
    are for players 16 and over." / "Add your date of birth in About you
    to join a club team."), shown where the join fails; [x] the rule up
    front on both: creating a team at the club level, moving a team to
    club (people already on it stay), a community's new team, invite
    links and club team invites; the community role picker says club
    teams take no one from roles. Tests: shared
    `test/personal.test.ts`, API `test/membership.test.ts`,
    `test/teams.test.ts` and their emulator tests, rules
    `firestore.rules.test.ts` ("club teams"), functions
    `test/communities/model.test.ts`, app `test/ui/club_age_test.dart`
    and `test/domain/personal_details_test.dart`. The website has no
    test runner yet, so its side is checked by hand.
18. Offline queue (app 0.0.28, web 0.38.0, api 0.30.0): [x] direct and
    group messages, team chat, new posts, new team posts and comments
    sent while Stall 10 can't be reached wait on the device (the app's
    support folder; the browser's IndexedDB) and send by themselves, in
    order per thread, once it can. Each keeps the id picked when it was
    sent; every endpoint answers `already_exists` to a second copy (the
    app also checks the server before resending), so nothing posts
    twice. Connection and server errors wait with backoff; anything else
    is "Not sent", with Try again and Discard, and doesn't hold up the
    rest. Both show an offline banner opening "Waiting to send", queued
    messages at the end of their thread, and a notice when something is
    queued instead of sent. Likes, reactions, RSVPs and edits aren't
    queued. Shared rules: `packages/shared/src/outbox.ts`, checked
    against `fixtures/outbox` (app `test/shared_fixtures/
    outbox_fixtures_test.dart`, shared `test/outbox_fixtures.test.ts`);
    the app's queue in `test/data/outbox_repository_test.dart` (a lost
    response, the app closed with items queued, one turned down not
    holding up the rest, another account's items); the API's comment
    id in `apps/api/test/post_editor.test.ts`. The website's IndexedDB
    side is checked by hand. Photos: the app's one "Photos +" button
    (Take photo or Upload photos) is app design only; the website keeps
    its photo button, both up to 4 a post.
19. Private profiles' posts (app 0.0.29, web 0.39.0, api 0.31.0;
    security review S1): [x] a private profile's posts, photos, comments
    and likes are for the author and accepted followers, in the rules
    (`canSeePost`; Storage likewise), not only the UI. Posts carry
    `private` from the author's profile (app and API write it; the
    `follows` functions stamp and update it). Both platforms' queries
    over several authors ask for `private == false`; one author at a
    time for the user's own and accepted private profiles (app
    `watchPostsByAuthors` `includePrivate`; web `PlayerPage` signal; the
    website's feeds come from the API, whose likes, comments and comment
    likes check the same follow). Neither reposts a private profile's
    post (app `canRepost`; web `canRepost` from `/v1/posts/state`).
    Phase B (the rules' list check) is still to come. Checked by the
    rules tests ("private profiles' posts", `posts_phase_b.rules.test.ts`,
    storage "user post photos"), the app's `home_test`, `privacy_test`,
    `post_actions_test` and `community_feed_api_test`, the API's
    `post_editor`/`posts` tests and the functions' `follows/privacy`.
20. UI review release 1 (app 0.0.30, web 0.40.0, api 0.31.1): [x] one
    name for communities on both, "Pickup community" for the kind
    (`TeamKind.community`, shared `teamKindLabels`, website `kindLabels`)
    and "community" in sentences for it and a school or club (group
    messages stay "group"; Explore's chip is Communities, `?only=groups`
    unchanged); the API's errors match. [x] Stats says **Track a
    tournament** and **Tournament stats** on both. [x] A **QR code**
    button in the invite dialog on both (app `qr_flutter`, website
    `qrcode`). App only (design): a message's long-press sheet shows
    when it was sent (the website shows it on hover). Tests: app
    `test/ui/invites_test.dart` (QR), `test/ui/messages_test.dart`; the
    website's side is checked by hand. Community *types* (§5) are still
    to come.
21. Stats per team on profiles (app 0.0.31, web 0.41.0, api 0.32.0):
    [x] a **Team** filter on a profile's stats on both, offered with two
    or more published teams that have stats; it narrows the totals,
    seasons and season table (recent games stay as they are). The
    player's app publishes `teamStats` (team → season → totals) only
    with both stats and teams shown; the API's `profileView` and
    visibility follow the same rule, and the rules cap it at 50 teams.
    One rule: app `ProfileStatsChoice`, shared `profileStatsChoice`,
    vectors `fixtures/profile_stats/choice.json`. The website keeps the
    pick in `?team=`. Tests: app `test/ui/player_profile_test.dart`,
    `test/data/profile_api_test.dart`; shared
    `test/profile_stats_fixtures.test.ts`; API `test/profiles.test.ts`,
    `test/browse.model.test.ts`; rules "per-team stats".
22. Team chats in Messages (app 0.0.32, web 0.42.0, api 0.33.0):
    [x] Messages lists every team and community chat above direct
    messages on both (reversing item 3's "team chats live on team
    pages"): rooms with new messages, the newest's time, an unread dot; a
    tap opens the only unread room, else the newest. [x] A team's room
    list shows unread rooms bold with a dot on both; an open room is
    marked read. Rooms carry `lastAt` (a time, never text), stamped by
    senders; read times are private `users/{uid}/chatReads/{teamId}`.
    App only (design): the Unread filter and the Messages badge count
    them (the website has neither for messages). One rule: app
    `TeamChatSummary.fromReadable`, shared `teamChatSummary`, vectors
    `fixtures/team_chats/summary.json`. Tests: app
    `test/ui/messages_test.dart`, `test/ui/chat_test.dart`,
    `test/data/chat_reads_test.dart`; shared
    `test/team_chats_fixtures.test.ts`; API `test/hub.test.ts`; rules
    "stamps its lastAt", "chat read times".
23. Tournament-day card (app 0.0.33, web 0.43.0):
    [x] On a tournament day Home and the team page show the team's card
    in place of the next event on both: the tournament (Live), next game
    (opponent, time, field; the evening before from 17:00: tomorrow's
    first game), record, pool place (once it has a pool result) and last
    result; "Next game to be decided" between pools and the bracket while
    a bracket slot comes from the team, the day on a next game that isn't
    today. [x] Captains get Report / Confirm score on both, opening the
    tournament page on that game with its score form (app: the game
    sheet; web: **This game**, form open); `?game=`, `?division=`,
    `?tab=` on both. One rule: app `TournamentDay.of`, shared
    `tournamentDay`, vectors `fixtures/tournament_day/day.json`. Data:
    accepted entries from the day before to the last day (app
    `TournamentDays`, web `useTournamentDays`). Tests: app
    `test/ui/tournament_day_test.dart`; shared
    `test/tournament_day_fixtures.test.ts` (the website has no test
    runner; its rule is the shared one); rules "an entered team's
    players read an invite-only event's games".
24. Tournaments tab when one is ahead (app 0.0.34, web 0.44.0):
    [x] A team's page shows Tournaments as its own tab after Chat on
    both while the team has a tournament ahead (members), and More drops
    it; otherwise it stays under More. [x] The Tournaments section starts
    with the tournament-day card on both. One rule: app
    `hasTournamentAhead`, shared `hasTournamentAhead`, vectors
    `fixtures/tournament_day/ahead.json`.
25. Redesign ("Turf & Disc", `docs/redesign-plan.md`; app 0.0.36, web
   0.45.0): [x] same tabs on both (Home, Discover, Schedule, Teams,
   Inbox); [x] Discover merges Explore and Find events on both
   (`/discover`, `/events` and `/schedule?view=find` redirect; chips All,
   Tournaments, Leagues, Pickup, Teams, Communities, Players); [x] feed
   tabs Your teams / Following / Everyone on both (no composer on
   Everyone); [x] the Teams tab always shows your teams' list on both
   (it opened your only team until F34, item 37); [x] live
   tournament days open on Schedule; "Next steps"; host chooser "What are
   you hosting?" / "Host as" (Tournament · League · Hat); [x] RSVP counts
   on each answer, "Needs RSVP", "Directions", "Notes"; [x] compact team
   header with initials and Message; [x] Light / Dark / System on both.
   Each platform keeps its own layout.
26. Playbook whiteboard (F31): [x] app; [x] website. A "Plays |
    Whiteboard" switch on the playbook; the whiteboard is a field to
    sketch on (pen in white, navy, turf or amber; offense, defense,
    disc and cones to drop and drag; erase, undo, clear). Anyone who
    sees the playbook can sketch; those who can edit plays save it as a
    play (pieces as the setup, strokes kept) or as a whiteboard (a play
    doc with `kind: "whiteboard"`, no steps), listed under the switch.
    Leaving with an unsaved sketch asks "Discard sketch?". Plays keep
    pen strokes (`drawings`, painted under arrows; the play editor
    erases and clears them). Data: `playDrawingSchema`, `playKinds`,
    `drawingColors`, `playLimits.drawings`/`drawingPoints` in
    `@stall10/shared`; vectors `fixtures/playbook/play_docs.json`. Web:
    `/teams/:id/playbook?view=whiteboard`, `/teams/:id/whiteboards/new`
    and `/whiteboards/:playId` (notifications' `webRoute` opens them),
    logic in `components/team/playbook/whiteboard_state.ts` (no web
    unit-test runner yet). Tests: app
    `test/ui/whiteboard_viewmodel_test.dart`,
    `test/ui/whiteboard_test.dart`; shared `routes.test.ts`.
27. New teams start simple (F21): [x] app; [x] website. A new team
    (not a community) stores `sections: {playbook, videos, stats,
    meetings}` all false, so it starts with Feed, Schedule, Chat and
    Roster (Tournaments under More); a missing map or key reads as on, so
    older teams keep everything. The owner turns them on in Settings ›
    Sections (a switch each, with a one-line description); an off section
    has no tab or More row, and with Meetings off, New on the schedule
    adds an event straight away. A brand-new team's owner sees a
    dismissible hint. Data: `optionalTeamSections`, `newTeamSections`,
    `sectionOn`, `setTeamSectionsRequestSchema` in `@stall10/shared`;
    `PUT /v1/teams/:id/sections` (owner only; rules `setSections`);
    vectors `fixtures/team_create.json`. Tests: app
    `test/ui/team_sections_test.dart`; API `documents.test.ts`,
    `membership.test.ts`; rules "team sections".
28. Live running scores (F1; app 0.0.37, web 0.46.0, api 0.34.0):
    [x] app; [x] website. While a game is played, either team's captain
    or the host's event managers keep its running score on the game's
    day (from 2 hours before its start to 24 hours after; not on a draft
    or finished event, a game without both teams, or one already
    reported or final): app a "Live score" sheet, website a "Live score"
    dialog, both with "Start game" (0–0), "+1" and an undo per team, the
    score big in the scoreboard face, "Report final score" (a captain) or
    "Set final score" (the host) opening the usual score form filled in
    from the running score, and "Stop live score" ("Stop the live
    score?"). Taps show at once and are sent in the background (absolute
    scores, latest wins, one request at a time); a failed send goes back
    to the server's score and shows the API's message. It's never the
    final: the game stays scheduled and the final is still reported and
    confirmed (or set by the host). [x] Everyone following sees it on
    both: a red LIVE pill and the score on the game (with "Live score.
    It isn't final until it's reported."), "Start game" / "Update live
    score" on the game for those who keep it, the navy header's "nameA
    7–5 nameB · +N more live" (the viewer's own game first), the
    tournament-day card's "LIVE NOW" with the score from the team's side
    (the team's live game in place of its next), and Discover's Live now
    cards ("nameA 9–7 nameB · Field 3", up to three, then "+N more
    live"). Visitors read it from the public page and list
    (`game.live`, `card.liveGames`). A game is live while it's scheduled
    and its running score was updated in the last 3 hours. Data:
    `games/{id}.live`, written only by the API (`POST`/`DELETE
    /v1/tournaments/:id/divisions/:divisionId/games/:gameId/live`);
    `liveScoreRequestSchema`, `liveLimits`, `isLiveGame`, `inLiveWindow`
    in `@stall10/shared`. Tests: app `test/ui/live_scores_test.dart`;
    API `tournaments.test.ts`, `public_tournaments.test.ts` (the website
    has no test runner; its rules are the shared ones).
29. Note on an RSVP (F7): [x] app; [x] website. With an answer to a
    team event (Going / Maybe / Can't go) or a meeting (Attending / Not
    attending), a member can add a short note under it ("Add a note
    (optional)", Save or Enter; e.g. "Late 15 min"): one line, up to 140
    characters, control characters stripped and spaces trimmed; empty
    removes it. Changing the answer keeps the note; taking the answer
    back removes it. The note shows in quotes after the person's name in
    Responses (events) and Invited (meetings), to whoever sees those.
    Data: `rsvpNotes` (uid → note) on `teams/{id}/events/{id}` and
    `teams/{id}/meetings/{id}`; `rsvpNoteMax`, `cleanRsvpNote`,
    `rsvpNoteSchema`, `nextRsvpNotes` in `@stall10/shared` (the app's
    `cleanRsvpNote` matches); `note` on `PUT .../events/:id/rsvp` and
    `PUT .../meetings/:id/rsvp` (left out keeps it); rules
    `validRsvpNote` for the app's direct writes; account deletion
    removes the user's notes. Tests: app `schedule_viewmodels_test.dart`,
    `meetings_viewmodels_test.dart`, `meetings_screens_test.dart`; API
    `hub.test.ts`, `meetings.test.ts`; shared `rsvp_notes.test.ts`;
    rules "a short note to their own answer"; functions
    `account/model.test.ts`.
30. Schedule month view (F16): [x] app; [x] website. The personal
    Schedule has a Week / Month switch on the app (Week is the week
    strip) and List / Month on the website (List is the upcoming list),
    remembered on the device (app preferences; browser storage). Month
    is a calendar grid, Monday first, of the whole weeks around the
    month (`monthGrid` on both), each day with dots: team blue,
    personal magenta, amber when something on it still needs an RSVP;
    today in turf, the picked day outlined. Arrows move a month (today
    picked in this month, else the 1st), Today comes back, and a day
    from the next or previous month opens it. The picked day's whole
    week (its grid row, `weekOf` on both) is listed below with the usual
    rows, scrolled to that day, and the row is tinted, through the All /
    Team / Personal filter (`scheduleOnDay` in `@stall10/shared`, the
    app's `eventsOn`). The Calendars card under the schedule is compact:
    the calendars on one line and one Manage button. The month reads its own range (calendars for the grid;
    on the website team events from the grid's first day). No data
    changes. Tests: app `test/ui/schedule_month_test.dart`; shared
    `schedule.test.ts`.
31. Meetings list (F17): [x] app; [x] website. A team's Meetings page:
    Upcoming / Past switch; "Live now" first with Join; Coming up
    soonest first (a meeting earlier today that hasn't started stays
    here); Past (ended, or started before today) newest first. Rows have
    the date tile, title (Live pill when live), when and who's invited
    (and "N going"), and the member's answer, with "Needs RSVP" in amber
    while it's theirs to give. Admins get "New meeting". App: More ›
    Meetings and "Meetings" on the team's schedule
    (`/team-meetings/:teamId`, which used to redirect to the schedule),
    only with Meetings on (Settings › Sections); website: the Meetings
    tab. Tests: app `test/ui/meetings_list_test.dart`,
    `event_navigation_test.dart` ("More opens the team's Meetings
    list").
32. Pinned messages and event cards in team rooms (F2, F3): [x] app;
    [x] website. **Pins:** the owner and chat managers who can read a
    room pin and unpin a message (app: its long-press sheet; website:
    Pin / Unpin in its actions). A "Pinned" strip under the room's header
    shows the newest pin; a tap or click lists every pin with its whole
    text (opening it in context isn't cheap in a paged thread), with
    Unpin for those who pin. At most 10 a room: pinning an 11th asks
    which pin to take down and swaps them in one write. A deleted
    message's pin goes with it (clients list pins with a query on the
    messages, `orderBy pinnedAt`; the room's `pins` ids, kept for the
    limit, drop deleted ones). Team rooms only, not direct messages.
    **Event cards:** someone who can post in the room and add the team's
    events picks "Share an event" in the composer's attach menu and an
    upcoming event; it posts a message carrying `event: {id, title}`,
    shown as a card: date tile, title, time and place, the member's
    answer and Going count, and Going / Maybe / Can't go (the event's
    own RSVP path; amber "RSVP needed" while unanswered; picking the
    current answer takes it back). A deleted event, or one the reader
    can't see, shows "Event no longer available". A community shares
    only events for everyone. The push says "<name> shared an event:
    <title>". Both are API-only from the start (`PUT|DELETE
    .../messages/:id/pin`, `POST .../event-shares`; firestore.rules
    already keeps clients from setting these fields), so the app needs
    `API_BASE_URL` for them. Chat polls: item 39 (F33). Tests:
    API `test/chat_extras.test.ts`; functions
    `test/notifications/model.test.ts`; app `test/ui/chat_extras_test.dart`.
    The website's side is checked by typecheck and by hand.
33. Public team page switch and Download your data (F12, F14): [x] app;
    [x] website. **Public team page:** team Settings › Visibility has a
    "Public team page" switch (teams only; groups use "Approve who
    joins"). Everyone on the team sees it; admins (manageTeam, as for
    the details) switch it through `PUT /v1/teams/:id/public-page`, which
    writes `publicPage: false` on the team doc and its listing (on
    removes it; missing reads as on). Off, people outside the team see
    only its card, as a private group's: no public posts, events or
    roster (signed-out or signed in), no shared event posts, and its
    hosted events and rankings drop out of the public lists; search
    still finds it by name. It only hides more: youth rosters stay
    private either way. The app now shows team Settings to admins, not
    only the owner (Sections stay the owner's). **Download your data:**
    Settings › Account › Your data fetches `GET /v1/me/export`, a JSON
    file of the caller's account, profile, personal details, settings,
    follows, posts, comments, messages they sent, conversations (who's
    in them), teams with their own role, their RSVPs and answers,
    personal events and roster spots; never other people's messages,
    answers or details. Once every 10 minutes. App: the share sheet
    (Files, Drive, mail); website: a file download. Blocked accounts
    (F11) aren't built: there's no blocking yet. Tests: API
    `test/data_export.test.ts`, `membership.test.ts` (public page),
    `browse.test.ts`, `roster.test.ts`, `post_tags_events.test.ts`;
    rules `firestore.rules.test.ts`, `storage.rules.test.ts`; app
    `test/ui/team_public_page_test.dart`, `download_data_test.dart`,
    `team_sections_test.dart`. The website's side is checked by
    typecheck and by hand.
34. Discovery: Learn progress, spots left, public pickup games (F9, F10,
    F29): [x] app; [x] website. **Learn progress:** the guide's contents
    show "N of 12 read" and a tick on each lesson read, with a neutral
    "Mark all unread". A lesson counts as read once the end of it has
    stayed on screen for 2 seconds (`learnReadAfterMs`). The lessons
    (ids, titles, order) are `learnLessons` in
    `packages/shared/src/discover.ts`; the app's `learnSections` match
    (vectors `fixtures/discover/learn.json`). Kept on the device only
    (localStorage `learn.read`; the app's shared preferences), not
    synced between devices. **Spots left:** tournament and league cards
    (Discover, Tournaments, a host's Tournaments section, visitors' list)
    say "N spots left" (turf) or "Full · waitlist" (neutral) while
    registration is open, for events that take teams (hat tournaments'
    players aren't capped): each division's cap less its accepted
    teams. `GET /v1/public/tournaments` works it out (`spots`, from the
    divisions); members' live lists read it from there (one cached
    read). Without the API (app builds with no `API_BASE_URL`), or for
    a private group's event (not in the public list), no line shows.
    Home has no tournament list (only tournament-day cards), so nothing
    there. **Public pickup games:** the app's Discover now lists public
    team events from `GET /v1/public/events` as the website does: every
    one under All ("Team events"), pickup games under Pickup ("Pickup
    games"), and in search results ("Events" / "Pickup games"). Rows:
    date, title, team or community with a dot (turf for pickup, team
    blue otherwise), when and where, and type. A row opens the event for
    the team's members, else the team or community's page (only members
    read events), as the website links the team. Not on the app: the
    website's week strip and community (group) tournaments in that list.
    Tests: shared `test/discover_fixtures.test.ts`; API
    `public_tournaments.test.ts` (spots); app `test/ui/learn_test.dart`,
    `discover_public_test.dart`, `test/shared_fixtures/discover_fixtures_test.dart`.
    The website's side is checked by typecheck and by hand.

35. Tournament extras (F30): [x] app; [x] website. **Bracket page:**
    Results' Bracket has "Open bracket", the division's bracket on its own
    page (app `/tournaments/:id/bracket/:divisionId`; website
    `/tournaments/:id/bracket?division=`, server-rendered for visitors of
    a published event, members-only otherwise; `webRoute` maps the app's),
    with the division chips and each game opening as usual. **Score
    steppers:** the score form (report, confirm a different score, set or
    correct the final, group tournaments too) has − and + around each
    score in the scoreboard face; it can still be typed; an untouched
    score stays empty ("Enter both scores."), + starts at 1, 0–99, and
    the usual checks (no ties) apply. **League weeks:** a league's
    Schedule shows one game night at a time, "‹ Week N ›" with its date,
    "of N" and byes; it opens on tonight's night, else the next, else
    the last. Weeks are nights, not rounds (two games a night, skipped
    weeks), a night of bracket games is "Week N · Playoffs", unscheduled
    games come last (`leagueWeeks`, `currentWeekIndex`,
    `leagueWeekLabel` in `@stall10/shared`; the app's
    `domain/tournament_engine/league_weeks.dart` matches). Tournaments
    keep the list by day. **Enter a team:** Apply to play, Accept the
    invite and Captains open full screen (app) or on their own page
    (website `/tournaments/:id/enter`, `?team=` for an invite or
    captains), with the team, division and captains as before; the
    website's page offers only what the event page would (registration
    open, public, divisions, no team already in). Reserving a spot stays
    a small form. **Form steps:** hosting or editing an event goes Details
    → When & where → Who can play → Format & divisions → Fees → Review
    (Edit on each part); "Save draft" at any step and "Publish" on Review
    while it's a draft (new or saved as one): Publish saves and opens
    registration (`status: registration`, as "Publish and open
    registration" does). A published event has one Save. If a new event
    is created but publishing fails, it opens as the draft. **Share:** a
    published event's page (tournament or league; visitors too on the
    website) has Share: the app's share sheet, the website's
    `navigator.share` or copy link, both sending
    `https://<site>/tournaments/:id` (not a draft). The app doesn't claim
    `/tournaments/` links yet, so they open the website. No data or rules
    changes. Tests: app `test/ui/tournament_extras_test.dart`,
    `test/domain/league_weeks_test.dart`, `host_event_test.dart` (form
    steps); shared `league_weeks.test.ts`, `routes.test.ts`. The
    website's side is checked by typecheck and by hand.
36. Video notes, comments and game tags (F4, F5, F6): [x] app; [x]
    website. On a team video's page, below the player: **Notes:** members
    pin a note to a moment ("Mark start" takes the player's time, or the
    current time when Post is pressed without one) and make it a clip
    with "Mark end (clip)" (after the start; "No end" takes it back).
    Notes list by time with a turf time chip ("1:23", a clip "1:23–1:40");
    a tap or click plays from there. **Comments:** a thread, oldest first,
    with a composer. Both are up to 1000 characters (trimmed), show
    the author's name and date, and are deleted by their author or
    an admin (manageTeam), with a confirm. A comment (not a note) pushes
    "<team>: <name> commented on your video" to the video's author while
    they're on the team. **Game tag:** admins tag the video to one of the
    team's events from the last year or the next month (newest first; a
    community's for everyone only): "Tag a game or event", then Change
    event / Remove tag; everyone sees the event's date tile, type, date
    and title, opening the event ("Tagged event not available" once it's
    deleted). The event's page lists the videos tagged to it (members,
    with Videos on). Data: `teams/{id}/videos/{videoId}/comments/{id}`
    (`authorId`, `authorName`, `body`, `createdAt`, and `atMs` / `endMs`
    for notes and clips) and `eventId` on the video;
    `videoCommentRequestSchema`, `tagVideoEventRequestSchema`,
    `videoCommentLimits`, `splitVideoComments`, `formatVideoTime` in
    `@stall10/shared` (the app's `VideoComment` matches). API-only from
    the start (`POST .../videos/:id/comments`, `DELETE
    .../videos/:id/comments/:commentId`, `PUT .../videos/:id/event`;
    `apps/api/src/videos/extras.ts`), so the app needs `API_BASE_URL` to
    write them (it still reads them). Rules: members read comments; no
    client creates them; admins may delete them so the app's own video
    removal clears them first (the API's removal does the same);
    `eventId` is in neither of the video's key lists. Account deletion
    and Download your data cover them (collection group `comments`).
    Tests: app `test/ui/video_extras_test.dart`; API
    `test/video_extras.test.ts`, `data_export.test.ts`; shared
    `videos.test.ts`; rules "only the API tags a video" and "members read
    notes and comments"; functions `notifications/model.test.ts`. The
    website's side is checked by typecheck and by hand.

37. Teams tab and Add to calendar (F34, F35): [x] app; [x] website.
    **Teams tab:** always opens the list of your teams (invitations, your
    teams, find and start one), even when you're on exactly one; the
    redesign's shortcut that opened your only team is gone (app
    `TeamsTabTap` / `TeamsViewModel.single`, web `useSingleTeam`). A
    team's page keeps its "All teams" back to the list. **Add to
    calendar** adds the event to a calendar the person picks: the app
    opens the phone's own new-event editor filled in (`add_2_calendar`:
    iOS's event editor, which needs no calendar access from iOS 17 and
    asks first on iOS 15–16; Android's calendar insert screen, no
    permission), where they choose the calendar and save, and shares the
    .ics file only where there's no editor (no calendar app, or the
    plugin fails). The website's "Add to calendar" is a menu: **Google
    Calendar** and **Outlook** open their new-event pages filled in, and
    **Apple / other (.ics)** downloads the file. Both send the title,
    start, end (an hour after the start without one), location and
    notes; times are fixed instants shown in the person's own time zone
    (events have no all-day form). On every event that offers it: team
    events, My calendar and shared-calendar events. The subscription
    feed (`/v1/ical/:token.ics`) is unchanged. Data:
    `googleCalendarUrl`, `outlookCalendarUrl`, `calendarEventEnd` in
    `@stall10/shared` (`calendar_links.ts`); app
    `DeviceCalendarService` (`data/services/device_calendar_service.dart`)
    and `Ics.endOf`. Tests: app `test/ui/add_to_calendar_test.dart`,
    `test/ui/event_navigation_test.dart` ("with one team, the Teams tab
    shows the list"); shared `calendar_links.test.ts`. The website's
    side is checked by typecheck and by hand; the native editor only on
    a device.

38. Team page: stat tiles, roster lines, invites pending, More (F18,
    F23, F28): [x] app; [x] website. **Stat tiles** (members, under the
    header on the app, atop the feed on the website): "N going" to the
    next event (its Going answers; opens it) and "N new in chat" (the
    team's rooms the member can read with messages they haven't read,
    rooms not messages; amber while any; opens Chat), from data the page
    already reads (the app's shared room and read listeners; the
    website's chat-page room queries and one `chatReads` doc). No
    win–loss tile: results aren't kept anywhere cheap to read.
    **Roster:** each player's row shows the linked member's role (a staff
    tier as a tag/pill, custom roles after it). Once anyone has a line the
    roster is grouped O-line, D-line, Both lines, Unassigned; a team's
    admins (manageTeam) get "Edit lines" (O / D / Both on every row,
    tapping the picked one clears it; Save lines / Cancel). Lines are a
    roster spot's `line` (`o`, `d`, `both`), not a position and not a
    stats game's lines; `PUT /v1/teams/:id/roster-lines` writes them
    (teams only; every spot must exist); the rules let a client keep or
    drop a line when it saves a spot, never set one, and the API's
    `roster-players` save keeps it. It's in Download your data (roster
    spots' `line`) and goes with the spot. **Invites pending** (those who
    invite people: manageMembers, or the linked school or club's member
    managers): who's invited and hasn't answered, with who invited them
    and when, newest first, and Withdraw ("Withdraw the invite to …?");
    neutral, not amber. `GET /v1/teams/:id/invites` finds them by
    `teamId`, which invites now carry (rules allow it, only the team's
    own); invites sent before that aren't listed. **More:** each row has
    a line on what's there (Playbook "Plays and whiteboards", Videos
    "Game film and highlights", Stats "Games, lines and player stats",
    Tournaments "Events your team has entered", Meetings "Video calls
    with the team"); a team's admins get "Manage team" ("Details,
    sections and visibility", opens Settings) and everyone but the owner
    "Leave team" at the bottom with the usual confirm (the owner is told
    to make someone else the owner first). The website's More menu has
    the same rows and Settings' own leave confirm; Leave also stays in
    Settings, and in the header menu on the app, for pages with no
    More. "Manage team" is for teams only: groups have no Settings
    screen on the app (their admins use Edit community). Data:
    `rosterLines`, `groupByLine`, `setRosterLinesRequestSchema`,
    `PendingInvites`, `goingCount`, `newInChatDescription`,
    `teamMoreSubtitles`, `manageRowLabel` in `@stall10/shared`; app
    `RosterLine`, `groupByLine`, `teamMoreSubtitle`. Tests: app
    `test/ui/team_page_slice_test.dart`, `test/domain/team_page_test.dart`;
    API `roster_lines.test.ts`, `data_export.test.ts`,
    `membership.test.ts`; shared `team_page.test.ts`; rules "a spot's
    line is the API's" and "an invite may name its team". The website's
    side is checked by typecheck and by hand.
39. Polls in team rooms (F33): [x] app; [x] website. Anyone who can post
    in a room picks "Poll" in the composer's attach menu (app: the +
    menu; website: 📎): a question (up to 200 characters), 2–6 options
    (up to 80 each, all different), "Allow multiple answers" and an
    optional closing time (in the future). It posts a message carrying
    `poll` (question, options, multiple, closesAt, votes, voterIds),
    shown as a card: the question, "Pick one" / "Pick any", each option
    with its count and bar (the viewer's picks in turf, ticked), the
    number of votes, "Closes …" or "Poll closed", and an amber "Vote"
    while it's open and the viewer hasn't voted. Anyone who can read the
    room votes: click an option, again to take it back; a single-choice
    poll swaps. "See votes" lists who picked each option by name: votes
    aren't anonymous (they sit on the message every reader reads; an
    anonymous mode would need a separate store, not built). Its author,
    the owner and chat managers who can read the room close it early
    ("Close poll", confirmed); a closed or past-closing poll takes no
    votes. Deleting the message deletes the poll. The card listens to
    its own message (older pages of a thread aren't live). The push says
    "<name> posted a poll: <question>"; previews and reply quotes say
    "📊 <question>"; votes don't push. API-only (`POST
    /v1/teams/:id/chats/:room/polls`, `PUT .../messages/:id/vote` with
    the whole choice, `[]` taking it back, `POST
    .../messages/:id/close-poll`), each re-checking membership and room
    access in a transaction; firestore.rules already keeps clients from
    setting `poll` (message create lists its fields; updates may only
    react), so no rules change. The app needs `API_BASE_URL` for them.
    Votes are user data: Download your data has `pollVotes` (each poll
    they voted in with their own picks) and the question and options of
    polls they posted; deleting the account removes their votes from
    their teams' rooms (`poll.votes.<uid>` and `poll.voterIds`, room by
    room) and their own polls with their messages. Team rooms only, not
    direct messages. Data: `createChatPollRequestSchema`,
    `voteChatPollRequestSchema`, `chatPollTally`, `chatPollToggle`,
    `chatPollClosed` and the limits in `@stall10/shared`
    (`chat_extras.ts`); app `ChatPoll`. Tests: API
    `test/chat_extras.test.ts` ("polls"), `data_export.test.ts`; shared
    `chat_polls.test.ts`; functions `test/notifications/model.test.ts`,
    `test/account/model.test.ts`; app `test/ui/chat_polls_test.dart`,
    `test/data/chat_extras_api_test.dart`. The website's side is checked
    by typecheck and by hand.
40. Team feed: pinned posts, comments and the post box (F24): [x] app;
    [x] website. **Pinned:** a team's admins (manageTeam, who post for it)
    pin a post (app: the post's ⋯ menu "Pin to the top" / "Unpin";
    website: Pin / Unpin beside Edit). Pinned posts come first in the
    team feed, newest pin first, each with a "Pinned" label, then the rest
    newest first; at most 3 a team: pinning a 4th asks which pin to take
    down and swaps them in one write. A deleted post's pin goes with it.
    Pinned posts load with their own query (orderBy `pinnedAt`, limit 3;
    non-members add `public == true`), so an old pinned post still shows;
    outsiders see only public pinned posts, and visitors' team page
    (`GET /v1/public/teams/:id`) sends them first with `pinnedAt` (never
    who pinned). Home's feeds stay newest first. **Comments:** each post on
    the team page ends with "Comment" / "1 comment" / "N comments", for
    members; it opens the thread (app: a sheet; website: under the post),
    oldest first, the newest 100, with a box to add one (up to 1000
    characters, trimmed). Members comment on any of the team's posts,
    public or not; outsiders and visitors see neither the thread nor the
    count. Its author or a team admin deletes a comment (confirmed); no
    editing, likes, replies or pushes. The count is the post's
    `commentCount`, kept by the `follows-teamPostCommentCount` function
    (missing reads as 0, so posts read "Comment" until it runs);
    `follows-teamPostDeleted` deletes a post's comments with it (by the
    app, the API or its team). **Post box:** admins get a "Post to the
    team…" box ("Post to the community…" for a community) at the top of
    the posts, opening the existing editor (app: the New post dialog, in
    place of the old New post buttons; website: the composer opens in
    place). Data: `teams/{id}/posts/{postId}`: `pinnedAt`, `pinnedBy`,
    `commentCount`; `.../comments/{id}` (`authorId`, `authorName`, `body`,
    `createdAt`); `teams/{id}/feed/pins` (`ids`, server-only, for the
    limit). `teamPostPinsMax`, `pinTeamPostRequestSchema`,
    `teamPostCommentRequestSchema`, `teamPostCommentLimits`,
    `arrangeTeamFeed`, `teamPostCommentLabel` in `@stall10/shared`
    (`team_posts.ts`); the app's `arrangeTeamFeed`,
    `teamPostCommentLabel`, `TeamPostComment` match. API-only (`PUT|DELETE
    /v1/teams/:id/posts/:postId/pin` with `{unpin?}`, `POST
    .../posts/:postId/comments`, `DELETE .../comments/:commentId`), so
    the app needs `API_BASE_URL` to pin or comment (it still reads
    them). Rules: the post's key lists leave out the three fields;
    members get and list comments (`capped(100)`), no client writes
    them. Index: posts `public` + `pinnedAt` desc. Account deletion and
    Download your data cover comments (collection group `comments`).
    **Audience picker (F8), checked:** both platforms' Home box posts to
    Everyone or a team the member manages ("To" chip); a team post is
    members-only unless Public (no Public for a private group). There's
    no Followers choice on either: not built (redesign-plan "Waiting for
    you"). Tests: API `test/team_post_extras.test.ts`, `browse.test.ts`
    (pinned first); shared `team_posts.test.ts`; rules "team post pins
    and comments"; app `test/ui/team_feed_extras_test.dart`,
    `team_home_test.dart` (the box). The website's side is checked by
    typecheck and by hand.
41. Role presets and per-person permissions (F25): [x] app; [x] website.
    The owner opens a member's permissions (app: the member's menu in
    Members, "Permissions"; website: Settings › Roles, the "Permissions"
    column's Edit) and picks a preset in one tap: Member (none), Stat
    keeper (Keep stats), Captain (Manage chats, Manage events, Moderate,
    Keep stats), Coach (Manage team, Manage members, Manage events, Keep
    stats) or Admin (all); a group's are Member, Moderator, Organizer and
    Admin (no Keep stats). Below, a switch per permission with its
    one-line description; a mix no preset matches reads "Custom".
    Permissions a custom role already gives show on and locked, naming
    the role. The member's row shows "Player · <preset or Custom>".
    Only the owner, never on themselves (the owner has everything) nor
    on a legacy coach or captain (make them a player first). Data:
    `memberGrants.{uid}` on the team doc, API-only (`PUT
    /v1/teams/:id/members/:uid/permissions` `{perms}`); `memberPerms` (what
    the rules, the API, the functions and both apps check) is the union
    of the person's roles' permissions and their own, recomputed by every
    writer (roles save, Discord import, the communities mirror); Keep
    stats also keeps `statKeepers` in step. Removing a member drops their
    grants (the rule requires it). No client writes `memberGrants`, so
    nobody grants themselves anything. `teamRolePresets`,
    `groupRolePresets`, `presetMatching`, `cleanMemberGrants`,
    `memberPermsFor` (with grants), `setMemberPermissionsRequestSchema`
    in `@stall10/shared` (`membership.ts`); the app's `RolePreset`,
    `memberPermsFor` match (fixtures `team_roles.json`,
    `role_presets.json`). Download your data lists them with the
    person's permissions. Tests: API `test/membership.test.ts`
    ("per-person permissions"); shared `role_presets.test.ts`; rules
    "custom roles" (memberGrants); functions
    `test/communities/model.test.ts`; app `test/ui/member_permissions_test.dart`,
    `test/domain/team_role_test.dart`, `test/data/shared_fixtures_test.dart`.
    The website's side is checked by typecheck and by hand.
42. Team join requests (F26): [x] app; [x] website. A team's admins
    (Manage team) turn on "Allow join requests" in Settings › Visibility
    (off by default; not on a league's team; groups keep "Approve who
    joins"). Turning it off asks first and declines everyone waiting.
    While on, a signed-in outsider sees "Request to join" on the team's
    page (app: a card with Request to join / Cancel request and Use a
    code; website: the banner's button, "Requested" with Cancel, and
    "Ask to join, or have a code?"). Member managers see the requests
    (app: Members tab and Home's Needs you; website: the invite dialog's
    Requests pane and Home's Needs you) and Approve or Decline; the
    requester can cancel. Approval runs the same server checks as any
    join: already a member, the flood mute and, for a club team, the age
    rule (16+, birth date needed), checked at the request too. A new
    request pushes to the owner, coaches, captains and Manage members
    holders (groups too); approval pushes "You're in: <team>" to the
    requester. Data: `allowJoinRequests: true` on the team doc and its
    listing (removed when off), via `PUT
    /v1/teams/:id/allow-join-requests` `{on}`;
    `teams/{id}/joinRequests/{uid}` (`name`, `createdAt`), written for
    teams only by the API (the rules' create and approve stay
    group-only); the asker and member managers read and delete it.
    Account deletion deletes the person's requests and Download your
    data lists them (`joinRequests`). `allowsJoinRequests`,
    `takesJoinRequests`, `allowJoinRequestsDescription`,
    `setAllowJoinRequestsRequestSchema` in `@stall10/shared` (`team.ts`);
    the app's `TeamListing.takesRequests` matches (fixture
    `team_listing.json`). Tests: API `test/membership.test.ts` ("allow
    join requests", "team join requests", club age "join requests"),
    `data_export.test.ts`; shared `join_requests.test.ts`; rules "team
    join requests (allowJoinRequests)"; functions
    `test/notifications/model.test.ts` ("join requests"); app
    `test/ui/team_join_requests_test.dart`. The website's side is checked
    by typecheck and by hand.
43. Discord import: pick channels (F15): [x] app; [x] website. After
    Preview, a "Pick channels" list shows the template's text channels
    grouped by category as Discord lists them (no category first), each
    with a box, a box per category (all / some / none of its channels)
    and All / None; everything starts ticked and a new preview starts
    over. Only ticked channels become rooms; roles all come across. A
    category whose channels are all unticked isn't made (one with no
    channels in the template still is, as before). In a community with
    teams, "Where rooms go" lists only the ticked rooms, keeps a choice
    made for a room while it's unticked, and an unticked room never goes
    to a team or moves out of the community chat. No API or data change:
    the client cuts the plan down before mapping it (app: writes as
    before; website: sends the cut-down plan, with destinations by its
    room indexes, to `POST /v1/teams/:id/discord/import`, which checks
    it as any plan). `channelGroups`, `allChannels`, `pickRooms`,
    `pickedDestinations` in `@stall10/shared` (`discord.ts`); the app's
    `ChannelGroup.of`, `PickedPlan.of` match (fixture
    `discord/pick.json`). Tests: shared `discord.test.ts` ("picking
    channels"), `discord_fixtures.test.ts`; app
    `test/ui/discord_import_test.dart`,
    `test/shared_fixtures/discord_fixtures_test.dart`. The website's side
    is checked by typecheck and by hand.

44. Community page (F27): [x] app; [x] website. A pickup community's or
    a school or club's page (not a team's) leads with its next event
    (the first one the viewer can see that isn't over): "Next pickup"
    ("Next event" for a school or club) with the date tile, title, time,
    place and "N going", and Going / Maybe / Can't go with counts (the
    event screen's control; the same `setRsvp` / `PUT
    .../events/:id/rsvp` path and rules as the schedule; picking the
    current answer takes it back, and its note with it) and an amber "RSVP
    needed" while the member hasn't answered. Tapping it opens the event.
    It takes the dark Up next card's place; Coming up lists the events
    after it (and hides when there are none). With nothing ahead, members
    see a quiet "No pickup scheduled" ("No events scheduled"), with New
    event for those who manage events (app: the event editor; website:
    the schedule's editor via `?new=event`). Outsiders of a group that
    isn't private see the public event (no answers, no count) with "Join
    the community to RSVP." and Join (the page's join path, so the
    separate join card goes while it shows; a group that approves members
    is private to outsiders, so they never see the card);
    with no public event ahead they keep the join card; signed-out
    visitors on the website get "Log in to join". A private group shows
    outsiders nothing new. **Chat rooms** (members): the rooms they can read,
    unread ones first (newest first) with an amber dot, then the rest in
    order, up to 5, each opening its room; "All chat" (with "+N" when
    more) opens Chat. From the listeners the stat tiles already use (the
    website's tiles and section now share one `useTeamChatRooms`).
    **Organizers** (members): the owner, then anyone with a coach or
    captain tier, or Manage team, members or events from their roles or
    their own switches (F25), by name, labelled Owner, by tier, or by the
    group preset their permissions match (Admin, Organizer), else
    Organizer; chat moderators alone aren't listed. Initials avatars (the
    team doc has names only) and Message for everyone but the viewer
    (the profile's direct-message flow: `openConversation` / `POST
    /v1/conversations`). The stat tiles stay. No new data, API or rules.
    Data: `chatSectionRooms`, `chatSectionMax`, `communityOrganizers`,
    `organizerPermissions`, `nextEventCardText` in `@stall10/shared`
    (`team_page.ts`); the app's twins in `team_page.dart`. Tests: shared
    `team_page.test.ts` ("community page"); app
    `test/ui/community_page_test.dart`, `test/domain/team_page_test.dart`.
    The website's side is checked by typecheck and by hand.
Out of scope: payments, meeting recording, USA Ultimate data.
45. Chat reactions bubble: [x] app; [x] website. Double-tap (website:
    double-click, or React) a message for a bubble of the quick reactions
    ❤️ 👍 👎 😂 ‼️ ❓ just above it, with + for every emoji by group (the
    same list on both, `fixtures/chat_reactions/choices.json`); the
    user's own reaction is highlighted, picking it again takes it back,
    and one picked from + shows in the bubble. The app's long-press sheet
    has the + too. The API accepts any one emoji (`isChatReaction`), not
    only the quick ones. Tests: app `messages_test.dart` (double-tap
    bubble), `chat_reactions_fixtures_test.dart`; shared
    `chat_reactions_fixtures.test.ts`; API `hub.test.ts`,
    `conversations.test.ts`. The website's bubble has no test runner
    (typecheck and build only).
46. RSVP buttons: [x] app; [x] website (already separate buttons). The
    app's Going / Maybe / Can't go are separate outlined buttons, filled
    when chosen, and change straight away on the event, meeting and
    community cards (they were switched off after the first save until
    the event was reopened).
47. Typed times: [x] app; [x] website (time inputs already typed). The
    app's time pickers open on the hour and minute boxes with the hour
    focused; the clock icon switches to the dial. Test:
    `time_picker_test.dart`.
48. New shared calendar from the event editor: [x] app; [x] website. A
    new event's calendar choice offers "New shared calendar": name,
    color, Can view / Can edit and people to invite, made on the spot
    (`POST /v1/me/calendars`, then `.../invites`) with the event put on
    it; invites that fail say so. Tests: app `calendars_test.dart`
    (create, invite, select, save); website typecheck and build only.
49. Share an event: [x] app; [x] website. Beside Add to calendar: the
    share sheet with the .ics and "Title · when · where" (website: the
    browser's share sheet, else copies the text). Test: app
    `add_to_calendar_test.dart`.
50. Calendars on the Schedule tab: [x] app; [x] website (already). A
    Calendars button in the header and a Calendars card under the days:
    each calendar with its owner and role, Manage, Share a calendar, and
    Outlook, Apple or Google Calendar, all opening Calendars.
51. Report (App Store 1.2): [x] app; [x] website. Posts, comments, team
    posts and their comments, team chat, direct messages and profiles:
    a reason (`reportReasons`), optional details, "Also block". Tests:
    app `report_block_test.dart`; API `moderation.test.ts`.
52. Block and unblock: [x] app; [x] website. From profiles and direct
    conversations; both hide posts, reposts, comments, message requests
    and group messages from people blocked either way, show a blocked
    profile as the name only, and replace a blocked conversation's
    composer. Team chat and posts stay. Rules tests `blocks.rules.test.ts`.
53. Blocked accounts in Settings: [x] app; [x] website.
54. A team's Reports (owner, admins, `moderate`): [x] app (Team settings
    › Safety); [x] website (Team settings). Remove or dismiss.
55. Staff report queue: website only (`/staff`), by design: it's a staff
    tool, not a member feature (remove, dismiss, warn, suspend).
56. Staff badge: [x] app; [x] website. "Stall 10 staff" by the name on a
    staff member's profile, from `staff/{uid}` (only `set-staff.mjs`
    writes it). Tests: app `player_profile_test.dart`; rules
    `blocks.rules.test.ts`.
57. Word filter: [x] app; [x] website. Slurs, hate terms and "kill
    yourself" are refused with the guidelines message; mild swearing is
    saved masked. One set of lists and rules (`packages/shared`
    `word_filter.ts`, the app's `word_filter.dart`, the functions' copy),
    all tested against `packages/shared/fixtures/word_filter/`. The
    website gets it from the API's schemas; the app filters before its
    direct writes; the `api` functions' triggers catch older builds.
    Tests: shared `word_filter.test.ts`, API `word_filter.test.ts`, app
    `test/domain/word_filter_test.dart`, functions
    `test/moderation/word_filter.test.ts`.
58. Photo checks: [x] app; [x] website. Cloud Vision SafeSearch on every
    photo upload (API `media/vision.ts`, policy `safe_search.ts`); older
    builds' direct uploads are checked by the `photoCheck` function and
    deleted if unsafe. Tests: API `media.test.ts`, functions
    `test/moderation/photo_check.test.ts`.
59. Calendar Subscribe: [x] app; [x] website. One Subscribe button with
    the device's calendar apps (`subscribeOptions`, shared and Dart).
    Tests: shared `subscribe_options.test.ts`, app
    `test/domain/subscribe_options_test.dart` and `calendars_test.dart`.
60. Repeating events: [x] app; [x] website. A new team, My calendar or
    shared-calendar event can repeat daily, weekly, every 2 weeks or
    monthly until an end date (at most 100 events, a year), written as
    one event per occurrence with `series` (`recurrence.ts`, the app's
    `recurrence.dart`, tested against `packages/shared/fixtures/recurrence/`).
    Edits and deletes ask "this event" or "this and following events"
    (`?scope=following` on the API). The website and shared calendars go
    through the API with the device's time zone; the app writes team and
    My calendar series to Firestore (`validSeries` in the rules). One
    notification per series or bulk change. Tests: shared
    `recurrence.test.ts`, API `hub.test.ts` and `calendar.test.ts`, app
    `test/domain/recurrence_test.dart`, `schedule_viewmodels_test.dart`
    and `event_editor_screen_test.dart`, rules and functions
    `notifications/model.test.ts`.
61. Directions: [x] app; [x] website. Directions to an event's place
    (and a group's map in the app) asks for the app: Apple Maps on Apple
    devices, Google Maps, Waze (`directionsOptions`, shared and Dart;
    web links that open the app when installed). Tests: shared
    `directions_fixtures.test.ts`, app
    `test/shared_fixtures/directions_fixtures_test.dart`.
62. Tournament chats with the organizers: [x] app; [x] website. A hosted
    tournament's Captains' channel (organizers with Manage events and the
    captains of applied, accepted and waitlisted teams) and each team's
    private thread with the organizers, in Messages; the server sets who
    is in them (the API when opened from the tournament page,
    `tournaments-chatMembers` on entry changes), and nobody adds, leaves
    or renames. Someone who stops organizing or leaves a team reads on
    until the next of those. Not for drafts or
    player-only events. Tests: API `tournament_chats.test.ts`, functions
    `tournaments/chat_members.test.ts` and the rules tests, app
    `hosted_tournaments_test.dart` and `group_messages_test.dart`.
63. "At a tournament" tags: [x] app; [x] website. The composer lists
    followed tournaments from a week before they start to their last day
    (`GET /v1/me/tag-tournaments`, `tournamentTagOpen`), and the tag on a
    post opens the tournament. Tests: shared
    `tournament_tag_fixtures.test.ts`, API `post_tags_events.test.ts`, app
    `test/shared_fixtures/tournament_tag_fixtures_test.dart`,
    `inline_composer_test.dart` and `shared_event_test.dart`.
64. Agree to the Community Guidelines and Terms: [x] app; [x] website.
    Every member, once per `termsVersion` (`agreements.ts` / `agreement.dart`),
    after the username step and before About you
    (`GET`/`PUT /v1/me/agreement`). Tests: API `account.test.ts`, shared
    `agreement_fixtures.test.ts`, app `auth_redirect_test.dart`,
    `agree_terms_test.dart` and `shared_fixtures/agreement_fixtures_test.dart`.
65. Composer header, body and footer: [x] app; [x] website. Avatar (opens
    the profile), name and "Posting to" with the audience; the post; the
    tools and Send. Hint from `postPrompts`. Tests: app
    `inline_composer_test.dart`, shared `post_prompts_fixtures.test.ts`.
66. Chats, not Inbox; messages only in Chats: [x] app; [x] website.
    Messages push but have no Notifications entry (functions `feed:
    false`); the Chats tab's bubble leaves out muted conversations and
    rooms, and muted rows show no unread dot. Tests: app `shell_test.dart`,
    functions `notifications/model.test.ts`, shared
    `team_chats_fixtures.test.ts`.
67. Back from a notification goes to its parent page: [x] app; [x]
    website (`openFromNotifications`; `webParent`). Tests: app
    `open_link_test.dart`, shared `routes.test.ts`.

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
