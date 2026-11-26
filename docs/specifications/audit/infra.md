# Stall10 infrastructure and release audit (read-only, baseline 39c8a53)

How this was done: I read the files offline only, with no live service calls. Console state (GitHub settings, GCP, Vercel, Codemagic) is **unverified**, not missing. One incidental exposure: a `git grep` printed four comment and placeholder lines of the tracked `apps/api/.env.example`. I have not cited them. This confirms the prior work (readiness rows 19–20, plan R1–R8) and adds the items marked **new**.

## Environment matrix

| Layer | How dev vs prod is chosen | Evidence | Prod hazards |
|---|---|---|---|
| App (Flutter) | No flavors. `FIREBASE_ENV` comes from `--dart-define-from-file`. Anything other than `prod` means dev, but `ensureConfigured()` throws unless the value is dev or prod. Both projects' options are compiled in. Other defines: `API_BASE_URL`, `STRIPE_PUBLISHABLE_KEY`, `APP_CHECK_DEBUG_TOKEN`, `USE_EMULATORS`, `FIRESTORE_MEMORY_CACHE`, `FIREBASE_ANDROID_API_KEY`, `FIREBASE_APPLE_API_KEY`. | `apps/mobile/lib/firebase_options.dart:28-33`, `main.dart:67`, `api_client.dart:36`, `invite_links.dart:9-16` | Dev and prod share one bundle ID, `com.brianrhonea.frisbeeApp` (`codemagic.yaml:46`), so a TestFlight dev build and the App Store build are the same app. |
| Web (Next.js, Vercel) | Vercel env per deployment (Production vs Preview). Names used: `NEXT_PUBLIC_FIREBASE_{API_KEY,AUTH_DOMAIN,PROJECT_ID,STORAGE_BUCKET,APP_ID}`, `NEXT_PUBLIC_API_BASE_URL`, `API_BASE_URL`, `WEB_SERVER_KEY`, `NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`, `NEXT_PUBLIC_RECAPTCHA_SITE_KEY`, `NEXT_PUBLIC_APP_VERSION`, plus `*_EMULATOR_HOST`. `vercel-ignore.sh` builds `main` as production and `development` only when the web changed. | `apps/web/lib/firebase.ts:22`, `lib/api.ts:8`, `lib/client.ts:7`, `app/layout.tsx:24`, `scripts/vercel-ignore.sh` | If the env is missing, the site silently falls back to `localhost:8787` / `localhost:3000` instead of failing the build. |
| API (Cloud Run) | `FIREBASE_PROJECT_ID` is filled in per environment by `_deploy-api.yml:96-104` into `service.yaml`. Also read: `ENFORCE_APP_CHECK`, `CORS_ORIGINS`, `TRUST_PROXY_HOPS`, `STORAGE_BUCKET`, `PERSONAL_DETAILS_KMS_KEY`, `WEB_SERVER_KEY`, `WEB_SITE_URL`, `PUBLIC_API_URL`, `PAYMENTS_RETURN_URL`, `STRIPE_SECRET_KEY`, `STRIPE_PLATFORM_WEBHOOK_SECRET`, `STRIPE_WEBHOOK_SECRET`, `PLATFORM_FEE_BPS`, `PLATFORM_FEE_FIXED_CENTS`, `PAYOUT_HOLD_DAYS`, `JOBS_AUDIENCE`, `JOBS_INVOKER`, `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `SAFE_SEARCH`, `LOG_LEVEL`, `GOOGLE_CLOUD_QUOTA_PROJECT`. | `apps/api/src/server.ts`, `deploy/service.yaml:37-96` | **`server.ts:37` falls back to `frisbee-app-brianrhonea-dev`** if the variable is unset. There is no startup check that the project and the Stripe mode match. |
| Functions | `firebase deploy --project dev\|prod` (aliases in `firebase/.firebaserc`, where default is dev). `ENFORCE_APP_CHECK` comes from `functions/.env.<project>`. Secrets: `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `WEB_API_KEY`. | `firebase/functions/src/options.ts:12`, `meetings/functions.ts:29-30`, `account/functions.ts:36` | The default alias is dev, so a bare `firebase deploy` targets dev. That is safe. |

