# Rolling back

There are two levers, one for the backend and one for the app.

## Backend: one click in GitHub Actions

**Roll back:** GitHub → Actions → **Roll back backend** → Run workflow.
- Pick `dev` or `prod`.
- Leave *release* empty to go back one release, or paste a tag like
  `release-dev-20261105-142233`.

Rules, indexes, hosting and functions go back to exactly what that release
had. It takes about 3–5 minutes.

**Deploy:** Actions → **Deploy backend** → Run workflow.
- Pick the project and the branch: `development` for dev, `main` for prod.
- Every deploy is tagged `release-<env>-<time>`. Those tags are what
  rollback picks from, so deploy through this button and not the CLI if you
  want to be able to roll back.

What a rollback doesn't undo:
- **Data.** Documents written since stay as they are. Rules and functions
  are kept backward-compatible with the previous release for this reason.
- **Functions added after that release** (for example the `api` group when
  rolling back to before it). They stay deployed. Delete one by hand if
  needed: `firebase functions:delete api-search --project dev`.
- **Indexes added since.** They stay, which is harmless.

### One-time setup
1. For each Firebase project, create a service account key: Google Cloud
   console → IAM → Service Accounts → *Firebase Admin SDK* account (or a
   new one with the *Firebase Admin* role) → Keys → Add key → JSON.
2. GitHub → Settings → Secrets and variables → Actions → New repository
   secret:
   - `FIREBASE_SA_DEV`: the dev project's JSON key.
   - `FIREBASE_SA_PROD`: the prod project's JSON key.

   Then delete the downloaded JSON files. Never commit them.
3. GitHub → Settings → Environments → `prod` → Required reviewers → you.
   Prod deploys and rollbacks then wait for your approval.
4. Optional: the variable `FUNCTION_GROUPS` overrides which function groups
   deploy. The default is
   `account,api,communities,discord,follows,meetings,notifications`.

## App: kill switches in `meta/flags`

A build already in the App Store can't be rolled back, so newer behaviour
sits behind switches that every running app reads live. To use one, open
Firebase console → Firestore → `meta` → `flags` (create the document if
it's missing) and set a boolean field:

| Field | Default | Off means |
|---|---|---|
| `use_api_search` | `false` | Search queries Firestore directly instead of the rate-limited `api-search` function |
| `compress_images` | `true` | Photos upload as picked, without shrinking |

Changes reach open apps within seconds, with no new build. Missing fields
use the defaults in `lib/data/services/feature_flags.dart`.

To undo a whole app build, stop its rollout:
- **TestFlight:** App Store Connect → TestFlight → the build → Expire.
- **App Store:** pause the phased release, or submit the previous version
  again. The backend stays compatible with older builds.
