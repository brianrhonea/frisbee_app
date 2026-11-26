<!-- Converted from Stall10_10_Payments_Fraud_Prevention.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# Payments & Fraud Prevention

DOCUMENT 10  /  VERSION 1.0  /  25 NOVEMBER 2026

Approved product direction • Engineering specification • Pre-launch

### Purpose

Enable trustworthy paid sports participation while protecting athletes, organizers and Stall10 from payment failures, fraudulent events and unrecoverable financial losses. Retain the existing Stripe Connect separate charges and transfers architecture; expand it into a reusable financial service.

### Operating model

Stall10 collects payments on its platform Stripe account. Hosts receive their advertised principal under normal settlement, subject to refunds, reserves and debt recovery. Payers cover the platform service fee and estimated processing costs. Free events and offline tracking remain available. No general-purpose wallet, peer-to-peer transfers or claim of escrow.

### Launch decision

Begin with an invite-only paid hosting beta. Require critical event verification and payout security controls before live collection; expand access only after operational evidence supports it. This supersedes the November 24 fraud-planning decision to defer most safeguards until disputes appear.

### Document map

02–03 Approved requirements and repository baseline • 04 Checkout and payment categories • 05 Host verification and risk • 06 Settlement and completion • 07 Refunds and disputes • 08 Ledger and API • 09 Operations and security • 10 Acceptance and rollout • 11 References and open decisions.

Status convention: approved = user-confirmed direction; baseline = reviewed source or repository documentation; proposed = implementation design or parameter requiring validation. UI concepts are reserved for Document 17.

## 02  Approved requirements

| | |
|---|---|
| PF01 · Paid hosting | Invite-only beta, then broader verified-host access. |
| PF02 · Fraud priority | Critical payout and event verification safeguards before launch; advanced automation phased. |
| PF03 · Verification | Stripe identity, verified contacts, bank ownership checks where supported, risk-based review. |
| PF04 · Trust tiers | Provisional, established, trusted and restricted hosts. |
| PF05 · Deposits | Optional risk-based refundable deposit; initially consider $200. |
| PF06 · New hosts | First three events enhanced review; proposed $1,500 cap with staff exceptions. |
| PF07 · Holds | Three days established; proposed 14 days provisional after verified completion. |
| PF08 · Reserves | Risk-based 10–20% for up to 90 days where justified and permitted. |
| PF09 · Completion | Independent participant evidence; event-specific checks; manual review if insufficient. |
| PF10 · Early settlement | Established hosts may request partial early settlement after launch. |
| PF11 · Account changes | MFA, recent authentication, proposed 72-hour freeze and renewed approval. |
| PF12 · Refunds | Full mandatory fees included for host cancellation, fraud and platform errors; disclosed withdrawal policy. |
| PF13 · Methods | Cards and supported mobile wallets at launch; ACH later. |
| PF14 · Expansion | Dues, installments, community fees, clinics and eligible contributions with distinct settlement rules. |
| PF15 · Administration | Auditable ledger, automated reconciliation, risk alerts, debt recovery and scoped reports. |

## 03  Repository baseline

Source review: frisbee_app / development. Existing implementation and documented behavior are not proof of production readiness. References appear on page 11.

| | |
|---|---|
| Collection [1–3] | Stripe platform charges, recipient connected accounts, embedded onboarding, Checkout and mobile PaymentIntent flows; USD only. |
| Pricing [2] | Default 300 basis points; onlineCharge grosses up estimated card costs. Legacy feeBreakdown deducts fees; audit callers. |
| Settlement [1,3] | Server finishedAt, original end date, payment age, default 3-day hold, readiness, first payout and $2,000 event review. |
| Recovery [1,3] | Refunds currently principal only; reverse host transfer first; staff can record debt; dispute creation and won handling. |
| Integrity [1,3] | Signed webhooks, event records, idempotency keys, transaction plans, lookup before old retries; server-only financial writes documented. |
| Operations [4,5] | Hourly release and daily reconciliation documented; OIDC scheduler verification; discrepancy detection. |
| Known gaps [1,6] | Per-instance limits; earnings read triggers release; bank changes do not reset approval; owner takeover risk; some background errors only found in reconciliation. |
| Tests [7] | API, shared, mobile and rules test files exist; not executed. |

