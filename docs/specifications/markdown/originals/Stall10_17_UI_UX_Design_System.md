<!-- Converted from Stall10_17_UI_UX_Design_System.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# STALL10

# 17 / UI/UX & Design System

Version 1.0  |  Approved product direction  |  November 2026

A modern, sport-neutral social experience for athletes, teams and communities.

### Design mandate

Replace the grass-green identity with neutral graphite and white surfaces and a proposed electric indigo accent. Retain the useful Turf & Disc foundations: Inter, Barlow Condensed, semantic tokens, responsive navigation and restrained cards. The latest user preference supersedes the earlier green palette.

### Scope

Flutter mobile and Next.js web; ultimate first, extensible to other sports. Social feed inspiration: Instagram, X and Facebook; activity and athlete identity: Strava; team channels and roles: Discord. These are interaction references, not designs to copy.

### Reading guide

02 Approved decisions • 03 Repository baseline • 04 Foundations • 05 Navigation • 06–11 Screen concepts • 12 Workflow states • 13 Accessibility and motion • 14 Engineering and acceptance

## 02 / Approved requirements

### Brand

Sport-neutral modern identity; replaceable Stall10 assets; retain useful Turf & Disc foundations, not grass green.

### Style and themes

Clean athletic social interface; light, dark and system; device-specific preference.

### Navigation

Home, Discover, Schedule, Teams, Chats; profile avatar.

### Home

Compact dashboard above Following and Explore; later customization.

### Desktop

Persistent sidebar, central content, contextual right panel when useful.

### Workspaces

Compact team header and configurable modules; distinct communities and organizations within Teams and Discover.

### Creation

Contextual actions and unified create menu.

### Profiles

Sports-first customizable public profile; separate private performance dashboard.

### Advanced tools

Expanded statistics, brackets, playbooks and film workspaces.

### Customization

Controlled team branding; no override of accessibility tokens.

### Interaction

WCAG 2.2 AA target, native motion, reduced motion, keyboard and outdoor usability.

### Engineering

Generated shared tokens, native components and visual regression.

### Mockups

Core mobile and desktop, light/dark, components and workflow states.

## 03 / Repository baseline

Selected development-branch files reviewed in the requirements assessment. Source implementation is not a runtime verification.

| Source | Observed foundation |
|---|---|
| Flutter theme.dart | Material 3, Inter, Barlow Condensed, 16/12 radii, semantic colors, platform transitions. |
| Flutter app_shell.dart | Five tabs, avatar profile, tablet rail, desktop sidebar, breadcrumbs, unread chat badges, command palette. |
| Web app/layout.tsx | Inter and Barlow, theme script before paint, auth and voice providers. |
| Web lib/theme.ts | Local system/light/dark preference, data-theme attribute. |
| docs/redesign-plan.md | Turf & Disc tokens; app/web parity; new teams enable Feed, Schedule, Chat, Roster only; Teams always opens list. |

### Migration decisions

Keep existing routes and actions; do not remove functionality because a mockup omits it. Replace palette through semantic tokens, audit hardcoded colors and migrate screen by screen. Preserve deep links and existing tests. The private redesign canvas was not inspected.

### References

https://github.com/brianrhonea/frisbee_app/blob/development/apps/mobile/lib/ui/core/themes/theme.dart

https://github.com/brianrhonea/frisbee_app/blob/development/apps/mobile/lib/ui/shell/widgets/app_shell.dart

https://github.com/brianrhonea/frisbee_app/blob/development/apps/web/app/layout.tsx

https://github.com/brianrhonea/frisbee_app/blob/development/apps/web/lib/theme.ts

https://github.com/brianrhonea/frisbee_app/blob/development/docs/redesign-plan.md

## 04 / Visual foundations

| Canvas | #F4F4F5 | #09090B |
|---|---|---|
| Surface | #FFFFFF | #18181B |
| Raised | #E4E4E7 | #27272A |
| Text | #18181B | #FAFAFA |
| Muted | #52525B | #A1A1AA |
| Border | #D4D4D8 | #3F3F46 |
| Accent | #4338CA | #A5B4FC |
| On accent | #FFFFFF | #18181B |
| Success | #166534 | #86EFAC |
| Warning | #92400E | #FCD34D |
| Error | #B91C1C | #FCA5A5 |
| Live | #BE123C | #FDA4AF |

Proposed palette, not final contrast certification. Use explicit on-color tokens; validate every text, icon, focus and state pairing. Green remains semantic success only. Team and personal event colors are supplemental to labels/icons.

