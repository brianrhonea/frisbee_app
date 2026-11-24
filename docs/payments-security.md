# Payments: design and security

How Stall 10 takes fees and pays hosts, what could go wrong, and what
stops it. Code: `apps/api/src/payments` (service, reconcile, jobs, Stripe
gateway); rules: `firebase/firestore.rules`; operations:
`apps/api/DEPLOY.md` (Payments). Keep this file current with any change
to how money moves.

## The model

- **Stall 10 is the merchant.** Every fee is charged to Stall 10's
  Stripe account (Stripe Connect *separate charges and transfers*,
  `transfer_group` `tournament_<id>`). The payer pays the fee, plus
  Stall 10's 3% and Stripe's card fee on top.
- **Hosts are payout-only recipients.** Each host team has a Stripe
  account with no dashboard (`recipient` configuration; fees and losses
  are Stall 10's). Hosts fill in identity and bank details in Stripe's
  embedded forms inside the app and website. Stall 10 never sees or
  stores card, bank or identity numbers (PCI SAQ A).
- **Fees wait in Stall 10's balance** until the event is over, then the
  whole fee goes to the host as a transfer (`source_transaction` = the
  charge). Refunds return the fee only.

Every fee Stall 10 takes today is an *event fee*: a tournament's or
league's team fee (bid or spot fee), or a hat tournament's or league's
player fee. They share one path: `payer()` works out who pays what,
`charges/{id}` records it, and `release()` pays it out once the event's
hold is over. A new kind of fee (seasonal team memberships, later) adds:
a payer resolver, its own release rule (a membership has no event to
finish, so for example "N days after paid"), and its own transfer
group. The ledger, refunds, disputes, the daily check and staff tools
stay as they are.

## Invariants

1. Money only moves on the server (the API, with the Admin SDK). Clients
   can't write `charges`, `paymentLog`, `payoutAccounts`, `payerCharges`,
   `stripe*`, `paymentIssues` or `paymentChecks` (rules, tested).
2. A fee is marked paid only from Stripe: a signed webhook (two
   endpoints, two secrets) or asking Stripe directly. "Paid online
   through Stall 10" can't be written, changed or removed by organizers.
3. Every call that moves money has an idempotency key tied to our record
   (`transfer:<charge>:<n>`, `reverse:<charge>:<n>`, `refund:<charge>`,
   `credit:<charge>`). Stripe forgets keys after 24 hours, so a release
   planned more than an hour ago is looked up on Stripe (by metadata)
   before it's sent again, and a refund that was started before checks
   what Stripe already refunded.
4. The host's share is taken back *before* a refund goes out. If the
   host's balance is short (already paid out to their bank), an
   organizer's refund is refused; staff can refund it, and the host owes
   it, taken off their next payouts.
5. Stall 10 never pays a host twice: a confirmed transfer is recorded
   only by the run that planned it; a won dispute either re-sends a
   reversed transfer or cancels the debt.
6. A payout needs: the event finished (`finishedAt`, stamped by the
   server, cleared on reopening), its last day passed (also as it was
   when the fee was paid), the hold over (`PAYOUT_HOLD_DAYS`, default 3,
   after both finishing and paying), the host's payouts set up, and
   staff approval for a host's first payout and for an event once its
   payouts to the host pass $2,000 (`eventSent`, `approvedEvents`).

## Threats and controls

| Threat | Controls |
|---|---|
| Stolen cards used to pay (card testing) | Stripe Radar (rules in DEPLOY.md); per-user rate limits on checkout and intents; App Check (`ENFORCE_APP_CHECK`); new-account gates; payments only for real entries or signups |
| A host paying their own event with stolen cards and cashing out before the chargebacks | Organizers can't pay online for their own event; staff approve each host's first payout and each event past $2,000 paid out; 3-day hold; registration opens at most 60 days before the start, so fees aren't held long; disputes claw back from the host, and what can't be taken back is owed |
| A host collecting fees for an event that never happens | Fees are held until the event is finished and its date has passed; moving the date earlier, or finishing early, doesn't pay out sooner; refunds come from Stall 10's balance before release |
| A stolen or left-open session moving payouts to another bank | Only the team's owner sets up payouts; setting up or changing them needs a sign-in in the last 15 minutes; Stripe emails bank changes |
| An organizer marking fees paid, or undoing a payment | Server-only payment records; paid-online lock in the API and rules |
| Replayed or forged webhooks | Signature checks with each endpoint's secret; each event handled once (`stripeEvents`) |
| Retries and races paying twice | Idempotency keys, transactions, a lookup before old retries, a plan number on every release |
| Missed webhooks or bugs leaving money wrong | The daily check against Stripe (`paymentIssues`), shown to staff on `/staff`; the hourly release job |
| Deleting a team with money held or owed | Refused until it's settled |
| Leaked keys | Secrets only in Secret Manager; a restricted live key; rotation (DEPLOY.md) |
| Scheduler routes called by anyone | Google-signed OIDC tokens for one service account and this API's URL only |

## Known gaps (to do)

- Rate limits are per server instance (in memory). Before launch, put
  checkout and intents behind a shared limit (Firestore or Redis) and
  cap Cloud Run's instance count, or rely on App Check and Radar.
- Disputes: the evidence step is done in Stripe's Dashboard by staff;
  `charge.dispute.funds_withdrawn` and `funds_reinstated` aren't
  followed separately (created and closed are).
- Reading the host's earnings also sends any fee that's due (safe and
  idempotent, but a read that moves money); the scheduled job makes it
  unnecessary, so it can be removed once the jobs run everywhere.
- Errors from Stripe in background steps (a credit transfer) are left
  for the daily check rather than logged on the spot.
- Staff approval of a host isn't reset when the host changes its bank
  account in Stripe's form. Follow Stripe's external-account events and
  clear `approvedAt` on a change (Stripe also emails the host).
- The self-payment block stops an organizer's own account; someone
  using a second account to pay their own event is left to the payout
  review, the hold and Radar.
- A team's owner change is the main account-takeover path for payouts;
  consider requiring a fresh sign-in for handing a team on too.
- The Stripe API version follows the SDK's pinned version; upgrade both
  together (`upgrade-stripe`).
