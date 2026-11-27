# Stall 10 website changelog

The website's version is `version` in `apps/web/package.json`, shown in
the site's footer. Bump it with every change to the site and add an entry
here; `pnpm test` fails without one (`scripts/check-versions.mjs`).

## 0.63.8 — 2026-11-27

Signed-in browser fixtures (emulators only, synthetic data) and the profile directory's adult filter.

- `PersonPicker` lists profiles with `where("adult", "==", true)` next to the keyword filter (the new Firestore rules refuse a profiles list without it); unit test added.
- Opt-in `E2E_WORLD=1` Playwright projects: seed a synthetic world through the real API into the Auth and Firestore emulators (two teams with chat, single and weekly events, posts, DMs, notifications, a community, adult profiles and one unmarked minor that must not be found), sign Ada in through the sign-in form, and capture the H screens at 375 and 1440 px, light and dark. See tests/e2e/world/start.md. The normal suite is unchanged.

## 0.63.7 — 2026-11-26

- The four scripted smooth scrolls (compose, back to top on Home and Videos, jump to a pinned message) use a shared `prefersReducedMotion()` helper and scroll instantly under reduced motion (N13).
- Checked the whiteboard toast: `.frame .team-hub .wb-toast` (app.css) outranks the fixed `bottom: 24px` rule, so it sits above the phone tab bar.

## 0.63.6 — 2026-11-26

Navigation motion onto the K7 tokens (N13). Motion polish only; no routing changes.

- Dialogs open over the sheet time (`--dur-sheet`, 300 ms, `--ease`) with a short rise and a backdrop fade; both are 0 under reduced motion.
- The username check spinner stops under reduced motion; the pinned-message highlight fade uses `--dur-base` instead of a fixed 0.4 s.
- Tests: reduced-motion and token checks, and a width-change check (the page is not reloaded, URL and scroll place stay). Opt-in video recordings of the main journeys at 375 and 1440 px, light and dark (`E2E_MOTION=1`, projects `motion-*`), saved untracked under `review/web/motion/`.

## 0.63.5 — 2026-11-26

UI review fixes for the shell and components (Sprint 3 lane C). No routes, logic or permissions change.

- Blocker: an EmptyState's primary button was invisible (`.empty a` set the accent colour on an accent fill); it is now `.empty a:not(.btn)`.
- Confirm dialogs have their own title and confirm label for unblock, block, delete post, take back repost, leave team or community, make owner, cancel request, move Discord rooms, deal players, regenerate or replace the schedule, the staff actions, finish and cancel draft ("Keep draft" / "Cancel draft"), and "Tell the community?" ("Post it" / "Not now"). Destructive: delete post, block, make owner, move rooms, deal teams, regenerate and replace schedule.
- Phone: `--tabbar-h` is on `:root`; focused fields scroll above the tab bar (`scroll-padding-bottom`); the floating Post button hides where the stats dock or tournament bar shows; tab and rail labels are 11 px and ellipsise.
- Sidebar links are 48 px high; the search clear button has a 48 px hit area and the WebKit cancel button is hidden; summary-tile labels wrap and tiles go two across under 360 px.
- Second confirm question answers the first with no; a ReactNode message is not wrapped in a paragraph; ErrorState drops the old `form-error error-note` classes; SearchField's `role="search"` is opt-in (`landmark`); "Your sideline" is a paragraph and the sidebar a plain `div`.
- Tests: CRLF-safe CSS reads, new unit and browser checks for each fix, and `E2E_PORT` to run the browser tests on another port.

## 0.63.4 — 2026-11-26

Browser-test setup only: the route check (N8) is its own Playwright project that runs after the width projects (it starts a stub API on port 8787, which must not run beside them), and the shell width test has a longer timeout for first-visit compiles.

## 0.63.3 — 2026-11-26

Browser tests only (Sprint 3 N8 and N10): every page in `app/**/page.tsx` opens signed out (77 checks, with a stub API answering 404 so server-rendered pages do not need a real one), and the shell works by keyboard (skip link, reading order, focus rings, only the visible navigation is reachable, arrows on chips and tabs). The review-picture spec also captures the new gallery sections.

## 0.63.2 — 2026-11-26

C9: 168 plain `<p className="form-error">` messages in 84 files are now the shared ErrorNote (ErrorState): the same words in a soft red box, announced as an alert (`role="alert"`), the same colours in light and dark. Messages that sit in a form row keep their place; nothing about when an error shows has changed.

## 0.63.1 — 2026-11-26

C10: the browser's `window.confirm` is replaced by the shared ConfirmDialog (`useConfirm()`) in 39 files, about 60 call sites: deletes, removals, withdrawals, unblock, publish and the rest. Deletes and removals use the destructive variant. Same questions, same outcomes; only the dialog is new.

- Left on purpose: the two payment screens (`Payments.tsx`, `StaffPayments.tsx`, behaviour not touched without approval) and `StatsHome.tsx`, whose helper returns the answer synchronously. `tests/unit/noNativeConfirm.test.ts` fails if any other `confirm()` comes back.

## 0.63.0 — 2026-11-26

Shared components C5-C10, the website halves (Sprint 3). Same names as the app's: CoverHeader, SummaryTiles, ListRow, EventCard, DateBadge, EmptyState, ErrorState, LoadingState, TextField, SearchField, ConfirmDialog. All in `components/ui/`, every state on the `/dev/ui` gallery. No business logic, routes or permissions change.

- New: CoverHeader, SummaryTiles, ListRow, EventCard (RSVP chip, Cancelled, Repeats), DateBadge, TextField, TextArea, SearchField, ConfirmDialog, and `useConfirm()` with a `ConfirmProvider` in the layout (destructive variant; Esc cancels; focus returns to the opener; messages keep their line breaks).
- `StatusViews.tsx` (`Loading`, `EmptyState`, `ErrorNote`) now renders the shared LoadingState, EmptyState and ErrorState (a soft red box, `role="alert"`, a 48 px Try again button).
- `DateTile` and the event list's date badge are the shared DateBadge.
- `Dialog` keeps Tab inside the dialog (it wraps at the ends), so every modal has a focus trap.
- `Button` accepts `ref`.

## 0.62.0 — 2026-11-26

Website shell matching the boards (Sprint 3 S3, UI-Q5 and UI-Q11). No route changes.

- Sidebar from 900 px; an icon rail from 600 to 899 px; the tabs as a bar fixed to the bottom under 600 px (it was a row under the top bar). The right panel shows from 1200 px, and the whole shell is capped at 1600 px.
- Members' tab order is Home, Discover, Teams, Schedule, Chats. Learn is no longer a member tab: it opens under Discover (highlighted there, a "Learn to play" link in the sidebar, and a card on Discover). Signed-out visitors keep Learn as a tab.
- Bottom-fixed elements (floating Post, voice bar, game and stats docks, whiteboard toast) sit above the bottom bar, with the safe-area inset.
- A "Skip to content" link; the icon rail's create button has a name.
- Tests: tests/e2e/shell.spec.ts (N9) and tests/unit/AppFrame.test.tsx.

## 0.61.0 — 2026-11-26

Release-branch merge of #3a (account gate, web 0.60.0/0.60.1 on hold/3a-account-gate) with C1-C4 (0.59.9-0.59.14).

- 0.60.1 on the #3a branch was the same video-upload flag change as 0.59.8 below; it is listed once.

## 0.60.0 — 2026-11-26

