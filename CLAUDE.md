# Stall 10 — project instructions

Monorepo (see `ARCHITECTURE.md`):

```
apps/mobile    Flutter app (iOS first, Android); Dart package `frisbee_app`
apps/api       Node.js API (TypeScript, Fastify, firebase-admin, zod)
apps/web       Next.js website (phase 3; placeholder today)
packages/      Shared TypeScript (@stall10/shared: types, zod schemas)
firebase/      firebase.json, rules, indexes, functions, hosting, scripts, docs
docs/          Current-state architecture, user guide, changelog, iOS release
```

## Secrets: never commit them

All secrets (API keys, tokens, credentials, service-account files) live in
gitignored local files and must never be committed or pushed to GitHub.

- Firebase API keys live in `apps/mobile/secrets.local.json` (dev) and
  `apps/mobile/secrets.prod.local.json` (prod), both gitignored. The app
  reads them at build time via `--dart-define-from-file=secrets.local.json`
  (run from `apps/mobile`); `lib/firebase_options.dart` only references
  `String.fromEnvironment(...)`.
- `apps/mobile/secrets.example.json` is the committed template — keys only,
  empty values. When adding a new secret, add the key to both files and read
  it with `String.fromEnvironment` (Dart), `defineSecret` (Cloud Functions)
  or an environment variable (API; template `apps/api/.env.example`, real
  values in the gitignored `apps/api/.env`).
- The API uses Application Default Credentials (Cloud Run's identity, or
  `gcloud auth application-default login` / the emulators locally). Never
  create or commit a service-account key for it.
- Native Firebase config files are gitignored local files:
  `apps/mobile/android/app/google-services.json`,
  `apps/mobile/ios/Runner/GoogleService-Info.plist`,
  `apps/mobile/macos/Runner/GoogleService-Info.plist`. Get them from the
  Firebase console or `flutterfire configure`.
- iOS Google Sign-In IDs live in `apps/mobile/ios/Flutter/Secrets.xcconfig`
  (gitignored; template `Secrets.example.xcconfig`), filled from
  `GoogleService-Info.plist`'s `REVERSED_CLIENT_ID` and `CLIENT_ID`.
- Codemagic (`codemagic.yaml`) gets every secret from its `frisbee_secrets`
  environment groups and App Store Connect API key integration. Never put
  secrets, `.p8` keys, certificates or provisioning profiles in the repo.
- Never hardcode a secret in source, tests, docs, or commit messages. Never
  paste one into a published artifact or external service.
- `flutterfire configure` (run in `apps/mobile`) rewrites
  `lib/firebase_options.dart` with hardcoded keys. Re-run it with
  `--out=lib/firebase_options.generated.dart` (gitignored), copy any
  new/changed keys into `secrets.local.json`, then delete the generated
  file. It also writes `apps/mobile/firebase.json` (gitignored); the real
  config is `firebase/firebase.json`.
- Before every commit, check that no secret is staged:
  `git diff --cached | grep -E "AIza[0-9A-Za-z_-]{20,}|BEGIN (RSA )?PRIVATE KEY|\"private_key\""`
  must print nothing, and `git status` must not list any of the files above.
- If a secret is ever committed, stop and tell the user. Rotate the key; don't
  just delete it in a follow-up commit.

## Environments

Two Firebase projects:

- `frisbee-app-brianrhonea-dev` (dev): local runs, and TestFlight builds from
  the `development` branch. `secrets.local.json` (`"FIREBASE_ENV": "dev"`).
- `frisbee-app-brianrhonea` (prod): App Store builds from `main`.
  `secrets.prod.local.json` (`"FIREBASE_ENV": "prod"`).

Local native config files (`apps/mobile/android/app/google-services.json`)
are the dev project's; prod copies are
`apps/mobile/android/app/google-services.prod.json` and the root
`GoogleService-Info.plist` (dev: `GoogleService-Info.dev.plist`), all
gitignored. Run the Firebase CLI from `firebase/` (it finds
`firebase.json` there); it defaults to dev. Deploy to production only with
`--project prod`, and only when the user asks.

## Running and building

The app (always pass the secrets file; run from `apps/mobile`):

```
cd apps/mobile
flutter run -d windows --dart-define-from-file=secrets.local.json
flutter build windows --dart-define-from-file=secrets.local.json
flutter build ipa --dart-define-from-file=secrets.local.json   # Codemagic does this
```

VS Code launch configs in `.vscode/launch.json` already do this.

