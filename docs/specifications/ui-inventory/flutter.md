# Flutter UI inventory against the UI Implementation Guide (39c8a53, app 0.0.55)

This is a read-only review of the code: nothing was run, and no tests were executed. Paths are relative to `apps/mobile/`. "r:N" means `lib/routing/router.dart` line N, and "tr:N" means `lib/routing/tournament_routes.dart` line N. Per-file counts come from grep over the screen's main widget files:

- **C** is `Color(0x…)`.
- **M** is non-transparent Material `Colors.*`.
- **F** is lines containing a literal `fontSize:`.

**Effort heuristic** (an estimate, restyle only, assuming the tokens and primitives below already exist): about 1 h per 300 lines of screen widget code, plus 1 h per 10 literal font sizes, plus 1–2 h for goldens. Shared work in G1–G4 is not counted in the per-screen hours.

## Global findings (referenced as G1–G6)

**G1. Palette.** `AppColors` (`lib/ui/core/themes/theme.dart:336-535`) has about 30 fields. The guide has 12 tokens.

- **Direct mapping:** background→Canvas, card→Surface, field→Raised, border/border2→Border, ink→Text, muted→Muted, accent→Accent, onAccent→On accent, positive→Success, live→Live, highlight→Warning (SUSPECTED intent).
- **No guide token:** ink2, accentSoft/Ink, highlightSoft/Ink, liveSoft/Ink, sidebar/onSidebar*, feature/onFeature*/featureHighlight, chipOn/onChipOn, team, personal, badge.
- **Swap effects:**
  - Today `accent` and `positive` are the same green (`theme.dart:476,494`). Indigo will separate them, so every place that uses `c.accent` to mean "success" must move to `positive`. That needs an audit (SUSPECTED, not counted).
  - The navy `FeatureCard` (`core/ui/layout.dart:321`, `c.feature #0F1A2A`) has no counterpart in the guide's flat-surface model.
- **Decision needed:** what `feature`, the amber `highlight` and the team/personal colours become. Doc 17 §04 keeps team and personal event colours as supplemental to labels.
  - The documents conflict: the guide calls the palette both "proposed" and "approved" (lines 5 and 156), while `uiux.md` says Turf & Disc "already matches" the concept.
  - This is not resolved here.
- **Already in place:** Inter and Barlow Condensed are bundled (`pubspec.yaml:108-129`), radii are 16/12 (`theme.dart:14,17`), light/dark/system mode exists (`settings_screen.dart:30`), and `ScoreText` uses Barlow 800 (`core/ui/scoreboard.dart:11`).

**G2. Breakpoints.** The app uses `ScreenSize` 720/1200 (`layout.dart:20-21`), with a side column at a content width of 860 or more (`layout.dart:36`), a page cap of 1180 (`:42`), a chat split at 840 (`chat/widgets/chat_layout.dart:9`) and a 440 slide-over panel (`slide_over_page.dart:7`). The shell has a bottom NavigationBar (`shell/widgets/app_shell.dart:120`), a 68-px rail (`:546`) and a 232-px sidebar (`:259`). The guide uses 600/900/1200/1600. As a result:

- At 600–719 the app shows tabs where the guide wants a rail.
- At 900–1199 it shows a rail where the guide wants a sidebar.
- There is no 1200+ contextual panel and no 1600 cap.

The tab order already matches the guide: Home, Discover, Schedule, Teams, Chats.

**G3. Type and spacing.** There is no type scale and no spacing tokens: 776 literal font sizes and 912 numeric insets (`uiux.md`). The mobile page gutter is 14 (`layout.dart:46`), against the guide's 16.

**G4. Tests.** There are no goldens, no `meetsGuideline` tests and no text-scale tests. `test/screenshots/*` is opt-in, writes PNGs and makes no assertions; it's marked "(ss)" below. Every screen needs:

- goldens at 360/768/1280 in light and dark,
- `meetsGuideline` for tap targets, labels and text contrast,
- `textScaler` 2.0 with no overflow.

**G5. Global accessibility issues** from `uiux.md`, reused here:

- UX-1: ToneTag contrast (`core/ui/tone.dart:6-13`).
- UX-4: 42 `VisualDensity.compact` uses.
- UX-6: the amber unread dot.
- UX-7: input borders are 1.29:1 (`theme.dart:157-163`).

**G6. Shell top bar.** `MobileTopBar` (`app_shell.dart:768`) uses `c.sidebar`, shows the avatar via `ProfileButton.leading`, and has search and notifications buttons. It matches the guide's "avatar opens profile/settings".

## Screens

### 01 Auth / onboarding (P0)
1. **Routes:**
   - `/sign-in` r:123, `/sign-up` r:133.
   - `/welcome/username` r:125, `/welcome/terms` r:128, `/welcome/details` r:130.
   - The redirect chain is at r:1111-1172. `/join/:code` is at r:137.
   - Files: `ui/auth/widgets/{sign_in,sign_up,choose_username,agree_terms}_screen.dart`, `auth_layout.dart`, `disc_throw_hero.dart`, `password_field.dart`, `username_field.dart`, and the view models in `ui/auth/view_models/`. Also `ui/personal/widgets/personal_details_screen.dart` with its view model.
2. **Current design:** an animated "disc throw" field sits on top, with the form in a sheet below on phones and side by side on wide screens (`auth_layout.dart:18-24`). The Google and Apple buttons are full width and 48 high (`sign_in_screen.dart:76`).
3. **Changes:** form surface on Canvas, an indigo primary button, inline Error-token messages, and re-tinting the hero art (9 Color literals).
4. **Components:** uses PersonAvatar and Eyebrow. Needs AppButton (primary, secondary, social), AppTextField and InlineError. There are 4 raw `CircularProgressIndicator`s.
5. **Light/dark:** `disc_throw_hero` has C9, M4 (paint overlays at `:234-477`) and F3. The other auth files have F of 2 or less.
6. **Responsive:** `auth_layout` decides phone vs wide with a LayoutBuilder. That matches the guide's centred form with an optional brand panel.
7. **Preserve:**
   - the `from` target carried through redirects, and invite links surviving sign-in (r:1170),
   - password reset (`sign_in_screen.dart:91,180`),
   - the Google/Apple visibility flags,
   - the throw skipped under reduced motion,
   - the age gates in personal details.