### Migration priorities

Preserve legacy direct-charge compatibility, existing payment references and recovery semantics. Audit fee helpers and both clients; remove money movement from reads; add durable review and restriction state. Do not infer deployed Stripe settings from code.

## 04  Checkout and payment categories

### Authoritative checkout

API resolves payer eligibility, registration, amount, currency and host from canonical records. Snapshot fee policy, event dates and refund terms. Show total mandatory price before commitment; use Stripe-hosted or embedded payment components. Only signed provider events or authenticated provider lookups confirm payment. Pending payments do not count as paid; reserve registration capacity with an expiring hold and handle late success by reconciliation or refund.

Illustration: $500 principal + $15 platform fee + approximately $15.69 processing = $530.69 total using repository estimates of 2.9% + $0.30. Host principal $500; gross platform revenue $15 before costs. Actual fees and rounding may differ. Validate fee presentation, surcharge rules and provider terms before launch.

| | |
|---|---|
| Tournament / hat entry | Verified completion and applicable hold. |
| League registration | Approved completion milestones; prevent release beyond earned amount. |
| Pickup, clinic, tryout | Event-specific attendance and completion checks. |
| Season / community dues | Membership activation and defined settlement interval; installments independently tracked. |
| Eligible contributions | Separate eligibility, purpose and settlement policy; no charitable tax claims without validation. |
| Platform subscriptions | Direct platform revenue; coordinate Document 11 and app-store billing rules. |
| Host deposit | Separate refundable obligation; not earned revenue on receipt. |

### Methods and expansion

Launch USD cards and supported Apple Pay / Google Pay. ACH later: asynchronous confirmation, returns, distinct risk limits and release rules. Manual cash/check/external payment records remain explicitly offline and cannot overwrite verified online payments.

## 05  Host verification and risk

| | |
|---|---|
| Unverified | Free hosting and offline records only. |
| Provisional | Stripe onboarding, verified contacts, eligible adult representative, risk review; first three paid events enhanced review. |
| Established | Successful verified events, satisfactory financial standing; standard hold. |
| Trusted | Additional organizational evidence and approved higher limits; early settlement eligibility later. |
| Restricted | Block new collections and/or releases as appropriate; allow refunds, disputes and authorized recovery. |

Proposed provisional cap: $1,500 collected principal per event, enforced transactionally across paid and pending reservations; staff exceptions require reason, limit and expiry. Track related hosts and aggregate exposure; do not rely solely on event-level limits. Review tier changes using event history, complaints, dispute rate, debt and identity changes.

### Verification workflow

Owner completes Stripe onboarding and verified contact checks. Use bank ownership/name matching where supported; instant verification preferred, microdeposits fallback where available. Never collect raw card, bank or government ID numbers in Stall10. Stripe readiness is necessary but not proof of event legitimacy. Staff review venue, organizer history and event details.

### Deposits and reserves

Optional risk-based refundable deposit, initially consider $200. Record separate liability, reason, release conditions and authorized deductions. Do not automatically confiscate on cancellation. Reserve 10–20% up to 90 days only where justified, disclosed and permitted by provider and law; record each tranche and release date. Deposit and reserve do not replace completion checks or platform liquidity.

## 06  Settlement and event completion

### Release gate

Require confirmed payment, current host readiness, verified completion, original and current event end dates passed, applicable hold expired, no unresolved restriction, and required staff approval. Established hold three days; provisional proposed 14 days. Preserve payment-age safeguard. Apply debt recovery and approved reserves before transfer. Recheck conditions at execution and reconcile any race with refund or dispute.

| | |
|---|---|
| Competitive tournament | Opposing captain-confirmed results, participant confirmations and complaint review. |
| Hat / pickup / clinic | Independent attendance or participant confirmation; staff review if sparse. |
| League | Verified completed games and approved milestone evidence. |
| Insufficient evidence | No automatic release; open review case with reason and evidence request. |
| Cancellation / postponement | Freeze release; evaluate refund or participant-approved rescheduling. |

### Transfer is not bank payout

