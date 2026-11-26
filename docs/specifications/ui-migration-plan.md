# UI migration plan

**Status: proposal, awaiting owner approval.** No application code changes
until approved.

- **Baseline:** `39c8a53` (app 0.0.55, web 0.59.5).
- **Target:** [`audit/Stall10_UI_Implementation_Guide.md`](audit/Stall10_UI_Implementation_Guide.md) (the guide), Document 17, and the five UI-updated specifications.
- **Evidence:** two read-only, screen-by-screen inventories with file:line references:
  - [`ui-inventory/flutter.md`](ui-inventory/flutter.md)
  - [`ui-inventory/web.md`](ui-inventory/web.md)

  This plan consolidates them. Every number below comes from them unless marked otherwise.
- **Not verified:** nothing was rendered or run. Visual judgements and hours are estimates.

---

## 1. What the guide changes, and the conflicts it raises

The guide is the newest UI document. It says to **"use the approved palette above rather than inferring colors from older artwork."** That
overrides two recommendations I made in the development plan. They are
listed here rather than settled silently.

| Topic | Earlier recommendation (development plan) | Guide | Effect |
|---|---|---|---|
| **Palette** | Q1: keep Turf & Disc navy `#0F1A2A` + green `#12805C`, because the UI-updated concept images use it | Doc 17's zinc neutrals + **indigo** accent `#4338CA` / `#A5B4FC`; **"Green only for success"** | A visible rebrand of both apps. Withdraw Q1; replace it with **UI-Q1** |
| **Tab order** | Q2: switch to Home · Discover · Teams · Schedule · Chats (UI-updated images) | Home · Discover · **Schedule · Teams** · Chats | That is **today's order**, so no change. Withdraw plan item U1 |
| Status of the palette | — | Called "proposed design defaults, not certified contrast results" and also "approved" | I checked contrast myself (§2); it passes, with one exception |
| Home tabs | — | "Following/Explore" | The app and web have Your teams / Following / Everyone. Keep them (changing them is a product change), **UI-Q10** |
| Web nav | — | 5 tabs, bottom on phones | The web has 6 (adds Learn), shown as a top row on phones. **UI-Q5** |

## 2. Proposed palette and contrast check

Values from the guide, ratios computed with the WCAG 2.x formula (4.5:1 normal text, 3:1 large text and UI
boundaries).

| Token | Light | Dark | Text on Surface, light / dark | Result |
|---|---|---|---|---|
| Canvas | `#F4F4F5` | `#09090B` | — | — |
| Surface | `#FFFFFF` | `#18181B` | — | — |
| Raised | `#E4E4E7` | `#27272A` | — | — |
| Text | `#18181B` | `#FAFAFA` | 17.7 / 17.0 | Pass |
| Muted | `#52525B` | `#A1A1AA` | 7.7 / 6.9 (6.1 / 5.8 on Raised) | Pass |
| Accent | `#4338CA` | `#A5B4FC` | 7.9 / 8.9 | Pass |
| On accent | `#FFFFFF` | `#18181B` | 7.9 / 8.9 on Accent | Pass |
| Success | `#166534` | `#86EFAC` | 7.1 / 12.6 | Pass |
| Warning | `#92400E` | `#FCD34D` | 7.1 / 12.3 | Pass |
| Error | `#B91C1C` | `#FCA5A5` | 6.5 / 9.3 | Pass |
| Live | `#BE123C` | `#FDA4AF` | 6.3 / 9.4 (4.95 on Raised) | Pass |
| **Border** | `#D4D4D8` | `#3F3F46` | **1.48 / 1.70** | Fine for card edges. **Fails 3:1 as an input-field boundary** (WCAG 1.4.11) |

Surface against Canvas is only 1.1:1 in both themes. Cards are told
apart from the page by the border, which fits the guide's "flat surfaces,
subtle borders".

### Tokens the guide doesn't define but the apps need

Both inventories found current tokens with no guide equivalent: the selected nav item, pills, unread badges, calendar
colours, the navy "feature" card, input outlines and the playbook field. These are proposed values; every pair was computed.