8. **Accessibility:** no `Semantics` in the auth files. The hero is tap-to-replay, so it needs an excluded or labelled node.
9. **Tests:** `test/ui/sign_in_test`, `auth_layout_test`, `choose_username_test`, `agree_terms_test`, `personal_details_test`, `club_age_test`, `test/routing/auth_redirect_test`, and `acct_test` (ss). New tests per G4.
10. **Effort:** 6 h.
11. **Dependencies:** AppButton, AppTextField, G1. **Feature – not approved:** the "pending verification" state, because there is no email-verified check (`mobile.md`).

### 02 Home / Following (P0)
1. **Route:** `/home` r:695 (`homePage`, `route_builders.dart:238`). Files: `ui/home/widgets/home_screen.dart` (886 lines), `home_cards.dart`, `home/view_models/home_viewmodel.dart`, `posts/view_models/home_feed.dart`, `posts/widgets/inline_composer.dart`, `post_widgets.dart`, and `tournaments/widgets/tournament_day_card.dart`.
2. **Current design:**
   - MobileTopBar plus a SearchField.
   - On narrow screens, the tournament-day card, "needs you" and `_ComingUpCard` (`:776`) sit above the tabs.
   - `_UpNextCard` is a navy FeatureCard (`:683-760`).
   - The tabs are UnderlineTabs: Your teams, Following, Everyone (`:33-38`, `:520`).
   - `SideColumnLayout` is at `:262`.
3. **Changes:**
   - Flatten the navy card (G1).
   - Add a "N going" count and your-RSVP chip to the next-event card. This is a parity gap with the web (`uiux.md` item 2), visual only.
   - The guide's tabs are "Following/Explore". The app has three tabs with Your teams as the default. Keep them; changing that needs approval.
4. **Components:** uses SectionCard, CardLink, FeatureCard, DateBadge, TeamBadge, UnderlineTabs, SkeletonPost. Needs SegmentedTabs, EventCard, StatusPill (RSVP), PostCard, Composer, Avatar, EmptyState.
5. **Light/dark:** C0 M0. F: `home_screen` 13, `home_cards` 6, `inline_composer` 9.
6. **Responsive:** the shell switches at 720. Cards move into the side column at a content width of 860 or more, capped at 1180. The guide wants a right panel at 1200+ and a 1600 cap.
7. **Preserve:**
   - pull-to-refresh, and re-tapping the tab to scroll to the top (`app_shell.dart:22`),
   - the composer draft kept in the view model across tabs (`home_screen.dart:280`),
   - lazy `openCommunity`/`openTeams`, and `hasMorePosts` pagination,
   - the join card, and the realtime post streams.
8. **Accessibility:** `shrinkWrap` button at `home_screen.dart:860-862` (UX-3). `inline_composer` has 7 compact uses (UX-4).
9. **Tests:** `home_test`, `inline_composer_test`, `social_test`, `post_actions_test`, `event_navigation_test`, `home_test` (ss). New: loading, empty and error goldens, plus G4.
10. **Effort:** 8 h.
11. **Dependencies:** G1 feature-card decision, SegmentedTabs, EventCard. **Not restyle:** the feed error state (UX-2, `home_feed.dart:53,67`) needs a view-model change and should be tracked as its own issue.

### 03 Explore / post detail / composer (P1)
1. **Routes:**
   - The guide's "Explore" is Home's Everyone tab (`home_screen.dart:37`, `posts/view_models/community_feed.dart`).
   - Post detail is `/posts/:postId` r:185; `/p/:postId` redirects to it (r:157).
   - The composer has no route. It's a sheet or panel opened by `showPostComposer` (`posts/widgets/post_composer.dart:24`, called at `home_screen.dart:458`). Also `send_post_sheet.dart`.
2. **Current design:** PostCard family in `post_widgets.dart` (1048 lines, 6 private widgets). The detail screen has comments and a report sheet. The composer uses PanelFrame and a SegmentedButton.
3. **Changes:** PostCard and CommentRow on tokens, an audience selector styled as chips, and an upload progress bar. Today that is a `LinearProgressIndicator` at `home_screen.dart:254`.
4. **Components:** uses UserAvatar, PersonAvatar, PanelFrame, Loading/Error/EmptyView. Needs PostCard, CommentRow, Composer, ReactionBar, Avatar, AppButton.
5. **Light/dark:** F: `post_detail` 0, `post_composer` 0, `post_widgets` 4, `inline_composer` 9. No literal colours.
6. **Responsive:** `post_widgets` has 3 width checks. Detail is single column. The guide allows a contextual detail panel on web.
7. **Preserve:** realtime likes, reposts, edits and deletes per page (`community_feed.dart` header); `focusComment`; report and block; drafts in the view model.
8. **Accessibility:** `shrinkWrap` at `post_detail_screen.dart:369-372` (UX-3), and 3 compact uses.
9. **Tests:** `post_actions_test`, `post_comments_test`, `social_test`. `PostDetailScreen` is not referenced by any test, so add a widget test and golden for it.
10. **Effort:** 6 h.
11. **Dependencies:** PostCard, Composer. **Feature – not approved:** ranked Explore (the feed is "newest posts", per `community_feed.dart:1-2`) and bookmark/save (no matches in `ui/posts`).

### 04 Athlete profile (P1)
1. **Routes:**
   - `/profile` r:1057, a shell branch (`myProfilePage`, `route_builders.dart:199`).
   - `/players/:uid` r:719 and `/people/:uid` r:164 (the "over" variant).
   - `/profile/following` r:1062.
   - Files: `ui/profile/widgets/profile_screen.dart` (1642 lines, 14 private widgets), `profile_viewmodel.dart`, `player_profile_viewmodel.dart`, `follow/widgets/follow_button.dart`.
