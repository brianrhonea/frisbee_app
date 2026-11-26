# Stall 10 specification library

Master index for the Stall 10 product and engineering specifications.
The Word documents are the originals and are kept unchanged. The Markdown
copies are for reading, searching and linking from the repository.

| Folder | Contents |
|---|---|
| `Originals/` | 20 Word specifications (source of truth for wording) |
| `UI-updated/` | 5 Word specifications with an added design appendix and concept image |
| `markdown/originals/` | Markdown conversions of `Originals/` |
| `markdown/ui-updated/` | Markdown conversions of `UI-updated/` |
| `markdown/assets/` | The 5 concept images extracted from `UI-updated/` |
| [`conflicts.md`](conflicts.md) | Conflicting requirements and how each is resolved or what needs deciding |
| [`readiness-assessment.md`](readiness-assessment.md) | Feature readiness against the January 4 beta and January 18 public release |
| [`development-plan.md`](development-plan.md) | Proposed plan to reach both dates, **awaiting approval** |
| [`release-audit.md`](release-audit.md) | Consolidated seven-agent audit (2026-11-25): bugs, security, tests, UI, infra, issue proposals, sprints, parallel lanes |
| [`audit/`](audit/) | The seven individual audit reports, with full file:line evidence, and the UI Implementation Guide |
| [`ui-migration-plan.md`](ui-migration-plan.md) | Screen-by-screen UI inventory summary, palette check, shared tokens and components, phased migration plan, **awaiting approval** |
| [`ui-inventory/`](ui-inventory/) | Full Flutter and web screen inventories against the UI Implementation Guide |

## Decision log

Decisions recorded here override the specifications where they disagree.
The specifications themselves are not edited; they will be revised to match
these decisions later.

| # | Date | Decision | Overrides |
|---|---|---|---|
| D-1 | 2026-11-25 | **Closed beta Monday January 4, 2027; public release Monday January 18, 2027.** The specifications predate this decision. | Doc 19 §01, §06–§07 (February 2027 target, six sprints from Nov 30, M3 beta in sprint 4, M5 launch in sprint 6); Doc 18 §15 phasing where it implies a later date |
| D-2 | 2026-11-25 | Approved UI-updated specifications take precedence for design decisions. | Doc 17 where the UI-updated concepts differ (see [`conflicts.md`](conflicts.md) C-02, C-03) |
| D-3 | 2026-11-25 | No new features or application code changes until the development plan is approved. | — |

Standing project decisions that also apply (from `CLAUDE.md` and earlier
sessions): exact web/mobile feature parity, with each platform keeping its own
design; no USA Ultimate data; all writes through the API as the target
architecture; Stall 10 collects tournament fees and pays hosts out (3%
platform fee paid by the payer); club teams are 16+.

## How to read the documents

Status language used throughout the specifications:

- **Approved**: product direction confirmed by the owner. Binding.
- **Baseline / Existing / Current**: what the author saw in the `development` branch on 2026-11-25. This describes source code, not verified behaviour.
- **Proposed**: an engineering default (numbers, schemas, route names, sequencing) that still needs validation. Not binding.

Precedence when documents disagree: decision log above → Doc 19 (latest
roadmap, final decisions) → the topic's own numbered document (01–18) → the
Master and Tournament Marketplace blueprints (earliest, broadest). For design
only: UI-updated appendices → Doc 17 → the rest.

## Document register

There is no Document 09 file. The Master Blueprint's library lists
"09 Tournament & league marketplace", and the **Tournament Marketplace
Blueprint** fills that slot. The Master Blueprint plays the role of Document 00.

