<!-- Converted from Stall10_08_Discovery_Search.docx; the Word original is kept alongside. Do not edit the requirements here without updating the source. -->

# 08 / Discovery & Search

Version 1.0  |  Approved product requirements  |  25 November 2026

Product owner: Stall10  •  Status: specification, not implementation certification

### Executive summary

Discovery connects athletes to people, teams, communities, competitions, events and permitted public content. Search answers explicit intent; Explore surfaces relevant opportunities; Nearby locates real-world activities. All three share authorization, entity projections and search infrastructure.

### Operating constraints

Launch with ultimate frisbee and sport-agnostic contracts. Flutter and Next.js should achieve practical feature parity through the Fastify API. All writes pass through the API; authorized real-time reads may use Firebase. The solo developer’s $50–$150 monthly infrastructure budget is shared across the platform, not reserved for search.

### Success criteria

A new athlete can find an appropriate local activity without existing connections. A captain can find eligible competitions or opted-in recruits. A visitor can browse eligible public opportunities without an account. Search never exposes restricted data, and competitive rankings remain independent of recommendation and sponsorship scores.

### Document scope

Approved requirements, repository baseline, discovery workflows, technical contracts, privacy, measurement, release plan and acceptance tests. UI mockups and visual design are reserved for Document 17. Proposed implementation details are not additional approved product decisions.

## 01  Approved requirements

| ID / capability | Approved product decision |
|---|---|
| DS01 Universal search | Athletes, teams, communities, competitions, events and public content in one search. |
| DS02 Matching | Multi-word matching, autocomplete, typo tolerance and exact-match prioritization. |
| DS03 Geography | Current location, selected city, travel destinations and configurable radius. |
| DS04 Personalization | Interests, location, activity and social connections, with user controls. |
| DS05 Onboarding | Optional sport, experience, interests and location preferences. |
| DS06 Saved searches | Saved criteria and optional matching-opportunity alerts. |
| DS07 History | Private, synchronized recent searches; deletion and opt-out. |
| DS08 Content | Permitted public posts, hashtags, highlights and educational content. |
| DS09 Visitors | Eligible public teams, communities, events and competitions; sign-in for athlete search and interaction. |
| DS10 Competition | Live scores, results, rankings and followed competition updates. |
| DS11 Education | Free sport-specific beginner guides linked to local activities. |
| DS12 Controls | Not interested, hide, adjust interests and reset personalization. |
| DS13 Promotion | Future labeled promoted opportunities with relevance and verification safeguards. |
| DS14 Infrastructure | Firestore provider abstraction; migrate when metrics justify it. |
| DS15 Monetization | Free core discovery; premium organizer analytics and advanced recruitment. |

## 02  Repository baseline

Observed in selected development-branch source files reviewed for this specification. Existing code is not proof of deployed behavior.

| Area | Observed implementation / gap |
|---|---|
| Search | Browse service selects longest normalized word, truncates to 20 characters; repository uses keywords array-contains and bounded results. No comprehensive relevance or cursor established. |
| Explore | Web filters: tournaments, leagues, pickup, teams, groups, players. Mobile matches public event text and watches up to 30 upcoming tournaments; preview is not a complete index. |
| Competition | Live game rows, recent results, team and player rankings; team division informs ranking preview. Youth rankings excluded in mobile view model. |
| Capacity | Shared tournamentSpots computes accepted seeds against division capacity for team-entry registration; individual availability not covered by this helper. |
| Caching | Mobile discovery repository shares in-flight requests and caches for one minute; missing API returns empty results. |
| Education | Shared twelve-lesson ultimate guide, local reading progress and shared fixtures. |
| Privacy | Fastify host checks fail closed on missing or inconsistent directory/team records; youth restrictions and drafted league names protected. Legacy callable uses different checks. |
| Geography | Architecture documents OSM maps and Nominatim geocoding; comprehensive radius search not established. |

### Migration priority

Consolidate callable and direct keyword paths behind Fastify. Audit legacy access before retirement. Preserve shared cross-platform category aliases and fixtures. Distinguish service unavailable from zero matches.

## 03  Search and geographic workflows

### Universal search

A query returns typed, grouped results or a selected category. Normalize Unicode, case and whitespace; tokenize multiple words; prioritize exact username/name, then prefix and all-token matches, then bounded fuzzy matches. Autocomplete uses the same access rules. Never return private suggestions or counts. Use stable score/entity-ID cursors; bind cursor to query and filters.