| New token | Light | Dark | Use | Contrast |
|---|---|---|---|---|
| `inputBorder` | `#71717A` | `#71717A` | Text field and select outlines | 4.8 / 3.7 on Surface ✔ |
| `accentSoft` + `accentInk` | `#EEF2FF` + `#3730A3` | `#1E1B4B` + `#C7D2FE` | Selected nav, active chips, tinted pills | 8.9 / 10.7 ✔ |
| `successSoft` | `#DCFCE7` | `#052E16` | Success pills (Success text on it) | 6.5 / 10.6 ✔ |
| `warningSoft` | `#FEF3C7` | `#451A03` | "Needs you" pills | 6.4 / 10.4 ✔ |
| `errorSoft` | `#FEE2E2` | `#450A0A` | Error banners | 5.3 / 8.5 ✔ |
| `liveSoft` | `#FFE4E6` | `#4C0519` | Live pills | 5.2 / 8.3 ✔ |
| `attention` (dot or badge fill) | `#D97706` | `#FCD34D` | Unread dot, count badge. Replaces today's amber at 1.75:1 | 3.2 / 12.3 non-text ✔ |
| `team` / `personal` | `#1D4ED8` / `#A21CAF` | `#93C5FD` / `#F0ABFC` | Calendar marks, always beside a label (Doc 17 §04) | ≥6.3 ✔ |
| `feature` (hero band) | `#18181B`, Text `#FAFAFA`, Muted `#A1A1AA` | `#27272A` | Replaces the navy FeatureCard and scoreboard band, *if kept* (**UI-Q6**) | 17.0 / 14.3 ✔ |
| Playbook field | unchanged (`FieldColors`) | unchanged | Sport surface, not UI chrome; align the web's grass and pen literals | n/a |

The status-pill rule is **soft fill + Ink text + a label** (never colour alone).
This also fixes UX-1, where every ToneTag in light mode was 3.1–4.2:1.

**Accent and success are the same green today** (app `theme.dart:476,494`;
web `.form-ok` uses `--accent`, `app.css:633`). After the swap, every place
that uses accent to mean "done/OK" must move to Success. This is an audit
step in Phase 1, not a restyle detail.

## 3. Foundations to build before any screen

### 3.1 Tokens

| Group | Value (guide) | Today | Work |
|---|---|---|---|
| Colour | §2 + extensions | App `AppColors` has about 30 fields (`theme.dart:336-535`); web `site.css:6-140`, with the dark block duplicated | Swap values behind the **existing token names** (aliases) so the 493 app and most web uses change in one step |
| Type | Inter 12 caption · 14 secondary · 16 body · 20 section · 24/28/32 heading; Barlow Condensed 800 for scores and metrics | App: 776 literal `fontSize` in **23 sizes**; web: 462 `font-size` in **86 values** | Named styles (`AppText.caption…heading3`, `--text-*`), then migrate screen by screen. **UI-Q4:** body 16 is larger than today's common 13–15 |
| Spacing | 4-pt grid: 4/8/12/16/24/32/48 | App 912 numeric `EdgeInsets`; web none; phone gutter 14 (guide 16) | `AppSpace` / `--space-*` |
| Radius | Card 16, control 12, chip pill | Already 16/12 on both | Add `chip` (999) |
| Motion | Feedback 100–150 ms, transitions 150–250, sheets 250–350; reduced motion respected | Partly | `AppMotion` / `--dur-*` |
| Breakpoints | <600 bottom tabs · 600–899 rail · 900–1199 sidebar · 1200+ context panel · 1600 cap | App 720/1200 (+840/860/1180); web 640/1000/1200 + 13 ad-hoc | One set on both. The shell changes first (§5 Phase 2) |
| Targets | 48 px | App: `shrinkWrap`/compact about 32–40; web `.btn` 44, `.btn-small` / `.icon-btn` 36 | Fixed in the primitives |

**Token source (UI-Q7).** The guide wants one JSON source that generates Dart
and CSS. For January I recommend **hand-kept mirrored files**:
`theme.dart` and `tokens.css`, plus a shared fixture test in
`packages/shared` that checks both carry identical values. The repo already
uses fixture vectors this way. That avoids a new build tool, which would
be a major dependency under CLAUDE.md §14. The generator can come after
launch.

### 3.2 Shared components

Built once per platform, each in its own design, with the same name and
states. "Screens" = how many of the 23 guide screens use it (Flutter / web
inventories).

