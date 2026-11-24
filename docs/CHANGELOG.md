# Stall 10 version log

Each feature branch bumps the version by one. The version lives in
`pubspec.yaml` (`version: X.Y.Z+N`, where `N` is the build number) and in
`appVersion` in `lib/ui/core/ui/brand.dart`; `test/version_test.dart`
fails if they drift apart or this log has no entry for the version.

Versions stay at `0.0.x` until the first App Store release. Codemagic
picks iOS build numbers on its own (see `docs/ios-release.md`).

Plain-language notes for testers are in
[release-notes.md](release-notes.md); add to both when you bump.

| Version | Date       | Branch                                  | Commits             |
|---------|------------|-----------------------------------------|---------------------|
| 0.0.52  | 2026-11-24 | `development`                           |                     |
| 0.0.51  | 2026-11-23 | `feature/platform-payments`             |                     |
| 0.0.50  | 2026-11-23 | `feature/tournament-flow`               |                     |
| 0.0.49  | 2026-11-22 | `feature/tournament-invites-pay`        |                     |
| 0.0.48  | 2026-11-22 | `feature/security-hardening`           |                     |
| 0.0.47  | 2026-11-22 | `feature/profile-staff`                 |                     |
| 0.0.46  | 2026-11-22 | `feature/launch-fixes`                  |                     |
| 0.0.45  | 2026-11-22 | `feature/tournament-fixes`              |                     |
| 0.0.44  | 2026-11-21 | `feature/payments`                      |                     |
| 0.0.43  | 2026-11-21 | `feature/report-block`                  |                     |
| 0.0.42  | 2026-11-20 | `feature/report-block`                  |                     |
| 0.0.41  | 2026-11-20 | `feature/report-block`                  |                     |
| 0.0.40  | 2026-11-20 | `feature/redesign`                      |                     |
| 0.0.39  | 2026-11-20 | `feature/redesign`                      |                     |
| 0.0.38  | 2026-11-20 | `feature/redesign`                      |                     |
| 0.0.37  | 2026-11-20 | `feature/redesign`                      |                     |
| 0.0.36  | 2026-11-20 | `feature/redesign`                      |                     |
| 0.0.35  | 2026-11-19 | `feature/redesign`                      |                     |
| 0.0.34  | 2026-11-19 | `feature/team-first`                    |                     |
| 0.0.33  | 2026-11-19 | `feature/team-first`                    |                     |
| 0.0.32  | 2026-11-19 | `feature/team-first`                    |                     |
| 0.0.31  | 2026-11-19 | `feature/profile-team-stats`            |                     |
| 0.0.30  | 2026-11-19 | `fix/ui-wording`                        |                     |
| 0.0.29  | 2026-11-17 | `fix/private-posts`                     |                     |
| 0.0.28  | 2026-11-16 | `feature/offline-queue`                 |                     |
| 0.0.26  | 2026-11-16 | `feature/web-parity`                    |                     |
| 0.0.25  | 2026-11-16 | `feature/web-parity`                    |                     |
| 0.0.24  | 2026-11-16 | `feature/web-parity`                    |                     |
| 0.0.23  | 2026-11-14 | `feature/web-parity`                    |                     |
| 0.0.22  | 2026-11-14 | `feature/web-redesign`                  |                     |
| 0.0.21  | 2026-11-14 | `feature/web-redesign`                  | `848021e`           |
| 0.0.20  | 2026-11-13 | `feature/core-parity`                   |                     |
| 0.0.19  | 2026-11-13 | `feature/personal-details`              |                     |
| 0.0.18  | 2026-11-13 | `development`                           |                     |
| 0.0.17  | 2026-11-12 | `development`                           |                     |
| 0.0.16  | 2026-11-12 | `development`                           | `9ba6ea0` and later |
| 0.0.15  | 2026-11-12 | `feature/leagues`, `monorepo`           | `e3bac8b` and later |
| 0.0.14  | 2026-11-06 | `development`                           |                     |
| 0.0.13  | 2026-11-05 | `hardening/scale-and-abuse`             | `09d17af` and later |
| 0.0.12  | 2026-11-05 | `development`                           |                     |
| 0.0.11  | 2026-11-04 | `development`                           | `6d50dc5`–`ea081ac` |
| 0.0.10  | 2026-11-03 | `development`                           | `bfcf7f4`–`b80e854` |
| 0.0.9   | 2026-11-02 | `feature/gps-workouts`                  | `41a03bc`           |
| 0.0.8   | 2026-10-31 | `feature/follows-feed`                  | `1f81f45` and later |
| 0.0.7   | 2026-10-31 | `feature/community-groups`              | `9f19c55` and later |
| 0.0.6   | 2026-10-30 | `feature/team-videos`                   | `d623748` and later |
| 0.0.5   | 2026-10-30 | `feature/team-meetings`                 | `1b2e424` and later |
| 0.0.4   | 2026-10-29 | `feature/ultiup-schedule`               | `06830cc` and later |
| 0.0.3   | 2026-10-29 | `feature/roster-import`                 | `5620a1d`           |
| 0.0.2   | 2026-10-29 | `feature/stats-mockup`                  | `7556460`           |
| 0.0.1   | 2026-10-28 | `feature/team-calendar-animated-plays`  | `fd59d92`           |
| 0.0.0   | 2026-10-28 | `development` (MVP baseline)            | `090e7b4`–`04d4109` |

## 0.0.52 — Confirm it's you before setting up payouts

- Set up payments / Bank account and payouts: when the API wants a recent
  sign-in (`payoutsReauthMessage`, 412), the screen asks for the
  password, Google or Apple, gets a fresh ID token, and opens Stripe's
  form. Same on the website (`ConfirmSignIn`). Test: the app's message
  matches packages/shared.
- "Set up payouts" (was "Set up payments"), with `payoutsSetupNote` above
  Stripe's form: Stall 10 pays hosts through Stripe and never sees their
  details.

## 0.0.51 — Stall 10 collects fees and pays hosts out

