# Overnight report: Sprint 1 UI foundation (started 2026-11-26)

**Branch:** `feature/jan-4-release`. Merged locally only: **nothing pushed, deployed or merged to `development`/`main`.**
**Your decisions** are collected in §7. Each one has my default, which I used so work could continue.

## 1. Where things stand (morning summary, HEAD `ee068fe`)

**Sprint 1 is complete except for items that need your answers.** Everything is merged locally on `feature/jan-4-release`, independently reviewed, and the full regression passes. Nothing is pushed or deployed.

| Item | Status |
|---|---|
| K1 tokens | Done (approved) |
| K2/K3 colours | Merged. **Needs your visual OK** |
| K4/K5 green only for success | Merged, UI review fixes merged. **Needs your visual OK** |
| K8 token parity tests | Merged (`83ba28b`); no mismatches |
| #1 rules test bugs, CI for firebase | Merged; rules 381/381. CI untested until the first PR |
| #2 Flutter CI | Merged; untested until the first PR |
| #3b sign-up check fails closed | Merged on **website and app** (app added for parity after the security review) |
| #3a server age/Terms/email gate | **Not started. Waiting on D1 (Q5, Q6)** |
| #4 club level only via API with age re-check | Merged: API, app, website, rules, plus security fixes. **Deploy to dev needs your approval** (API first, then rules) |
| #5 push unregister on every sign-out | Merged. **iPhone account-switch test by you.** Server-side cleanup of the old account's device: **needs D11** |
| #8 payments off without Stripe, startup checks, no dev-secret fallback | Merged. **You need to set the GitHub variables/secrets listed in §8** |
| K6/K7 text, spacing, corner and motion tokens | Not started (stretch). K8 tests are waiting for them |

**Your morning list:**
1. Answer D1–D13 (§7).
2. Look at the colours (K2–K5); before/after pictures are in the scratchpad folders named in §9.
3. Approve, or not, the dev deploys for SEC-4.
4. Do the iPhone checks for #5.
5. Delete the leftover worktree folders under `.claude/worktrees/` (Windows refused to remove some: path too long).

## 2. K5 (website): what changed

- **Success green replaces indigo for "done/OK" states.** This covers:
  - form success notes and "username available";
  - completed sign-up steps and Learn sections read;
  - RSVP "Going" (pills, groups, your RSVP);
  - video "uploaded" and "Registration open";
  - accepted draft or tournament entries;
  - done checklist marks;
  - champions, wins and positive point differences or stats;
  - "spots left" and "Paid".
- **Indigo stays** for anything you choose or navigate:
  - chat event answers (your going/maybe/no choice);
  - selected tabs, rows and divisions;
  - links, buttons, unread dots and today markers.
- **Selected controls** now always have an indigo outline (2px) or an indigo bar, not just a pale tint. This covers:
  - segmented controls;
  - composer tools, reactions, divisions, playbook tools, call buttons and video marks;
  - settings, team menu, chat room and conversation rows;
  - the phone tab bar.

  A test checks about 34 rules for this and the 3:1 contrast.
- **Status pills:** every website tint-plus-text pill already passed 4.5:1 in both themes, so nothing needed darkening. A test now guards this.
- **Sidebar team colours:** the six-colour idea is kept. Three colours failed dark mode and were changed:
  - Purple `#5348b2` → `#665cc8`.
  - The old blue → the theme's team colour.
  - The old pink → the theme's personal colour.

  All six pass in both themes, with a test.
- **Seen only in code and tests, not by eye:** these states appear only on signed-in pages, and there is no test account or API data locally.

## 3. Work started overnight (approved Sprint 1 items)

At most three implementation agents ran at once.

| Lane | Items | Notes |
|---|---|---|
| App (flutter-developer) | K4, plus follow-ups 1–3 | Running |
| Backend (backend-developer) | **#1** fix the 2 rules test bugs, and make the moderation tests run. **#4** club level changes only through the API, with an age check; clients can't edit it directly | The rules change is a separate commit. It will be held back until the app and website stop writing `level` directly, otherwise editing a team would break |
| Website/CI (web-developer) | **#2** Flutter analyze and test on PRs. **#1 CI:** rules, functions and moderation tests on PRs touching `firebase/**`, and a rules-test gate before rules deploys. **#3b** sign-up check blocks on API errors | Workflows can't be run locally, so they are untested until the first PR |

**Not started:**
- **#3a** (server age, Terms and email check): waiting on Q5 and Q6.
- **#5** (push unregister): starts in the app lane after K4.