**Hardcoded dev values outside configuration:**
- `apps/api/src/server.ts:37`: the project ID fallback (fix this).
- `apps/mobile/android/app/src/main/AndroidManifest.xml:63`: `dev.stall10.app`. It is listed alongside the prod host, so this is intentional.
- `apps/mobile/lib/utils/invite_links.dart:15`: the dev host, chosen through the environment. Fine.
- The backfill scripts and `setup-alerts.sh:17` map dev and prod explicitly. Fine.

## CI/CD matrix

**Key fact:** `origin/main` (090e7b4) contains no `.github/workflows` and no `codemagic.yaml` (`git ls-tree origin/main`). It is the pre-monorepo MVP.

| Workflow | Trigger / branches | Builds or deploys | Secrets and variables (by name) |
|---|---|---|---|
| `ci-node.yml` | push and PR on any branch, filtered by path (api, web, packages, lockfile) | `check` job: typecheck, tests and builds for shared, api and web. `api-emulator` job: Java 21 plus emulator tests. `api-image` job: Docker build plus smoke test (401, non-root, SIGTERM). | none |
| `deploy-api.yml` → `_deploy-api.yml` | `workflow_dispatch` (dev\|prod, ref) | Tests the API, builds the image and pushes it to Artifact Registry, runs `run services replace`, routes 100% of traffic, runs a smoke test, and tags `api-release-<env>-*` | `FIREBASE_SA_DEV`/`_PROD` (as `GCP_SA_KEY`). Variables: `GCP_WIF_PROVIDER_*`, `GCP_DEPLOYER_SA_*`, `API_REGION`, `API_CORS_ORIGINS_*`, `API_ENFORCE_APP_CHECK_*`, `API_MAX_INSTANCES_*`, `API_WEB_SITE_URL_*`, `API_PAYOUT_HOLD_DAYS_*` |
| `rollback-api.yml` | `workflow_dispatch` | Redeploys a tagged image by its digest | same as above |
| `deploy-backend.yml` → `_deploy-backend.yml` | `workflow_dispatch` | Runs functions build and `npm test`, then deploys rules, indexes, storage, hosting and functions by group. Tags `release-<env>-*`. | `FIREBASE_SA_DEV`/`_PROD`, `FIREBASE_WEB_API_KEY_DEV`/`_PROD`. Variable: `FUNCTION_GROUPS` |
| `rollback-backend.yml` | `workflow_dispatch` | Redeploys a tagged release | same as above |
| Codemagic `ios-testflight` | push to `development`, filtered by changeset (`apps/mobile`, `packages`, `codemagic.yaml`) | Runs analyze and test, builds the IPA, uploads to TestFlight (dev) | group `frisbee_secrets_dev` (`SECRETS_LOCAL_JSON`, `GOOGLE_SERVICE_INFO_PLIST`), integration "Frisbee App Store Connect" |
| Codemagic `ios-app-store` | push to `main` | Same build against prod, then **`submit_to_app_store: true`** with manual release (`codemagic.yaml:140-149`) | group `frisbee_secrets` |

**Gaps:**
- There is no Android pipeline. Android release builds are signed with the debug key (`apps/mobile/android/app/build.gradle.kts:33-36`).
- No Flutter checks run on GitHub PRs. They run only in Codemagic, paid, after a push to `development`.
- The rules tests (`test:rules`) and server tests (`test:server`) never run in CI or in the deploy workflow. The functions `test` script also skips `test/moderation` (`firebase/functions/package.json` scripts).
- The web app has no test script (`apps/web/package.json`).
- There is no CODEOWNERS, Dependabot or Renovate file. Branch protection and `prod` environment reviewers are unverified.
- Tools are not pinned: `firebase-tools@latest` (`_deploy-backend.yml:135`), `xcode: latest` and `cocoapods: default` (`codemagic.yaml:37-38`), and there is no `Podfile.lock`.
- There are no `release-*` or `api-release-*` tags locally, which suggests deploys bypass the workflows. That would leave nothing for tag-based rollback to restore. Remote tags are unverified.