With web 0.59.0 and API 0.47.0. Firestore rules changed (payments,
events' `finishedAt` and deletes); no functions changes.

- Payment sheet: PaymentIntents are on Stall 10's account, so
  `PaymentSheetRequest.account` is null and `Stripe.stripeAccountId` is
  cleared; the merchant shown is Stall 10.
- `PaymentRepository.refund` and `.earnings` (`Earnings`, `EarningsItem`,
  `EarningsStatus`); `EntryPayment.paidOnline` (note `paidOnlineNote`).
- `RefundButton` (asks first, `refundPolicyNote`) replaces the paid switch
  for fees paid online, on the event's Teams tab
  (`HostedTournamentViewModel.refund`) and hat signups
  (`PlayerSignupsViewModel.refund`).
- Payouts card: new wording, held/sent/refunded/owed totals, and **Bank
  account and payouts** (`PayoutsSetupScreen(manage: true)`, the
  website's `/embed/payouts?view=manage`).
- Payouts card: **Each fee** (`Earnings.items`). Payouts are sent a few
  days after the event (`payoutTimingNote`).
- `PayoutsSetupScreen` only loads the website's `/embed/payouts` at the
  top (a `NavigationDelegate`), and hands Stripe's session over only to
  that page.
- Firestore rules: clients can't set `finishedAt` on an event, and only
  drafts are deleted directly (others through the API). Registration
  opens at most 60 days before the start (rules and API).
- Event form: Publish waits until registration can open, 60 days before
  the start (`registrationWindowProblem`, `publishProblem`); Save draft
  still works.
- Payouts card: says Stall 10 checks a host's first payout, and an
  event's payouts once they pass $2,000 (`payoutReviewNote`).

## 0.0.50 — Tournament flow: respond, deadline, seeds, director

With web 0.58.0 and API 0.46.0. Firestore rules and functions changed.

- **Respond flow** (`/tournaments/:id/respond?team=&step=`,
  `RespondViewModel` + `RespondScreen`): Respond (Accept/Decline or
  Apply, with team, division and captains) → Roster (or set later) →
  Payment (`PayOnlineButton`, or pay later) → **Request confirmed!** /
  **Request sent!** with the checklist. Replaces `EnterTeamScreen` and
  `showApplyDialog`. Accepting an invite puts the team straight in.
- Team page: one **Respond** button per invite, and **Entries to
  finish** (`TeamTournamentBusiness.toFinish`) with **Finish entry**.
  The event page's card has **Respond**, **Roster & fee** and
  **Captains**.
- Organizers: the guide's host steps confirm each division's seeds
  (`confirmSeeds`) and publish every schedule at once (`publishAll`,
  `PUT /schedule`); the Teams tab has **Confirm seeds** and **Roster
  missing** flags, and the registration step counts teams missing a
  roster or fee. Overdue uses the entry deadline (`effectiveDeadline`).
- Event form: **Fees & deadline** (`entryDeadline`, which the fee's due
  date follows, with the host's payments card) and a **Director** step
  (`TournamentDirector`: a member found by name, or anyone by name,
  email and phone). The event page shows a director card.
- Payments: `PayoutsCard` shows **Payments: On / Finish setup / Not set
  up**, tells non-owners who sets it up, and runs Stripe's onboarding in
  the app (`PayoutsSetupScreen`, a WebView of the website's
  `/embed/payouts`; `webview_flutter` 4.14.1). Team settings show it to
  anyone who manages events.
- A new paid hat signup goes on to Payment, then **You're signed up!**
  (`signUpWithNextSteps`).
- Writes the API also takes go through it while `use_api_tournaments`
  (meta/flags, default on) is on: status, entries, seeds, publishing,
  delete. Event saves, scores, signups and drafts still write Firestore.
- Rules: `entryDeadline`, `director` (`validDirector`),
  `seedsConfirmedAt`, entries' `roster`, `rosterSetAt` and `reason`.
- Functions: `tournamentInvite` (push to a team's admins when invited),
  `tournamentScheduled`, `tournamentFinal`, `entryDeadlineReminders`
  (hourly: 3 days before and when it passes) and `tournamentDeleted`
  (deletes the event's chats).
- `firebase/scripts/set-staff.mjs --host <orgId>` lets staff host as the
  official Stall 10 organization (badge **Stall 10 verified**).
- Shared fixtures: `entry_checklist` (deadline, deadline check,
  checklist).

## 0.0.49 — Tournament invites: reply-by time, team page answers

With web 0.57.0 and API 0.45.0. Firestore rules changed.

- Hosts pick when invited teams must answer by (**Invited teams answer
  by**: 3 days, 1, 2, 3 weeks or 30 days before it starts, or no
  deadline; new events default to 2 weeks). `tournaments/{id}` gains
  `inviteReplyDays` (null or one of 3/7/14/21/30, checked in
  `validHosted`).
- An invite's entry stores `replyBy` (the start less those days, at least
  2 days after the invite, never after the start) and `teamId`. Past
  `replyBy` the invite has expired: the rules (`inviteOpen()` in
  `teamApplies`) and the API (`putEntry`) refuse accepting it, both sides
  see **Expired**, and the host's **Invite again** sets a fresh time.
  Shared logic: `inviteReplyBy` / `inviteExpired` in
  `packages/shared/src/tournaments.ts`, the Dart copy on
  `HostedTournament`, cross-checked by `fixtures/invite_reply`.
- Team page: a team's admins see its open tournament invites with
  **Accept** (opens the event to pick captains) and **Decline** (the team
  withdraws), from `GET /v1/teams/:id/tournament-invites` (the team's
  `tournamentEntries` records, no new index).
- The event page shows the invite's reply-by time on your team's card.
- **Pay online** opens Stripe's payment sheet in the app (flutter_stripe
  14.2.0) instead of Checkout in the browser: a PaymentIntent on the
  host's account from `POST /v1/tournaments/:id/pay/intent`. Needs
  `STRIPE_PUBLISHABLE_KEY` in the secrets file; without it the browser
  checkout stays. Android's `MainActivity` is a `FlutterFragmentActivity`
  with AppCompat themes and Stripe's R8 rules (`proguard-rules.pro`);
  Stripe's return link `stall10://open/safepay` is kept from the router
  (`onEnter`). `data/services/payment_sheet_service.dart`.
- Fees: Stall 10's fee is 3% of the fee (was 1% + $1), and payers always
  pay it and Stripe's card fee on top, so hosts get the whole fee
  (`onlineCharge`; the Dart `PaymentFees.chargeCoveringFees` /
  `platformOn`). The host form's "Teams cover the processing fee" switch
  is gone; `payerCoversFees` is ignored.

## 0.0.48 — Security fixes

With web 0.56.1 and API 0.44.0. Firestore and Storage rules changed.

- Chats: the reactions bubble opens under a message near the top of the
  screen, so the title bar never covers it.
- Pinned messages are their own page, from a room's ⋯ (as in Discord):
  a card for each pin with its author, date, text and files. Tap one to
  jump to it in the chat, loading older messages as needed; it's tinted
  for a moment. The pinned strip at the top of the room is gone.
- Learn to play and the rules of ultimate are one page: the lessons (now
  in one card, divided), then the rules, each opening in place, with the
  official rule books. Settings and Help have one "Learn to play";
  `/rules` opens the rules part.
- Your email is never shown as your name: someone without a name
  appears as "Player" on teams, chats, posts and follows (pentest P6).
- Rules: private profiles' posts can't be listed by people who don't
  follow them, at most 50 a query (P1); uploads must be a photo, video
  or document type, never SVG, HTML or untyped (P3); `users/{uid}`
  takes only the fields the app writes (P10).

## 0.0.47 — Communities without a level, league entry, fee shares, mentions

With web 0.56.0 and API 0.43.0. Functions `notifications` changed.

- Pickup communities and schools/clubs have no division or level
  (`Team.hasDivision`; maps leave them out, `sameAs` ignores them; rules'
  `validTeamFields` let groups omit them). A team made inside a school or
  club picks its own level (`community-team-level`, college by default).
  `firebase/scripts/backfill-group-divisions.mjs` cleared them on dev.
- Hosted events: **Who can enter** is `EntryChoice` (teams, players, both;
  `entryChoices` in shared, fixtures `entry_choices/choices.json`).
  Leagues offer all three; tournaments two plus "Teams can also reserve a
  spot". Players in "Teams and players" are drafted onto new teams.
- Split a team fee (`TeamShareCard`, `TeamShareRepositoryApi`,
  `/v1/teams/:id/share`): whoever manages the team sets each member's
  share and how to pay the collector, then marks people paid. Stored in
  `teams/{id}/private/share` (server only). No money goes through Stall 10.
- Team chat rooms: press and hold (or ⋯) for **Mute notifications**;
  muted rooms show a bell-off icon and no unread dot. Rooms drag only with
  a mouse now, since press and hold opens the menu.
- Chats: **Team chats** and **Direct messages** fold away
  (`InboxViewModel.toggleSection`), kept until the app restarts.
- @mentions (`domain/models/mentions.dart`, `mentions.ts`, fixtures
  `mentions/cases.json`): the composer suggests @everyone and roles (the
  owner, coaches, captains, chat managers) and members; messages draw
  mentions, the reader's brighter. The `chatMessage` trigger reads them
  from the text: mentioned readers get "#room · Team / Cam mentioned you:
  …" instead of the room's notice, through a room mute for a personal
  or role mention (@everyone respects it). Its feed entry
  (`mention_{team}_{room}`, `mention: true`) is `ChatRepository
  .watchMentions`; `TeamChatSummary` shows it as the row's subtitle and
  counts the room unread until it's read (fixture cases in
  `team_chats/summary.json`).
- Settings → **Help** (`Routes.settingsHelp`, `HelpScreen`) and **Rules of
  ultimate** (`Routes.rules`, `RulesScreen`), from
  `domain/models/guides.dart` (`helpTopics`, `rulesGuide`,
  `officialRules`), the same words as `guides.ts` (fixtures
  `guides/guides.json`). The rules guide is our own summary; it links the
  official USA Ultimate and WFDF rules and copies none of their text.

## 0.0.46 — Agree to the guidelines, Chats, composer header

With web 0.55.0 and API 0.42.0.

- **Before you start** (`AgreementRepository`, `AgreeTermsScreen`,
  `Routes.agreeTerms`): the router sends every member who hasn't agreed
  to the current `termsVersion` (`domain/models/agreement.dart`, fixtures
  in `packages/shared/fixtures/agreements`) there after the username
  step and before personal details. Unknown (no API, offline) holds
  nobody up.
- Settings → Legal and your data: Community Guidelines instead of the
  Cookie Policy (`LegalLinks.guidelines`); the app sets no cookies.
- Composer: header (avatar → `Routes.profile`, name, "Posting to" and the
  audience chip), body, footer with **Send**. The hint goes round
  `postPrompts` (`domain/models/post_prompts.dart`, fixtures in
  `packages/shared/fixtures/post_prompts`).
- The Inbox tab is **Chats**.
- Messages are no longer listed in Notifications or counted on the bell
  (`NotificationCategory.isMessages`); they're in Chats. Their feed
  entries are still written (functions unchanged), because the in-app
  bubble for a new message reads them.
- Mute hides the bubble: the Chats badge (`ShellViewModel`), the list's
  unread count and dots leave out muted conversations, and
  `TeamChatActivity.muted` / `TeamChatSummary.fromReadable(muted:)` muted
  rooms (fixture case in `team_chats/summary.json`).
- Notifications open with `openFromNotifications`: back goes to the page
  it belongs under (a team chat to its team, a conversation to Chats);
  people and follow requests still come back to the list.
- Profile → Posts: New post, Log a workout and Record are small action
  chips (`RecordWorkoutButton(chip:)`), with space before the posts and
  between them.

## 0.0.45 — Captains' channel, tournament tags

With web 0.54.0 and API 0.41.0.

- Tournament chats with the organizers (`TournamentChatRepository`,
  `OrganizerChatsCard`, `HostedTournamentViewModel.openChat`,
  `myChatEntries`, `offersChats`): the Captains' channel and each team's
  private thread, opened through the API and shown in Messages.
  Organizers message a team from its row on the Teams tab.
  `Conversation.tournamentId` / `isTournamentChat` (kind `tournament`):
  a group with no Add people, Rename or Leave, and an Open tournament
  item.
- Functions: `tournaments-chatMembers` keeps the chats' people in step
  when an entry's status or captains change (`chat_members.ts`, the port
  of the API's rule); `notifications` title a tournament chat's message
  with the chat's name, like a group's.
- Rules: no change in behaviour; kind `tournament` conversations aren't
  `groupDoc()`, so clients can't add, remove, rename or create them.
  Tests in firestore.rules.test.ts.
- "At a tournament" (`UserPostRepository.tagTournaments`, both composer
  view models): followed tournaments from a week before they start to
  their last day (`tournamentTagOpen` in follow.dart, fixtures in
  `packages/shared/fixtures/tournament_tags`); a build without the API
  offers every follow.
- The "At …" line on a post opens the tournament
  (`FollowTarget.parseTournamentKey`, `Routes.tournament(id, host:)`).

## 0.0.44 — Pay tournament fees online

- Online payments for tournament and league fees through the API
  (api 0.40.0; Stripe Connect). `PaymentRepository` /
  `PaymentRepositoryApi` (no API client: off), `PayoutsViewModel`,
  `PayOnlineViewModel`, `ui/payments/widgets/payment_widgets.dart`.
- The event page shows the host's owner a "Take payments online" card
  (`PayoutsCard`, hidden for everyone else and while payments are off),
  and each of your teams that still owes its bid or spot fee gets a card
  with the host's instructions and "Pay $400 online"
  (`PayOnlineButton`). A signed-up player's card gets the same button
  for their entry fee.
- Stripe's pages open in the browser (`LaunchMode.externalApplication`);
  coming back to the app reloads the card and button. The payment record
  the host marks by hand is the one Stripe marks, so the paid state
  updates live as before.
- Hosts see what reaches them of a fee paid online: under the price in
  the event form (`FeeBreakdownNote`, from `GET /v1/payments/fees`) and on
  the payout card for the event's own fee (Stall 10's fee plus Stripe's
  estimated 2.9% + 30¢). The fee section no longer says teams always pay
  the host directly. Built as 0.0.27 on `feature/payments`, renumbered on
  merging `development`.
- "Teams cover the processing fee" switch in the fee step
  (`BidFee.payerCoversFees`, allowed by `validBidFee` in the rules); the
  note shows what payers pay. `PayOptions` gains `chargeCents`,
  `processingCents` and `processing`; the Pay button shows the total and
  the processing fee.
- `PayOnlineViewModel.checking`: back from Stripe, the button gives way to
  "Checking your payment…" until the reload (which asks Stripe) answers.
  A clearing bank payment shows "Your bank payment is processing…".
- "We'll pay another way" (`PayOnlineViewModel.payOffline`, through
  `PUT /v1/tournaments/:id/pay/offline`), with Undo; `EntryPayment.offlineAt`
  and `paymentStatusLabel` ("Paying another way") on the host's lists.
- Payment notes: a note button beside each paid switch
  (`setPaymentNote` on `HostedTournamentViewModel` and
  `PlayerSignupsViewModel`, `editPaymentNote`). With the API there, marks
  and notes go through `PUT /v1/tournaments/:id/payments/:payerId` (so
  they're in the payment history), shown at once and undone on failure;
  without it, straight to Firestore as before.
- With online payments on, the form's "How to pay" reads "Other ways to
  pay" (`PaymentsOnBuilder`).

## 0.0.43 — Repeating events, month week, Directions apps

With web 0.52.0 and API 0.39.0 (product-spec §8.1 items 30, 60–61).

- Repeating events (`domain/models/recurrence.dart`, the port of
  packages/shared's `recurrence.ts`, tested against
  `packages/shared/fixtures/recurrence/`): a new event has **Repeat**
  (daily, weekly on its day, every 2 weeks, monthly on its date) until an
  end date, at most 100 events and a year, with a live "Creates N events".
  Each occurrence is its own event (ids `${seriesId}_${index}`, `series`
  on each), so RSVPs, reminders and calendar feeds work as before. Team
  and My calendar series are written in one Firestore batch; shared
  calendars through the API with the device's time zone
  (`flutter_timezone`, `data/services/time_zone.dart`).
- Editing or deleting an event in a series (editor, event pages, the
  schedule's swipe) asks **this event** or **this and following events**
  (`askSeriesScope`); "following" moves later ones by the same change of
  date and time and keeps their RSVPs. Rows show a repeat mark; details
  say "Repeats weekly until …".
- Rules: `series` on team and personal events, `seriesWrite` on team
  event edits (`validSeries`, `validSeriesWrite`). `teamEvent`
  notifications: one per new series ("repeats weekly until …") and one
  per "this and following" edit or delete (`isQuietSeriesWrite`).
- Schedule, Month: the picked day's whole week is listed below the grid,
  scrolled to that day, with its row tinted (`weekOf`).
- Schedule's Calendars card: compact, one **Manage** button.
- **Directions** (event pages, a group's map) asks which app: Apple Maps
  on iPhone, Google Maps or Waze (`domain/models/directions.dart`, tested
  against `packages/shared/fixtures/directions/`). Each link opens the app
  when installed, the browser otherwise.

## 0.0.42 — Word filter and photo checks

With web 0.51.0 and API 0.38.0 (product-spec §8.1 items 57–58).

- Word filter in the app (`domain/models/word_filter.dart`, the same
  lists and rules as `packages/shared` `word_filter.ts`, both tested
  against `packages/shared/fixtures/word_filter/`). Repositories that
  write to Firestore directly run text through it first: posts and
  reposts, comments, direct messages and group names, team chat, rooms
  and folders, team posts, events, meetings and their chat, RSVP notes,
  profile details, names and teams. A blocked word fails with
  `BlockedWordsException` (its message is the guidelines one); swearing
  is saved masked.
- Photos uploaded through the API are checked by SafeSearch there.
- Functions (`api` group): `*TextFilter` triggers mask or delete text from
  older builds that skip the filter, `photoCheck` deletes unsafe photos
  they put in Storage directly, and notification previews are masked
  (nothing is sent for blocked text).
- Community guidelines (`firebase/hosting/guidelines.html`): "Words and
  photos we filter".
- Calendars: one **Subscribe** button instead of three. Its sheet lists
  the calendar apps for this device (`subscribeOptions` in
  `domain/models/calendar.dart`, the same as packages/shared's): Apple
  Calendar on iPhone, Google first on Android, Outlook (personal, and
  work or school, which now open Outlook's own subscribe page), another
  webcal app when Android has one, and Copy link. On Android, an
  installed Outlook goes first (`<queries>` for `ms-outlook` and
  `webcal`). The footer says how often each app checks the link.
- Reminders for shared calendars (`notifications` functions,
  `eventReminders`): the day before, everyone on the calendar gets
  "Tomorrow: …" with the calendar's name; it opens Schedule. Invites not
  yet accepted don't.

## 0.0.41 — Report and block

With web 0.50.0 and API 0.37.0 (product-spec §8.1 items 51–56). Reports
and blocks go through the API only (`ModerationRepositoryApi`); a build
without `API_BASE_URL` says they aren't available in this version.

- Report sheet (`ui/moderation/widgets/report_sheet.dart`,
  `ReportViewModel`): reasons from `reportReasons` in packages/shared,
  details, "Also block". On posts (⋯), comments, team posts (⋯) and their
  comments, team chat and direct messages (long-press), and profiles (⋯)
  and direct conversations (header menu).
- Block and unblock from profiles and direct conversations; the block
  list is live from `users/{uid}/blocks` (`ModerationRepository.current`).
  Posts and reposts, comments, message requests and group messages from
  people blocked either way are hidden; a blocked profile shows only the
  name; a blocked conversation shows "You blocked …" with Unblock in
  place of the composer. Team chat and team posts stay (shared teams).
- Settings › Blocked accounts; Team settings › Safety › Reports for the
  owner, admins and members who may moderate (`TeamReportsScreen`).
- "Stall 10 staff" badge on staff members' profiles, from `staff/{uid}`
  (read-only in `firestore.rules`; written by
  `firebase/scripts/set-staff.mjs` with the `staff` claim).
- The "need a connection to Stall 10" messages (calendars, pins, live
  scores, video notes, personal details) now say the feature isn't
  available in this version of the app (a build without the API address).

## 0.0.40 — Schedule: typed times, sharing, calendars on the tab

With web 0.49.0 (product-spec §8.1 items 47–50). No API change.

- Time pickers open in input mode with the hour focused
  (`core/ui/time_picker.dart`, `showTypedTimePicker`; Flutter only
  autofocuses after a mode switch); the clock icon switches to the dial.
  Every picker in the app uses it.
- Event editor: "New shared calendar" in Add to (new events) makes a
  calendar on the spot (name, color, Can view / Can edit, people to
  invite) and puts the event on it (`EventEditorViewModel.createCalendar`,
  `new_shared_calendar_sheet.dart`).
- Share beside Add to calendar on every event: the share sheet with the
  .ics and "Title · when · where" (`shareCalendarEvent`).
- Schedule tab: Calendars button in the header and a Calendars card under
  the days (each calendar, Manage, Share a calendar, Outlook/Apple/Google),
  as the website's.
- Creating a club team without the API (a build with no `API_BASE_URL`)
  now says club teams need the server (it checks ages) instead of "You
  don't have permission": firestore.rules refuses club teams from
  clients. There is no one-team-per-level limit.

## 0.0.39 — Double-tap reactions; RSVP buttons fixed

With web 0.48.0 and API 0.36.0 (product-spec §8.1 item 45).

- Chat: double-tap a message (pointer events in `_Pressable`, not a
  double-tap recognizer, so taps inside messages aren't delayed) for a
  bubble of quick reactions above it (`reaction_bubble.dart`) with a +
  that opens every emoji by group; the long-press sheet has the + too.
  `quickReactions`, `reactionGroups` and `isChatReaction` in
  `domain/models/chat.dart`; shared vectors in
  `packages/shared/fixtures/chat_reactions/choices.json`. The website's
  quick reactions are now the app's (it offered a different set, and the
  API refused three of the app's).
- RSVP: Going / Maybe / Can't go switched off while a save ran and
  nothing redrew them after, so a second answer needed the event
  reopened. The event, meeting and community cards now rebuild on the
  command. The choices are separate outlined buttons (filled when
  chosen) instead of a segmented track.

## 0.0.38 — Redesign features, second batch (redesign 4)

With web 0.47.0 and API 0.35.0. Details and tests per feature in
`docs/product-spec.md` §8.1 items 35–44; open questions in
`docs/redesign-plan.md` ("Waiting for you" 12–37). Needs the dev deploy
of Firestore rules + indexes (done), the API, and functions groups
`notifications`, `follows`, `communities`, `account`, `browse`.

- Tournament extras (F30): standalone bracket page
  (`/tournaments/:id/bracket/:divisionId`), −/+ score steppers, league
  week stepper (`league_weeks.dart`, shared `league_weeks.ts`),
  full-screen Enter a team, host form in steps with Save draft /
  Publish, Share on tournament pages.
- Team videos (F4–F6): notes pinned to a moment and clips, a comment
  thread (push to the video's author), tag a video to a team event
  (`teams/{t}/videos/{v}/comments`, `eventId`; API-only writes).
- Teams tab always opens the list, even with one team (F34; reverses
  the 0.0.36 shortcut, `TeamsTabTap` removed).
- Add to calendar opens the phone's own new-event screen
  (`add_2_calendar` 3.0.1, `DeviceCalendarService`); .ics share only as a
  fallback. Info.plist: `NSCalendarsUsageDescription`,
  `NSContactsUsageDescription`; Android `<queries>` for INSERT (F35).
- Team page: "N going" / "N new in chat" tiles (F18); roster roles,
  O-line / D-line groups and Edit lines (roster spot `line`, API-only),
  Invites pending with Withdraw (F23); More rows with subtitles, Manage
  team and Leave (F28).
- Chat polls in team rooms (F33): question, 2–6 options, multiple
  answers, closing time; vote, see votes, close (`poll` on the message,
  API-only).
- Team feed (F24): pin up to 3 posts, comments on team posts with
  counts (`teams/{t}/posts/{p}/comments`, `commentCount` kept by the
  `follows` group), "Post to the team…" box replaces New post. F8
  audience picker verified (Everyone or a team you manage).
- Roles (F25): presets (Member, Stat keeper, Captain, Coach, Admin;
  groups Moderator, Organizer) and per-person permission switches
  (`memberGrants`, owner only, API-only; `memberPerms` includes them).
- Team join requests (F26): "Allow join requests" (off by default),
  Request to join, approve/decline in Members, club age rule checked at
  request and approval, push "You're in".
- Discord import: pick which text channels to bring (F15).
- Community page (F27): Next pickup card with RSVP, Chat rooms with
  unread dots, Organizers with Message.

## 0.0.37 — Redesign features, first batch (redesign 4)

With web 0.46.0 and API 0.34.0. Details and tests per feature in
`docs/product-spec.md` §8.1 items 26–34. Needs the dev deploy of
Firestore + Storage rules, the API, and functions groups
`notifications`, `browse`, `tournaments`, `account`.

- Live running scores (F1): captains and event managers keep a game's
  running score ("Live score" sheet: Start game, +1, undo, Report/Set
  final, Stop live score). LIVE pill and score on games, the navy
  header, the tournament-day card and Discover's "Live now". Data
  `games/{id}.live`, API-only.
- New teams start simple (F21): Playbook, Videos, Stats and Meetings
  start off (`sections` on the team; missing reads as on); Settings ›
  Sections; a hint for a new team's owner.
- Playbook whiteboard (F31): Plays | Whiteboard switch; sketch with pen,
  players, disc and cones; save as a play or a whiteboard
  (`kind: "whiteboard"`, `drawings`). Plays keep pen strokes.
- Note on an RSVP (F7): up to 140 characters on event and meeting
  answers (`rsvpNotes`), shown in Responses / Invited; rules
  `validRsvpNote`; account deletion removes them.
- Schedule month view (F16): Week / Month switch with day dots.
- Meetings list (F17): Upcoming / Past, Live now, Needs RSVP;
  `/team-meetings/:teamId` now opens it.
- Team rooms (F2, F3): pinned messages (up to 10 a room, "Pinned"
  strip) and event cards shared into chat with RSVP buttons. API-only.
- Public team page switch (F12): Settings › Visibility; off, outsiders
  see only the team's card. Team Settings now open to admins (Sections
  stay the owner's).
- Download your data (F14): Settings › Account › Your data
  (`GET /v1/me/export`, once per 10 minutes), via the share sheet.
- Learn progress (F9): "N of 12 read", kept on the device.
- Spots left (F10): "N spots left" / "Full · waitlist" on tournament
  and league cards while registration is open.
- Discover lists public team events and pickup games (F29), as the
  website does.

## 0.0.36 — Navigation and every screen restyled (redesign 2–3)

Web navigation changes land in the web 0.45.0 commit that follows. No
API, rules or data changes.

- Navigation (redesign 2): tabs Home, Discover, Schedule, Teams, Inbox.
  Discover merges Explore and Find events (`/discover`,
  `/schedule?view=find` redirect to `/explore`; chips All, Tournaments,
  Leagues, Pickup, Teams, Communities, Players). The Teams tab opens
  your team straight away when you have exactly one and no invite. Feed
  tabs Your teams / Following / Everyone. `events_tabs.dart` removed.
- Every area restyled in the Turf & Disc look (redesign 3a–3i):
  tournaments and leagues (navy live header, live days open on
  Schedule, amber "your game needs a score", "Next steps"), teams and
  communities (compact team header, initials badges, Teams list rows,
  invitations in amber), schedule, events and meetings (RSVP segmented
  control with counts, "Needs RSVP", summary cards), Inbox and chat
  (Team chats above Direct messages, turf own bubbles, room access
  segmented control), Home, Discover, profiles, posts and notifications,
  sign-in and settings (grouped settings cards, Light/Dark/System
  control), playbook and videos (category grids, tool tiles, step
  timeline, video rows), hat tournaments, drafts and stats.
- Colour rules applied: no red Delete/Leave (destructive confirms are
  solid ink), red only for live games, amber only for what's yours to
  do. Event-type colours are turf (field time) or neutral. Play
  diagrams: defence navy instead of red.
- Shared: `TeamBadge(name:)` draws initials; `TeamInitials`; switch
  theme; new area parts (`tournament_parts.dart`, `hat_parts.dart`,
  `rsvp_widgets.dart`, `settings_widgets.dart` additions).
- Fixes: the sign-up details intro no longer mentions USA Ultimate;
  leaving Record workout no longer notifies the recorder mid-teardown;
  text styles with no font in the profile dropdowns and "Follow back".
- Temporary screenshot tests in `test/screenshots/` (skipped unless
  `--dart-define=SCREENSHOTS=<dir>`).

## 0.0.35 — "Turf & Disc" redesign foundation (redesign 1)

App only; no API, rules or data changes. Plan: `docs/redesign-plan.md`.

- New palette in `AppColors` (light and dark): turf green actions,
  scoreboard navy for live/today, disc amber only for what is yours to
  do, red only for live games. Existing token names kept; new tokens
  `border2`, `ink2`, `accentInk`, `highlightSoft`, `highlightInk`, `live`,
  `liveSoft`, `liveInk`, `chipOn`, `onChipOn`, `badge`.
- Barlow Condensed (OFL) bundled for scores, big numbers, date badges
  and the italic "STALL 10" wordmark (`scoreFont`).
- Radii 16 (cards) / 12 (controls); outlined filter chips, navy when
  selected; turf tab underline; amber unread badges; turf "See all".
- New shared widgets in `ui/core/ui/scoreboard.dart`: `ScoreText`,
  `LiveDot`, `LivePill`, `NeedsYouPill`, `TeamDot`, `SectionHeader`,
  `ScoreLine`, `BoardLabel`.
- Sign-in artwork recoloured; screenshot harness takes
  `--dart-define=SHOT_THEME=dark`.

## 0.0.34 — Tournaments tab when one is ahead (team-first 3)

Web 0.44.0. No API or rules changes.

- A team's page shows **Tournaments** as a tab of its own, after Chat,
  while the team has a tournament ahead; More no longer lists it then.
  Otherwise it stays under More. Members only (they're the ones who read
  `teams/{id}/tournamentEntries`); communities are unchanged.
- One rule: `hasTournamentAhead` (`domain/tournament_engine/tournament_day.dart`),
  ported to `@stall10/shared`, vectors `fixtures/tournament_day/ahead.json`:
  an entry still in play (accepted, invited, applied, waitlisted) whose
  last day is no earlier than yesterday.
- `TeamTab.tournaments`; `TeamHomeViewModel.tournamentsTab` watches the
  team's entered tournaments.
- The team's Tournaments section starts with its tournament-day card when
  it has one.

## 0.0.33 — Tournament-day card (team-first 2)

Web 0.43.0. No API, rules or function changes: hosted divisions, entries
and games are already readable by signed-in users once the event isn't a
draft, and `teams/{id}/tournamentEntries` by the team's members.

- On a tournament day, Home and the team page show a card in place of
  the next event: the tournament (Live when it is), the team's next game
  (opponent, time, field; "Tomorrow" from 17:00 the evening before), its
  record and pool place, and its last result. Home shows one per team;
  the team page its own.
- Captains get **Report score** (or **Confirm score**) on the card for
  the earliest of the team's games that has started without a score, or
  that the other captain reported. It opens the tournament page on
  Schedule with that game's sheet up, so the existing score dialog and
  its checks do the rest. **Schedule & standings** opens the Schedule tab.
- One rule: `TournamentDay.of` (`domain/tournament_engine/tournament_day.dart`),
  ported as `tournamentDay` in `@stall10/shared`, vectors
  `fixtures/tournament_day/day.json`. Pool place shows once the team has
  a pool result (before that it's only the seed). Between pool play and
  the bracket the card says **Next game to be decided** while an empty
  bracket slot comes from the team (`awaiting`: its pool rank, or the
  winner/loser of a game it played), and **All games played** once it's
  out. A next game on another day shows the day ("Tomorrow 9:00 AM",
  "Sun 9:00 AM").
- `TournamentDays` (`data/repositories/hosted_tournament`) gathers the
  data: each team's (not communities') accepted entries from two days
  before the event to the day after it ends (event dates are the host's
  local midnight, which can be a day off elsewhere; the games' own times
  decide), then the tournament, entries, divisions and the team's
  division's games, re-checked each minute while something is on. Used
  by `HomeViewModel` and `TeamHomeViewModel` (optional
  `tournamentRepository`).
- `Routes.tournament(id, division:, game:, tab:)`: `?game=` opens the
  game's sheet once its division's games load; `?tab=schedule|results`
  picks the tab.
- Rules test "an entered team's players read an invite-only event's
  games": a private group's invite-only event is readable by the
  players of a team it accepted (reads only need the event published).
- Tests: `test/ui/tournament_day_test.dart`,
  `test/shared_fixtures/tournament_day_fixtures_test.dart`;
  `seedLiveTournament` in `test/testing/hosted_tournament_fakes.dart`
  (also used by the screenshot harness).

## 0.0.32 — Team chats in Messages (team-first 1)

Web 0.42.0, api 0.33.0. Rules change (deploy to dev; done).

- Messages lists every team and community chat above direct messages
  (`TeamChatActivity` in `data/repositories/chat`, used by
  `InboxViewModel` and `ShellViewModel`), unread first: which rooms have
  new messages ("New in #general"), when the newest was sent, and an
  unread dot. A tap opens the only unread room, else the newest. The
  Unread filter and search include them; the Messages badge counts teams
  with unread chat. This reverses the spec's "team chats live on team
  pages" (§8.1 item 3).
- `ChatRoom.lastAt`: when the room's last message was sent, stamped by
  the sender in the same batch as the message (`_send`; the API's
  `sendMessage` in its transaction). Only a time, never the text: chat
  managers read rooms' docs even when they can't read the messages.
  Rooms only get it from their next message.
- Read times are private, `users/{uid}/chatReads/{teamId}`
  (`rooms.{roomId}`): `watchReads` / `markRead`. A sender's own message
  counts as read; an open room is marked read as messages arrive
  (`ChatRoomViewModel`). The team's room list shows unread rooms bold
  with a dot. Account deletion already removes `users/{uid}`.
- One rule for the inbox row: `TeamChatSummary.fromReadable`, ported as
  `teamChatSummary` in `@stall10/shared`, vectors
  `fixtures/team_chats/summary.json`.
- Rules: anyone who can post in a room may set only `lastAt`, and only to
  `request.time`; `chatReads` docs are their owner's, `rooms` a map of at
  most 300.
- Fix: Home's "Complete your details" card no longer notifies after it's
  disposed (leaving Home before its preference loaded threw).
- `test/screenshots/screens_test.dart`: phone screenshots of the main
  screens on fake data, skipped unless
  `--dart-define=SCREENSHOTS=<dir>` is passed.
- Tests: `data/chat_reads_test`, `ui/messages_test` (team chats),
  `ui/chat_test` (marking read, room dots),
  `shared_fixtures/team_chats_fixtures_test`; rules "stamps its lastAt",
  "chat read times"; API `hub` (stamp, `PUT .../read`).

## 0.0.31 — Stats per team on profiles

Web 0.41.0, api 0.32.0. Rules change (deploy to dev).

- `ProfileSummary.teamSeasons` (team id → season → totals), built in
  `PlayerProfileViewModel._recompute` beside `seasons` and published as
  `teamStats` (in `_summaryFields` and `PlayerProfile.privateFields`, so
  it moves with a private profile). It says which teams someone plays
  on, so it's published only with both stats and teams shown;
  `saveVisibility` deletes it when either is hidden (deleted rather than
  `{}`, since a merge keeps an old map's entries). `sameAs` compares it,
  so existing profiles republish with it.
- `ProfileStatsChoice`: the profile's **Team** filter beside the season
  menu, offering the published teams that have stats (two or more);
  it narrows By the numbers, the season list and Season by season.
  Recent games stay unfiltered. Ported as `profileStatsChoice` in
  `@stall10/shared` and checked on `fixtures/profile_stats/choice.json`.
- Rules: `profiles/{uid}` and `private/details` accept `teamStats`, a
  map of at most 50 teams.
- `firebase/functions/src/browse/model.ts` gets the API's `profileView`
  change (the copies are checked to match); the old browse callables
  aren't redeployed for it.
- The profile's team tag for a pickup community says **Pickup** (was
  Group), as does the website's sidebar.
- Tests: `player_profile_test` (filter, publish, round trip, hiding
  teams), `profile_api_test` (writes, hide, private move),
  `shared_fixtures/profile_stats_fixtures_test`; rules "per-team stats";
  API `profiles` and `browse.model`.

## 0.0.30 — Wording, QR invites, message times (UI review release 1)

The first of the UI review's releases (web 0.40.0, api 0.31.1). No data,
rules or function changes.

- One name for communities in every user-facing string: `TeamKind.community`
  is labelled **Pickup community** (was "Community group") and its noun
  is "community" (was "group"), so a pickup community and a school or club
  both read as "community" in sentences. Group messages (group DMs) keep
  "group". Explore's filter chip is **Communities** (the `groups` filter
  and `?only=groups` keep their names). The shared `teamKindLabels`
  (name-taken message) and the website's `kindLabels` match.
- Stats wording: **Track a tournament** (was New tournament), **Track
  stats** on the Stats tab's button (was Game / tournament), the list is
  **Tournament stats**. The data is still `statsTournaments`; only labels
  changed, so "tournament" in Stats no longer reads like a hosted one.
- Invite dialog: a **QR code** button beside Copy opens
  `InviteQrDialog` (`qr_flutter`), the invite link dark on white for a
  phone camera. The website has the same button (`qrcode`).
- A message's long-press sheet shows when it was sent, so times aren't
  only behind the drag-left gesture.
- `docs/user-guide.md` rewritten for the five tabs, the team hub, the
  community names, QR invites and stats wording.
- Tests: `invites_test` (QR code), `messages_test` (time in the sheet),
  and the renamed strings in `stats_*`, `explore`, `groups`,
  `host_event` and `group_tournaments` tests.

## 0.0.29 — Private profiles' posts stay private (S1)

Security review S1: the database rules let anyone signed in read a
private profile's posts, comments and photos; only the app hid them.

- Every person's post carries `private` (`UserPost.isPrivate`), its
  author's profile's privacy when posted: the app reads the profile and
  writes it on new posts and reposts (`UserPostRepositoryFirebase`), the
  API does the same, and the `follows` functions stamp posts that come
  without it (`postPrivacy`) and update every post when a profile turns
  private or public (`profilePrivacy`). `firebase/scripts/
  backfill-post-privacy.mjs` stamps existing posts.
- Rules (`canSeePost`): a private post, its comments, and liking or
  commenting on it are for the author and their accepted followers
  (`users/{me}/follows/user_{author}`); the author can't change the flag.
  Storage: a private profile's post photos likewise. A missing post can
  still be asked about (the offline queue checks).
- Queries: the rules can't check a follow per post in a query over
  several authors, so those ask for `private == false`, and the user and
  private profiles they follow (`Follow.approved`, at most 30, the latest
  followed) are asked for one author at a time
  (`watchPostsByAuthors`/`fetchPostsBefore` `includePrivate`). Tournament,
  team-event and community-feed posts are public ones only. A profile
  page asks for every post on the user's own or an accepted private
  profile, else public ones. When a profile turns private, its existing
  followers' follows are marked `approved` by `profilePrivacy`.
- Push: a private profile's post tagged with a tournament no longer
  notifies that tournament's followers, only the author's.
- The community feed watches each post on its own (`watchPostsByIds`):
  the rules check a query by id post by post, so one that turned private
  would fail them all; a post the user may not read just drops out. A
  private author whose follow was taken away shows no posts instead of
  failing the feed. A single post the user may not read errors with
  `PostHiddenException` ("Only people they approve see this post.").
- A private profile's post can't be reposted (`PostActions.canRepost`;
  the rules and API refuse it too).
- Phase A only: the rules still let any post query through (`allow
  list: if signedIn()`), so this build and 0.0.28 both work, and a
  query for one private author's posts is still answered to anyone.
  Phase B switches it to `canListPost` (strict `private == false`, since
  `get('private', false)` let unfiltered queries through in tests) once
  this build is on testers' phones;
  `firebase/functions/test/rules/posts_phase_b.rules.test.ts` runs every
  query this build makes against that rule.

## 0.0.28 — Offline queue, one Photos + button

(0.0.27 is the payments branch's.)

- Offline queue (`OutboxRepository`, `lib/data/repositories/outbox/`):
  direct and group messages, team chat, posts, team posts and comments
  sent while Stall 10 can't be reached wait on the device
  (`FileOutboxStore`: the app support folder, `outbox/jobs.json` and
  each item's photos and files) and send by themselves, in order per
  thread, once it can, including after the app is closed and opened
  again. Each item's id is picked when the user sends it and kept, so a
  retry never posts twice: before resending, the queue checks the server
  (`existsOnServer`), and `already_exists` counts as sent. Connection or
  server errors (`unavailable`, 5xx, rate limits, timeouts) wait and try
  again with backoff (5 s up to 5 min); anything else is "Not sent",
  with Try again and Discard, and doesn't hold up the rest. Items belong
  to the account that sent them and only go out while it's signed in.
  The rules are shared with the website (`packages/shared/src/outbox.ts`,
  fixtures in `packages/shared/fixtures/outbox`). New posts only; likes,
  reactions, RSVPs and edits aren't queued.
- `ConnectivityService`: no network (connectivity_plus) is offline at
  once; a failed send also marks it offline; then the API's `/health`
  every 15 seconds until it answers. Firestore writes wait instead of
  failing offline, so a send that hangs 15 s (2 min with attachments) is
  queued. Storage uploads give up after a minute
  (`setMaxUploadRetryTime`) instead of ten. An expired sign-in token that
  can't refresh offline is a connection error (`ApiClient`).
- `OfflineBanner` at the top of the app while offline or while anything
  waits; tap for "Waiting to send" (`OutboxSheet`). Queued messages show
  in their thread (`MessageThreadViewModel.statusFor`): "Waiting to
  send", "Sending…" or "Not sent". A snackbar says when something was
  queued instead of sent.
- Post composers (Home's box, the full composer, team posts): one
  "Photos +" button (`AddPhotosButton`) asks Take photo or Upload photos
  (straight to the library without a camera), instead of separate camera
  and photo buttons. Still up to 4 photos; extra picks are left out with
  a note.
- New packages: `connectivity_plus` 7.3.1 (7.3.2 needs a newer `dbus`
  than geolocator allows), `path_provider`.

## 0.0.26 — Clearer workout boxes, scroll while showing times, push back

- Workouts (both composers): every box has its name above it, always
  shown (`WorkoutField`), with an example inside (`e.g. 45`, `min`, the
  distance unit). Each exercise is its own card (`ExerciseCard`):
  "Exercise 1" and remove, the name across the full width, then Sets,
  Reps and Weight, each named. Before, small boxes on a phone had their
  labels cut off or hidden once typed in.
- Messages: the thread keeps scrolling up and down while dragging left
  to show the times. `_RevealTimes` follows the finger with a `Listener`
  instead of taking the drag, and a bubble's swipe to reply (`_RightSwipe`)
  gives way as soon as a drag sets off left.
- A notification tapped outside the app (push) opens its page with back
  going where the page belongs, not where the app was left
  (`openFromOutside`): a conversation over Messages, a team chat over its
  team (`go`), a post over Home, a team event or meeting over the team's
  events, a tournament or your own event over Events (`pushParent`).

## 0.0.25 — Message times, notifications stay, follow requests in Notifications

- Messages: swiping right to reply only starts on the message bubble
  (`_SwipeToReply` wraps the bubble, or the message body in feed-style
  rooms), not the whole row. Dragging the thread left anywhere shows
  every message's time at the right edge, sliding back on release
  (`_TimeReveal`, `_RevealTimes`, `_TimeSlide`); your own bubbles slide
  over to make room.
- Profiles opened from a page over the tabs (Following, follow requests,
  notifications) open over it at `/people/:uid` (`openPage` and
  `openLink` rewrite `/players/:uid`), so back returns there instead of
  switching to the Explore tab with no way back.
- Notifications stay in the list once opened: `markSeen` and
  `clearRoute` (a chat or post seen, a notice tapped) mark entries read
  instead of deleting them. Unread entries are bold and larger; read ones
  lighter. Clear and Clear all still remove them.
- Follow requests moved from Settings → Privacy to the top of
  Notifications (`/notifications/follow-requests`, with how many wait);
  `/settings/follow-requests`, which older notices link to, redirects
  there.

## 0.0.24 — Keyboard, Send, no link tool, lighter workouts

- Keyboard: tapping outside a text field closes it everywhere
  (`TapOutsideUnfocus` in `main.dart`'s builder overrides
  `EditableTextTapOutsideIntent`, which Flutter only honours for a mouse
  on phones). Chat, comment and Home composer bars sit in a
  `TextFieldTapRegion`, so their Send/attach buttons keep it open.
- Send (a post's paper plane) and Repost drop focus before opening and
  after closing (`dropKeyboard`): closing a sheet no longer hands focus
  back to a field, which re-opened the keyboard. The repost note no
  longer autofocuses.
- Send's Recent list skips group chats and people who deleted their
  account (`Conversation.otherDeleted`: deletion keeps the conversation
  under "Deleted user").
- Account deletion (`account` functions) also deletes the user's Storage
  folder (`users/{uid}/`: profile and header photos, leftover post
  photos).
- Posts have no Link tool or "Add a link" field (Home composer, post
  editor, team post editor; same on the website). Web addresses in a
  post's text are tappable (`LinkifiedText`). Older posts keep their
  links, shown and removable when edited.
- Workouts look lighter: a one-row activity picker (`ActivityPicker`)
  and a one-line effort slider (`EffortRow`) in both composers, with a
  close button instead of "Remove workout"; the posted workout is an
  outlined card with values over small labels, a shorter map and a
  compact exercise list.

## 0.0.23 — Visitors see only team and community pages

- Flutter web (`web_router.dart`): signed-out visitors keep the community
  feed and team/community pages; Explore, Events, the Teams tab, player
  profiles, Schedule, Rankings, Learn, Messages, Notifications and
  Settings send them to sign in (`?from=` brings them back), as on the
  Next.js website.
- `browse` functions: `profile`, `events` and `search` need a signed-in
  caller (`unauthenticated` otherwise); `feed`, `post` and `team` stay
  open. School/club communities that approve members are private groups
  on public pages, like groups (review S6).
- The native app is unchanged: it already needs a sign-in.
- Discord import: moving rooms to linked teams never moves the
  community's General room (as on the website).
- Balanced draft: a seeded mulberry32 shuffle (`SeededRandom`,
  `shuffleWith`), the website's, so the same seed deals the same teams on
  both. Existing seeds deal differently than before; teams aren't
  redealt unless the host deals again.
- Voice channels re-check your access while connected (as on the
  website): losing access to the channel or team drops the call, losing
  the right to talk mutes you, and signing out or switching accounts
  hangs up.
- New Community tab on Home (For you / Community / Your teams), as on the
  website, from the API's members' feed.
- Deleting a team asks you to type its name and goes through the API
  (`DELETE /v1/teams/:id`, which also refuses while it hosts an unfinished
  tournament or league).
- Voice: switching channels quickly ends in the last one picked; voice no
  longer drops while a team is still loading, and its watches reconnect.
- Drafts typed right after sign-in no longer overwrite saved ones.
- Players with the same name are drafted in a fixed order (by uid).
- A youth team's page says "Rosters of youth teams are private: only
  members see them." to anyone who isn't on it (as on the website; the
  API refuses them its roster).
- The tournament form says the location and About are public.
- Removed code we no longer need: the old Flutter website, the
  Windows/macOS leftovers (Windows Google sign-in, screen-source and
  speaker pickers, the mouse-only message strip, WebView2 players) and
  unused packages. iOS and Android work as before.
- Cancelling Google or Apple sign-in (or the check before deleting the
  account) shows no error, as on the website; it used to show the raw
  Google exception or "Sign-in was cancelled.".
- Message drafts are kept per user and cleared on sign-out (as on the
  website).
- Home: the Your teams tab is your teams' posts, a team strip with
  New / Join, a Get started checklist and a Needs you card; the invite
  dialog makes its link on open and lists join requests.
- Phone top bar: "Stall 10" without the logo, and a bell for
  notifications.
- Google and Apple sign-ups are asked "Your name and username"; "About
  you" starts the legal name from it.
- Email sign-up saves the birthday (encrypted, through the API) so
  "About you" fills it in after a restart or on another device.
- Club teams are for players 16 and over: creating, joining and
  accepting an invite go through the API, which checks the date of
  birth; the rules refuse direct writes for club teams.
- Rankings: Level and Division filters (as on the website), opening on
  Club Mixed; youth is never ranked or rated.
- Home's post box is an inline composer (`InlineComposerViewModel`):
  type and tap Post; Photo, Link and Workout open inside the box, and
  "To" posts to Everyone or a team you manage (replaces the Team post
  button and the editor popup on Home). Nothing can change while it
  posts, and if the team picked leaves your list the post isn't sent
  (never to Everyone instead). Links keep a lower-case scheme.
- Explore's filter chips sit on one row that scrolls sideways.
- Get started: "Join or create a team"; the create-or-join dialog no
  longer overflows on narrow phones.
- Tests: shared test vectors (`packages/shared/fixtures`, written by
  `test/shared_fixtures`) check the tournament engine, stats, play
  animation, drafts, Discord import and calendar files against the
  website's code.

## 0.0.22 — An indigo logo

Assets only; no data, rules or API changes.

- `tool/brand/stall10_logo.py` draws the same "10" disc mark on white
  with an ink "1" and an indigo disc and trail (the website's accent), in
  place of lime on green, so the icon promises the palette users find
  inside. It now runs from `apps/mobile`
  and writes the in-app logo, the Android and iOS launcher icons and the
  website's `logo.png` / `favicon.png` (`apps/web/public`,
  `firebase/hosting`); the macOS and Windows outputs went with those
  platforms.

## 0.0.21 — The website's palette; layout fixes

UI only; no data, rules or API changes.

- `AppColors` (`ui/core/themes/theme.dart`) takes the website's tokens
  (`apps/web/app/site.css`): indigo accent on `#F3F5FB` (light) and
  "Midnight" (dark). `sidebar` is now white / Midnight card with ink text,
  `feature` is the brand indigo, and `highlight` is amber, kept for calls
  to action and marks on feature cards and strong tags.
- Selection is indigo tint, as on the website: the sidebar and rail's
  selected item (`accentSoft` with `accent`), the bottom bar's selected
  icon and label, `UnderlineTabs` and `TabBar` (accent label and
  indicator), selected chips (accent fill), badges and selected list tiles.
- The sign-in hero (`disc_throw_hero.dart`) is a Midnight sky over an
  indigo field with an amber disc. The logo and launcher icon are
  unchanged.
- Post photos (`_PostContent`) fill the post's width: one at 4:3, more in
  two columns sized from the width. A fixed 320 dp photo overflowed the
  post page by 10 dp on phones.
- `SettingsTile` puts a long value (over 22 characters, e.g. an email)
  under the title, and caps a short one at 180 dp with an ellipsis.
- Home's composer buttons wrap from the card's left edge.
- A post's Like / Repost / Comment row drops its words by the row's own
  width (under 380 dp), not the screen's: on 411 dp phones it overflowed
  the post card.
- Schedule marks (`AppColors.team` / `personal`) use the website's tile
  blue (`#2C6FB7`, dark `#7FB0EE`) and berry (`#A8407A`, dark `#E08BB8`),
  so personal events no longer look like the new indigo accent.
- The sign-in hero drops its chalk brick mark, which sat behind the
  tagline. Home's "Coming up" Add event button is compact (36 dp), so the
  card's bottom padding matches its top. The selected conversation's left
  bar is the accent.

## 0.0.20 — Pull to refresh Home; calendars

Needs API 0.8.0 (`/v1/me/calendars`, `/v1/calendars/*`), the
`calendars` rules and the `notifications-calendarInvite` function.
Without `API_BASE_URL`, calendars other than My calendar are hidden.

- Calendars, as in Outlook or Apple Calendar (`CalendarRepository`, API
  only; models in `domain/models/calendar.dart`). **Settings → Calendars**
  (`CalendarsScreen`): your calendars with their color and people, a new
  calendar, invites to accept, calendars shared with you (leave), and a
  private subscription link (Apple Calendar or Outlook via `webcal://`,
  Google Calendar, copy, reset, turn off). Each calendar's page renames,
  recolors, sets each person's role (Can view or Can edit), cancels
  invites, invites by people search with a role, and deletes it.
- Invites push (`notifications-calendarInvite`, opens Calendars) and show
  on the Schedule tab with Accept and Decline. Nothing is shared until
  you accept.
- The Schedule tab shows your other calendars' events in each calendar's
  color (`ScheduleEntry.calendar`); tapping one opens a sheet with Add to
  calendar and, if you can edit it, Edit. Editors and owners can swipe
  to delete. Personal filter includes them. `MySchedule.loadCalendars`
  covers the week shown, from a week before to nine weeks after; pull
  down to reload. My calendar's events stay live from Firestore.
- The event editor's **Add to** picks My calendar, another calendar you
  own or can edit, or a team; events on other calendars save through the
  API (`/calendars/:id/events/:eventId/edit` to edit one).
- **Add to calendar** (an .ics file through the share sheet) on personal
  and team events (`utils/ics.dart`).
- `ApiClient` accepts empty `204` answers.
- Links use the domain: invite, group and post links and the legal
  pages are on `stall10.app` in prod builds and `dev.stall10.app` in dev
  builds (`InviteLinks.host`), served by the website. Links on the old
  `frisbee-app-brianrhonea.web.app` still open the app
  (`InviteLinks.hosts`; AndroidManifest lists all three).

- Home's feed refreshes on pull-down, and when Home is tapped again (back
  to For you, top of the feed): `HomeFeed.refresh()` re-subscribes every
  source. `PageScroll` takes an `onRefresh`.

## 0.0.19 — Personal details at sign-up

Needs API 0.7.0 (`/v1/me/personal`) and its KMS key. Deploy
`firestore.rules` (`personalDetails/{uid}` closed to clients) and the
`account` functions group (account deletion removes the record).

- Sign-up asks the date of birth; under 13 can't make an account.
- New accounts (made from `personalDetailsRequiredSince`) give their
  legal name, birthday, phone, gender, mailing address and, under 18, a
  parent or guardian before anything else (`/welcome/details`, after the
  username). A birthday under 13 there (Google and Apple sign-ups aren't
  asked first) deletes the account without sending anything (or, if that
  needs a fresh sign-in, signs them out). Also on the Flutter web build
  (`web_router.dart`). Unknown status (no
  `API_BASE_URL`, offline) holds nobody up.
- Older accounts get a dismissible **Complete your details** card on Home.
- **Settings → Personal details** to see and change them.
- `PersonalDetailsRepository` (API only; no direct Firestore path, since
  the rules allow none). Model in `domain/models/personal_details.dart`
  mirrors `packages/shared/src/personal.ts`.
- Profile writes no longer use the account's email as the public name when
  there's no display name (`AppUser.publicName`).
- Account deletion also removes `personalDetails/{uid}` and the profile's
  subcollections (`private/details`, follow requests), which were left
  behind before.

## 0.0.18 — A tidier Teams tab; one team page; communities list their teams

Needs API 0.6.0 for community admins' invites (the rules allow the direct
path too). Deploy `firestore.rules`.

**Changed**
- **Teams tab** (`TeamsScreen`): Invitations, then **Your teams** (teams
  you joined yourself, "Part of X" when a community links them), then
  **Communities**, each with its teams nested and folded past three
  (`_CommunityCard`). A team one of your communities lists
  (`TeamsViewModel.viaCommunity`) sits only under the community, even if
  you own it.
- One **+** button (Join with a code, Find a team or community, Start
  one) replaces Search, Join and the New button.
- **Team page on phones** (`TeamHomeScreen._phonePage`): one page for
  every tab, More included. The header (`_TeamHeaderDelegate`, a pinned
  `SliverPersistentHeader` in a `NestedScrollView` with an overlap
  absorber) folds from the banner, badge and name into a bar (back, small
  badge, name, menu) with the tabs pinned under it: animated when a tab
  other than the feed opens, and as the feed scrolls. Follow, Message and
  Invite moved to the top of the feed (`_HeroDetails`). Before, each tab
  rebuilt the page with a different header, which read as a new page with
  a back arrow. Tablets and desktops are unchanged.

**Added**
- A community's page has a **Teams** tab (`TeamTab.teams`) for its
  linked teams (`CommunityTeamsTab`).
- **Add yourself** on Roster → Players: admins who aren't on the roster
  get a spot filled in with their name and linked to their account
  (`TeamDetailViewModel.selfDraft`, `onRoster`).
- Community admins with Manage members invite people to any of its teams
  from that tab (**Invite people** in a team's menu). The invite dialog
  runs without a link there (`InviteMembersViewModel.withLink`): the
  community's admins can't make the team's links, so the message says to
  accept from the Teams tab. `firestore.rules`: `teamInvites` lets them.

## 0.0.17 — Learn to play in the app

The rules for beginners were only on the website (`/learn`). No data
changes.

**Added**
- **Learn to play** (`/learn`, `LearnScreen`): the website's beginner's
  guide to the rules as a native page, with jump-to-section chips and
  links to Explore and Find events. The text is in
  `lib/ui/learn/learn_content.dart`; keep it in step with
  `apps/web/app/learn/page.tsx`.
- Opens from Explore's **Jump in** card and from **Settings**.

## 0.0.16 — New navigation: five tabs and a five-tab team page

Step 1 of the rework in `docs/product-spec.md` (§3, §4). No data changes.

**Changed**
- **Tabs** (`ShellSection`): Home, Explore, **Events**, Teams, Messages.
  The profile keeps its shell branch but has no tab; on phones an avatar
  (`ProfileButton`) at the top left of each tab's first page opens it,
  and no tab looks selected there.
- **Events tab** (`/schedule`): My schedule (moved from Home's branch) and
  Find events (`?view=find`, the tournaments and leagues list), under
  `EventsTabs`. `/tournaments` still opens on its own.
- **Team and community pages** (`TeamTab`): Feed, Schedule, Chat, Roster,
  More, over the unchanged `TeamSection`s and their links. Roster opens on
  members, with a Members / Players switch on teams; More
  (`?section=more`) lists Playbook, Videos, Stats, Tournaments and, for
  schools/clubs, Teams. "Team Events" is now Schedule everywhere.
- Breadcrumbs say Home, Events and Teams; the desktop sidebar drops its
  Team calendar link.

## 0.0.15 — Leagues and hat tournaments; monorepo; API paths

**Added**
- **Leagues and hat tournaments**: a `HostedTournament` with
  `kind: league`, team or player entry (`entryType`), set weeks, and a
  balanced (self-rating) or captains' live draft
  (`/tournaments/:id/live-draft/:divisionId`, callables in
  `functions/src/tournaments/draft.ts`). Mixed entry: teams reserve spots,
  free agents are drafted into the rest. **Host an event** picker
  (League / Tournament / Hat) and a Tournaments & leagues find page.
- **Official hosts**: `Team.official` (console only) and
  `HostedTournament.hostOfficial`, shown with a verified badge.
- Shared event format (`HostedTournament.format`) and points or time
  scoring.
- **API paths** for team create, membership and profiles/usernames
  (`apps/api`), behind `use_api_teams`, `use_api_membership` and
  `use_api_profiles`. Builds without `API_BASE_URL` keep writing Firestore
  directly.

**Changed**
- The repo is a monorepo: the app lives in `apps/mobile` (Codemagic builds
  from there).

**Removed**
- The `web/`, `macos/` and `windows/` targets. The app is iOS and Android
  only; the website is `apps/web` (Next.js). Local runs use an Android
  emulator or a device.

## 0.0.14 — Hosted tournaments; USA Ultimate data removed

**Removed**
- All USA Ultimate data and features (events, rankings, team pages and
  search, team linking and roster sync, the `onUsau` flag, USAU event
  follows, the Home card and the `functions/src/usau` scrapers). We don't
  have rights to the data; see CLAUDE.md.

**Added**
- **Hosted tournaments** at `tournaments/{id}` (`HostedTournament` in
  `lib/domain/models/hosted_tournament.dart`), with `divisions/{id}/games`,
  `entries/{teamId}` and `payments/{teamId}`. Any team, group or
  school/club hosts from its Tournaments section; members with Manage
  events run it. Draft → registration → seeding → scheduled → live →
  final. Public or invite-only; published tournaments are readable by
  anyone signed in, payments only by managers and the team's admins.
- Divisions (division × level, team cap, format, game rules), team
  applications and invites with captains, accept/waitlist/decline/
  withdraw, a recorded bid fee marked paid by hand (unpaid and overdue
  filters), drag-to-seed, publish per division, captain score reporting,
  results with final placements, news (public host posts tagged with the
  tournament's follow key) and following.
- Engine: `TournamentFormat.poolsPlacement` (pools, then brackets where
  every team plays for a final place), `GameStage.crossover` and
  `placement`, `GroupGame.place`, `placementsOf`, `suggestedPools` /
  `suggestedFormat`, `scheduleFor(teams, settings)`.
- Routes `/tournaments` (find), `/tournaments/new?host=`,
  `/tournaments/:id`, `/tournaments/:id/edit`; Explore → **Find a
  tournament**. Signed-in web gets the same routes; visitors sign in.
- `firestore.rules`: `tournaments` block; game docs (both kinds) may
  carry `place`. Index: `tournaments` (status, startsOn). Rules and
  indexes deployed to dev.

**Changed**
- Teams and schools/clubs get a Tournaments section; groups list hat
  tournaments under their hosted ones. Tournament follows open
  `/tournaments/:id?host=`, which falls back to the hat tournament.

## 0.0.13 — Flood protection, paging, smaller photos, push fix

Branch `hardening/scale-and-abuse`, merged into `development`.

**Added**
- **Flood control** (`functions/src/api`, deployed as `api`): create
  triggers count each person's messages, posts, comments, follows, join
  requests and new teams in `limits/{uid}`; past the limit the extra item
  is deleted and `mutedUntil` set 10 minutes ahead. `firestore.rules`
  checks `notMuted()` on those creates. The app shows "You're going too
  fast". Username sign-in is limited to 10 tries per 15 minutes.
- **`api-search`** callable (people, players, teams; rate limited), off
  until `meta/flags.use_api_search` is true. **`api-health`** for uptime
  checks.
- **App Check** in the app (`AppCheck.activate()`, `X-Firebase-AppCheck`
  on HTTPS calls); callables enforce it when `ENFORCE_APP_CHECK=true`.
  `APP_CHECK_DEBUG_TOKEN` added to the secrets files.
- **Kill switches** in `meta/flags` (`FeatureFlags`): `use_api_search`,
  `compress_images`.
- **Photo compression** (`ImageCompressor`): ≤ 1920 px, JPEG 80, EXIF
  baked in, before upload; picks up to 50 MB. Uploads get a year-long
  `Cache-Control`. `functions/scripts/compress-existing-images.ts` for
  old uploads.
- **Cursor paging** for chat, DMs, meeting chat (`fetchOlderMessages`)
  and the home feed (`fetchPostsBefore`): older pages load one at a time.
- **Deploy / Roll back backend** GitHub Actions workflows, and
  `scripts/monitoring/setup-alerts.sh` for SMS alerts.
- Docs: `ARCHITECTURE.md` restructured, `cloud-limits.md`, `rollback.md`,
  `monitoring.md`, `app-check.md`.

**Changed**
- The chat Send button shows at every width (it was hidden at 720 px and
  up, so tablets couldn't send).
- Notification rows are compact (no category icons; one line each for
  title and message); the notifications button is a flying disc
  (`DiscIcon`) instead of a bell.
- `fieldOverrides` stop indexing large unqueried fields; hosting sends CDN
  cache headers; `maxInstances: 10` for every function.

**Fixed**
- **iPhone push never registering**: `PushService.register` waited for
  `onRegistered`, which iOS can fire at launch before anything listens,
  so it timed out and no device was saved. It now waits for the APNs
  token, registers, and reads the FID from Firebase Installations
  (`firebase_app_installations`). Failures throw
  `PushRegistrationException` and show in Notification settings with
  **Try again**; the server logs "Push sent" / "No push devices".

## 0.0.12 — School and club communities, private profiles, username sign-in

Straight on `development`.

**Added**
- **School or club communities** (`TeamKind.organization`, noun
  "community"): one community with several full teams (e.g. Woof and
  Whiplash). Teams link both ways: the team sets `orgId`/`orgName`, the
  community lists it in `linkedTeams.{teamId}` `{name, division, roles}`.
  A team asks to join (`teams/{orgId}/linkRequests/{teamId}`) and the
  community accepts, or the community creates the team inside itself.
  The admin picks which community roles get onto each team; holders join
  it automatically and leave when the role is taken away (only people the
  community added, tracked in `orgMembers`). **Teams** tab on the
  community; **School or club** in the team ⋮ menu and a chip on the team
  home.
- **Community events by role**: an organization's event has an `audience`
  (role ids / `everyone`); only those roles see it. Queries use
  array-contains per held id (`Team.eventAudienceOf`), with a composite
  index (audience CONTAINS, startsAt ASC). Event editor: **Who sees it**.
- **Discord import into teams**: on a community with teams, rooms only one
  team's roles read go to that team's chat (`DiscordTeamSplit`), shared
  rooms stay in the community, each room can be overridden. Each team
  gets copies of the community roles that grant it (`Team.orgRoles`,
  team role → community role) and the community function keeps who holds
  them in step. Rooms already in the community chat from an earlier
  import are moved (deleted there after a confirm).
- **Sign in with username or email** (`account-signInEmail` callable,
  checks the password through the Identity Toolkit REST API with the
  `WEB_API_KEY` secret, then returns the email).
- **Private profiles**: Settings → Privacy → **Private profile**. Only
  name, username and photo stay in `profiles/{uid}`; the rest moves to
  `profiles/{uid}/private/details`, readable by the owner and accepted
  followers. Following one sends a request
  (`profiles/{owner}/followRequests/{uid}`); **Follow requests** in
  Settings accepts or declines.
- **Change password** in Settings → Account (current, new, confirm;
  "Forgot it?" sends a reset link).
- **In-app notification bubble** while the app is open, from the feed, on
  every platform; repeats in the same chat update it in place. iOS and
  macOS no longer show a system banner in the foreground.

**Changed**
- Playbook on phones: a 44 px minimum grab radius and a small drag
  threshold so fingers pick up dots; touching the field hides the step
  note keyboard.
- Notification settings explain when push is off on the phone, with
  **Turn on notifications** / **Check again**.

**Infrastructure**
- New Cloud Function `communities-sync` (`onDocumentWritten teams/{id}`):
  membership by role, catch-up for teams linked earlier, role copies
  (`mirrorUpdate`). `notifications` use `eventViewers` (audience) and
  honor custom roles in `roomReaders`; `account-signInEmail` added and
  join-request cleanup covers both group kinds. All deployed to dev.
- Rules: organizations, `validOrgRef`, `linkRequests`, `orgMembers`,
  `orgRoles` (map ≤ 50), event `audience`, private profiles and follow
  requests, with rules tests. Rules and indexes deployed to dev.
- Secret `WEB_API_KEY` set on dev and prod.

## 0.0.11 — Usernames, Settings, search everywhere and polish

Straight on `development`.

**Added**
- **Usernames.** Unique, 3–20 of `a-z 0-9 _ .` (no leading, trailing or
  double periods; a few reserved). Sign-up asks for first and last name,
  username (live availability check), email, password and confirmation.
  Google, Apple and older accounts are sent to **Pick your username**
  (`/welcome/username`) by `authRedirect` before anything else. Shown as
  @name on profiles, in people search, Explore, the send-post sheet and
  the invite dialog; search matches it.
- **Password policy**: 8–128 characters, a letter and a number, no
  leading or trailing space, not a common password. Strength meter and
  checklist on sign-up; show/hide on every password field.
- **Settings page** (`/settings`, gear at the top right of your profile)
  sliding over the page, a 440 px panel on wide windows: General
  (theme), Notifications, Privacy (read receipts), People you follow,
  Account (display name, username, email, delete account), Sign out and
  the version. Sub-pages `/settings/general`, `/privacy`, `/account`.
  Replaces the profile's Settings card.
- **Read receipts**: "Seen" under your last message once the other person
  reads it; off in Settings → Privacy (then you don't see theirs).
- **Notification offers**: once at first sign-in, on joining a team, and
  on following someone. Declining a team turns off its per-team
  categories.
- **One search**: Home has a search bar on phones; the top bar's box
  says "Search Stall 10". Explore searches players, teams, groups and
  upcoming USA Ultimate events (chips: All, Players, Teams, Groups,
  Events; three events in All with "See all"). `/teams/search` redirects
  to Explore. A shared `AppSearchField` everywhere.
- **Command menu**: Ctrl K / ⌘K from anywhere (a `HardwareKeyboard`
  handler, so focus doesn't matter): sections, your teams, common
  actions, and "Search Stall 10 for …". Ctrl 1–5 switch sections, from
  inside the menu too. Key-cap hints in the top bar, menu and rail
  tooltips.
- **Undo instead of "Are you sure?"** for deleting feed posts, comments
  and chat messages: hidden at once, deleted after 5 s
  (`PendingRemovals`), or when the screen closes.
- Skeleton placeholders instead of spinners (`LoadingView` and the
  feed, profile, Explore, sheets and photos); photos fade in.
- Balanced headlines (`BalancedText`) on page and auth titles.

**Changed**
- **Roles**: built in are Owner and Player only; owners create the rest.
  Coach and captain tiers migrate to custom roles (Coach and Captain
  with every permission on teams, Organizer on groups) the first time
  the owner opens the team; rooms that admitted a tier admit the new
  role. Nobody can be made coach or captain any more.
- Notifications: per-room mute moved into the room's ⋮ menu; a person's
  post notifications into the **Following ▾** menu.
- Phones: portrait only (iPhone `Info.plist`, Android under 600 dp), and
  the bottom bar has every section.
- Direct messages on phones have a back arrow to Messages instead of the
  conversations drawer (team chat keeps its drawer).
- Sign-in and sign-up fit a phone screen without scrolling.
- Theme: `RoundedSuperellipseBorder` corners, tabular figures in all
  text, drag handles on swipeable sheets, predictive back on Android
  (`enableOnBackInvokedCallback`), Cupertino slides on iOS and macOS and
  fade-forwards elsewhere. `slideOverPage` (with an edge shadow) for
  Settings and notification settings.

**Infrastructure**
- New Firestore data: `usernames/{name}` → `{uid, createdAt}`, claimed in
  the same transaction that sets `profiles/{uid}.username` (set once);
  `users/{uid}.firstName`, `.lastName`, `.readReceipts`; private read
  marks `users/{uid}/dmReads/{conversationId}`. Rules and rules tests
  for all of them, and for the role migration (deployed to dev).
- `account-deleteAccount` frees the user's username, and ownership
  passes to coach, then captain, then a member with Manage team
  (deployed to dev).

## 0.0.10 — Comments and sending posts

Straight on `development`; feature branches are retired for the beta.

**Added**

- **Comments** on people's posts. **Comment** under a post (with the
  count) opens its page at the comment box; comments show oldest first
  with who and when, and links in them are tappable. Commenting on a
  repost comments on its original. Delete your own comment, or any
  comment on your post.
- The post's author is notified ("Zed commented on your post"; comments
  on one post fold together), in the **Likes, reposts and followers**
  category.
- **Send** under a post: pick someone you've messaged (listed first) or
  search for anyone, and tap **Send**. It goes as a direct message with a
  line about the post and its link, which opens the post in the app.
  **Copy link** and **Share to other apps** are there too.
- **Post links** (`…web.app/p/<id>`) open the post in Stall 10 on phones
  with the app, or a page with an **Open in Stall 10** button. Signing in
  from one returns to the post.

**Infrastructure**

- New Firestore data: `posts/{id}/comments/{commentId}`; rules and rules
  tests (anyone signed in comments as themselves, up to 1000 characters,
  not on a repost; the commenter or the post's author deletes; nobody
  edits; nobody writes `commentCount`). A collection-group exemption on
  `comments.authorId` for account deletion.
- New Cloud Functions: `follows-commentCount` keeps each post's
  `commentCount`; `notifications-postCommented` tells the post's author.
  `follows-userPostDeleted` now deletes a post's comments too, and
  `account-deleteAccount` deletes the user's comments.
- `/p/*` added to the hosting rewrites, the iOS
  `apple-app-site-association` and the Android App Links filter.

**Also in 0.0.10** (`b80e854`)
- Discord-style **custom roles** with permissions (Manage team, Manage
  members, Manage chats, Manage events, Moderate, Keep stats) for teams
  and groups; rooms take role-based access and live in reorderable
  folders.
- **Import roles and channels from a Discord server template** link
  (`discord-previewTemplate` function).
- **Voice channels** on LiveKit (`meetings-voiceToken`), listen-only for
  members who can read but not write.
- Discord-style message rows and composer; drag to rearrange channels and
  folders.
- Faster back navigation: shared message streams, and the native iOS page
  so swipe-back works.
- A separate **dev Firebase project** (`frisbee-app-brianrhonea-dev`):
  `FIREBASE_ENV` picks the project; `development` builds TestFlight against
  dev, `main` builds the App Store against production.

## 0.0.9 — Record runs and rides with GPS

Branch `feature/gps-workouts`.

**Added**
- **Record** (Home and Profile, on phones): record a run, ride, walk or
  hike with GPS. A live map draws the route, with the time, distance,
  average pace and current pace (speed for rides). Start, Pause, Resume,
  Finish or Discard. Recording keeps going with the screen locked (an
  Android notification; iOS background location) and while you use the
  rest of the app; the Record button shows the clock.
- **Finish** opens the composer with the time, distance and route filled
  in. **Hide your start and finish** (on by default) cuts the first and
  last 200 m from the posted map; the stats are unchanged.
- Recorded workouts show the route map on the post. Opening the post
  shows **splits**: the time for each mile or kilometre, with the part
  left over, and elevation gain.
- New activities: Ride, Walk and Hike.

- **New sign-in and sign-up screens.** A disc is thrown across an ultimate
  field while the wordmark counts the stall (Stall 1… 9) and is caught as
  the "0" of the logo: Stall 10. Then the form slides up. Plays once per
  launch, not at all with reduced motion; tap the field to throw again. The
  field sits above the form on phones and beside it on wide screens.
- **Share an event with followers.** A switch on new events posts the
  event (date, time, place, team) to your profile with an optional note.
  A shared team event also shows in the feed of everyone on that team.
- **Likes and reposts** on people's posts, with counts. A repost shows
  your note over the original, which stays live (edits show; a deleted
  original says so). One repost per person per post; tap **Reposted** to
  take it back.
- **Notifications** when someone likes or reposts your post (likes on a
  post fold together) or starts following you, with **Follow back** right
  in the list. A new **Likes, reposts and followers** category turns them
  off.

**Changed**
- **Add event** moved from the post composer to **Coming up**, asks which
  schedule first, and opens over the page like the composer instead of on
  a page of its own. Saving offers **View**; closing with changes asks
  first.
- The post composer on wide screens is only as tall as its content.
- From a post's own page, tapping a person or team switches to their tab
  instead of crashing with duplicate page keys.
- Signing in or up always lands on **Community**, instead of the page you
  were on. Invite links (`/join/…`, `/g/…`) still return to the link so
  you can finish joining.
- Distances, paces and speeds show in miles in the US and UK, kilometres
  elsewhere. The manual workout distance field uses the same unit.
- Workouts store `durationSeconds` and a `route` (encoded polyline, splits
  per mile and per km, elevation gain); `validRoute` in `firestore.rules`.
- Codemagic builds the iOS app and uploads it to TestFlight on every push
  to `development`.

## 0.0.8 — Follows, the home feed and workout posts

Branch `feature/follows-feed`.

**Added**
- **Follow** people, teams, community groups, group tournaments and USA
  Ultimate events. The button is on team and group pages, tournament and
  event pages, and people's profiles. It shows the follower count.
- A **bell** next to Following turns on notifications for that one's new
  posts (push where the device allows, and always in Notifications). A new
  **Posts you follow** notification category turns them all off.
- **Home feed**: your posts, every post from your teams and groups, public
  posts from teams you follow, posts by people you follow, and posts
  tagged with a tournament you follow. Newest first, with **Show older
  posts**. On phones, Home is now the week, your team, then the feed.
  Playbook, events and rankings moved to the side column on wide screens,
  and they're still in their tabs.
- **Your own posts**: text, up to 4 photos and 5 links, optionally tagged
  with a tournament or event you follow.
- **Workouts**: share a run, sprints, throwing, gym, agility or mobility
  session. Add the time, an optional distance (pace is worked out for
  runs), effort 1–10 and up to 20 exercises with sets, reps and weight. The
  feed shows it as a stat card.
- **Profiles** (`/people/:uid`): name, photo, followers and following
  counts, Follow, Message and their posts. Open one from a post's author,
  a team's Members list, or **View profile** in people search.
- **Following** (Profile → Following, or **Following** on the feed):
  everything you follow, with each bell and Unfollow.
- Group pages list the group's tournaments for people outside the group.
  Someone who isn't playing in a tournament sees a public summary with
  Follow.
- **Invite links.** The invite dialog (team Members) shows the team's link
  to copy or **Share** to any app: Messages, WhatsApp, email. Tapping it
  opens Stall 10 at a Join screen naming the team; without the app, a page
  on Firebase Hosting (`hosting/`) has an Open in Stall 10 button.
  Inviting someone found by search also sends them the link as a direct
  message. Groups' links open their page. Links in messages are now
  tappable, and Stall 10's own open in the app.
- **Invite codes rotate; links expire.** Admins tap **Show code** on
  Members for a code that changes every 30 seconds (each works for 45).
  Team links last 1 hour, 1 day, 7 days (default) or 30 days, picked in
  the invite dialog. Codes and link tokens are `inviteCodes` docs with
  `createdAt` + `ttl`, checked by `join()` in `firestore.rules` on the
  server's clock; a TTL policy on `expiresAt` (`firestore.indexes.json`)
  deletes them. Coaches and captains can now mint codes, not just the
  owner. Permanent codes (`private/invite`, team-doc `inviteCode`) no
  longer work, and new teams get none.

**Changed**
- **The app is now Stall 10**, with a new logo: a "10" whose "0" is a
  flying disc. `tool/brand/stall10_logo.py` draws it and every launcher
  icon (Android, iOS, macOS, Windows). Bundle ids and the package name
  are unchanged.
- **Team pages have tabs.** Home, Team Events, Chat, Roster, Playbook,
  Videos, Stats and Members (groups: Home, Events, Chat, Tournaments,
  Members) sit in a tab bar under the team name. Switching tabs changes
  only the content below it; back leaves the team. This replaces the
  section tiles and the separate page for each section.
- **USA Ultimate tournament and team pages open over the current tab.**
  Tapping a tournament or ranked team on Home, Events, Rankings or
  Following no longer switches you to the Events or Rankings tab, and
  back returns to where you were. Opened from a link, back goes to
  Events or Rankings.

**Infrastructure**
- New Firestore data: `users/{uid}/follows/{key}`, `posts/{id}`,
  `followCounts/{key}` and `tournamentDirectory/{groupId_tournamentId}`.
  Team posts get an optional `tournamentKey`, which the tournament
  announcement sets. Rules and rules tests are written for all of them,
  plus Storage `users/{uid}/posts/…`; the rules tests need Java and the
  emulator to run.
- New Cloud Functions:
  - `notifications-userPost` and `notifications-teamPost` notify followers
    who turned the bell on.
  - A new `follows` group: `followCount` keeps `followCounts`;
    `profileDeleted`, `teamDeleted` and `groupTournamentDeleted` drop
    follows of deleted targets; `userPostDeleted` removes a deleted
    post's photos.
- New composite indexes: `posts` by `authorId` and by `tournamentKey`,
  each with `createdAt`. Also a collection-group index on `follows`
  (`key`, `notify`).
- Deleting an account also deletes the user's follows and posts.

## 0.0.7 — Community groups and pickup tournaments

Branch `feature/community-groups`.

**Added**
- **Community groups**: open pickup communities, alongside teams. No
  roster, playbook, videos or stats; instead Events, Chat, Tournaments and
  Members. Roles are Owner, Organizer and Member.
- Find groups in Teams search (filter All, Teams or Groups). Anyone can
  **Join**; if the owner turns on **Approve new members**, people **Ask to
  join** and organizers approve or decline requests on the Members page.
- A group's description and location. Organizers search for an address
  (OpenStreetMap / Nominatim) and fine-tune it on the map; the home page
  shows the map with a **Directions** button.
- **Pickup** events. Tournament events in groups take **Attending**,
  **Planning to attend** and **Not able to make it :(** RSVPs.
- **Tournaments** for groups: organizers set the format, rules and number
  of teams (Team 1, Team 2…, renamable) first, publish the schedule, and
  add players before or after. Players come from a Tournament event's
  attending and planning-to-attend RSVPs, or by hand; **Assign teams**
  deals them evenly into the teams with a random captain each.
- Formats: round robin, pool play + single elimination, single
  elimination and double elimination (with an if-needed final). Settings
  for 3v3 to 7v7, game length, breaks, score cap, timeouts per half,
  fields and an ideal end time.
- **Multi-day tournaments**: first and last date, with a start time for
  each day. The generated schedule splits games evenly over the days, in
  bracket order, and warns if it runs past the ideal end.
- The tournament page: schedule, pool standings, bracket and teams, plus
  "You're on…" with your captain and next game. Teams are private to the
  tournament's players and organizers.
- Captains **report** scores; the other captain **confirms**, or reports
  their own score instead. Organizers can set or correct any score.
  Confirmed results move teams on in the bracket; organizers seed the
  bracket from pool standings when pools finish.

**Infrastructure**
- Groups are `teams/{id}` with `kind: 'community'`. Firestore rules for
  group creation (no invite code), open join, `joinRequests` and
  approvals, group details and location, `groupTournaments` and their
  `games` (captain reports and confirmations, and bracket advancement
  checked against the source game with `getAfter`). Rules tests are
  written; they need Java and the emulator to run.
- Pure-Dart tournament engine in `lib/domain/tournament_engine/`
  (team builder, schedule generator, standings, bracket progress).
- New packages: `flutter_map`, `latlong2`.

## 0.0.6 — Team videos

Branch `feature/team-videos`.

**Added**
- A **Videos** section on each team for YouTube videos: meeting
  recordings, game film, anything uploaded to YouTube (Unlisted works).
  Thumbnails in a grid, newest first; tap one to play it in the app.
- Owners, coaches and captains add videos by pasting a link. UltiUP checks
  it with YouTube, shows the thumbnail, fills in the title, and warns if
  the video is private or doesn't allow embedding. They can edit the
  title and description, or remove a video (it stays on YouTube).
- YouTube's embedded player on Android, iOS and macOS, and on Windows in
  an Edge WebView2.
- **Upload a video file** (MP4, MOV, MKV, WebM, AVI, WMV, MPEG or 3GP)
  instead of a link: up to 500 MB per file and 5 GB per
  team, with an upload progress bar. Admins see how much of the team's
  space is used. Uploads play in the app with media_kit; removing one
  deletes the file.
- **Watch together** in meetings: an admin picks a team video (by folder)
  and it plays for everyone in the call, in sync, on their own device at
  full quality, instead of a screen share. Play, pause and seek follow the
  presenter; another admin can take control; Stop returns to the call.
  YouTube links and uploads both work, on Windows too (YouTube's IFrame
  API in WebView2).
- **Folders** to organize videos, like Film review, Game film and
  Highlights. Filter with chips (All, a folder, Unsorted); owners, coaches
  and captains create, rename and delete folders and move videos with
  **⋮ → Move to folder**. Deleting a folder moves its videos to Unsorted.

**Infrastructure**
- Firestore rules for `teams/{id}/videos`: members read; owners, coaches
  and captains write; only an 11-character YouTube id is stored, never a
  URL, or a video file record (deployed). Deleting a team removes its
  videos and their files.
- Storage rules for `teams/{id}/videos/{videoId}/{name}`: members read;
  owners, coaches and captains upload `video/*` files up to 500 MB (deployed).
- Firestore rules for `meetings/{id}/playback/current`: people in the
  call read; admins write as themselves, while live, for a team video
  (deployed). Ending or deleting a meeting clears it.
- Firestore rules for `teams/{id}/videoFolders` and a video's
  `folderId` (deployed). Deleting a team removes its folders.
- New packages: `media_kit`, `media_kit_video`, `media_kit_libs_video`.

## 0.0.5 — Team meetings

Branch `feature/team-meetings`.

**Added**
- Team meetings: owners, coaches and captains schedule a meeting for
  chosen roles and/or people, with an optional "Require admin approval to
  join". Meetings show on the schedule only for invitees.
- Meeting page with Attending / Not attending RSVP and a link to the
  meeting room.
- Meeting room lobby: pick microphone, speaker and camera, camera preview,
  meeting volume. Admins start the meeting (early if they like) and admit
  or deny people waiting to join.
- Video calls on LiveKit Cloud: camera or profile photo per person, a
  speaking highlight, screen share (Windows, macOS, Android), in-call
  chat, and mic / camera / sound / leave controls. Admins can end the
  meeting for everyone.
- Tap a person to set their volume (0–200%) or mute them, just for you.
  Devices and volumes are remembered on the device.
- Notifications for meeting invites, cancellations and starts; an in-app
  banner with **Join** when a meeting you're attending starts.

**Fixed**
- Opening notifications one after another (for example a play, then a
  team's events) could break navigation with a red screen.
- Leaving the play editor could throw an error while the page closed.
- Deleting a team now deletes its meetings too.

**Infrastructure**
- Firestore rules for meetings, join requests and meeting chat (deployed).
- `meetings` Cloud Functions group (`joinToken`, `closeRoom`), using the
  `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` secrets
  (deployed, with the updated `notifications` group).
- `--dart-define=FIRESTORE_MEMORY_CACHE=true` lets a second copy of the
  desktop app run on the same computer, for testing two accounts.

**Also since 0.0.4** (branches that didn't bump the version)
- USA Ultimate event schedules and brackets on tournament pages (`6f9e179`).
- Team chat rooms and direct messages (`bb69f04`).
- Notifications: push, in-app feed and settings (`106087f`).
- Team home pages, posts and team search (`d10353c`).
- Stat undo history, game and tournament delete, bigger player tiles
  (`96cc7b4`).

## 0.0.4 — UltiUP home, personal schedule, privacy by role

Branch `feature/ultiup-schedule`.

**Added**
- UltiUP branding: logo, wordmark and the Barlow Condensed heading font.
- Team-first Home: a "This week" outlook, your team (or a join/create card),
  a playbook preview, "Coming up" events with a USA Ultimate toggle, and a
  2-1-3 rankings podium with ranks 4–10 and division chips.
- Personal schedule: add your own events (same types as team events).
  Owners, coaches and captains choose which schedule a new event goes on.
- Schedule tab: a week at a time, day by day, with All / Team / Personal
  filters. Team events are blue and personal events purple, with tags.
- Swipe right on the Schedule tab to delete, with a 4-second Undo.
  Personal events always; team events only for owners, coaches and captains.
- Workout and Scrimmage event types.
- Search USA Ultimate teams from the Teams tab (ranked teams, filter by
  ranking list) and open a team's page.
- Light / Dark / System theme setting on Profile, remembered on the device.
- App version shown on Profile.

**Changed**
- Events tab shows USA Ultimate tournaments only; team and personal events
  moved to Schedule.
- Profile opens from the avatar on Home instead of the bottom bar.
- Event pages open over the current tab, so back returns where you were.

**Security and privacy**
- Players see only names, numbers and positions on the roster. Paid and
  USA Ultimate status moved to `teams/{id}/rosterStatus`, readable by
  owners, coaches and captains only.
- The team invite code moved off the team record to
  `teams/{id}/private/invite` (owners, coaches and captains only). Join
  proofs moved to `teams/{id}/joins/{uid}` so the code no longer lingers on
  the team record. Older teams are migrated the first time an admin opens
  them.
- Personal events in `users/{uid}/events`, private to their owner.

**Fixed**
- New-event pages had no way back; a stale Roster page could hijack event
  links; personal events didn't show on Home.

**Infrastructure**
- USA Ultimate scraping Cloud Functions set to run every two months, but
  left undeployed: the app scrapes live on the device until the user base
  grows.

## 0.0.3 — USA Ultimate roster import

Branch `feature/roster-import`.

- Link a team to its USA Ultimate page by searching the rankings or pasting
  the link.
- Preview a roster sync, then apply it: new players added, numbers and
  positions updated, players missing from USA Ultimate flagged. Nobody is
  removed; players are matched by name.
- On/Not on USAU and an admin-set Paid mark per player, a confirmed count
  and an "Unconfirmed only" filter.
- Team page parser updated for USA Ultimate's real layout.

## 0.0.2 — Live stats and team roles

Branch `feature/stats-mockup`.

- Stats tab: tournaments as folders of games, lines of 7, live O/D tracking
  with a pull timer, subs, timeouts and a point log.
- Stat sheets with O efficiency, break rate and ratings, plus a glossary;
  season stats.
- Roles: owner, coach, captain and player, with stats access as an add-on
  the owner grants to players. Owners can transfer ownership; only the
  owner sets roles and regenerates invite codes.

## 0.0.1 — Team calendar and animated plays

Branch `feature/team-calendar-animated-plays`.

- Team Schedule tab: month calendar and upcoming list; owners and coaches
  create, edit and delete events.
- RSVPs (Going / Maybe / Can't go) with a no-reply list, emoji reactions and
  optional single- or multi-choice polls. Only members going may react or
  vote.
- Playbook animation steps: drag players to record cuts and the disc to
  record throws, then play them back with scrubbing, speed and captions.

## 0.0.0 — MVP baseline

Branches `main` and `development`.

- Sign in with email/password, Google and Apple.
- Teams with a roster, members and invite codes.
- Playbook with a drawable field editor.
- USA Ultimate tournaments, rankings and team pages.
- iOS release setup through Codemagic; the web target was dropped.