2. **Current design:** a header with avatar and follow button. Tabs Overview, Posts, Stats, Teams (`profile_screen.dart:28`) as UnderlineTabs. Six SectionCards, ScoreText figures, ToneTag, and a staff badge (`:1607-1615`).
3. **Changes:** a profile header per the guide (avatar, position, follow/message); StatTiles in Barlow; heavy type-scale migration (36 font sizes). Keep the existing tab set.
4. **Components:** uses SectionCard, Tag, ToneTag, ScoreText, PersonAvatar, HighlightButton, SegmentedButton. Needs ProfileHeader, Avatar, StatTile, SegmentedTabs, StatusPill, AppButton.
5. **Light/dark:** C0 M0 F36.
6. **Responsive:** `SideColumnLayout` ×2 (side column at 860 or more). This roughly matches the guide's "contextual stats".
7. **Preserve:**
   - report, block and unblock (`:30`),
   - image choose, camera and remove (`:641`),
   - private-profile gating and follow requests,
   - the gear that opens Settings, and roster-spot linking.
8. **Accessibility:** 2 compact uses. The 36-px box at `:1564` is decorative (SUSPECTED).
9. **Tests:** `player_profile_test`, `privacy_test`, `profile_images_test`, `social_test`.
10. **Effort:** 10 h.
11. **Dependencies:** StatTile, ProfileHeader, and a decision on showing self-reported team history (`mobile.md` correction 5).

### 05 Discover / search (P1)
1. **Routes:** `/explore` r:702 (`explorePage`, `route_builders.dart:106`). `/discover` redirects to it (r:706). `/rankings` r:715. `/teams/search` redirects to Explore filtered to teams (r:774-777). Files: `ui/explore/widgets/explore_screen.dart` (816 lines), `explore_cards.dart` (670), `rankings_screen.dart`, `explore_viewmodel.dart`, `player_search_viewmodel.dart`.
2. **Current design:** PageHeader, AppSearchField and ChoiceChip filters (ExploreFilter teams, groups, players, tournaments, leagues, pickup; `routes.dart:328`). Below them: live now, upcoming events, results, a rankings preview, and a FeatureCard call to action.
3. **Changes:** chip group on tokens, EventCard with DateBadge, flattening the CTA card (G1), and a proper EmptyState.
4. **Components:** uses SectionCard, CardLink, FeatureCard, DateBadge, ScoreText, SkeletonList, Tag. Needs SearchField, FilterChips, EventCard, Avatar, EmptyState, SegmentedTabs (rankings).
5. **Light/dark:** F: `explore_cards` 12, `explore_screen` 8, `rankings` 4. No literal colours.
6. **Responsive:** `SideColumnLayout` (860). The guide wants a filters and results layout on web.
7. **Preserve:** signed-out public discovery, the `query` and `only` URL parameters, the `use_api_search` flag behaviour, and rankings filters.
8. **Accessibility:** compact uses in `explore_cards` (×2) and rankings (UX-4).
9. **Tests:** `explore_test`, `discover_public_test`, `player_profile_test`.
10. **Effort:** 6 h.
11. **Dependencies:** FilterChips, EventCard. **Feature – not approved:** radius and distance filters, and a map/list toggle. There is no map in `ui/explore`; `groups/widgets/group_map.dart` is only for groups. A sport filter doesn't apply (ultimate only).

### 06 Schedule / event detail (P0)
1. **Routes:**
   - `/schedule` r:734 (`?view=find` redirects to Explore).
   - `/team-events/:teamId/new` r:342, `/:eventId` r:362, `/edit` r:382.
   - `/my-events/new` r:620, `/:eventId` r:641, `/edit` r:656.
   - `/calendars/:calendarId/events/:eventId/edit` r:593, and `/settings/calendar` r:259.
   - Files: `ui/schedule/widgets/schedule_screen.dart` (954 lines, 11 private widgets), `schedule_widgets.dart`, `event_detail_screen.dart` (773), `rsvp_widgets.dart`, `my_event_detail_screen.dart`, `event_editor_screen.dart`, and the view models `schedule_viewmodel`, `my_schedule`, `event_detail_viewmodel`.
2. **Current design:**
   - A Week strip or a Month grid (`schedule_viewmodel.dart:31`).
   - Filters All, Team, Personal (`:20`).
   - Day marks: team blue, personal magenta, needs-RSVP amber (`:40`).
   - Event detail uses SectionCard ×6, DateBadge and NeedsYouPill.
3. **Changes:**
   - The week list reads as an agenda; making it the default is SUSPECTED to need no logic change.
   - A SegmentedTabs Week/Month toggle, replacing the custom toggle at `:560-570`.
   - EmptyState in place of the plain "Nothing scheduled" text (`:718`).
   - Team and personal colours shown only alongside labels (Doc 17 §04).
4. **Components:** uses DateBadge, NeedsYouPill, SectionCard, LoadingView. Needs SegmentedTabs, FilterChips, EventCard, RsvpControl, StatusPill, and a merged DateBadge (consolidating `EventDateBadge` in `tournaments/widgets/tournament_parts.dart:15`).
5. **Light/dark:** F: `schedule_screen` 14, `schedule_widgets` 9, `event_detail` 11, `rsvp_widgets` 7. There are 4 transparent colours.
6. **Responsive:** `schedule_screen` has no breakpoint logic, so it's single column at every width. The guide wants a calendar grid plus a detail panel at 900+.
7. **Preserve:**
   - field-path RSVPs and RSVP notes,
   - recurrence series, add-to-calendar and calendar sharing, timezones,
   - event polls and reactions, meetings within the schedule,
   - notification deep links.
8. **Accessibility:**
   - The Week/Month toggle is an `InkWell` 34 high (`schedule_screen.dart:564`), below 48.
   - The day cell is 46 high (`:469`).
   - There are 4 `Semantics` uses, which is good.
