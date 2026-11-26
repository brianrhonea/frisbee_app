# Web UI inventory against the UI Implementation Guide (apps/web, web 0.59.5, 39c8a53)

This is a read-only review. I did not run a server, tests or a browser, so nothing here has been rendered.

**Conventions**
- Paths are relative to `apps/web/` unless they start with `docs/`.
- "ferr" means a `className="form-error"` element with no `role="alert"` on the same element. I found these with a same-line grep, so a parent `aria-live` may still announce some of them. Treat those lists as SUSPECTED unless I note that I spot-checked them.
- Tests: **the website has no tests at all** (`docs/specifications/audit/web.md` §Tech debt). Every "Tests" line below lists tests that are needed, not tests that exist.
- **Hours** cover the restyle only. They assume the tokens and primitives from block 00 already exist.

## 00. Shell and global (do this first)

**Files**
- `app/layout.tsx`, which imports `site.css` then `app.css` (lines 11–12) and sets the theme colour with hex at lines 36–37.
- `components/AppFrame.tsx`, the shell.
- `app/site.css` (506 lines) and `app/app.css` (1,859 lines).
- `components/ThemeToggle.tsx` and `lib/theme.ts`.

**Token map: current to guide**

| Current token (`site.css:6-53`) | Guide token | Notes |
|---|---|---|
| `--bg` | Canvas | |
| `--card` | Surface | |
| `--field`, `--bg-2` | Raised | |
| `--ink` | Text | |
| `--muted`, `--ink-soft` | Muted | `--ink-soft` has no guide twin |
| `--line`, `--line-2` | Border | |
| `--accent` | Accent | Turf `#12805C`/`#3DBE8B` becomes indigo `#4338CA`/`#A5B4FC` |
| `--on-accent` | On accent | |
| `--live` | Live | |

Open decisions. I have not resolved any of these.
1. `--accent-soft` and `--accent-ink` have no guide value. The selected nav, pills and active tabs all depend on them (`app.css:497-499, 606, 245`).
2. `--danger` is an alias of `--live-ink` (`site.css:46`). The guide splits Error (`#B91C1C`) from Live (`#BE123C`).
3. `.form-ok` uses `--accent` (`app.css:633`). After the swap, "success" turns indigo, against the guide's rule that green is for success only. It needs a `--success` token.
4. Four current tokens have no guide equivalent:
   - `--board` (scoreboard navy). It is used by `.team-badge.organization` (`team_hub.css:48`) and by the play pieces.
   - `--disc` (amber "yours to do", unread `.count-badge`, `app.css:624-627`). It could map to Warning, but Warning `#92400E` is a text colour, not a badge fill.
   - `--team` and `--personal` (calendar dots). Doc 17 §04 says to keep these as supplemental colours.
5. The dark block appears twice, at `site.css:55-98` and `site.css:99-140`. Emit both copies from one generated source.
6. Only the Accent swap is a visible re-brand. I computed no contrast ratios for the guide pairs. `uiux.md` measured only the current palette.

**Typography and geometry**
- Inter and Barlow are already wired up: `layout.tsx:14,20`, `--font-score` at `site.css:52`, and Barlow used in 10 CSS files.
- `uiux.md` counts 462 `font-size` declarations with 86 distinct values, and 198 literal `border-radius` values. The work is to collapse them to the scale 12/14/16/20/24–32 and the radii 16/12/pill.
- There are no spacing tokens.
- `.btn` sets `min-height: 44px` (`site.css:196`) and `.btn-small` sets 36 px (`site.css:215`). `.icon-btn` is 36 px (`app.css:617`). The guide asks for 48.

**Breakpoints**

| Guide | Current |
|---|---|
| <600: bottom tabs | ≤640: tab row **under the top bar**, 6 member tabs including Learn, with 10.5 px labels (`app.css:586-608`) |
| 600–899: rail | 641–1000: icon rail (`app.css:570-584`) |
| 900–1199: sidebar | 1001–1200: sidebar |
| 1200+: contextual panel | >1200: `.frame-aside` 320 px (`app.css:428, 563`) |
| 1600+: cap reading width | No cap: `--wrap: 1160px` (`site.css:51`), `.page` 720 (`app.css:4`) |

- Ad-hoc breakpoints in use: 380, 420, 480, 560, 600, 640, 720, 760, 860, 900, 1000, 1100 and 1200 (`app.css`, `team_hub.css`, `member.css` and others).
- Moving the tabs to the bottom collides with three fixed or sticky elements:
  - the floating Post button (`.fab-post`, `app.css:1638-1643`);
  - the sticky `.voice-bar` (`voice.css:2-3`);
  - the hard-coded `top: 64px`/`56px` offsets (`app.css:478, 554, 595`, `.hub-detail` at 942, `.chat-rooms` at 977).
- The guide's five tabs leave out **Learn**, but the web has it (`AppFrame.tsx:41`). Moving it needs product-owner approval (uiux.md Q2), so I have flagged it rather than assumed it.

