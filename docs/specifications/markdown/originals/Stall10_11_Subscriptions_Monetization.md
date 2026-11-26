<!-- Converted from Stall10_11_Subscriptions_Monetization.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# Subscriptions & Monetization

DOCUMENT 11  /  VERSION 1.0  /  25 NOVEMBER 2026

Approved product direction • Engineering specification • Pre-launch

### Purpose

Build a sustainable, social-first sports ecosystem with free core participation, optional paid capabilities and transaction revenue. Launch with ultimate frisbee while retaining sport-agnostic plans and entitlements.

### Operating model

Stall10 earns a standard 3% platform fee on eligible online sports transactions. Hosts receive their advertised fee under the payer-funded model, subject to Document 10 safeguards. Digital subscriptions are a separate revenue stream and billing domain.

### Launch decision

Launch free core functionality and verified-host transaction revenue first. Build entitlement and cost-control foundations before launch; introduce paid subscriptions after measuring demand and resource consumption.

### Document map

02 Approved requirements • 03 Repository baseline • 04 Plans and benefits • 05 Resource allowances • 06 Billing lifecycle • 07 Technical architecture • 08 Financial model • 09 Delivery and acceptance • 10 References and open decisions.

Status convention: approved = user-confirmed direction; baseline = reviewed repository evidence; proposed = implementation detail or planning assumption requiring validation. No UI mockups; see Document 17.

## 02  Approved requirements

| Decision | Approved direction |
|---|---|
| Plans and prices | Free; Individual Plus $4.99; Community Pro $9.99; Team Pro $19.99; Organization Pro $49.99 monthly. |
| Annual / seasonal | Approximately two months free annually; optional prepaid season passes later. |
| Launch | Free platform and transaction fees first; subscriptions post-launch. |
| Organization | Five linked teams, pooled allowances, optional additional team coverage. |
| Media / meetings | Server-enforced adjustable storage; participant-minute quotas; separate recording and transcription allowances. |
| Add-ons | Optional prepaid capacity or recurring storage; no automatic overage charges. |
| Billing | Separate digital billing module; evaluate RevenueCat; server-owned entitlements. |
| Trials | 14-day individual; 30-day workspace; abuse controls. |
| Promotions | Limited launch partner discount, proposed 50% for first year. |
| Expiration | Preserve core records; disable premium operations; proposed 90-day excess-media transition. |
| Marketplace | Standard 3% across plans; evaluate one-time Tournament Pro pass later. |
| Advertising | No general advertising at launch; future verified sponsored opportunities and partnerships. |
| Financial target | At least 60% premium contribution margin; adjust allowances using measured costs. |

## 03  Repository baseline

Selected development-branch files were reviewed in the preceding assessment. The following describes source evidence, not a verified production deployment.

| Source | Finding / implication |
|---|---|
| packages/shared/src/payments.ts | Default 300 basis points, zero fixed cents; onlineCharge grosses up payer amount to cover platform and estimated processing fees. Legacy feeBreakdown comments describe a different model; use onlineCharge for current policy. |
| docs/product-spec.md | Free social participation; Stripe Connect real-world tournament and league payments; configurable fees. Existing refund text differs from approved Document 10 full mandatory-fee refunds for host cancellation, fraud and platform errors. |
| apps/api/src/app.ts | Fastify registers payments, media, videos and meetings. No dedicated subscription module established in reviewed registration. |
| apps/api/src/media/service.ts | Signed uploads and transactional daily chat quota accounting; useful pattern for reservations. |
| apps/api/src/videos/service.ts; firebase/storage.rules | Video size validation and 500 MB storage rule; premium file sizes require coordinated changes. |
| docs/ARCHITECTURE.md | Documents 5 GB team video quota as app-only; legacy direct Firebase writes remain a bypass risk. |
| firebase/docs/cloud-limits.md | Provider pricing snapshot dated Nov 5, 2026; LiveKit Build plan assumed, 5,000 project-wide participant minutes documented. |
| apps/api/src/limits/writes.ts | 120 writes/minute per signed-in user, per-instance; abuse controls are not paid quotas. |

### Gap

No verified recurring billing lifecycle, provider purchase validation, centralized entitlement catalog or workspace-level metering was established in the selected files. Existing code and documentation may differ; confirm before implementation.

## 04  Plans and feature boundaries

| Plan | Monthly / annual (USD) | Scope and benefits |
|---|---|---|
| Free | $0 | Core social, teams, communities, calendars, search, messaging, basic statistics, playbooks, external film links, free hosting. |
| Individual Plus | $4.99 / $49.99 | Personal analytics, training insights, profile tools and expanded media. |
| Community Pro | $9.99 / $99.99 | Organizer analytics, event automation, expanded media and meetings. |
| Team Pro | $19.99 / $199.99 | Advanced statistics, film tools, recruitment, attendance and financial reporting. |
| Organization Pro | $49.99 / $499.99 | Five covered teams, pooled resources, organization analytics and administration. |