9. **Tests:** `schedule_month_test`, `schedule_viewmodels_test`, `event_rsvp_note_test`, `event_editor_screen_test`, `event_navigation_test`, `shared_event_test`, `calendars_test`, `add_to_calendar_test`, `schedule_test` (ss).
10. **Effort:** 10 h.
11. **Dependencies:** SegmentedTabs, EventCard, a DateBadge merge, and G2 for the panel. **Feature – not approved:** a "competition" filter, and a separate agenda mode if one is wanted.

### 07 Teams directory (P0)
1. **Route:** `/teams` r:747. `/teams/new` r:757 (`?kind=community|organization`, `routes.dart:20-22`). Files: `ui/teams/widgets/teams_screen.dart` (741 lines, 10 private widgets), `teams/view_models/teams_viewmodel.dart`, `create_team_screen.dart`, `join_team_dialog.dart`, `invite_code_card.dart`.
2. **Current design:**
   - A "Your teams" heading with a count (`:160`).
   - Communities with folding team lists (`_CommunityBlock`, `:482`).
   - A `_RolePill` (`:356`).
   - Tiles for Join with code, Find a team and Start a team (`:641-645`).
   - An `_InviteTile` (`:653`).
3. **Changes:** list rows on Surface, the role pill moved to StatusPill, and the add tiles as AppButtons. There's no workspace switcher; the guide's switcher is in effect the community grouping.
4. **Components:** uses SectionHeader, Loading/Error/EmptyView. Needs ListRow, Avatar/TeamLogo, StatusPill, AppButton, EmptyState.
5. **Light/dark:** C0 M0 F12.
6. **Responsive:** none in the file. On desktop the sidebar also lists clubs (`app_shell.dart:430`).
7. **Preserve:** the empty-membership state (`:128`), pending invites, the club age 16+ join gate, and "Teams always opens the list" (Doc 17 §03).
8. **Accessibility:** the 36-px box at `:614` is decorative (SUSPECTED).
9. **Tests:** `club_age_test`, `event_navigation_test`, `teams_viewmodels_test`, `invites_test`, `teams_test` (ss).
10. **Effort:** 4 h.
11. **Dependencies:** ListRow, StatusPill.

### 08 Team overview / feed (P0)
1. **Route:** `/teams/:teamId` r:781 (`teamPage`, `route_builders.dart:208`). Section paths are r:797 and legacy `?tab=` redirects are at r:784-791. `/over/teams/:teamId` is r:174. Files: `ui/teams/widgets/team_home_screen.dart` (2820 lines, 23 private widgets), `team_section_screen.dart` (TeamSection enum at `:32-41`), `team_post_widgets.dart`, `team_home_viewmodel.dart`, `team_detail_viewmodel.dart`.
2. **Current design:**
   - A collapsing `_TeamHeaderDelegate` on `c.card` (`:1696`), with `_Hero` (`:1424`) and pinned `_TeamTabs` (`:1840`).
   - `_StatTiles` (`:2058`), `_UpNextCard` (`:2259`), `_MembersCard`.
   - A roster SegmentedButton (`:594`).
   - A public page for non-members.
3. **Changes:** a compact header per the guide, StatTile in Barlow, and type-scale migration (34 font sizes). The guide's Overview/Feed/Schedule plus Roster/Chat/More layout maps onto the existing `_MoreList` (`:1922`). Keep the existing section set.
4. **Components:** uses SectionCard ×12, Tag ×6, StatBlock, CardLink, FeatureCard, DateBadge, UnderlineTabs. Needs SegmentedTabs (scrollable), StatTile, EventCard, StatusPill, TeamLogo, ConfirmDialog (it has 4 raw AlertDialogs).
5. **Light/dark:** C0 M0 F34.
6. **Responsive:** `SideColumnLayout` ×2 plus the collapsing header on phones.
7. **Preserve:**
   - only enabled modules shown (`TeamSection.values` filtering at `team_section_screen.dart:62`),
   - role-gated actions,
   - join and request cards, and the youth roster note (`:2560`),
   - the delete-team flow (`:2745`),
   - realtime team posts,
   - "one page, back leaves the team" (`:72-75`).
8. **Accessibility:** the 34-high item at `:1966` (SUSPECTED a tap target). The header's fixed extents (`:1728-1731`) need a text-scale test.
9. **Tests:** `team_home_test`, `team_page_slice_test`, `team_sections_test`, `team_feed_extras_test`, `team_public_page_test`, `team_share_test`, `community_page_test`, `groups_test`, `teamhead_test` (ss).
10. **Effort:** 14 h.
11. **Dependencies:** SegmentedTabs, StatTile, and the G1 feature/badge decision. **Feature – not approved:** attendance % (`uiux.md` item 4).

### 09 Roster / invitations / roles (P0)
1. **Routes:** the roster and members sections are under r:797. `/teams/:teamId/roles` r:822. Invites open as a dialog (`teams/widgets/invite_members_dialog.dart`). Files: `roster_tab.dart`, `members_tab.dart` (642 lines), `roles_screen.dart`, `member_permissions_dialog.dart`, `player_dialog.dart`, and the view models `roles_viewmodel` and `invite_members_viewmodel`.
2. **Current design:** ListTile rows with a navy initials box (`roster_tab.dart:174`, `c.feature`), Tags, a SegmentedButton and FilterChips. The invite dialog has search, chips and a QR code.
3. **Changes:** MemberRow with Avatar and a role StatusPill, ConfirmDialog for removal, and initials on a token instead of `c.feature`.
4. **Components:** uses PersonAvatar, Tag, SkeletonList, AppSearchField. Needs MemberRow, StatusPill, ConfirmDialog, SearchField.
5. **Light/dark:** `invite_members_dialog` M2 (`:446,456`, white QR background, legitimate). F: roster 2, members 3, roles 5, invite 9.
6. **Responsive:** none. The guide wants a searchable roster table on web only.
7. **Preserve:** pending invites and join requests, the permission matrix, confirmation before removal, and the client-side `_moveLegacyStatus`. Don't touch the latter (M-B5).
8. **Accessibility:** `shrinkWrap` at `roster_tab.dart:279-280` (UX-3).
9. **Tests:** `roles_viewmodel_test`, `member_permissions_test`, `invites_test`, `team_join_requests_test`, `team_page_slice_test`. `RolesScreen` has no widget test.
10. **Effort:** 6 h.
11. **Dependencies:** MemberRow, StatusPill, ConfirmDialog.

