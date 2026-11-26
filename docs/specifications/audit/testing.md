# Stall10 testing audit (read-only, baseline 39c8a53)

I did not run any suites. Pass and fail totals are the ones provided for today. File and case counts come from grep: `^\s*(it|test|testWidgets)\(`. Those figures are a **floor**, because loops, `it.each` and fixtures generate more cases at run time.

## Inventory table

| Package | Framework | Files | Grep cases / run total | Covers | Golden / E2E / load |
|---|---|---|---|---|---|
| packages/shared | Vitest 5 | 58 | 337 / 922 | Pure logic plus cross-platform fixture vectors: stats, tournament engine, drafts, rankings, recurrence, ics, payments, word filter, agreements, signup birth date | none |
| apps/api (fakes) | Vitest 5 + Fastify inject, `FakeStore` | 50 | ~1,180 / 1,307 | Every service: teams, membership, club age, posts, chat, conversations, payments (136 cases), export, moderation, stats, media, version | none |
| apps/api (emulator) | Vitest + Firestore/Auth/Storage emulator | 13 | ~100 / not run today | browse, calendar, data_export, me, membership, posts, profiles, public rankings, public tournaments, queries, teams, tournament_chats, uploads | none |
| firebase/functions `npm test` | Vitest 4 | 22 | 247 / 276 | Model functions for notifications, tournaments, drafts, rankings, account, meetings, discord, communities | none |
| functions `test:rules` | rules-unit-testing 6 | 5 | 362 / 377 | Firestore: 47 describe blocks (teams, joins, club 16+, chat, roles, DMs, posts, private profiles, list caps). Storage: 6 blocks. Also blocks, suspension, payments | none |
| functions `test:server` | Vitest + emulator | 4 | 15 / not run | Counter triggers, draft, calendars, rankings | none |
| functions `test/moderation` | Vitest | 2 | 9 / **never run** | photo_check, word_filter | none |
| apps/mobile | flutter_test + mocktail | 165 | 1,489 / 1,522 pass + 68 skip | ui 87 files (1,057), domain 22, data 18, shared_fixtures 23, routing 2, utils 2, screenshots 10 | none |
| apps/web | none | 0 | 0 | No `test` script (`apps/web/package.json`). The root `pnpm test` also filters it out with `--filter=!@stall10/web` | none |

Things that **do not exist** (checked with `find` and `pubspec.yaml`):
- `matchesGoldenFile`
- an `integration_test/` directory or the `integration_test` dependency (dev_dependencies has only mocktail)
- Maestro flows
- `playwright.config*`
- any k6, Artillery or Locust scripts

**Moderation tests run nowhere.** The script at `firebase/functions/package.json:12` lists `test/api … test/rankings` and leaves out `test/moderation`.

## CI matrix

| Workflow | Trigger | Runs | Gaps |
|---|---|---|---|
| `ci-node.yml` | `push`/`pull_request` on any branch, path-filtered (`:7-29`). `firebase/**` and `apps/mobile/**` are not in the paths | `check`: typecheck, `pnpm test` (shared + API fakes, `:44`), API and web builds. `api-emulator`: `pnpm test:api:emulator` (`:64`). `api-image`: Docker smoke test with a 401 check | No web tests. No rules, functions or server tests. A PR that only changes rules triggers nothing |
| `_deploy-backend.yml` (manual, via `deploy-backend.yml` `workflow_dispatch`) | manual | `npm test` (`:84-89`), then deploys `firestore:rules,…,storage` (`:110`) | **Deploys rules without `test:rules`.** `test:server` never runs |
| `_deploy-api.yml` | manual | shared + API typecheck and test (`:145-151`) | Emulator suite not re-run at deploy |
| `codemagic.yaml` `ios-testflight` | **push** to `development` only (`:52-57`), when `apps/mobile/`, `packages/` or `codemagic.yaml` change (`:59-65`) | `flutter analyze`, then `flutter test` (`:95-98`), then the IPA build | Not on PRs, so a regression is found only after the merge, and the paid build fails. No Android job |
| `ios-app-store` | push to `main` (`:127-140`, `<<: *ios`, so the same scripts) | same | same |

