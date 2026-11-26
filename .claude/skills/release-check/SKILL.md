---
name: release-check
description: Read-only Hylite release-readiness check for a build or date — branch state, versions, CI and Codemagic, test results, security blockers, environment separation, store requirements, rollback — ending in a go/no-go list for the owner. Use before a TestFlight or store submission, the Jan 4 beta, the Jan 18 release, or when asked if something is ready to ship.
argument-hint: "<target: beta | testflight | store | web | api> [date]"
---

# Release check

This skill is read-only: no pushes, merges, deploys, uploads or production changes. Target: $ARGUMENTS

Use the **release-engineer** agent for the CI and infrastructure parts. Run the steps below and collect the evidence.

## 1. Code state
- Branch and commit.
- Ahead/behind `development` and `main`.
- Any uncommitted changes.
- Is the release branch the one the owner intends? Jan work lives on `feature/jan-4-release`; `main` lacks the monorepo until it is merged.
- Versions: app `pubspec.yaml`, web, API and shared `package.json`. Check they agree with `node scripts/check-versions.mjs`.

## 2. Quality gates
- Run `run-regression all` and include e2e for a web release.
- Open P0 issues and blockers come from `docs/specifications/release-audit.md` and GitHub.
- Open critical or high security findings come from the last `security-audit`.
- Look for the owner's acceptance of the UI review (`review-ui`).

## 3. Build and CI (do not trigger paid builds)
- Read `codemagic.yaml` and `.github/workflows/*`. Confirm which workflow builds the target, and whether it runs `flutter analyze` and `flutter test`.
- Codemagic is pay-as-you-go. Only the owner starts a build.
- A local `flutter build` must use `--dart-define-from-file=secrets.local.json`, and only if the owner asks.

## 4. Environments
- Check dev and prod are separate:
  - Firebase projects
  - API URLs
  - Stripe mode
  - rules deployed per project
- Prod still needs rules and a database clean-up first (see memory and the release audit).
- Firestore/Storage rules: are the deployed rules the reviewed ones? Ask the owner, or compare without deploying.
- Monitoring, logging, backups and alerting: is each configured or missing?

## 5. Store and manual checks
- **iOS:** TestFlight build number, export compliance, privacy manifest, and App Store review notes, including a demo account.
- **Android:** a Play testing track (not set up yet, if still true).
- **Device checklist:** what still needs a physical device, including:
  - notifications
  - camera and microphone
  - LiveKit voice
  - background behaviour
  - deep links
  - large text
  - VoiceOver and TalkBack

## 6. Rollback
For the API, web, functions and app, check:
- Is there a previous good version, and how is it restored? (`rollback-api.yml`, `rollback-backend.yml`, Vercel promote, phased release)
- Is there a rollback owner and a rollback trigger?

## Report
Produce a go/no-go table:

| Area | Status (ready / blocked / unknown) | Evidence | Action and owner |
|---|---|---|---|

Then give:
- exact commands for the owner to run, for anything that needs a push, build or deploy
- the overall verdict: **GO**, **NO-GO** or **GO with conditions**

Never say a store approval or deploy happened unless you have seen it confirmed.