| Primitive | Screens | Build from (Flutter) | Build from (web) | Required states |
|---|---|---|---|---|
| **StatusPill** (tone + label + icon) | 11 / 9 | Merge `Tag`, `ToneTag`, `CountPill`, `LivePill`, `NeedsYouPill`, `HostedStatusBadge`, `MeetingStatusBadge`, `CountBadge`, `RsvpStatusPill`, `PayoutsStatusChip` + 14 private pills | `RsvpPill`, `.pill`, `.count-badge` | All tones, light and dark, never colour-only |
| **AppButton** (primary, secondary, ghost, destructive, large, social) | 10 / all | Material themes, `HighlightButton` | `.btn*`, `.icon-btn` | Hover, pressed, focus, disabled, loading; 48 px hit area |
| **Tabs / SegmentedTabs** | 10 / 13 | `UnderlineTabs`, `SegmentedButton`, `schedule_screen.dart:560` toggle | Only `Dashboard.tsx:238-256` supports arrow keys; 19 other tablists don't | Keyboard arrows, `aria-selected`, scrollable |
| **Avatar / TeamLogo** | 10 / 10 | `PersonAvatar`, `UserAvatar`, `TeamBadge`, `team_initials` | `Avatar`, `TeamBadge` | Image, initials, fallback; drop the hashed web tints (`SideTeams.tsx:15`) |
| **EmptyState / ErrorView / Loading** | 8+ / all | `status_views.dart` (used about 60 times); 42 raw spinners | `StatusViews.tsx` vs 166 ad-hoc `form-error` and 67 `aria-busy` | Next action; retry; `role="alert"` |
| **SectionCard / Card** | 7 / 18 | `SectionCard`, `FeatureCard` (UI-Q6) | `.card` | Flat surface, border |
| **EventCard + DateBadge** | 6 / 4 | `DateBadge`, `EventDateBadge`, `_UpNextCard` ×2, `_ComingUpCard` | `DateTile`, `.event-date`, `EventItem` | RSVP chip, canceled, recurring |
| **ListRow / MemberRow** | 6 / 3 | ListTile theme, `_Row` | CSS only | Unread, muted, min height (no fixed 52) |
| **TextField / SearchField / Switch** | 3+ / 5 | Input theme (border fix), `AppSearchField` | `.settings-form`, `.auth-card input` | Label, hint, error, `inputBorder` 3:1 |
| **ConfirmDialog / Dialog** | 3+ / 9 | `confirm_dialog.dart` vs 49 raw `AlertDialog` | `Dialog.tsx` vs about 67 `confirm()` | Destructive variant, focus trap |
| **StatTile / ScoreText** | 5 / 2 | `StatBlock`, `ScoreText`, `_StatTiles` | `--font-score` | Barlow 800, tabular numbers |
| PostCard, Composer, FilterChips, DataTable, PriceBreakdown (gated) | 2–5 | Existing feature widgets | Existing | Per screen |

## 4. Screen inventory

Priority is from the guide: **P0** January, **P1** January if time,
**Inh** = inherited (restyle through tokens only), **Gated** = paid, off at launch.
Hours are restyle only and assume §3 exists. App and web hours are
separate. Full detail per screen is in the inventories: routes, current design,
changes, components, theme, responsive, preserve, accessibility, tests and dependencies.