**Theme literals outside tokens**
- CSS hex/rgb counts: `app.css` 37, `voice.css` 8, `team_hub.css` 4, `member.css` 2, `tournaments.css` 2, `whiteboard.css` 1, `chat_attachments.css` 1. That is 146 in total including `site.css`'s 91, which are mostly token definitions.
- Theme overrides outside `site.css`:
  - `team_hub.css:50-53` (team badge in dark mode);
  - `voice.css:15-22` (light-mode text colours `#b45309`/`#15803d`, plus `#d97706`, `#16a34a`, `#fbbf24` and `#4ade80` at 9–12).
- Shadows use `rgb(0 0 0 / x)` literals at `app.css:240, 405, 654, 710, 925, 1317, 1643, 1794`.

**Preserve**
- Member tabs and visitor tabs with the `?only=` filter tabs (`AppFrame.tsx:34-54, 128-135`).
- `aria-current`, and the Home tab refresh on re-click (line 150).
- The `g`+letter, `/` and `n` keyboard shortcuts (84–123).
- The unread chat and notification badges (187–193).
- The `/embed/*` bare frame (212) and the `fullWidth` and `aside` rules (77, 183).
- The OfflineBanner, VoiceBar and MeetingAlerts, which render for members only (298–301).
- The theme script that runs before paint (Doc 17 §03).

**Accessibility**
- There is no skip link (uiux UX-11).
- There is a global `:focus-visible` ring (`site.css:220`, `app.css:1529-1534`).
- `.top-search input:focus { outline: none }` (`app.css:463`) is covered by the parent's `:focus-within` ring at 458.
- `.composer textarea` has `outline: none` with no replacement (`app.css:674`, W-B10).

**Tests to add**
- Vitest + RTL for the primitives.
- A Playwright smoke test for every route, with `@axe-core/playwright`.
- `toHaveScreenshot` at 375, 768, 1024, 1440 and 1680 px, in light and dark.
- A test that the theme doesn't flash on first paint.
- Keyboard-shortcut tests.

This is the harness `web.md` suggests (16 h, P1). It would add new dev dependencies, which need approval under CLAUDE.md §14.

**Hours:** 18 for the shell and breakpoints, plus 24 for tokens.css and the primitives. **Priority:** P0, a dependency for every block below.

---

## 01. Authentication and onboarding (P0)

- **Routes:**
  - `app/sign-in/page.tsx`, `app/sign-up/page.tsx`
  - The onboarding gates that wrap every route from `app/layout.tsx`.
  - `components/AuthForm.tsx` (374 lines), `SignUpSteps.tsx`, `UsernameStep.tsx`, `UsernameField.tsx`, `PersonalGate.tsx`, `AgreeTerms.tsx`, `PersonalDetailsForm.tsx`, `ClubAge.tsx`, `PasswordHints.tsx` and its CSS.
  - CSS: `app.css:140-170` (`.auth-*`).
- **Now:** a centred `.auth-card`, widening to 560 for sign-up (`app.css:144`). It has Google/Apple buttons, an "or" divider and 48 px primary buttons. Full width, with no aside.
- **Change:**
  - Swap the tokens.
  - Add the optional brand panel at 900 px and up.
  - The input border `--line` measures 1.29:1 (UX-7) and needs to reach 3:1.
- **Components:** reuse Button, ErrorNote and Dialog. Add a new TextField with label, hint and error.
- **Theme:** no literals.
- **Responsive:** `.page` padding switches at 640 (`app.css:1287`). Move it to 600.
- **Preserve:**
  - The `safeNext` redirect guard (`AuthForm.tsx:67-79`).
  - Email-or-username login and password reset (196, 257).
  - The PersonalGate and AgreeTerms flows. Keep their fail-open bug W-B1 as a separate P0 fix, not part of the restyle.
- **Accessibility:** no role on `AuthForm.tsx:114`, `AgreeTerms.tsx:68`, or `PersonalDetailsForm.tsx:215, 256`. The 215 error does have an `id` for `aria-describedby`, which I spot-checked.
- **Tests:** sign-in and sign-up e2e on emulators, plus axe on both routes.
- **Hours:** 4. **Depends on:** 00. **Feature – not approved:** email verification UI (no `sendEmailVerification`, web.md C-26).

## 02. Home / Following (P0)

- **Routes:**
  - `app/page.tsx`, a server-rendered visitor preview with `getPublic` and the `feed` tag. `app/home/page.tsx` redirects.
  - `HomeGate.tsx`, `Dashboard.tsx` (395 lines), `home/ForYou.tsx`, `NeedsYou.tsx`, `TeamStrip.tsx`, `StartOrJoin.tsx`, `useInfiniteFeed.tsx`, `Composer.tsx`, `PostCard.tsx`, `HomeCards.tsx`, `UpcomingAside.tsx`, `TournamentDayCard.tsx`.
  - CSS: `app.css:1198-1246` (`.huddle`), `home_feed.css`.
- **Now:** this already matches the guide's Web line. It has a sidebar, a feed capped at 760 (`.huddle-main`, `app.css:1201`), and a sticky right column with Upcoming events and RSVP pills (`Dashboard.tsx:314-363`).
- **Change:**
  - Swap the tokens.
  - Align the column breakpoints (1100 and 760, `app.css:1240-1246`) to 1200 and 600.
  - Restyle the next-event card on phones (`.huddle-phone`).
