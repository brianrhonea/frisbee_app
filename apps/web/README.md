# apps/web — Stall 10 website (phase 3)

Next.js 16 (App Router) on Vercel. It replaces the Flutter web build that
Firebase Hosting serves today (`firebase/scripts/build_site.sh`); every
platform other than iOS and Android uses it.

## What's here

| Path | What |
|---|---|
| `/` | Visitors: a preview (a few community posts and public events, locked cards, sign-up prompts). Members: their dashboard (profile card, season stats, teams, upcoming events with RSVPs, their feed) from `GET /v1/me/home` |
| `/learn` | Beginner's guide to the rules of ultimate (an original summary, not the official text) |
| `/community`, `/posts/[id]` | The public feed and one post |
| `/players/[uid]`, `/teams/[id]` | Public profiles (private ones show only their card) and team/group pages |
| `/events`, `/explore?q=` | Upcoming public events and tournaments; player and team search |
| `/about`, `/help`, `/terms`, `/privacy`, `/cookies`, `/delete-account` | Static pages ported from `firebase/hosting` (`content/*.html`, served by `app/[slug]`) |
| `/join/[code]`, `/g/[id]`, `/p/[id]` | Invite and share link fallbacks; `public/.well-known` opens them in the app |
| `/sign-in`, `/sign-up` | Firebase Auth (email/password, Google). Sign-up asks the date of birth first (13 and over) |
| (every page) | `PersonalGate`: a new account finishes signing up with its personal details (legal name, birthday, phone, gender, address, guardian under 18) before anything else; older ones get a dismissible card. Encrypted by the API (`/v1/me/personal`); only the player sees them |
| `/settings/personal` | Their personal details |
| `/home`, `/profile` | Redirect to `/` |

- **Reads:** server components call the API's public routes
  (`lib/api.ts` → `GET /v1/public/*` at `API_BASE_URL`), cached 60 seconds.
  The server sends `x-stall10-web-key: WEB_SERVER_KEY`, so the API doesn't
  rate-limit it as a single visitor; Vercel's firewall limits visitors.
- **Visitors** see one page of the feed and of each profile (the API
  returns no cursor to them); everything else asks them to sign up.
- **Members:** the browser calls the API with the user's ID token
  (`lib/client.ts`, `NEXT_PUBLIC_API_BASE_URL`): `GET /v1/me/home` for the
  dashboard, `POST /v1/me/username` for the username step, likes and
  reposts on every post (`components/PostActions.tsx`; the buttons' state
  comes from one batched `GET /v1/posts/state` per page, `lib/postState.ts`,
  so the cached server-rendered pages stay the same for everyone), and
  `GET /v1/feed` for older community posts. The header's links and the
  sign-up prompts (`ForVisitors`) follow who's signed in. It uses Firebase
  only to sign in, to load photos visitors can't see (Storage
  `getDownloadURL`), and later for live listeners (chat, feeds, live stats).
- **Version:** `version` in `package.json`, shown in the footer. Bump it
  and add an entry to `CHANGELOG.md` with every change (`pnpm test` checks).