## 4. Lane C merged (`see git log: "Merge lane C"`)

- **#3b: the sign-up check now fails closed.** If the personal-details status or the Terms check errors, the member sees "Couldn't check your account" with **Try again**, instead of the app.
  - The legal pages stay readable.
  - "Not now" can't skip the error state.
  - Answers from an earlier account are ignored.
  - 9 new component tests; website unit tests 174/174.
- **#2 and #1 CI: new workflows, untested until the first PR.**
  - `ci-flutter.yml` runs Flutter 3.41.2 analyze and tests when `apps/mobile/**` changes.
  - `ci-firebase.yml` runs the functions tests, rules tests (with the emulator, firebase-tools 15.8.0, Java 21) and server tests when `firebase/**` or `packages/shared/**` changes.
  - `_deploy-backend.yml` now runs the rules tests before any rules deploy.

## 5. K4 (app) merged (`ea45f80`): green only for success, plus follow-ups 1–3

- **Success green** (`positive`) now marks done, OK, confirmed, won and paid. This covers:
  - RSVP "Going" pills and groups, and "You're on it";
  - "Registration open" tags and badges, and accepted, paid and confirmed tournament pills;
  - "Entry fee paid", done steps and checks, and "Imported";
  - roster Paid, "You've paid" and "Payments: On";
  - done checklist marks, Learn "read", password rules met and "username available";
  - video ready, "Voice Connected" and "Push notifications are on";
  - wins, positive +/- and point differences, "we scored", Break/Score, line ready and GOAL tags.
- **Indigo stays** for choices and actions:
  - RSVP selector buttons, poll choices, selected options and Following;
  - verified badges, hints, progress bars and stat-recording buttons;
  - "N spots left": see decision D6.
- **Selected segments:** Flutter can't outline one segment through its theme. A new shared `AppSegmentedButton` draws a 1.5px indigo outline on the selected segment; 17 screens use it. The schedule day strip, reaction bubbles, mic toggle and theme picker also got the outline.
- **Status tags** in light and dark now pass 4.5:1 for all 7 tones. They were 2.98–3.98:1 in light.
- **Sign-in illustration:** dark sky, chalk lines in the light media colour, turf-green grass from the playbook colours, red disc unchanged.
- **Tests:** app 1,578 passed / 68 skipped / 0 failed (20 new); goldens unchanged; screenshots show only the 3 known failures.

## 6. Lane A merged (`45c4ab1`): #1 test side and #4 API

- **#1 rules tests: 378/378 green.** Both old failures were test bugs:
  - a reused document id;
  - one batch mixing two Firestore instances.

  The rules themselves are unchanged. The moderation tests now run in `npm test` (functions 313 pass); the photo-check test needed a fake storage bucket.
- **#4 API:** `PATCH /v1/teams/:id` is the only way to change a team's level.
  - **Who is checked:** switching to club checks every member, plus any account linked to a roster spot, even someone who has left. Anyone under 16, or with no birth date, blocks the switch.
  - **The refusal:** HTTP 412 `failed_precondition` with the message "This team can't switch to the club level: N people on it are under 16 or haven't added a date of birth…" The count is given, never names.
  - **Safeguards:** it fails closed if the personal-details key is missing, and it re-checks inside the transaction in case someone joins meanwhile.
  - **Tests:** 14 API tests; API 1,320 pass.
- **Held back:** the rules commit that stops clients writing `level` directly. It is on local branch `hold/sec4-rules-level` (`e8a4fe4`). It merges only after:
  - the app removes its direct-write fallback (in progress);
  - the security review finishes.
- **Product behaviour change:** before, switching a team to club "removed no one", and people under 16 stayed on it. Now the switch is refused. `docs/product-spec.md:113` still describes the old behaviour; see decision D7.

## 7. Decisions for you (my default is in bold, and was used overnight)

