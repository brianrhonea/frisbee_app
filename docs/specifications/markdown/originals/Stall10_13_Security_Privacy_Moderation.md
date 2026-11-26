<!-- Converted from Stall10_13_Security_Privacy_Moderation.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# 13  Security, Privacy & Moderation

PRODUCT & ENGINEERING SPECIFICATION  /  VERSION 1.0

Approved product scope • Development branch baseline • Proposed engineering contracts

### Executive summary

Stall10 must protect athletes, youth participants, private communications, sporting records and financial transactions. Security is a free core capability. Launch ultimate first, with sport-agnostic policies. Apply least privilege, server-authoritative writes, privacy by default, accountable enforcement and data minimization.

### Scope and dependencies

Document 01 governs API writes and authorized direct reads; 02–08 establish profile, social, workspace, messaging, calendar and discovery privacy. Documents 09–10 govern paid hosting and financial risk; 11 preserves free safety features; 12 governs secure notifications. Document 14 owns detailed staff workflows; 17 owns UI design.

### Reading guide

| Section | Subject |
|---|---|
| 02 | Approved requirements |
| 03 | Repository baseline and gaps |
| 04 | Authentication and authorization |
| 05 | Youth safety and guardian consent |
| 06 | Privacy, location and blocking |
| 07 | Moderation and appeals |
| 08 | Data protection and retention |
| 09 | Staff, financial security and incidents |
| 10 | Technical contracts and abuse controls |
| 11 | Release gates and references |

Status convention: approved = user-confirmed policy; baseline = observed source behavior; proposed = implementation detail requiring validation. No UI mockups included.

## 02  Approved product requirements

| ID | Approved requirement |
|---|---|
| SP-01 | Verified email for interactive features; optional athlete MFA; mandatory staff MFA; risk-based sensitive-action verification. |
| SP-02 | Verified guardian relationships and recorded youth consent; restrict features pending required consent. |
| SP-03 | No independent under-13 accounts; evaluate guardian-managed records later. |
| SP-04 | Restrict private adult-to-minor messaging; favor authorized supervised team communication. |
| SP-05 | Guardian consent management, relevant team/event information, safety alerts and limited oversight; no unrestricted message access. |
| SP-06 | Review guardian access at 18; preserve privacy settings. |
| SP-07 | Approximate public athlete location; private GPS routes by default; optional privacy zones; restricted youth sharing. |
| SP-08 | Block personal interactions and recommendations; preserve necessary shared sporting participation. |
| SP-09 | Quarantine media requiring screening; retry failures; human review for significant enforcement. |
| SP-10 | Scoped warnings, removals, temporary restrictions, workspace bans and permanent platform bans. |
| SP-11 | Appeals of significant enforcement within proposed 30 days. |
| SP-12 | Least-privilege staff roles, MFA, report-specific evidence and audited exceptional investigations. |
| SP-13 | Proposed 30-day deletion target, 12-month security logs, 180-day ordinary moderation evidence; separate legal retention. |
| SP-14 | Documented incident response, emergency switches, access revocation and appropriate notifications. |
| SP-15 | Core security tests before launch; youth and paid hosting safeguards before respective access. |
| SP-16 | Publish privacy, community, youth safety and vulnerability disclosure policies; accessible reporting. |

Additional requirements: none. Numerical policy parameters remain subject to legal and operational validation.

## 03  Repository baseline and gaps

| Area | Observed source behavior |
|---|---|
| Authentication [1] | Firebase bearer ID tokens; configurable App Check; broad staff claim. |
| Moderation [2–5] | Server-only reports and reciprocal blocks; deterministic reporter/target ID; text and image URL snapshots; team queues hide reporter identity; staff remove, dismiss, warn, suspend or unsuspend; team remove/dismiss. |
| Account / personal [6–7] | Versioned terms acceptance; encrypted personal details and birth date; server age checks; guardian contact information is not verified consent. |
| Database / media [8–9] | Rules restrict private resources and server-only collections, but legacy direct user, event, notification and device writes remain. Authorized direct media uploads remain. |
| Image screening [10] | Cloud Vision SafeSearch on eligible uploads; unsafe files and thumbnails deleted; provider failure leaves photo in place. |
| Payments [11] | Documented first-payout approval, delayed release, self-payment restriction, dispute recovery and reconciliation; bank change does not reset approval in documented baseline. |
| Privacy [12] | Draft policy with unresolved youth and organizer disclosure questions; describes deletion and retention, not proof of completed implementation. |