| # | Screen | Pri | App routes / main files | Web routes / main files | Key visual changes | Must preserve | Accessibility to fix | Tests to add | App h | Web h | Depends on |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 01 | Auth / onboarding | P0 | `/sign-in`, `/sign-up`, `/welcome/*` (`router.dart:123-137`); `ui/auth/*` | `app/sign-in`, `sign-up`; `AuthForm.tsx` | Indigo primary, TextField, inline errors; re-tint the disc hero art (9 literals); web brand panel at 900+ | `from` redirect, invite links, reset, social flags, age gate | No `Semantics` (app); errors without role (web) | Goldens; e2e sign-in/up; axe | 6 | 4 | Button, TextField |
| 02 | Home / Following | P0 | `/home`; `home_screen.dart` (886 lines) | `app/page.tsx`; `Dashboard.tsx` | Flatten the navy Up-next card; add "N going" + RSVP chip (app parity); type scale | 3 tabs, pull-to-refresh, re-tap to top, composer draft, pagination, visitor preview | `shrinkWrap` (`home_screen.dart:860`); web error roles | Load/empty/error goldens; tab keyboard | 8 | 6 | EventCard, Tabs, UI-Q6 |
| 03 | Explore / post / composer | P1 | `/posts/:id`; `post_widgets.dart` (1,048) | `app/community`, `posts/[id]` | PostCard tokens, audience chips, upload progress | Realtime likes and edits, report/block, drafts, outbox | Composer focus (web `app.css:674`) | PostDetail widget test (none today) | 6 | 4 | 02 |
| 04 | Athlete profile | P1 | `/profile`, `/players/:uid`; `profile_screen.dart` (1,642, 36 font sizes) | `app/players/[uid]`; `PlayerPage.tsx` | Header band, StatTiles in Barlow; web stats panel at 1200+ | Private/blocked states, follow requests, images | `confirm()` (web) | Goldens; private states | 10 | 4 | StatTile; **hide self-reported history** (SEC-8) |
| 05 | Discover / search | P1 | `/explore`; `explore_screen.dart` | `app/explore`; `Explore.tsx` | FilterChips, EventCard, flatten CTA card | Signed-out discovery, `?query/?only` links, search flag | Compact chips (app) | Visitor vs member | 6 | 5 | FilterChips |
| 06 | Schedule / event | P0 | `/schedule`, `/team-events/*`, `/my-events/*` | `app/schedule`, team schedule | Segmented Week/Month, EventCard, EmptyState, calendar colours beside labels; web detail panel at 900+ | Field-path RSVPs, notes, recurrence, ICS, timezones, deep links | **Toggle 34 px, day cell 46 px** (`schedule_screen.dart:564,469`); web tabs on links | RSVP rollback, timezone, month/list | 10 | 8 | Tabs, EventCard, DateBadge merge |
| 07 | Teams directory | P0 | `/teams`; `teams_screen.dart` | `app/teams`; `MyTeams.tsx`, `SideTeams.tsx` | ListRow, role StatusPill, AppButton tiles; remove hashed web tints | Teams tab always opens the list, nested communities, invites, club 16+ gate | Ad-hoc error (web) | Empty membership | 4 | 3 | ListRow, StatusPill |
| 08 | Team overview / feed | P0 | `/teams/:id`; `team_home_screen.dart` (2,820, 34 font sizes) | `app/teams/[id]/*`; `TeamBanner`, `TeamNav`, `team_hub.css` | Compact header, StatTiles, flat cards, scrollable section tabs | Only enabled modules, role gating, public page, delete flow, realtime | Header text scaling (`:1728`); 5 `confirm()` (web) | Text-scale; outsider/denied | 14 | 6 | Tabs, StatTile, UI-Q6 |
| 09 | Roster / invites / roles | P0 | Roster section, `/teams/:id/roles` | `teams/[id]/roster`; `TeamRosterView.tsx` | MemberRow with Avatar + role pill; ConfirmDialog for removal | Pending invites, permission matrix, visitor and youth roster rules | `shrinkWrap` (`roster_tab.dart:279`); invite tabs keyboard | RolesScreen widget test (none) | 6 | 5 | MemberRow, Dialog |
| 10 | Community / pickup | P1 | Same hub, community kind | Same hub | Inherits 08; membership pills | Members private to visitors, approval to join | Hat tabs fixed 42 px | Community page | 4 | 4 | 08 |
| 11 | Organization | Inh | Hub, org kind | Hub, org kind | Tokens only | No cross-workspace rights | — | — | 0 | 2 | 08 |
| 12 | Chats / DMs | P0 | `/messages/*`, team chats; `message_thread_view.dart` (2,585) | `app/messages`, team chat; `Messages.tsx`, `TeamChat.tsx` | Bubble and row tokens, unread pill, Composer; sticky offsets from a token (web) | Outbox pending/failed/retry, mute, revoked access, mentions, no forced scroll | **Fixed 52-px rows** (`chat_tab.dart:929`); unread dot 1.75:1; web tabs on links | Send/pending/failed; text-scale | 14 | 8 | ListRow, StatusPill, Composer |
| 13 | Notifications | P0 | `/notifications/*` | `app/notifications` | ListRow, unread pill, Muted read items, EmptyState | Tap marks read and opens target, preferences | `shrinkWrap` (`:503`); unread dot | Empty and read states | 4 | 3 | ListRow |
| 14 | Competition discovery / detail | Inh | `/tournaments/*`; `hosted_tournament_screen.dart` (3,010, **54 font sizes**) | `app/tournaments/*`; `TournamentPage.tsx` | Merge badges into StatusPill / DateBadge; type scale | Spots left, respond steps, visitor view, deep links | ToneTag contrast; unlabelled search (web `:980`) | Visitor view | 14* | 5 | StatusPill, EventCard |
| 15 | Schedule / standings / bracket | Inh | bracket, draft, live-draft routes | Same | Tokens; Live = token + label | Live scores, drafts, last update | Hat TabBar fixed 42 | Live score | 8 | 6 | ScoreText |
| 16 | Host editor | Inh | `/tournaments/host,new,:id/edit` | Same | Tokens, form fields | Save/resume, publishing | Web error roles | — | 8 | 5 | TextField |
| 17 | Checkout | **Gated** | `PayOnlineButton`, payouts WebView | `enter`, `payments/*` | PriceBreakdown; Stripe accent per theme | Server total, payments flag | — | — | (4) | (3) | Financial approval |
| 18 | Stats recorder | Inh | `/teams/:id/stats/*`; `game_screen.dart` (1,990) | `teams/[id]/stats/*` | High-contrast outdoor tokens, Barlow scoreboard, 48+ px actions | Offline queue, undo, keys, line picking | **"Undo last" about 32 px** (`game_screen.dart:386`) | Text-scale; outdoor contrast | 8 | 6 | ScoreText |
| 19 | Playbook | Inh | `plays/*`, `whiteboards/*` | Same | Chrome tokens; align web field and pen literals | Gestures, steps, permissions | Small editor controls | — | 5 | 4 | UI-Q9 colours |
| 20 | Film | Inh | `/team-videos/*` | `teams/[id]/videos/*` | Chrome tokens; scrims stay black | Upload progress, external warning | — | — | 4 | 3 | — |
| 21 | Meetings / voice | Inh | `/team-meetings/*` | `teams/[id]/meetings/*` | Pills merged; `voice.css` literals to tokens | LiveKit lifecycle, permissions | — | **Device** | 5 | 4 | StatusPill |
| 22 | Settings | P0 | `/settings/*` (slide-over) | `app/settings/*` | SettingsRow, destructive button, input borders 3:1 | Theme choice, deletion re-auth, export, blocked list | Placeholder-only inputs (web) | BlockedAccounts test (none) | 5 | 4 | TextField, Dialog |
| 23 | Staff / moderation | Inh | `TeamReportsScreen` (pushed) | `app/staff` | Tokens; hide sections for non-staff | Audit-relevant actions | Note input unlabelled | — | 2 | 2 | — |
| — | Shell and nav | P0 | `app_shell.dart` | `AppFrame.tsx`, `app.css` | Breakpoints 600/900/1200/1600; 1600 cap; web bottom tabs on phones (UI-Q5) | Branch state, deep links, back, re-tap refresh, shortcuts, badges | Skip link (web), 48 px tab targets | Nav at 360/768/1024/1440 | (in 3.1) | 18 | Tokens |