### Typography and geometry

Inter: 12 caption, 14 secondary, 16 body, 20 section, 24–32 heading. Barlow Condensed 800: scores, timers and prominent metrics; tabular figures. 4-unit spacing grid; 8/12/16/24/32/48 increments. Cards 16 radius, controls 12, chips pill. Flat surfaces, subtle borders, restrained shadows.

## 05 / Navigation and responsive behavior

| | |
|---|---|
| Home | Dashboard, Following and Explore, composer |
| Discover | Search, athletes, teams, communities, events, competitions, rankings, Learn |
| Schedule | Unified agenda, calendar, RSVP |
| Teams | Workspace list, team/community/org switcher |
| Chats | Direct messages, group channels, unread |
| Avatar | Profile, settings, billing, privacy |
| Create | Post, event, team, competition; permission-filtered |

Proposed breakpoints: &lt;600 logical px bottom tabs; 600–899 rail; 900–1199 sidebar; 1200+ optional contextual panel. At 1600+ cap reading width rather than stretching feeds. Preserve scroll and branch state, support browser back, deep links and keyboard shortcuts. Full-screen tools may collapse navigation with an explicit return action.

### Desktop shell / light

| STALL10 | Search everything | Alerts • Profile |
|---|---|---|
| Home<br>Discover<br>Schedule<br>Teams<br>Chats | Following   Explore<br>Share an update…<br><br>Team recap<br>12–3 season record<br>Like  Comment  Save | Upcoming<br>Practice tomorrow<br>RSVP needed<br><br>Nearby events |
| Your teams<br>Dallas Club | Load more | View schedule |

Concept mockup • fictional content • editable Word cells; not a production screenshot.

## 06 / Social home and athlete identity

### Mobile home / light and athlete profile / dark

| STALL10   Search   Alerts | Profile   ••• |
|---|---|
| NEXT EVENT<br>Practice tomorrow 7 PM<br>RSVP needed  › | ALEX MORGAN<br>Ultimate • Cutter<br>Follow   Message |
| Share an update…  + | Posts  Activity  Stats |
| Following    Explore<br>Dallas Club • 2h<br>Tournament recap<br>5–1  \|  +24 point diff.<br>Like  Comment  Save | Season record  12–3<br>Goals 32  \|  Assists 18<br>Verified team stats |
| Home  Discover  Schedule<br>Teams  Chats | Current team • Dallas Club<br>Highlights • Career history |

Concept mockup • fictional content • editable Word cells; not a production screenshot.

Home: keep dashboard compact; chronological Following and ranked Explore. Composer supports audience, media and draft recovery. Use a consistent post header, content, media and engagement row. Profile sections are configurable and visibility-aware; private training and coaching feedback stay separate.

### Desktop social feed / light

| Navigation | Following  \|  Explore | Your week |
|---|---|---|
| Home<br>Discover<br>Schedule<br>Teams<br>Chats | Composer: share an update<br><br>Activity • 5 km run<br>25:10  \|  5:02/km<br>Like  Comment  Save | Practice • Tue<br>Pickup • Sat<br><br>Suggested communities |

Concept mockup • fictional content • editable Word cells; not a production screenshot.

## 07 / Teams and Discord-inspired messaging

### Mobile team and channel views / dark

| Dallas Club  ••• | Dallas Club / # general |
|---|---|
| 2027 season • 26 members<br>Overview  Feed  Schedule | Channels<br># announcements<br># general  (3)<br># film-review |
| Next practice • RSVP<br>Pinned: review offense | Coach • 9:41<br>Review the new play before practice.<br>[Playbook reference] |
| Roster   Chat   More<br>Enabled: Stats • Film • Plays | Reply…   +   Send |
| Home  Discover  Schedule<br>Teams  Chats | Unread • Jump to latest |

Concept mockup • fictional content • editable Word cells; not a production screenshot.

### Desktop team chat / dark

| Workspaces | # general   Search | Members |
|---|---|---|
| Dallas Club<br># announcements<br># general<br># film-review<br>Voice: Team meeting | Pinned: practice Thursday<br><br>Coach  9:41<br>Review the new offense.<br>[Open play]<br><br>Reply…  Attach  Send | Coach<br>Captain<br>Members<br><br>Channel details |

Concept mockup • fictional content • editable Word cells; not a production screenshot.