Account gate (SEC-2, item #3a; docs/specifications/contracts/account-gate.md):
the website explains the gate, the API and rules enforce it.

- A write refused with 403 `account_incomplete` asks the status route once,
  refreshes the token if told (`refreshToken: true`) and retries once; if
  still refused it shows the first missing step: verify your email, About
  you (birth date) or the Terms. No loops. Every answer carrying
  `refreshToken: true` refreshes the token.
- New "Verify your email" step (resend, "I've verified" reloads the user
  and refreshes the token). Email sign-up now sends Firebase's verification
  email.
- Adults only (18+): the sign-up and About you birth date are refused under
  18 with the server's message; the guardian fields are gone; under 18 ends
  at a "Stall 10 is for players 18 and older" page with Sign out and Delete
  account (the account is no longer removed automatically).
- The birth date is read-only once saved; a refused change shows the
  server's message and support@stall10.app.
- Onboarding order: the birth date is saved (and the token refreshed with
  `ageOk`) before the username is claimed; accounts that skipped it are
  asked About you before "Your name and username".

## 0.59.14 — 2026-11-26

Review fixes 2 for C1-C4 (Sprint 2).

- Visitor home: the "From the community" link is drawn as the single feed tab
  again (accent text and underline); it lost its style when the feed tabs
  moved to SegmentedTabs.
- A loading button keeps full colour (only disabled buttons dim), and a
  disabled button no longer takes the hover fill.
- Scrolling tab and chip bars fade at the end (or start) that has more, only
  while they overflow.
- Avatar: a picture is not treated as broken just because an SVG reports no
  natural width.

## 0.59.13 — 2026-11-26

Review fixes for C1-C4 (Sprint 2).

- Fixes found in review of C1-C4: migrated pills keep their row layout
  (`.row-card > .ui-pill`, member roles, team share, team banner and roster
  sizes); `Button` and `IconButton` are client components and `buttonClass`
  moved to its own plain module so server components can use it; the existing
  `.btn-danger` stays solid ink (only the Button's destructive variant is the
  error fill); the gallery's browser checks are skipped against a deployed
  site, and a check that Explore, Learn and Sign in do not scroll sideways at
  320 px was added.

## 0.59.12 — 2026-11-26

C4: Avatar, TeamLogo, AvatarStack (Sprint 2).

- New `Avatar`, `TeamLogo` and `AvatarStack` (components/ui/Avatar.tsx): the
  image, else the initials, else a neutral glyph; a picture that fails to
  load falls back the same way. `AvatarStack` overlaps avatars with a "+N".
  Decorative unless given a `label`. Parity with the app's Avatar, TeamLogo
  and AvatarStack. `components/Avatar.tsx` and `TeamBadge` stay as thin
  re-exports so no caller changed.
- The sidebar's "Your spaces" and Home's team strip no longer colour each team
  from a hash of its id: a logo is drawn by kind (team, pickup community,
  school or club) from tokens. The team page's member stack uses
  `AvatarStack`. In dark mode the team logo blue is a little deeper (50% team
  over the board, from 55%) so its initials pass 4.5:1.
- The K5-D check on the hashed tints is replaced by a check on the logo tones
  in light and dark and that no per-team colour is left.

## 0.59.11 — 2026-11-26

C3: SegmentedTabs and FilterChips (Sprint 2).

- New `SegmentedTabs` and `FilterChips` (components/ui): the selected tab or
  chip is filled indigo with heavier text; the bar scrolls sideways instead of
  wrapping (holds up at 320 px and large text); each is a 48 px target.
  `SegmentedTabs` is a proper ARIA tablist (one Tab stop, Left/Right with wrap,
  Home/End, `aria-selected`, optional `aria-controls`); `variant="underline"`
  draws the line style. `FilterChips` is a radio group (one choice) or toggle
  buttons with `aria-pressed` (`multiple`). Parity with the app's
  SegmentedTabs and FilterChip.
- Moved onto them: the Home feed tabs (their own key code is gone), schedule
  view and filter, notifications filter, Explore chips, following settings,
  draft divisions, invite dialog, meeting panel and list, playbook, game and
  tournament stats tabs, group tournament tabs. Tabs that are links (Messages,
  team schedule) and the play editor's steps are left as they are.
- Their old per-page button styling is removed from the stylesheets.

## 0.59.10 — 2026-11-26

C2: Button and IconButton (Sprint 2).

- New `Button` and `IconButton` (components/ui): primary, secondary, ghost,
  destructive; small, medium, large; loading keeps focus, shows a spinner,
  ignores clicks and sets `aria-busy`. `buttonClass()` styles links the same.
  Parity with the app's AppButton.
- `.btn*` and `.icon-btn` gain hover, pressed and loading states from tokens
  (no brightness filters) and a 48 px hit area in every size without moving
  the layout (an invisible band around the control). The Button's destructive
  variant is the error fill; the existing `.btn-danger` (solid ink) is
  unchanged, pending the owner's choice between them.
- Messages, Notifications, Schedule, the invite and create/join dialogs use
  the components; the other buttons get the new states through the classes.

## 0.59.9 — 2026-11-26

C1: StatusPill (Sprint 2).

- New `StatusPill` (components/ui): one soft-fill pill for every status, with
  a label and an optional icon, in six tones (neutral, accent, success,
  attention, live, error). Parity with the app's StatusPill.
- `RsvpPill` and the loose "Needs RSVP" / "RSVP needed" / "Vote" spans now use
  it (`NeedsPill`). Plain status spans on tournaments, entries, rosters, team
  share, profile, explore, drafts and payments moved from `.pill` to it, with
  tones chosen by meaning (accepted success, declined error, live live, ...).
  Pills that are buttons or links, and counts, keep `.pill` / `.count-badge`.
- A components gallery at /dev/ui (404 in production) and browser checks on it.

## 0.59.8 — 2026-11-26

Video uploads behind the server flag (item #13, website part; docs/specifications/contracts/meta-flags.md).

- The site reads `meta/flags` from Firestore (readable signed out). Native
  video upload is offered only while `videoUploads` is literally `true`;
  loading, unreadable, missing or mistyped means closed.
- Team and direct chat: while closed, the attach button and menu say "Photo
  or file", and a video (picked or pasted, by type or by name: .mp4 .mov
  .m4v .webm .3gp) is refused with "Video uploads aren't available right
  now." before any request. Photos and documents are unchanged.
- If the flag is turned off after the page loads, the API's 412 message is
  shown on that file.
- The site has no other native video upload: team videos are YouTube links.
  No web version gate (the contract explains why).

## 0.59.7 — 2026-11-26

- Crash reporting (#7): `app/global-error.tsx` and `app/error.tsx` show a
  friendly message with "Try again" and a link home, and report the error
  (message, stack trimmed to 8 KB, page path without query string, web
  version, digest) to the API's `POST /v1/client-errors`. Uncaught errors
  and unhandled rejections are reported too: once per error per page
  load, at most 5 per page. Emails, tokens and query strings are blanked
  first; failures are silent.

## 0.59.6 — 2026-11-26

- Text, spacing, corner and motion tokens in `site.css` (K6/K7): `--text-<name>`
  (`weight size/line`, plus `--text-<name>-size`), `--space-<name>`,
  `--radius-pill`, `--dur-fast/base/sheet` and `--ease`; durations are 0
  under `prefers-reduced-motion`. Spacing, font sizes, corner radii and
  transitions that equalled a token now use it (no layout change; the
  .15s transitions now run at 120ms). The 26 skipped token-parity checks run.

## 0.59.5 — 2026-11-24

- Notifications: each row has an icon for what happened (like, repost,
  comment, follower, mention, message, meeting, event, …, as the app's
  bubble), the count sits beside the title instead of across the card,
  and Follow requests and its arrow aren't underlined.
- Styled links (cards, rows, buttons) are no longer underlined anywhere
  unless their own style says so (`:where(a[class])` in `site.css`);
  links in text keep theirs.

## 0.59.4 — 2026-11-24

- New logo colours: a red disc with a turf-green trail (logo and favicon,
  from the app's `tool/brand/stall10_logo.py`).

## 0.59.3 — 2026-11-24

- Hosting from a team: the form starts with the team's division and
  level ticked, and "Enter <team> in this event" (on by default) puts
  the team in its own event, with no fee.
- The host's team shows "Host · no fee"; it isn't asked to pay.
- Tournament cards show spots left per division ("Mixed: 3 left").
- The Captains' channel button shows only to organizers and the captains
  picked with a roster; other team admins message the organizers about
  their team.
- Paying needs the roster's minimum first, and confirms the team's spot
  (the reason shows on the Pay button until then).

## 0.59.2 — 2026-11-24

- Pay: when a fee can't be paid online, the reason shows (the host isn't
  set up for online payments, you run the event, …) above "We'll pay
  another way", instead of no button and no reason.

## 0.59.1 — 2026-11-24

- Setting up payouts more than 15 minutes after signing in asks you to
  confirm it's you (password, Google or Apple) and then opens Stripe's
  form, instead of Stripe's form saying it couldn't sign in.
- "Set up payouts" (was "Set up payments with Stripe"), with a line saying
  Stall 10 pays hosts through Stripe and never sees their details
  (`payoutsSetupNote`), so hosts know they aren't opening a Stripe account.

## 0.59.0 — 2026-11-23

Stall 10 collects every fee and pays hosts out. With app 0.0.51 and API
0.47.0.

- Embedded Checkout loads on Stall 10's account (no `stripeAccount` when
  the API sends none).
- Payouts card: new wording (Stall 10 sends the whole fee once each event
  is over; no Stripe account needed), held, sent, refunded and owed
  totals, and **Bank account and payouts** (Stripe's notification banner,
  account management and payouts components) once it's on.
  `/embed/payouts?view=manage` shows the same in the app's WebView.
- **Refund** for a fee paid online, on the event's Teams tab and hat
  signups, in place of the paid checkbox; it asks first and says the
  service and processing fees aren't refunded.
- Payouts card: **Each fee**, the list of fees paid online and where each
  stands. Payout setup says when a fresh sign-in is needed.
- `/staff`: **Payments**, problems found by the check against Stripe, the
  latest payments, **Send what's due to hosts** and **Check against
  Stripe** (staff only).
- `/staff` Payments: **Waiting for approval** (a host's first payout, and
  an event's once its payouts pass $2,000) with **Approve**.
- The event form's Publish waits until registration can open, 60 days
  before the start (Save draft still works), and says when.
- Terms and privacy: paying fees and getting paid (Stall 10 collects,
  payout hold, refunds, disputes, owed amounts, Stripe's agreements),
  payment records and Stripe in the privacy policy.

## 0.58.0 — 2026-11-23

With app 0.0.50 and API 0.46.0.

- **Respond** to a tournament invite a step at a time
  (`/tournaments/:id/respond`, also `/enter`): Accept or Decline first,
  then the roster (or **Set later**), then the fee (or **Pay later**),
  then **Request confirmed!** with what's left. Applying to a public
  event is the same flow and ends with **Request sent!**.
- The team page's invites have one **Respond** button, and **Entries to
  finish** lists entries still missing a roster or fee with **Finish
  entry**.
- Organizers: the event page's **Run your event** card (registration,
  confirm seeds, publish every schedule at once, play). The Teams tab
  saves the seed order once (**Save order** / **Confirm seeds**) and
  flags **Roster missing** and **Unpaid** teams.
- Event form: **Fees & deadline** (one entry deadline for rosters and
  fees) and a **Director** step (a Stall 10 member, or anyone by name,
  email and phone). The event page shows the director with **Message**,
  or their email and phone; visitors see the name only.
- Payments: Stripe setup happens on the page (embedded onboarding) with
  a **Payments: On / Finish setup / Not set up** status; organizers who
  aren't the owner are told who sets it up. Team settings show it to
  anyone who manages events. `/embed/payouts` hosts the same form for
  the app.
- A paid hat signup goes on to **Payment** (pay now or later), then
  **You're signed up!**.
- Deleting an event says its captains' chats go too.

## 0.57.0 — 2026-11-22

- Tournament invites have a reply-by time: the host form's **Invited
  teams answer by** (2 weeks before it starts by default, or 3 days, 1
  or 3 weeks, 30 days, or no deadline). After it the invite is
  **Expired** for both sides; the host's **Invite again** sends a fresh
  one.
- A team's admins see its tournament invites on the team page, with
  **Accept** (straight to picking captains) and **Decline**.
- Organizers who also enter a team see **Your teams** (its entry, invite
  and fee) on the event page; it was hidden from the event's managers.
- **Pay online** opens Stripe's embedded Checkout inside the page
  (`@stripe/stripe-js` 10.2.1, on the host's account) when
  `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` is set; without it, Stripe's page
  as before. `Permissions-Policy` allows `payment` for Stripe's frames
  (wallets).
- Accessibility (Lighthouse on dev): a post's author and time links are
  at least 24px tall (tap target size), and the footer's version text is
  no longer faded below 4.5:1 contrast.
- Fees: Stall 10's 3% and Stripe's card fee are always added to what the
  payer pays, so organizers get the whole fee; the form's "Teams cover
  the processing fee" checkbox is gone and the notes say what payers pay.

## 0.56.1 — 2026-11-22

- Pinned messages are their own view, from a room's ⋯: a card for each
  pin (author, date, text and files). Click one to jump to it in the
  chat, loading older messages as needed; it's tinted for a moment. The
  pinned strip is gone.
- Learn to play and the rules of ultimate are one page (`/learn`, the
  rules at `#rules`, each opening in place; `/rules` redirects there).
  On phones the lessons index is a compact list and the spacing is
  tighter. Settings and Help link Learn to play once.

- Chats: the reactions bubble on the first message (no room above it in
  the message list) opens under the message instead of behind the chat
  header, so its emoji can be picked.

- Security headers on every page: no framing (`X-Frame-Options: DENY`,
  `frame-ancestors 'none'`), `nosniff`, a strict referrer policy and a
  permissions policy; `X-Powered-By` removed (pentest P5).

## 0.56.0 — 2026-11-22

With app 0.0.47 and API 0.43.0.

- Pickup communities and schools/clubs have no division or level (create
  and settings); a team inside a school or club picks its level.
- Hosted events: **Who can enter** (Teams apply / Players sign up / Teams
  and players for leagues), `entryChoices` in shared.
- Team fee shares (`TeamShare.tsx`) on the team feed, as the app.
- Team chat rooms: ⋯ or right-click → **Mute notifications**; muted rooms
  show 🔕 and no unread dot.
- Chats: **Team chats** and **Direct messages** fold away for the browser
  session (sessionStorage).
- @mentions (`Mentions.tsx`): suggestions above the composer (arrows,
  Enter or Tab), mentions marked in messages, and "… mentioned you" on the
  team's row in Chats until the room is read (`useTeamChats`).
- **Rules of ultimate** (`/rules`, public) and Settings → **Help**
  (`/settings/help`), from `guides.ts` (`rulesGuide`, `helpTopics`,
  `officialRules`), as the app. Our own summary, linking the official
  USA Ultimate and WFDF rules.

## 0.55.1 — 2026-11-22

- Profile card: the name, then "@username · pronouns" and the badges
  (Stall 10 staff, Private profile) centered; the bio and details below a
  rule, left-aligned, one detail per line with an icon (hometown, school,
  throwing hand, playing since).
- Settings shows **Stall 10 staff: reports** (the `/staff` queue) to
  staff.
- `firebase/scripts/set-staff.mjs` read the first argument as the
  project when `--project` was left out; new `set-official.mjs` marks a
  team an official organizer.

## 0.55.0 — 2026-11-22

Works with API 0.42.0.

- **Before you start** (`AgreeTerms.tsx`, in `PersonalGate`): every
  member reads a summary of the Community Guidelines and agrees to them
  and the Terms of Service, after the name step and before About you.
  Existing members see it once. `/guidelines` is readable without it.
- Composer: a header with your picture (it opens your profile), your
  name and "Posting to" with the audience picker; the post below; the
  tools and **Send** in the footer. The empty box's hint goes round
  `postPrompts` (packages/shared).
- Inbox is now **Chats** (the tab, the page and its first view).
- The Chats tab has an unread bubble (`useUnreadChats`): conversations
  and team chats with something new, leaving out muted ones. Muted
  conversations and rooms show no unread dot (`useMutedRooms`,
  `teamChatSummary`'s `muted`).
- Notifications: messages are no longer listed or counted on the bell
  (they're in Chats); the Messages filter is gone. Opening a notification
  replaces the list in the history with the page it belongs under
  (`webParent` in packages/shared), so back goes to the team, Chats,
  the tournament or Home.
- Event and meeting editors: the Starts and Ends fields line up, with
  "(optional)" on the label's line (`.form-row`).
- Delete your account and Help: deleting works on the website (Settings
  → Account), and the legal pages give support@stall10.app.

## 0.54.0 — 2026-11-22

Works with API 0.41.0.

- Tournament chats with the organizers (`tournaments/TournamentChats.tsx`):
  a "Questions?" card on a hosted tournament's overview for captains of
  entered teams (the Captains' channel, and Message the organizers for
  each of their teams) and "Talk with captains" for organizers, who also
  get Message on each team's row (Waiting and the seeded teams). They
  open in Messages, where a tournament chat lists its people and links
  to the tournament, with no rename, add, remove or leave.
- "At a tournament" in the composer lists followed tournaments from a
  week before they start to their last day
  (`GET /v1/me/tag-tournaments`), and is hidden when none are.
- The "At …" tag on a post links to the tournament (`tournamentTagHref`:
  the hosted page, falling back to the group's tournament).
- Following: hosted tournaments open their own page; they opened the
  group-tournament page, which couldn't show them.

## 0.53.0 — 2026-11-21

Works with API 0.40.0 (online payments; shows nothing until Stripe is set
up on the API).

**Added**
- Hosts: the host's owner sees "Take payments online" on the event page
  and connects Stripe (`PayoutsCard`); `/payments/payouts` is where
  Stripe sends them back, and asks for a fresh link when one expired.
- Payers: "Pay $400 online" on each of your teams' entries (with whether
  its fee is paid) and on your own signup when the host takes payments
  (`PayOnline`); Stripe Checkout opens in the tab and comes back to
  `/payments/done`.
- Hosts see what reaches them of a fee paid online, under the price in
  the event form ("Paid online in Stall 10, you get about $94.80 of each
  $100…", `FeeBreakdownNote`) and on the payout card for the event's own
  fee. The fee section no longer says teams always pay the host directly.
- "Teams cover the processing fee" in the event form: paid online, the
  payer pays e.g. $105.41 for a $100 fee and the host gets $100; the Pay
  button shows the total and the processing fee.
- After paying: "Checking your payment…" until the API has asked Stripe
  (no second Pay button meanwhile), and "Your bank payment is
  processing…" while a bank payment clears.
- Marking a player's entry fee paid ticks at once and undoes itself if
  the save fails.
- "We'll pay another way" under the Pay button (and in its place when the
  host doesn't take payments online), with Undo; the host's lists show
  "Paying another way".
- Hosts mark teams' bid and spot fees paid on the Teams tab, as in the
  app (it wasn't possible on the website before), and add a note to any
  payment ("Check #1042"; `HostPaymentControls`), through
  `PUT /v1/tournaments/:id/payments/:payerId`.
- With online payments on, the form's "How to pay" reads "Other ways to
  pay".

## 0.52.0 — 2026-11-21

With app 0.0.43 and API 0.39.0.

**Added**
- Repeating events: new events (team, My calendar and shared calendars)
  have **Repeat**: daily, weekly on the day, every 2 weeks or monthly on
  the date, until an end date, with how many events that makes. Repeating
  events show "Repeats weekly until …". Editing or deleting one asks
  **this event** or **this and following events** (`components/Repeat.tsx`).
- **Directions** opens a menu: Apple Maps (on Apple devices), Google Maps
  or Waze (`directionsOptions` in packages/shared, `components/Directions.tsx`).

**Changed**
- Schedule, Month: the picked day's whole week (Monday to Sunday) is
  listed under the grid, and its row is tinted.
- Schedule's Calendars card is compact: the calendars on one line, one
  **Manage** button and one sentence instead of two links.

## 0.51.0 — 2026-11-20

With app 0.0.42 and API 0.38.0.

**Added**
- Word filter and photo checks, from the API: text with slurs or hate
  terms is refused with the community-guidelines message, swearing is
  saved masked, and unsafe photos are refused on upload.
- Community guidelines: "Words and photos we filter".

**Changed**
- Calendar settings: one **Subscribe** button opens the choices for this
  device (`subscribeOptions` in packages/shared): Apple Calendar on Apple
  devices, Google, Outlook and Outlook for work or school (straight to
  Outlook's subscribe page), and Copy link. The text says how often each
  calendar app checks the link.

**Fixed**
- Home's Upcoming events: an event's title opens it on its team's
  schedule, as the app's Coming up card and the sidebar already did.

## 0.50.0 — 2026-11-20

With app 0.0.41 and API 0.37.0.

**Added**
- Report on posts, comments, team posts and their comments, team chat,
  direct messages and profiles: a reason, optional details, and "Also
  block". Block and unblock from profiles and direct conversations.
- Posts, comments, message requests and group messages from people
  blocked either way are hidden; a blocked conversation says so in place
  of the composer.
- Settings › Blocked accounts; a team's Reports (Team settings, for its
  admins and moderators); `/staff`, the report queue for Stall 10's staff.
- "Stall 10 staff" badge on staff members' profiles (`staff/{uid}`).
- Community guidelines page (`/guidelines`, a draft for review), linked
  from the footer and Help; Help explains reporting and blocking.

## 0.49.0 — 2026-11-20

With app 0.0.40.

**Added**
- Schedule event editor: "New shared calendar…" in the Calendar list
  makes a calendar there (name, color, Can view / Can edit, people to
  invite) and selects it for the event.
- Add to calendar → Share…: the browser's share sheet with the .ics file
  (or the text), else copies "Title · when · where".

## 0.48.0 — 2026-11-20

With app 0.0.39. Needs API 0.36.0 for emoji beyond the old eight.

**Added**
- Chat reactions as the app: double-click a message (or React) for a
  bubble of quick reactions over it, with + for every emoji by group
  (`chatQuickReactions`, `chatReactionGroups` in `packages/shared`).
  The quick ones are now the app's ❤️ 👍 👎 😂 ‼️ ❓.

## 0.47.0 — 2026-11-20

Redesign features, second batch, with app 0.0.38. Needs API 0.35.0.
Details in `docs/product-spec.md` §8.1 items 35–44.

**Added**
- Tournaments: bracket page (`/tournaments/:id/bracket`), −/+ score
  steppers, league week stepper, Enter a team page
  (`/tournaments/:id/enter`), host form in steps with Save draft /
  Publish, Share (or copy link).
- Team videos: notes and clips pinned to moments (YouTube now plays
  through YouTube's IFrame API so notes can seek), comments, tag to an
  event; events list their tagged videos.
- "Add to calendar" menu: Google Calendar, Outlook, Apple / other
  (.ics).
- Team page: Going and New in chat tiles; roster Role column, O-line /
  D-line groups, Edit lines, Invites pending; More rows with
  descriptions, Manage team and Leave.
- Chat polls in team rooms.
- Team feed: Pin / Unpin (up to 3), comments with counts, "Post to the
  team…".
- Settings › Roles: per-person permissions with presets. Settings ›
  Visibility: Allow join requests; Request to join for outsiders.
- Discord import: Pick channels.
- Community pages: Next pickup card with RSVP, Chat rooms, Organizers.

**Changed**
- The Teams tab always opens `/teams` (`useSingleTeam` removed).

## 0.46.0 — 2026-11-20

Redesign features, with app 0.0.37. Needs API 0.34.0. Details in
`docs/product-spec.md` §8.1 items 26–34.

**Added**
- Live running scores: "Live score" dialog for captains and hosts;
  LIVE pill and score on games, the live header, tournament-day card
  and Discover's "Live now" (`useLiveScores`).
- Team Settings › Sections (new teams start with Feed, Schedule, Chat,
  Roster; `SectionGate`, `SectionsHint`) and Settings › Visibility ›
  Public team page.
- Playbook whiteboard: `/teams/:id/playbook?view=whiteboard`,
  `/teams/:id/whiteboards/new` and `/whiteboards/:playId`.
- Notes on event and meeting RSVPs (`RsvpNote`).
- Schedule List / Month switch.
- Meetings tab: Upcoming / Past, Live now, Needs RSVP.
- Team rooms: pinned messages and shared event cards (`ChatExtras`).
- Settings › Account › Download your data.
- Learn progress ("N of 12 read") and "N spots left" on tournament
  cards (`useTournamentSpots`).

## 0.45.0 — 2026-11-20

Navigation and the "Turf & Disc" redesign, with app 0.0.36. Works with
API 0.33.0. Plan: `docs/redesign-plan.md`.

**Changed**
- Navigation as the app: Home, Discover, Schedule, Teams, Inbox. Discover
  (`/explore`) takes in Find events: `/discover`, `/events` and
  `/schedule?view=find` redirect; chips All, Tournaments, Leagues,
  Pickup, Teams, Communities, Players (`?only=`). Header "Join free".
  Home feed tabs Your teams / Following / Everyone (old `?tab=` values
  still open), no composer on Everyone. The Teams tab opens your only
  team (`useSingleTeam`) and the team page links back to All teams.
- New palette and type (light by default, dark from the system or the
  toggle): turf green for actions, scoreboard navy for live and today,
  amber only for what is yours to do, red only for live games; Inter and
  Barlow Condensed (next/font) for scores, dates and the wordmark. New
  tokens in `site.css` (old names kept as aliases).
- Every page restyled: frame and public pages (W1), member pages (W2:
  home "Needs you", schedule grouped by day with "Needs RSVP", inbox,
  notifications grouped Today / Earlier, settings with an Appearance
  Light / Dark / System control, create team), team hub (W3: compact
  header with initials badge and a Message button, schedule with
  "Directions", a "Notes" card and counts on each RSVP answer, room
  access None / Read / Read & write, playbook grids, video rows, navy
  meeting room), tournaments, drafts and stats (W4: navy live header,
  live days open on Schedule, "Next steps", host chooser "What are you
  hosting?" / "Host as" in the order Tournament · League · Hat, Teams
  tab "Accept applications above", publish card with games as a stat,
  signups Accepted / To decide / Waitlist with an MMP/WMP bar).
- Delete, leave and other destructive buttons are solid ink or neutral,
  not red. The finish-sign-up intro no longer mentions USA Ultimate.

**Removed**
- `/events` page (now Discover's Coming up).

## 0.44.0 — 2026-11-19

Tournaments tab when one is ahead, with app 0.0.34. Works with API 0.33.0.

**Changed**
- A team's hub shows **Tournaments** in its tab row, after Chat, while
  the team has a tournament ahead (members; `hasTournamentAhead` in
  `@stall10/shared`, the app's rule), and drops it from More then.
- The team's Tournaments page starts with its tournament-day card when it
  has one.

## 0.43.0 — 2026-11-19

Tournament-day card, with app 0.0.33. Works with API 0.33.0.

**Added**
- On a tournament day the member home page (phones: in place of Up next;
  wider: the side column) and the team page show the team's card: the
  tournament (Live when it is), the next game (opponent, time, field;
  "Tomorrow" from 17:00 the evening before), record and pool place, and
  the last result (`useTournamentDays`, `TournamentDayCard`). One rule
  with the app: `tournamentDay` in `@stall10/shared`. Between pools and
  the bracket it says **Next game to be decided**; a next game on another
  day shows the day. Wide screens show it in the side column, phones
  above the feed.
- Captains get **Report score** / **Confirm score** on the card. It opens
  `/tournaments/{id}?division=…&game=…`: the Schedule tab with the game
  first under **This game**, its score form open when it's theirs to
  report. `?tab=schedule|results` picks a tab.

## 0.42.0 — 2026-11-19

Team chats in Messages, with app 0.0.32. Needs API 0.33.0.

**Added**
- Messages' Inbox lists the member's team and community chats above
  their conversations (`useTeamChats`): which rooms have new messages, the
  newest's time, an unread dot. A click opens the team's Chat on the only
  unread room, else the newest. Search matches team names. One rule with
  the app: `teamChatSummary` in `@stall10/shared`.
- A team's room list shows rooms with unread messages bold with a dot;
  the open room is marked read (`PUT /v1/teams/:id/chats/:room/read`) as
  messages arrive.

## 0.41.0 — 2026-11-19

Stats per team on profiles, with app 0.0.31. Works with API 0.32.0.

**Added**
- A player's page has a **Team** menu on its Career table (two or more
  teams with stats; `profileStatsChoice` in `@stall10/shared`, the app's
  rule), kept in `?team=`. It narrows the table and the season tiles.
  The Career table also ends with a Career total row, as the app's does.

**Changed**
- The sidebar's short label for a pickup community is "Pickup".

## 0.40.0 — 2026-11-19

UI review release 1, with app 0.0.30. Works with API 0.31.1.

**Changed**
- One name for communities: "Pickup community" (was "Community group")
  and "community" (was "group") in every page, dialog and placeholder,
  with the app's words. Explore's chip is **Communities** (`?only=groups`
  still works). Group messages keep "group".
- Stats: **Track a tournament** (was New tournament) and **Tournament
  stats** for the list, as in the app.
- The static About and account-deletion pages say pickup communities.

**Added**
- The invite dialog's **QR code** button shows the link as a QR code to
  scan (the `qrcode` package, rendered to an inline SVG, dark on white in
  both themes).

## 0.39.1 — 2026-11-17

List caps (security review S4).

**Changed**
- A post shows its newest 100 comments, oldest first, as the app does
  (it showed the oldest 300). The database rules now refuse a comments
  query for more than 100.

## 0.39.0 — 2026-11-17

Private profiles' posts (security review S1). Works with API 0.31.0.

**Changed**
- A player's page listens for new posts with `private == false` unless
  it's the member's own page or a private profile they're an accepted
  follower of, as the database rules now require. What the page shows is
  unchanged (it comes from the API).

## 0.38.0 — 2026-11-16

Needs API 0.30.0: deploy the API first. The site now sends an `id` with
every new comment, and older APIs turn that down (400). 0.37.0 is the
payments branch's.

**Added**
- Offline queue, as in the app: a message (direct or team chat), post,
  team post or comment sent while Stall 10 can't be reached waits in this
  browser (IndexedDB, `lib/outbox.ts`) and sends by itself, in order,
  once it can. Each keeps the id it got when sent, so nothing is posted
  twice. Photos and files are uploaded when added, so the queued item is
  the finished request. One tab sends at a time (a Web Lock); other tabs
  follow along (BroadcastChannel).
- Whether Stall 10 can be reached (`lib/online.ts`): the browser's
  offline event, a send that couldn't get through, then `GET /health`
  every 15 seconds until it answers.
- A banner at the top while offline or while anything waits: "You're
  offline. 2 items will send when you're back." It opens "Waiting to
  send", with Try again (for one the server turned down) and Discard.
- Messages still waiting show at the end of their thread, faded, with
  "Waiting to send", "Sending…" or why it wasn't sent.
- Composers say "Couldn't reach Stall 10. Your message will send by
  itself once it can." when they queue instead of send.

Likes, reactions, RSVPs and edits aren't queued; they say they couldn't
reach Stall 10, as before.

## 0.36.0 — 2026-11-16

Works with API 0.28.0 (no API change).

**Changed**
- Workout exercises are cards: "Exercise 1" with remove, the name across,
  then Sets, Reps and Weight each named above its box (placeholders alone
  disappeared once typed in, and the one-line row was cramped on a phone).
  Minutes and Distance show examples; Distance says it's optional.

## 0.35.0 — 2026-11-16

Works with API 0.28.0 (no API change).

**Changed**
- Notifications stay in the list once opened, marked read; the page no
  longer marks everything read after a moment. Unread entries are bold
  and larger, read ones lighter. A Mark all read button joins Clear.
- Follow requests moved from Settings to the top of Notifications
  (`/notifications/requests`, showing how many wait); `/settings/requests`
  redirects there, and app routes `/settings/follow-requests` and
  `/notifications/follow-requests` both open it (`webRoute`).
- Messages and team chat show each message's time beside it on hover,
  for the messages under a name (the app shows them with a swipe).

## 0.34.0 — 2026-11-16

Works with API 0.28.0 (no API change).

**Changed**
- Posts have no Link tool (Home composer) or "Add a link" field (team
  post composer), as in the app: web addresses in a post's text are
  links (`LinkedText`, `splitLinks` in `lib/text.ts`). Older posts keep
  their links, shown and removable when edited.

## 0.33.0 — 2026-11-16

Needs API 0.28.0.

**Added**
- Rankings are public: visitors see team rankings with Level (Club,
  College, League, Pickup) and Division (Mixed, Open, Women, Masters)
  filters kept in the address; old `?division=` links still work. The
  Players tab asks visitors to sign up. Youth is never shown.
- Explore points visitors to rankings and tournaments.

**Changed**
- A team's own members aren't offered Follow on its banner, and members
  see one Settings gear (beside the tabs).
- The team feed's roster card tells visitors only what they can do ("See
  who's on the team.") and is hidden where the roster is members-only.
- Get started: "Join or create a team", ticked once you're on any team,
  opens the create-or-join choice.
- The composer adds a link you typed but didn't add when you post; both
  composers check links with the app's rule (`normalizeLink`), including
  the team page's; Escape in the link field drops what was typed.
- If the team picked in "To" leaves your list before you post, the post
  isn't sent (it used to go to Everyone).

## 0.32.0 — 2026-11-15

Needs API 0.27.0.

**Added**
- "Club teams are for players 16 and over" when creating a club team,
  moving a team to club, making a community's team, and on invite links
  and club team invites. A refused join shows why where it failed.
- The community role picker notes that club teams take no one from roles.
- After signing up with email, "About you" remembers your date of birth
  even if you leave and come back later or use another device (saved
  right after the account is made; it never holds up sign-up). Settings
  → Personal details starts from it too.

## 0.31.0 — 2026-11-15

More for signed-out visitors (parents, friends, colleagues). Needs API
0.26.0.

**Added**
- Learn is open to everyone and rendered on the server.
- Events and the Upcoming events card are open to everyone (My schedule
  stays for members).
- Teams has "Find a team or group" for everyone; for visitors the top
  bar's search goes there.
- Visitors see an adult team's roster (names, numbers, positions).
  Youth teams' rosters and groups' members stay private, with a note.
- Visitors can browse Tournaments and leagues and follow a published
  event's overview, teams, schedule, scores, standings, bracket and
  news; server-rendered, live events refresh every minute. Entering,
  signing up and following ask them to sign up or log in, then return.
- Group tournaments show visitors their public listing.
- The tournament form says the location and About are public.

**Changed** (visitor routes review)
- A youth team shows visitors its card only, with "Youth teams share
  their posts and schedule with members only." Signed-in people who
  aren't on it still see its public posts and events (read live, as the
  app does).
- Signed-in people who aren't on a youth team see "Rosters of youth
  teams are private: only members see them." in place of its roster.
- Team posts and the tournament News tab show visitors the author only
  when the author's profile is public.
- A tournament page asks the API for another division only when it's
  one of the event's (an unknown `?division=` shows the first).
- Roster pages aren't indexed by search engines; avatars and post
  photos load with `referrerPolicy="no-referrer"`.
- Members see their own team's real name and address in the hub's
  banner (the public page hides a drafted league team's name and a
  youth team's address). Signed in, Find a team uses the members'
  search, so it lists every team as the app's search does.

**Changed**
- Visitor prompts and home copy say what's open without an account.
- Server-rendered tournament dates show in UTC until the page loads,
  then in the viewer's time zone.

## 0.30.1 — 2026-11-15

**Changed**
- Signing up with Google or Apple asks "Your name and username": first
  and last name (filled in from Google or Apple when they share it) are
  the name on your profile, posts and rosters; the username is suggested
  from them until you change it.
- New accounts with no name (Apple can hide it) are asked for one before
  anything else; the Home username card asks it too.
- "About you" starts your legal name from the first and last name you
  just typed.

## 0.30.0 — 2026-11-15

Home and team pages redesign. Works with API 0.25.x.

**Added**
- Home leads with a greeting and one composer: "To: Everyone" or a team
  you manage (team posts get Title, Where and Public).
- Team strip with New / Join; "+" by Your spaces creates or joins.
- The Your teams tab is a feed of your teams' posts; feeds load as you
  scroll ("Older posts" as a fallback).
- Get started checklist on an empty For you feed; a Needs you card for
  join requests; Invitations and the next event above the feed on
  phones; a floating Post button on phones.
- Feed tabs work with the arrow keys (ARIA tabs).
- Team banner: Invite (with a join-request badge), Follow, Join for
  groups, Share, a Settings gear, member count with avatars and your
  role, a two-line description with "more", and "Invite-only — have a
  code?" for signed-in outsiders.
- One invite dialog from the banner, Roster, the feed and Settings:
  a link made on open with Copy and Share, the rotating code, search
  people (every kind, groups too) and join requests.
- Feed side column: six members with roles, "All N members" and Invite.
- Shared Loading, EmptyState and ErrorNote views; a visible focus ring.

**Changed**
- Team nav: six tabs, More ▾ and the gear, sticky below the top bar.
  "Teams" shows only for organizations.
- Playbook, Videos, Stats and Tournaments have their own URLs;
  `/more?tab=…` and `/plays` redirect.

## 0.29.0 — 2026-11-15

Review checklist fixes. Needs API 0.25.0 (confirming a score sends it).

**Added**
- Messages: search conversations by name, and "More conversations".
- Team schedule: "Earlier events"; `?event=` opens past events too.
- `/teams/:id/stats`, `/plays`, `/videos` and `/tournaments` open the
  matching More tab.

**Changed**
- Confirming a reported score sends the score shown, so one changed
  meanwhile isn't confirmed.
- Dates follow your browser's language.
- Logging in returns you to the page you were on.
- Entry fees without payment instructions say paying on Stall 10 is
  coming soon.
- The pull timer, line picker and substitution card open as dialogs.
- Lists that could grow without end are capped or paged.

**Fixed**
- A meeting call hangs up when you lose access, sign out, or switch
  account.
- The post and stats game pages show errors with Try again instead of
  loading forever; "see replies in the app" shows to visitors only.
- Players with the same name are drafted in a fixed order (by uid), as in
  the app.

**Removed**
- Unused components, helpers, CSS and the `team-draft` redirect page;
  duplicated helpers merged (dates, error text, my teams, dialogs, photo
  attachments).

## 0.28.1 — 2026-11-15

**Fixed**
- Cancelling or closing the Google or Apple sign-in window (sign-in,
  sign-up, and confirming it's you before deleting the account) shows no
  error; a blocked pop-up says to allow pop-ups. As in the app.

## 0.28.0 — 2026-11-15

Needs API 0.24.0 (Remove calls `DELETE /v1/uploads/:id`).

**Fixed** (security review of the messaging batch)
- A `/messages?to=` link asks before starting a conversation ("Message
  <name>"); it opens one without asking only if it already exists.
- Remove in the composer deletes the unsent chat file.
- Message drafts are kept per member and cleared on sign-out.

## 0.27.0 — 2026-11-15

**Changed** (security review of Explore and calls)
- Voice channels re-check your access while you're in them: losing
  access to the channel or team disconnects, and losing the right to
  talk mutes you and keeps you listening.
- Leaving or losing access while joining a call (even during the
  microphone prompt) always hangs up.
- The lobby camera preview only runs when the meeting can be joined.
- Per-person volume also covers screen-share sound, and no longer fails
  above 100% in browsers without Web Audio.
- Meeting and voice settings are kept per account, with at most 200
  per-person volumes; saved devices that are unplugged fall back to the
  default.
- Explore's Search retries a failed search.

## 0.26.0 — 2026-11-15

**Added**
- My schedule shows every team's upcoming events and meetings beside your
  calendars, soonest first, with the app's All / Team / Personal filter,
  team-name tags when you're on several teams, and Delete for event
  managers.

**Changed**
- My schedule drops an entry at its end, or once it starts without one,
  as the app does (calendar entries used to have an hour's grace).

## 0.25.1 — 2026-11-15

**Fixed** (shared test vectors with the app)
- The balanced draft deals players in the app's order with the app's
  seeded shuffle, so the same seed gives the same teams on both.
- "Add to calendar" downloads the same file as the app (no calendar
  name, so it adds to an existing calendar).
- The stats roster is ordered like the app's; play animation positions
  match the app exactly.

## 0.25.0 — 2026-11-15

Needs API 0.23.0 (chat uploads send the file's `name`).

**Added**
- Accept or decline team invites on Teams and the home page.
- Send any file in team chat and messages; videos play and files
  download with their name and size.
- Load older messages in conversations, team rooms and call chat.
- A Message button on player pages, and `/messages?to=` links.
- Unsent messages are kept as drafts per conversation and room (in this
  browser).

## 0.24.1 — 2026-11-15

**Fixed**
- The team schedule counts an event or meeting as upcoming until it
  ends (or two hours after it starts, without an end), as the app does;
  this morning's practice used to stay under Upcoming all day.
- `/tournaments/:id?host=` ignores a host that isn't an id.

## 0.24.0 — 2026-11-15

**Added**
- Explore searches tournaments as well as players, teams and groups,
  with the app's All / Players / Teams / Groups / Tournaments filters.
  Below search: upcoming tournaments and leagues, recent results, a
  rankings preview and shortcuts, as in the app.
- A voice channel call stays connected as you move around the site. A
  voice bar on every page shows the channel, with mute and disconnect;
  leaving the team or losing access to the room disconnects.
- Meetings: pick your microphone, camera and speaker (where the browser
  allows), preview your camera in the lobby, set the meeting volume,
  mute audio, and turn each person up to 200%. Choices are remembered
  on this browser; the meeting volume also applies to watch together.

## 0.23.0 — 2026-11-15

Needs API 0.22.0 (sharing calendar events sends `calendarId`).

**Added**
- Notifications open the matching page for tournaments, signups, drafts,
  plays, videos, stats games, group tournaments and meetings.
- Change password in Settings → Account (email accounts), with the app's
  password rules, checklist and strength meter.
- The theme toggle has a System choice beside Light and Dark.
- The team schedule lists meetings beside events, with "New meeting".
- "Share with my followers" on new events in My schedule.

**Changed**
- Draft URLs match the app: `draft/:div` is the host's balanced draft and
  `live-draft/:div` the captains' draft; old `team-draft/` links redirect.
- `/tournaments/:id?host=` falls back to that group's tournament.
- Sign-up needs 8+ characters with a letter and a number, as in the app
  (it was 6+).

## 0.22.0 — 2026-11-14

Needs API 0.21.0.

**Added**
- Home has For you, Community and Your teams tabs (in the URL). For you
  shows your teams' posts, followed teams' public posts, followed
  tournaments' news, and tagged and shared-event posts; a Team post
  button sits under the composer.
- Hosts post news on a tournament or league's News tab.
- Import from Discord in team Settings (owners): preview roles, folders
  and rooms, and sort rooms into a community's teams.
- Posts can be tagged with a tournament you follow; a new team event can
  be shared with your followers; a group tournament's announcement is
  tagged with it.

## 0.21.0 — 2026-11-14

Needs API 0.20.0, with the LiveKit settings for calls.

**Added**
- Meetings: a team's Meetings tab (live, upcoming, past); admins schedule
  and edit them; each meeting's page with RSVPs; the room with a lobby,
  camera, mic and screen share (asked for only on joining), people and
  volumes, letting people in, the call's chat and end for everyone.
- Watch together: admins play a team video (upload or YouTube) and
  everyone's player follows, in step with the app.
- "Meeting started" pop-ups on every page; meeting notifications open the
  meeting.
- Voice channels in team chat: join, mute, leave; members who can only
  read a room listen.

## 0.20.0 — 2026-11-14

Needs API 0.19.0.

**Added**
- Tournaments and leagues: find upcoming events (from Explore too); host
  one (tournament, hat or league) with format, divisions, who can play
  and fees; edit or delete it; the host's checklist to publish, open and
  close registration.
- Teams apply, accept invites, pick captains, withdraw or reserve a
  spot; hosts accept, waitlist or decline teams, invite teams and seed
  them.
- Schedules by day and league week; report, confirm and correct scores;
  pool and league standings, brackets and final places; event news.
- Player-entry events show signups on the event's Players tab, with
  links to each division's draft board and team editor.
- A team's Tournaments tab lists what it hosts and plays in; followed
  tournaments open their page.

## 0.19.0 — 2026-11-14

Needs API 0.18.0.

**Added**
- Communities' own tournaments: the Tournaments tab lists them (New
  tournament for organizers); each has Schedule, Standings, Bracket and
  Teams, a champion banner, your team's card, and Follow for outsiders.
- Captains report and confirm (or dispute) scores; organizers set any
  score and seed the bracket.
- The editor: link a Tournament event, dates, day start times, format,
  pools and rules, schedule preview, players from RSVPs, dealt teams,
  captains, Save and Publish, and an announcement after the first publish.
- A Tournament event shows "View …" or, for organizers, "Set up
  tournament"; followed group tournaments open their page from Following.

## 0.18.0 — 2026-11-14

Needs API 0.17.0.

**Added**
- Stats tab: season record, top +/-, tournament folders and games; stat
  keepers create games and tournaments, optionally linked to a schedule
  event.
- Live game tracker: point by point and play by play, with pull timer,
  subs, timeouts, game point, end or resume, undo and keyboard shortcuts.
  Plays save every few seconds and milestones at once, as in the app.
- Game lines (build, edit, import), the point log with halftime and
  timeouts, and the box score; tournament pages (games by round, roster,
  shared lines, stats); the season stats table; the roster players page.

## 0.17.0 — 2026-11-14

Needs API 0.16.0.

**Added**
- Players for player-entry tournaments and leagues: sign up with skill
  and gender match, see your status and fee, withdraw. Hosts accept,
  waitlist, decline and mark fees paid, with an unpaid filter.
- A live captains' draft board: captains and time per pick, a pick clock,
  every team side by side, the pool with "Best first" and gender filters,
  and the host's pause, resume, undo, auto-pick, finish and cancel.
- A team draft editor: deal balanced teams, shuffle, change the count,
  move players, rename, set captains, save; leagues create their real
  teams from it.

## 0.16.0 — 2026-11-14

Needs API 0.15.0.

**Added**
- Team videos: admins add YouTube links (checked with YouTube, title
  filled in), edit, move between folders and remove videos, and create,
  rename and delete folders.
- Folder filters (All, each folder, Unsorted) with counts, and the 5 GB
  upload-space bar for admins.
- Each video has its own page; uploaded videos now play on the website.
  Uploading files from the website waits on the video transcode job.

## 0.15.1 — 2026-11-14

Needs API 0.14.1.

**Fixed**
- Deleting a team says when others are still on it and waits until
  they're removed or it's handed over, as the API now requires.

## 0.15.0 — 2026-11-14

Needs API 0.14.0.

**Added**
- Playbook editor: admins add and edit plays on a field (players,
  defenders, disc, cones, cuts and throws), add steps where dragging a
  piece records its path, add step captions, undo and redo, and play the
  animation. Members open any play to watch it. Plays in the Playbook tab
  link to their page, and the tab has a "New play" button for admins.

## 0.14.0 — 2026-11-14

Needs API 0.13.0.

**Added**
- "… is typing" in direct and group conversations, and your own typing
  shown to others (sent at most every few seconds, cleared when you stop).
- Settings → Privacy: **Read receipts**.

## 0.13.0 — 2026-11-14

Team admin on the website. Needs API 0.12.0.

**Added**
- Team Settings → **Roles** (owners): custom roles with a name, color,
  permissions and members, reordered with ↑/↓; and **Keeps stats** per
  member on teams.
- **School or club** in a team's Settings: ask a community to list the
  team, cancel the request, or leave.
- A community's **Teams** tab for its admins: add a team, accept or
  decline teams asking to join, pick which community roles join each team,
  and take teams out.
- **Manage rooms** in team chat (members who manage chats): new rooms,
  voice rooms and folders, rename, who can see and post (Everyone, roles,
  single members), move between folders, reorder and delete.
- **Delete** a team, group or community (owners, typing its name).

**Fixed**
- The event editor read a community's roles as a list; they're a map, so
  it broke for communities with roles.

## 0.12.0 — 2026-11-14

The website is becoming a full way to use Stall 10 on its own. Needs API
0.11.0.

**Added**
- Settings → Profile: change your **name, profile picture and header
  photo** (a wide banner on your profile card).
- Settings → **Notifications**: what to be notified about, for every team
  and per team, with "Use my defaults".
- **Mute** in a team chat room or conversation header.
- Profile cards show the player's header photo.

## 0.11.0 — 2026-11-14

Website parity (`docs/product-spec.md` §8.1). Needs API 0.10.0.

**Added**
- **Team posts** from the hub's Feed, for the team's admins: a title,
  words, a place, links, up to four photos (picked, dragged in or
  pasted) and whether it shows on the public page. Edit and delete in
  place.
- **Team events**: members who manage events add, edit and delete them
  from Schedule (type, when, where, notes, a poll, public or not, and
  who sees it in a school or club community).
- **RSVPs, reactions and polls**: Going, Maybe or Can't go on every
  event, then react and vote while going.
- **Send in team chat**: Enter sends (Shift+Enter for a new line),
  attach photos, reply to a message, react, and delete your own (or
  any, for moderators). Rooms you can only read say so.

- **Messages** (`/messages`): the inbox, Message requests and Archived
  beside the open conversation (`?c=`), live. Start a conversation from
  a person search (it lands as a request when they don't follow you),
  make a group of up to 10, rename it, add people who follow you, leave
  or (its creator) remove people. Send with photos, reply, react, delete
  your own, accept or delete requests, archive, and delete a
  conversation for yourself. "Seen" shows when they've read your last
  message. `j`/`k` move through the list, `Esc` closes.
- **Create** a team, group or school/club community (`/teams/new`), and
  **join with a code** from Teams, or straight from an invite link
  (`/join/<code>`) when signed in.
- A hub **Settings** tab for members: edit details (name, level, city,
  and for groups the description and approval), make invite links or a
  45-second code, approve or decline people asking to join, change
  members' roles and remove them, hand the team to another member
  (owners), and leave. Custom roles are still edited in the app.
- Notification links open the conversation, chat room or event itself
  (`webRoute`), not just its tab.

**Changed**
- Signed-out visitors see only team and community pages (and the
  community feed and posts). Explore, Events, player profiles, Learn,
  Rankings, Schedule, Messages, Notifications, Settings and the Teams
  tab ask them to sign up or log in (`JoinPrompt`), then return there.
  These pages now load in the browser with the member's token, so none
  of their data is in the page sent to visitors; Home's visitor preview
  and the right column no longer show events.

**Fixed**
- The sign-in `?next=` link only returns to a page on this site: a path
  with a tab or new line (`/%09/other.site`) could send people elsewhere
  after logging in.
- Learn's guide is a client component (`components/LearnGuide.tsx`), so its
  words are no longer in the page HTML sent to visitors.

## 0.10.1 — 2026-11-14

**Changed**
- New logo and favicon: the app's "10" disc mark with an indigo disc on
  white instead of lime on green, matching the site's palette. `public/logo.png` and `public/favicon.png` are drawn by
  `apps/mobile/tool/brand/stall10_logo.py`.

**Deploys**
- Vercel builds only `main` (production) and `development` (the dev site,
  and only when `apps/web/` or `packages/` changed). Other branches no
  longer get preview deployments. See `vercel.json` and
  `scripts/vercel-ignore.sh`.

## 0.10.0 — 2026-11-14

**Changed**
- New look: an indigo palette (light) and "Midnight" (dark), with an amber
  call-to-action colour, squarer buttons and softer cards.
- The frame has a top bar on every page: the Stall 10 wordmark, a search
  box (players, teams and events; it opens Explore) and notifications and
  your account. The sidebar gains Learn, a **Create a post** button
  (**Join Stall 10** for visitors), your teams, and an About card.
- Home for members is "Your daily huddle.": the composer, then
  **Following** and **Community** feed tabs, with a right column for
  finding pickup, what's coming up on your teams and Learn. Your profile
  card and stats stay on your profile page.
- Home for visitors, and the right column on other pages, use the same
  layout: the community preview with pickup, upcoming events and sign-up
  cards beside it.
- Upcoming events show as date badges in a list; empty states and card
  spacing are consistent across pages.
- The top bar's search sits centred between the wordmark and your account,
  with even gaps at every width.
- Sign-up is two steps, as in the app: **Account details** (first and last
  name, a username suggested from your name that you can change, with a
  live "available" check, birthday, email and password), then **About
  you** (your personal details). With email, under 13 is refused before an
  account is made. Signing up with Google or Apple (as in the app) asks
  your username, then About you, whose birthday removes an account under
  13.
- Log in and sign up have a new look to match the rest of the site;
  "Forgot your password?" sits beside the password field.
- Form fields are the same height across sign-up and settings, and button
  labels are bold everywhere.

**Added**
- A light/dark switch (sun/moon) in the top bar, for visitors and members.
  The choice is kept in that browser; until someone picks, the site follows
  the system setting.
- Events has a week strip like the app's Schedule: seven days from today,
  dots for each day's team events (indigo) and tournaments (amber), and
  previous/next week. Pick a day to see just its events.
- Team hubs on desktops show Playbook, Videos, Stats and Tournaments as
  tabs of their own; narrower screens keep them under More.
- "Your spaces" in the sidebar labels each one (Team, Community or
  School/club) with its member count (128, 1.2k), and leaves out teams a
  community of yours lists, as the Teams page does.

## 0.9.3 — 2026-11-14

**Fixed**
- Ask to follow a private player: the button says **Requested** as soon as
  the API answers, and **Ask to follow** again once a request is taken
  back, instead of waiting for the live listener, which sometimes took
  15 s or more right after the profile turned private.

## 0.9.2 — 2026-11-14

**Fixed**
- `WEB_SERVER_KEY` is trimmed when sent to the API and when checking the
  API's refresh calls (`/api/revalidate`), so stray whitespace in either
  copy can't make them differ.

## 0.9.1 — 2026-11-13

Fixes from the two-person live test, for a more real-time feel. Needs API
0.9.0 and the `notifications` functions from the same change.

**Fixed**
- **Private profiles for approved followers**: a player page showed "This
  profile is private" even to people the player had accepted. Members now
  see each player's page as the API builds it for them
  (`/v1/players/:uid`, `components/PlayerPage.tsx`), so an accepted
  follower sees the bio, stats and posts the moment the request is
  accepted.
- **Stale pages**: player and post pages were cached for a minute, so a
  profile turned private or a post edited or deleted still showed. For
  members, they're now refetched whenever the profile, the player's
  posts, their own follow, or the post changes (Firestore listeners as
  change signals, `useChangeSignal` in `lib/live.ts`); likes and reposts
  by others update the counts too, and a deleted post says "This post was
  deleted." For visitors, the API expires the cached copy at once through
  the new `POST /api/revalidate` (shared `WEB_SERVER_KEY`; cache tags in
  `lib/api.ts`). A private author's post page now asks visitors to log in
  instead of showing "not found", and members who were approved see it.
- **Notification links**: the website opened the app's route, so some
  links were 404s (a follow request opened `/settings/follow-requests`).
  Each now opens the website's page for it (`webRoute` in
  `@stall10/shared`, tested against every route the functions send);
  things only the app has open "Get the app".
- **Notification counts** (the `notifications` functions): repeats by the
  same person no longer count up, so asking to follow again, or liking,
  unliking and liking, stays "Jordan wants to follow you" / "Jordan liked
  your post". Undoing takes it back out: an unlike, a request taken back,
  declined or accepted, a deleted comment, an undone repost or an
  unfollow re-words the notification or removes it.
- The career table and recent games on a player page follow the player's
  "Show on my profile" switches, like the stat tiles.

## 0.9.0 — 2026-11-13

Core features to match the app. Needs API 0.8.0.

**Added**
- **Settings → Account**: delete your account and its data. Confirms it's
  you (password, Google or Apple), then runs `account-deleteAccount`.
- **Share** on every post: the device's share sheet, or copies the link.
- **Settings → Privacy → Who can message you** (`/v1/me/message-policy`).
- **Continue with Apple** on sign-in and sign-up. Needs Apple set up in the
  Firebase console (Services ID, return URL) and the site's domain in
  Authentication's authorized domains.
- Sign in with a **username** as well as an email (`account-signInEmail`).
- **Rankings** (`/rankings`, linked from Explore): teams by division and
  player ratings, read live like the app's Rankings screen. Members only.
- **Workout posts**: the composer's workout button adds an activity,
  minutes, distance (km or mi), effort and exercises. GPS recordings stay
  in the app. Workouts show their activity's name.
- **Your schedule** (`/schedule`, from Events), like Outlook or Apple
  Calendar: every calendar you're on in its color, shown or hidden on
  this browser; invites to accept or decline; add, edit and delete events
  on any calendar you can edit, picking which one. Viewers see title,
  time and place, never notes. **Add to calendar** on each event
  downloads an .ics file.
- **Settings → Calendars**: make calendars (name and color), invite people
  as Can view or Can edit (they see nothing until they accept), change
  roles, cancel invites, remove people, leave others' calendars, and a
  private subscription link for Apple Calendar, Outlook and Google
  Calendar (reset or turn off).
- **Add to calendar** on team and group events.

**Changed**
- Clicking **Home** while on Home scrolls to the top and reloads the feed.

**Fixed**
- Editing a post showed the old words until a reload; the card now
  shows the edit at once.
- Username sign-in errors no longer end in the HTTP status (" [401]").

## 0.8.0 — 2026-11-13

Personal details at sign-up. Needs API 0.7.0.

**Added**
- Sign-up asks the date of birth first; under 13 can't make an account.
- New accounts finish signing up with their legal name, birthday, phone,
  gender, mailing address and, under 18, a parent or guardian, before
  using the site (`PersonalGate`). The legal pages and help stay open.
  If the API can't say, nobody is held up.
- Older accounts see a **Complete your details** card they can dismiss.
- **Settings → Personal details** to see and change them.
- A birthday under 13 when finishing sign-up (Google sign-ups aren't
  asked first) removes the new account without sending the details
  (`account-deleteAccount`, or the login alone if that can't be reached).

**Changed**
- The sign-up form's name field is now **Name on your profile**, said to
  be public; the legal name is asked separately and stays private.

## 0.7.0 — 2026-11-13

Communities and their teams. Needs API 0.6.0.

**Added**
- A community's page has a **Teams** tab listing its teams. Its member
  managers invite people to each one from there.
- A team's member managers invite people by name from **Roster**.

**Changed**
- **Teams** groups like the app: your teams first, then each community
  with its teams under it, folded when it has more than three. A team
  one of your communities lists sits only under the community.
  Read live from Firestore instead of `/v1/me/home`.

## 0.6.0 — 2026-11-12

Website parity, slice W2 (`docs/product-spec.md` §8.1): team pages as a
hub. Needs API 0.5.0.

**Added**
- Team and group pages are a hub with tabs in the URL: Feed, Schedule,
  Roster (Members for a group), and for members Chat and More.
- **Feed:** members see every post live, marked "Members only" where it
  isn't public; everyone else sees the public posts. "Coming up" beside it.
- **Schedule:** events down the left, the open one beside them
  (`?event=`): when, where (a map link), notes, and for members who's
  going, maybe or out, reactions and poll results. Members also get past
  events.
- **Roster:** anyone signed in sees the roster as a table (number, name,
  position) and the members with their roles, each linking to their
  profile, with a filter. Visitors are asked to log in.
- **Chat** (members): rooms by folder beside the open room (`?room=`),
  live, with replies, photos and reactions. Read only for now.
- **More** (members): the playbook drawn on a field, videos (YouTube plays
  in place), tracked games with the record, and hosted tournaments. A
  group's More is its tournaments.
- Join an open group, or ask to join one that approves members, from its
  page; members see their role there.

**Not yet:** posting to the team, RSVPs, votes and reactions, and sending
chat messages happen in the app until their API endpoints exist.

## 0.5.0 — 2026-11-12

Website parity, slice W1 (`docs/product-spec.md` §8.1): posting,
comments, follows, notifications and settings. Needs API 0.4.0.

**Added**
- **Write posts** from Home: words, up to 4 photos (choose, drag in or
  paste; they upload while you type, through `/v1/uploads`) and up to 5
  links. Ctrl+Enter posts.
- **Edit and delete** your posts from the ⋯ menu, in place.
- **Comments** under every post, live: comment, reply (one level deep),
  like, edit and delete your own; the post's author can delete any.
  Enter sends.
- **Follow** players, teams and groups from their pages, with a bell for
  post notifications; private profiles get "Ask to follow" and
  "Requested". (Approved followers still see a private profile's page as
  private here; the app shows it.)
- **Notifications** (`/notifications`), live, with filters, an unread
  badge in the sidebar, mark-as-read as you look, follow back, and clear.
- **Settings** (`/settings`): profile details, privacy and what your
  profile shows, people you follow (a table with notification switches),
  and follow requests.
- Keyboard: `n` writes a post, `/` searches, `g` then `h`/`e`/`v`/`t`/`m`/`n`
  goes to Home, Explore, Events, Teams, Messages or Notifications.

**Changed**
- Member pages read Firestore in the browser (live), as the app does;
  every write goes through the API. `NEXT_PUBLIC_FIRESTORE_EMULATOR_HOST`
  points them at the emulator.

**Fixed**
- This changelog's 0.4.0 heading had a stray Windows-1252 byte.

## 0.4.0 — 2026-11-12

**Changed**
- New layout with the app's five tabs: Home, Explore, Events, Teams and
  Messages, in a left sidebar (icons only on tablets) and along the bottom
  on phones. Members get a Profile link; Learn, About and Help sit under
  the tabs; the account menu is at the bottom of the sidebar.
- Wide screens show what's coming up, and a sign-up card for visitors, in
  a right column.

**Added**
- Teams (`/teams`): your teams and groups; visitors get a sign-up prompt.
- Messages (`/messages`): points to the app until messages come to the web.

## 0.3.1 — 2026-11-12

**Fixed**
- The build compiles `@stall10/shared` first, so it works on a fresh
  checkout such as Vercel's (it failed with "Can't resolve
  '@stall10/shared'").

## 0.3.0 — 2026-11-11

**Added**
- Members like and repost posts (with an optional note) on every feed,
  profile and post page; a repost's likes and reposts go to its original,
  as in the app. Replies stay in the app ("Reply in the app").
- Reposts show the original post under the reposter's note.
- Members page through the community feed ("Older posts").

**Changed**
- Navigation follows who's signed in: members get Home, Community,
  Explore, Events and Learn, and an account menu (dashboard, public
  profile, log out); visitors get Community, Explore, Events, Learn and
  About, with Log in and Sign up.
- Sign-up prompts show only to visitors.

## 0.2.0 — 2026-11-11

**Added**
- Home page for everyone at `/`. Visitors see a preview (three recent
  posts, upcoming events, locked cards for teams, schedule and stats) with
  sign-up prompts; members see their profile dashboard: profile card,
  season stats, their teams, upcoming events with their RSVP, and their
  feed (`GET /v1/me/home`).
- Pick-a-username step for accounts made on the web.
- `/learn`: the rules of ultimate for beginners.
- Profiles use the dashboard layout.
- Version in the footer.

**Changed**
- `/home` and `/profile` go to `/`; signing in lands on `/`.
- The community feed and profiles show the newest page only; signing up
  shows the rest.
- Phones show the site links as a scrollable row under the header (they
  were hidden).
- A photo that won't load shows "Photo unavailable" instead of a broken
  image.

## 0.1.0 — 2026-11-11

First version: the public site ported from the Flutter web build and
`firebase/hosting` (community, posts, profiles, teams, events, search,
About/Help/legal pages, invite-link fallbacks, sign-in and sign-up).