One correction to the readiness assessment: Flutter **is** tested in CI, but only after merge as part of the release build. It never gates a PR. Rules and server tests are missing from every pipeline.

## Skipped tests

Grep finds 46 `skip:` declarations. Loops expand them to **68** at run time:

| File | Declarations | Run-time count |
|---|---|---|
| `test/screenshots/acct_test.dart` | 14 | 14 |
| `hatstats_test.dart` | 12, two themes | 24 |
| `tournaments_test.dart` | 8, two themes | 16 |
| `play_test.dart` | 5 (`for owner in [true,false]` at `:347`) | 7 |
| `schedule_test.dart` | 2 | 2 |
| `chat`, `home`, `screens`, `teamhead`, `teams` | 1 each | 5 |

They all have **one reason**: `skip = _out.isEmpty ? 'pass --dart-define=SCREENSHOTS=<dir>'` (for example `screens_test.dart:91`, `acct_test.dart:78`). These are PNG generators for design review. They contain **zero `expect`** and compare nothing, so they are not golden tests.

No skips exist in any TypeScript suite: no `.skip`, `.todo`, `.only`, `xit` or `skipIf`.

## Failing rules tests analysis

Both failures are **test bugs**. The rules look correct, but that is unverified until the tests are fixed and run.

**1. "user posts › validates shared events"** (`firebase/functions/test/rules/firestore.rules.test.ts:3531`)
- At `:3550`, COACH creates `posts/ev`.
- At `:3558`, `assertSucceeds(setDoc(ref(PLAYER, "ev"), …teamId: null))` reuses the id `ev`. That makes the write an **update of COACH's post**.
- The author-update rule needs `resource.data.authorId == uid()` (`firebase/firestore.rules:2525`). The like/repost update rule needs `changed().hasOnly(['likedBy','repostedBy'])` (`:2541`). Both deny it, which matches the PERMISSION_DENIED in the memory note.
- **Fix:** use a fresh id (`"ev2"`).
- **Side effect:** every assertion after line 3558 never runs. That includes the bad-event loop (`:3563-3576`) and the edit of an old post. So `validSharedEvent`'s rejections are currently unverified.

**2. "lets people repost someone's post, once, with a note"** (`:3600`)
- `db = (uid) => env.authenticatedContext(uid).firestore()` (`:42`) returns a **new Firestore instance on every call**.
- `doRepost` (`:3608-3612`) and `undo` (`:3621-3623`) build a batch on one instance and refs on others. The SDK throws "document reference is from a different Firestore instance" on the client, so the request never reaches the rules.
- Every other batch in the file binds `const fs = db(uid)` once (for example `:320`, `:397`, `:1516`).
- **Consequence:** `validRepost` (`getAfter`, the id check, the private-original check, `:2412-2430`) and `repostMatches` (`existsAfter`, `:2471`) have **no passing rules coverage**. `posts.emulator.test.ts` goes through the API's Admin SDK, which bypasses the rules. After the fix the rules may still fail for a real reason, so run it before calling it resolved.

## Missing critical tests

