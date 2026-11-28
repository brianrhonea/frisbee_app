# Navigation route map

**Task P3 on the UI rework board.** Baseline `39c8a53`.

This is the checklist the navigation tests (N1–N12) cover. Every route below must still open, from the same places, after the UI rework. The rework changes the **look** of navigation and two things the owner approved:

- The tab order becomes Home · Discover · **Teams · Schedule** · Chats (UI-Q11).
- The profile opens from your picture at the top right (no profile tab).

Nothing else about routing changes.

Sources:
- App: `apps/mobile/lib/routing/router.dart`, `routes.dart`, `tournament_routes.dart` and `lib/ui/shell/widgets/app_shell.dart`.
- Website: `apps/web/app/**/page.tsx` and `apps/web/components/AppFrame.tsx`.

## 1. Tabs

| Tab | App branch (today's index) | App path | Website path | Website "also" paths (highlight the tab) |
|---|---|---|---|---|
| Home | 0 | `/home` | `/` (also `/home`) | `/community`, `/posts` |
| Discover | 1 | `/explore` (`/discover` redirects) | `/explore` | `/players`, `/rankings`, `/tournaments`, `/events`, `/discover` |
| Schedule | 2 → **3** | `/schedule` | `/schedule` | — |
| Teams | 3 → **2** | `/teams` | `/teams` | — |
| Chats | 4 | `/messages` | `/messages` | — |
| (profile) | 5, hidden branch | `/profile` | `/profile` | Opens from the picture at the top right; no tab |
| Learn | — | `/learn`, pushed over the page | `/learn` (6th tab today) | Moves under Discover on the website (UI-Q5) |

**Tab behaviour to keep:**
- Each branch keeps its own stack.
- Tapping the active tab again returns to its first page (`goBranch(initialLocation: again)`, `app_shell.dart:85`).
- Badges show unread chats and notifications.
- The Teams tab always opens the team list.

**Order change.** Swapping Schedule and Teams changes the branch **index**. The only code that depends on it is `ShellSection.values[navigationShell.currentIndex]` and `goBranch(s.index, ...)` (`app_shell.dart:77-85`). So the `ShellSection` enum and the `StatefulShellBranch` list in `router.dart:694-1054` must be reordered together.

## 2. Sign-in and redirects (app)

`authRedirect` (`router.dart:1100`) governs this. Only `/sign-in` and `/sign-up` are public in the app.

| Situation | Today's behaviour (tested in `test/routing/auth_redirect_test.dart`) |
|---|---|
| Auth not ready | `/splash?from=<target>` |
| Signed out, private route | `/sign-in?from=<target>` (no `from` for Home) |
| Signing in | **Lands on Home**, except a `from` of `/join/...` or `/g/...` (invite links), which carry on there |
| Opening the app signed in | Carries on to `from` |
| No username, or no name | `/welcome/username?from=<target>`, then terms, then details |

The board's N2 said "come back to the same page after sign-in". That is **not** today's behaviour: only invite links come back. N2 is corrected to test today's behaviour.

## 3. App routes

**Opening style:**
- **Tab**: inside the tab shell.
- **Over**: pushed over the shell with `context.push`, so back returns to where you were.
- **Redirect**: old links forwarded elsewhere.

### Sign-in and links

| Path | Opens | Style |
|---|---|---|
| `/splash` | Waiting for auth | Root |
| `/sign-in`, `/sign-up` | Sign in, sign up | Root, public |
| `/welcome/username`, `/welcome/terms`, `/welcome/details` | Sign-up steps | Root |
| `/join/:code` | Invite link | Root |
| `/g/:groupId` | → `/teams/:groupId` | Redirect |
| `/p/:postId` | → `/posts/:postId` | Redirect |
| `/people/:uid` | Another player's profile | Over |
| `/rules` | → `/learn?part=rules` | Redirect |

### Home, Discover, profile

| Path | Opens | Style |
|---|---|---|
| `/home` | Home feed | Tab |
| `/explore?q=&only=` | Discover (filters: teams, groups, players, tournaments, leagues, pickup) | Tab |
| `/discover` | → `/explore` | Redirect |
| `/rankings` | Rankings | Tab (Discover) |
| `/players/:uid` | Player profile | Tab (Discover) |
| `/posts/:postId` (`?comment=1`) | Post | Over |
| `/record` | Record a workout | Over |
| `/learn` (`?part=rules`) | Learn to play | Over |
| `/profile`, `/profile/following` | Your profile, who you follow | Profile branch / over |

### Settings and notifications (slide over)

| Path | Opens |
|---|---|
| `/settings` | Settings |
| `/settings/general`, `/settings/privacy`, `/settings/account`, `/settings/personal`, `/settings/calendar`, `/settings/help`, `/settings/following` | Settings sections |
| `/notifications` | Notifications |
| `/notifications/follow-requests`, `/notifications/settings` | Follow requests, notification settings |

### Schedule and events

| Path | Opens | Style |
|---|---|---|
| `/schedule` | Your calendar | Tab |
| `/team-events/:teamId/new` (`?date=`), `/:eventId`, `/:eventId/edit` | Team event | Over |
| `/my-events/new`, `/:eventId`, `/:eventId/edit` | Personal event | Over |
| `/calendars/:calendarId/events/:eventId/edit` | Other calendar's event | Over |

### Teams

| Path | Opens | Style |
|---|---|---|
| `/teams` | Team list | Tab |
| `/teams/new` (`?kind=community`, `?kind=organization`) | Create team, group or community | Tab |
| `/teams/search` | → `/explore?only=teams` | Redirect |
| `/teams/:teamId?section=` | Team page and its sections:<br>`teams`, `events`, `chat`, `roster`, `playbook`, `videos`, `stats`, `tournaments`, `members`<br>Old `/teams/:id/<section>` paths redirect here | Tab |
| `/over/teams/:teamId` | Team page over a full-screen page (a tournament, or the Chats tab) | Over |
| `/over/teams/:teamId/chats/new`, `/chats/:roomId`, `/chats/:roomId/settings` | The team's chat pages in the same "over" context: from Chats, back goes room, then the team's chat list, then Chats; the tab bar stays on Chats (NAV1) | Over |
| `/teams/:teamId/roles`, `/discord` | Roles, Discord import | Over |
| `/teams/:teamId/chats/new` (`?folder=`), `/chats/:roomId`, `/chats/:roomId/settings` | Team chat rooms | Over |
| `/teams/:teamId/plays/new`, `/plays/:playId`, `/whiteboards/new`, `/whiteboards/:playId` | Playbook | Over |
| `/teams/:teamId/stats/season`, `/stats/tournaments/:id`, `/stats/games/:id` | Stats | Over |
| `/team-videos/:teamId/new`, `/:videoId`, `/:videoId/edit` | Film | Over |
| `/team-meetings/:teamId`, `/new`, `/:meetingId`, `/:meetingId/edit`, `/:meetingId/room` | Meetings and voice | Over |
| `/group-tournaments/:groupId/new`, `/:id`, `/:id/edit` | Group hat tournaments | Over |

### Chats

| Path | Opens | Style |
|---|---|---|
| `/messages` | Inbox | Tab |
| `/messages/new`, `/messages/new-group` (`?to=`) | New message or group | Over |
| `/messages/:conversationId` | Conversation | Over |

### Tournaments (full screen over the tabs)

| Path | Opens |
|---|---|
| `/tournaments` | Tournament list |
| `/tournaments/host`, `/tournaments/new?host=&type=` | Host a tournament |
| `/tournaments/:id` (`?host=&division=&game=&tab=`), `/:id/edit` | Tournament, edit |
| `/tournaments/:id/respond` (`?team=&step=`) | Accept, roster, pay |
| `/tournaments/:id/draft/:div`, `/live-draft/:div`, `/bracket/:div` | Draft, live draft, bracket |

## 4. Website routes

**Who can open each page:**
- **All**: signed-out visitors as well.
- **Member**: signed in.

The visitor list follows the visitor-access rule: signed-out visitors see Learn, events, teams and tournaments, but youth rosters and community member lists stay private. N8 checks each page against this table, signed in and out.

| Path | Page | Who |
|---|---|---|
| `/`, `/home`, `/community` | Home | Member (visitors see a preview) |
| `/explore`, `/rankings`, `/players/[uid]` | Discover, rankings, player | All |
| `/posts/[postId]`, `/p/[id]` | Post, short link | Member |
| `/learn`, `/get-the-app`, `/[slug]` (about, help, privacy…) | Info pages | All |
| `/schedule` | Your calendar | Member |
| `/teams`, `/teams/new` | Teams, create | Member |
| `/teams/[teamId]` + `chat`, `roster`, `schedule`, `playbook`, `plays`, `plays/[playId]`, `whiteboards`, `whiteboards/[playId]`, `videos`, `videos/[videoId]`, `stats`, `stats/players`, `stats/season`, `stats/games/[id]`, `stats/tournaments/[id]`, `tournaments`, `tournaments/new`, `tournaments/[id]`, `tournaments/[id]/edit`, `meetings`, `meetings/[id]`, `meetings/[id]/edit`, `meetings/[id]/room`, `teams`, `more`, `settings` | Team pages | Team page: All. Sections: Member, by role |
| `/g/[id]`, `/join/[code]` | Group and invite links | All |
| `/messages` | Chats | Member |
| `/notifications`, `/notifications/requests` | Notifications | Member |
| `/profile` | Your profile | Member |
| `/settings` + `account`, `blocked`, `calendar`, `following`, `help`, `notifications`, `personal`, `privacy`, `profile`, `requests` | Settings | Member |
| `/tournaments`, `/tournaments/[id]`, `bracket` | Tournaments | All |
| `/tournaments/host`, `new`, `[id]/edit`, `enter`, `respond`, `signups`, `draft/[div]`, `live-draft/[div]` | Host and enter | Member |
| `/payments/done`, `/payments/payouts`, `/embed/payouts` | Payments | Member; gated |
| `/staff` | Moderation | Staff only |
| `/sign-in`, `/sign-up` | Auth | All |

## 5. Links that must open the same page on both (N11)

| Link | App | Website |
|---|---|---|
| Team | `/teams/:id` | `/teams/[id]` |
| Team section | `/teams/:id?section=roster` | `/teams/[id]/roster` |
| Group | `/g/:id` | `/g/[id]` |
| Invite | `/join/:code` | `/join/[code]` |
| Post | `/posts/:id`, `/p/:id` | `/posts/[id]`, `/p/[id]` |
| Player | `/players/:uid` | `/players/[uid]` |
| Discover filter | `/explore?only=teams&q=` | `/explore?only=teams&q=` |
| Rankings | `/rankings?level=&division=` | `/rankings?...` |
| Tournament | `/tournaments/:id` (`?tab=&game=`) | `/tournaments/[id]` |
| Respond | `/tournaments/:id/respond?team=&step=` | same |
| Bracket | `/tournaments/:id/bracket/:div` | `/tournaments/[id]/bracket?division=` |
| Live draft | `/tournaments/:id/live-draft/:div` | same |
| Meeting | `/team-meetings/:team/:id` | `/teams/[team]/meetings/[id]` |
| Learn rules | `/learn?part=rules`, `/rules` | `/learn` |

## 6. Existing navigation tests

| File | Covers |
|---|---|
| `apps/mobile/test/routing/auth_redirect_test.dart` | Splash, sign-in, invite-link and username redirects |
| `apps/mobile/test/routing/open_link_test.dart` | Opening links |
| Website | None yet; added in P6 and N8–N11 |

Gaps that N1–N11 fill:
- every route resolving;
- the tab order and branch stacks;
- widths;
- notification deep links from a cold start;
- the website in general;
- cross-platform link parity.