### Release-critical gaps

Complete API migration, test media authorization and revocation, enforce applicable App Check, replace broad staff access, implement guardian consent and adult/minor communication controls, quarantine required media, preserve evidence securely, implement appeals and financial gates, finalize legal policies. Existing test files are not evidence of passing tests.

## 04  Authentication and authorization

### Account protection

Retain Firebase Authentication. Require verified email before posting, messaging or organizing; allow necessary onboarding, account recovery and safety reporting without that gate. Offer athlete MFA; mandate staff MFA and previously approved financial MFA. Require recent authentication and risk-based step-up for credentials, ownership transfer, payout changes, sensitive exports and deletion. Notify verified contacts of sensitive changes. Distinguish email, phone, athlete, guardian, organizer and financial verification; none guarantees trustworthy behavior.

### Authorization contract

Every API operation checks identity, account eligibility, current resource membership, role and capability, age and consent, blocks, source visibility, and step-up requirements. Firebase Admin SDK bypasses rules; shared backend helpers must enforce these checks. Subscription entitlement never grants resource access. Public routes return only privacy-filtered projections. App Check is defense in depth, not authorization; enforce where supported without breaking intended public access.

### Session and migration controls

Support session revocation within Firebase capabilities; validate token revocation for sensitive actions and maintain server-side restriction checks to avoid stale claims. Do not promise per-device token revocation until implemented. Inventory every legacy write, migrate to API, test old client behavior and deny retired paths. Direct authorized reads remain; media bytes may use narrowly scoped server-authorized upload sessions with expiry, ownership, quota and finalization checks. Default deny on unknown resources and actions.

### Acceptance

Test cross-account access, privilege escalation, expired/revoked credentials, suspended accounts, stale claims, malformed inputs, direct write bypass, former membership, and public projection privacy. No security decision depends solely on client UI.

## 05  Youth safety and guardian consent

| Age | Approved policy |
|---|---|
| Under 13 | No independent accounts. Future guardian-managed records require separate legal and product review. |
| 13–17 | Private by default; restricted discovery, location, messaging and recruitment; verified guardian consent before applicable features. |
| 18+ | Adult controls after age transition review; existing privacy remains unchanged. |

### Guardian workflow

Collect only necessary encrypted contact and age data; issue expiring single-use invitation to a separately authenticated guardian. Verify identity and relationship using a method to be selected with legal review. Record consent scope, policy version, time, verification method and revocation. Pending or revoked consent restricts applicable features. Do not disclose athlete details to an unverified claimant. Handle disputed guardianship through restricted support review.

### Communication and oversight

Restrict unrelated adult-to-minor private messages; favor authorized supervised team channels. Coach roles do not bypass safety rules. Apply age checks to group creation, invitations, mentions, attachments and existing conversations when eligibility changes. Guardian can manage consent, review relevant team/event affiliations, receive safety alerts and access authorized participation information; no impersonation or unrestricted message access. At 18, review and revoke obsolete guardian privileges without making the profile public.

### Youth release gate

Test consent invitation abuse, revocation, age transition, adult contact restrictions, youth search and location projections, notification redaction and report escalation. Paid hosting adult-only is proposed launch policy. No personalized ads for minors or live location sharing at launch. Legal review must establish applicable consent and reporting obligations; minimum age alone is not compliance.

## 06  Privacy, location and blocking

| Resource | Policy |
|---|---|
| Profiles / posts | Public, followers or private as applicable; selected workspace and only-me post options; youth restrictions override. |
| Training / GPS | Private by default; optional adult sharing and start/end privacy zones; restrict youth sharing. |
| Teams / communities | Resource visibility and section-level permissions; public team does not expose private member data. |
| Calendar / events | Authorized audience; availability-only access hides details; revocable feeds. |
| Messages / playbooks / statistics | Participant or permitted workspace access; no entitlement bypass. |
| Financial / personal details | Authorized financial roles or owner; encrypted sensitive personal information. |

### Privacy propagation