Maintain separate payment, registration, settlement and bank payout states. Proposed settlement states: held, review_required, eligible, transfer_planned, transferred, reversed, restricted. Track bank payout only from authoritative provider evidence; show unknown if unavailable. Use durable operation IDs, provider idempotency and reconciliation before retrying ambiguous operations.

### Early settlement — post-launch

Established hosts may request partial release with documented need, risk review, remaining refund coverage, no unresolved debt and staff approval. Define maximum fraction and exposure limits before enabling. Never promise early release; maintain audit history and recovery obligations.

## 07  Refunds, disputes and recovery

| | |
|---|---|
| Host cancellation / fraudulent event | Full amount paid including mandatory fees; staff-managed recovery. |
| Platform error / duplicate | Full affected charge; reconcile registration and ledger. |
| Participant withdrawal | Apply disclosed, snapshotted policy and applicable law. |
| Reschedule / weather | Offer refund or accepted transfer of registration as applicable; preserve history. |
| Partial delivery | Staff review; support partial refund with explicit allocation. |
| Rejected registration | Full refund if collected. |

This changes the existing ordinary principal-only refund policy. Define allocation of unrecoverable provider costs and platform fee reversals. Do not deny an owed participant refund solely because the host has insufficient balance; authorized staff can fund it and record recoverable host debt. Avoid duplicate refund during open disputes; follow provider dispute workflow.

### Dispute handling

Create case on dispute or early fraud warning, hold affected unreleased funds, collect evidence and deadlines, reverse transfers where possible, record debt for shortfall. Staff submit evidence in Stripe initially. Reconcile won/lost and funds withdrawn/reinstated events; restore host entitlement only once. Maintain immutable history and prevent deletion of entities with unresolved liabilities.

### Fraud controls

Configure Radar, risk-based 3D Secure, velocity controls and App Check where supported. Shared limits by account and relevant risk signals; avoid raw sensitive payment data. Early warnings create review cases rather than unconditional refunds. Monitor related-account self-payment, suspicious volume, fabricated events and repeat disputes. Define pause and escalation thresholds before beta.

## 08  Ledger and API design

Target model (proposed): extend existing charges, paymentLog, payoutAccounts, payerCharges, paymentIssues and paymentChecks rather than replacing them abruptly.

| | |
|---|---|
| charges/{id} | Canonical source, payer/host, currency, principal, platform fee, processing estimate/actual, total, policy snapshot, provider IDs and status. |
| ledgerTransactions/{id}/entries/{id} | Immutable balanced entries in integer minor units; unique operation ID, timestamp, source and reversal link. |
| refunds / disputes / transfers / bankPayouts | Provider identifiers, amounts, lifecycle, evidence and reconciliation status. |
| hostReserves / hostDeposits | Liability, tranche, reason, release date, adjustments. |
| financialReviewCases | Risk flags, restrictions, assignee, evidence, decisions and audit history. |

Ledger accounts distinguish provider clearing, host payable, platform revenue, actual processing expense, refund liability, reserves, deposits, host receivable and dispute loss. Accountant validates postings and revenue recognition. Reversals append entries; no destructive edits. Reconcile by currency and provider account.

### API contracts — proposed extensions

Retain existing payment routes; reconcile exact route names before implementation. Add authenticated operations for host review, restrictions, completion evidence, settlement requests, refund requests and financial exports. Staff-only approval/release endpoints require reason and recent authentication. Read endpoints are side-effect free. Webhooks verify raw-body signatures and account scope; durable event processing tolerates retries and out-of-order delivery. All writes via API or trusted server jobs; direct reads only for explicitly authorized projections.

## 09  Security and financial operations

### Account takeover protection

Require MFA and recent authentication for payout setup, bank changes and ownership transfers. On provider bank-change event or confirmed owner change, freeze new transfers for proposed 72 hours, clear approval, notify verified contacts and require renewed review. Investigate ability to pause existing connected-account bank payouts; transfer freeze alone is insufficient. Fail closed when readiness or restriction status is uncertain.

### Operational controls

Use least-privilege financial roles, staff MFA, secret manager, isolated test/live accounts, restricted keys, audit trails and redacted logs. Financial reports are scoped to payer, host finance role or authorized staff. No raw bank/card details in exports. Define retention, deletion exceptions and incident response with counsel.