Distinct team, community and organization resource types; no automatic cross-workspace permissions. New teams start with Feed, Schedule, Chat, Roster. Enabled modules appear in More or contextual navigation. Channel roles, mentions, pins, threads, unread and mute states follow Document 06. Mobile channel drawer; desktop channel and member panes.

## 08 / Discover, calendar and competition

### Mobile discovery and schedule / light

| Discover  Search | Schedule   Today  + |
|---|---|
| For you  Events  Teams<br>Sport • Radius • Date | Agenda  Week  Month<br>Mon  Tue  Wed  Thu  Fri |
| Winter Invitational<br>Jan 23–24 • Dallas<br>3 divisions • 8 spots<br>$500 team bid<br>View details | TUE 7 PM • Team practice<br>RSVP: Going / Maybe / No<br><br>SAT 9 AM • Pickup<br>Open registration |
| Map  \|  List | Personal • Team • Competition |
| Home  Discover  Schedule<br>Teams  Chats | Home  Discover  Schedule<br>Teams  Chats |

Concept mockup • fictional content • editable Word cells; not a production screenshot.

### Desktop competition / light

| Competition | Winter Invitational | Host tools |
|---|---|---|
| Overview<br>Schedule<br>Standings<br>Bracket | LIVE • Pool A<br>Dallas  12 : 10  Austin<br><br>Next game  2:30 PM<br>Field 3 | Registration<br>8 spots remaining<br>Next steps<br>Publish schedule |

Concept mockup • fictional content • editable Word cells; not a production screenshot.

Signed-out visitors see eligible public discovery, not private athlete search. Map/list filters, saved searches and registration state must remain consistent. Calendar uses canonical events, timezone labels, RSVP and recurrence controls. Live scores show source and last update; no color-only status.

## 09 / Performance and coaching workspaces

### Desktop statistics recorder / dark

| Game • Offline saved | Dallas  8 : 6  Austin | Point 15 |
|---|---|---|
| Roster<br>A. Morgan<br>J. Lee<br>S. Patel | Possession: Dallas<br>Complete pass   Goal<br>Turnover   Block<br>Undo last action | Recent actions<br>Pass • 10:32<br>Block • 10:28<br>Sync pending: 2 |

Concept mockup • fictional content • editable Word cells; not a production screenshot.

### Desktop playbook and film analysis / light

| Play library | Horizontal stack • Draft | Inspector |
|---|---|---|
| Offense<br>Defense<br>Drills | FIELD CANVAS<br>O1      O2      O3<br>     O4 → O5<br>D1      D2      D3<br>Step 1  \|  Step 2  \|  Play | Selected player<br>Path • Timing<br>Save draft<br>Publish revision |
| Film library | VIDEO FRAME • 03:42 / 45:00 | Annotations |
| Game 1<br>Clips<br>Assignments | Timeline  ━━━●━━━━<br>Play  Pause  Seek | 03:42 Block<br>Link game event<br>Assign clip |

Concept mockup • fictional content • editable Word cells; not a production screenshot.

Dedicated landscape/expanded layouts with touch-friendly controls; compact mobile mode retains essential recording and review. Show statistical completeness, verification provenance, offline state and revision conflicts. Film annotations and private feedback require resource permissions; external video privacy warning.

## 10 / Payments, hosting and staff

### Mobile checkout / light

| Registration | Order summary |
|---|---|
| Winter Invitational<br>Team: Dallas Club<br>Division: Mixed | Team bid  $500.00<br>Platform fee  $15.00<br>Processing fee  calculated at checkout |
| Review refund policy<br>Confirm eligibility | Total shown before payment<br>Pay securely |
| Payment pending<br>Do not submit again | Receipt after confirmation |

Concept mockup • fictional content • editable Word cells; not a production screenshot.

Example amounts are illustrative; actual processing fees and total are server-calculated. Show host principal separately from buyer fees, refund terms, pending/failed/confirmed states. Never imply payment succeeded before authoritative confirmation.

### Desktop staff operations / dark

| Staff portal | Operations overview | Exceptions |
|---|---|---|
| Accounts<br>Workspaces<br>Support<br>Moderation<br>Payments<br>Jobs | Active users • 1,240<br>API health • Operational<br>GMV and earned revenue separate<br><br>Job runs  \|  Audit log | Payout review • 2<br>Safety case • restricted<br>Failed job • 1<br>Open authorized case |

Concept mockup • fictional content • editable Word cells; not a production screenshot.