- **Components:** reuse Avatar, RsvpPill, EventItem, Composer and PostCard. Add new Tabs, DateBadge, Card and StatusPill.
- **Theme:** `TeamStrip.tsx` has one inline style.
- **Preserve:**
  - The visitor preview (3 posts) and its locked cards (`page.tsx:9-17`).
  - The Following / Your teams / Everyone tabs.
  - The keyboard behaviour on the ARIA tabs (`Dashboard.tsx:238-256`, the only tablist with arrow-key support).
  - Composing from the shell with `n`.
  - `requestHomeRefresh`.
  - The tournament-day card replacing the next event.
- **Accessibility:** no role on `Dashboard.tsx:197`. `:286` is a `p.empty aria-busy`, not `<Loading>`. `:292` is a `post-error` with no role.
- **Tests:** visitor home versus member home, keyboard on the tabs, and pagination.
- **Hours:** 6. **Depends on:** 00, Tabs, Card.

## 03. Explore, post detail and composer (P1)

- **Routes:**
  - `app/community/page.tsx` (visitor feed, `MoreFeed`) and `app/posts/[postId]/page.tsx`.
  - `PostPage.tsx`, `PostCard.tsx`, `PostActions.tsx`, `Comments.tsx`, `Composer.tsx` (726 lines), `ComposerPhotos.tsx`, `Mentions.tsx`, `Report.tsx`, `composer_tag.css`.
- **Now:** cards in the 720 `.page`. The post route uses the frame's aside.
- **Change:** swap the tokens. Put the composer focus ring on `.composer:focus-within`. The cap is already in place.
- **Components:** reuse Dialog (Report, two uses) and Avatar. Add a new Card.
- **Theme:** `app.css:683, 687` (`rgb(0 0 0 / 0.6)` photo scrims, which are acceptable).
- **Preserve:**
  - Comments are read only when signed in (`Comments.tsx:47`).
  - The IndexedDB outbox for posts.
  - The audience selector.
  - Report and block.
- **Accessibility:**
  - No role on `Comments.tsx:70`.
  - `PostCard.tsx` and `Comments.tsx` each have one `confirm()`, which should become Dialog.
  - W-B10 composer focus (`app.css:674`).
- **Tests:** composer draft recovery, private or deleted post states, report dialog.
- **Hours:** 4. **Depends on:** 02.
- **Feature – not approved:**
  - Bookmark/save (no code found).
  - A ranked "Explore" feed. The web has a chronological Everyone tab only (SUSPECTED).

## 04. Athlete profile (P1)

- **Routes:**
  - `app/profile/page.tsx`, which redirects to `/players/{uid}`, and `app/players/[uid]/page.tsx` (MembersOnly).
  - `PlayerPage.tsx` (324 lines), `ProfileDashboard.tsx`, `FollowButton.tsx`, `MessageButton.tsx`, `member.css`.
- **Now:** `.dash` grid with a 320 px profile card beside the main column (`app.css:247`), collapsing at 860 (353). Sections are Career, Recent games and Posts (`PlayerPage.tsx:237, 287, 305`).
- **Change:**
  - Use a header band, then the timeline, with stats in the 1200+ panel.
  - Align the 860 breakpoint to 900.
- **Components:** reuse Avatar. Add new SectionCard and StatTile.
- **Theme:** `ProfileDashboard.tsx:45` sets the header image inline, which is data-driven and fine.
- **Preserve:**
  - The private and blocked profile states (`PlayerPage.tsx:178, 210`).
  - Visitors have no access (MembersOnly).
- **Accessibility:** no role on `PlayerPage.tsx:105`. The page has two `confirm()` calls (block/unfollow, SUSPECTED).
- **Hours:** 4. **Feature – not approved:** Posts/Activity/Stats tabs. The web uses stacked sections instead.

## 05. Discover and search (P1)

- **Routes:**
  - `app/explore/page.tsx`, which is server-rendered and parses `?only=`.
  - `explore/Explore.tsx` (776 lines), `explore/filters.ts`, `explore/explore.css`, `EventsBrowser.tsx` (a week strip, `app.css:1281`).
- **Now:**
  - A search card with filter chips: All, Tournaments, Leagues, Pickup, Teams, Communities, and People for members only (`filters.ts:12`, `Explore.tsx:287-293`).
  - Live scores, "coming up" events, and a link to rankings.
- **Change:** swap the tokens. Restyle the chips as pill FilterChips.
- **Components:** reuse Avatar and EmptyState. Add new FilterChip, DateBadge and Card.
- **Preserve:**
  - Visitor discovery (`ForVisitors`) and the People prompt to log in (`Explore.tsx:294-298`).
  - Deep links: `?q=`, `?only=` and `#coming-up`.
  - The `aria-live` results region (`:300`).
- **Accessibility:**
  - `:306` is a `form-error` inside an `aria-live` region, so it is announced but has no retry.
  - No role on `:553, 575, 688, 723` (SUSPECTED).
  - The page has five `aria-busy` paragraphs.
- **Tests:** visitor versus member chips, empty results, each `?only=` deep link.
- **Hours:** 5.
- **Feature – not approved:** map view, radius and date filters, and the "For you" tab.

## 06. Schedule and event detail (P0)

