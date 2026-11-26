<!-- Converted from Stall10_15_Statistics_Performance_Analytics.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# Statistics & Performance Analytics

DOCUMENT 15  /  VERSION 1.0  /  25 NOVEMBER 2026

Approved product direction • Engineering specification • Pre-launch

### Purpose

Make Stall10 a reliable record of athletic performance across games, seasons, competitions and training. Preserve the existing ultimate tracker while separating sport-specific rules from shared recording, verification and aggregation services.

### Scope

Flutter and Next.js clients, Fastify API, Firebase persistence, durable offline recording, athlete career records, training sessions and permission-scoped analytics. Ultimate first; additional sports follow validated modules. No UI mockups until Document 17.

### Release strategy

Prioritize integrity, offline recovery, authorized finalization and competition identity before advanced analysis. Core recording and basic analytics remain free. Premium analysis follows Document 11; video integration follows Document 16.

### Reading guide

02 Approved requirements; 03 Repository baseline; 04 Sport engine and recording; 05 Offline synchronization; 06 Metrics; 07 Identity and verification; 08 Competition and leaderboards; 09 Training; 10 Coaching and monetization; 11 Data and API; 12 Migration and acceptance; 13 Sources.

Status convention: approved = confirmed product policy; baseline = selected development-branch source evidence; proposed = engineering details requiring validation. No repository changes or live tests performed.

## 02  Approved requirements

| Decision | Approved direction |
|---|---|
| Recording | Free score-only, basic and advanced modes; explicit completeness. |
| Formats | Seven-player, five-player and configurable recreational rules, versioned. |
| Offline | Durable mobile and web recording, restart recovery, idempotent sync. |
| Statisticians | One primary recorder with controlled handoff; collaboration later. |
| Metrics | Preserve existing metrics; add possession efficiency, clean holds, conversion and optional attributes. |
| Field position | Optional detailed throws and locations after core reliability. |
| Ratings | Transparent role-specific versioned metrics; minimum samples; no universal rating initially. |
| Career | Stable roster identities, approved claims and cross-team seasonal aggregation. |
| Verification | Self-reported, device-recorded, team-recorded, team-verified, competition-verified, imported provenance. |
| Corrections | Authorized finalization, athlete requests, audited revisions and recalculation. |
| Competition | Canonical game IDs; separate official results and detailed team observations. |
| Leaderboards | Team and competition initially; public verified later with eligibility thresholds. |
| Training | Independent private sessions, optional sharing, structured strength and sport drills. |
| Development | Free goals, records and basic trends; premium advanced analysis. |
| Coaching | Private evaluations, selective feedback, premium advanced player and line analysis. |
| Portability | Basic CSV export; phased historical imports, fitness integrations and video sync. |

## 03  Repository baseline and gaps

| Reviewed source | Observed behavior / implication |
|---|---|
| packages/shared/src/stats.ts | Ultimate action types, seven-player line constant, game targets, point arrays, timeouts, stat sheets, schema limits and SaveQueue. Whole-game document; 900,000 JSON-character guard is not exact Firestore byte size. |
| packages/shared/src/stats_tracker.ts | GameTracker, line reuse, tournament roster, substitutions, undo history (200), game completion and timeout controls. |
| apps/api/src/stats/service.ts | Team-scoped game and roster operations; roster claim/unlink and manageTeam checks. Stable historical attribution needs stronger lifecycle. |
| apps/web/components/team/stats/useTracker.ts | Initial listener snapshot becomes local truth; dirty state in memory; 3s ordinary delay, 1s minimum gap, 2–30s backoff. Potential concurrent overwrite and restart loss. |
| apps/web/components/team/stats/SeasonStatsPage.tsx | Team member gate; aggregates returned games client-side, not explicit season projections. |
| apps/mobile/lib/domain/models/workout.dart | Workout post model; GPS run/ride/walk/hike, sprints, throwing, gym, agility, mobility; duration, distance, effort 1–10; free-text weight. |
| Repository tree | Mobile and web trackers, API routes, shared fixtures and tests exist. Test execution and deployed behavior not verified. |

### Priority gaps

Replace whole-document overwrites with ordered event batches; introduce durable local queues, explicit seasons, stable roster identity, provenance and server projections. Retain current tracker and formulas through compatibility adapters. Separate private training sessions from posts.

## 04  Sport engine and recording modes

### Shared engine

Own game identity, participants, recorder permissions, lifecycle, event ordering, revisions, provenance, synchronization, exports and summary orchestration. Sport modules define legal actions, scoring, periods, lineup constraints, positions and calculations. Trusted code validates versioned rule sets; never execute arbitrary stored formulas.

