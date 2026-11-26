# UI/UX audit: Stall10 at 39c8a53 (app 0.0.55, web 0.59.5)

Read-only code and spec review. No apps launched, so nothing here was checked on a device. Counts come from grep over `apps/mobile/lib/ui` (276 Dart files) and `apps/web/{app,components}` (268 TSX files plus CSS). Contrast ratios were computed with the WCAG 2.x formula from the token hex values.

## Token adoption

**Correction to C-35 and readiness row 18.** The "about 619 hardcoded colours" figure is wrong. The regex `Colors\.` also matched `AppColors.of` (492 hits), so most of the count is token usage. The real counts are:

| Flutter (`lib/ui`) | Count | Notes |
|---|---|---|
| `Color(0x…)` outside `theme.dart` | **28** | `tone.dart` 7 (the light/dark Tone palette), `auth/widgets/disc_throw_hero.dart` 9, `workouts/widgets/route_widgets.dart` 3 |
| Material `Colors.*` | **80** | 40 are `transparent`. The rest: `white` 22, `black` 8, and `black26/38/54/87`, `white70` |
| `AppColors.of(context)` | 493 | Tokens are widely adopted |
| Literal `fontSize:` | **776** in 115 files, **23 distinct sizes** | 12 (162), 12.5 (135), 13 (129), 13.5 (47), 11.5, 14.5 … Compare 169 `textTheme.` uses. There is no type scale |
| `EdgeInsets` with numeric literals | **912** | No spacing tokens exist at all |
| Numeric `BorderRadius.circular` | **146** | 12, 10, 999, 8, 16, 6 … Compare 91 uses of `cardRadius`/`controlRadius` |

Top files by hardcoded colour (`Color(0x)` plus Material colours, excluding transparent): `core/ui/tone.dart` 14, `auth/widgets/disc_throw_hero.dart` 14, `workouts/widgets/route_widgets.dart` 5, `playbook/widgets/field_painter.dart` 5, `chat/widgets/message_thread_view.dart` 4. Nine files have 2 each: `record_workout_screen`, `videos_tab`, `video_screen`, `invite_members_dialog`, `watch_together_view`, `slide_over_page`, `reaction_bubble`, `chat_tab`. `youtube_player_view` and `file_video_player` have 1 each. Most of these are media scrims or brand art, which is legitimate.

Top files by literal font size: `tournaments/widgets/hosted_tournament_screen.dart` 54, `teams/widgets/team_home_screen.dart` 33, `profile/widgets/profile_screen.dart` 33, `chat/widgets/message_thread_view.dart` 23, `group_tournaments/widgets/group_tournament_screen.dart` 19.

**Web.** `site.css:6-140` defines full light, dark and system token sets.

- **Hex literals in TSX:** 13, with no `rgb()`.
  - `app/layout.tsx:36-37` sets theme-color. This one is legitimate.
  - `components/payments/Payments.tsx:187` sets Stripe `colorPrimary: "#12805C"` with no dark variant. That colour reaches only 3.33:1 on the dark card.
  - `components/SideTeams.tsx:15` uses six hashed tints, including the old purple `#5348b2`.
  - `components/team/InviteDialog.tsx:247` sets QR colours. This one is legitimate.
- **Inline `style={{}}`:** 29 uses. The largest is `components/Schedule.tsx` with 9, all calendar dots. The data-driven ones are acceptable.
- **CSS colour literals outside the token blocks:** `app/app.css` 24 hex and 16 rgb, `components/voice/voice.css` 8, `components/team/team_hub.css` 4.
  - The playbook colours (`app.css:1011-1049`: offense `#c9e36b`, defense `#ff8a7a`) **differ from the app** (`theme.dart` FieldColors: offense `#2F78C8`, defense `#14213A`). The same play looks different on each platform.
- **CSS typography and radii:** 462 `font-size` declarations with **86 distinct values** (rem and px mixed). There are 198 literal `border-radius` values and 91 that use `var(--radius…)`.

## Component gaps

**The existing library** in `lib/ui/core/ui/` is reasonably complete:

- Layout and cards: `layout.dart` has PageHeader, SectionCard, CardLink, FeatureCard, Tag, StatBlock, DateBadge, PersonAvatar, TeamBadge, CountPill, UnderlineTabs, HighlightButton and Eyebrow.
- State views: `status_views.dart` has LoadingView, ErrorView, EmptyView and ConstrainedContent. `skeleton.dart` has the skeletons.
- Scoreboard: `scoreboard.dart` has LivePill, NeedsYouPill, SectionHeader and ScoreLine.
- Other: `tone.dart` (ToneTag), `confirm_dialog`, `error_message` (snack bars) and `overlay_panel`.