| # | Question | Default used |
|---|---|---|
| D1 | Q5 and Q6: email limited to Firebase verify/reset, and adult-only (18+) launch enforced on the server? Unblocks #3a | **Waiting. #3a not started; lane A did #8 instead** |
| D2 | Q10: your weekly hours until Jan 18 | — |
| D3 | Sign-up check: should it also block while the *first* status check is still loading? Today pages render during that moment. The real fix is the server-side check (#3a) | **No; leave it to #3a** |
| D4 | Rules-test gate on deploys also runs for **rollbacks**, so a failing test would block an emergency rollback. Skip the gate for rollbacks? | **Keep the gate. Revisit if a rollback is ever blocked** |
| D5 | Tournaments legend dot: indigo (category colour) or green? | **Indigo** |
| D6 | "N spots left": the app kept indigo, the website made it green | **Indigo on both.** The UI review says a count is information, not success. The website is being changed back |
| D7 | Club switch: refuse while anyone under 16 is on the team (new), or the old "switch and keep them"? Also, roster spots with no linked account (walk-ons) can't be age-checked and are ignored. OK? | **Refuse; ignore walk-ons. Update `product-spec.md:113` after you confirm** |
| D8 | Game screen: "we scored", "Break/Score" and GOAL tags green (done), while the GOAL buttons stay indigo (actions) | **As built** |
| D9 | The app uses teal, blue and purple for tournament statuses (Seeding, Scheduled, Finished) and team-kind tags; the website shows these as neutral. Make them neutral in the app too (zinc + indigo, red for live, green for success)? | **Not changed yet. I recommend neutral** |
| D11 | **#5, the push device left on the previous account:** the server can't find the old account's copy of a phone without a new collection. Proposal: a server-only `fidOwners/{fid}` → `{uid}` map, kept by a new trigger (deploy group `deviceOwnership`). Delivery also skips any device the map says belongs to someone else. Needs a one-off backfill on dev. Approve the new collection + function, or the alternative (a `fid` field on device docs + an index exemption, which also changes the rules)? | **Not built: needs your approval. I recommend `fidOwners`. Until then the gap is open only when the old account's sign-out happened offline** |
| D12 | **App sign-up check (new screen):** when the check fails, the app shows "Couldn't check your account" with Try again, Sign out and links to Terms, Privacy and Guidelines. **Learn and Help stay blocked** while it shows. Keep them blocked, or open them? | **Blocked** (the app has no in-app legal pages; those links open the browser) |
| D13 | Compact segmented controls (roster line picker, rankings toggle, mi/km) are now 48px tall, about 8px taller, to meet the touch-target rule | **48px**, per the approved guide. Please look at those rows |
| D10 | The club-switch refusal says *how many* people are under 16. With a daily limit on failed attempts, keep the count, or say only "some people"? | **Keep the count, plus a limit of 3 failed switches per team per day** |

## 8. Merged since: website #4 (`7a4679f`) and #8 (`e59eb2c`)

- **Website #4:** the club-switch refusal shows under the Level field, and the copy is corrected. The website never writes `level` to Firestore directly; it uses only the API. Website unit tests 177.
- **#8: payments off, and checks at server start.**
  - The API now refuses to start in production without `FIREBASE_PROJECT_ID`.
  - Live and test Stripe keys can't be used with the wrong project. Key values are never logged.
  - The Stripe secrets are no longer required in `service.yaml`. The deploy workflow adds them only when `API_PAYMENTS_DEV`/`API_PAYMENTS_PROD` is `on`.
  - Production backend deploys fail instead of falling back to dev credentials.
  - API tests 1,330 pass.

**What you need to set** (names only):
- GitHub variables `API_PAYMENTS_PROD` (`off` for launch) and `API_PAYMENTS_DEV` (`on`).
- GitHub secret `FIREBASE_SA_PROD`, which must exist or prod backend deploys now fail.
- Before turning prod payments on: the three Stripe secrets in the prod project's Secret Manager.

## 9. Independent reviews

**Security (Sprint 1 changes): OK with fixes. No critical or high findings.**
- SEC-4 is only closed once the held rules commit is merged and both the new API and the rules are deployed to dev. Deploy the API first or together; that needs your approval.
- **Fixes in progress (backend):**
  - a race between the age check and the save;
  - refusing the switch when a roster is too large to check fully;
  - a rate limit on team edits, plus at most 3 failed club switches per team per day, so the count can't be used to probe ages;
  - the API refuses to start in production without the personal-details key (otherwise the website sign-up check would block everyone);
  - CI permissions and pinned action versions;
  - the deploy script no longer pastes inputs into shell commands.
- **Website:** the sign-up check now also treats a malformed answer as a failure (in progress).
- **App parity gap (Medium):** the app's sign-up checks still let people through when the API errors, as the website did before #3b. This is queued for the app lane.

**UI (K4/K5): approve with fixes.** Green is used only for success on both platforms.
- **Required fixes, queued for the app lane:**
  - The new selected-segment outline draws in the wrong place, about 6px too tall, with square inner corners. The reviewer recommends replacing it with one simple shared segmented control, also used by Schedule's Week/Month and filters, the hat tournament tabs and two other controls, at 48px tall.
  - The champion card should be green, as on the website.
  - The sign-in tagline is too faint (about 3.2:1).
- **Website (in progress):** "spots left" back to indigo, the green sidebar team tint replaced, stale comments fixed.

## 10. Merged after the reviews

| Merge | What |
|---|---|
| `b7ae28d` | **#4 app:** a team edit never writes `level` straight to the database. With the API off, a level change returns a clear error instead. The copy now says switching to club needs everyone 16+ with a birth date. The API's refusal message reaches the user. **#5:** every sign-out (Settings, Agree terms, Choose username, Personal details, failed delete) unregisters this phone's push in one shared place first. It gives up after 4 seconds, so sign-out never hangs offline. App 1,589 pass / 68 skip / 0 fail |
| `9b489b0` | **Website:** the sign-up check also treats a malformed answer as a failure. "Spots left" is back to indigo. The green sidebar team tint is now cyan `#0e7490`. Website unit 181, e2e 16 |
| `49c3f9a` | **Security fixes:** the club-switch race and roster cap; team edits limited to 5/min and 30/day per person; at most **3 failed club switches per team per day**, kept in `limits/clubswitch-{teamId}`. The API won't start in production without `PERSONAL_DETAILS_KMS_KEY`. CI gets read-only permissions and actions pinned to commit SHAs. The deploy script takes its inputs through `env`; firebase-tools is pinned to 15.8.0. API 1,335 |
| `14b4a49` | **#4 rules (the held commit):** clients can no longer write a team's `level`. Rules 378/378. **Not deployed.** |

**SEC-4 deploy order (your approval needed):** deploy the API from this branch to dev first, then the Firestore rules to dev. Until both are live, dev still lets the old path switch a team to club without the age check.

**Flaky test:** one rules test failed once in the 45c4ab1 regression (376/377). It passed on two re-runs. I'm watching for it in the final regression.

**#5, the part not done on the phone:** removing the same phone from the *previous* account's device list can't be done from the app under the current rules. A server-side fix is in progress (backend agent). If it needs a new collection or index, it stops for your approval.

## 11. Later merges

- `83ba28b` **K8:** token parity tests. Every colour, alias and contrast pair is checked across the fixture, the app and the website CSS in all three theme blocks. **No mismatches.** The text, spacing, radius and motion tokens don't exist on either platform yet (that's K6/K7), so those 30 checks are skipped with a reason. They turn on by themselves once the tokens are added.
- **Rules tests (SEC-4):** three new tests show a client can't change a team's level as a group manager, through a custom role with manageTeam, or in a team-plus-listing batch. None of them found a hole. Rules 381/381.
- `ee068fe` **App review fixes:**
  - **One shared segmented control built from plain widgets.** The outline now sits exactly on the selected segment, with rounded corners; it works right-to-left and at 200% text, and is 48px tall. Schedule Week/Month and its filters, the hat tournament tabs, the playbook switch and the game side switch use it too, so they all look the same. Before: `C:\Users\brian\AppData\Local\Temp\claude\f4f2bdc0cec82280\f687b260-b40a-446b-b082-0a83caa80248\scratchpad\before\seg_before.dark.360.png`. After: `apps/mobile/test/ui/core/goldens/segmented_control.{light,dark}.360.png`.
  - The champion card is success green.
  - The sign-in tagline is at full strength (about 4.8:1).
  - **The sign-up check fails closed** (security review, parity with website #3b). An API error or a malformed answer shows the blocking "Couldn't check your account" screen instead of the app.
  - App 1,633 pass / 68 skip / 0 fail.
  - The hat "You're in" card isn't in the app; that finding was website-only, so no change.

## 12. Final regression on `ee068fe` (run on Windows, 2026-11-26)

| Suite | Result |
|---|---|
| App analyze | No issues |
| App tests (goldens compared) | **1,637 passed, 72 skipped, 0 failed** (skips: 68 screenshot generators + 4 K6/K7 token checks) |
| Website typecheck | Clean |
| Website unit | **198 passed, 26 skipped** (K6/K7 token checks) |
| Website browser (Playwright) | **16 passed**, 32 skipped (before-picture generators). The first run failed 11 because the dev server timed out on a cold start while other suites were running; the re-run passed 16/16 |
| API | **1,335 passed** |
| Shared | **922 passed** |
| Functions | **313 passed** |
| Rules | **381 passed** (was 375 + 2 failing at sprint start) |
| Version check | OK |

**Not run:** API emulator tests; Maestro or devices; the 3 known screenshot failures were not re-checked.

**Flaky:** one rules test failed once at `45c4ab1` and has passed in four runs since; the browser tests failed once on a cold start (above).