- **Routes:**
  - `app/schedule/page.tsx` (MembersOnly) and `app/teams/[teamId]/schedule/page.tsx` (`?event=` and `?when=past`).
  - `Schedule.tsx` (968 lines), `team/TeamSchedule.tsx` (630), `TeamEventEditor.tsx`, `Repeat.tsx`, `RsvpPill.tsx`, `RsvpNote.tsx`, `AddToCalendar.tsx`, `ScheduleLink.tsx`, `team/DateTile.tsx`, `EventItem.tsx`, `rsvp_note.css`, `team_schedule_meetings.css`.
- **Now:** a single card with List/Month segmented control (`Schedule.tsx:570-573`, saved in `localStorage` with try/catch), plus a filter tab row. The event detail is in the team hub.
- **Change:**
  - At 900+, show the calendar grid with an event detail panel. Today the detail is a separate team route, so this is a layout change only.
  - Restyle the date badge.
- **Components:** reuse DateTile, RsvpPill and EventItem. Add new DateBadge (merging DateTile and `.event-date`), Tabs and StatusPill.
- **Theme:** nine inline `style` attributes for calendar dots (`Schedule.tsx:286-545`), which are data-driven. Lines 489–490 use token variables.
- **Preserve:**
  - Live listeners `useLiveQueries` on `teams/{id}/events` and `meetings` (`Schedule.tsx:98-100`).
  - Personal calendars, invites and ICS.
  - The `?event=` deep link.
  - Recurrence.
- **Accessibility:**
  - The `role="tab"` controls at `Schedule.tsx:403` and `:419` have no arrow-key support.
  - `TeamSchedule.tsx:221-224` puts `role="tab"` on `<Link>`s.
  - No role on `Schedule.tsx:440, 700`.
  - Two `confirm()` calls.
- **Tests:** RSVP error rollback, timezone display, deep link, month and list views.
- **Hours:** 8.
- **Feature – not approved:**
  - A Week view on My schedule. Only List and Month exist on the web.
  - An agenda-plus-detail panel that changes how the event route behaves.

## 07. Teams directory (P0)

- **Routes:**
  - `app/teams/page.tsx`, `app/teams/new/page.tsx` and `app/join/[code]/page.tsx`.
  - `MyTeams.tsx`, `TeamFinder.tsx`, `TeamInvites.tsx`, `CreateTeam.tsx`, `JoinLink.tsx`, `SideTeams.tsx`, `team_invites.css`.
- **Now:** a stack of cards (teams, then communities with nested teams), plus a finder and invites. The sidebar team list is in `SideTeams`.
- **Change:**
  - Show a sidebar list with the selected workspace context.
  - Replace `SideTeams.tsx:15`'s six hashed hex tints, including the old purple `#5348b2`, with tokens.
- **Components:** reuse Avatar and TeamBadge. Add new ListRow, EmptyState (with action) and ErrorNote.
- **Preserve:**
  - The Teams tab always opens the list (`AppFrame.tsx:139`).
  - Community-linked teams stay nested (`MyTeams.tsx:64-67`).
  - The visitor sign-up card (43–55).
- **Accessibility:** `MyTeams.tsx:59` is a `form-error` with no role and no retry. `:60` is an ad-hoc `aria-busy`.
- **Hours:** 3.

## 08. Team overview and feed (P0)

- **Routes:**
  - `app/teams/[teamId]/layout.tsx`: server-rendered for visitors, `TeamProvider`, `SectionGate`.
  - `[teamId]/page.tsx` (TeamFeed), `more/page.tsx`, `settings/page.tsx`.
  - `team/TeamBanner.tsx`, `TeamNav.tsx`, `TeamFeed.tsx`, `TeamPostCard.tsx`, `TeamPostComposer.tsx`, `TeamPostComments.tsx`, `TeamStatTiles.tsx`, `TeamSettings.tsx` (536 lines), `SectionGate.tsx`, `SectionsHint.tsx`, `team_hub.css` (532).
- **Now:**
  - A compact banner with badge, meta and actions, a visitor CTA, and sticky scrolling section tabs with a More menu (`TeamNav.tsx:80-110`).
  - The hub has its own right column. The frame aside is turned off for `/teams/*` (`AppFrame.tsx:183`).
- **Change:** give it workspace nav plus a modular dashboard. The tab underline stays the accent colour.
- **Components:** reuse TeamBadge, Avatar and Dialog, plus `EmptyState`, `ErrorNote` and `Loading` (seven uses in TeamFeed). Add new Tabs (nav variant) and Card.
- **Theme:**
  - `team_hub.css:50-53` handles dark mode itself.
  - Line 889 has `#000` inside a mask, which is acceptable.
- **Preserve:**
  - The tabs `hubSections` builds for member versus outsider and for team, community or organization (`TeamNav.tsx:64-72`).
  - The optional modules playbook, stats, videos and meetings.
  - Live `tournamentEntries` read for members (`:93`).
  - The outsider and denied states (`TeamContext.tsx:134-140`).
- **Accessibility:** `TeamSettings.tsx` has five `confirm()` calls, which should move to Dialog.
- **Hours:** 6. **Feature – not approved:** a pinned-content module and a "next practice" card that would add new data.