| | |
|---|---|
| Continuous | Alert on critical fraud, payout destination changes, failed money movement and unresolved webhook processing. |
| Hourly | Process eligible releases with authenticated scheduler and bounded retries. |
| Daily | Reconcile provider payments, refunds, disputes, transfers and bank payouts where available; review exceptions. |
| Weekly | Review dispute trends, host exposure, pending cases and reserve adequacy. |
| Monthly | Reconcile statements, actual provider costs, host liabilities and platform cash; export accounting records. |

### Reporting and liquidity

Payers receive itemized receipts and refund status. Hosts see principal, offline payments, held funds, reserves, transfers, bank payout status and debt. Staff see gross volume, earned fees, expenses, liabilities and losses. Maintain platform operating liquidity separately in accounting from host obligations; define cash buffer and maximum exposure before beta.

## 10  Acceptance and delivery plan

### Launch gate — required tests

Run existing API, shared, mobile and Firestore rules suites; add integration tests in Stripe test mode. Verify mobile/web parity and failure recovery before live pilot.

- Concurrent checkout and capacity reservations; duplicate and late payment success; out-of-order and replayed webhooks.
- Client cannot mark online payments paid or modify financial records; unauthorized reports and scheduler calls rejected.
- Fake completion, early finish, reschedule, cancellation and missing independent evidence cannot release funds.
- Bank/owner change invalidates approval and freezes transfer; MFA and role restrictions enforced.
- Refund before/after transfer, insufficient host balance, partial refund, duplicate refund and open dispute.
- Interrupted transfer and old retry recover without double payment; reconciliation detects amount, destination and reversal mismatch.
- Reserve/deposit accounting balances; debt deductions and dispute-won credits occur once; legacy direct charges remain reconcilable.
- Fee quote matches checkout and receipt; actual costs recorded; test/live isolation and alert delivery verified.

### Delivery phases

Beta: existing payment flows, Radar, shared abuse limits, verified hosts, completion review, MFA/change freeze, reason-specific refunds, ledger foundation and reconciliation alerts. Broader launch: expand verified access only after review of pilot losses, exceptions and operational capacity. Post-launch: deposits/reserves where approved, ACH, dues and community categories, partial early settlement, advanced fraud automation. Future: international payments and sophisticated risk scoring.

Proposed beta exit criteria: no unresolved critical reconciliation errors, demonstrated refund and dispute recovery, verified release controls, documented support ownership and acceptable exposure within approved limits. Quantitative thresholds require owner approval.

## 11  References and open decisions

Repository: https://github.com/brianrhonea/frisbee_app/tree/development. Source references below identify the reviewed files or test inventory; branch contents may change.

[1] docs/payments-security.md — operating model, invariants, threats and known gaps.

[2] packages/shared/src/payments.ts — fee defaults, onlineCharge, legacy feeBreakdown and USD constraints.

[3] apps/api/src/payments/service.ts; stripe.ts; gateway.ts — collection, release, refunds, disputes and provider integration.

[4] apps/api/src/payments/reconcile.ts — discrepancy detection.

[5] apps/api/src/payments/jobs.ts — scheduler identity and release/reconcile jobs.

[6] docs/payments-fraud-ideas.md — proposed controls and November 24 decision, superseded in priority by PF02.

[7] apps/api/test/payments.test.ts; packages/shared/test/payments.test.ts; apps/mobile/test/ui/payments_test.dart; firebase/functions/test/rules/payments.rules.test.ts; docs/payments-failure-testing.md — test inventory, not execution results.

### Open implementation decisions

Confirm Stripe account configuration, bank verification capabilities, permitted holding periods and reserve/deposit mechanisms; legal review of merchant obligations, fee disclosures, host agreement, refunds, tax and money transmission implications. Confirm MFA implementation, aggregate caps, dispute thresholds, liquidity buffer, retention, early-release limits and accounting mappings. Validate actual provider pricing and app-store requirements.

### Review limitations

Selected development-branch sources and prior assessment only. No tests executed, no live Stripe settings or transactions verified, no complete client parity or rules audit. Proposed schema, controls and numeric parameters are design targets, not implemented features. No repository modifications. UI mockups deferred to Document 17.
