# Deploying the API to Cloud Run

The API (`apps/api`) runs as the Cloud Run service **`api`** in each
Firebase project, next to Firestore, under its own service account
(ARCHITECTURE.md §8, §11). No service-account key files: the service uses
its Cloud Run identity through Application Default Credentials.

| | dev | prod |
|---|---|---|
| Project | `frisbee-app-brianrhonea-dev` | `frisbee-app-brianrhonea` |
| Deployed from | usually `development` | `main` |
| Approval | none | GitHub `prod` environment reviewers |

Pieces:
- `apps/api/Dockerfile`: multi-stage pnpm build; the default target `api`
  is slim Node 22 running `node dist/server.js` as the `node` user on
  `$PORT`. Target `media` adds ffmpeg for the video-transcode job.
- `/.dockerignore`: an allow-list. Only the root manifests,
  `packages/shared` and `apps/api` are sent to the build; `apps/mobile`,
  `apps/web`, `firebase/`, secrets and native Firebase files never are.
- `apps/api/deploy/service.yaml`: the whole Cloud Run configuration
  (scaling, probes, env vars, service account). Change it there, not in the
  console; the next deploy would undo console edits.
- `.github/workflows/deploy-api.yml` → **Deploy API**, and
  `rollback-api.yml` → **Roll back API**; both use `_deploy-api.yml`.

## Deploying

Actions → **Deploy API** → Run workflow → pick `dev` or `prod` and a ref.
It runs the API and shared tests, builds the image, pushes it to Artifact
Registry (`<region>-docker.pkg.dev/<project>/stall10/api:<commit>`),
applies `service.yaml`, sends all traffic to the new revision, checks
`/health`, `/ready` and that an unauthenticated `POST /v1/teams` gets a 401,
then tags the commit `api-release-<env>-<time>`. The tag's message records
the image digest. The run summary shows the service URL.

Environment variables on the service:

| Variable | From | Default |
|---|---|---|
| `FIREBASE_PROJECT_ID` | the environment | |
| `ENFORCE_APP_CHECK` | repo variable `API_ENFORCE_APP_CHECK_DEV` / `_PROD` | `false` |
| `CORS_ORIGINS` | repo variable `API_CORS_ORIGINS_DEV` / `_PROD` | dev: `http://localhost:3000`; prod: none |
| `TRUST_PROXY_HOPS` | `service.yaml` | `1` (Cloud Run's front end; `2` behind a Firebase Hosting rewrite) |
| `LOG_LEVEL` | `service.yaml` | `info` |

`CORS_ORIGINS` is comma-separated. A `*` matches one host label or port,
e.g. `https://stall10.app,https://stall10-*-brianrhonea.vercel.app` for
Vercel previews, or `http://localhost:*` for any local port. Leaving prod
empty means no website can call the API from a browser (the apps don't
need CORS).

After the first deploy, check `TRUST_PROXY_HOPS`: call `<url>/health` and
compare the `remoteAddress` in its "incoming request" log line with your
own public IP. If it shows a Google address instead, raise the value.

Other optional repository variables: `API_REGION` (default `us-central1`),
`API_MAX_INSTANCES_DEV` / `_PROD` (3 / 10).

## Rolling back

- **One click:** Actions → **Roll back API** → pick the environment, and
  leave *release* empty for the release before the latest, or name an
  `api-release-<env>-<time>` tag. It redeploys that release's image by
  digest (no rebuild) with that commit's `service.yaml`.
- **Instantly, from a terminal:** send traffic back to an earlier revision.
  The next deploy moves traffic to the newest revision again.

  ```sh
  gcloud run revisions list --service api --region us-central1 --project <project>
  gcloud run services update-traffic api --to-revisions <revision>=100 \
    --region us-central1 --project <project>
  ```

Data written since isn't touched. To switch the app off the API without a
build, use the `use_api_*` flags in `meta/flags`.

## One-time setup (per project)

Run these once for dev, then again for prod. You need `gcloud` signed in as
a project owner (`gcloud auth login`). In Git Bash:

```sh
PROJECT=frisbee-app-brianrhonea-dev   # then: frisbee-app-brianrhonea
REGION=us-central1
REPO=brianrhonea/frisbee_app          # GitHub owner/repo
gcloud config set project "$PROJECT"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
```

### 1. Check the region

The API should run in Firestore's region (or the nearest Cloud Run region
for a multi-region database):

```sh
gcloud firestore databases describe --database='(default)' --format='value(locationId)'
```

`nam5` (US multi-region) or `us-central1` → keep `us-central1`. Anything
else → use the matching region in the commands below and set the
repository variable `API_REGION` to it.

### 2. Enable the APIs

```sh
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  firestore.googleapis.com \
  identitytoolkit.googleapis.com \
  firebaseappcheck.googleapis.com \
  storage.googleapis.com
```

(`iamcredentials` signs Storage upload URLs; `sts` is for Workload
Identity Federation.)

### 3. Artifact Registry repository

```sh
gcloud artifacts repositories create stall10 \
  --repository-format=docker --location="$REGION" \
  --description="Stall 10 container images"
```

Keep storage small (images are ~100 MB; rollbacks need recent ones):