## 09. Roster, invitations and roles (P0)

- **Routes:**
  - `app/teams/[teamId]/roster/page.tsx`, a server fetch with no cache tag (W-B8).
  - `team/TeamRosterView.tsx` (490 lines), `TeamRoles.tsx`, `MemberPermissions.tsx`, `InviteDialog.tsx` (418), `InvitePeople.tsx`, `JoinRequests.tsx`.
- **Now:** the roster as a table, then member rows. The invite dialog has tabs and a QR code.
- **Change:** a searchable table with a member detail view at 1200+ and token-styled role chips.
- **Components:** reuse Dialog, Avatar and EmptyState. Add new DataTable, StatusPill and SearchField.
- **Theme:**
  - The QR hex colours at `InviteDialog.tsx:247` and `app.css:1496` should stay literal.
- **Preserve:**
  - Visitors see an adult team's public roster without links. Youth rosters and community member lists ask visitors to log in (`TeamRosterView.tsx:35-41`, memory "Visitor access").
  - The "Club age" rule.
- **Accessibility:**
  - `InviteDialog.tsx:138` tabs have no arrow-key support.
  - No role on `TeamRosterView.tsx:381, 438`.
  - Removal uses `confirm()`. The guide wants an explicit confirmation, so use Dialog.
- **Hours:** 5. **Feature – not approved:** roster search. There is no search input in `TeamRosterView`.

## 10. Community and pickup (P1)

- **Routes:**
  - The same hub with `kind` set to a community, plus `app/teams/[teamId]/teams/page.tsx` and the `tournaments/*` group (hat) routes.
  - `team/CommunitySections.tsx`, `CommunityAdmin.tsx`, `CommunityTeams.tsx`, `group_tournaments/*` (GroupTournamentPage is 691 lines, TournamentEditor is 828), `group_tournaments.css`.
  - Pickup is reached through `/explore?only=pickup`.
- **Now:** team-hub styling, with a turf-coloured round badge for communities (`team_hub.css:47`).
- **Change:** swap the tokens. Add an upcoming-events panel at 1200+.
- **Components:** reuse TeamBadge and ScoreStepper. Add new Tabs.
- **Preserve:**
  - Private groups need approval to join.
  - Community members stay private (memory).
  - Hat draft flows.
- **Accessibility:**
  - `GroupTournamentPage.tsx:234` tabs have no arrow-key support.
  - `TournamentEditor.tsx` has three `confirm()` calls.
- **Hours:** 4.

## 11. Organization console (Inherited)

- **Routes:** the hub with `kind="organization"`, the org tabs at `TeamNav.tsx:71`, and `/teams/[id]/teams`. `CommunityAdmin.tsx:298` handles linking schools and clubs.
- **Now:** the team hub, with a navy round badge (`team_hub.css:48`).
- **Change:** inherit the tokens. `--board` has no guide token (see 00).
- **Preserve:** org links never grant cross-workspace rights.
- **Hours:** 2. **Feature – not approved:** a management table console.

## 12. Chats, channels and DMs (P0)

- **Routes:**
  - `app/messages/page.tsx` (MembersOnly; `?view=inbox|requests|archived`, `?to=`) and `app/teams/[teamId]/chat/page.tsx`.
  - `Messages.tsx` (836 lines), `ChatComposer.tsx`, `ChatAttachment.tsx`, `OlderMessages.tsx`, `PendingMessages.tsx`, `Mentions.tsx`.
  - `team/TeamChat.tsx` (518), `ChatExtras.tsx` (621), `ChatManager.tsx`, `DiscordImport.tsx`, `tournaments/TournamentChats.tsx`.
  - CSS: `chat_extras.css`, `chat_attachments.css`, `app.css:935-977, 1334-1371, 1780-1806`.
- **Now:** `.hub-split`, a 260–360 px list beside the thread (`app.css:935`), collapsing at 860 (1073). Messages is full width with no aside.
- **Change:**
  - Show the workspace and channel sidebar with the message pane.
  - Fix the sticky `top: 64px` offsets so they come from a token.
- **Components:** reuse Avatar, Dialog (three uses in ChatExtras), `EmptyState` and `ErrorNote`. Add new ListRow, CountBadge and StatusPill (pending/failed).
- **Theme:** `app.css:1794` and the shadows.
- **Preserve:**
  - The live listeners: `conversations` paged, `dmReads`, typing, and team `chats`/`chatFolders` (`Messages.tsx:57-58, 345-346, 770`; `TeamChat.tsx:68-76`).
  - The IndexedDB outbox, with W-B2 handled separately.
  - Read receipts, mute and pins.
  - The unread divider and the no-forced-scroll behaviour.
- **Accessibility:**
  - `Messages.tsx:181` puts `role="tab"` on `Link`s.
  - No role on `Messages.tsx:164, 416, 428, 535, 539` and `TeamChat.tsx:116, 340, 344`.
  - Message actions show only on hover (`app.css:1368`, but `hover:none` shows them).
- **Tests:** send, pending, failed and retry, and access revoked.
- **Hours:** 8. **Feature – not approved:** a member panel.

## 13. Notifications (P0)

