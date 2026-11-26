<!-- Converted from Stall10_02_Authentication_Athlete_Profiles.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# Authentication & Athlete Profiles

DOCUMENT 02  /  VERSION 1.0  /  APPROVED PRODUCT DIRECTION

Companion to Document 01 — System Architecture & Infrastructure

### Purpose

Create a durable athletic identity that connects social activity, teams, competition history and recruitment across sports. Launch with ultimate frisbee while keeping the underlying account and profile model sport-agnostic. Core identity and social functionality should remain accessible without a paid subscription (recommended).

### Approved requirements

| Area | Target behavior |
|---|---|
| Onboarding | Basic account details and age first; other personal data collected when needed. |
| Identity & relationships | One account, multiple sport-specific profiles; followers only. |
| Career & recruitment | Automatic team/season history plus manual entries; looking-for-team preferences and discovery. |
| Credibility | Self-reported and verified records clearly distinguished; optional athlete verification; appropriate paid-host verification required. |
| Username | Changes permitted with cooldown and old-name protection. |
| Youth & privacy | 13+; additional minor safeguards; minors private by default; existing visibility controls retained. |
| Public presence | Shareable public web profiles subject to privacy controls; standard layout with configurable sections. |

### Status convention

Current = supported by inspected source or architecture documentation. Target = owner-approved behavior. Proposed = implementation choice or release sequencing requiring validation. This specification is not evidence of a deployed or tested feature.

## 1 / Current implementation

Repository: brianrhonea/frisbee_app, development branch. Selected source reviewed in the preceding assessment; no runtime tests performed.

| Domain | Current evidence and gap |
|---|---|
| Authentication | Architecture describes Firebase Auth, email/password, username sign-in, Google and Apple, username gate and deletion. Provider linking, recovery and verification need testing. |
| Profile | ProfileService saves details, claims username transactionally and moves private fields to private/details. Current username claim is once-only. |
| Visibility | Section controls clear hidden stats, games and teams; teamStats removed when stats or teams hidden. Public browse returns a private profile card without posts. |
| Followers | FollowService supports users, teams and tournaments, private requests, cancellation, approval, removal and notification preferences. |
| Personal details | PersonalService encrypts records; shared schema requires legal name, phone, gender, address and guardian details for under-18s. New-account requirement applies from 2026-11-14. |
| Age | Under-13 details rejected; club membership gate requires 16+ and fails closed if age service unavailable. Existing members are not removed by that gate. |
| Account settings | Account routes support identity, agreements, read receipts and notification preferences; cache revalidation on identity changes. |

### Migration gaps

Replace full-details onboarding gate with capability-specific requirements. Add sport profiles, historical membership records, recruitment, verification provenance and username rotation. Verify remaining direct client mutations and remove them under Document 01. Complete frontend parity and test all privacy paths.

## 2 / Authentication & onboarding

### Target workflow

1. Choose email/password, Google or Apple. 2. Establish Firebase identity and verify email where applicable. 3. Collect display name, unique username, date of birth and required agreement acceptance. 4. Apply age and safety policy before enabling social access. 5. Offer optional sport, photo, bio and general location. 6. Enter the app; prompt for additional information only when a capability requires it.

### Capability-based collection

| Capability | Data required or proposed |
|---|---|
| Basic account | Authentication identity, display name, username, birth date, agreement version. |
| Competition registration | Legal name and other fields only when necessary for eligibility, waivers or event requirements. |
| Minor participation | Guardian contact and consent workflow as appropriate; not a substitute for verified consent. |
| Paid host | Appropriate payment-provider identity and business verification; separate from athlete verification. |
| Optional profile | Sport, positions, general location, photo, biography; no public residential address. |

### Authentication and recovery

Use Firebase Auth for credential operations; API verifies ID tokens and derives caller UID. Application-data mutations use the API, not direct Firestore writes. Proposed: verify email before sensitive actions, support password reset, provider linking with reauthentication, and session revocation after account compromise. Never merge accounts solely because emails match. Rate-limit username sign-in and avoid account enumeration.

### Onboarding migration

Separate encrypted birth-date completion from full personal-details completion. Enforce onboarding state at protected API operations, not just client navigation. Preserve existing encrypted records until a documented retention review; do not silently discard data. Make interrupted onboarding resumable across devices.

## 3 / Athlete identity & experience

### Standard profile layout

Header: avatar, cover, display name, @username, optional bio and general location, follow/message actions and permitted counts. Sections: Overview, Posts, Stats, Activity, Career, Achievements and Media. Recruitment appears only when enabled. Users can hide supported sections; layout remains consistent across mobile and web.