Staff is web-first, role-scoped and audited. Sensitive case details never appear in general dashboard cards. Hosting wizard: identity verification, event details, divisions, capacity, schedule, pricing, review and publish; save draft and resume.

## 11 / Components and workflow states

### Reusable controls / light

| Primary action | Secondary action | Destructive action |
|---|---|---|
| Create post | Cancel | Delete draft |
| Selected filter | Unselected filter | Disabled action |
| Following ✓ | Explore | Unavailable |
| Loading | Empty | Error |
| Loading schedule… | No events yet<br>Create event | Could not load<br>Retry |
| Offline | Pending | Confirmed |
| Saved on device | Payment processing | Registration confirmed |

Concept mockup • fictional content • editable Word cells; not a production screenshot.

| | |
|---|---|
| Identity | Avatar, logo, role, verification provenance; accessible labels |
| Social | Composer, post, comments, reactions, bookmark, audience selector |
| Sports | Scoreboard, bracket, roster, stat tile, chart with table alternative |
| Events | Date badge, event card, RSVP, recurrence and timezone |
| Coaching | Canvas controls, timeline, clip, revision and assignment |
| Commerce | Price breakdown, receipt, refund and entitlement status |
| Safety | Report, block, consent, privacy, restriction and appeal |
| Feedback | Skeleton, empty, error, stale, offline, conflict, success |

All interactive components specify focus, hover (pointer only), pressed, selected, disabled, loading and error. No dead-end empty states; give a relevant next action. Preserve user input on recoverable errors.

## 12 / Interaction, motion and accessibility

| | |
|---|---|
| Microinteractions | Proposed 100–150 ms press/reaction feedback; avoid layout shifts. |
| Transitions | 150–250 ms ordinary transitions; 250–350 ms sheets; native back gesture; no artificial wait. |
| Feed | Optimistic reversible reactions; rollback with clear error. Preserve scroll on refresh. |
| Chat | Stable message ordering, pending/failed/retry, unread divider; no forced scroll when reading history. |
| Offline | Explicit local save, queued, syncing, conflict and synced states; restart recovery. |
| Reduced motion | Respect OS/browser; replace movement with brief fade or instant change; no autoplay motion by default. |
| Accessibility | WCAG 2.2 AA target; 4.5:1 normal text, 3:1 large text and applicable non-text controls; verify pairs. |
| Touch and keyboard | 48 logical px target, visible focus, logical tab order, escape/close, no keyboard traps. |
| Outdoor use | High contrast score and recording controls, large targets, text labels, no reliance on subtle color. |
| Media and charts | Captions where available, alt text, accessible data tables, pause controls, no color-only series. |

Support text scaling and browser zoom without clipping; test narrow widths and landscape. Announce asynchronous state changes without overwhelming screen readers. Never expose sensitive notifications on locked screens beyond user preference.

## 13 / Engineering and rollout

Shared JSON design tokens → generated Dart ThemeExtension and CSS variables/TypeScript. Keep native Flutter and React components; do not force identical platform widgets. Version tokens and publish a component catalog with light/dark, interaction and accessibility examples.

| | |
|---|---|
| packages/design-tokens/ | colors.json, typography.json, spacing.json, motion.json; generator and schema validation |
| Flutter ui/core/ | themes, components, layout; widget and golden tests |
| Next.js components/ | ui, sports, layouts; CSS variables; component and browser screenshot tests |
| docs/design-system/ | foundations, patterns, screen inventory, accessibility, migration notes |

### Rollout

1. Audit existing screens and hardcoded colors; establish token mappings. 2. Implement theme and component primitives; preserve existing route behavior. 3. Restyle Home, Discover, Schedule, Teams, Chats and profiles. 4. Migrate competition, checkout, coaching, settings and staff. 5. Validate parity, accessibility and performance before release. Use server-enforced feature flags for functional changes, not insecure legacy fallbacks.

### Acceptance criteria

Light/dark/system work without theme flash; all five tabs and deep links remain valid; team modules honor configuration; keyboard and screen reader workflows complete; 200% text/zoom remains usable; reduced motion works; offline drafts recover; checkout and permissions remain authoritative; screenshot regression covers representative widths and states; outdoor usability tested on devices.

### Validation and open engineering choices

Indigo palette, exact breakpoints, motion timings and component dimensions are proposed defaults. Mockups are editable conceptual Word layouts, not pixel-perfect prototypes or live animations. No repository changes, runtime testing, contrast certification or full screen inventory verification performed. Validate with athletes, coaches and organizers before implementation.
