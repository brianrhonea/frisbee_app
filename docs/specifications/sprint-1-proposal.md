# Sprint 1 proposal (Nov 30 – Dec 6, 2026)

**Status:** approved by the owner on 2026-11-26. Q5 and Q6 answered yes and Q10 answered (about 20 hours a week) on 2026-11-26; #3a started.

**Baseline:** `feature/jan-4-release` at `28f3ebe`.

**Sources:**
- [`release-audit.md`](release-audit.md), issues #1–#32
- [`ui-migration-plan.md`](ui-migration-plan.md)
- the UI rework task board

## 1. Read-only audit at `28f3ebe` (2026-11-26)

**Code changes since the audit.** Since the audit baseline (`39c8a53`), only docs, test tooling (Phase 0) and the agent setup changed. No app, API, rules or functions behaviour changed.

**Audit findings re-checked at this commit.** All of these are still open:

| Finding | Still true at | Evidence |
|---|---|---|
| W-B1 | `apps/web/components/PersonalGate.tsx:64-66` | An API error sets the status to `null`, so the gate fails open |
| SEC-4 | `firebase/firestore.rules:644-646` | `level` is in the fields a manager can edit |
| M-B1 | `agree_terms_viewmodel.dart:16`, `choose_username_viewmodel.dart:39`, `personal_details_viewmodel.dart:21` | Onboarding sign-out calls `authRepository.signOut` directly |
| B-B2 | `firebase/functions/package.json:12` | The `test` script leaves out `test/moderation` |
| INF-1 | `codemagic.yaml:148` | `submit_to_app_store: true` |
| T-3 | `ci-node.yml` | No Flutter and no `firebase/**` jobs |
| INF-6 | `apps/api/src/server.ts:37` | Falls back to the dev project id |
| INF-8 | `apps/api/deploy/service.yaml:73-87` | The three Stripe secrets are required |
| INF-10 | `android/app/build.gradle.kts:36` | Release builds are signed with the debug key |
| INF-3 | `apps/web/app` | No crash reporting: there is no `global-error.tsx` |
| Home feed | `home_feed.dart:53-70` | Stream errors are swallowed |

### Baseline tests (run 2026-11-26 at `28f3ebe`, Windows)