## Ops readiness checklist

| Item | Status | Evidence |
|---|---|---|
| Firestore backups / PITR | **Missing** | No export, backup schedule or PITR anywhere in the repo |
| Restore drill | Missing | none |
| Mobile crash reporting | **Missing** | No Crashlytics or Sentry in `pubspec.yaml` or code |
| Web error reporting | Missing | No Sentry or instrumentation file in `apps/web` |
| API structured logging | Present | `apps/api/DEPLOY.md:325-338`, `cloudLoggingOptions` in `server.ts` |
| Uptime checks and alerts | **Partial, wrong targets** | `setup-alerts.sh:65-66` probes `<project>.web.app` and the functions `api-health`, not Cloud Run `/health` or Vercel. Whether it was ever run is unverified. |
| Payment-problem alert | Documented only | `DEPLOY.md:520-521` |
| Budget alerts | Documented only ($10 example; spec asks for 50/75/90/100%) | `firebase/docs/cloud-limits.md:22-24` |
| Feature flags | Partial, client-only | `meta/flags`, read by the app only when signed in (`feature_flags.dart:22-40, 63-75`). Rule `firestore.rules:3055-3058` (read for signed-in users). |
| Server kill switches (uploads, meetings, sign-ups, payments) | **Missing** | No server reads of `meta/flags` (grep). Payments are off only when the Stripe secrets are absent. |
| Minimum-version gate | **Missing** | No version header or check. The app version is only a UI string (`brand.dart:9`). The API exposes its own version only (`version.ts`). |
| Rollback docs | Present, partly stale | `firebase/docs/rollback.md`. The groups default at `:42-43` lists 7 groups vs 10 in `_deploy-backend.yml:56`. `monitoring.md:29` checks out an old branch. |
| Incident runbook / release manifest | Missing | Spec 18 §05/§12 require them; none in the repo |
| App Check enforcement | Off (by design, pending rollout) | `_deploy-api.yml:98,101` default false, `options.ts:12` |

## Scalability (verified config)

- **Cloud Run:** min 0, max 3 on dev and 10 on prod, concurrency 80, timeout 60s, 1 vCPU / 512Mi, startup boost, probes on `/ready` and `/health` (`service.yaml:22-31, 97-114`). Cold starts of 1–3 s (`DEPLOY.md:342-346`).
- **Functions:** global `maxInstances: 10` (`options.ts:5`). Region defaults to us-central1, except `photoCheck`, which is us-east1 with 256MiB (`moderation/photo_check.ts:47-49`). `deleteAccount` runs at 540s / 512MiB.
- **Scheduled jobs:**

  | Job | Schedule | Timeout | Defined in |
  |---|---|---|---|
  | `notifications-eventReminders` | `0 * * * *` UTC | 300s | `triggers.ts:646-647` |
  | `notifications-entryDeadlineReminders` | `15 * * * *` UTC | 300s | `:827-828` |
  | `rankings-nightly` | `15 9 * * *` UTC | 540s | `rankings/functions.ts:190-191`; scans all profiles, so it scales risk with users |
  | Cloud Scheduler `payments-release` | hourly | — | `DEPLOY.md:515` |
  | Cloud Scheduler `payments-reconcile` | 06:30 America/New_York | — | `DEPLOY.md:516` |

  All functions jobs use `retryCount: 1`. The two Cloud Scheduler jobs are created by hand (`gcloud`) and are not in code.
- **Indexes:** 12 composite indexes and 23 overrides, including the TTL on `inviteCodes.expiresAt`. I sampled the compound queries (`tournaments/public_repository.ts:46-52`, the posts feeds, events) and each has a matching index. Coverage is **sampled, not proven**.
- **Rate limiting:**
  - Browse uses a Firestore-transaction limiter keyed on uid or hashed IP (`limits/limiter.ts:14-30`).
  - Writes use an in-memory limiter per instance, so the real ceiling is limit × instances (`limits/memory.ts:4-10`).
  - The functions' flood mutes are shared with these.