| # | Title | Version / date | Markdown (original) | UI-updated | Approved requirement IDs | Scope in one line |
|---|---|---|---|---|---|---|
| 00 | Master Product & Technical Architecture Blueprint | undated, earliest | [md](markdown/originals/Stall10_Master_Product_Blueprint.md) | [md](markdown/ui-updated/Stall10_Master_Product_Blueprint_UI.md) · [image](markdown/assets/Stall10_Master_Product_Blueprint_UI_image1.png) | Pillars, 5-tab navigation, phases 1–5 | Product vision, navigation, event model, architecture, monetization hypotheses |
| 01 | System Architecture & Infrastructure | v1.0, 2026-11-25 | [md](markdown/originals/Stall10_01_System_Architecture.md) | — | Owner-approved table §1 | API-only writes, direct reads, multi-sport, budget $50–150/mo |
| 02 | Authentication & Athlete Profiles | v1.0 | [md](markdown/originals/Stall10_02_Authentication_Athlete_Profiles.md) | [md](markdown/ui-updated/Stall10_02_Authentication_Athlete_Profiles_UI.md) · [image](markdown/assets/Stall10_02_Authentication_Athlete_Profiles_UI_image1.png) | PRO-01…08 | Onboarding, sport profiles, career, privacy, youth, usernames |
| 03 | Social Feed & Engagement | v1.0 | [md](markdown/originals/Stall10_03_Social_Feed_Engagement.md) | [md](markdown/ui-updated/Stall10_03_Social_Feed_Engagement_UI.md) · [image](markdown/assets/Stall10_03_Social_Feed_Engagement_UI_image1.png) | SF-01…12 | Following/Explore, audiences, post types, training, media |
| 04 | Teams & Organizations | v1.0, 2026-11-25 | [md](markdown/originals/Stall10_04_Teams_Organizations.md) | [md](markdown/ui-updated/Stall10_04_Teams_Organizations_UI.md) · [image](markdown/assets/Stall10_04_Teams_Organizations_UI_image1.png) | R01…R14 | Seasons, ownership, permissions, recruiting, attendance, finances |
| 05 | Communities & Groups | v1.0 | [md](markdown/originals/Stall10_05_Communities_Groups.md) | — | CG-01…14 | Community entity, recurring events, waitlists, hat tournaments |
| 06 | Messaging & Communication | v1.0 | [md](markdown/originals/Stall10_06_Messaging_Communication.md) | — | MC01…15 | DMs, channels, voice, meetings, film review |
| 07 | Events & Unified Calendar | v1.0 | [md](markdown/originals/Stall10_07_Events_Unified_Calendar.md) | — | EC01…15 | Canonical events, sharing, recurrence, ICS, tournaments |
| 08 | Discovery & Search | v1.0, 2026-11-25 | [md](markdown/originals/Stall10_08_Discovery_Search.md) | — | DS01…15 | Universal search, nearby, recommendations, recruitment |
| 09 | Tournament Marketplace Blueprint | undated, early | [md](markdown/originals/Stall10_Tournament_Marketplace_Blueprint.md) | [md](markdown/ui-updated/Stall10_Tournament_Marketplace_Blueprint_UI.md) · [image](markdown/assets/Stall10_Tournament_Marketplace_Blueprint_UI_image1.png) | Host tiers, launch scope | Listings, host verification, checkout, transfers, admin |
| 10 | Payments & Fraud Prevention | v1.0, 2026-11-25 | [md](markdown/originals/Stall10_10_Payments_Fraud_Prevention.md) | — | PF01…15 | Invite-only paid hosting, holds, caps, refunds, ledger |
| 11 | Subscriptions & Monetization | v1.0, 2026-11-25 | [md](markdown/originals/Stall10_11_Subscriptions_Monetization.md) | — | Approved table §02 | Plans and prices, quotas, billing lifecycle (post-launch) |
| 12 | Notifications & Reminders | v1.0 | [md](markdown/originals/Stall10_12_Notifications_Reminders.md) | — | NR-01…16 | Channels, priorities, reminders, outbox, retention |
| 13 | Security, Privacy & Moderation | v1.0 | [md](markdown/originals/Stall10_13_Security_Privacy_Moderation.md) | — | SP-01…16 | Verification, youth, blocking, moderation, retention, incidents |
| 14 | Administration & Operations | v1.0, 2026-11-25 | [md](markdown/originals/Stall10_14_Administration_Operations.md) | — | Approved table §02 | Staff portal, support, host review, flags, jobs, metrics |
| 15 | Statistics & Performance Analytics | v1.0, 2026-11-25 | [md](markdown/originals/Stall10_15_Statistics_Performance_Analytics.md) | — | Approved table §02 | Recording modes, offline sync, provenance, training |
| 16 | Playbooks & Video Analysis | v1.0, 2026-11-25 | [md](markdown/originals/Stall10_16_Playbooks_Video_Analysis.md) | — | Approved table §02 | Tactical engine, revisions, media pipeline, film |
| 17 | UI/UX & Design System | v1.0, Nov 2026 | [md](markdown/originals/Stall10_17_UI_UX_Design_System.md) | — | Approved table §02 | Palette, navigation, breakpoints, states, accessibility, tokens |
| 18 | Deployment, Testing & Scalability | v1.0, 2026-11-25 | [md](markdown/originals/Stall10_18_Deployment_Testing_Scalability.md) | — | Approved table §02 | Environments, release pipeline, testing, load, recovery |
| 19 | Product Roadmap & Launch Strategy | v1.0, 2026-11-25 | [md](markdown/originals/Stall10_19_Product_Roadmap_Launch_Strategy.md) | — | Approved table §02; P0-01…12 | Launch scope, sprints, release gates, beta, metrics. **Dates superseded by D-1** |