### Functional requirements

| ID | Requirement |
|---|---|
| PRO-01 | One immutable account UID; multiple sport profiles keyed by sport ID, with optional primary sport. |
| PRO-02 | Sport-specific positions, experience and competition levels use sport definitions, not global ultimate-only enums. |
| PRO-03 | Retain team/season history after departure; allow clearly labeled manual additions. |
| PRO-04 | Separate self-reported statistics and achievements from records verified by an authorized source. |
| PRO-05 | Allow opt-in looking-for-team status, sport, positions, competition level and broad region; discovery respects privacy. |
| PRO-06 | Preserve follower and follow-request workflows; no mutual friendship model. |
| PRO-07 | Shareable web profile uses the same visibility rules as mobile; hidden sections never appear in public metadata. |
| PRO-08 | Optional athlete verification is distinct from host eligibility and record verification. |

### User stories

As an athlete, I can leave a team without losing my history. As a captain, I can find eligible athletes who opted into recruitment. As a private user, I can approve followers without exposing restricted details to visitors. As a multi-sport athlete, I can switch sport views without creating a second account.

## 4 / Privacy, youth & trust

### Visibility rules

Keep existing public/private profile and section controls. Private profiles expose only an approved minimal directory card; approved followers may see permitted sections. Blocks override follow and recruitment access. Proposed: enforce visibility in API projections, Firestore rules, search, cached web pages, reposts and media access. Invalidate public caches on privacy changes.

### Youth safety

Keep minimum age 13 and current club age threshold 16 unless competition policy changes. Default minor profiles to private. Proposed launch safeguards: restrict unsolicited adult-to-minor messages, disable public recruitment and precise location exposure for minors, prevent public indexing of minor profiles, and require appropriate guardian approval before sensitive participation. Define guardian verification and age-transition policies before release. A birthday entered by a user is not verified age; guardian contact alone is not consent.

### Verification and record provenance

Use separate statuses for identity, competition records and paid-host eligibility. Suggested record states: self-reported, verified, disputed, revoked. Store verifier/source, timestamp and evidence reference with access restrictions. A verified athlete badge must not imply verified statistics or safe conduct. Use payment provider onboarding for paid hosts; avoid storing identity documents unless necessary.

### Username lifecycle

Target: allow changes with cooldown and old-name protection. Proposed defaults: 30-day change cooldown and 90-day old-handle reservation, subject to approval. Claim new handle and retire old handle atomically; preserve UID-based links. Prevent impersonation, reserved names and conflicting claims; never redirect an old handle to an unrelated new owner. Define deletion and reuse policy.

### Account lifecycle

Provide export, deletion and recovery controls. Proposed: require recent authentication for deletion, revoke sessions, remove private media and search entries, and document retention of competition records and payment records. Verify applicable youth/privacy obligations with qualified counsel before launch.

## 5 / Data model & API contracts

Existing paths below are supported by reviewed services. Proposed additions are illustrative contracts, not implemented endpoints or a final schema.

| Firestore path | Role / status |
|---|---|
| profiles/{uid} | Current: directory, public profile, privacy flag. |
| profiles/{uid}/private/details | Current: restricted profile details. |
| users/{uid}; usernames/{handle} | Current: settings and handle claims. |
| personalDetails/{uid} | Current: encrypted API-only personal details. |
| users/{uid}/follows/{key} | Current: follow relationship. |
| profiles/{uid}/followRequests/{uid} | Current: pending request. |
| profiles/{uid}/sports/{sportId} | Proposed: positions, experience, level, sport preferences. |
| profiles/{uid}/career/{entryId} | Proposed: team/season IDs, role, dates, source, status. |
| profiles/{uid}/achievements/{id} | Proposed: sport, title, source, verification state. |
| recruitmentListings/{uid_sportId} | Proposed: minimal searchable opt-in projection; server maintained. |
| usernameReservations/{handle} | Proposed: previous owner, reservedUntil; server only. |

### Data integrity

Use server timestamps, transactional uniqueness and idempotent history creation keyed by membership/season. Preserve canonical team IDs and historical display snapshots. Do not allow client-authored verification status. Keep private sport/career fields out of public projections; Firestore reads expose entire documents, not selected fields.

### Indexes and cost

Proposed composite indexes: recruitment sport + level + region + updatedAt; career sport + endDate; public directory keyword search. Validate actual query shapes before creating indexes. Paginate results and avoid one listener per career entry. Keep personal details and verification evidence inaccessible to client SDKs.

## 6 / API & integration design