Apply most restrictive applicable policy to search, public projections, recommendations, media, notifications and caches. Recheck authoritative access before delivery and on resource open. Revoke or expire signed links; audit bearer URLs and legacy media access. Previously downloaded data cannot be recalled. Public athlete location is optional approximate city/region; never expose home address. Request device location only when necessary; background tracking only during explicitly authorized activity.

### Blocking

Preserve reciprocal server-only block records. Prevent direct messages, follows, direct social interactions, targeted mentions and recommendations; suppress related notifications. Shared team or competition participation is not automatically removed. Permit necessary shared operational information with controls to hide personal content and prevent direct targeting. Reporting remains available. Test group membership, shared events, search, media and notification paths for consistent enforcement.

## 07  Moderation and appeals

### Screening and reporting

Keep existing text filters and image screening; quarantine media requiring review until approved. Validate file type, size, ownership and content; retry transient provider failures, keep pending files inaccessible, and route persistent failures to review. Phase in video and malware screening; validate external URLs. Automated scores are not proof of misconduct. Human review significant penalties, with temporary protective restrictions when urgent.

Support reports for harassment, discrimination, threats, youth safety, sexual content, privacy violations, fraud, spam, impersonation, illegal activity, copyright and other guideline violations. Group related reports into cases; preserve restricted evidence with timestamps and hashes where appropriate. Image URLs alone are not durable evidence. Suspected illegal exploitative material requires specialized handling and legally required reporting, not ordinary copying.

| Severity | Proposed internal objective |
|---|---|
| Critical | Urgent protective action and human escalation; no 24/7 guarantee. |
| High | Review within 24 hours. |
| Medium | Review within 72 hours. |
| Low | Review within seven days. |

### Enforcement and appeals

Record scope, reason, duration, actor and case for warnings, removal, posting/messaging/hosting restrictions, workspace bans and platform suspension or permanent ban. Workspace moderators cannot impose platform sanctions. Notify affected users where appropriate without revealing reporters. Allow significant-decision appeals within proposed 30 days; record rationale and use independent reviewer when staffing permits. Solo-developer coverage and independence limitations require explicit escalation arrangements.

## 08  Data protection and retention

| Classification | Protection |
|---|---|
| Public | Privacy-filtered projections only. |
| Internal | Restricted operational service access. |
| Private | Authenticated resource authorization; encryption in transit and at rest. |
| Sensitive | Application-level KMS encryption for personal details; audited access. |
| Highly restricted | Separate access controls for keys, financial credentials and moderation evidence. |

Use TLS, provider encryption at rest, existing KMS personal encryption, Secret Manager, restricted service accounts and encrypted backups. Never store raw payment card or bank credentials. Hash revocable calendar tokens where feasible. Do not claim end-to-end encrypted messaging; evaluate later.

| Record | Retention |
|---|---|
| Deleted account operational data | Proposed 30-day target. |
| Ordinary notifications | 60 days (Document 12). |
| Diagnostic logs / backups | Proposed 30 days each. |
| Security audit logs | Proposed 12 months. |
| Ordinary moderation evidence | Proposed 180 days after closure. |
| Serious safety / financial records | Restricted case-specific or legally required retention. |

### Deletion and export

Durable backend jobs verify request, revoke access, resolve owned workspaces, remove eligible personal data/media and projections, anonymize appropriate shared history, preserve required financial/legal records and track completion. Legal holds override routine deletion; backup expiry and restore procedures must prevent resurrection. Provide free authorized export with expiring download, exclude other users’ private data, and audit completion. Validate actual deletion behavior against published policy.

## 09  Staff, financial security and incidents

### Staff access

Replace broad staff claim with scoped support, content moderation, youth safety, financial review, security and platform administration permissions. One operator may hold several roles initially. Require MFA, recent authentication, reason and append-only audit records for sensitive actions. Restrict private message access to report evidence or authorized exceptional investigation. Audit actor, target, scope, reason, timestamp and outcome; redact secrets. Use separate emergency access and review its use. Document 14 defines operational workflows.

### Financial integration (Document 10)

Invite-only paid beta; Stripe verification plus risk review; first three provisional events enhanced review and proposed $1,500 cap. Independent completion evidence; established three-day and provisional proposed 14-day holds. Bank/ownership change MFA, renewed approval and proposed 72-hour transfer freeze. Risk-based reserves 10–20% up to 90 days where permitted; optional refundable deposit, not universal. Full refunds including mandatory fees for host cancellation, fraud and platform errors; ledger, reconciliation and debt recovery. Provider/legal validation required; already transferred funds may not be stoppable.