### 10 Community / pickup (P1)
1. **Routes:** the same `TeamHomeScreen` at `/teams/:teamId` r:781, used for `TeamKind.community` and `TeamKind.organization` (`domain/models/team.dart:104-107`). `/g/:groupId` redirects (r:152). Group tournaments are at `/group-tournaments/:groupId/...` r:447. Files: `teams/widgets/community_sections.dart`, `community_teams_tab.dart` (657 lines), `team_community_sheet.dart`, `posts/view_models/community_feed.dart`.
2. **Current design:** community sections built from SectionCard ×4, DateBadge, NeedsYouPill, and team lists with TeamBadge and Tags.
3. **Changes:** inherits the screen 08 header and cards. Membership chips go to StatusPill.
4. **Components:** same as 08, plus EventCard.
5. **Light/dark:** F: `community_sections` 9, `community_teams_tab` 4.
6. **Responsive:** inherits from 08.
7. **Preserve:** membership and visibility kept separate from teams; groups' members stay private to visitors (memory note on visitor access).
8. **Accessibility:** `shrinkWrap` in `community_teams_tab`.
9. **Tests:** `communities_test`, `community_page_test`, `groups_test`, `group_messages_test`.
10. **Effort:** 4 h (after 08).
11. **Dependencies:** screen 08.

### 11 Organization console (Inherited)
1. **Route:** none dedicated. Organizations are `TeamKind.organization` on `/teams/:teamId`, with `community_teams_tab.dart` listing their teams.
2–6. Inherits from 08 and 10.
7. **Preserve:** no automatic cross-workspace permissions; roles are per team.
9. **Tests:** `communities_test`.
10. **Effort:** 0 h beyond 08/10.
11. **Feature – not approved:** an organization switcher and management console.

### 12 Chats / channels / DMs (P0)
1. **Routes:**
   - `/messages` r:984, `/messages/new` r:997, `/messages/new-group` r:1009, `/messages/:conversationId` r:1025.
   - Team chat: the section under r:797, `/teams/:teamId/chats/:roomId` r:843 (`/settings` r:871), and `chats/new` r:838.
   - Files: `ui/messages/widgets/inbox_screen.dart` (1148 lines), `direct_chat_screen.dart`, `group_members_screen.dart`, `ui/chat/widgets/chat_tab.dart` (1181), `message_thread_view.dart` (2585, 43 private widgets), `chat_room_screen.dart`, `chat_layout.dart`, `pinned_messages_screen.dart`, `chat_extras.dart`, `chat_polls.dart`, `reaction_bubble.dart`.
2. **Current design:**
   - The inbox is a list with a conversation on the right when the window is wide.
   - The room has a channel drawer behind a "Chats" button on phones (`chat_room_screen.dart:28-31`).
   - Pinned messages, polls, event cards and reactions.
3. **Changes:** bubble and row tokens, an unread StatusPill (UX-6), and type-scale migration (`message_thread_view` F23).
4. **Components:** uses UserAvatar, PersonAvatar, CountPill, SectionHeader, AppSearchField. Needs ListRow, Avatar, StatusPill/CountBadge, Composer, SearchField, EmptyState.
5. **Light/dark:**
   - `message_thread_view` M4 (`:2006-2083`, an image-viewer scrim, legitimate).
   - `chat_tab` M2 (`:492,955`, `black26` shadows).
   - `reaction_bubble` M2 (barrier and shadow).
6. **Responsive:** split at 840 (`chat_layout.dart:9`), list 340 wide. The guide adds a member panel at 1200+.
7. **Preserve:**
   - outbox idempotent sends with pending/failed/retry,
   - mute (`chat_tab.dart:204-224`),
   - access-revoked handling, no forced scroll,
   - mentions, voice channels, report (`message_thread_view.dart:295`),
   - drafts, and realtime streams.
8. **Accessibility:** fixed 52-high rows (`chat_tab.dart:929-930,949`, UX-5); unread dot contrast (`chat_tab.dart:906`, `inbox_screen.dart:945`, UX-6).
9. **Tests:** `chat_test`, `chat_extras_test`, `chat_polls_test`, `messages_test`, `message_features_test`, `group_messages_test`, `outbox_ui_test`, `chat_test` (ss).
10. **Effort:** 14 h.
11. **Dependencies:** ListRow, StatusPill, Composer, G2. **Feature – not approved (SUSPECTED absent):** an unread divider. There are no "unread" matches in `message_thread_view.dart`.

### 13 Notifications (P0)
1. **Routes:** `/notifications` r:296, `/notifications/follow-requests` r:308, `/notifications/settings` r:313. Files: `ui/notifications/widgets/notifications_screen.dart` (517 lines), `notification_settings_screen.dart`, `follow_requests_screen.dart`, `in_app_notice_bubble.dart`, and their view models.
2. **Current design:** grouped "Today" and "Earlier" (`notifications_screen.dart:224,228`), a 36-px icon per kind (`:338`), read items shown in lighter type, and a Follow requests entry with a CountPill.
3. **Changes:** a ListRow with an unread StatusPill, Muted text for read items, and EmptyState.
4. **Components:** uses CountPill and the status views. Needs ListRow, StatusPill, IconBadge, EmptyState.
5. **Light/dark:** F6 in the screen, F7 in settings.
6. **Responsive:** none. The guide allows a panel on web only.
7. **Preserve:** tap marks read and opens the target like a push; handling of deleted targets; notification preferences; lock-screen privacy (server side).
8. **Accessibility:** `shrinkWrap` at `:503-504` (UX-3); unread dot at `:272` (UX-6); there is 1 `Semantics`.
9. **Tests:** `notifications_test`, `in_app_notices_test`, `acct_test` (ss).
10. **Effort:** 4 h.
11. **Dependencies:** ListRow, StatusPill.