Annual prices are proposed exact implementations of the approved approximate two-month discount. Monthly prices are approved. Basic manual dues, expenses, offline payment tracking, historical records, privacy, safety, account deletion and personal data export remain free.

### Scope and permissions

A workspace owner or authorized billing administrator buys coverage for the workspace. Eligible members receive scoped premium capabilities without buying individual plans. Individual Plus does not upgrade a team. Organization coverage does not grant access to private team data; normal role checks remain mandatory.

### Coverage changes

Prevent duplicate charges when independently subscribed teams join an organization. Require explicit confirmation of billing ownership and coverage changes; do not silently cancel existing subscriptions. Additional team coverage is optional. A proposed $7.99/month add-on requires cost validation.

### Marketplace

Free and premium hosts pay the same standard 3% platform fee, funded by the payer. Paid hosting eligibility is governed by Document 10, not subscription status. Advanced event reporting and automation may be premium; evaluate a proposed $29.99 event pass later.

## 05  Resource allowances and enforcement

| Resource | Free | Premium (proposed) |
|---|---|---|
| Personal stored media | 250 MB | 2 GB |
| Community stored media | 1 GB | 5 GB |
| Team stored media | 5 GB | 25 GB |
| Organization storage | Linked free allowances | 100 GB pooled |
| Team video file | 500 MB | 1 GB |
| External film links | No paid cap | No paid cap |
| Team/community calls | 1,000 participant-min/month | Team 6,000; community 3,000 |
| Personal hosted calls | Basic access subject to limits | 1,500 participant-min/month |
| Organization calls | Linked free allowances | 20,000 pooled participant-min/month |

All numeric allowances are adjustable planning defaults, not guaranteed public commitments. Meter participant-minutes as actual connected time, including voice channels; a 20-person one-hour meeting consumes 1,200 minutes. Recording, transcription, bandwidth and transcoding require separate cost budgets and quotas.

### Enforcement

Reserve capacity transactionally before issuing upload URLs or admitting billable sessions; finalize actual bytes or minutes idempotently, release expired reservations, reconcile provider events and orphaned media. Check both authorization and entitlement. Prevent legacy direct writes and storage uploads from bypassing limits. Maintain project-wide emergency cost controls independent of plan limits.

### Exhaustion and add-ons

Notify at proposed 75%, 90% and 100% usage. Block new resource-consuming operations when exhausted; preserve core access and existing media during the retention window. No automatic overage billing. Proposed post-launch add-ons: 10 GB $2.99/month, 50 GB $9.99/month, 5,000 participant-minutes $9.99; validate before sale. Do not promise unlimited calls.

## 06  Billing and subscription lifecycle

### Provider strategy

Web: Stripe Billing. iOS and Android: applicable StoreKit / Google Play Billing requirements; evaluate RevenueCat for individual mobile subscriptions. Keep Stripe Connect for eligible real-world sports transactions. Team and organization purchase channels must be verified against current storefront and distribution rules. No client-reported purchase may activate entitlements.

| Action | Required behavior |
|---|---|
| Purchase / upgrade | Verify provider receipt or event server-side; activate correct scope. Disclose price, term, tax and renewal. |
| Trial | 14 days individual; 30 days workspace. Prevent repeat abuse; disclose auto-renewal and cancellation. |
| Renewal / failure | Reconcile verified provider status; proposed seven-day web grace, store-specific verified grace states. |
| Cancel / downgrade | Keep paid access through term unless provider revokes; downgrade at period end. |
| Restore / refund | Revalidate purchase ownership and provider state; revoke refunded or revoked benefits as appropriate. |
| Ownership transfer | Confirm billing responsibility separately from team ownership. |
| Price changes | Advance notice and consent where required; version catalog and preserve existing terms. |
| Expiration | Core records remain; block new premium operations; proposed 90-day excess-media transition with notices and export. |

After transition, excess media may be removed only under disclosed retention policy; do not delete ordinary records for nonpayment. Preserve financial records as required. Recording retention and legal holds require separate policy. Proposed launch partner discount: 50% first year, limited eligibility and documented expiry.

## 07  Technical architecture

Proposed Fastify billing module: apps/api/src/billing/{routes,service,catalog,entitlements,usage,reconciliation}.ts; provider adapters for Stripe, Apple and Google; shared contracts in packages/shared/src/billing.ts. Flutter and Next.js consume the same authoritative entitlement model.

| Collection | Purpose |
|---|---|
| billingPlans / billingPrices | Versioned feature catalog, currency, price and effective dates. |
| billingAccounts / subscriptions | Billing owner, scope type/id, provider IDs, status, period start/end, cancellation flag. |
| entitlements/{scopeKey} | Derived effective plan, feature flags, allowance and coverage source; server-only writes. |
| usageCounters/{scopeKey}/periods/{periodId} | Stored bytes and period-based usage; distinguish persistent storage from monthly minutes. |
| usageReservations | Idempotency key, scope, resource, quantity, expiry and settlement state. |
| billingEvents / billingInvoices | Verified provider event deduplication, invoice references, reconciliation status. |
| billingAuditLogs | Actor, scope, action, timestamp and reason; restricted access. |