- **Routes:** `app/notifications/page.tsx` and `notifications/requests/page.tsx`, with `Notifications.tsx` (351 lines) and `FollowRequests.tsx`. The bell and badge are in `AppFrame.tsx:245`.
- **Now:** a full live list with kind filters and an icon per kind (commit 39c8a53).
- **Change:** a grouped list using unread StatusPills.
- **Components:** reuse Avatar. Add new Tabs, ListRow and CountBadge.
- **Preserve:**
  - The live `useLiveQuery` (`Notifications.tsx:83-107`).
  - The routing from notification to page (75).
  - Follow-back.
- **Accessibility:**
  - `Notifications.tsx:140` tabs have no arrow-key support.
  - No role on `:190`.
  - Errors are swallowed (W-B4, separate).
- **Hours:** 3. **Feature – not approved:** a slide-over notification panel (optional in the guide).

## 14. Competition discovery and detail (Inherited)

- **Routes:**
  - `app/tournaments/page.tsx` and `tournaments/[tournamentId]/page.tsx`, both server-rendered for visitors with live data for members.
  - `tournaments/PublicTournament.tsx`, `TournamentLists.tsx`, `TournamentPage.tsx` (1,043 lines), `TournamentNews.tsx`, `TournamentDayCard.tsx`, `VisitorParts.tsx`, and `tournaments.css` (324), `tournament_day.css`, `tournament_news.css`.
- **Now:** list cards with search (`TournamentLists.tsx:217`) and a tabbed detail page.
- **Change:** inherit the tokens. Use DateBadge on the cards.
- **Components:** add new Card, DateBadge, StatusPill and Tabs.
- **Theme:** `tournaments.css` has two literals.
- **Preserve:**
  - Visitors see a read-only `TournamentView` with no Players or News tabs (`TournamentPage.tsx:66-71`).
  - The `?tab=`, `?game=` and `?division=` deep links.
  - Visitor scores refresh on a timer (`PublicTournament.tsx:29`).
- **Accessibility:**
  - No role on `TournamentPage.tsx:240, 497, 596, 702, 745, 950, 1003`.
  - The `:980` search uses a placeholder with no label.
  - The page has five `confirm()` calls.
- **Hours:** 5.

## 15. Competition schedule, standings and bracket (Inherited)

- **Routes:**
  - `tournaments/[id]/bracket`, `draft/[divisionId]`, `live-draft/[divisionId]` and `signups`.
  - `TournamentBracket.tsx`, `TournamentGames.tsx` (693 lines; `ScoreStepper` at 120), `useLiveScores.ts`, `drafts/*` with `drafts.css`.
- **Now:** score forms in the Barlow scoreboard face, and live drafts.
- **Change:** an expanded bracket and score panel at 1200+.
- **Components:** reuse ScoreStepper and TeamMark (`TournamentGames.tsx:89`). Add new ScoreText and StatusPill (Live, plus a text label).
- **Preserve:**
  - `BracketForEveryone` for visitors and `MemberBracket` for members.
  - The live scores.
- **Accessibility:**
  - `PlayerSignups.tsx:73` tabs have no arrow-key support.
  - `PlayerSignups` has three inline styles.
  - Check that status is not shown by colour alone (SUSPECTED).
- **Hours:** 6.

## 16. Host wizard and dashboard (Inherited)

- **Routes:** `tournaments/host`, `tournaments/new` and `[id]/edit`, with `HostEvent.tsx`, `TournamentForm.tsx` (944 lines), `DirectorStep.tsx`, `SignupsSlot.tsx` and `host_event.css`.
- **Now:** one long form with `publicDetailsHint` (`TournamentForm.tsx:249`).
- **Change:** inherit the tokens. Step navigation would be a layout change, flagged below.
- **Preserve:**
  - Only hosts with Manage events can host (`HostEvent.tsx:37`).
  - Paid publishing stays gated.
- **Accessibility:** no role on `HostEvent.tsx:42` and `TournamentForm.tsx:300, 823`.
- **Hours:** 5. **Feature – not approved:** the step wizard and the registration table.

## 17. Checkout, receipt and refund (Gated)

- **Routes:**
  - `tournaments/[id]/enter` and `respond`, `payments/done`, `payments/payouts` and `embed/payouts`.
  - `EnterTeam.tsx` (579 lines), `payments/Payments.tsx` (685), `PaymentPages.tsx`, `EmbeddedPayouts.tsx`, `ConfirmSignIn.tsx`.
- **Now:** fees are shown as a sentence (`Payments.tsx:528-537`). Everything is hidden until the API reports `available`.
- **Change:**
  - An order summary beside the checkout at 900+.
  - Give Stripe's `colorPrimary` the indigo accent for each theme. Today it is `"#12805C"` with no dark variant (`Payments.tsx:187`, UX-9).
- **Components:** add a new PriceBreakdown.
- **Preserve:** the server-side total, the server switch and no duplicate submission.
- **Accessibility:** no role on `Payments.tsx:123, 218, 316, 516, 607, 682`.
- **Hours:** 3. Do this only after the financial approval required by CLAUDE.md §8.

## 18. Statistics and game recorder (Inherited)

