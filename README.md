# Stall 10

**Version 0.0.4** · [User guide](docs/user-guide.md) · [Architecture](ARCHITECTURE.md) · [Current-state architecture](docs/ARCHITECTURE.md) · [Version log](docs/CHANGELOG.md) · [iOS release](docs/ios-release.md) · [Cloud limits](docs/cloud-limits.md)

An ultimate frisbee team app. A monorepo: the Flutter app for iOS and Android (`apps/mobile`, Dart package `frisbee_app`), a Node.js API both clients call (`apps/api`), the Next.js website (`apps/web`, phase 3), shared TypeScript (`packages/`), and the Firebase project (`firebase/`). See [ARCHITECTURE.md](ARCHITECTURE.md) and [CLAUDE.md](CLAUDE.md) for commands.

**Features**
- Sign in with email/password, Google and Apple (Google/Apple are hidden on Windows, which has no plugin support)
- Team-first Home: this week's events, your team, a playbook preview and upcoming events
- Teams with roles (owner, coach, captain, player, plus stats access), invite codes and a roster with admin-only paid marks
- A home page for each team: summary, upcoming events and posts from owners, coaches and captains
- Team search: anyone can find a team and see its public page (public events and posts only)
- Team Events with RSVPs, reactions and polls; a personal schedule; and a Schedule tab merging both, with swipe-to-delete by role
- Playbook with a drawable field editor and animated plays
- Live game stats: lines, O/D, pull timer, stat sheets and season stats
- Light/dark theme setting
- Role-based privacy enforced by `firestore.rules`: paid marks and the invite code are admin-only; personal events are private

## Versioning

The version is in `apps/mobile/pubspec.yaml` (`version: 0.0.11+11`) and `appVersion` in `apps/mobile/lib/ui/core/ui/brand.dart`, and shows at the bottom of Settings. Each release bumps the patch version and adds an entry to [docs/CHANGELOG.md](docs/CHANGELOG.md) (developer log) and [docs/release-notes.md](docs/release-notes.md) (what testers see); `apps/mobile/test/version_test.dart` checks the version, pubspec and changelog agree.

## Architecture

The app follows the [Flutter app architecture guide](https://docs.flutter.dev/app-architecture) (MVVM):

```
apps/mobile/lib/
  config/dependencies.dart    provider wiring (services -> repositories)
  data/services/              thin wrappers over Firebase SDKs
  data/repositories/<x>/      abstract repository + Firebase implementation
  domain/models/              immutable models, no Firebase types
  routing/                    go_router with auth redirect
  ui/<feature>/view_models/   ChangeNotifier ViewModels exposing Commands
  ui/<feature>/widgets/       Views, no business logic
  utils/                      Result, Command, platform support
apps/api/                     Node.js API: routes -> services -> repositories (firebase-admin)
packages/shared/              API types and zod schemas shared by the API and the website
firebase/functions/           Cloud Functions (TypeScript), deployed by group
firebase/firestore.rules      security rules (the trust boundary for membership and privacy)
docs/                         architecture, user guide, version log, iOS release steps
```

Most team membership changes are still written by the client and validated by `firebase/firestore.rules`; they move to the API one feature at a time (ARCHITECTURE.md §10). Creating a team already goes through the API when the build has `API_BASE_URL`.

## One-time setup

The Firebase project `frisbee-app-brianrhonea` and its apps are already registered.

In the [Firebase console](https://console.firebase.google.com/project/frisbee-app-brianrhonea/overview):

1. **Firestore**: Build > Firestore Database > Create database (location `nam5`, production mode).
2. **Authentication**: Build > Authentication > Get started, then enable:
   - Email/Password
   - Google
   - Apple (needs an Apple Developer Services ID + key; see Firebase docs)
3. **Blaze plan and Storage**: team chat and direct message photos and files use Cloud Storage, which needs the Blaze plan. Upgrade, then Build > Storage > Get started (default bucket). The free allowance covers small teams.
4. **Android Google sign-in**: add your debug/release SHA-1 under Project settings > Android app, then re-run `flutterfire configure` to refresh `google-services.json`.
   ```
   cd android && ./gradlew signingReport
   ```
5. **iOS/macOS (on a Mac)**:
   - After enabling Google sign-in, re-run `flutterfire configure`, then add `GIDClientID` and the `REVERSED_CLIENT_ID` URL scheme from `GoogleService-Info.plist` to `ios/Runner/Info.plist` and `macos/Runner/Info.plist`.
   - In Xcode, add the **Sign in with Apple** capability to the iOS Runner target, and set your signing team for both iOS and macOS (macOS entitlements already include network, keychain and Apple sign-in).
   - Set `platform :ios, '15.0'` in `ios/Podfile` if `pod install` complains.

Then deploy the security rules and indexes:

```
cd firebase && firebase deploy --only firestore:rules,firestore:indexes,storage
```

The Storage rules read chat rooms from Firestore; accept the prompt to let
them (or grant it under Storage > Rules).

Notifications are sent by the Cloud Functions in `firebase/functions/src/notifications` (Firestore triggers and an hourly reminder job). Deploy only that group:

```
cd firebase && firebase deploy --only functions:notifications
```

iOS push also needs an APNs key uploaded to Firebase (see [iOS release](docs/ios-release.md)). Android needs nothing extra. Windows has no push (FCM has no Windows plugin); notifications still show in the app's feed.

## Secrets

API keys are kept out of git (see `CLAUDE.md`). On a fresh clone:

1. In `apps/mobile`, copy `secrets.example.json` to `secrets.local.json` and fill in the Firebase API keys
   (Firebase console > Project settings > Your apps).
2. Download `google-services.json` to `android/app/` (and `GoogleService-Info.plist` to
   `ios/Runner/` and `macos/Runner/` on a Mac), or run
   `flutterfire configure --out=lib/firebase_options.generated.dart`.

## Running

```
cd apps/mobile
flutter run -d <android-emulator-or-device> --dart-define-from-file=secrets.local.json
```

The API (Node 22, pnpm): `pnpm install && pnpm dev:api` from the repo root
(copy `apps/api/.env.example` to `apps/api/.env` first). Point the app at it
with `"API_BASE_URL": "http://localhost:8787"` in `secrets.local.json`
(`http://10.0.2.2:8787` from the Android emulator).

VS Code launch configs in `.vscode/launch.json` pass the file for you.

Against local emulators (needs Java 21+ for the Firestore emulator):

```
cd firebase/functions && npm run serve # auth, firestore, functions emulators
cd apps/mobile && flutter run -d <android-emulator-or-device> --dart-define-from-file=secrets.local.json --dart-define=USE_EMULATORS=true
```

## Tests

```
cd apps/mobile && flutter analyze && flutter test   # models, ViewModels, router redirect, widgets
pnpm typecheck && pnpm test            # API and shared package (fakes)
pnpm test:api:emulator                 # API against the Firestore/Auth emulators
cd firebase/functions && npm test      # functions logic (notifications, browse, api, ...)
cd firebase/functions && npm run test:rules     # Firestore security rules (needs Java for the emulator)
```