`API_BASE_URL` in the secrets file points the app at the API; without it
the app writes Firestore directly as before. The `use_api_*` flags in
`meta/flags` switch API paths off without a build.

The API and shared packages (pnpm workspace, from the repo root):

```
pnpm install
pnpm dev:api                         # builds @stall10/shared, then tsx watch on :8787
cd firebase && firebase emulators:start   # optional; set the emulator hosts in apps/api/.env
```

iOS App Store builds run on Codemagic (no Mac needed) from `apps/mobile`;
see `docs/ios-release.md`. Pushes that don't touch `apps/mobile/` or
`packages/` skip the iOS build.

## Website

Today: Firebase Hosting serves `firebase/build/site` (gitignored), built by
`firebase/scripts/build_site.sh` (firebase.json predeploy): the Flutter web
app (`apps/mobile/lib/main_web.dart`, `lib/routing/web_router.dart`,
`lib/ui/web/`, `lib/ui/browse/`) at `/`, and the static pages in
`firebase/hosting/` (`/about`, `/help`, `/terms`, `/privacy`, `/cookies`,
invite fallbacks) beside it. Signed-out visitors browse the community
feed, search, public profiles, team pages and events through the `browse`
Cloud Functions (allow-listed public fields, rate-limited per hashed IP;
Firestore rules stay sign-in-only), and liking, following or joining asks
them to sign up. Members get their home feed and the app's screens; other
paths show "get the app". The legal pages are drafts: fill in the
[bracketed] details and get them reviewed before launch.

```
cd apps/mobile && flutter run -d chrome -t lib/main_web.dart --dart-define-from-file=secrets.local.json
bash firebase/scripts/build_site.sh && cd firebase && firebase emulators:start --only hosting
```

Phase 3 replaces it with `apps/web` (Next.js on Vercel; see
`apps/web/README.md`): the public pages are ported and read through the
API's `/v1/public/*`; the member area is next. Its env lives in the
gitignored `apps/web/.env.local` (template `.env.example`). Store URLs are
placeholders in `apps/mobile/lib/config/store_links.dart`,
`apps/web/lib/site.ts` and `firebase/hosting/about.html` / `join.html`
(and `apps/web/content/about.html`); keep them in step. The
deploy workflow builds the site from the `FIREBASE_WEB_API_KEY_DEV` /
`_PROD` repository secrets and skips hosting without them. The web API key
ends up in public JS (normal for Firebase web), so never commit `build/`.

## Architecture

- **App:** the official Flutter MVVM architecture guide: `data/services` →
  `data/repositories` (abstract + implementation) → `ui/<feature>/view_models`
  (ChangeNotifier + `Command`s) → `ui/<feature>/widgets` (no logic). DI via
  `provider`; no Riverpod. Repositories call the API through
  `data/services/api_client.dart`.
- **API:** `routes.ts` (HTTP) → `service.ts` (rules, validation, no
  Firebase imports) → `repository.ts` (interface + Firestore). The caller
  comes from the ID token, never the body. The Admin SDK bypasses
  `firestore.rules`, so a migrated operation must re-check everything its
  rule checked. Request types and zod schemas go in `packages/shared`.
- **Migrating a feature to the API:** follow the playbook and checklist in
  `ARCHITECTURE.md` §10, and update its status there.
- Team membership writes not yet migrated are validated only by
  `firebase/firestore.rules`, so update the rules (and
  `firebase/functions/test/rules`) with any membership change.
- New client-facing endpoints go in the API, not new callables.

## USA Ultimate data

USA Ultimate events, rankings, team pages and roster sync were removed
(November 2026): we don't have rights to that data. Don't add USA Ultimate
data back without the user confirming they have permission. The old code is
in git history. play.usaultimate.org's robots.txt also disallows
Claude/Anthropic agents, so never fetch it.

## Checks

```
cd apps/mobile && flutter analyze && flutter test
pnpm typecheck && pnpm test                    # shared + API (fakes)
pnpm test:api:emulator                         # API against Firestore/Auth emulators
cd firebase/functions && npm run build && npm test
cd firebase/functions && npm run test:rules    # Firestore/Storage rules (emulator)
cd firebase/functions && npm run test:server   # callables against the emulator
```

After changing what a new team starts with or the team-name rules, refresh
the shared fixtures (`flutter test test/data/shared_fixtures_test.dart
--dart-define=UPDATE_FIXTURES=true` in `apps/mobile`) and rerun `pnpm test`.
