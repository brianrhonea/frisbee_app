# Design tokens: K1 draft for approval

**Status:** approved by the owner on 2026-11-26 (Sprint 1 item K1), including the seven choices at the end. Nothing in the apps has changed yet. The values below are what K2–K8 will put behind the existing names.

**Sources:**
- the UI guide (`audit/Stall10_UI_Implementation_Guide.md`)
- `ui-migration-plan.md` §2, §3.1 and §9 (UI-Q1, Q3, Q4, Q6, Q7)
- the four boards

**The list itself** is [`packages/shared/fixtures/design_tokens/tokens.json`](../../packages/shared/fixtures/design_tokens/tokens.json). It is the single list both platforms must match, and the K8 tests will read it.

## How it works

- **Existing names stay.** Every app `AppColors` field and website CSS variable keeps its name. Only the values change, so all screens move at once (K2, K3).
- **A few names are added:**
  - `error` and `errorSoft` on both platforms;
  - `--success` and `--success-soft` on the website, because the app already has `positive`.
- **Contrast.** All 50 text/background pairs in the fixture pass in both themes: 4.5:1 for text, 3:1 for outlines and marks. I computed each one with the WCAG formula.

## Colour

| Meaning | App name | Website name | Light | Dark | Was (light) |
|---|---|---|---|---|---|
| Page background | `background` | `--bg` | `#F4F4F5` | `#09090B` | `#F5F6F1` |
| Alt page band | — | `--bg-2` | `#E4E4E7` | `#18181B` | `#EDEFE8` |
| Cards, sheets, bars | `card` | `--card` | `#FFFFFF` | `#18181B` | `#FFFFFF` |
| Field fill | `field` | `--field` | `#E4E4E7` | `#27272A` | `#EEF0EA` |
| Card edge, divider | `border` | `--line` | `#D4D4D8` | `#3F3F46` | `#E1E4DC` |
| Input, outline button, unselected chip | `border2` | `--line-2` | `#71717A` | `#71717A` | `#D5D9CF` |
| Text | `ink` | `--ink` | `#18181B` | `#FAFAFA` | `#0F1A2A` |
| Strong secondary text | `ink2` | `--ink-soft` | `#3F3F46` | `#D4D4D8` | `#3B4352` |
| Meta text | `muted` | `--muted` | `#52525B` | `#A1A1AA` | `#5E6573` |
| Primary action, link, selected | `accent` | `--accent` | `#4338CA` | `#A5B4FC` | green `#12805C` |
| On accent | `onAccent` | `--on-accent` | `#FFFFFF` | `#18181B` | |
| Soft accent fill / its text | `accentSoft` / `accentInk` | `--accent-soft` / `--accent-ink` | `#EEF2FF` / `#3730A3` | `#1E1B4B` / `#C7D2FE` | |
| Unread dot, count badge | `highlight` / `onHighlight` | `--disc` / `--on-disc` | `#4338CA` / `#FFFFFF` | `#A5B4FC` / `#18181B` | amber `#FFB627` |
| "Needs you" pill fill / text | `highlightSoft` / `highlightInk` | `--disc-soft` / `--disc-ink` | `#FEF3C7` / `#92400E` | `#451A03` / `#FCD34D` | |
| Live dot / pill fill / pill text | `live` / `liveSoft` / `liveInk` | `--live…` | `#BE123C` / `#FFE4E6` / `#BE123C` | `#FDA4AF` / `#4C0519` / `#FDA4AF` | `#D93636` |
| Error text / banner fill **(new)** | `error` / `errorSoft` | `--error` / `--error-soft` | `#B91C1C` / `#FEE2E2` | `#FCA5A5` / `#450A0A` | — |
| Success only | `positive` / `positiveSoft` | `--success` / `--success-soft` **(new)** | `#166534` / `#DCFCE7` | `#86EFAC` / `#052E16` | was the accent green |
| Nav sidebar, rail, top bar | `sidebar`, `onSidebar`, `onSidebarMuted` | — | surface / text / muted | same | |
| Selected filter chip | `chipOn` / `onChipOn` | `--chip-on` / `--on-chip-on` | `#4338CA` / `#FFFFFF` | `#A5B4FC` / `#18181B` | navy |
| Team / personal events | `team` / `personal` | `--team` / `--personal` | `#1D4ED8` / `#A21CAF` | `#93C5FD` / `#F0ABFC` | |
| Team badge (white initials) | `badge` | — | `#4338CA` | `#4338CA` | `#2C6FB7` |
| Retired dark card | `feature`, `onFeature`, `onFeatureMuted`, `featureHighlight` | `--board…` | surface / text / muted / raised | same | navy |
| Video and call surfaces, device mock-up **(new, added during K2/K3 review)** | `media`, `media2`, `onMedia`, `onMediaMuted` | `--media`, `--media-2`, `--on-media`, `--on-media-muted` | `#18181B` / `#27272A` / `#FAFAFA` / `#A1A1AA` | same | was the navy card |

