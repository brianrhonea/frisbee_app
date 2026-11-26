# Stall10 — UI/UX implementation guide
November 2026 • January 2027 release reference

## Scope and authority
Consolidates Document 17 and the five UI-updated specifications. The palette and layouts are proposed design defaults, not certified contrast results or verified current screens. Keep Stall10 ultimate-first. January priorities: shared theme, navigation, Home, Teams, Chats, Discover, Schedule, profiles and onboarding. Preserve existing routes and behavior; advanced tools inherit shared styling unless approved. Paid hosting remains gated. Do not implement missing features merely because they appear here.

## Design tokens
| Token | Light | Dark |
|---|---|---|
| Canvas | #F4F4F5 | #09090B |
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

Inter: 12 caption, 14 secondary, 16 body, 20 section, 24–32 heading. Barlow Condensed 800 for scores and prominent metrics. Spacing grid 4; increments 8/12/16/24/32/48. Cards radius 16, controls 12, chips pill. Flat surfaces, subtle borders. Green only for success. Light/dark/system preference per device.

## Navigation and responsive shell
Mobile <600 logical px: Home, Discover, Schedule, Teams, Chats bottom tabs; avatar opens profile/settings. 600–899 rail; 900–1199 sidebar; 1200+ optional contextual panel; 1600+ cap reading width. Preserve scroll, branch state, deep links and browser back. Create menu is permission-filtered.

## Page inventory and implementation concepts
The following screen-level breakdown expands the earlier concepts into implementation guidance. Additional layout details are proposed, not previously approved mockups. P0/P1 labels are suggested January scope; inherited means restyle existing functionality only.

### 01. Authentication / onboarding — P0
- Mobile: Focused sign-in/signup form, reset and verification; progressive profile setup.
- Web: Centered form, optional brand panel.
- States and safeguards: Validation, pending verification, recoverable errors.

### 02. Home / Following — P0
- Mobile: Compact next-event RSVP dashboard, composer, Following/Explore tabs, post cards.
- Web: Sidebar, capped feed, right panel with upcoming events.
- States and safeguards: Empty feed, pagination, optimistic reaction rollback.

### 03. Explore / post detail / composer — P1
- Mobile: Ranked Explore, audience selector, media, comments, save/report.
- Web: Feed with contextual detail or dedicated route.
- States and safeguards: Draft recovery, private/deleted post, upload progress.

### 04. Athlete profile — P1
- Mobile: Avatar, sport/position, follow/message, Posts/Activity/Stats, team and career history.
- Web: Profile header, main timeline, contextual stats.
- States and safeguards: Visibility-aware sections; private dashboard separate.

### 05. Discover / search — P1
- Mobile: For you, Events, Teams; filters for sport, radius, date; map/list.
- Web: Search and filters with results and optional map.
- States and safeguards: Public discovery only when signed out; empty results.

### 06. Schedule / event detail — P0
- Mobile: Agenda default, week/month toggle, date badges, RSVP, personal/team/competition filters.
- Web: Calendar grid plus event detail panel.
- States and safeguards: Timezone, recurrence, canceled events, RSVP errors.

### 07. Teams directory — P0
- Mobile: Workspace list with team/community/org switcher and create/join actions.
- Web: Sidebar list with selected workspace context.
- States and safeguards: Empty membership, invitation pending, inaccessible team.

### 08. Team overview / feed — P0
- Mobile: Compact logo/header, next practice, pinned content, Overview/Feed/Schedule; Roster/Chat/More.
- Web: Workspace navigation and modular dashboard.
- States and safeguards: Only enabled modules; role-gated actions.

### 09. Roster / invitations / roles — P0
- Mobile: Member list, role labels, invite and management actions.
- Web: Searchable roster table and member detail.
- States and safeguards: Pending invites, permission denied, confirmation for removal.

### 10. Community / pickup — P1
- Mobile: Community header, join, events, posts and chat.
- Web: Community overview and upcoming events panel.
- States and safeguards: Membership and visibility distinct from teams.

### 11. Organization console — Inherited
- Mobile: Organization switcher, teams and role-scoped actions.
- Web: Management table and contextual details.
- States and safeguards: No automatic cross-workspace permissions.

### 12. Chats / channels / DMs — P0
- Mobile: Conversation list, channel drawer, pinned messages, composer, unread divider.
- Web: Workspace/channel sidebar, message pane, member panel.
- States and safeguards: Pending/failed/retry, mute, access revoked; no forced scroll.