\* Shared with 15.

**Features the guide shows that don't exist** (not in any estimate, not approved):
- Email-verification state.
- Ranked Explore and bookmarks.
- Discover map, radius and "For you".
- Schedule week view (web) and competition filter.
- Chat unread divider (app, suspected).
- Roster search.
- Member panel in chat.
- Organization console.
- Attendance %.
- Host step wizard.
- Receipts and refunds.
- Billing.
- Staff accounts, workspaces and jobs dashboards.
- Video annotation and web upload.

## 5. Incremental migration plan

Each phase is one or more small PRs per platform. Each lands with screenshots for review and keeps
behaviour unchanged ("do not change business logic to accomplish a visual
redesign", CLAUDE.md §7). The app and the web move together (parity), each in its own design.

| Phase | Contents | App h | Web h | Exit check |
|---|---|---|---|---|
| **0. Decisions and baseline** | Answer UI-Q1…Q10. **Capture baseline screenshots** of the P0 screens (app goldens at 360/768/1280 in light and dark; web screenshots) so every later change is reviewed as a diff. Add the test harness: Flutter `matchesGoldenFile`, `meetsGuideline`, text scale 2.0 (no new dependency); web Playwright + axe + Vitest/RTL (**new dev dependencies, needs approval, UI-Q8**) | 8 | 16 | Baselines committed; harness runs in CI |
| **1. Tokens** | New palette behind existing names (aliases); extension tokens; `AppText`/`--text-*`, `AppSpace`/`--space-*`, motion, radius `chip`; parity fixture test; **accent-vs-success audit**; remove the duplicate dark block | 12 | 10 | Both apps show the new palette everywhere. Contrast unit test on token pairs. Golden diffs reviewed |
| **2. Shell and primitives** | Breakpoints and shell (rail 600, sidebar 900, panel 1200, cap 1600); StatusPill, AppButton, Tabs, Avatar, EmptyState/Error/Loading, SectionCard, EventCard/DateBadge, ListRow, TextField, ConfirmDialog, StatTile | 25 | 32 | Each primitive has widget/component tests for all states, a11y guidelines and goldens |
| **3. P0 screens** | In order: 02 Home → 06 Schedule → 07, 08, 09 Teams → 12 Chats → 13 Notifications → 22 Settings → 01 Auth | 71 | 47 | Per-screen goldens and axe; existing tests still pass; device check of Home, Chats, Schedule |
| **4. P1 screens** | 03, 04, 05, 10 | 26 | 17 | Same |
| **5. Inherited and gated** | 11, 14–16, 18–21, 23 (these already pick up the Phase 1 tokens); 17 after financial approval | 54 | 43 | After launch, except bugs |

**Totals:**

| Scope | App h | Web h | Total |
|---|---|---|---|
| Phases 0–3 (P0) | 116 | 105 | **221** |
| Phase 4 (P1) | 26 | 17 | **43** |
| Phase 5 | 54 | 43 | about 97 after launch |

### Fitting January

The release audit's non-UI P0 work (security, prod, backups, tests) is
about 200 h. **UI P0 at 221 h plus that is about 420 h, roughly twice the capacity at
35 h/week before Jan 18.** The app also freezes **Jan 8** for App Store
review. Options (**UI-Q9**):

| Option | January UI scope | UI hours | What users see on Jan 18 |
|---|---|---|---|
| **A. Foundation-first (recommended)** | Phases 0–2, plus the P0 screens' most visible fixes only: Home card, Schedule toggle, Chats rows, Settings inputs, contrast and tap targets | about 120 | New palette, type, spacing, buttons, pills, tabs and states on **every** screen, because they all read the tokens. Screen-specific layouts (panels, headers) after launch |
| B. Full P0 restyle | Phases 0–3 | about 221 | Complete P0 redesign; most security and release P0 work must move, or the date must |
| C. Palette only | Phase 1 + contrast fixes | about 40 | New colours on old layouts |

Option A works because both apps already route almost all colour through
tokens (493 `AppColors.of` uses; CSS variables on the web). The palette,
radius and state changes land everywhere at once; only type and spacing
need per-file migration.

**Order for Option A within the schedule:**
- Phase 0–1 in week 1 (Nov 30).
- Phase 2 in weeks 2–3.
- P0 targeted fixes in weeks 3–5.
- App UI code done by **Jan 8**. Web polish continues to Jan 17.

## 6. Parallel work

There are two implementation lanes, plus independent review. Each lane works in its own worktree off the same commit, within the CLAUDE.md
limit of three agents.

| Lane | Owns | Starts after |
|---|---|---|
| Flutter UI | `apps/mobile/lib/ui/core/**`, then screen folders one at a time | The token contract (values and names) is approved |
| Web UI | `apps/web/app/*.css`, `apps/web/components/ui/**`, then screen components | Same |
| Shared | `packages/shared` token-parity fixture | First; both lanes depend on it |
| Review (read-only) | UI/UX review agent compares goldens and screenshots against the guide; QA agent runs a11y and regression | Each PR |

**Conflicts to avoid:** screen PRs never edit `core/ui` or `tokens.css`. A
needed primitive change goes back to Phase 2 as its own PR first.

## 7. Required automated tests (summary)

| Layer | Tests |
|---|---|
| Tokens | Parity fixture (app = web values); contrast ratios for every text/background token pair ≥ 4.5 (3.0 for boundaries) |
| Flutter primitives | Widget tests for each state; `meetsGuideline` (tap target, labels, contrast); `textScaler` 2.0 with no overflow; goldens in light and dark |
| Flutter screens | Goldens at 360/768/1280 in light and dark; loading, empty and error goldens; existing widget tests unchanged and passing |
| Web primitives | Vitest + RTL (states, keyboard on Tabs, `role="alert"` on errors) |
| Web screens | Playwright route smoke + axe on every P0 route; `toHaveScreenshot` at 375/768/1024/1440/1680 in light and dark; no theme flash on first paint |
| Device | Home, Chats, Schedule, Settings on a physical iPhone (TestFlight) and an Android device: dark mode, large text, VoiceOver/TalkBack |

## 8. Decisions needed

| # | Question | Recommendation |
|---|---|---|
| UI-Q1 | Adopt the guide's zinc + **indigo** palette (green only for success), replacing Turf & Disc navy + green? This replaces plan Q1 | Yes, as the guide directs; contrast verified (§2) |
| UI-Q2 | Keep today's tab order (matches the guide). This replaces plan Q2 | Yes, no change |
| UI-Q3 | Approve the extension tokens in §2 (input border, soft tints, attention, team/personal, feature) | Yes |
| UI-Q4 | Body text 16 / secondary 14 (larger than today's 13–15, so less dense) | Yes for body; dense lists use 14 |
| UI-Q5 | Web on phones: bottom tabs as in the guide, and where does **Learn** go (6th tab, or under Discover)? | Bottom tabs; Learn under Discover, matching the app |
| UI-Q6 | The navy "feature" card and scoreboard band: keep a dark `feature` surface (zinc-900) or go fully flat? | Keep one dark feature surface for Up next and live scores only |
| UI-Q7 | Token source for January: mirrored files + parity test, or a JSON generator? | Mirrored files now, generator after launch |
| UI-Q8 | Approve web test dev dependencies: Vitest, Testing Library, Playwright, axe-core (and optionally Stylelint) | Yes; Stylelint optional |
| UI-Q9 | January UI scope: A, B or C (§5)? | **A** |
| UI-Q10 | Keep Home's three tabs (Your teams / Following / Everyone) rather than the guide's Following/Explore? | Keep; changing tabs is a product change |

Separate product decisions noted in the inventories:
- Hide self-reported team history on profiles (SEC-8).
- Playbook colours: web aligns to the app.

## 9. Decisions recorded (owner, 2026-11-25)

The four mock-up boards in `docs/` (`Stall10 Athlete Experience UI Mockups-1.png`, `Team Experience UI Concepts-2`, `Ultimate Frisbee Dashboard-3`, `Competition Experience UI Board-4`) are the visual reference for every page. They supersede the older concept images where the two differ.

| # | Decision |
|---|---|
| UI-Q1 | Zinc + indigo palette; green only for success |
| UI-Q5 | The website matches the boards: sidebar on desktop, bottom tabs on phones |
| UI-Q6 | Follow the boards: light cards with summary tiles; drop the dark feature card |
| UI-Q9 | Foundation first (option A): tokens, then shell and shared components, then pages |
| UI-Q11 (new) | Bottom bar: **Home · Discover · Teams · Schedule · Chats**, the same on app and website. Teams and Schedule swap places compared with today. There is no profile tab: profile and settings open from your picture at the top right |
| UI-Q12 (new) | Keep every current feature and redesign its elements. January additions: Home summary tiles, Month/Week/List on both platforms, chat filters (All/Teams/Direct/Unread). All other new things on the boards come after launch and need approval |

Changes these make to the earlier sections:
- **§2:** unread dots and count badges use the indigo accent, as the boards draw them; the amber `attention` token is dropped. The `feature` (dark band) token is dropped.
- **§3.2:** two components are added: a **cover header** (photo with the profile picture or team logo sitting on its lower edge) and **summary tiles**.

Still open:
- UI-Q3: extension tokens.
- UI-Q4: 16 px body text.
- UI-Q7: mirrored token files.
- UI-Q8: website test dependencies.
- UI-Q10: Home feed tabs.

The recommendations in §8 stand until these are answered.

**Gate:** design work begins only after the owner approves every page and screen on the UI direction page.

Task board: https://claude.ai/artifact/6NYWMKQmuuRJeHrKJSM1yS

**Approved (owner, 2026-11-25):**
- Every page and screen design on the UI direction page. The design gate is lifted.
- UI-Q8: Vitest, Testing Library, Playwright and axe as **dev-only** website dependencies.

**Decided (owner, 2026-11-25), following the recommendations in §8:**
- **UI-Q3:** extension tokens approved:
  - input border;
  - soft pill tints;
  - team and personal colours.
  - Unread uses indigo, per §9.
- **UI-Q4:** body text 16, secondary 14, dense lists 14.
- **UI-Q7:** mirrored token files (Dart and CSS) plus a parity fixture test for January; a JSON generator after launch.
- **UI-Q10:** keep Home's three feed tabs (Your teams / Following / Everyone).
