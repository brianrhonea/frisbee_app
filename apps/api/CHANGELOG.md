# Stall 10 API changelog

The API's version is `version` in `apps/api/package.json`. Bump it with
every change to the API (patch for fixes, minor for new endpoints or
behaviour, major once clients depend on a breaking change) and add an
entry here; `pnpm test` fails without one (`scripts/check-versions.mjs`).
The running version is in `GET /health` and in every response's
`x-stall10-api-version` header.

## 0.48.0 — 2026-11-24

- Hosting: `POST /v1/tournaments` takes `enterHost`. A team hosting an
  event that teams enter goes in, accepted and seeded, in the opened
  division matching its own (else the first), with the caller as captain.
  Groups and players' events ignore it; leagues check the team's fit.
- The host's own team has no fee (`teamFee` in shared): pay options say
  so, the Finish entry list and the payment reminder skip it.
- Paying confirms a spot: a team waiting on the host can pay once its
  roster reaches the division's minimum and its division has room
  (`teamPayProblem`; the pay options' reason says which), and a paid
  applied or waitlisted team is accepted and seeded while registration
  is open.
- `GET /v1/public/tournaments`: `spots` also has `divisions`, each open
  division's own spots left.
- Tournament chats: the Captains' channel holds only the captains picked
  with each team's roster (`captainIds`), not every team admin; a team's
  own thread with the organizers still has its admins.

## 0.47.1 — 2026-11-24

- Setting up payouts checks the recent sign-in before anything else, so a
  stale session can't even create the host's Stripe account. The answer
  (412) now says "confirm it's you", and the app and website ask for the
  password, Google or Apple right there.
- Deploy: `service.yaml` reads the Stripe key and both webhook secrets,
  the payout hold (`API_PAYOUT_HOLD_DAYS_<ENV>`) and the payment jobs'
  audience and invoker.

## 0.47.0 — 2026-11-23

Stall 10 collects every fee and pays hosts out (separate charges and
transfers). With app 0.0.51 and web 0.59.0.

- **Charges on Stall 10's account.** Checkout Sessions and PaymentIntents
  no longer use the host's account or an application fee; they carry
  `transfer_group: tournament_<id>` and the charge doc records
  `flow: "platform"`, the destination account and `released: false`.
  Charges made before this (no `flow`) keep the old direct-charge
  handling, so nothing is paid twice.
- **Payout accounts are recipients.** New accounts are Accounts v2 with
  `dashboard: "none"`, the `recipient` configuration (`stripe_transfers`)
  and Stall 10 as fees and losses collector. `payoutAccounts/{team}`
  gets `model: "recipient"`; hosts with an old account set up again
  (the old id is kept as `legacyAccount`).
- **Release.** Once the event is finished and its last day has passed,
  each paid fee is transferred to the host (`source_transaction` = the
  charge, idempotency key `transfer:<session>:<n>`), less anything the
  host owes. Runs when the event is set to finished, when a late payment
  succeeds, when the host's account becomes ready, when its earnings are
  read, and from the staff sweep `POST /v1/payments/release`. Stall 10's
  own events (official hosts) keep their fees.
- **Refunds.** `POST /v1/tournaments/:id/payments/:payerId/refund`
  (organizers or staff) refunds the fee only; service and processing
  fees aren't refunded. After release the transfer is reversed; what
  can't be reversed is owed and taken off the next payout.
- **Disputes.** `charge.dispute.created` marks the fee disputed and
  claws the transfer back; a won dispute (`charge.dispute.closed`) frees
  it again.
- **Earnings.** `GET /v1/teams/:teamId/earnings`: held, sent, refunded,
  disputed and owed totals with each fee.
- **Webhooks.** Platform events (charges, refunds, disputes) are signed
  with `STRIPE_PLATFORM_WEBHOOK_SECRET`, Connect events with
  `STRIPE_WEBHOOK_SECRET`; either verifies.
- Deleting an event is refused while it holds fees paid online.
- **Security (review, 2026-11-23).**
  - An organizer's refund of a fee already paid out to the host's bank
    is refused (it was paid from Stall 10's balance); staff can refund it,
    leaving it owed. A reversal counts as owed only on Stripe's
    insufficient-balance error (`InsufficientBalance`); any other failure
    is retried with the same key.
  - Payout hold: fees go out `PAYOUT_HOLD_DAYS` (default 3) after the
    server-stamped `finishedAt`, and never before the event's last day
    as it was when the fee was paid (`eventEndsAt` on the charge), so
    moving an event earlier doesn't pay out sooner.
  - Debt a fee paid off (`owedTakenCents`, now kept on the charge) comes
    back when that fee is refunded or disputed. A dispute won after a
    reversal that was left owed cancels the debt instead of paying the
    host twice; what was already recovered is sent back
    (`credit:<session>`).
  - A transfer is confirmed only by the run that planned it, and a fee
    refunded or disputed while its transfer went out is taken back.
  - Setting up or changing payouts needs a sign-in in the last 15
    minutes (`Caller.authTime`, `payoutsReauthMessage`).
  - Organizers can't mark a fee "Paid online through Stall 10" by hand,
    or change one that was, through either payments route
    (`paymentProblem` for hat signups too); a refund finds an earlier
    paid charge when a newer attempt is the latest.
  - Only `payment_status: "paid"` counts as paid.
  - Reopening an event clears `finishedAt` (clients must drop it too), so
    finishing again starts a new hold; the daily check waits for the
    hold before flagging `payout_overdue`, and flags `credit_unsent`.
  - Fraud checks: staff approve each host's first payout, and an event's
    payouts once their total to the host would pass $2,000
    (`charge.review`, `POST /v1/staff/payments/:session/approve`,
    `payoutAccounts.approvedAt`, `eventSent`, `approvedEvents`); organizers can't pay online for their
    own event (`selfPaymentMessage`); a fee paid after the event waits the
    hold from when it was paid.
  - Stripe forgets idempotency keys after 24 hours: a release planned over
    an hour ago is looked up (`findTransfer`, metadata `release`) before
    it's sent again, and a refund started before checks what Stripe
    already refunded.
  - A team holding fees, owed money or an unsent credit can't be deleted.
- **Registration window.** Registration opens at most 60 days before an
  event starts (`registrationWindowProblem` in packages/shared, the
  status route and moving an open event's date; Firestore rules too). The
  location can be added later; once registration is open, fees can be
  paid at any time.
- `docs/payments-security.md`: the design, invariants, threats and gaps.
- Failure simulation tests (`payments.test.ts`, "failure simulation"; see
  `docs/payments-failure-testing.md`). Found: a double-clicked refund
  could start twice; refunds now take a one-minute lock
  (`refundLease`), freed at once if the refund fails.
- **Oversight.** `GET /v1/staff/payments` (staff): open problems and the
  latest payments. `POST /v1/payments/reconcile` (staff) and the Cloud
  Scheduler jobs `POST /v1/jobs/payments/release` and `/reconcile`
  (Google OIDC from `JOBS_INVOKER` for `JOBS_AUDIENCE`): the daily check of
  every payment and transfer against Stripe (`src/payments/reconcile.ts`),
  recorded in `paymentIssues/{charge}` and `paymentChecks/latest`. New
  dependency `google-auth-library`.
- New payment log actions: `released`, `kept_by_stall10`,
  `transfer_reversed`, `owed_by_host`, `refund_started`, `refunded`,
  `refunded_on_stripe`, `dispute_won`.

## 0.46.0 — 2026-11-23

Tournament flow: respond, roster, deadline, seeds and publishing, director.

- `PUT /v1/tournaments/:id/entries/:teamId` answers `{ status }`. An
  invited team that accepts is in straight away (`accepted`, added to the
  division's seeds and captains), or `waitlisted` when the division is
  full; the organizer no longer accepts it a second time. The roster
  minimum is no longer checked here: it moved to the roster.
- `PUT /v1/tournaments/:id/entries/:teamId/roster` (team admins and
  captains): the players the team brings (from its roster, at least the
  division's minimum, up to 60), stored as `roster` and `rosterSetAt`;
  locked once the event is live.
- Declining an invite withdraws the entry with `reason: "declined"`;
  the reason is cleared if the team comes back.
- `GET /v1/teams/:teamId/tournament-invites` answers
  `{ invites, toFinish }`: `toFinish` lists the team's entries still
  missing a roster or fee before the event (`entryChecklist`).
- Tournaments store `entryDeadline` (rosters and fees due; must be by
  the start) and `director` (`{ uid?, name, email?, phone? }`; a member
  must be a real account). The fee's `dueAt` follows the deadline.
  Shared helpers: `effectiveDeadline`, `entryDeadlineProblem`,
  `entryChecklist`, `directorSchema` (fixtures/entry_checklist).
- `PUT .../divisions/:d/seeds` takes `confirm` and sets
  `seedsConfirmedAt`; changing the order (or a team joining or leaving
  the seeds) clears it.
- `PUT /v1/tournaments/:id/schedule`: publishes every division at once
  (each division's seeds must be confirmed) and makes the event
  `scheduled`.
- Deleting a tournament deletes its chats with the organizers first (the
  Captains' channel and team threads: their conversations and messages,
  so they leave everyone's inbox); the `tournamentDeleted` function then
  removes the chat pointers and attachments.
- Payments: `GET /v1/teams/:id/payouts` is readable by anyone who
  manages events (`canSetUp`, `ownerName`; only the owner sets it up).
  `POST /v1/teams/:id/payouts/session` (owner) answers an AccountSession
  client secret for Stripe's embedded onboarding.
- Visitors' tournament pages add `directorName` and `entryDeadline`
  (never the director's email or phone).

## 0.45.0 — 2026-11-22

- Tournaments store `inviteReplyDays` (null or 3/7/14/21/30). An invite's
  entry stores `replyBy` and `teamId`; accepting an invite past
  `replyBy` is refused (`failed_precondition`), and inviting a team
  whose invite expired invites it again.
- `GET /v1/teams/:teamId/tournament-invites` (team admins): the team's
  open invites, soonest first, with reply-by and expiry.
- `POST /v1/tournaments/:id/pay/intent`: the app's payment sheet, a
  direct-charge PaymentIntent on the host's account (automatic payment
  methods, Stall 10's application fee) for the amount from the
  tournament; reused while open, and it closes an open Checkout session
  first (and Checkout closes it), so a fee has one live payment. Charges
  gain `mode` (hosted, embedded, intent). The webhook handles
  `payment_intent.succeeded`, `.processing`, `.payment_failed` and
  `.canceled` for sheet charges on their own account only; the payer's
  status check asks Stripe about the intent too.
- Fees: the default platform fee is 3% (was 1% + $1), taken on the fee
  itself, and every online charge adds it and Stripe's card fee on top
  (`onlineCharge`), whatever `payerCoversFees` says, so the host gets the
  whole fee. Checkout's extra line is "Service and processing fees".
- `POST /v1/tournaments/:id/checkout` takes `ui: "embedded"` (Checkout
  inside the website, `ui_mode: embedded_page`) and returns
  `{url, clientSecret, account}`.

## 0.44.0 — 2026-11-22

- Hosts' Stripe accounts are made with Accounts v2 (`/v2/core/accounts`,
  merchant configuration with card and ACH Direct Debit payments; the
  host pays Stripe's fees, Stripe covers losses, full Dashboard), and
  onboarding links with v2 account links. Readiness is v2's
  `card_payments` capability status, not v1's `charges_enabled`.
- Checkout asks Stripe whether the host can still take cards first; if
  not, the host's payouts show as pending and the payer is told to pay
  another way (a Stripe outage doesn't block payments).

## 0.43.1 — 2026-11-22

- Names stored on teams, invites and join requests never fall back to
  the caller's email; "Player" instead (pentest P6).
- `sharp` 0.35.5 (libvips, libheif and librsvg advisories; pentest P2).

## 0.43.0 — 2026-11-22

With app 0.0.47 and web 0.56.0.

- Pickup communities and schools/clubs are created and edited without a
  division or level (`createTeamRequestSchema`, `editDetails`,
  `listingFor`); teams still need both.
- `GET`/`PUT`/`DELETE /v1/teams/:id/share` and
  `PUT /v1/teams/:id/share/members/:uid` (`teams/share.ts`): a team fee
  split among members, stored in `teams/{id}/private/share`.

## 0.42.0 — 2026-11-22

With app 0.0.46 and web 0.55.0.

- `GET` / `PUT /v1/me/agreement` (`account/`, `agreements.ts` in
  packages/shared): whether the caller has agreed to the current
  Community Guidelines and Terms (`termsVersion`), and recording that
  they have (`users/{uid}.agreedTerms = {version, at}`). An old version
  is refused (412). Both apps ask before anything else until it's yes.

## 0.41.0 — 2026-11-22

With app 0.0.45 and web 0.54.0.

- Tournament chats with the organizers (`src/tournament_chats`,
  `tournament_chats.ts` in packages/shared):
  `POST /v1/tournaments/:id/chats/captains` opens the Captains' channel
  (the host's organizers with manageEvents and the captains of every
  applied, accepted or waitlisted entry: its captainIds and the team's
  admins; invited teams join once they apply), and `POST /v1/tournaments/:id/chats/teams/:teamId` a
  team's private thread with the organizers. Each is a conversation of
  kind `tournament` (up to 500 people, organizers first) behind the
  server-only pointer `tournaments/{t}/chats/{captains | team_<id>}`,
  claimed in the same transaction, so two first opens share one. Each
  open recomputes who is in it, keeping names and read times (opening it
  from the inbox doesn't go through here). The
  conversation endpoints refuse adding, removing and renaming for them
  (they check kind `group`). Not while the tournament is a draft.
- `GET /v1/me/tag-tournaments`: the followed tournaments a post can be
  tagged "At" now, from 7 days before each starts to its last day
  (`tournamentTagOpen`); hosted from `tournaments/{id}` (not drafts),
  group ones from their `tournamentDirectory` listing. Soonest first.

## 0.40.0 — 2026-11-21

With app 0.0.44 and web 0.53.0. Never released before: payments were
built as 0.29.0 on `feature/payments` and renumbered on merging
`development`.

Online payments for tournament and league fees (Stripe Connect). Off
until `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` and
`PAYMENTS_RETURN_URL` (or `WEB_SITE_URL`) are set (DEPLOY.md,
"Payments"); without them the routes below say payments aren't set up.

**Added**
- `GET /v1/teams/:id/payouts` and `POST /v1/teams/:id/payouts/link`: the
  host's owner connects a Stripe account (made once per team; the host
  pays Stripe's fees, Stripe covers losses, full Dashboard) and gets a
  single-use onboarding link back to the website's `/payments/payouts`.
- `GET /v1/tournaments/:id/pay[?team=]` and `POST
  /v1/tournaments/:id/checkout`: whether the caller can pay a team's bid
  or spot fee (the team's admins) or their own entry fee (a signed-up
  player) online, and a Stripe Checkout session for it: a direct charge
  on the host's account with Stall 10's fee (`PLATFORM_FEE_BPS`,
  `PLATFORM_FEE_FIXED_CENTS`, 1% + $1 by default) as the application
  fee. The amount comes from the tournament, never the request.
- `POST /v1/payments/stripe/webhook` (Connect endpoint, signed, raw
  body, each event handled once): a completed payment marks
  `tournaments/{id}/payments/{payer}` paid with the host's own three
  fields; a second payment for something already paid is refunded in
  full; a full refund in the host's Dashboard un-marks it (unless the
  host has since marked it by hand) and refunds Stall 10's fee; expired
  sessions, disputes and account updates are recorded.
- Server-only collections, outside tournaments so deletions keep the
  money records: `payoutAccounts`, `stripeAccounts`, `charges`,
  `stripePayments`, `stripeEvents`. No client rules match them.
- The `stripe` SDK (23.1.0).
- `GET /v1/payments/fees` (signed in): Stall 10's fee and Stripe's
  estimated card fee (2.9% + 30¢, `stripeCardFeeEstimate`), so hosts see
  what reaches them of a fee paid online while they set the price.
  `feeBreakdown` in `@stall10/shared` does the arithmetic.
- Payers covering the fees: a fee's `payerCoversFees` (tournament save
  and the Firestore rule) charges the payer enough that the host gets the
  whole fee (`chargeCoveringFees`, Stripe's card rate), as a separate
  "Processing fee" line on Checkout, the same for every payment method.
  `PayOptions` gains `chargeCents`, `processingCents` and `pending`.
- Bank payments: new host accounts request
  `us_bank_account_ach_payments`; a bank payment's charge is `processing`
  until `checkout.session.async_payment_succeeded` or `_failed` (now
  handled: the payer can pay again). Add `async_payment_failed` to the
  webhook's events (DEPLOY.md).
- Lost connections: `payerCharges/{tournament}~{payer}` keeps the payer's
  latest session. Pay again reuses an open one (a fresh one, after
  expiring the old, when the fee changed or it has under 10 minutes
  left); `GET .../pay` asks Stripe about it first, so a payer back from
  Stripe sees it paid (or processing) before the webhook arrives. The
  webhook and that check share one idempotent settle path; if Stripe
  doesn't answer, the stored state stands.
- Paying another way: `PUT /v1/tournaments/:id/pay/offline` lets the
  payer say they'll pay by check, PO or the host's own way (or take it
  back); the payment record's `offlineAt` (allowed by the rule, kept by
  every mark) and `PayOptions.offlineAt` show it.
- `PUT /v1/tournaments/:id/payments/:payerId`: the host marks a team's or
  player's fee paid or unpaid with a note ("Check #1042"); the website's
  way to mark teams' bid fees, and the app's when the API is there.
- The payment history: `paymentLog/{id}` (server only, never changed or
  deleted, kept when a tournament goes) records every step with who, when,
  amount and Stripe's ids: checkout started, paid online, bank payment
  processing or failed, expired, duplicate and its refund, the host's
  refunds (full or part) and disputes, the host's marks with notes, and
  the payer's "paying another way". `src/payments/log.ts`.

## 0.39.0 — 2026-11-21

With app 0.0.43 and web 0.52.0. Needs the Firestore rules and the
`notifications` functions from the same commit.

**Added**
- Repeating events (`packages/shared` `recurrence.ts`): `POST
  /v1/teams/:teamId/events` and `POST /v1/calendars/:id/events` take
  `repeat` (`{ freq: daily | weekly | biweekly | monthly, until:
  YYYY-MM-DD }`) and `timeZone` (IANA). The series is written as one event
  per occurrence, ids `${seriesId}_${index}`, each with `series` (`id`,
  `index`, `count`, `freq`, `until`), at the same wall-clock time in that
  zone across clock changes. At most 100 events and a year; refused with
  400 otherwise. Returns the first event's id.
- `?scope=following` on `PATCH` and `DELETE` of a team or calendar event:
  it and every later event in its series. An edit applies the same
  details and the same change of date and time to each one, keeping each
  one's RSVPs. Team bulk writes stamp `seriesWrite` so the change
  notification goes out once.
- `series` on `CalendarEvent` (`GET /v1/me/calendar-events` and
  `GET /v1/calendars/:id/events/:eventId`).

## 0.38.0 — 2026-11-20

With app 0.0.42 and web 0.51.0. Needs the Vision API on in the project
(`vision.googleapis.com`; on in dev) and the `api` functions from the
same commit (the backstop for older app builds).

**Added**
- Word filter (`packages/shared` `word_filter.ts`, `clean()` in the
  request schemas): every free-text field people write (posts, comments,
  chat and direct messages, group and room names, team posts, events,
  polls, RSVP notes, videos, meetings, profile details, names, teams,
  tournaments) refuses slurs, hate terms and "kill yourself" with 400
  and `blockedWordsMessage`, and saves mild swearing masked (`f***`).
- Photo checks: each photo upload's compressed image goes to Cloud Vision
  SafeSearch (`media/vision.ts`); `isUnsafeImage` (adult likely, racy or
  violence very likely) refuses it with `unsafeImageMessage` and nothing
  is saved. If Vision fails the photo is let through and logged. Off with
  the emulators or `SAFE_SEARCH=off`; locally it needs
  `GOOGLE_CLOUD_QUOTA_PROJECT`.
- Files the API writes carry `stall10Checked` metadata, so the functions'
  photo backstop skips them.

## 0.37.0 — 2026-11-20

With app 0.0.41 and web 0.50.0. Needs the `firestore.rules` from the same
commit (blocks, suspended accounts, `reports` server-only) and the
`account` functions (deleting an account removes the other person's block
record).

**Added**
- Reports (App Store guideline 1.2): `POST /v1/reports` (30 a day) for a
  post, comment, team post or comment, team message, direct message or
  person, with a reason, optional details and `block`. One report per
  person per thing (`reports/{id}`, id from reporter and content path),
  with a snapshot of the text and photos. Team kinds also go to the team.
- Team queue: `GET /v1/teams/:teamId/reports` and
  `POST /v1/teams/:teamId/reports/:reportId` (`remove` or `dismiss`) for
  the owner and members with `moderate` or `manageTeam`.
- Staff queue: `GET /v1/me/moderation`, `GET /v1/staff/reports`,
  `POST /v1/staff/reports/:reportId` (`remove`, `dismiss`, `warn`,
  `suspend`, `unsuspend`) for accounts with the `staff` claim
  (`firebase/scripts/set-staff.mjs`, which also writes `staff/{uid}` for
  the profile badge). Suspending sets
  `limits/{uid}.suspended`, disables sign-in and revokes tokens; warning
  sends a notification linking the community guidelines.
- Blocks: `GET /v1/me/blocks`, `PUT`/`DELETE /v1/me/blocks/:uid`. Written
  to both people (`users/{uid}/blocks/{other}`, `mine` on the blocker's);
  blocking removes follows and follow requests both ways.
- Data export includes the people you blocked and the reports you made.

**Changed**
- Blocked people can't follow, accept a follow request, start or send a
  direct message, add each other to a group, like, repost or comment on
  each other's posts. Suspended accounts can't post, comment or message
  (`checkNotMuted`).

## 0.36.0 — 2026-11-20

With app 0.0.39 and web 0.48.0.

**Changed**
- Chat reactions (`PUT .../messages/:messageId/reaction` for team rooms
  and conversations) take any one emoji (`isChatReaction` in
  `packages/shared`), not only the website's old list of eight, so the
  app's quick reactions and the emoji picker's choices are accepted.
  Anything else is still 400.

## 0.35.0 — 2026-11-20

Redesign features, second batch, with app 0.0.38 and web 0.47.0.
Details in `docs/product-spec.md` §8.1 items 35–44.

**Added**
- Video notes, clips and comments: `POST /v1/teams/:id/videos/:videoId/comments`,
  `DELETE .../comments/:commentId` (author or manageTeam); `PUT
  .../videos/:videoId/event` tags a video to a team event (`{eventId |
  null}`). Removing a video deletes its comments.
- Roster lines: `PUT /v1/teams/:id/roster-lines` (manageTeam, teams
  only). Pending invites: `GET /v1/teams/:id/invites`, `DELETE
  /v1/teams/:id/invites/:uid`; invites now record `teamId`.
- Chat polls: `POST /v1/teams/:id/chats/:roomId/polls`, `PUT
  .../messages/:messageId/vote`, `POST .../messages/:messageId/close-poll`.
- Team posts: `PUT|DELETE /v1/teams/:id/posts/:postId/pin` (up to 3,
  swap), `POST /v1/teams/:id/posts/:postId/comments`, `DELETE
  .../comments/:commentId`. Public team pages list pinned posts first
  with `pinnedAt`.
- Permissions: `PUT /v1/teams/:id/members/:uid/permissions` (owner;
  `memberGrants`, included in `memberPerms`).
- Team join requests: `PUT /v1/teams/:id/allow-join-requests`; the
  existing join-request endpoints now serve teams that allow them, with
  the club age rule at request and approval.

**Changed**
- Download your data adds video notes/comments (with team, video and
  times), poll votes and polls posted, roster lines, and waiting join
  requests.
- Reply quotes of a poll say "📊 question".

## 0.34.0 — 2026-11-20

Redesign features, with app 0.0.37 and web 0.46.0. Details in
`docs/product-spec.md` §8.1 items 26–34.

**Added**
- Live running scores: `POST`/`DELETE
  /v1/tournaments/:id/divisions/:divisionId/games/:gameId/live`
  (either team's captain or the host's event managers, on the game's
  day, scheduled games only). Public games carry `live`; public list
  cards carry `liveGames` (updated in the last 3 hours).
- `PUT /v1/teams/:id/sections` (owner): Playbook, Videos, Stats,
  Meetings switches; new teams start with them off.
- `PUT /v1/teams/:id/public-page` (manageTeam): `publicPage: false` on
  the team and its listing; off, outsiders get the card only and its
  hosted events and rankings leave the public lists.
- Team rooms: `PUT|DELETE .../messages/:id/pin` (up to 10 a room, swap
  on the 11th) and `POST .../event-shares` (event card messages).
- `GET /v1/me/export`: the caller's own data as a JSON attachment, once
  per 10 minutes (`limits/{uid}.exportedAt`).
- `spots` on public tournament list cards (each division's cap less its
  accepted teams) while registration is open.

**Changed**
- RSVPs to team events and meetings take an optional `note` (140
  characters; left out keeps it, taking the answer back removes it).
- Plays take `kind` (`play` | `whiteboard`) and `drawings`; a save that
  leaves them out keeps the stored ones.

## 0.33.0 — 2026-11-19

**Added**
- `PUT /v1/teams/:teamId/chats/:roomId/read`: marks a room read for the
  caller (`users/{uid}/chatReads/{teamId}`, `rooms.{roomId}`), only in
  rooms they can read.

**Changed**
- Sending a team chat message also stamps the room's `lastAt` (a time,
  never the text) and marks the room read for the sender, in the same
  transaction.

## 0.32.0 — 2026-11-19

**Added**
- Profiles (`/v1/players/:uid`, `profileView`) include `teamStats` (team
  id → season → totals) when the player shows both stats and teams.
  `PUT /v1/me/profile/visibility` deletes it when either is hidden, and
  making a profile private moves it with the rest (`privateProfileFields`).

## 0.31.1 — 2026-11-19

**Changed**
- Error messages say "community" where they said "group" (hat
  tournaments, joining one that needs approval, its events and roster),
  matching the app 0.0.30 and website 0.40.0 wording. Group messages
  keep "group".

## 0.31.0 — 2026-11-17

Private profiles' posts (security review S1).

**Changed**
- `POST /v1/posts` and `PUT /v1/posts/:id/repost` stamp `private` on the
  new post from the author's profile (the `follows` functions keep it in
  step when a profile turns private or public).
- Liking a post, commenting on it and liking its comments check what the
  rules' `canSeePost` does: a private post is for its author and accepted
  followers only (403 otherwise; a repost and its original both count).
- A private profile's post can't be reposted (412), and `GET
  /v1/posts/state` says `canRepost: false` for one (unless already
  reposted, so it can be taken back).

## 0.30.0 — 2026-11-16

The offline queue's comments. Deploy before web 0.38.0, which sends an
`id` with every new comment (older clients don't, and keep working).
0.29.0 is the payments branch's.

**Changed**
- `POST /v1/posts/:id/comments` takes an optional `id` (the app or site
  picks it when the member sends), so a comment resent from the offline
  queue is never posted twice: a second send with the same id answers
  409 `already_exists`.

## 0.28.0 — 2026-11-16

Public rankings. Deploy before web 0.33.0 and with the `rankings`
functions group.

**Added**
- `GET /v1/public/rankings`: team rankings for visitors, no token. Never
  youth (no youth rankings, youth teams, private groups or drafted
  league teams); rank, team, rating and record only. Visitor limit,
  cached 5 minutes.

**Changed**
- `GET /v1/teams/:id/roster`: a team in a youth division of a league is
  members-only too (and its school or club's member managers), whatever
  level its team doc says.

## 0.27.0 — 2026-11-15

Club teams are for players 16 and over. Deploy with (or before) the new
`firestore.rules`; needs `PERSONAL_DETAILS_KMS_KEY`.

**Added**
- Joining a club team (code, link or invite) or starting one
  (`POST /v1/teams`, a team made inside a community) needs the player to
  be 16 that day, read from their encrypted personal details
  (`PersonalService.birthDate`, never returned). No date of birth on file
  → 412 "Add your date of birth in About you to join a club team.";
  under 16 → 412 "Club teams are for players 16 and over."; no
  personal-details key → 503.
- Invites can still be sent to anyone; people already on a club team
  stay. `clubMinimumAge`, `canJoinClubTeam` and `isClubTeam` (a team
  with level club, or no level) are in `@stall10/shared`.
- `PUT /v1/me/personal/birth-date` keeps an email sign-up's birthday,
  encrypted like the rest of the personal details, until "About you" is
  saved: under 13 refused, never completes the details, refused (409)
  once they're saved, 5 a minute / 20 a day. `GET /v1/me/personal`
  returns it as `signUpBirthDate` until the details are given; it counts
  as "on file" for the club rule.

## 0.26.0 — 2026-11-15

Public reads for signed-out website visitors. Deploy before web 0.31.0.

**Added**
- `GET /v1/public/teams?q=`: a team finder that returns team and group
  listings by name, never players.
- `GET /v1/public/teams/:id/roster`: an adult team's roster for anyone
  (names, numbers and positions, plus a public profile's username and
  photo). Youth teams, teams without a level and groups answer 404.
  `rosterIsPublic` in `@stall10/shared` decides, checked on both the
  team and its listing.
- `GET /v1/public/tournaments`, `/v1/public/tournaments/:id?division=`
  and `/v1/public/group-tournaments/:groupId/:id`: published tournaments
  and leagues (overview, divisions, accepted teams, one division's
  schedule and scores) and a group tournament's listing. Drafts and
  private groups' events are 404. No captains, signups, fee
  instructions or player names; drafted teams always show as "Team N".
  Cached publicly for 30 seconds, and in each instance for 30 seconds
  (at most 200 events, the games by the division they resolve to).

**Changed**
- `GET /v1/public/events` is public (no token, limited by IP, publicly
  cacheable). Its tournament listings carry only their seven public
  fields.
- Youth teams' rosters (`GET /v1/teams/:id/roster`) are for their members
  and the member managers of the school or club community that accepted
  them; anyone else gets 403 "Rosters of youth teams are private: only
  members see them." Adult teams are unchanged.
- League teams drafted from a youth division are youth teams (team and
  listing `level: "youth"`), as in the functions' copy.

**Security** (visitor routes review)
- Visitors are limited by `req.ip` (only the trusted proxy hops,
  TRUST_PROXY_HOPS), never the X-Forwarded-For first hop a client
  writes, so a spoofed header gets no fresh bucket and can't spend or
  mute another address's.
- A youth team shows visitors its card only: no posts, events or
  location on its page, in `/v1/public/events` or in the finder.
- Public team posts no longer carry `authorId`; `authorName` only when
  the author's profile is public (one batched read).
- Private-group checks read the team doc too (kind, requiresApproval,
  level; a field mask): a missing team doc, or one that disagrees with
  its listing, counts as private.
- Visitor photo URLs only from this project's Storage buckets
  (STORAGE_BUCKET, `<project>.firebasestorage.app`,
  `<project>.appspot.com`) or `lh3.googleusercontent.com`.
- A league's drafted teams (`league_…`) are out of the finder, show as
  "League team" on their page and in events, and their public roster is
  404; so is the roster of a team in a league's youth division. Entrants
  that are drafted teams show as "Team N" (or "Team N (drafted)" beside a
  real team of that name).
- A public roster spot linked to a private profile, or one that hides
  its teams, shows as "Player" with its number and position only.
- `firebase/scripts/backfill-youth-league-teams.mjs` (dry run by
  default) sets `level: "youth"` on existing youth league teams and their
  listings.

## 0.25.1 — 2026-11-15

Clean-up; no behaviour change for clients.

**Changed**
- One tournament engine: `groupEngine` in `@stall10/shared` is now a thin
  adapter over `tournament_engine.ts` (about 550 duplicated lines gone).
- One set of room and event access checks: media rooms and the home feed
  use `hub/access.ts`; `audienceTier` (shared) is the one place a "stats"
  member counts as a player.
- Shared helpers replace copies: `parseBody`, `limited()`/`tooFast()`,
  `clip`/`clipText`, `mapOf`/`isMap`, `storedId`/`isDocId`; `ChatAdmin` is
  built once.
- Removed unused shared exports and 27 unused request/input type aliases.
- A test checks that the API's browse and Discord copies stay in step with
  `firebase/functions`.

## 0.25.0 — 2026-11-15

Review checklist fixes. Deploy with web 0.29.0: hosted game confirm now
needs the score in its body.

**Changed**
- Hosted game confirm requires the `{scoreA, scoreB}` being confirmed and
  refuses (412) if the report changed meanwhile (the rules' check, ported).
- A team that hosts an unfinished tournament or league can't be deleted
  (412); finished ones stay, read-only.
- Videos outside chat are refused until the transcode job ships (chat
  videos still work).
- Dates must carry Z or an offset (`isoDateTime` in `@stall10/shared`).
- New `unavailable` (503) error code; Discord being unreachable uses it.
  A missing team's Discord preview answers not_found.
- Read rate limits per member: roster 60/min, post states 120/min,
  calendars 60/min, calendar events 60/min. Roster cards use one batched
  read.

**Fixed**
- The home feed no longer drops posts when every source is short.
- Home upcoming events include ones under way and aren't emptied by the
  audience filter.
- Uploads: a delete during complete wins, and two completes can't both run.
- Reconcile reads only the division's entries and the games it fills;
  closing a division removes all its games.
- Drafts and Discord imports re-check inside their transactions.
- Saving a finished group tournament keeps it finished.
- Roster-link refusals say why.
- The test fake store refuses reads after writes, as Firestore does.

## 0.24.0 — 2026-11-15

**Added** (security review of the messaging batch)
- A daily chat-upload quota per member: 200 files asked for and 2 GB
  received per UTC day (`uploadQuotas/{uid}`; a retried complete is
  charged once).
- `DELETE /v1/uploads/:id`: the owner removes an unsent chat file (raw,
  stored and thumbnail); refused once a message holds it.

**Fixed**
- Completing an upload checks and copies one generation of the raw file,
  then re-checks the copy's size, so the bytes can't be swapped after the
  check.
- Direct-message uploads need the conversation to exist and list the
  caller.
- In chat, an MP4/MOV with an unlisted ftyp brand counts as video when
  declared or named as one.
- Upload names are cleaned of control and bidi characters, and `/` `\`
  become `_`.

## 0.23.1 — 2026-11-15

**Fixed** (shared test vectors with the app)
- Discord import into a community's teams orders community roles tied on
  position by name as the app does (which new role id goes to which role).
- The roster's players are ordered as the app orders them: by number (none
  counts as 1000), then name compared exactly.
- Tests read the shared Discord template (`packages/shared/fixtures`) and
  check the whole parsed plan.

## 0.23.0 — 2026-11-15

**Changed**
- Chat uploads (`/v1/uploads`, team rooms and DMs) take any file, as the
  app does: the app's document types or `application/octet-stream`
  (never HTML, SVG or script), with the file's `name` kept. Chat videos
  and files are stored as sent at the app's paths
  (`{folder}/{uploadId}-{safeName}`, so storage.rules still apply),
  within its limits (10 MB, or 100 MB for a video), and no longer wait on
  the transcode job. Chat photos are still compressed. Anything whose
  bytes don't confirm a photo or video is stored as
  `application/octet-stream`.

## 0.22.1 — 2026-11-15

**Fixed** (security review of the small-fixes batch)
- Sharing a team event refuses a private group's events (412), as both
  apps' editors already hide it; before, a schedule manager could post
  one by calling the API directly.
- `webRoute` (`@stall10/shared`) only maps id segments of letters,
  digits, `_`, `-` and inner dots, so a stored notification route with
  `..`, a backslash or `%2e` can't open another page of the site.

## 0.22.0 — 2026-11-15

**Added**
- `POST /v1/posts` `shareEvent` takes an optional `calendarId`, so My
  calendar and shared-calendar events can be shared with followers, as
  in the app. Only the calendar's owner and editors share; viewers get
  403, non-members and pending invitees 404; it can't be sent with
  `teamId`. The stored copy keeps `validSharedEvent`'s keys.
- `@stall10/shared`: the app's password policy (`password.ts`) and app
  routes for tournaments, drafts, plays, videos, stats and meetings in
  `webRoute`.

## 0.21.1 — 2026-11-15

**Fixed** (security review of the meetings and posts slices)
- `GET /v1/me/home`: every feed post goes through the privacy check,
  including the caller's own and followed people's, so a followed
  person's repost of a private stranger's post no longer shows it.
- The home feed reads at most 300 followed people and 300 followed
  tournaments (`followReadLimit`), and `/v1/me/home` (60/min),
  `/v1/players/:uid` and `/v1/posts/:id` (120/min) are rate-limited per
  member.
- Discord import: plan keys can't be `__proto__`, `constructor` or other
  Object.prototype names, and key lookups only read own properties.
- Discord import: moving rooms to linked teams never deletes the
  community's General room (it used to fail partway after the import).
- Meeting and voice tokens are sent with `cache-control: no-store`.

## 0.21.0 — 2026-11-14

**Added**
- Team posts take a `tournamentKey` for one of the team's tournaments or
  leagues, so hosts post event news.
- Discord import: `POST /v1/teams/:id/discord/preview` (a port of the
  `discord-previewTemplate` callable: owner only, discord.com only, 10 s
  timeout, no redirects, 2 MB cap) and `POST /v1/teams/:id/discord/import`
  (the roles, folders and rooms the app adds, including community splits
  with role copies; the server re-runs the mapping on the stored team).
- `/v1/me/home` adds posts tagged with followed tournaments and events
  shared from the member's teams.
- `POST`/`PATCH /v1/posts` take an "At a tournament" tag, and `POST` can
  share a team event or one from your own schedule (details copied from
  the stored event).

## 0.20.1 — 2026-11-14

**Fixed** (security review of 0.14.0–0.19.0)
- League teams: a team already at a league team's id is kept only if the
  league made it (league, host and captain match); otherwise creating
  teams fails with 412. The rules now refuse client-made team ids that
  start with `league_`, and drafted-team ids can't start with it either.
  The `createLeagueTeams` callable has the same check.
- Deleting a stats tournament or a video folder, and reading group or
  hosted tournament games, query only ids or the fields needed
  (`DocQueries`), with no caps on how many there are.
- Hosted and group tournament operations check permission before reading
  games, entries or divisions; group `advance` refuses people not playing.
- Publishing a schedule is limited to 5 a minute and 50 a day, reconcile
  to 20 a minute, and failed draft picks and controls count toward the
  any-write limit.
- Group tournament listings must belong to the same group and tournament;
  delete removes only the tournament's own listing.
- Deleting a tournament removes every subcollection, however large,
  checking permission on each batch; removing a division deletes all its
  games.
- Stats games up to the 900 KB limit and hosted schedules up to 2,100
  games are accepted (per-route body limits).
- Playbook permission checks run inside the write transaction; failed
  video file deletes are logged.

## 0.20.0 — 2026-11-14

**Added**
- Meeting and voice channel tokens:
  `POST /v1/teams/:teamId/meetings/:meetingId/token` and
  `POST /v1/teams/:teamId/voice-rooms/:roomId/token`, ports of the
  `meetings-joinToken` and `meetings-voiceToken` callables (same checks,
  grants, messages and 6 h lifetime), 30 a minute per caller. They answer
  412 until `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` are
  set (see DEPLOY.md).
- Meetings (`/v1/teams/:teamId/meetings`): schedule, edit, cancel, RSVP,
  start and end; join requests (ask, take back, let in or turn away);
  watch together state (`playback/current`, 60 a minute); the call's chat.
  Each ports the `match /meetings` rules.

## 0.19.0 — 2026-11-14

**Added**
- Hosted tournaments and leagues (`/v1/tournaments`): create, edit,
  publish and delete events; status steps; divisions; seeds; team
  entries with the host's approval, invites and captains; publishing the
  schedule; captains report and confirm scores and the host sets final
  scores; seeding the bracket; and a host-only reconcile (bracket
  catch-up, going live, final places, withdrawn teams, captains).
- Every conjunct of the tournament rules is ported, with one test each;
  the scheduling engine is shared (`packages/shared/src/tournament_engine.ts`).

## 0.18.0 — 2026-11-14

**Added**
- Group tournaments (`/v1/teams/:teamId/group-tournaments`): create,
  save, publish (the server builds the schedule with the app's engine,
  ported to `packages/shared`), delete, report, confirm and set scores,
  seed the bracket from pool standings, and catch up bracket moves.
- Every conjunct of the `groupTournaments`, `games` and
  `tournamentDirectory` rules is ported; the tournament's public listing
  is kept in step.

## 0.17.0 — 2026-11-14

**Added**
- Team stats: create, save whole and delete stats games
  (`/v1/teams/:teamId/stats-games`) and stats tournaments
  (`.../stats-tournaments`); deleting a tournament deletes its games.
- Roster spots (`.../roster-players`): admins add, edit (with the paid
  mark) and remove them; members claim or let go of their own spot
  (`PUT .../roster-players/:id/link`).
- Every conjunct of the statsGames, statsTournaments, roster and
  rosterStatus rules is ported, with bounds on nested game shapes and
  size. Stats writes have their own limit of 90 a minute per member.

## 0.16.0 — 2026-11-14

**Added**
- Player signups: sign up, edit, sign back up, withdraw; the host's
  accept, waitlist and decline, and marking a player's fee paid
  (`/v1/tournaments/:id/signups/...`), ports of the signups and payments
  rules.
- Saving a division's drafted teams (`PUT .../divisions/:d/drafted-teams`):
  the division rule plus the app's pre-save checks.
- The captains' draft: start, pick, control (pause, resume, undo,
  autopick, cancel) and finish, ports of the `startDraft`, `draftPick`,
  `draftControl` and `finishDraft` callables; and creating a league's
  teams from its drafted teams, a port of `createLeagueTeams`. The app
  keeps the callables until it switches.
- Draft writes have their own buckets (picks and controls 240 a minute,
  signup decisions 120, other draft writes 30); picks and controls skip
  the 120-a-minute any-write count so a host can auto-pick a full draft.

## 0.15.0 — 2026-11-14

**Added**
- Team videos: `POST/PATCH/DELETE /v1/teams/:teamId/videos[/:videoId]`
  add YouTube videos, edit them, move them between folders and remove
  them (an uploaded video's file is deleted too, only from its own
  folder).
- Video folders: `POST/PATCH/DELETE /v1/teams/:teamId/video-folders[/:folderId]`;
  deleting a folder moves its videos to Unsorted first, as the app does.
- The `videos` and `videoFolders` rules are ported whole (`validVideo`,
  `validFile` on the resulting document), on the hub write limit.

## 0.14.1 — 2026-11-14

**Fixed** (security review of 0.11.0–0.13.0)
- `DELETE /v1/teams/:teamId` now checks everything the rule checks:
  `ownerId` must be the caller (a `members` entry of "owner" is no longer
  enough), the owner must be the only member (412 until the others are
  removed or it's handed over), and a team that plays in an unfinished
  league can't be deleted. Stored community and linked-team ids are
  checked before they're used in paths.
- Notification settings: at most 200 teams with their own settings (the
  rules' cap); resetting a team now really removes its settings (it used
  a merge, which kept the key).
- `PUT /v1/me/identity` refuses one upload for both pictures, and an
  unreadable old picture URL no longer fails the request after saving.
- Visitors' profile views only pass on pictures from Firebase Storage or
  Google, so a profile can't point visitors' browsers at another server.
- Chat folder ids refuse `.`, `..` and Firestore's reserved names; failed
  file clean-ups after deleting a team or room are logged.
- Test fakes: `merge` now merges nested maps as Firestore does.

## 0.14.0 — 2026-11-14

**Added**
- Team playbooks: `POST /v1/teams/:teamId/plays`, `PUT` and `DELETE
  /v1/teams/:teamId/plays/:playId` (`apps/api/src/playbook`), the plays
  rule ported. Members who manage the team save whole plays, checked by
  `savePlayRequestSchema` (pieces, arrows, steps, their limits, and steps
  only moving pieces on the field); `updatedBy` is the caller.

## 0.13.0 — 2026-11-14

**Added**
- `PUT /v1/conversations/:id/typing`: a participant marks or clears their
  typing (`conversations/{id}/typing/{uid}`, as the typing rule).
- `PUT /v1/me/read-receipts`: `users/{uid}.readReceipts`.

## 0.12.0 — 2026-11-14

Team admin for the website on its own.

**Added**
- Chat rooms and folders (`src/hub/rooms.ts`, ports of the `chats` and
  `chatFolders` rules, manageChats): `POST|PATCH|DELETE
  /v1/teams/:teamId/chat-rooms[/:roomId]`, `POST|PATCH|DELETE
  .../chat-folders[/:folderId]` and `PUT .../chat-layout` (order and
  folders). Access lists are capped as the rules cap them, writers must
  be readers, and single members must be on the team. A room's kind never
  changes; General can't be deleted; a deleted room takes its messages
  and files, and only someone who can read it may delete it. A deleted
  folder's rooms move out of it.
- `DELETE /v1/teams/:teamId`: the owner deletes a team, group or
  community, typing its name (checked here too). As the app's deleteTeam:
  `deletingAt` first, then every document under the team
  (`recursiveDelete`), its Storage folder, its directory listing and its
  tournaments' listings. It also leaves its community's list, and a
  deleted community's teams are freed.

## 0.11.0 — 2026-11-14

The member's own account, for the website on its own.

**Added**
- `PUT /v1/me/identity`: change your name, profile picture and header
  photo (`src/account`). The name and picture go on the Auth record (what
  the app reads), `users/{uid}` and the profile's directory fields with
  fresh search keywords; the header on the profile. Pictures are the
  caller's own finished `avatar` uploads, given a lasting download URL
  (`MediaStorage.downloadUrl`); replaced or removed ones are deleted, and
  only from the caller's own `users/{uid}/profile/` folder.
- Notification settings (`users/{uid}/settings/notifications`, as the
  app's NotificationPreferences): `PUT /v1/me/notification-settings/category`
  (a kind for every team, or a per-team kind for one team), `DELETE
  .../teams/:teamId` (back to the defaults), `PUT .../mute` (one team chat
  room or conversation; at most 500).
- Player profiles' card includes `headerUrl` (shown even when private, as
  in the app), here and in the `browse` functions.

## 0.10.0 — 2026-11-14

Website parity (`docs/product-spec.md` §8.1) and visitors limited to team
and community pages. Needs the `browse` functions from the same change
for the Flutter web site.

**Added**
- Team hub writes (`src/hub`), each re-checking its Firestore rule in a
  transaction, with zod schemas in `packages/shared/src/hub.ts`:
  - Team posts: `POST /v1/teams/:teamId/posts`, `PATCH|DELETE
    .../posts/:postId` (manageTeam; words or a photo, 5 links, 4 photos
    from the caller's `teamImage` uploads for this team and post).
  - Team events: `POST /v1/teams/:teamId/events`, `PATCH|DELETE
    .../events/:eventId` (manageEvents; validEvent, a community's
    audience, the `publicEvents` copy kept in step, votes reset when the
    poll changes; a hosted tournament's event keeps its link).
  - Answers: `PUT .../events/:eventId/rsvp`, `/reaction`, `/votes`
    (members who see the event change only their own entries; reactions
    and votes only while going; votes must be poll options).
  - Team chat: `POST /v1/teams/:teamId/chats/:roomId/messages` (members who
    may write in the room, not muted; attachments from the caller's
    `chat` uploads for this room and message; a reply's quote is copied
    from the room by the server), `PUT .../messages/:id/reaction` (one of
    the offered emoji, as the caller) and `DELETE .../messages/:id`
    (authors, the owner, and moderators or chat managers who can read the
    room).
- Direct and group messages (`src/messages`, schemas in
  `packages/shared/src/messages.ts`), porting the conversations rules:
  `POST /v1/conversations` (straight to their inbox if they follow you,
  else a request where their message policy allows one, else refused),
  `POST /v1/conversations/groups`, `PATCH /v1/conversations/:id` (rename),
  `POST|DELETE .../members` (only people who follow the adder and take
  messages, up to 10; leave, or the creator takes someone out),
  `POST .../messages` (with the inbox preview and the sender's read time;
  not while a request waits on the sender; attachments from `chat`
  uploads for this conversation and message), `PUT|DELETE
  .../messages/:id` (react; authors delete), `POST .../read` (their read
  time, and the shared receipt unless turned off or a request waits on
  them), `PUT .../request` (accept or decline), `PUT .../archive` and
  `POST .../clear`. Outsiders get 404 for every conversation.
- A per-member, per-instance write limit on those routes
  (`MemoryRateLimiter`: 30 posts/events, 60 messages and 120 answers a
  minute), a first step on security review S9.
- Author names on these writes never fall back to an email (review S2).

**Changed**
- `GET /v1/public/players/:uid`, `/v1/public/events` and
  `/v1/public/search` need a signed-in caller (401 otherwise, even with
  the website's server key) and App Check like other member routes, are
  limited per uid in memory (so heavy browsing can't trip the shared
  mute on chat and posts), and answer `cache-control: private, no-store`.
  The feed, posts and team pages stay open to visitors.
- Every signed-in write is rate limited per caller (120 a minute, in
  memory per instance; `src/limits/writes.ts`), with tighter limits on
  joining by code, invites, join requests, new teams, uploads and new
  conversations or groups (also a best-effort daily cap, reset when an
  instance restarts) (security review S9). `buildApp({ writeLimits: false })`
  turns them off for tests.

**Fixed**
- A school or club community that approves who joins is a private group
  on public pages, like a group: its posts and events no longer show to
  visitors (security review S6).
- Editing a community event without an `audience` keeps its audience
  instead of opening it to everyone.
- Deleting a team chat message as a non-member says only that the room
  isn't found, whether or not the message exists.

## 0.9.2 — 2026-11-14

**Fixed**
- Photo uploads on Cloud Run: `service.yaml` never set `STORAGE_BUCKET`,
  so `/v1/uploads` wasn't registered and the website said "No such
  endpoint." It's now `<project>.firebasestorage.app`. The bucket also
  needs CORS for the website (`deploy/storage-cors.dev.json` /
  `.prod.json`; DEPLOY.md).

## 0.9.1 — 2026-11-14

**Fixed**
- `WEB_SERVER_KEY` is trimmed when read, so a secret saved with a trailing
  newline still matches the website's copy. On dev the site refused every
  cache refresh (401 "Website revalidate refused") although both sides
  came from the same key.

## 0.9.0 — 2026-11-13

Live pages and instant refreshes for the website (fixes from the
two-person web test).

**Added**
- `GET /v1/players/:uid` (signed in, never cached): a player's page as the
  caller may see it. A private profile comes back in full, with its
  private details and posts, to the player and the people whose follow
  they accepted; anyone else gets `locked: true` and only the card
  (`MemberProfilePage` in `@stall10/shared`). Posts by private authors, or
  reposts of their posts, are left out unless the caller follows them.
- `GET /v1/posts/:id` (signed in, never cached): one post, if the caller
  may see it; 404 "This post was deleted." once it's gone.
- The website's cached public pages are expired the moment they change:
  after a profile's details, visibility, privacy or username change, and
  after a post is created, edited, deleted, reposted or a repost undone,
  the API calls the site's `POST /api/revalidate` with cache tags
  (`player:<uid>`, `post:<id>`, `posts`, `feed`, `search`;
  `web/revalidate.ts`). Awaited with a 1.5 s timeout (Cloud Run throttles
  CPU after the reply) and never fails the write. Needs `WEB_SITE_URL`
  (repository variable `API_WEB_SITE_URL_DEV/_PROD` on Cloud Run) and
  `WEB_SERVER_KEY`; without them pages refresh within a minute, as do
  changes the app still writes straight to Firestore (its stats summary).
- `MeRepository.profiles(ids)`.

## 0.8.0 — 2026-11-13

Core features on both apps.

**Added**
- `GET` / `PUT /v1/me/message-policy`: who can start a conversation with
  the caller (`everyone`, `followers`, `following`, `nobody`;
  `messagePolicyRequestSchema`). Stored in `users/{uid}.messagePolicy`,
  as the app already does; unset reads as `everyone`.
- `POST /v1/posts` takes an optional `workout` (`workoutSchema`: activity,
  whole minutes, distance, effort, up to 20 exercises; no GPS route),
  checked as `validWorkout` checks it and stored as `Workout.toMap` does.
  `PATCH` refuses to change a workout.
- Calendars, as in Outlook or Apple Calendar (requirements U11, D4;
  `calendar/`). `calendars/{id}` holds the owner, name, color, `members`
  (`{uid: owner|edit|view}`, mirrored in `memberIds`) and `pending`
  invites. "My calendar" has the owner's uid for id, is made the first
  time it's needed, and keeps its events in `users/{uid}/events`; others
  keep theirs in `calendars/{id}/events`.
  - `GET` / `POST /v1/me/calendars` (up to 20 owned), `PATCH` / `DELETE
    /v1/calendars/:id` (owner; My calendar can't be deleted; deleting
    takes its invites and events with it).
  - Invites: `POST /v1/calendars/:id/invites` (`{uid, role}`; also changes
    a pending invite's role; up to 50 people; not while muted), `DELETE
    /v1/calendars/:id/invites/:uid`. The invitee's copy is
    `users/{uid}/calendarInvites/{id}`; nothing is shared until `POST
    /v1/me/calendar-invites/:id/accept`, which checks the calendar still
    has them pending. `GET /v1/me/calendar-invites`, `.../decline`.
  - Members: `PATCH` / `DELETE /v1/calendars/:id/members/:uid` (Can view or
    Can edit; the owner removes people, anyone leaves).
  - Events: `GET /v1/me/calendar-events?from=&to=` (up to 92 days, every
    calendar the caller is on), `POST /v1/calendars/:id/events`, `GET` /
    `PATCH` / `DELETE /v1/calendars/:id/events/:eventId` (owner or Can
    edit; `calendarEventSchema` checks `validMine`, and My calendar's
    events are saved as the app saves them). Viewers never get notes.
  - Subscription feed: `GET` / `POST` / `DELETE /v1/me/calendar-feed` (a
    private link, reset or turned off) and `GET /v1/ical/:token.ics`
    (public; iCalendar of every calendar the link's owner is on, a month
    back and a year ahead; membership checked on each fetch; rate-limited
    per link; logged at warn only, since the path holds the token). Links
    are stored as a SHA-256 hash (`calendarFeeds`, `calendarFeedOwners`,
    both closed to clients). `PUBLIC_API_URL` sets the links' address.
  - `FirestoreCalendarRepository`: `memberIds` array-contains, `ownerId`
    and date-range queries (single-field indexes only).
- Empty `204` answers for calendar changes.

## 0.7.0 — 2026-11-13

Personal details at sign-up: legal name, birthday, phone, gender, mailing
address and, under 18, a parent or guardian. Only the player reaches them.

**Added**
- `GET /v1/me/personal/status` (`complete`, `required`: accounts made from
  `personalDetailsRequiredSince` on must give them first). Reads no
  ciphertext.
- `GET` / `PUT /v1/me/personal`: the caller's own details, replaced whole.
  Validated by `personalDetailsSchema` (`@stall10/shared`); under 13 is
  refused (`failed_precondition`) and nothing is saved; a guardian is
  required under 18 and dropped at 18 and over. Ages count on the date in
  UTC+14, so a birthday today anywhere counts. Responses are
  `private, no-store`.
- Stored in `personalDetails/{uid}` as one Cloud KMS ciphertext
  (`PERSONAL_DETAILS_KMS_KEY`), bound to the document's path; nothing is
  kept in the clear. Without a key the routes are off. `LocalCipher`
  (`PERSONAL_DETAILS_LOCAL_KEY`) works with the emulators only.
- `UserLookup` returns the account's creation time.

**Fixed**
- A profile write for an account with no display name no longer lists
  the account's email as its public name; the username (or "Player")
  stands in.

**Deploy**
- Create the KMS key and grant `api-runtime` Encrypter/Decrypter first
  (`DEPLOY.md`, step 4). Done for dev; not yet for prod.

## 0.6.0 — 2026-11-13

Communities and their teams.

**Added**
- `GET /v1/teams/:id/roster` also lists a community's teams (`teams`: id,
  name, division), sorted by name; a team's list is empty.
- `POST /v1/teams/:id/invites`: a community's member managers (Manage
  members there) may invite people to any team it has accepted and still
  lists, as well as the team's own. `firestore.rules` (`teamInvites`)
  allow the same for the direct path.

## 0.5.0 — 2026-11-12

Website parity, slice W2 (`docs/product-spec.md` §8.1): team pages.

**Added**
- `GET /v1/teams/:id/roster`: who's on a team, for anyone signed in, not
  only its members: the roster's players (name, number, position, and the
  linked member's public card) and the members (public card, tier and
  custom role names). Nothing else from the team doc (permissions, stats
  keepers, paid marks) goes out. A private group (a community or
  organization that approves joins) shows its members only to members.

## 0.4.0 — 2026-11-12

Website parity, slice W1 (`docs/product-spec.md` §8.1): what the website
needs to post, comment and follow. The app still writes these directly.

**Added**
- Posts: `POST /v1/posts` (a text post, with photos from the caller's
  finished `post` uploads for that post id), `PATCH /v1/posts/:id` (the
  author changes the words, links or photos; a repost only its note;
  dropped photos are deleted from Storage), `DELETE /v1/posts/:id` (with
  its photos; a repost also leaves the original's `repostedBy`). The posts
  rule's checks: 5,000 characters, 5 http(s) links, 4 photos, words or a
  photo, the author only, the flood mute.
- Comments: `POST /v1/posts/:id/comments` (replies one level deep, with
  `replyToName` when answering a reply; not on reposts), `PATCH` and
  `DELETE /v1/posts/:id/comments/:commentId` (its author edits; its author
  or the post's author deletes), `PUT|DELETE .../like`.
- Follows: `PUT /v1/follows` (players, teams, tournaments, with the
  target's own name and photo; a private profile gets a follow request),
  `PATCH|DELETE /v1/follows/:key`, `DELETE /v1/follows/requests/:owner`,
  `POST /v1/me/follow-requests/:uid/accept`,
  `DELETE /v1/me/follow-requests/:uid`, `DELETE /v1/me/followers/:uid`.
- Notifications: `POST /v1/me/notifications/read` and `/delete` by id.

## 0.3.0 — 2026-11-11

**Added**
- Likes and reposts (`PUT|DELETE /v1/posts/:id/like`,
  `PUT|DELETE /v1/posts/:id/repost` with an optional note), with the posts
  rule's checks: only the caller added or removed, 20,000 at most, no
  reposting your own post, the flood mute, and the repost
  (`r_{original}_{uid}`, the fields the app writes) and the original's
  `repostedBy` in one transaction. Liking or reposting a repost acts on its
  original, as in the app.
- `GET /v1/posts/state?ids=`: the caller's likes and reposts of up to 50
  posts, for the website's buttons.
- `GET /v1/feed?before=`: the community feed a page at a time, for members.

**Changed**
- Reposts carry their original (`original`, null once deleted) in the
  public reads and `/v1/me/home`.

## 0.2.0 — 2026-11-11

**Added**
- `GET /v1/me/home`: the signed-in member's dashboard. Their own profile
  (private details included, and `needsUsername` for new accounts), their
  teams with their role, upcoming events they may see (firestore.rules
  `sees(e)`), and a paged feed of their own posts and the people they follow.
- The version in `GET /health` and the `x-stall10-api-version` header.

**Changed**
- Uploads save processed files in the app's Storage folders (e.g.
  `users/{uid}/posts/{postId}/{uploadId}/{uploadId}.jpg`) instead of
  `media/{uid}/`, so `storage.rules` guard reads as before.
  `POST /v1/uploads` takes `itemId` (the post, video or message) for every
  purpose but `avatar`.
- `/v1/public/feed` and `/v1/public/players/:uid` return one page and no
  cursor: visitors see the newest posts; members page through their own
  feed.

## 0.1.0 — 2026-11-11

First version on the `monorepo` branch.
- Team creation (`POST /v1/teams`).
- Team membership and management, communities, invite codes; profiles and
  usernames; media uploads with server-side compression (step 5 of the
  migration; ARCHITECTURE.md §10).
- Public reads for the website (`/v1/public/*`).
- Cloud Run deployment: Dockerfile, CORS allow-list, Cloud Logging,
  readiness, graceful shutdown (`DEPLOY.md`).
