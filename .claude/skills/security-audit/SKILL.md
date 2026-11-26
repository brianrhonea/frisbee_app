---
name: security-audit
description: Independent, read-only security and privacy review of a Hylite change set or area — authentication, resource-level authorization, Firebase rules, API permissions, cross-team access, private data, input validation, secrets, payments, data integrity. Use for any change touching auth, rules, API, private data or payments, or when asked for a security review.
argument-hint: "<change set (branch, commit range) or area>"
---

# Security audit

Target: $ARGUMENTS

## 1. Scope it
- **For a change set:** the orchestrator saves the diff for the reviewer. Run `git diff <baseline>..<head> > <scratchpad>/security-diff.patch` and `git diff --name-only ... > files.txt`.
- **For an area:** list the entry points. These are API routes, rules paths, callable functions and client writes.
- Read prior findings so known issues aren't reported as new:
  - `docs/specifications/audit/security.md`
  - `docs/reviews/2026-11-21-pentest.md`
  - `docs/reviews/2026-11-security-and-cost.md`

## 2. Delegate the review
Use the **security-reviewer** agent (read-only, Opus). Give it the patch and file list, the baseline, and the checklist below.

- **Authentication:** token verification on every API route; session handling; new-account gates.
- **Authorization:**
  - Membership and role are checked on the **server** for every team, community and organization resource, whatever the client claims.
  - Cross-team and cross-community access is blocked.
  - Visitor access matches the documented list.
- **Firestore and Storage rules:** reviewed independently of the API, with private fields, messages and media protected. Each rule change has matching tests in `firebase/functions` (`npm run test:rules`).
- **Input:** validation of every external input (schemas, sizes, enums); no injection into queries or HTML.
- **Personal data:** youth/minor data (the club 16+ rule), blocked users, private profiles, data export and deletion.
- **Integrity:** idempotency for retries; transactions for counters, rosters and spots; race conditions.
- **Secrets:** no keys in code, logs or client bundles. Check by grep for key patterns only; never open secret files.
- **Payments:** webhook signature checks, amounts computed on the server, Connect account ownership. Any payments change needs extra approval.
- **Dependencies and configuration:** new packages, CORS, headers, App Check.

## 3. Run what's safe
Run the rules and API emulator tests for the area (see `run-regression`) and include the results. Never run dynamic attacks against hosted environments.

## 4. Report
For each finding give:
- severity (critical, high, medium or low)
- whether it is a **confirmed** vulnerability or a **potential** risk
- affected files and lines
- evidence
- preconditions
- impact
- remediation
- the test that would prove the fix

**Critical or high** findings block integration and release until fixed and re-verified. Report them to the owner immediately.