### 13. Notifications — P0
- Mobile: Grouped alerts, unread markers, deep links and preferences.
- Web: Notification panel or full list.
- States and safeguards: Read state, deleted target, privacy on lock screen.

### 14. Competition discovery / detail — Inherited
- Mobile: Event cards with date, venue, divisions, capacity and bid; detail and registration.
- Web: Search/filter list with event overview.
- States and safeguards: Registration closed, waitlist if supported, source freshness.

### 15. Competition schedule / standings / bracket — Inherited
- Mobile: Overview, schedule, standings, bracket; compact score cards.
- Web: Expanded bracket and score panel with host tools.
- States and safeguards: Live source and last update; no color-only status.

### 16. Host wizard / dashboard — Inherited
- Mobile: Draft, verification, details, divisions, capacity, schedule, pricing, review.
- Web: Step navigation and registration management table.
- States and safeguards: Save/resume; approval and restricted paid publishing.

### 17. Checkout / receipt / refund — Gated
- Mobile: Team/division selection, itemized bid and fees, policy, secure payment.
- Web: Order summary beside checkout.
- States and safeguards: Server total; pending/failed/confirmed; no duplicate submission.

### 18. Statistics / game recorder — Inherited
- Mobile: Score, roster, large action buttons, undo, recent actions.
- Web: Expanded scoreboard, roster and event log.
- States and safeguards: Offline queue, conflicts, completeness and provenance.

### 19. Playbook library / editor — Inherited
- Mobile: Play cards and compact field canvas, step controls.
- Web: Library, field canvas, inspector.
- States and safeguards: Draft/revision, permissions, explicit return from full screen.

### 20. Film library / analysis — Inherited
- Mobile: Video, timeline, clips and assignments.
- Web: Library, video pane, annotation inspector.
- States and safeguards: Upload progress, private feedback, external video warning.

### 21. Meetings / voice — Inherited
- Mobile: Join controls, participants, mute/camera and leave.
- Web: Expanded meeting panel.
- States and safeguards: Permissions, reconnect, device errors.

### 22. Settings / privacy / billing — P0
- Mobile: Grouped account, theme, notification, privacy, support and deletion settings.
- Web: Settings sidebar and form panel.
- States and safeguards: Confirm destructive actions; billing only if enabled.

### 23. Staff operations / moderation — Inherited
- Mobile: Essential authorized case actions only.
- Web: Web-first role-scoped dashboard, accounts, workspaces, support, payments, jobs.
- States and safeguards: Audit trail, restricted case details, explicit confirmation.

## Component and interaction contract
Identity: avatar, logo, role, verification provenance. Social: composer, post, comments, reactions, bookmark, audience. Sports: scoreboard, bracket, roster, stat tiles and chart table alternative. Events: date badge, RSVP, recurrence/timezone. Coaching: canvas, timeline, clip, revision. Commerce: price breakdown, receipt, refund. Safety: report, block, privacy, restriction. All controls need focus, hover where applicable, pressed, selected, disabled, loading and error states. Empty states offer a relevant next action. Preserve input on recoverable errors.

## Accessibility and motion
WCAG 2.2 AA target; verify 4.5:1 normal text, 3:1 large text and applicable non-text controls. 48 logical px touch target, visible focus, keyboard navigation, 200% text/zoom, reduced motion. Proposed 100–150 ms feedback, 150–250 ms transitions, 250–350 ms sheets. Outdoor score controls need high contrast and labels.

## Engineering and acceptance
Shared JSON tokens generate Dart ThemeExtension and CSS variables/TypeScript. Native components remain platform-specific. Audit hardcoded colors, implement primitives, migrate primary screens, then remaining modules. Test representative widths, light/dark, loading/empty/error, keyboard, screen reader, deep links, permissions and visual regression. No runtime or route inventory verification performed for this guide.

## Source documents and visual references
Document 17 contains editable mobile/desktop light/dark wireframes. The five UI-updated documents contain paired visual concepts. Preserve these originals alongside this guide; use the approved palette above rather than inferring colors from older artwork.
- Stall10_02_Authentication_Athlete_Profiles_UI.docx
- Stall10_03_Social_Feed_Engagement_UI.docx
- Stall10_04_Teams_Organizations_UI.docx
- Stall10_Master_Product_Blueprint_UI.docx
- Stall10_Tournament_Marketplace_Blueprint_UI.docx
- Stall10_17_UI_UX_Design_System.docx
