---
name: audit-feature
description: Read-only audit of one Hylite feature across the Flutter app, website, API and Firebase rules against its specification — what exists, gaps, defects, security and test coverage, with file:line evidence. Use when asked to audit, assess or check the state of a feature or screen.
argument-hint: "<feature or screen, e.g. 'team roster' or 'chat filters'>"
---

# Audit a feature

This skill is read-only. Do not change files, deploy, or use production data. Feature: $ARGUMENTS

## 1. Define the feature
- Find its specification sections in `docs/specifications/markdown/`, any mock-up, and the UI guide section.
- Write down whether it is **approved for January** or describes the future.

## 2. Map the implementation on every layer
| Layer | Where to look |
|---|---|
| App | `apps/mobile/lib/ui/<area>/` (views, view models), `lib/data/repositories/`, `lib/routing/` |
| Website | `apps/web/app/<route>/`, `apps/web/components/` |
| API | `apps/api/src/` routes, validation, authorization |
| Rules | `firebase/firestore.rules`, `firebase/storage.rules` |
| Functions | `firebase/functions/` |
| Shared | `packages/shared/` contracts and fixtures |

Use the route map (`docs/specifications/navigation-route-map.md`) to find screens.

## 3. Compare
- For each spec requirement, record one of:
  - **implemented** (with file:line)
  - **partial**
  - **missing**
  - **differs from spec**
- Check app/website parity.
- Check loading, empty, error and offline states, light and dark themes, and accessibility.
- Check authorization:
  - The server decides who may act; the client's claims are not trusted.
  - Visitors see only the documented pages (visitors: learn, events, teams, tournaments; youth rosters and community members stay private).

## 4. Tests
- List the existing tests per layer, and the gaps: unauthorized cases, invalid input, regression risks.
- Where useful, run read-only test commands and report the counts.

## 5. Report
Report:
- the requirement-by-requirement table
- defects, with severity, evidence and reproduction steps
- security concerns, marked as confirmed or potential
- test gaps
- recommended issues, with priority, estimate and the agent to do them

Mark every finding as **verified** (seen in code or tests) or **assumed**. Do not propose building future-only requirements; list them separately.