| Endpoint | Status / purpose |
|---|---|
| POST /v1/me/username | Current: initial claim. |
| PUT /v1/me/profile/details | Current: profile edit. |
| PUT /v1/me/profile/privacy | Current: public/private transition. |
| PUT /v1/me/profile/visibility | Current: section visibility. |
| GET/PUT /v1/me/message-policy | Current: messaging preference. |
| PUT /v1/me/identity | Current: account identity. |
| GET/PUT /v1/me/agreement | Current: agreement status/acceptance. |
| GET/PUT /v1/me/personal | Current contract: encrypted details. |
| PUT /v1/me/personal/birth-date | Current contract: initial encrypted birth date. |
| PUT /v1/follows | Current: follow or request. |
| POST /v1/me/follow-requests/:uid/accept | Current: approve request. |
| PATCH /v1/me/username | Proposed: rotate handle. |
| PUT /v1/me/sports/:sportId | Proposed: update sport profile. |
| POST /v1/me/career | Proposed: manual history entry. |
| PUT /v1/me/recruitment/:sportId | Proposed: opt-in and preferences. |
| GET /v1/recruitment | Proposed: authorized, paginated discovery. |

### Service boundaries

Extend ProfileService and AccountService; isolate age policy, username rotation and verification logic. Team/season services publish idempotent career updates. Discovery consumes only authorized projections. Shared Zod schemas validate requests; Flutter mirrors contracts with parity tests. All application writes use authenticated API routes; Firebase Auth and approved signed media uploads remain separate infrastructure operations.

## 7 / Acceptance criteria & delivery

| Test area | Required result |
|---|---|
| Registration | All providers complete minimal onboarding; under-13 users cannot access protected features; incomplete accounts resume correctly. |
| Privacy | Private or hidden fields never leak through direct reads, search, web caches, reposts or media. Blocked users cannot bypass restrictions. |
| Youth | Minor defaults and messaging restrictions enforced server-side; age boundaries and missing birth dates tested. |
| Username | Concurrent claims yield one winner; cooldown and reservation enforced; UID links remain valid. |
| Career | Repeated membership events create no duplicates; leaving a team retains history; manual records labeled. |
| Recruitment | Opt-out removes search projection; privacy and age policies enforced; results paginated. |
| Verification | Only authorized verifier changes status; self-reported records remain distinguishable. |
| Parity | Flutter and Next.js pass equivalent core flows; API rejects unauthorized direct mutations. |

### Recommended sequencing

Launch: minimal onboarding, recovery, API migration, privacy and youth safeguards, followers, basic sport-aware profile and automatic career history. Next: manual career entries, recruiting discovery, username rotation and verification provenance. Later: highlight reels, advanced recruiting, shareable résumé and additional active sports. Sequencing is proposed, not a reduction of approved scope.

### Open implementation decisions

Confirm cooldown/reservation durations, guardian consent mechanism, age-transition rules, verification provider and evidence policy, retention periods, recruitment visibility for minors, and exact profile field inventory. Maintain the Document 01 infrastructure budget of $50–$150/month; measure incremental costs rather than assigning unverified estimates.

## 8 / Source references & limitations

Repository source references (development branch; branch may change):

### docs/ARCHITECTURE.md

Authentication, mobile navigation, data paths and existing flows.  
https://github.com/brianrhonea/frisbee_app/blob/development/docs/ARCHITECTURE.md

### apps/api/src/profiles/service.ts

Username claims, privacy transactions and visibility.  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/profiles/service.ts

### apps/api/src/profiles/routes.ts

Profile endpoints and cache revalidation.  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/profiles/routes.ts

### apps/api/src/account/routes.ts

Identity, agreements and account settings.  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/account/routes.ts

### apps/api/src/follows/service.ts

Follow relationships and requests.  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/follows/service.ts

### apps/api/src/personal/service.ts

Encrypted personal records and age checks.  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/personal/service.ts

### packages/shared/src/personal.ts

Personal schema and age thresholds.  
https://github.com/brianrhonea/frisbee_app/blob/development/packages/shared/src/personal.ts

### apps/api/src/teams/club_age.ts

Club eligibility gate.  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/teams/club_age.ts

### apps/api/src/browse/service.ts

Public profile and search projections.  
https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/browse/service.ts

Limitations: selected-source review only; no tests executed, live Firebase settings checked, or complete frontend parity audit performed. The attempted packages/shared/src/profiles.ts lookup returned 404; complete profile field inventory remains open. No repository files modified. Approved requirements are product direction, not a claim of implementation or legal compliance.