```sh
cat > /tmp/cleanup.json <<'EOF'
[
  { "name": "keep-recent", "action": { "type": "Keep" },
    "mostRecentVersions": { "keepCount": 15 } },
  { "name": "delete-old", "action": { "type": "Delete" },
    "condition": { "olderThan": "2592000s" } }
]
EOF
gcloud artifacts repositories set-cleanup-policies stall10 \
  --location="$REGION" --policy=/tmp/cleanup.json --no-dry-run
```

### 4. The runtime service account

The identity the API runs as, with only what it uses:

```sh
RUNTIME_SA="api-runtime@$PROJECT.iam.gserviceaccount.com"
gcloud iam service-accounts create api-runtime --display-name="Stall 10 API (Cloud Run)"

# Firestore reads and writes.
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:$RUNTIME_SA" --role=roles/datastore.user
# Firebase Auth: getUser today; account changes as features move to the API.
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:$RUNTIME_SA" --role=roles/firebaseauth.admin
# App Check token verification.
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:$RUNTIME_SA" --role=roles/firebaseappcheck.tokenVerifier
```

`roles/firebaseauth.admin` is there so endpoints that change accounts
(custom claims, deleting users) work as they move over. For now the API
only reads users, so `roles/firebaseauth.viewer` would be enough if you
prefer the tighter role; verifying ID tokens needs no role.

Storage (for the media pipeline, ARCHITECTURE.md §6): object admin on the
project's bucket only, and permission to sign URLs as itself:

```sh
gcloud storage buckets list --format='value(name)'   # usually $PROJECT.firebasestorage.app
BUCKET="$PROJECT.firebasestorage.app"                # or $PROJECT.appspot.com on older projects
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="serviceAccount:$RUNTIME_SA" --role=roles/storage.objectAdmin
gcloud iam service-accounts add-iam-policy-binding "$RUNTIME_SA" \
  --member="serviceAccount:$RUNTIME_SA" --role=roles/iam.serviceAccountTokenCreator
```

The website's server key (`WEB_SERVER_KEY`, see `apps/web/README.md`): a
random value in Secret Manager that only `api-runtime` can read. The
service reads it at deploy time, so create it before the first deploy. Put
the same value in Vercel's `WEB_SERVER_KEY` (dev key on Preview, prod key
on Production); never commit it.

```sh
gcloud services enable secretmanager.googleapis.com
openssl rand -base64 32 | tr -d '
' | gcloud secrets create web-server-key --data-file=-
gcloud secrets add-iam-policy-binding web-server-key --member="serviceAccount:$RUNTIME_SA" --role=roles/secretmanager.secretAccessor
gcloud secrets versions access latest --secret=web-server-key   # copy into Vercel
```

### 5. The deployer identity (GitHub Actions)

**Recommended: Workload Identity Federation (no key in GitHub).** GitHub's
short-lived OIDC token is exchanged for a deployer service account, only
for this repository (and, for prod, only for jobs in the approved `prod`
environment):

```sh
DEPLOYER_SA="api-deployer@$PROJECT.iam.gserviceaccount.com"
gcloud iam service-accounts create api-deployer --display-name="GitHub Actions: deploy the API"

gcloud iam workload-identity-pools create github \
  --location=global --display-name="GitHub Actions"

# dev:
CONDITION="assertion.repository == '$REPO'"
# prod instead (only jobs that passed the prod environment's approval):
# CONDITION="assertion.repository == '$REPO' && assertion.environment == 'prod'"

gcloud iam workload-identity-pools providers create-oidc frisbee-app \
  --location=global --workload-identity-pool=github \
  --display-name="frisbee_app repo" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.environment=assertion.environment" \
  --attribute-condition="$CONDITION"

gcloud iam service-accounts add-iam-policy-binding "$DEPLOYER_SA" \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/attribute.repository/$REPO"

# The value for the GCP_WIF_PROVIDER_DEV / _PROD repository variable:
gcloud iam workload-identity-pools providers describe frisbee-app \
  --location=global --workload-identity-pool=github --format='value(name)'
```

Then in GitHub → Settings → Secrets and variables → Actions → **Variables**:

| Variable | Value |
|---|---|
| `GCP_WIF_PROVIDER_DEV` / `_PROD` | the provider name printed above (`projects/<number>/locations/global/workloadIdentityPools/github/providers/frisbee-app`) |
| `GCP_DEPLOYER_SA_DEV` / `_PROD` | `api-deployer@<project>.iam.gserviceaccount.com` |

**Or: the existing key secret.** Without those variables the workflow signs
in with `FIREBASE_SA_DEV` / `_PROD`, the keys the backend deploy uses. Then
give that account the roles below instead (`DEPLOYER_SA=<its email>`, the
`client_email` in the key). This works without the setup above but keeps a
long-lived key in GitHub; prefer WIF.

Either way, the deployer gets only what deploying needs:

```sh
# Deploy and update Cloud Run services (not IAM on them).
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:$DEPLOYER_SA" --role=roles/run.developer
# Push images to this one repository.
gcloud artifacts repositories add-iam-policy-binding stall10 --location="$REGION" \
  --member="serviceAccount:$DEPLOYER_SA" --role=roles/artifactregistry.writer
# Run the service as api-runtime ("act as" that account only).
gcloud iam service-accounts add-iam-policy-binding "$RUNTIME_SA" \
  --member="serviceAccount:$DEPLOYER_SA" --role=roles/iam.serviceAccountUser
```

### 6. Create the service and make it public

The API does its own auth (Firebase ID tokens), so Cloud Run must let
every request through. Create the service once with Google's sample image,
under the runtime account, and allow unauthenticated calls; the first
**Deploy API** run then replaces the image and configuration:

```sh
gcloud run deploy api --region="$REGION"   --image=us-docker.pkg.dev/cloudrun/container/hello   --service-account="$RUNTIME_SA" --min-instances=0 --max-instances=1   --allow-unauthenticated
```

(If this says the policy can't be set, run
`gcloud run services add-iam-policy-binding api --region="$REGION" --member=allUsers --role=roles/run.invoker`.)
Then run **Deploy API** for this environment.

### 7. Point the app and the website at it

```sh
gcloud run services describe api --region="$REGION" --format='value(status.url)'
# e.g. https://api-<hash>-uc.a.run.app
```

- **App, local:** set `"API_BASE_URL"` in `apps/mobile/secrets.local.json`
  (dev URL) and `apps/mobile/secrets.prod.local.json` (prod URL).
- **App, Codemagic:** base64-encode each updated file again and replace
  `SECRETS_LOCAL_JSON` in the `frisbee_secrets_dev` / `frisbee_secrets`
  groups (docs/ios-release.md, step 4).
- **Website (Vercel):** project → Settings → Environment Variables →
  `API_BASE_URL` (and `NEXT_PUBLIC_API_BASE_URL`, for browser calls) = the
  prod URL for Production, the dev URL for Preview and Development, plus
  `WEB_SERVER_KEY` from step 4. Add the site's origins to `API_CORS_ORIGINS_PROD`
  / `_DEV` and redeploy the API.

The app keeps writing Firestore directly until a build has
`API_BASE_URL`; the `use_api_*` flags in `meta/flags` turn the API path
off again without a build.

## Logs

The API writes one JSON line per event with `severity` and `message`, and
groups each request's lines under its trace.

- Console: Cloud Run → `api` → **Logs**, or Logs Explorer with
  `resource.type="cloud_run_revision" resource.labels.service_name="api"`.
- Terminal:

  ```sh
  gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="api"' \
    --project <project> --limit 50 --freshness 1h
  # errors only: add AND severity>=ERROR
  ```

## Cost

- **Scales to zero** (`minScale: 0`): no requests, no charge for the
  service. The first request after an idle spell waits for a cold start
  (about 1–3 s; startup CPU boost is on). Set `minScale: "1"` in
  `service.yaml` later if that matters more than about $5–10 a month per
  always-on instance.
- **CPU only during requests** (request-based billing). Cloud Run's free
  tier (per billing account, per month: about 2 million requests,
  180,000 vCPU-seconds and 360,000 GiB-seconds) should cover dev and early
  prod. Check https://cloud.google.com/run/pricing before relying on it.
- `maxScale` (3 dev, 10 prod) caps the bill if something floods the API; at
  80 concurrent requests per instance that's 240 / 800 requests in flight.
- **Artifact Registry**: storage beyond the free 0.5 GB is about
  $0.10/GB-month; the cleanup policy above keeps it to recent images.
- Firestore, Auth and Storage usage is billed as it is today
  (firebase/docs/cloud-limits.md); the API doesn't add reads beyond what
  the app did.

## Video transcoding (later)

The same Dockerfile's `media` target adds ffmpeg (Debian's: libx264, AAC,
HEVC decoding) and `heif-convert`. When the transcoder exists, build and
push it next to the API image and create the job once:

```sh
docker build -f apps/api/Dockerfile --target media \
  -t "$REGION-docker.pkg.dev/$PROJECT/stall10/media:<commit>" .
gcloud run jobs create transcode --region="$REGION" \
  --image="$REGION-docker.pkg.dev/$PROJECT/stall10/media:<commit>" \
  --service-account="$RUNTIME_SA" --command=node --args=dist/transcode.js \
  --cpu=2 --memory=2Gi --task-timeout=30m --max-retries=1
```

The API would then start executions (`run.jobs.run` on the job for
`api-runtime`), and the deploy workflow gain a step to update the job's
image.

## Building and running the image locally

Needs Docker Desktop. From the repo root:

```sh
docker build -f apps/api/Dockerfile -t stall10-api .
docker run --rm -p 8080:8080 -e FIREBASE_PROJECT_ID=frisbee-app-brianrhonea-dev stall10-api
curl localhost:8080/health                       # {"ok":true}
curl -X POST localhost:8080/v1/teams -H 'content-type: application/json' -d '{}'
# 401 {"error":{"code":"unauthenticated",...}}
```

Without Google credentials in the container, `/ready` answers 503 and
Firestore calls fail; for real calls run the API with `pnpm dev:api`
instead (it uses your `gcloud auth application-default login`).