On the web, `components/StatusViews.tsx` has Loading, EmptyState, ErrorNote and LiveList, and there are `Dialog.tsx`, `Avatar`, `RsvpPill` and `OfflineBanner`. The shared views are used 56/54/63 times (Loading/Error/Empty) on the app, but 42 raw `CircularProgressIndicator` remain.

**Gaps:**

1. **No spacing or type-scale tokens** on the app. There is no `Space`/`Gap` class and no named text styles beyond `textTheme`. This is the root cause of the 776 font sizes and 912 insets.
2. **Pill and badge sprawl.** There are 10 public variants: CountPill (`layout.dart:645`) vs CountBadge (`meetings/widgets/meeting_room_widgets.dart:183`), DateBadge (`layout.dart:486`) vs EventDateBadge (`tournaments/widgets/tournament_parts.dart:15`), and Tag vs ToneTag vs HostedStatusBadge, MeetingStatusBadge, RsvpStatusPill and PayoutsStatusChip. On top of those there are 14 private `_…Chip/Pill/Tag/Badge` widgets. One `StatusPill(tone, label, icon)` would cover most of them.
3. **41 private `_…Card` widgets**, including `_UpNextCard` ×2 and `_InviteCard` ×3. There are also 23 ad-hoc `BorderRadius.circular(cardRadius)` containers outside core that duplicate SectionCard.
4. **Web state markup is mostly ad hoc:**
   - 166 `<p className="form-error">` vs 12 `<ErrorNote>`. There are only 56 `role="alert"` in total, so most errors aren't announced, and none of the ad-hoc ones offer retry.
   - 67 `aria-busy` paragraphs vs 16 `<Loading>`.
   - 77 `className="empty…"` vs 16 `<EmptyState>`.
   - Examples: `components/MyTeams.tsx:59-60` and `components/explore/Explore.tsx:302-306`.
5. **Missing:** a shared Button component on the web (the CSS classes `.btn` and `.icon-btn` are used instead, which is fine), golden or visual regression tests, and an accessibility guideline test helper.

## State coverage matrix

The numbers are file:line. The offline state is global on both platforms: the app's `OfflineBanner` at `main.dart:192`, and the web's at `components/AppFrame.tsx:298` (signed-in users only).

| Screen | App loading / error / empty | Web loading / error / empty |
|---|---|---|
| Home | Skeleton `home_screen.dart:289`. **No feed error state**: `posts/view_models/home_feed.dart:53,67` swallows stream errors and marks the feed loaded, so a failure renders as "caught up/empty" (`home_screen.dart:317`). Action errors use a snack bar (`:107`) | `Dashboard.tsx:205` / `:103` / `:286` |
| Discover | `explore_screen.dart:366` / `:368` / `:370` | `explore/Explore.tsx:302` / `:306` (ad hoc, no retry) / `:308` |
| Schedule | `schedule_screen.dart:161` / `:60` / text at `:718` (not EmptyView) | `Schedule.tsx:507` / `:178` / `:508` |
| Teams | `teams_screen.dart:108` / `:52` / `:126` | `MyTeams.tsx:60` / `:59` (ad hoc) / `:69` |
| Chats | `messages/widgets/inbox_screen.dart:313` / `:403` / `:404` | `Messages.tsx:226` / `:314` / `:230` |
| Profile | `profile_screen.dart:180` / `:78` / `:184` | `app/profile/page.tsx:15` then `PlayerPage.tsx:119` / `:105` / `ProfileDashboard.tsx:122` |
| Team home | `team_home_screen.dart:437` / `:201` / `:438` | `team/TeamFeed.tsx:85` / `:87` / `:89` |
| Tournament | `hosted_tournament_screen.dart:242` / `:211` / `:261` | `tournaments/TournamentPage.tsx:61` / `:200` / `:62` |

## Accessibility findings

Icon buttons are in good shape. All 95 Flutter `IconButton`s that I spot-checked have a `tooltip:`, and the 13 web `.icon-btn`s all have an `aria-label`. All 8 `<img>` tags carry `alt`. A global `:focus-visible` ring exists (`site.css:220`, `app.css:1525-1534`), and so does `prefers-reduced-motion` (`site.css:503`). The app applies no text-scale clamp.