Filters: sport, category, level, division, date range, distance, price/currency, registration state and capacity where applicable. Sort by relevance, distance or date; use explicit sort labels. Public content search excludes restricted posts, private messages and calendars.

### Nearby and travel

Accept a manually selected city or destination without changing home profile. Request device location only with permission; manual fallback is always available. Use geohash bounds, deduplicate candidates, compute actual distance and filter radius. Proposed presets: 5, 10, 25 and 50 miles with custom bounded radius; broader competition search may use region or national scope.

Index public venue coordinates and approved team/community regions only. Athlete discovery uses opt-in coarse city/region, never home address or precise live location. Do not expose youth venue details where restricted.

### User stories and edge cases

As a visitor, find public pickup by city and date; sign in before joining. As a traveler, search a destination without changing profile. As a captain, filter open competitions by division and entry fee. If location is denied, search by city. If a query is empty, show browse categories; if no results, suggest broader filters without revealing hidden entities. If an index is unavailable, return a clear retry state or safe limited fallback.

## 04  Recommendations and recruitment

### Personalization

Optional onboarding captures sport, experience, interests and coarse location. Missing preferences use nonpersonalized public opportunities and recency. Do not infer sensitive traits. Use explicit interests, authorized membership and mutual connections, activity and recency. Exclude blocked, hidden, ineligible and unauthorized entities before scoring.

| Signal | Illustrative local-opportunity weight |
|---|---|
| Geographic relevance | 30% |
| Sport and interests | 25% |
| Activity and opportunities | 20% |
| Social connections | 15% |
| Recency | 10% |

Weights are proposed, configurable and category-specific; missing signals are renormalized. Explain recommendations using safe reasons. Not interested suppresses the item or category as selected; reset clears learned preferences and restores neutral ranking. Do not conflate discovery with competitive rankings.

### Recruitment

Athletes opt in to recruitment, specify sport, level, division, position, season, availability and travel preferences. Teams publish roster needs and tryouts. Search leads to authorized applications, invitations and offers under Documents 02 and 04. Distinguish self-reported from verified statistics. Restrict minor recruitment and adult contact; never index private evaluations.

### Saved searches and history

Save normalized criteria, not result snapshots. Optional alerts evaluate new or materially changed matching opportunities, deduplicate by search/entity/version and honor notification preferences. Private history syncs across devices only when enabled; deletion and opt-out stop future retention. Proposed default: 30 days of recent history, subject to privacy policy approval.

## 05  Competition, education and monetization

### Competition discovery

Support tournament, league and hat categories; individual/team entry; sport, division, level, dates, location, price, host verification, registration and competition state. Show remaining places only from authorized current projections. Registration must recheck capacity, eligibility and price transactionally.

Preserve live scores, recent results, rankings and followed competition updates. Link to authoritative competition records. Clearly distinguish provisional results and verified final results. Ranking methodology and history belong to Document 15; paid placement never changes competitive ranking.

### Learning

Retain the existing ultimate guide and reading progress. Extend through sport-specific lesson configurations; link to beginner-friendly public activities. Foundational lessons remain free. Avoid claiming a venue or activity is beginner-friendly unless organizer metadata supports it.

### Entitlements

| Free core | Potential premium / future |
|---|---|
| Search, filters, nearby, recommendations | Advanced recruiting workflow and campaign analytics |
| Basic saved searches and optional alerts | Advanced organizer analytics and automation |
| Live scores, rankings, beginner guides | Specialized educational programs or historical analytics (proposed) |
| Organic opportunity listings | Future verified, clearly labeled sponsored opportunities |

Sponsored placements must pass relevance, eligibility, privacy and verification checks. Label paid placement, cap frequency, separate organic and paid metrics, provide reporting and moderation. Defer until meaningful organic traffic; no paid ranking advantage or guaranteed registration. Pricing and exact entitlements belong to Document 11.

## 06  Data and API contracts

### Proposed search projection

SearchRecord: entityType, entityId, sportIds, title, searchableText, keywords, category, division, competitionLevel, approved city/region/geohash, startsAt, endsAt, registrationStatus, priceMinorUnits, currency, visibility, updatedAt, sourceVersion. Key by entityType + entityId. Store only audience-appropriate fields; canonical records remain authoritative.