| ID | P | Layer | Scenario | Target file | h |
|---|---|---|---|---|---|
| T-1 | P0 | rules | Fix both failing user-posts tests (id reuse, single `fs` instance) and re-verify the repost and shared-event rules | `test/rules/firestore.rules.test.ts:3558, 3602-3623` | 2 |
| T-2 | P0 | CI | Add `test:rules` + `test:server` (Java + emulator) on PRs touching `firebase/**`, and gate `_deploy-backend.yml` on them; add `test/moderation` to `npm test` | new `ci-firebase-rules.yml`; `functions/package.json:12` | 4 |
| T-3 | P0 | CI | Run `flutter analyze` and `flutter test` on PRs (GitHub Actions; leave paid Codemagic for release builds) | new `ci-mobile.yml` | 3 |
| T-4 | P0 | rules | A **former member** (removed, or left) is denied reads of chat rooms and messages, events, roster, files and stats games. The existing "roles and removal" tests check the team-doc update only | `firestore.rules.test.ts` (rules `/teams/{id}/chats/{roomId}/messages` `:1591/1631`, `/events` `:1014`, `/games` `:1476`) | 4 |
| T-5 | P0 | rules | A table-driven **deny matrix**: signed-out, outsider, other-team member, other-community admin, blocked user and former member × every team and community subcollection, plus storage paths (storage has only 3 unauthenticated checks) | new `test/rules/deny_matrix.rules.test.ts` | 8 |
| T-6 | P0 | functions emulator | `deleteAccount` end to end: auth user removed, posts and comments anonymised, team ownership handed over, storage removed, idempotent retry. Today only pure helpers are tested (`test/account/model.test.ts`) | new `test/server/account.server.test.ts` | 6 |
| T-7 | P0 | Flutter + web | Export/delete UI happy path and error path on both clients (API export already well covered, `data_export.test.ts`) | `test/ui/account_test.dart`; web (none) | 3 |
| T-8 | P1 | API emulator | **Concurrency on real transactions**. `FakeStore.transact` has no conflict detection or retry (`apps/api/test/fakes.ts:159-188`), so `Promise.all` tests on fakes don't model Firestore. Cover two teams paying for or claiming the **last division spot**, three payout sweeps, and a double checkout. None of the 13 emulator files touch payments or registration | new `apps/api/test/payments.emulator.test.ts`, `tournaments.emulator.test.ts` | 8 |
| T-9 | P1 | rules | RSVP: two members write `rsvps.<uid>` at the same moment and neither is lost; a member can't write someone else's entry; a former member can't RSVP (client write at `event_repository_firebase.dart:297`) | `firestore.rules.test.ts` "events" | 2 |
| T-10 | P1 | functions emulator | Reminder **idempotency**: `eventReminders` run twice gives one notice (`sentReminders` create guard, `notifications/triggers.ts:667-674`); a moved event gets a new one; a removed member gets none. Today only `reminderDue` and `reminderRecipients` are tested | `test/server/notifications.server.test.ts` | 4 |
| T-11 | P1 | rules/API | Stats concurrent edits: the client `.set()` replaces the whole `statsGames` doc (`stats_repository_firebase.dart:97`) and the API PUT replaces it (`stats.test.ts:100`). Last write wins, so two scorekeepers lose points. **Product decision needed** (lease or merge) before writing the test | `stats.test.ts`, rules "stats" | 3 + decision |
| T-12 | P1 | API | Chat send: duplicate client retry (same id) stores one message; blocked user; muted or suspended sender; a former member is refused | `apps/api/test/chat_rooms.test.ts`, `conversations.test.ts` | 3 |
| T-13 | P1 | API | Payments off: `paymentsConfig()` (`apps/api/src/server.ts:147`) is off when the return URL is missing, a live key is refused on dev, and checkout routes return the "not available" error when the app is built without config. `stripeFromEnv` and "aren't available" are already covered (`payments.test.ts:319, 374, 1196`). There is **no runtime pause flag** (Doc 18 "emergency pause"), so that is a feature question | `payments.test.ts`, new `server.test.ts` | 2 |
| T-14 | P1 | Flutter/API | **Minimum-version gate**: no implementation exists (grep for `minVersion`/`forceUpdate` finds nothing). This is a feature dependency, and its tests follow the feature (`version.test.ts` covers only the version header) | `apps/api/test/version.test.ts`, `test/ui/` | after feature, 3 |
| T-15 | P1 | E2E web | Playwright core journey on the emulator with synthetic users: sign up, create team, invite and join, event and RSVP, chat send, post, sign out, and visitor pages | new `apps/web/e2e/` + `playwright.config.ts` | 16 |
| T-16 | P1 | E2E mobile | Flutter `integration_test` (or Maestro) for the same journey on the iOS simulator and Android emulator | new `apps/mobile/integration_test/core_journey_test.dart` | 16 |
| T-17 | P1 | load | k6 at 10/50/100 VUs (Doc 18 §10) against an isolated env: 35% feed, 25% team/calendar, 15% chat, 15% competition; p95 < 750 ms | new `tests/load/k6/core.js` | 12 |
| T-18 | P2 | age | Club 16+ is well covered (code, invite, request: `membership.test.ts:973-1100`; emulator `:114`). Still missing: a team **changed to club level** with under-16 members, and league or draft placement into a club team | `membership.test.ts`, `drafts.test.ts` | 3 |
| T-19 | P2 | web | Web component tests (Vitest + RTL) for checkout and "pay another way", report/block, and the age form | new `apps/web/**/*.test.tsx` | 8 |