**Contrast**, light / dark:

| Pair | Light | Dark | Result |
|---|---|---|---|
| Accent on card | 4.92 | 6.98 | Pass |
| Accent on background | 4.53 | 7.99 | Pass |
| Text on accent (`onAccent`) | 4.92 | 6.73 | Pass |
| Muted on card | 5.86 | 6.18 | Pass |
| Muted on field | 5.10 | 5.62 | Pass |
| `accentInk` on `accentSoft` | 6.73 | 8.23 | Pass |
| `highlightInk` on `highlightSoft` | 5.29 | 8.46 | Pass |
| `live` on card | 4.63 | 5.36 | Pass |
| `onFeatureMuted` on feature | 9.53 | 7.12 | Pass |
| **Highlight (amber) on card** | **1.75** | 10.21 | Light fails |
| **Border on card** | **1.29** | 1.27 | Fails |
| **ToneTag text on its 14% tint** | **3.11–4.21** | 5.1–7.4 | Every light tone fails |

| ID | Severity | file:line | Issue | Fix |
|---|---|---|---|---|
| UX-1 | High | `core/ui/tone.dart:6-13,41,55` | ToneTag text at 11.5 px on its tint is 3.11 (amber), 3.42 (green), 3.51 (teal) and up to 4.21 in light mode. Below 4.5:1. Used for tournament and team status | Darken the light shades (for example amber `#8A5A00`, green `#1F6E43`) |
| UX-2 | High | `posts/view_models/home_feed.dart:53,67` | A feed error is shown as an empty "caught up" feed (state honesty) | Expose an error and render ErrorView with retry |
| UX-3 | Medium | `stats/widgets/game_screen.dart:386-388`; `posts/widgets/post_detail_screen.dart:369-372`; `teams/widgets/roster_tab.dart:279-280`; `notifications/widgets/notifications_screen.dart:503-504`; `home/widgets/home_screen.dart:860-862` | `shrinkWrap` with compact density gives tap targets of about 32–36 dp. "Undo last" while keeping a live game score is the worst case | Remove `shrinkWrap`, keep 48 dp hit areas, and make the visual size smaller |
| UX-4 | Medium | 42 `VisualDensity.compact` uses (for example `follow/widgets/follow_button.dart`, `explore/widgets/explore_cards.dart`) | Compact density shrinks the padded hit area to 40 dp | Audit them and allow it only on desktop |
| UX-5 | Medium | `chat/widgets/chat_tab.dart:929-930,949` | The chat room row is a fixed `SizedBox(height: 52)`, so its text clips at large text scale. The same applies to `group_tournaments/widgets/hat_parts.dart:116` (TabBar at 42) | Use `minHeight` constraints |
| UX-6 | Medium | `inbox_screen.dart:945`, `chat_tab.dart:906`, `notifications_screen.dart:272` | The unread dot in amber is 1.75:1 on a white card. Non-text contrast needs 3:1 (it does have a semantic label) | Use `highlightInk`, or add a ring |
| UX-7 | Medium | `theme.dart:157-163`; web `--line` | Input borders are 1.29:1 and field fill vs card is about 1.1:1, so field boundaries fail WCAG 1.4.11 | Use `border2` darkened to ≥3:1 for inputs only |
| UX-8 | Medium | 166 `form-error` paragraphs across 99 web files | Errors without `role="alert"` aren't announced | Migrate to `<ErrorNote>` |
| UX-9 | Low | `components/payments/Payments.tsx:187` | The Stripe element uses the light accent in dark mode (3.33:1) | Pass the theme's accent |
| UX-10 | Low | `app/app.css:674` | The composer textarea sets `outline: none` with no focus-within replacement | Add a `:focus-within` ring on `.composer` |
| UX-11 | Low | `components/AppFrame.tsx:212-299` | No skip-to-content link before the sidebar's roughly 10 links | Add a skip link |
| UX-12 | Low | `app/app.css:620-621` | `.icon-btn` is 36 px. That passes 2.5.8 AA (24 px) but is small for touch | Make it 44 px under the phone breakpoint |
| UX-13 | Low | `apps/mobile/test` | No `meetsGuideline` or text-scale tests. `test/screenshots/*` is opt-in PNG output, not assertions | Add guideline tests to the 8 sampled screens |