- **LiveKit:** the Build plan is assumed: 100 concurrent connections and 5,000 participant-minutes (`cloud-limits.md:17, 80-84`). Tokens last 6h. There is no per-room participant cap in code.
- **Load test:** none.

## Dependency and version hygiene

- **Node:** 22 everywhere: CI, `Dockerfile` `node:22-bookworm-slim`, functions `engines: 22`, root `>=22`. Node 22 reaches end of life in April 2027, so plan Node 24 after launch.
- **pnpm:** 11.13.1, pinned in `packageManager` and the Dockerfile. Installs use the frozen lockfile.
- **Functions:** a separate npm lockfile.
- **Flutter / Dart:** Flutter 3.41.2 is pinned in Codemagic. Dart is `^3.11.0`. `pubspec.lock` is tracked.
- **Version split:** vitest is `^4` in functions vs `^5` in the API.
- **Outdated majors: unverified.** Checking needs registry access, which is not allowed here.
- **Secret hygiene:** `secrets.prod.local.json` and `GoogleService-Info*.plist` exist at the repo root but are gitignored (`.gitignore:56,62`). `.dockerignore` is an allow-list.

## Risks

| ID | Sev | Evidence | Impact | Fix |
|---|---|---|---|---|
| INF-1 | P0 | `origin/main` has no workflows or `codemagic.yaml`; all deploys are `workflow_dispatch` | Deploy and rollback can't run from main. The first merge also starts a paid App Store submission (`codemagic.yaml:148`) and a Vercel production build. | Set up the Codemagic prod group, Vercel prod env and prod secrets *before* the merge; consider `submit_to_app_store: false` at first |
| INF-2 | P0 | No backup or PITR config | Data loss can't be recovered | Daily backup schedule (30-day retention) plus PITR on prod; restore drill |
| INF-3 | P0 | No Crashlytics or Sentry | Beta crashes go unseen | Add Crashlytics, plus web error reporting |
| INF-4 | P0 | `setup-alerts.sh:65-66` | Outages of the real API or site raise no alert | Probe the Cloud Run `/health` and the Vercel domain; budget alerts; test that alerts arrive |
| INF-5 | P0 | No minimum-version gate | Rules can't be tightened without breaking old builds | Add a `minVersion` in `meta/flags` or the API, with an update screen |
| INF-6 | P1 | `server.ts:37` dev fallback; no environment assertion | A misconfigured prod API could silently use dev | Fail at startup if the project ID is missing or mismatched, or if the Stripe key mode is wrong for the environment |
| INF-7 | P1 | `deploy-backend.yml:32-33`, `rollback-backend.yml:71-72` use `prod && PROD \|\| DEV` | If the prod secret is unset, the run silently uses dev's key | Use the `secrets[...]` name-selection pattern already in `deploy-api.yml:40` |
| INF-8 | P1 | `service.yaml:73-87` requires the three `STRIPE_*` secrets (`DEPLOY.md:468-470`) | A prod API can't deploy "payments off" without creating Stripe secrets | Owner decision: make them optional plus a server payments flag (plan F4) |
| INF-9 | P1 | Rules and server suites not in CI; no Flutter PR checks; web has no tests | Regressions ship | Add CI jobs, then require them on `main` |
| INF-10 | P1 | No Android pipeline; debug signing (`build.gradle.kts:36`) | No Play beta | Upload key plus a Codemagic Android workflow (plan F1) |
| INF-11 | P2 | `firebase-tools@latest`, `xcode: latest`, no `Podfile.lock` | Builds aren't reproducible | Pin the versions; commit `Podfile.lock` |
| INF-12 | P2 | Only client `use_api_*` and `compress_images` flags | No emergency stop for uploads, meetings or payments | Server-enforced switches (R4) |
| INF-13 | P2 | No local release tags; stale `rollback.md:42-43`, `monitoring.md:29`; `docs/ARCHITECTURE.md:807-814` says prod has old rules | Rollback may have no target; docs mislead | Deploy only through the workflows; refresh the docs |