### UI-updated documents

Each UI-updated file is identical to its original plus one "Design appendix"
(checked line by line). Every appendix shows two mobile concepts, Option A
("recommended starting point") and Option B ("complementary or alternate
emphasis"), and says: *"Concepts for discussion • Not current application
screenshots. Fictional example data. Existing requirements remain
unchanged."* Each appendix also sets the same responsive rule: on mobile,
stack cards and keep bottom navigation; on desktop, use a persistent
navigation rail with secondary cards alongside; provide loading, empty, error
and inaccessible states; and use accessible contrast, scalable text and
keyboard navigation.

| Appendix | Option A (recommended) | Option B |
|---|---|---|
| 00 Product experience | Home dashboard: upcoming practice + attendance, following feed, team announcement | Discovery hub: explore your sport, upcoming competitions, suggested athletes |
| 02 Athlete identity | Athlete profile: name, @handle, followers/teams counts, season stats, team history, Follow/Message | Career-first profile: Overview/Career/Stats tabs, current season, recruitment, looking for a team |
| 03 Social experience | Following: upcoming practice with RSVP, activity post, team announcement | Explore: For you / Ultimate / Local, highlights with engagement counts, community |
| 04 Team operations | Team dashboard: season, players, attendance %, upcoming practice, management tools (Roster • Schedule • Finances) | Organization console: teams, athlete counts, per-team cards, Members • Calendar • Reports |
| 09 Competition marketplace | Tournament discovery: event card, registration (team bid), divisions and rules, itemized checkout | Host console: registered/capacity, registration overview, completion evidence, payout status |

Visual language read from the images: a navy header band with a small
"STALL10" wordmark, green accent text for key figures and links, light grey
cards with subtle borders and 16-px-style rounded corners, and bottom tabs in
the order **Home · Discover · Teams · Schedule · Chat**.

## Conversion notes

- Converted on 2026-11-25 with a small converter that uses only Python's standard library (pandoc isn't installed). It handles Title/Heading styles, bullet lists, tables, bold/italic, line breaks and embedded images.
- **Verification:** every non-empty paragraph in each `word/document.xml` was checked against the Markdown after whitespace normalization, and the table count matched for all 25 files (212 tables in total). The only flags were 8 Doc 17 mock-up cells containing a literal `|` (escaped as `\|`). Their text is present and was checked by eye.
- No nested tables or content controls exist in the sources.
- Running page headers and footers (for example "STALL10 / PRODUCT & ENGINEERING LIBRARY") were left out because they hold no requirements.
- Word tables have no marked header row. A first row whose cells are all short labels (40 characters or fewer, no full stop) became the Markdown header row; otherwise an empty header row was added. A few label-style data rows still render as headers, for example Doc 17's palette table ("Canvas | #F4F4F5 | #09090B") and navigation table ("Home | Dashboard…"). No text is lost.
- The converter is saved as [`tools/docx2md.py`](tools/docx2md.py) (Python standard library only). Run it as `python tools/docx2md.py <in.docx> <out.md> markdown/assets ../assets`.
- `<` and `>` in the text are escaped (for example `Bearer &lt;Firebase ID token&gt;` renders as `Bearer <Firebase ID token>`).
- Doc 17's mock-up layouts are Word tables in the original, so they appear as tables here. They are labelled "Concept mockup • fictional content".
- Word metadata dates (`docProps/core.xml`) are a template default (2013), so they can't show which file is newer. Dates come from each document's own heading.