## Modernization opportunities

Option A in each appendix (00, 02, 03, 04, 09) is a navy header band, one mint summary card with green key figures, light cards beneath, and bottom tabs ordered Home · Discover · Teams · Schedule · Chat. The palette already matches (§2 of the development plan).

| # | Item | Platforms | Visual only? | Hours |
|---|---|---|---|---|
| 1 | Type scale and spacing tokens, then migrate the top 10 files (hosted_tournament, team_home, profile, message_thread …) | App (web: collapse the 86 font sizes to about 8) | Visual only | 16–24 |
| 2 | Up-next card: add the "N going" count and your RSVP chip (00/03). `TeamEvent.rsvps` already exists (`domain/models/team_event.dart:190`). The web already shows your RSVP (`Dashboard.tsx:390`) but the app card doesn't (`home_screen.dart:700-760`), which is a parity gap | Both | Visual only | 4 |
| 3 | Profile header: @handle, "followers \| teams" figures, season card (02). Followers already exist at `profile_screen.dart:575` | Both | Visual only | 6 |
| 4 | Team home summary card: season, player count, next practice with going count (04) | Both | Visual only, but **attendance % needs attendance tracking (not approved)** | 8 |
| 5 | Unify pills and badges into StatusPill, and fix the ToneTag contrast | App | Visual only | 6 |
| 6 | Align the playbook colours between web and app | Web | Visual only | 2 |
| 7 | Tab order Teams before Schedule (Q2) | Both | Visual only (needs approval) | 2 |
| 8 | Tournament tile: the concept already matches (dates, place, divisions, fee at `explore/widgets/explore_cards.dart:63-64`). An itemized checkout card exists as a sentence (`Payments.tsx:534`); make it a line-item table | Both | Visual only | 4 |
| 9 | Option B screens (discovery hub, career profile, organization console, host console) | Both | Needs new data or features (not approved) | — |
| 10 | Per-team colours (`docs/redesign-plan.md` Q4) to replace the hashed web tints in `SideTeams.tsx:15` | Both | Needs new data (not approved) | 6 |

**Navigation consistency.** The app (`shell/widgets/app_shell.dart:28-44`) has five tabs: Home, Discover, Schedule, Teams, Chats. Profile sits in the sidebar and the top bar, and Learn is reached from Discover or Settings. The web (`components/AppFrame.tsx:34-42`) has **six** tabs, adding Learn, and on phones shows them as a top tab bar at 10.5 px labels (`app.css:595-604`) rather than at the bottom. Signed-out visitors get a different five tabs. The labels and icons match. The differences to resolve are Learn's place and the tab order versus the concept. Both platforms badge unread chats.

## Suggested issues

| Title | Priority | Hours |
|---|---|---|
| Correct C-35 and readiness row 18 (the colour count is about 108, not 619) and re-scope to type and spacing | P2 | 0.5 |
| Home feed: show an error state instead of "caught up" on load failure (UX-2) | P1 | 3 |
| ToneTag, unread dot and input-border contrast fixes (UX-1, UX-6, UX-7) | P1 | 5 |
| Restore 48 dp tap targets on compact and shrinkWrap buttons (UX-3, UX-4) | P1 | 4 |
| Fixed-height rows clip under large text (UX-5) plus text-scale widget tests | P1 | 4 |
| Web: migrate ad-hoc errors to ErrorNote and announce them (UX-8) | P1 | 6 |
| Up-next card: going count and RSVP chip, app parity with web | P1 | 4 |
| Profile and team-home summary cards (Option A, without attendance %) | P2 | 14 |
| App type-scale and spacing tokens, first 10 files | P2 | 20 |
| Consolidate pills and badges into StatusPill | P2 | 6 |
| Web: skip link, composer focus, Stripe dark accent, 44 px phone icon buttons (UX-9 to UX-12) | P2 | 3 |
| Playbook colours: web matches app | P2 | 2 |
| Accessibility guideline and golden tests for the 8 key screens (UX-13) | P2 | 8 |
| Learn's tab placement and tab order decision (Q2) | P3 | 1 |

**Verified vs assumed.** All counts, line references and contrast ratios come from the code at 39c8a53. Hit-area sizes are derived from Flutter's density rules and weren't measured. Text clipping is inferred from fixed heights and wasn't rendered. Nothing was checked on a device or simulator.