### 14 Competition discovery / detail (Inherited)
1. **Routes:** `/tournaments` tr:30 (FindTournamentsScreen), `/tournaments/:tournamentId` tr:73, and `/respond` tr:112. Files: `ui/tournaments/widgets/hosted_tournaments_list.dart`, `hosted_tournament_screen.dart` (3010 lines, 19 private widgets, F54), `event_page_header.dart`, `tournament_parts.dart`, `spots_left.dart`, `respond_screen.dart`, `signup_next_steps.dart`, `event_guide_cards.dart`.
2. **Current design:** ChoiceChip status filters and cards with EventDateBadge, place, divisions and fee (`explore_cards.dart:63-64`). Detail has a scrollable TabBar (`hosted_tournament_screen.dart:321`), HostedStatusBadge and ToneTag.
3. **Changes:** inherit the tokens, merge the badges into StatusPill and DateBadge, and type-scale migration. This is the largest font cleanup in the app.
4. **Components:** uses SectionCard, ScoreText, LivePill, HighlightButton. Needs EventCard, StatusPill, DateBadge, SegmentedTabs.
5. **Light/dark:** `hosted_tournament_screen` F54 T2; `respond_screen` F11; `tournament_parts` F14.
6. **Responsive:** none in the screen.
7. **Preserve:**
   - "registration closed" and spots left,
   - "your waiting team" and the respond steps,
   - public visitor access,
   - captains' channel gating.
8. **Accessibility:** `shrinkWrap` and 2 compact uses in the screen; ToneTag contrast (UX-1).
9. **Tests:** `hosted_tournaments_test`, `respond_test`, `player_entry_test`, `tournament_extras_test`, `event_guide_test`, `discover_public_test`, `tournaments_test` (ss).
10. **Effort:** 14 h, shared with 15.
11. **Dependencies:** StatusPill, EventCard.

### 15 Competition schedule / standings / bracket (Inherited)
1. **Routes:**
   - The tabs of `/tournaments/:id` tr:73.
   - `/bracket/:divisionId` tr:166, `/draft/:divisionId` tr:132, `/live-draft/:divisionId` tr:148.
   - Group tournaments: `/group-tournaments/:groupId/:tournamentId` r:459.
   - Files: `hosted_bracket_screen.dart`, `live_score_sheet.dart`, `tournament_day_card.dart`, `team_draft_screen.dart`, `live_draft_screen.dart`, `group_tournaments/widgets/group_tournament_screen.dart`, `hat_parts.dart`.
2. **Current design:** ScoreLine and LivePill from `core/ui/scoreboard.dart`, Barlow scores, and DateBadge ×3 in group tournaments.
3. **Changes:** token swap only. Live uses the Live token plus a label, never colour alone.
4. **Components:** uses ScoreText, ScoreLine, LivePill, SectionHeader. Needs ScoreCard, StatusPill, SegmentedTabs.
5. **Light/dark:** F: `live_draft` 16, `team_draft` 13, `group_tournament_screen` 19, `hat_parts` 10.
6. **Responsive:** `live_draft_screen` has 2 width checks; the others have none.
7. **Preserve:** realtime live scores, server-callable drafts, and the last-update display.
8. **Accessibility:** the `hat_parts.dart:116` TabBar is fixed at 42 (UX-5).
9. **Tests:** `live_scores_test`, `live_draft_test`, `tournament_day_test`, `group_tournaments_test`, `hatstats_test` (ss).
10. **Effort:** 8 h.
11. **Dependencies:** ScoreCard.

### 16 Host wizard / dashboard (Inherited)
1. **Routes:** `/tournaments/host` tr:42, `/tournaments/new` tr:53, `/tournaments/:id/edit` tr:187, and the group editor at r:455/479. Files: `host_event_screen.dart`, `hosted_tournament_form_screen.dart` (1126 lines), `director_section.dart`, `event_format_section.dart`, `player_signups_tab.dart` (F17), and `group_tournaments/widgets/tournament_editor_screen.dart` (F14).
2. **Current design:** a "pick what and who hosts" page, then a long single form with 4 SegmentedButtons. It isn't step-based.
3. **Changes:** token swap and form controls. A step wizard is a layout change and needs approval.
4. **Components:** needs AppTextField, SegmentedTabs, SectionCard, AppButton.
5. **Light/dark:** F: 10, 11, 17 and 14 across those files.
6. **Responsive:** `host_event_screen` has 1 check.
7. **Preserve:** save and resume, publishing via the API, and restricted paid publishing.
8. **Accessibility:** 40- and 38-high items at `host_event_screen.dart:130,276` (SUSPECTED decorative).
9. **Tests:** `host_event_test`, `run_event_test`, `tournament_extras_test`.
10. **Effort:** 8 h.
11. **Feature – not approved:** a step-by-step wizard with verification.

### 17 Checkout / receipt / refund (Gated, excluded from the January total)
1. **Routes:** none. `PayOnlineButton` (`payments/widgets/payment_widgets.dart:389`) is embedded in respond and tournament screens. `PayoutsSetupScreen` is pushed with `.open` (`payment_widgets.dart:332,363`; WebView at `payouts_setup_screen.dart:97-121`). Other pieces: `PayoutsCard` `:175`, `PayoutsStatusChip` `:670`.
2. **Current design:** a Stripe PaymentSheet, and fees described in a sentence.
3. **Changes:** an itemized PriceBreakdown table. That is visual, but it's on a gated surface.
5. **Light/dark:** F1.
7. **Preserve:** the server-computed total; Pay shown only when the server says `online` (`payments_viewmodels.dart:135`).
9. **Tests:** `payments_test`. `PayoutsSetupScreen` is untested.
10. **Effort:** (4 h, gated).
11. **Dependencies:** approval for financial changes. **Feature – not approved:** receipt and refund screens.