## Weak tests

- **Screenshot tests:** 46 declarations with no assertions (above). Either rename them as tools or convert some to golden tests.
- **Repost test's `assertFails` loop** (`:3626-3634`): even after the fix, a batch that throws on the client would be a false pass in a future refactor. Assert `PERMISSION_DENIED` explicitly.
- **Rules tests that "fail" on a missing doc:** for example `teamId: "no-such-team"` (`:3548`) passes because of an evaluation error, not a deliberate deny. That is acceptable but brittle.
- **Wall-clock use:**
  - Rules tests call `new Date()` 62 times. Invite codes live 45 s (`liveCode`, `:48`, seeded in `beforeEach`), so a slow emulator on CI could flake.
  - Flutter: `DateTime.now()` appears in 19 files, 35 uses (for example `event_navigation_test.dart` 6 and `personal_details_test.dart:91,104,118`, which build birthdays from `now.year - 15`). Only 3 files use `fakeAsync`/`withClock`. Not inspected one by one.
  - API fakes inject a clock (`personal.test.ts:9`, `FakeStore(() => now)`). That is good.
- **Sleeps:** none found. `vi.waitFor` appears once (`infra.test.ts:187`). No `Future.delayed` in Flutter tests.
- **Real network:** only localhost or the emulator (`infra.test.ts:186`, `teams.emulator.test.ts:58-73`).
- **Missing asserts:** file-level only, not per test. Apart from the screenshots, every file with fewer `expect` calls than tests was a `shared_fixtures/*` file, and those assert through `checkFixture` (`fixture_file.dart:44-54`). The `UPDATE_FIXTURES=true` mode rewrites the fixtures and passes, so keep it out of CI.
- **Fakes vs Firestore:** `FakeStore` applies transactions without contention (above), so concurrency tests on fakes are weak evidence.

## Suggested issues

1. **[P0] Fix 2 failing user-posts rules tests and re-verify the repost and shared-event rules** (T-1). Labels: rules, test.
2. **[P0] CI: rules, server and moderation tests on PRs; gate rules deploys** (T-2).
3. **[P0] CI: Flutter analyze and test on PRs** (T-3).
4. **[P0] Rules deny matrix, including former members and storage** (T-4, T-5).
5. **[P0] Account deletion server tests and client export/delete checks** (T-6, T-7).
6. **[P1] API emulator concurrency for payments, spots and payouts** (T-8), plus the RSVP rules (T-9).
7. **[P1] Reminder idempotency server test** (T-10).
8. **[P1] Decide stats concurrent-edit behaviour, then test it** (T-11; needs a product owner decision).
9. **[P1] Chat send: dedupe and deny cases** (T-12). **Payments-off config tests** (T-13), and a question for the owner about a runtime pause switch.
10. **[P1] Minimum-version gate feature and its tests** (T-14; needs approval, since it is a feature).
11. **[P1] E2E core journey on Playwright and Flutter integration** (T-15, T-16).
12. **[P1] k6 load test at 10/50/100 users** (T-17).
13. **[P2] Age-gate edge cases and web component tests** (T-18, T-19).
14. Update the test evidence table in `docs/specifications/readiness-assessment.md`: Flutter runs in CI but only after merge; moderation tests are unrun; and the 2 rules failures are test bugs.