### Incident response

Detect → contain → investigate → remediate → recover → communicate → review. Maintain emergency switches for uploads, paid hosting, eligible transfers, compromised integrations and account access. Revoke credentials, isolate affected services, preserve restricted evidence and assess impact. Notify affected parties and authorities as required; record decisions and recovery checks. Establish escalation contacts and a critical safety procedure before youth access. Stall10 is not an emergency response service.

## 10  Technical contracts and abuse controls

| Proposed collection | Purpose |
|---|---|
| guardianRelationships; consentRecords | Verified relationship, scope, version and revocation. |
| moderationCases/{id}/reports, evidence, decisions | Restricted case history; retain existing report IDs during migration. |
| moderationAppeals; accountRestrictions | Review lifecycle; scoped capability, reason, start/end and status. |
| staffPermissions; securityAuditLogs | Scoped roles and append-only sensitive action history. |
| securityIncidents; mediaReviewJobs | Incident tracking and quarantine state/retry. |
| dataExportJobs; accountDeletionJobs | Durable privacy requests with progress and expiry. |

### Proposed API contracts

GET /v1/me/security; GET /v1/me/sessions; POST /v1/me/security/revoke-all; GET/PUT /v1/me/privacy; POST /v1/me/data-export; POST /v1/me/account-deletion; POST /v1/guardians/invitations; POST /v1/guardians/invitations/:id/accept; POST/DELETE /v1/guardians/:id/consent; POST /v1/moderation/appeals; GET /v1/me/moderation/appeals; GET /v1/staff/moderation/cases; POST /v1/staff/moderation/cases/:id/actions. Reconcile existing routes before implementation. Existing /v1/reports and /v1/me/blocks remain.

### Abuse and reliability

Distributed rate limits for signup, messages, follows, reports, search, invitations and uploads; existing 30 reports/day limit needs urgent safety escalation path. Use bounded queues, idempotent actions, transactional restrictions and expiry checks. Monitor denial spikes, failed authentication, moderation backlog, quarantine failures, suspicious staff access and financial alerts. Keep sensitive payloads out of logs. Test horizontal scaling; per-instance limits alone are insufficient.

## 11  Release gates and references

### Release sequence

General launch: API migration, rule and authorization tests, staff MFA/audit, blocking/reporting, quarantine, basic appeals, export/deletion, incident controls and published policies. Youth access only after verified consent, communication restrictions and escalation tests. Paid hosting only after Document 10 safeguards. Post-launch: advanced guardian tools, behavioral detection, video screening and independent penetration testing (recommended before public launch where feasible). Future: under-13 managed records and E2EE evaluation.

Test unauthorized reads/writes, role escalation, revoked access, private media links, youth consent and age transition, blocked interactions, screening outage, workspace/platform sanctions, audit tampering, financial changes, entitlement bypass, deletion/export, secret leakage and backup restoration. Legal review: US children’s privacy, applicable state laws, consumer protection, copyright, payment obligations; international review before expansion. Publish terms, privacy, community and youth safety, vulnerability disclosure, retention/deletion, organizer and refund policies; subscription terms before billing.

### Source references

Repository: github.com/brianrhonea/frisbee_app, development branch. Reviewed paths (append to https://github.com/brianrhonea/frisbee_app/blob/development/):

[1] apps/api/src/auth.ts

[2] apps/api/src/moderation/service.ts

[3] apps/api/src/moderation/blocks.ts

[4] apps/api/src/moderation/routes.ts

[5] packages/shared/src/moderation.ts

[6] apps/api/src/account/service.ts

[7] apps/api/src/personal/service.ts

[8] firebase/firestore.rules

[9] firebase/storage.rules

[10] firebase/functions/src/moderation/photo_check.ts

[11] docs/payments-security.md

[12] apps/web/content/privacy.html

Review limits: selected source inspection only; no tests executed, penetration test, production IAM/rules verification or legal review. Guardian verification method, retention and response objectives require validation. No repository modifications. UI mockups deferred to Document 17.