### 18 Statistics / game recorder (Inherited)
1. **Routes:** `/teams/:teamId/stats/season` r:919, `stats/tournaments/:tournamentId` r:937 (team stats, not competition), `stats/games/:gameId` r:956. Files: `ui/stats/widgets/game_screen.dart` (1990 lines, 22 private widgets), `stats_tab.dart`, `tournament_screen.dart`, `line_picker.dart`, `stat_sheet.dart`, `pull_timer.dart`, and `game_tracker_viewmodel.dart`.
2. **Current design:** `_Scoreboard` (`:399`), a player grid, big offence and defence action buttons (`_bigOutline` height 52, `:1324`), an UndoBar (`:362`) and a point log.
3. **Changes:** outdoor high-contrast tokens and a Barlow scoreboard, which is already partly done.
4. **Components:** uses ScoreText, TabBar, SegmentedButton, ChoiceChip. Needs ScoreBoard, AppButton (large), StatTile, SegmentedTabs.
5. **Light/dark:** F: `game_screen` 10, `stats_tab` 11.
6. **Responsive:** none. The guide wants an expanded scoreboard and log on web.
7. **Preserve:** the offline queue and debounced save, undo, line picking, and the timers. Don't alter the M-B4 sync behaviour in a restyle.
8. **Accessibility:** "Undo last" is compact and `shrinkWrap` (`game_screen.dart:386-388`, UX-3, the worst case); 5 `shrinkWrap` uses in the file.
9. **Tests:** `stats_screens_test`, `stats_navigation_test`, `game_tracker_viewmodel_test`, `hatstats_test` (ss).
10. **Effort:** 8 h.
11. **Dependencies:** an outdoor contrast check.

### 19 Playbook library / editor (Inherited)
1. **Routes:** the playbook section (r:797), `plays/:playId` r:881, `whiteboards/:playId` r:900. Files: `ui/playbook/widgets/playbook_tab.dart`, `play_editor_screen.dart` (930 lines), `whiteboard_screen.dart`, `field_painter.dart`, `play_canvas.dart`, `playbook_parts.dart`.
2. **Current design:** play cards, and a field canvas using `FieldColors` (the offence and defence palette in `theme.dart`).
3. **Changes:** chrome tokens only. The canvas colours must stay aligned with the web (`uiux.md` item 6).
4. **Components:** needs PlayCard, AppButton/IconButton, SegmentedTabs.
5. **Light/dark:** `field_painter` M5 (painter, legitimate); `play_editor` M1 F11; `whiteboard` M1 F5.
6. **Responsive:** `play_canvas` has 2 checks. The guide wants a canvas with an inspector at 900+.
7. **Preserve:** step controls, touch gestures, an explicit return from full screen, and permission gating.
8. **Accessibility:** 36- and 40-high controls at `play_editor_screen.dart:429,551,653` (SUSPECTED tap targets); there are 11 tooltips.
9. **Tests:** `play_canvas_touch_test`, `play_editor_viewmodel_test`, `whiteboard_test`, `whiteboard_viewmodel_test`, `play_test` (ss).
10. **Effort:** 5 h.
11. **Dependencies:** a decision on web/app colour parity.

### 20 Film library / analysis (Inherited)
1. **Routes:** the videos section, `/team-videos/:teamId/new` r:412, `/:videoId` r:414, `/edit` r:432. Files: `ui/videos/widgets/videos_tab.dart` (706 lines), `video_screen.dart`, `video_editor_screen.dart`, `video_discussion.dart`, `youtube_player_view.dart`, `file_video_player.dart`.
2. **Current design:** a library list with thumbnails and a black player with a discussion below.
3. **Changes:** chrome tokens; player scrims stay black.
4. **Components:** needs VideoCard, ListRow, EmptyState.
5. **Light/dark:** M: `videos_tab` 2 (`:657,660`, play-button scrim), `video_screen` 2, `youtube` 1, `file_player` 1. All legitimate.
6. **Responsive:** `video_discussion` has 1 check.
7. **Preserve:** upload progress, the external-video warning, private feedback, and watch-together.
9. **Tests:** `videos_test`, `video_extras_test`, `watch_together_test`.
10. **Effort:** 4 h.
11. **Dependencies:** none beyond G1.

### 21 Meetings / voice (Inherited)
1. **Routes:** `/team-meetings/:teamId` r:492, `/new` r:509, `/:meetingId` r:528, `/room` r:564. Files: `ui/meetings/widgets/meetings_list_screen.dart`, `meeting_detail_screen.dart`, `meeting_room_screen.dart` (a lobby, then the call), `meeting_call_view.dart` (11 width checks), `meeting_room_widgets.dart`, `watch_together_view.dart`, and `chat/widgets/voice_channel_view.dart`.
2. **Current design:** a list with DateBadge and NeedsYouPill, a lobby with device pickers, and a call grid.
3. **Changes:** tokens, and merging `CountBadge` (`meeting_room_widgets.dart:183`) and `MeetingStatusBadge` into StatusPill.
4. **Components:** needs StatusPill, AppButton, Avatar.
5. **Light/dark:** `watch_together` M2, `meeting_alerts` M1 (video overlays).
6. **Responsive:** `meeting_call_view` is already adaptive.
7. **Preserve:** the LiveKit lifecycle, permission prompts, and reconnect handling. This screen needs device validation (M-B7).
8. **Accessibility:** there are 11 tooltips in the call view.
9. **Tests:** `meetings_list_test`, `meetings_screens_test`, `meetings_viewmodels_test`, `device_access_test`. `VoiceChannelView` is untested.
10. **Effort:** 5 h.
11. **Dependencies:** StatusPill.

### 22 Settings / privacy / billing (P0)
1. **Routes:**
   - `/settings` r:209 (a slide-over that becomes a panel on wide screens).
   - `/settings/{general,privacy,account}` r:223.
   - `/settings/help` r:239, `/settings/personal` r:249, `/settings/calendar` r:259, `/settings/following` r:276.
   - Files: `ui/settings/widgets/settings_screen.dart` (817 lines), `settings_widgets.dart`, `change_password_dialog.dart`, `device_access_group.dart`, `download_data_group.dart`, `profile/widgets/delete_account_dialog.dart`, and `moderation/widgets/blocked_accounts_screen.dart` (pushed at `:12-14`, no route).
