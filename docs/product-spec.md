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

## 9. Open questions

- News articles: are official posts enough, or is a longer article format
  wanted for the website? (Start with posts.)
- Which community types need their own rules beyond College (for example,
  youth safeguarding for School / youth)?
- What happens to existing groups and schools/clubs: migrate each to a
  community type automatically, or ask their admins to pick one?