## Prod stand-up sequence

Labels: **A** = automatable (workflow or script), **O** = owner console action.

1. **O:** Decide whether the beta runs on prod (Q9). Clean the prod database. Prod already has older rules (`docs/ARCHITECTURE.md:811`).
2. **O:** In GitHub: `prod` environment with required reviewers; branch protection on `main`; secret `FIREBASE_SA_PROD` or WIF variables (`DEPLOY.md:226-272`).
3. **A (gcloud scripts in `DEPLOY.md:91-301`):**
   - Check the region.
   - Enable the APIs.
   - Artifact Registry plus its cleanup policy.
   - The `api-runtime` service account and its roles.
   - Bucket IAM and CORS (`storage-cors.prod.json`).
   - `web-server-key`.
   - The KMS key ring and key. These can't be deleted, so the owner reviews the names first.
   - The deployer service account / WIF.
   - The hello-image service with public access.
4. **O + A:** Stripe live (or test) secrets, needed even with payments off (INF-8). LiveKit secrets. `firebase functions:secrets:set` for the LiveKit values and `WEB_API_KEY`.
5. **O:** Firebase Auth authorized domains (`stall10.app`). Restrict API keys (P9). App Check registration. Set `functions/.env.prod`.
6. **O:** Vercel Production env vars (the names in the environment matrix) for `stall10.app`. Codemagic group `frisbee_secrets` with the prod `API_BASE_URL`. Optionally set `submit_to_app_store: false` for the first runs.
7. **O (paid; needs explicit OK):** Merge `development` → `main`.
8. **A:** Deploy backend for prod (rules, indexes, storage, hosting, function groups). Deploy API for prod with `API_CORS_ORIGINS_PROD`, `API_WEB_SITE_URL_PROD` and the hold days.
9. **A:** Create the Cloud Scheduler payment jobs (`DEPLOY.md:512-517`). Create `meta/flags` with payments off.
10. **A + O:** `setup-alerts.sh prod`, after retargeting it (INF-4). Budget alerts at 50/75/90/100%. Log alert on payment problems.
11. **O:** Firestore backup schedule plus PITR. Restore drill into an isolated project.
12. **A:** Smoke test the prod API, site and app (TestFlight build from `main`). Record the release manifest.

## Suggested issues

| Title | Priority | Hours |
|---|---|---|
| Stand up prod: GCP/IAM/KMS/secrets per DEPLOY.md, gated by owner | P0 | 12 |
| Safe `development` → `main` merge plan (Codemagic and Vercel prod pre-config) | P0 | 3 |
| Firestore daily backups, PITR, restore drill with RPO/RTO | P0 | 5 |
| Crashlytics (app) and web error reporting | P0 | 5 |
| Retarget uptime and alerts to Cloud Run and Vercel; budget alerts; delivery test | P0 | 3 |
| Minimum-version gate (`meta/flags` + API header) with an update screen | P0 | 5 |
| API startup assertion for environment and Stripe mode; remove the dev fallback | P1 | 2 |
| Fix the prod→dev secret fallback in backend deploy and rollback | P1 | 1 |
| CI: rules and server suites, Flutter analyze/test on PR, required checks | P1 | 6 |
| Optional Stripe secrets plus server payments-off flag | P1 | 3 |
| Android signing and Codemagic Play pipeline | P1 | 8 |
| Server-enforced emergency switches (uploads, meetings, sign-ups, payments) | P1 | 4 |
| Pin `firebase-tools`, Xcode, CocoaPods; commit `Podfile.lock` | P2 | 2 |
| Incident runbook, release manifest, doc refresh (`rollback.md`, `monitoring.md`) | P2 | 3 |
| k6 load test at 10/50/100 users on dev; profile the `rankings-nightly` scan | P2 | 5 |