2. **Current design:** grouped rows with a 32-px icon box (`settings_widgets.dart:190`), and sections for General, Notifications, Privacy, People and Account.
3. **Changes:** a SettingsGroup and SettingsRow on tokens, plus a destructive AppButton for deletion.
4. **Components:** uses PersonAvatar. Needs SettingsGroup/Row, AppButton (destructive), ConfirmDialog. It has 2 raw AlertDialogs.
5. **Light/dark:** F: `settings_screen` 8, `settings_widgets` 9.
6. **Responsive:** a 440 slide-over panel (`slide_over_page.dart:7`). That's close to the guide's "sidebar + form" on web.
7. **Preserve:** the theme choice, deletion with re-authentication, data export (90 s), device access, blocked accounts, and sign-out (M-B1/M-B2 are logic bugs, not restyle).
8. **Accessibility:** the 40-high item at `settings_screen.dart:305` (SUSPECTED).
9. **Tests:** `account_test`, `privacy_test`, `download_data_test`, `device_access_test`, `report_block_test`, `acct_test` (ss). `BlockedAccountsScreen` is untested.
10. **Effort:** 5 h.
11. **Dependencies:** SettingsRow, ConfirmDialog. **Feature – not approved:** billing (none exists; memberships are deferred).

### 23 Staff operations / moderation (Inherited)
1. **Routes:** none. `TeamReportsScreen` is pushed by `showTeamReports` (`moderation/widgets/team_reports_screen.dart:15-21`) from team settings. Others: `report_sheet.dart:38`, and the staff badge at `profile_screen.dart:1607`.
2. **Current design:** a reports list and a report sheet.
3. **Changes:** tokens only.
5. **Light/dark:** F2 and F3.
9. **Tests:** `report_block_test`.
10. **Effort:** 2 h.
11. **Feature – not approved:** a staff console. The guide marks this web-first.

## Shared primitives needed across screens

Frequencies come from the files sampled above.

| Primitive (target) | Screens | Build from (existing) |
|---|---|---|
| Tokens: AppSpacing, AppText scale | all 23 | `theme.dart` (`textTheme`), `layout.dart:45` `pagePadding` |
| StatusPill | 02 06 07 08 09 10 12 13 14 15 21 (11) | `Tag` (`layout.dart:384`), `ToneTag` (`tone.dart:23`), `CountPill` (`layout.dart:645`), `LivePill`/`NeedsYouPill` (`scoreboard.dart:50,84`), HostedStatusBadge, MeetingStatusBadge, CountBadge, RsvpStatusPill, PayoutsStatusChip |
| Avatar / TeamLogo | 01 02 03 04 07 08 09 12 21 22 (10) | `PersonAvatar` (`layout.dart:546`), `UserAvatar` (`user_avatar.dart:18`), `TeamBadge` (`layout.dart:583`), `team_initials.dart` |
| EmptyState (with action) | 02 03 05 06 07 12 13 20 (8) and others | `EmptyView` (`status_views.dart:45`) |
| SegmentedTabs | 02 04 05 06 08 14 15 16 18 19 (10) | `UnderlineTabs` (`layout.dart:695`), Material `SegmentedButton`/`TabBar`, the custom toggle at `schedule_screen.dart:560` |
| AppButton (primary, secondary, destructive, large, social) | 01 02 03 04 07 16 18 19 21 22 (10) | Material button themes in `theme.dart`, `HighlightButton` (`layout.dart:349`) |
| EventCard and DateBadge | 02 05 06 10 14 21 (6) | `DateBadge` (`layout.dart:486`), `EventDateBadge` (`tournament_parts.dart:15`), `_ComingUpCard`/`_UpNextCard` ×2 |
| ListRow / MemberRow | 07 09 12 13 20 22 (6) | ListTile theme, `_Row` (`teams_screen.dart:386`) |
| SectionCard (flat) | 02 04 05 06 08 10 16 (7) | `SectionCard` (`layout.dart:236`), `FeatureCard` (`:321`, which needs the G1 decision) |
| StatTile / ScoreText / ScoreCard | 04 08 14 15 18 (5) | `StatBlock` (`layout.dart:455`), `ScoreText`/`ScoreLine` (`scoreboard.dart:11,195`), `_StatTiles` (`team_home_screen.dart:2058`) |
| PostCard / Composer | 02 03 12 (3) | `post_widgets.dart`, `inline_composer.dart`, `team_post_widgets.dart` |
| SearchField / FilterChips | 05 06 09 12 14 (5) | `AppSearchField` (`app_search_field.dart:8`), `ToneFilterBar` (`tone.dart:71`) |
| ConfirmDialog | 08 09 22 and others | `confirm_dialog.dart` (49 raw AlertDialogs elsewhere) |
| AppTextField / InlineError | 01 16 22 | input theme (`theme.dart:157-166`; border contrast per UX-7), `error_message.dart` |
| Skeletons | 02 04 05 09 | `skeleton.dart` (already shared) |

**January estimate (restyle only):**

- **P0** (01, 02, 06, 07, 08, 09, 12, 13, 22): about 71 h.
- **P1** (03, 04, 05, 10): about 26 h.
- **Inherited** (11, 14, 15, 16, 18–21, 23): about 54 h.
- **Gated** (17, not counted): 4 h.

Shared work comes on top of these: G1–G3 tokens plus the primitives table (SUSPECTED 30–40 h), and the G4 test harness (about 8 h, per `uiux.md`).

**Verified vs assumed.** These are verified by grep and reading at 39c8a53: routes and line numbers, file sizes, per-file counts, core widget usage, test-file references (by class name), breakpoints and tokens. These are assumed: hours, the tap-target status of the items marked SUSPECTED, "agenda equals week list", the absence of an unread divider (grep only), and every visual judgment. Nothing was rendered or run, and no tests were executed.