| Mode (all free) | Coverage |
|---|---|
| Score only | Live/final score and result; individual metrics unknown. |
| Basic | Goals, assists, turnovers, blocks, participation and lines where recorded. |
| Advanced | Individual throws/catches, possession sequences, pull timing, substitutions and optional action attributes. |

Store coverage by metric family, period and team. Unknown is null/not tracked, not zero. Mode changes create coverage boundaries. Do not calculate rates from incomplete denominators without an explicit partial-data label.

### Ultimate rules

Support seven-player, five-player and configurable recreational formats. Rule set captures lineup size, target score, periods/halftime, time cap, timeout allowance and substitution constraints. Validate against selected format; preserve historical rules. Existing game-to targets 7, 11, 13, 15, 17, 21 remain presets, not universal constraints.

### Future modules

Soccer: halves, goals, shots and substitutions. Basketball: periods, shots, rebounds and assists. Volleyball: sets, rallies and serves. Each module has independent fixtures and release gates; no ultimate-specific assumptions in shared game identity.

## 05  Offline recording and concurrency

### Durable recording

Proposed SQLite mobile and IndexedDB web queues. Persist each local event and its client-generated ID before acknowledging the action locally. Store authorized game snapshot, rule version, roster, last accepted sequence and pending events. Restore after restart; show pending, synchronized, rejected and conflict states. Offline recording applies to previously loaded games; do not promise first-time offline access.

### Synchronization contract

Batch ordered events through authenticated API. Transactionally check game state, recorder lease/epoch, permissions, expected revision and unique client event ID. Return accepted IDs, authoritative sequence and revision; duplicate IDs return original outcome. Retry transient failures with bounded exponential backoff; quarantine permanent failures for review. Never discard unsynced events silently. Server timestamps and client occurrence times remain distinct.

### Recorder ownership

One primary recorder per team game at launch. Proposed renewable lease with fencing epoch, explicit handoff and authorized recovery after expiry. Handoff flushes or transfers pending work; stale offline recorder batches cannot overwrite accepted history. Preserve conflicting events for authorized reconciliation. Assistants may view; simultaneous distinct-role recording later.

### Local privacy

Scope queues to account and workspace, protect device storage, clear or quarantine on logout and revocation; never expose another account’s cache. Revalidate authorization on reconnect. Authorized real-time listeners consume projections; all writes use API. Retain existing save timing as compatibility behavior until migration.

## 06  Ultimate metrics and analytical definitions

| Metric family | Definition / implementation note |
|---|---|
| Participation | Points played, O/D starts; substitutions receive participation credit under existing convention. |
| Scoring / possession | Goals, assists, touches, pickups, catches, completions; preserve existing plus/minus definition. |
| Throwing / receiving | Existing completion metric credits on-target drops to thrower; drops charged to receiver. Distinguish conventional successful possession completion. |
| Defense / pulling | Hand blocks, breakups, times beaten, pulls, out-of-bounds and average hang time; explicit attribution for forced turnovers. |
| Hold / break | Scored completed O/D points divided by completed O/D points respectively. |
| Clean hold | O points scored without turnover divided by completed O points with full turnover coverage. |
| Conversion | Scoring possessions / tracked offensive possessions; defensive takeaways converted to goals / eligible tracked takeaways. |
| Normalized rates | Goals, assists, turnovers or blocks per eligible point; show numerator, denominator and sample size. |
| Ratings | Preserve existing involvement-weighted O/D ratings; document formula version; role-specific comparisons only. |

Aggregate ratios by summing numerators and denominators, not averaging game percentages. Example: 9/10 and 20/40 yield 29/50 = 58%, not 70%. Null for zero denominator. Separate partial and finalized data.

### Optional advanced capture

After reliability gates, add throw type, reset/huck purpose, direction, measured or estimated distance, normalized start/end field coordinates, outcome, pressure and break-side flag. Never infer forced turnovers from an unattributed throwaway. Heatmaps and pull landing analysis require recorded coordinates and coverage.

## 07  Career identity, verification and corrections

### Stable attribution

Use immutable roster-participant IDs with season membership snapshots; preserve names and jersey numbers as historical display data. Account claims require authorized approval and evidence, prevent duplicate claims, and audit link/unlink. Reassignment must not silently transfer historical stats. Support unregistered roster spots; cross-team aggregation only after approved identity linkage and visibility checks.

| Provenance | Meaning |
|---|---|
| Self-reported | Athlete-entered; not independently verified. |
| Device-recorded | Captured by device; not proof of identity or accuracy. |
| Team-recorded | Authorized statistician observations. |
| Team-verified | Authorized reviewer finalized team observations. |
| Competition-verified | Official competition workflow confirmed relevant facts. |
| Imported | External source and original verification retained; not automatically verified. |

### Lifecycle

Draft → live → completed → under review → finalized; approved corrections create new revision. Completion does not equal verification. Record reviewer, timestamp, source, coverage and rule/formula versions. Live undo is an auditable reversal after sync; no destructive edit to finalized history.