- **Routes:**
  - `teams/[id]/stats`, `stats/games/[gameId]`, `stats/season`, `stats/players`, `stats/tournaments/[id]`, and `app/rankings/page.tsx`.
  - `team/stats/*`: GamePage is 954 lines, plus `useTracker`, `LinePicker`, `PullTimer`, `StatSheetTable`, and `stats.css`, which uses Barlow 12 times. Also `Rankings.tsx`.
- **Now:**
  - The game tracker has keyboard shortcuts and an UndoBar (`GamePage.tsx:245, 292-296, 413-415`).
- **Change:** an expanded scoreboard with the roster and log at 1200+. Outdoor-contrast and 48 px controls.
- **Components:** add new ScoreText, StatTile and DataTable.
- **Preserve:**
  - The tracker's keys (`U`, `Ctrl+Z`, `Esc`).
  - Line picking.
  - Rankings are members only (pentest P7 is a separate issue).
- **Accessibility:**
  - `GamePage.tsx:133` and `stats/TournamentPage.tsx:161` tabs have no arrow-key support.
  - No role on `GamePage.tsx:63, 120, 316`.
- **Hours:** 6.

## 19. Playbook library and editor (Inherited)

- **Routes:**
  - `teams/[id]/playbook`, `plays` and `plays/[playId]`, `whiteboards` and `whiteboards/[playId]`.
  - `team/playbook/Playbook.tsx`, `PlayEditor.tsx` (473 lines), `PlayField.tsx`, `PlayPage.tsx`, `Whiteboard.tsx` (506), `whiteboard.css`.
- **Now:** a canvas with a 300 px inspector (`app.css:1032`) and a breakpoint at 900.
- **Change:** inherit the tokens.
- **Theme conflict (updates `uiux.md`):**
  - `app.css:1010-1049` has literal piece colours (`#c9e36b`, `#ff8a7a`, `#ff9a3d`) and a grass colour (`#2f6b3a`).
  - Inside `.team-hub`, `team_hub.css:296-321` overrides the pieces with app-matching tokens. Those overrides are offense `color-mix(--team, --board)` and defense `--board`.
  - The grass, the field lines and the pen colours (`team_hub.css:305-308`, hex) are still literal.
  - The `app.css` piece rules are probably dead (SUSPECTED).
- **Components:** reuse Dialog (three uses in Whiteboard). Add new Tabs.
- **Accessibility:**
  - `Playbook.tsx:39` and `PlayEditor.tsx:346-350` tabs have no arrow-key support.
  - Check the canvas keyboard support (SUSPECTED gap).
- **Hours:** 4.

## 20. Film library and analysis (Inherited)

- **Routes:** `teams/[id]/videos` and `videos/[videoId]`, with `team/videos/*` (TeamVideos, VideoPage, VideoPlayer, VideoDiscussion, VideoEditor, EventVideos) and `videos.css`.
- **Now:** a video grid using `minmax(280px)` (`app.css:1005`). Video links only; the web points file uploads to the app (`TeamVideos.tsx:220`).
- **Change:** inherit the tokens.
- **Preserve:** clicking a note seeks the video (`VideoPage.tsx:18-21`). Manager-only edits.
- **Accessibility:** no role on `TeamVideos.tsx:60, 62`. `VideoPage` has four `form-error` elements.
- **Hours:** 3. **Feature – not approved:** an annotation inspector and web upload.

## 21. Meetings and voice (Inherited)

- **Routes:**
  - `teams/[id]/meetings`, `[meetingId]`, `edit` and `room`.
  - `team/meetings/*`: MeetingRoom (486 lines), CallTiles, DeviceSettings, WatchTogether, VoiceRoom, MeetingChat. `voice/VoiceBar.tsx` and `VoiceProvider.tsx`. CSS: `meetings.css`, `devices.css`, `voice.css`.
- **Now:** the room with side panels (chat, people, watch). The voice bar is sticky.
- **Change:** move the eight literals in `voice.css` onto Success and Warning tokens.
- **Preserve:** the mic and camera are requested only on join (`MeetingRoom.tsx:25-30`). Admins start and end meetings and admit people.
- **Accessibility:**
  - `MeetingRoom.tsx:308` and `MeetingsList.tsx:46-49` tabs have no arrow-key support.
  - The `play()` rejection (W-B6) is separate.
- **Tests:** physical device for mic, camera and autoplay.
- **Hours:** 4.

## 22. Settings, privacy and billing (P0)

- **Routes:**
  - `app/settings/layout.tsx` (MembersOnly with `SettingsNav`), plus `account`, `blocked`, `calendar`, `following`, `help`, `notifications`, `personal`, `privacy`, `profile` and `requests`.
  - `settings/*`: 16 files, including `AppearanceSetting` (light/dark/system), `DownloadData`, `ChangePassword` and `AccountSettings`, which handles deletion.
- **Now:** this already matches the guide's Web line. `.settings` is a 220 px nav beside the form (`app.css:789`), collapsing at 860 (851).
- **Change:**
  - Swap the tokens.
  - Inputs reach 3:1 contrast (UX-7). They are currently 44 px high (`app.css:659`).
  - Align 860 to 900.