Retain profiles, teamDirectory and tournamentDirectory. Proposed searchIndex/{entityKey}, searchIndexJobs/{jobId}, searchMetrics/{periodId}; users/{uid}/discoveryPreferences/current, recentSearches/{id}, savedSearches/{id}, hiddenRecommendations/{entityKey}. Private user collections require owner authorization; writes through API.

### Provider abstraction

SearchProvider.search(request, context), upsert(record), remove(entityType, entityId). Firestore implementation first; future Typesense, Meilisearch or Algolia evaluation. Provider candidates are never trusted as final authorization.

| Proposed endpoint | Purpose |
|---|---|
| GET /v1/search; /v1/search/suggestions | Typed query, filters, cursor, bounded limit; safe suggestions |
| GET /v1/discover; /v1/discover/nearby; /v1/discover/recruitment | Personalized, geographic and opt-in recruitment results |
| GET/PUT /v1/me/discovery-preferences | Read/update private preferences |
| GET/POST /v1/me/saved-searches; PATCH/DELETE /v1/me/saved-searches/:id | Manage criteria and alert settings |
| DELETE /v1/me/recent-searches | Clear history |
| PUT /v1/me/hidden-recommendations/:id | Suppress or restore recommendation |

Existing browse routes remain during migration: /v1/public/search, /teams, /players/:uid, /events, /tournaments, /feed and /posts/:id under their existing prefixes. Route naming does not grant access. Return typed results, opaque cursor and safe error codes; never expose restricted totals.

## 07  Privacy, reliability and verification

### Authorization and index lifecycle

Visitors may browse eligible public opportunities; athlete search and interaction require authentication. Private adult cards only if permitted; minors default private with restricted discovery. Unlisted entities excluded. Block relationships enforced for signed-in results. Public post indexing requires both post audience and author visibility. No private messages, personal calendars, legal identity data or confidential evaluations in public index.

On source mutation, update authoritative state, enqueue idempotent projection job with version, invalidate caches and remove stale entries. Ignore out-of-order versions; retry failures with backoff and reconcile periodically. Recheck current visibility before serving results, including cached candidates. Never share personalized cache entries across users.

### Performance and abuse

Bound query length, candidate counts, radius, page size and concurrency. Debounce autocomplete; rate limit by account and visitor with distributed controls as needed. Use deterministic pagination and geohash indexes; measure read amplification. Avoid logging raw queries or coordinates by default.

### Acceptance tests

| Test | Expected outcome |
|---|---|
| Exact, multi-word, typo, prefix | Relevant authorized matches; stable order and pagination |
| Privacy change during index lag | Restricted result disappears immediately at serving boundary |
| Minor, blocked, unlisted, stale host | No prohibited card, location, suggestion or count |
| Geohash boundary / denied location | Correct radius filtering; manual city works |
| History opt-out / reset | No new history; cleared preferences and alerts behave as configured |
| Capacity changes / duplicate alert | Registration rechecks; one alert per eligible change |
| Mobile/web parity / API outage | Same filter semantics; explicit unavailable state |

## 08  Delivery, measurement and sources

### Phased implementation (proposed)

Launch: consolidate API search, exact and multi-word matching, basic autocomplete, category filters, geographic search, public discovery, recruitment, live competition and learning, privacy checks, basic recommendations and history controls. Post-launch: advanced typo tolerance, saved alerts, public content/hashtag search, improved ranking and provider evaluation. Future: sponsored opportunities, semantic search and ML only when justified.

Measure p95 latency, zero-result rate, search-to-entity click rate, completed join/registration conversion, reads per query, index lag and cost. Proposed warm API p95 target: 750 ms, aligned with Document 01; benchmark before adopting. Review provider migration when relevance, read amplification or cost consistently misses targets. No vendor pricing or actual traffic measurements verified.

### Source register

Repository: github.com/brianrhonea/frisbee_app • development branch. Reviewed paths (relative to repository root):

apps/api/src/browse/service.ts, routes.ts, repository.ts, visibility.ts

apps/mobile/lib/ui/explore/view_models/explore_viewmodel.dart

apps/mobile/lib/data/repositories/discover/discover_repository.dart

apps/web/components/explore/filters.ts

packages/shared/src/discover.ts

firebase/functions/src/browse/functions.ts

docs/ARCHITECTURE.md

Review limitations: selected source review only; no runtime execution, automated tests, full rules audit, performance benchmark or complete parity verification. No repository changes. Open implementation decisions: exact fuzzy matching method, retention and alert cadence, index limits, provider migration thresholds and premium entitlements. UI design deferred to Document 17.