| Suite | Result |
|---|---|
| Shared (`pnpm --filter @stall10/shared test`) | 922 / 922 passed |
| API (`pnpm --filter @stall10/api test`) | 1,307 / 1,307 passed |
| Web typecheck / Vitest | Passed / 5 of 5 passed |
| Functions unit (`npm test`) | 276 / 276 passed |
| Rules (`npm run test:rules`) | 375 passed, **2 failed**. These were already failing, and both are test bugs (#1): "validates shared events" and "lets people repost someone's post, once, with a note" |
| Flutter analyze | No issues |
| Flutter test | 1,529 passed, 68 skipped (screenshot generators), 0 failed |

**Not run:**
- Functions server and moderation suites
- API emulator tests
- Playwright (16 of 16 passed on 2026-11-25)

**Worktree check:** an isolated agent worktree now starts at `28f3ebe` on the release branch. This was verified after the restart.

## 2. Proposed sprint

**Goal.** The audit recommends doing security and CI first. This sprint does that, and starts the approved UI foundation (colour tokens) in parallel.

**Capacity.** An estimated ~48 h of agent work. Your review and device-test time is the real limit, and Q10 (weekly hours) is still open.

| # | Item | Lane | P | h | Depends on | Tests | Done when |
|---|---|---|---|---|---|---|---|
| 1 | Fix the 2 rules test bugs; run the rules, server and moderation suites on PRs touching `firebase/**`; gate rules deploys on them | C | P0 | 6 | — | Rules 377/377 green; moderation tests run | CI run shown on the branch |
| 2 | `flutter analyze` and `flutter test` on PRs in GitHub Actions (not Codemagic) | C | P0 | 3 | — | CI run | A PR touching `apps/mobile/**` runs them |
| 4 | Club `level` can't be changed by clients; the change goes through the API with an age re-check | A | P0 | 4 | — | Rules deny test; API allow/deny | A manager can't switch an under-16 team to club |
| 5 | Unregister the push device on **every** sign-out (onboarding screens included); clear other uids' tokens for the same device; sign-out doesn't hang offline | B | P0 | 4 | — | Unit tests per sign-out path | **iPhone account-switch test by you** |
| 3a | Server gate for age, Terms and verified email: `ageOk` claim, `requireCaller` and rules check it; birthday locked once set | A | P0 | 12 | **Q5, Q6** | Rules and API allow/deny, including REST-created accounts | Gated writes return the agreed error code |
| 3b | Web `PersonalGate` fails closed on API errors | C | P0 | 2 | — | Vitest: error → blocked | No skip on error |
| K1 | Agree the token list (colour, text, spacing names and values) | Orchestrator, then you | P1 | 2 | — | — | You approve the list |
| K2 / K4 | App: new colours behind the existing `AppColors` names; green only for success | B | P1 | 7 | K1 | Goldens light and dark; contrast checks | Goldens reviewed against the before-pictures |
| K3 / K5 | Website: new colours behind the existing CSS variables; green only for success | C | P1 | 5 | K1 | Playwright screenshots; axe | Screenshots reviewed |
| K8 | Contrast and Dart/CSS token parity tests | QA | P1 | 3 | K2, K3 | Self | Fails if a token differs between the platforms |

**Stretch, if capacity allows:**
- **#8:** payments off without Stripe secrets, a startup environment check, and the deploy-secret fallback fix (6 h, lane A).
- **K6/K7:** text-size, spacing, corner and motion tokens (6 h, lanes B and C).

## 3. Lanes (at most 3 implementation agents, in worktrees from the sprint baseline SHA)

| Lane | Agent | Owns |
|---|---|---|
| A | backend-developer | `apps/api/**`, `firebase/*.rules`, `firebase/functions/**` |
| B | flutter-developer | `apps/mobile/**` |
| C | web-developer | `apps/web/**`, `.github/workflows/**` |

**Order:**
1. Contract first: the `ageOk` claim name and the error code for gated writes. Lane A proposes them, and you approve. The app and web handling of that error is **Sprint 2**.
2. K1 is approved before K2–K5 start.
3. #1 and #2 (CI) land first, so later work is gated by them.
4. Lane A's rules changes merge before lane C's CI gate is finalised, because both touch rules tests.

**Reviews:**
- QA reviews each item.
- security-reviewer reviews #3a, #4 and #5.
- ui-ux-reviewer reviews K2–K5.

All work merges locally into `feature/jan-4-release`. At the sprint's end, a PR to `development` waits for your approval; nothing is pushed before then.

**Deploys.** Rules changes (#4, #3a) are deployed to dev only after you approve. Lane A also has a functions change for #3a (claim setting), which deploys by named group, with approval.

## 4. Not in Sprint 1, and why

| Issue | Reason |
|---|---|
| #6 minimum-version gate | Needs **Q19**. Sprint 2 |
| #7 crash reporting | New dependency; needs **Q15**. Sprint 2 |
| #9 prod stand-up and safe `main` merge | Needs **Q9** and your console steps. Sprint 2. **Until then, don't merge to `main`** (INF-1) |
| #10 Android pipeline | Needs a Play account and the decision whether Android is in the beta |
| Navigation tests N1–N12, components C1–C10, shells S1–S3 | Follow the tokens (Sprint 2–3) |

## 5. Decisions needed before Monday

1. **Approve this sprint**, or change the scope.
2. **Q5 and Q6:**
   - Email limited to Firebase verification and reset.
   - Adult-only (18+) launch enforced on the server.

   Both are needed for #3a. If they're not decided, lane A takes #8 instead.
3. **Q10:** answered 2026-11-26: about 20 hours a week.
4. **Early answers would help Sprint 2:**
   - **Q9:** beta on prod or dev.
   - **Q15:** Crashlytics plus Cloud Error Reporting.
   - **Q19:** the minimum-version gate and the video-upload flag.
   - **Q14:** separate dev and prod bundle IDs.
5. **Board.** Whether to also create GitHub Issues. The `gh` CLI isn't installed, so for now progress goes on the task board only.