### Proposed API

GET /v1/billing/plans; GET /v1/me/subscriptions; GET /v1/me/entitlements; GET /v1/teams/:id/entitlements; GET /v1/teams/:id/usage; POST /v1/billing/checkout; POST /v1/billing/portal; POST /v1/billing/purchases/verify and /restore; POST /v1/billing/webhooks/{stripe,apple,google}; POST /v1/billing/add-ons/checkout.

### Security and consistency

Resolve scope membership and permission before entitlement. Verify webhook signatures, deduplicate provider event IDs, handle out-of-order events by fetching authoritative status, retry safely and reconcile periodically. Never store card data or log receipts/secrets. Use least-privilege billing access, audit changes, and separate subscription revenue from host settlement liabilities. Direct reads only for authorized projections; all authoritative writes through backend.

## 08  Financial model and monitoring

Illustrative steady-state annual gross revenue: 12 × sum of active monthly subscriptions at list price + eligible paid event volume × 3%. Excludes annual discounts, churn, refunds, tax, billing commissions and operating costs. Paying teams exclude organization-covered teams.

| Scenario | Athletes | Subscriptions | Transactions | Total |
|---|---|---|---|---|
| Early | 1,000 | $5,394 | $9,600 | $14,994 |
| Growing | 10,000 | $65,921 | $48,000 | $113,921 |
| Established | 50,000 | $389,484 | $240,000 | $629,484 |

Assumptions: 3%, 5%, 7% individual conversion respectively; 10/100/500 paying teams; 5/50/250 communities; 1/10/50 organizations; 20/100/500 tournaments annually, 32 entries each at $500. These are scenarios, not forecasts. Values recalculated from the stated inputs.

### Contribution margin

Target at least 60% after billing commissions and attributable variable infrastructure/support costs. Example: $19.99 Team Pro less assumed 15% billing commission ($3.00), $1 storage/bandwidth, $4 meetings and $1.50 other variable costs = $10.49 contribution (52.5%). This misses target; adjust allowance or pricing before sale. Fixed expenses and taxes excluded.

### Operational controls

Initial infrastructure target $50–$150/month. Track MRR, ARR, paid conversion, churn, retention, trial conversion, gross payment volume, net transaction revenue, refunds, chargebacks, cost per workspace, storage egress, meeting usage and contribution margin by plan/channel. Budget alerts are not hard caps; use application controls and provider monitoring. Review costs monthly and before price changes.

## 09  Delivery and acceptance

| Phase | Deliverables |
|---|---|
| Before launch | Free core; approved payment safeguards; entitlement catalog; server quotas; usage reconciliation; cost alerts; no general advertising. |
| Early post-launch | Team Pro pilot, billing verification, trials, renewal/cancellation, restoration and reporting. |
| Post-launch | Individual, community and organization plans; annual terms; optional add-ons; evaluate season passes. |
| Future | Tournament Pro pass, verified sponsored discovery, partnerships and enterprise licensing. |

### Acceptance criteria

- Free users retain core features and data access regardless of premium status.
- Verified purchase activates only the intended scope; duplicate or out-of-order events do not double-grant benefits.
- Renewal, cancellation, failed payment, refund and restore follow verified provider state.
- Organization coverage and team membership changes do not grant unauthorized content access or duplicate billing.
- Concurrent uploads and meeting sessions cannot exceed reserved capacity; expired reservations are released.
- Downgrade preserves core records and provides notice/export for excess media.
- Legacy Firebase writes cannot bypass quotas; provider outage cannot grant unverified premium access.
- Subscription invoices and marketplace settlement funds reconcile separately; staff actions are audited.
- Test Flutter and Next.js parity, sandbox purchases, provider webhook replay, security rules, concurrency and cost alerts.

## 10  References and open decisions

### Repository references — development branch

https://github.com/brianrhonea/frisbee_app/blob/development/packages/shared/src/payments.ts

https://github.com/brianrhonea/frisbee_app/blob/development/docs/product-spec.md

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/app.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/media/service.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/videos/service.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/meetings/service.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/limits/writes.ts

https://github.com/brianrhonea/frisbee_app/blob/development/firebase/storage.rules

https://github.com/brianrhonea/frisbee_app/blob/development/firebase/docs/cloud-limits.md

https://github.com/brianrhonea/frisbee_app/blob/development/docs/ARCHITECTURE.md

### External implementation references (not refreshed)

https://developer.apple.com/app-store/review/guidelines/  
https://support.google.com/googleplay/android-developer/answer/9858738  
https://docs.stripe.com/billing  
https://firebase.google.com/pricing  
https://livekit.com/pricing

### Open validation

Confirm provider pricing, app-store rules, taxes, billing commissions, RevenueCat suitability, recording retention, actual resource costs, add-on prices, exact annual prices and grace periods. Validate organization pooling and coverage transition rules. Reconcile stale payment/refund documentation with Document 10. No application tests, live billing inspection or independent policy verification were performed; no repository changes made. UI design deferred to Document 17.