- **Components:** add new TextField, Switch and SectionCard.
- **Preserve:** the calendar feed's Reset and Turn off actions, data export, and the deletion confirmation.
- **Accessibility:**
  - `FollowingSettings.tsx:66` tabs have no arrow-key support.
  - `FollowingSettings.tsx:72`'s "Find" input has a placeholder only.
  - No role on `ProfileSettings.tsx:43, 145` and `PrivacySettings.tsx:22, 85`.
  - `CalendarSettings` has four `confirm()` calls.
- **Hours:** 4. **Feature – not approved:** billing settings, which are gated.

## 23. Staff operations and moderation (Inherited)

- **Routes:** `app/staff/page.tsx` (MembersOnly), with `StaffQueue.tsx`, `ReportQueue.tsx`, `payments/StaffPayments.tsx` and `team/TeamReports.tsx` for team admins.
- **Now:** a "Reports" h1 and a "Payments" section shown even to non-staff (W-B7).
- **Change:** inherit the tokens.
- **Accessibility:**
  - The note input at `StaffQueue.tsx:74-76` has a placeholder only.
  - No role on `:61`.
- **Hours:** 2. **Feature – not approved:** the accounts, workspaces and jobs dashboards.

## Unmapped routes

These inherit 00 only, about 3 h in total:
- `app/[slug]/page.tsx`: legal, about and help HTML, which still has draft placeholders (W-B3).
- `learn/page.tsx`
- `get-the-app/page.tsx`
- `g/[id]`, `p/[id]`: OpenInApp
- `not-found.tsx`, `error.tsx`
- `api/revalidate` has no UI.

## Totals

| Item | Hours |
|---|---|
| Screens 01–23 | 104 |
| Unmapped routes | 3 |
| Shell (00) | 18 |
| Tokens and primitives | 24 |
| **Restyle total** | **≈149** |
| Test harness (web.md, separate) | +16 |

The first-wave screens (P0 and P1: 01–10, 12, 13 and 22) come to 64 h.

## Shared primitives needed

| Primitive (Flutter name) | Exists on web today | Screens |
|---|---|---|
| Button | CSS `.btn`/`.btn-primary`/`.btn-small`/`.icon-btn` only (`site.css:191-215`, `app.css:615`) | all |
| Card / SectionCard | CSS `.card` (`app.css:227`) | 02–10, 12–20, 22 |
| Tabs (ARIA, arrow keys) | Only in `Dashboard.tsx:238-256`; 19 other tablists don't support arrow keys | 02, 05, 06, 08–10, 12–15, 18, 19, 21, 22 |
| StatusPill | `RsvpPill.tsx`, CSS `.pill` (`app.css:243`), `.count-badge` | 02, 06, 09, 12–15, 17, 18 |
| DateBadge | `team/DateTile.tsx` (9 files), `.event-date` | 02, 06, 14, 21 |
| Avatar / TeamBadge | `Avatar.tsx` (27 files), `team/TeamBadge.tsx` | 02–05, 07–13 |
| EmptyState / ErrorNote / Loading | `StatusViews.tsx` (8, 8 and 11 files), against 166 ad-hoc `form-error`s | all |
| Dialog (replacing `confirm`) | `Dialog.tsx` (14 files), against about 67 `confirm()` calls | 03, 04, 06, 08–10, 14, 22, 23 |
| ScoreText | CSS `--font-score` only | 15, 18 |
| TextField / SearchField / Switch | CSS `.settings-form`, `.auth-card input`, `.switch-row` | 01, 05, 09, 22, 23 |
| FilterChip | CSS `.segmented` | 05, 06, 13 |
| ListRow / CountBadge | CSS only | 07, 12, 13 |
| DataTable / StatTile | `StatSheetTable.tsx`, CSS `.tiles` | 09, 18 |
| PriceBreakdown | none | 17 |

## CSS structure

**Today**
- Two global sheets load in order (`layout.tsx:11-12`): `site.css` has the tokens, the landing page and the base controls; `app.css` is a 1,859-line monolith covering the shell, member area, chat, play field, Learn and more.
- There are 24 component CSS files beside them, global and imported by their components.

**Proposed** (guide §Engineering; Doc 17 §13)
1. `packages/design-tokens/{colors,typography,spacing,motion}.json` generates:
   - `apps/web/app/tokens.css` (`:root`, `@media (prefers-color-scheme: dark) :root:not([data-theme="light"])`, `[data-theme="dark"]`), written once, which removes the duplicate at `site.css:55-140`;
   - a TypeScript module for the Stripe appearance and `theme-color`;
   - a Dart ThemeExtension.

   Keep the old variable names (`--accent`, `--ink`, …) as aliases for one release, as `site.css:40-46` already does.
2. Add `--space-*`, `--text-*`, `--radius-chip`, `--bp-*` (as comments or custom media) and `--top-bar-h`. That last one replaces the hard-coded 64/56 px offsets.
3. Split `app.css` into:
   - `base.css` (reset and type);
   - `components/ui/*.css` for the primitives;
   - `shell.css` for the AppFrame;
   - feature sheets that sit beside their components, as `team_hub.css` and `tournaments.css` already do.

   Move the playbook and voice colours into tokens.
4. Lint rules:
   - Stylelint `color-no-hex` outside `tokens.css`, which is a new dev dependency and needs approval.
   - One breakpoint set: 600/900/1200/1600.
