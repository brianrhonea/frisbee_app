---
name: run-regression
description: Runs Hylite's automated regression suites — Flutter, website component and browser tests, API, shared package, Firebase rules — on the current branch and reports exact counts with pre-existing failures separated. Use before and after changes, before integration, or when asked to run the tests.
argument-hint: "[all | app | web | api | shared | rules | e2e] (default: all except e2e)"
---

# Run regression

Scope: $ARGUMENTS. If no scope is given, run everything except `e2e`.

## Rules
- Run against local code, emulators and fakes only. Never touch production.
- Never skip, weaken or delete a test to get a pass. Never report a result you didn't run.
- Before anything else, record the branch and commit: `git rev-parse --abbrev-ref HEAD` and `git rev-parse --short HEAD`.

## Suites
Run each in its own directory and capture the summary line.

| Scope | Directory | Command | Notes |
|---|---|---|---|
| app | `apps/mobile` | `flutter analyze` then `flutter test` | About 1,500 tests, roughly 2 min. Goldens compare only on Windows. |
| web | `apps/web` | `pnpm typecheck` then `pnpm test` | Vitest |
| e2e | `apps/web` | `pnpm test:e2e` | Playwright starts `next dev` on 3000. API calls to 8787 fail unless `pnpm dev:api` is running, and these are reported, not failed. |
| api | repo root | `pnpm --filter @stall10/api test` | Add `pnpm test:api:emulator` when Firestore emulator coverage is needed. |
| shared | repo root | `pnpm --filter @stall10/shared test` then `node scripts/check-versions.mjs` | |
| rules | `firebase/functions` | `npm run test:rules` | Needs Java, which is installed. Two user-post tests were already failing. Confirm they still fail, and report them as known. |

For long suites, use `run_in_background` and wait for the notification.

## Report
| Suite | Command | Passed | Failed | Skipped | Duration |
|---|---|---|---|---|---|

Then list:
- **New failures:** test name, error excerpt, likely cause and owner.
- **Failures that were already there:** compare with the baseline run, or with `git stash` / the baseline commit if needed, read-only.
- **Not run:** anything not run, and why (missing emulator, OS, credentials).

Verdict: **PASS**, **FAIL** or **INCOMPLETE**.