### Corrections

Athlete or authorized participant submits affected event/metric, reason and evidence. Reviewer approves or rejects with reason; official result changes require competition authority. Preserve original and revised values, actor, timestamps and revision links. Recompute affected game, season, career and leaderboard projections idempotently. Notify affected users as permitted.

## 08  Competition integration and leaderboards

### Canonical records

Competition owns registration, divisions and schedules; competition game owns matchup and official result; team statistics records own detailed observations; calendar owns scheduling/attendance references. Existing eventId and tournamentId are migration anchors. Two teams may record observations for one canonical game; never count that game twice in competition standings. Conflicting score submissions enter official review, not last-write-wins.

### Leaderboards

Launch team and competition statistical leaderboards with authorized visibility. Later public verified leaderboards require eligibility thresholds, adequate coverage, sport, format, season, division and competition level. Define tie rules and sample thresholds per metric; display denominator and verification. Statistical leaders are not universal skill rankings. Exclude unverified or incomplete data from verified leaderboards; do not publish youth profiles by default.

### Privacy and safety

Apply Document 13: private GPS routes, approximate public location, youth restrictions, guardian consent and scoped oversight, blocked-user interaction restrictions without erasing necessary shared competition participation. Team-controlled stats plus athlete visibility; private coach notes and training data. Public official results only where permitted. Staff access least privilege, MFA and audited exceptional investigations. Entitlements never override authorization.

### Notifications

Use Document 12 preferences and durable delivery for finalized results, corrections, approved claims and followed competition milestones. No continuous push for every recorded action. Avoid sensitive details in previews.

## 09  Training and athlete development

### Independent training record

Private session is authoritative; social post references an explicitly shared, sanitized projection. Deleting a post does not delete the training record. Sharing never exposes raw GPS by default; optional privacy zones and youth restrictions apply. Support manual entry and GPS recording with source provenance.

| Category | Structured measurements |
|---|---|
| Running / cycling / walking / hiking | Duration, distance, pace/speed, optional route and intervals. |
| Sprints / agility | Distance, repetitions, split times, drill type. |
| Strength | Exercise ID/name, individual sets, reps, numeric load, unit, bodyweight indicator, optional notes. |
| Throwing | Throw type, attempts, completions, target distance and drill conditions. |
| Mobility / conditioning / practice | Duration, effort, intervals, skill objectives and drill completion. |
| Recovery | Optional private subjective observations; no medical diagnosis. |

Normalize measurements to canonical units while retaining original input. Existing free-text loads remain readable; only parse confidently, otherwise mark unknown. Personal records require comparable activity and measurement conditions. Free goals, records and basic trends; optional achievement sharing requires user approval.

### Integrations

Basic CSV export at launch; phased historical import with preview, mapping, deduplication and source attribution. GPS file import, Apple Health and Android Health Connect post-launch; Garmin/Strava later subject to provider terms and consent. Allow revocation; avoid importing unrelated health data. Video event IDs and timestamp references prepare Document 16.

## 10  Coaching and monetization

### Coaching analytics

Separate subjective evaluations from objective game statistics. Restrict by role, workspace and athlete; selective feedback sharing, audit access, youth safeguards. Evaluate positioning, decision-making, communication, skills and effort without a universal rating. Line analytics show points together, hold/break rates, clean holds, turnovers, pair performance and sample sizes. Opponent-adjusted comparisons require sufficient data and documented methodology.

| Plan | Analytics entitlement |
|---|---|
| Free | All recording modes, offline, basic game/tournament/season/career stats, basic leaderboards, training, goals, records, basic trends and CSV export. |
| Individual Plus ($4.99/mo) | Advanced personal trends and development comparisons. |
| Community Pro ($9.99/mo) | Advanced participation and activity reporting. |
| Team Pro ($19.99/mo) | Advanced player/line analysis, connections, heatmaps, coaching reports and custom dashboards. |
| Organization Pro ($49.99/mo) | Scoped pooled team comparisons and organization reporting. |

Prices carry forward from Document 11; premium features phased after launch. Preserve underlying records and basic access on downgrade. Server enforces entitlement, resource permission and usage limits separately. No paywall for corrections, export of core data or safety controls.

### Reporting

Advanced scheduled reports use authorized audiences and Document 12 delivery preferences. Avoid raw private training exports by coaches without explicit permission. Track aggregate feature usage and cost separately from athlete performance under Document 14.

## 11  Proposed data and API contracts