- Types come from `@stall10/shared` (`browse.ts`).
- Styles: `app/site.css` (ported from `firebase/hosting/site.css`, follows
  the system's light/dark setting) and `app/app.css`.

## Running

```
cp apps/web/.env.example apps/web/.env.local   # fill in; never commit it
pnpm install
pnpm dev:api                                   # the API on :8787
pnpm --filter @stall10/web dev                 # the site on :3000
```

Against the emulators: start `firebase emulators:start` in `firebase/`,
point the API at them (`apps/api/.env`), and set
`NEXT_PUBLIC_FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099` (and
`NEXT_PUBLIC_FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199`) to sign in
there. `NEXT_PUBLIC_*` values are baked in at build time, so rebuild after
changing them.

## Vercel

One Vercel project, `frisbeeapp` (team `brian-honeas-projects`), serves
both sites:

| | Dev site | Prod site |
|---|---|---|
| Branch | `development` (and every other non-`main` branch) | `main` |
| Vercel environment | Preview | Production |
| Firebase project | `frisbee-app-brianrhonea-dev` | `frisbee-app-brianrhonea` |
| API | dev Cloud Run `api` | prod Cloud Run `api` |
| Address | `https://dev.stall10.app` (Settings → Domains, Git Branch `development`); other branches `frisbeeapp-git-<branch>-brian-honeas-projects.vercel.app` | `https://stall10.app` |

Until `monorepo` is merged into `development`, the dev site is
`frisbeeapp-git-monorepo-brian-honeas-projects.vercel.app`.

### Project settings

- **Settings → Build and Deployment:** Framework Preset **Next.js**, Root
  Directory `apps/web`, "Include files outside the root directory" on, and
  no overrides for the build, install or output commands. The `build`
  script compiles `@stall10/shared` first (its `dist/` isn't committed).
- **Settings → Environments → Production:** branch `main`.
- **Deployment Protection:** Vercel Authentication is on for previews, so
  the dev site asks for a Vercel login. Turn it off to test on a phone or
  share the dev site.

### Environment variables

The variables in `.env.example`, each added twice: dev values with only
**Preview** ticked, prod values with only **Production** ticked.

| Variable | Dev (Preview) | Prod (Production) | Sensitive |
|---|---|---|---|
| `API_BASE_URL`, `NEXT_PUBLIC_API_BASE_URL` | dev API URL | prod API URL | no |
| `WEB_SERVER_KEY` | `gcloud secrets versions access latest --secret=web-server-key --project frisbee-app-brianrhonea-dev` | same, `--project frisbee-app-brianrhonea` | **yes** |
| `NEXT_PUBLIC_SITE_URL` | `https://dev.stall10.app` | `https://stall10.app` | no |
| `NEXT_PUBLIC_FIREBASE_*` | the dev web app's config | the prod web app's config | no |

Get a project's web config with `firebase apps:sdkconfig WEB <app id>
--project <project>` (app ids from `firebase apps:list WEB`). The
`NEXT_PUBLIC_*` values are built into the site, so redeploy after
changing them.

### Pitfalls

- **Import shows only `main`.** The import screen browses the default
  branch, which may not have `apps/web`. Import with root `./`, let the
  first build fail, then set the root directory and branch in Settings.
- **Every page is Vercel's `404: NOT_FOUND`.** The Framework Preset isn't
  Next.js (an import with root `./` picks "Other"). Changing the root
  directory doesn't change the preset.
- **No quotes in values.** Vercel stores them literally. A quoted Firebase
  key (copied from `.env.local`) makes Google sign-in close its popup at
  once, with `auth/api-key-not-valid` (400) in the console.
- **`NEXT_PUBLIC_*` can't be Sensitive** ("cannot use `visibility:
  secret`"). They're public anyway; only `WEB_SERVER_KEY` is a secret.
  If the team forces Sensitive variables, turn that policy off.
- **An existing variable can't be added again** for the same
  environment; edit it instead.

### Firebase and the API

- In Firebase Auth (each project), add the site's domains to
  **Authorized domains** (no wildcards, so use the branch address, not a
  per-build one), or sign-in fails with "isn't set up for this web
  address".
- Add the site's addresses to the API's `CORS_ORIGINS` (repository
  variables `API_CORS_ORIGINS_DEV` / `_PROD`, `apps/api/DEPLOY.md`), or
  the member dashboard can't load. Dev uses
  `http://localhost:3000,https://dev.stall10.app,https://frisbee*-brian-honeas-projects.vercel.app`
  (the dev domain, then branch and per-build addresses); prod uses
  `https://stall10.app`.
- Add a firewall rate-limit rule for visitors (the API trusts this server
  through `WEB_SERVER_KEY`).
- Keep store URLs in step: `lib/site.ts`, `apps/mobile/lib/config/store_links.dart`.
