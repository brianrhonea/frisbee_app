# Payments: failure testing

How payment processing is tested for things going wrong, both automatically
and by hand in Stripe's test mode. Design and threats:
`docs/payments-security.md`. Fraud ideas: `docs/payments-fraud-ideas.md`.

## 1. Automated failure simulation (runs with `pnpm test`)

`apps/api/test/payments.test.ts` → **failure simulation**. Each test
breaks one step on purpose and checks the money: nothing is lost, sent
twice or refunded twice. It uses a fake Stripe that can fail any call, a
store that can "crash" mid-step, and hooks that let a webhook or a second
click land while a payout or reversal is in flight.

| Area | What's broken | What must happen (tested) |
|---|---|---|
| Taking payment | Stripe down when checkout starts | Error shown, nothing marked paid, a retry works |
| | Forged webhook (bad signature) | Refused (400), nothing changes |
| | Same webhook twice, plus a second event for the same payment | Recorded once (one `paid_online` log entry) |
| | Server crash while recording a payment | Webhook isn't marked handled; Stripe's redelivery records it |
| | Checkout "expired" arriving after it was paid | Stays paid |
| | Payer pays twice (two tabs) | Second payment refunded in full, first kept |
| Paying the host | Stripe down at payout | Held; later sent once, same amount |
| | Crash after Stripe made the transfer, before it was recorded | Never sent twice (same key; after 1 hour, looked up on Stripe first) |
| | Three payout runs at once | One transfer |
| | Dispute lands while the transfer is in flight | Transfer taken back |
| | Refund lands while the transfer is in flight | Transfer taken back |
| | Host's Stripe account becomes restricted | Fees wait |
| Refunds | Double click / two organizers | One refund; the second is told it's under way |
| | Stripe fails the refund after the host's share was taken back | Retry refunds once; the host's share is never taken twice |
| | Refund while the payout is going out | Asked to wait; works after |
| | Refund again, or by someone who isn't an organizer | Refused |
| Disputes | Lost after the host spent the money | Owed; next payout pays it back first; books balance |
| | Same dispute webhook twice | Host's share taken back once |
| Daily check | Refund made in Stripe, webhook lost | Flagged for staff |
| | Payment whose webhook never arrived | Flagged for staff |

Earlier suites in the same file cover: the payout hold, first and large
payout approval, the 60-day registration window (also
`tournaments.test.ts`, rules, app), self-payment, recent sign-in for
payouts, owed amounts, disputes won and lost, scheduler auth, team
deletion with money held (`team_deletion.test.ts`), and the rules
(`firebase/functions/test/rules/payments.rules.test.ts`).

Run: `pnpm test` (all), or
`cd apps/api && npx vitest run test/payments.test.ts -t "failure simulation"`.

Found and fixed by this suite (2026-11-24): a double-clicked refund could
start twice. Real Stripe's idempotency keys would have merged them, but
only for 24 hours. Refunds now take a one-minute lock, freed straight
away if the refund fails.

Not simulated (Stripe-side; test by hand below): 3D Secure, bank
debits that fail days later, Radar blocks, early fraud warnings, real
webhook signatures and delivery retries.

## 2. By hand in Stripe test mode (on dev, once Stripe is set up)

Use test keys only. Forward webhooks locally with
`stripe listen --forward-to localhost:8787/v1/payments/stripe/webhook --forward-connect-to localhost:8787/v1/payments/stripe/webhook`,
or point both dev endpoints at the dev API. Check each card number on
Stripe's testing page (docs.stripe.com/testing) before relying on it.

Cards (any future expiry, any CVC, any postcode):

| Card | Use it to check |
|---|---|
| `4242 4242 4242 4242` | A normal payment, payout, refund |
| `4000 0025 0000 3155` | 3D Secure is asked for and completes |
| `4000 0000 0000 9995` | A decline (insufficient funds) shows a clear message, nothing recorded |
| `4000 0000 0000 0002` | A generic decline |
| `4000 0000 0000 0259` | A dispute (fraud): host's share taken back, owed if spent |
| `4000 0000 0000 0077` | Funds available at once (lets a payout go out immediately in test mode) |
| `4100 0000 0000 0019` | Radar blocks it (highest risk) |

Walk-through (do it on the app and on the website):

1. Host: set up payouts in the app (embedded form, test bank
   `000123456789` / routing `110000000`), see "Online payments are on".
2. Make an event starting within 60 days; check Publish is blocked for
   one further out.
3. Team pays with 4242 → Teams tab shows paid; staff `/staff` lists it.
4. Pay as an organizer of the host → refused ("You run this event").
5. Finish the event → fee held (3-day hold, first payout waits for
   approval). Approve on `/staff` (set `PAYOUT_HOLD_DAYS=0` on dev to
   skip the wait) → transfer appears in Stripe.
6. Refund from the Teams tab → reversal then refund in Stripe; payment
   shows "Refunded".
7. Pay with 0259 → dispute arrives → transfer reversed; owed shows on the
   host card if the balance was paid out.
8. Run **Check against Stripe** on `/staff` → no problems.
9. Break things: stop the API mid-payment and restart (Stripe redelivers),
   resend events with `stripe events resend <evt_…>`, refund in the
   Stripe Dashboard (the app follows), double-click Refund.
10. Pay a bank debit (ACH test account) → "Bank payment clearing", then
    paid; try the failing test account → shows not paid.

Check after each step: `charges/{id}` and `paymentLog` in the Firestore
console agree with Stripe's Dashboard, and `/staff` shows no problems.
