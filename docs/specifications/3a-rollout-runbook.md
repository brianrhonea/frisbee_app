# #3a account gate: rollout runbook (dev)

**Status:** draft for the owner. Nothing here has been run. Every step is an owner-run deploy or script, per CLAUDE.md §16.

**Code:** `feature/jan-4-release` at `b471e30` or later. That means API 0.52.1, web 0.61.0 and app 0.0.58, with `ACCOUNT_GATE_MODE: "report"` in `apps/api/deploy/service.yaml`.

**Dev project:** `frisbee-app-brianrhonea-dev`.

The order is the one the owner chose on 2026-11-26: API report-only, then backfill, then apps, then enforcement, then rules and callables last.

## Before you start

1. **Check `follows.photoUrl` hosts on dev.** Look for any `follows` doc whose `photoUrl` is not one of these:
   - our Storage bucket;
   - `lh3.googleusercontent.com`.

   The new rules re-validate the whole doc when the notify toggle changes, so a legacy URL there would make that update fail. QA found no current app or web write that breaks.
2. **Check dev `profiles`** for `photoUrl` or `headerUrl` values that fail the new strict pattern. A Storage URL with `/o/<name>?alt=media&token=…` passes. Two effects:
   - From step 1, API 0.52.1 drops a non-conforming profile photo from new posts, comments, follows, follow requests, block cards and meeting tokens. Those players appear without a picture until they upload a new one.
   - From step 5, their direct profile writes are also refused.
3. **Confirm the `ageRefusals/{uid}` collection** (owner decision, see the completion report).

## 1. API in report-only on dev

- Build and replace the API from this branch. Use your usual Cloud Build plus `gcloud run services replace` procedure (`apps/api/DEPLOY.md`). `service.yaml` already sets `ACCOUNT_GATE_MODE: "report"`. Since 0.52.1, a deployed API refuses to start without that value.
- Deploy the `account` function group at the same time. From now on the API writes `ageRefusals`, and `deleteAccount` must clear it:
  `firebase deploy --only functions:account --project frisbee-app-brianrhonea-dev`
- Check that `/health` reports 0.52.1.

## 2. Claim backfill on dev

```sh
gcloud auth application-default login
# set PERSONAL_DETAILS_KMS_KEY to the dev API's value in your shell (never commit it)
pnpm --filter @stall10/api exec tsx src/scripts/backfill_claims.ts --project frisbee-app-brianrhonea-dev          # dry run
pnpm --filter @stall10/api exec tsx src/scripts/backfill_claims.ts --project frisbee-app-brianrhonea-dev --apply  # apply
pnpm --filter @stall10/api exec tsx src/scripts/backfill_claims.ts --project frisbee-app-brianrhonea-dev          # expect changed: 0
```

- `decryptFailures` and `writeFailures` should be empty.
- The script refuses any project except dev, or a `demo-*` project running on the emulators.

## 3. App and website

- Ship the TestFlight build (app 0.0.58) and the website (0.61.0).
- Watch the dev API logs for `account_incomplete` with `mode: "report"` until it is near zero.
- **Device check:**
  1. New sign-up, then verify email, then post.
  2. Set `meta/flags.minBuild` above 58. The "Update required" screen should show. Lift the value again.

## 4. Enforcement on

- Change `ACCOUNT_GATE_MODE` to `"enforce"` in `apps/api/deploy/service.yaml`, commit it, and redeploy the API as in step 1.
- Confirm that an incomplete account's write now gets 403 `account_incomplete`.

## 5. Rules and callables last

```sh
firebase deploy --only firestore:rules,storage --project frisbee-app-brianrhonea-dev
firebase deploy --only functions:meetings,functions:tournaments --project frisbee-app-brianrhonea-dev
```

- Test a 13–17 account: it should stay read-only and unable to publish a profile.
- **Device check for callables.** This only works now, because the gated callables are live from this step. An unverified account joins a meeting or voice room, or starts a draft. It should go to the verify-email screen, not show a bare error.
  - The app's parsing of the callable error (`details.code`) has only been unit-tested against the documented shape, never against a real callable, so this is the first real check.
  - Also test a migrated account whose old token predates its claims. It should succeed after the automatic status check, refresh and retry.

## Rollback

- Set `ACCOUNT_GATE_MODE` back to `"report"` and redeploy, or use the traffic rollback in `apps/api/DEPLOY.md`.
- Rules and functions can be re-deployed from the previous commit.

## Prod

Not covered here. Prod needs its own stand-up (#9, Sprint 3), with `ACCOUNT_GATE_MODE` set explicitly.