| Collection / record | Responsibility |
|---|---|
| sports; sportRuleSets | Versioned sport and format definitions. |
| games/{id}/participants | Canonical game and immutable roster snapshots. |
| games/{id}/events; revisions | Ordered events, correction lineage and provenance. |
| gameStatSummaries; teamSeasonStats | Versioned reproducible projections. |
| athleteSeasonStats; athleteCareerStats | Authorized cross-team aggregation. |
| competitionStatSummaries | Official result and eligible observation projections. |
| statCorrectionRequests | Evidence, review and decision. |
| users/{uid}/trainingSessions; trainingGoals; personalRecords | Private training and development records. |

Event contract: id, gameId, sportId, ruleVersion, schemaVersion, sequence, type, teamId, participantId, relatedParticipantId, periodId, possessionId, recordedAt, recordedBy, clientEventId, validated attributes. Include recorder epoch and source revision in batch envelope. Summary contract: scope, metric version, source revision, numerator, denominator, coverage, verification, updatedAt.

| Proposed API (prefix /v1) | Purpose |
|---|---|
| GET /sports/:sportId/stat-definitions | Rules and metrics. |
| POST /teams/:teamId/games; GET /games/:gameId | Create/read authorized game. |
| POST /games/:gameId/events/batch; /tracker-session | Sync and recorder ownership. |
| POST /games/:gameId/finalize; /corrections | Review and revisions. |
| GET /games/:gameId/stats; /teams/:teamId/seasons/:seasonId/stats | Game and season projections. |
| GET /athletes/:athleteId/stats; /competitions/:competitionId/leaderboards | Authorized career and leaderboards. |
| GET/POST /me/training-sessions; GET /me/training-summary | Private training. |
| POST /me/training-goals; GET /me/personal-records | Development. |

## 12  Migration, scalability and release gates

### Migration

Extract existing shared stats.ts and stats_tracker.ts into statistics/core and sports/ultimate modules via compatibility adapters; maintain Dart parity with shared fixtures. Backfill stable game/participant/event IDs and explicit seasons from verified mappings; flag ambiguous records for review. Shadow-calculate summaries and compare legacy values before cutover. Keep legacy reads during migration; never enable unsafe direct writes. Rollback preserves accepted events and revisions.

### Scalability

Incrementally project game summaries into season, career and competition aggregates with durable outbox, bounded workers, idempotent revision keys and periodic reconciliation. Paginate history; index only necessary fields; avoid full game downloads for profile reads. Track queue age, rejected events, conflicts, duplicate attempts, projection lag and Firestore cost. Proposed targets: local action acknowledgement under 100 ms after durable write; online projection within 5 seconds under normal load; validate on real devices. Respect overall $50–150/month early infrastructure budget and Document 14 alerts.

### Release sequence

Launch: preserve tracker, sport formats, three modes, durable offline, recorder handoff, basic summaries, verification/corrections, canonical competition links, private training, goals and basic leaderboards. Post-launch: advanced line/player analysis, field positions, coaching reports, collaborative recording, imports and fitness integrations, eligible public leaderboards. Future: additional sports and automated video-derived statistics.

### Acceptance gates

Test Dart/TS parity, seven/five/custom formats, complete offline game and restart recovery, duplicate retries, stale recorder rejection, handoff, substitution credit, missing versus zero, finalized correction and recalculation, historical claims, competition deduplication, weighted rates, privacy and youth rules, entitlement isolation, large game bounds and migration rollback. Run physical-device and browser failure tests before release. No tests executed in this assessment.

## 13  Sources and validation

Repository: https://github.com/brianrhonea/frisbee_app — development branch. Selected source review; branch is mutable, not a pinned release.

https://github.com/brianrhonea/frisbee_app/blob/development/packages/shared/src/stats.ts

https://github.com/brianrhonea/frisbee_app/blob/development/packages/shared/src/stats_tracker.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/stats/service.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/api/src/stats/routes.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/web/components/team/stats/useTracker.ts

https://github.com/brianrhonea/frisbee_app/blob/development/apps/web/components/team/stats/SeasonStatsPage.tsx

https://github.com/brianrhonea/frisbee_app/blob/development/apps/mobile/lib/domain/models/workout.dart

https://github.com/brianrhonea/frisbee_app/blob/development/apps/mobile/lib/data/repositories/workout_recorder/workout_recorder.dart

https://github.com/brianrhonea/frisbee_app/tree/development/packages/shared/fixtures/stats

### Related specifications

01 Architecture; 02 Athlete Profiles; 03 Social Feed; 04 Teams; 07 Calendar; 08 Discovery; 09 Marketplace; 11 Monetization; 12 Notifications; 13 Security; 14 Operations; 16 Playbooks & Video (next); 17 UI/UX (deferred).

### Validation and open engineering details

Exact lease durations, batch limits, minimum leaderboard samples, formula versions, coverage thresholds, import mappings, provider integrations and performance targets remain proposed or to be validated. No live Firestore inspection, security audit, test execution, device testing or cost benchmark was performed. No repository files modified.
