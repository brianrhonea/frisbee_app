# Payments: stopping stolen-card fraud (ideas to decide on)

Stall 10 is the merchant, so a stolen-card payment that's disputed costs
Stall 10: the fee goes back to the cardholder, Stripe charges a dispute
fee (about $15), and if the host already has the money Stall 10 has to
recover it. Too many disputes (Stripe's line is about 0.75% of payments)
also puts Stall 10's own Stripe account at risk. This lists what's
already in place and what else could be added, roughly in order of how
much it helps for the effort. Decisions are yours; nothing here is built
unless it says so.

## Already in place

- Card details never touch Stall 10 (Stripe's payment sheet and Checkout).
- Fees are held: payouts wait until the event is finished, its date has
  passed (as it was when paid), and 3 more days (`PAYOUT_HOLD_DAYS`).
- Registration, and so paying, opens at most 60 days before the start.
- Staff approve each host's first payout, and an event's payouts once they
  pass $2,000.
- Organizers can't pay online for their own event.
- Disputes take the host's share back; what can't be taken back is owed
  and comes off the next payout. Teams with money held or owed can't be
  deleted.
- Payout setup is owner-only and needs a recent sign-in; hosts' identity
  and bank are verified by Stripe.
- Per-user rate limits on starting payments; App Check available.
- A daily check against Stripe; staff payments view.

## Highest value next (recommend before launch)

1. **Radar rules (no code, Stripe Dashboard).**
   - Require 3D Secure when Radar says it's risky (or for every payment
     over, say, $100). A 3D Secure payment that turns out to be fraud
     usually shifts the dispute to the card's bank, not Stall 10.
   - Block when CVC or postcode checks fail.
   - Block risk level "highest"; review "elevated".
   - Velocity: block more than 3 cards per customer email, or 5 payments
     per card, per day.
   - Optional: block non-US cards while Stall 10 is US-only.
2. **Act on early fraud warnings (small build).** Card networks send
   `radar.early_fraud_warning.created` days or weeks before a dispute.
   Refunding then avoids the dispute and its fee, and doesn't count
   towards the dispute rate. Build: a webhook handler that refunds the fee
   (as staff would), holds the host's payouts for staff, and flags it on
   `/staff`.
3. **Pay out only for events that happened (small build).** Release
   needs evidence the event took place: games scheduled and at least some
   scores reported, or staff approval. A fake event with no games never
   pays out.
4. **New-host limits (small build).** For a host's first 3 events:
   - cap online fees per event (for example $1,500) until staff raise it;
   - a longer hold (for example 14 days);
   - payouts always approved by staff (today only the first).
5. **Rolling reserve for new hosts (medium build).** Keep back 10–20% of
   each payout for 90 days (the main chargeback window) and send it
   after. This covers late disputes without holding everything.
6. **Pause payouts after a bank or owner change (small build).** When the
   payout bank changes (Stripe's external-account events) or the team's
   owner changes: pause payouts for 3 days, email the old and new owner,
   and clear staff approval so the next payout is checked again.

## Worth adding as volume grows

7. **Card fingerprints.** Stripe gives each card a fingerprint. Store it on
   the charge (not the card number) and flag:
   - one card paying for many different teams;
   - many payers for one event using brand-new accounts and cards;
   - a payer's card matching a card the host's organizers have used.
8. **Payer account checks.** Before paying online: a verified email and an
   account more than a day old (the new-account gates help), and phone
   verification for payments over a set amount.
9. **Two-factor sign-in for host owners** who collect money (Firebase
   multi-factor), required before payouts can be turned on.
10. **Dispute-rate brake.** Automatically pause a host's payouts if more
    than 1% of its payments (or 2 in 30 days) are disputed, and alert
    staff. Track Stall 10's overall rate weekly.
11. **Staff tools.** A "freeze host" switch (payouts and new payments),
    block lists (card fingerprint, email, device), and a reason log.
12. **Caps per payment.** Refuse a single online fee over a set amount
    (for example $3,000) without staff approval.
13. **Bank debits for big team fees.** US bank debits (ACH) cost less, but
    unauthorized-debit claims can come up to 60 days later. Keep the hold
    and reserve for them, or limit them to established hosts.
14. **Shared rate limits.** Today's per-user limits are counted on each
    server instance. Move checkout and payment limits to a shared counter
    (Firestore or Redis) and cap Cloud Run instances, and enforce App
    Check, so card testers can't spread across servers.

## Process, not code

- Write a short fraud playbook: what staff check before approving (host
  team age, past events, location, games, who paid), and when to refund
  and freeze.
- Turn on Stripe's emails for disputes, early fraud warnings, payout
  failures and bank changes; check `/staff` daily at first.
- Terms (drafted): hosts are responsible for refunds and disputes on
  their events, owe what can't be recovered, and can be removed for
  fraud. Get a lawyer to review.
- Consider Stripe Radar for Fraud Teams (custom rules, card fingerprint
  lists, manual review queue) once volume justifies its cost.
- Keep test and live keys separate, use a restricted live key, and turn
  on two-factor sign-in for everyone with Stripe Dashboard access.

## Suggested order

Decided 2026-11-24: turn on 1 (Radar rules, no code) when Stripe is set
up; build the rest only if disputes start showing up. What's already in
place covers the main risks at today's size.

If it does become an issue: 2 (early fraud warnings), 3 (events that
happened), 4 (new-host limits), 6 (pause on bank change). Then 5
(reserve) and 14 (shared limits). The rest as volume grows.

Host verification, if needed later: instant bank verification with the
account holder's name matched to the verified host (Financial
Connections; microdeposits only as the fallback), and collecting every
identity detail Stripe may ask for at setup (`eventually_due`) instead
of the minimum. Both are settings on Stripe's embedded onboarding.