**Website aliases.** These keep pointing where they did: `--amber`, `--brand` and `--glow`. `--danger` moves to the new `--error`. The duplicated dark block in `site.css` becomes one block (K3).

**Not changed:** the playbook field colours (`FieldColors`). They are the sport surface, not app chrome. On the website the playbook pieces now use literals matching the app: defense `#14213A` on both platforms (previously navy `#0F1A2A`/`#1A2940` on the website), and offense, disc edge and cones keep their earlier colours.

## Text (K6)

The fonts stay as they are: Inter for everything, and Barlow Condensed 800 for scores and big numbers.

| Name (app `AppText.` / web `--text-`) | Size / line height | Weight |
|---|---|---|
| `caption` | 12 / 16 | 500 |
| `secondary` (also dense lists) | 14 / 20 | 400 |
| `label` (buttons, chips) | 14 / 20 | 600 |
| `body` | 16 / 24 | 400 |
| `bodyStrong` | 16 / 24 | 600 |
| `section` | 20 / 28 | 700 |
| `heading3` / `heading2` / `heading1` | 24/32 · 28/36 · 32/40 | 700 · 800 · 800 |
| `scoreSmall` / `score` (Barlow) | 24/28 · 40/44 | 800 |

## Spacing, corners, motion, targets (K7)

| Group | Values | App | Web |
|---|---|---|---|
| Space | xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32 · xxxl 48; page edge 16, card padding 16, control padding 12 | `AppSpace.lg` | `--space-lg` |
| Corners | card 16 · control 12 · pill 999 | `AppRadius.card` | `--radius`, `--radius-control`, `--radius-pill` (new) |
| Motion | fast 120 ms (feedback) · base 200 ms (transitions) · sheet 300 ms; easing (0.2, 0, 0, 1); 0 when reduced motion is on | `AppMotion.fast` | `--dur-fast`, `--ease` |
| Targets | at least 48 px | in the shared buttons (C2) | |
| Breakpoints (for the shell, S2/S3) | rail 600 · sidebar 900 · context panel 1200 · content cap 1600 | | |

## Choices I made that need your OK

1. **Amber is retired.** Today "needs you" amber (`highlight`) is used both as a solid fill (unread counts, the score-report button, some chat badges) and as soft pills. I split it:
   - The **solid fill becomes indigo**, as the boards draw unread counts.
   - The **soft pill becomes the guide's warning amber**, with dark text at 6.4:1.

   Where the solid fill means "your turn" rather than "unread", it will look like a primary button. K4 lists each use:
   - `chat_tab.dart:906`
   - `chat_extras.dart:350`
   - `layout.dart:365`, `layout.dart:660`
   - `scoreboard.dart:98`
   - `theme.dart:246`, `theme.dart:287`
2. **The dark card is dropped (UI-Q6).** Its four names get light-card values, so the scoreboard band and feature cards become white cards with a border.
   - **Snackbars:** they use `feature` today. I propose they keep a dark look: text-coloured background with page-coloured text, `#18181B` / `#FAFAFA` in light, inverted in dark. Otherwise they would blend into the page.
3. **Selected chips** are solid indigo with white text. The other option is the soft indigo tint, which is quieter but less obvious.
4. **One outline colour** (`#71717A`) serves inputs, outline buttons and unselected chips, so no separate `inputBorder` name is needed. It passes 3:1 on cards and on field fill in both themes.
5. **Field fill** is `#E4E4E7`, darker than today. Fields will read clearly as fields on white cards.
6. **Team badges** use indigo in both themes. Before, they were blue in both.
7. **Line heights, score sizes and motion times** are my picks within the guide's ranges.

**Approval.** Approved 2026-11-26. K2 (app) and K3 (website) start from the approved list, then K4/K5 (success green) and K8 (tests).
