# App Check and abuse protection

## What protects what

| Layer | Stops | Where |
|---|---|---|
| App Check | Scripts and bots that aren't the real app | `lib/data/services/app_check.dart`, Firebase console |
| Rate limits + mutes | A real account flooding messages, posts, comments, follows, join requests, teams | `functions/src/api/`, `notMuted()` in `firestore.rules` |
| Search through `api-search` | Bulk scraping of profiles and the team directory | `functions/src/api/functions.ts`, `use_api_search` flag |
| Username sign-in limit | Password guessing (10 tries per username per 15 min) | `functions/src/account/functions.ts` |
| `maxInstances: 10` | A flood scaling a function (and the bill) without limit | `functions/src/options.ts` |

Limits live in `functions/src/api/model.ts`. Someone over a limit has the
extra write deleted and is muted for 10 minutes (`limits/{uid}`); the app
tells them "You're going too fast".

## Turning App Check on (dev first, then prod)

1. **Register the apps** in Firebase console → App Check:
   - Android: Play Integrity (add the app's SHA-256 signing fingerprint).
   - iOS/macOS: App Attest (DeviceCheck fallback). Add the App Attest
     capability in Xcode (Codemagic signs it).
2. **Debug token for Windows and debug builds**: App Check → Apps →
   Manage debug tokens → Add. Put the token in `APP_CHECK_DEBUG_TOKEN` in
   `secrets.local.json` (never commit it). Without one, Windows runs
   without App Check.
3. **Watch** App Check → APIs → Firestore / Storage / Functions metrics for
   a week. "Verified" should cover nearly all requests from current builds.
4. **Enforce** in the console (Firestore, Storage) once older builds without
   App Check are gone. For callables, add `ENFORCE_APP_CHECK=true` to
   `functions/.env.dev` (or `.env.prod`) and redeploy the functions.
5. Undo any step by un-enforcing in the console, or removing the env line
   and redeploying.

## Turning on server search

Deploy the `api` functions to the project, then set `use_api_search: true`
in the Firestore document `meta/flags` (see docs/rollback.md). Later,
once every app build in use searches through the function, firestore.rules
can deny `list` queries on `profiles` and `teamDirectory` to clients.
