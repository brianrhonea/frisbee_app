# UltiUP

**Version 0.0.4** · [User guide](docs/user-guide.md) · [Version log](docs/CHANGELOG.md) · [iOS release](docs/ios-release.md)

An ultimate frisbee team app built with Flutter + Firebase for Android, iOS, macOS and Windows. The website is a separate project. (The Dart package is still named `frisbee_app`.)

**Features**
- Sign in with email/password, Google and Apple (Google/Apple are hidden on Windows, which has no plugin support)
- Team-first Home: this week's events, your team, a playbook preview, upcoming events and a rankings podium
- Teams with roles (owner, coach, captain, player, plus stats access), invite codes and a roster that can be imported and synced from USA Ultimate
- Team schedule with RSVPs, reactions and polls; a personal schedule; and a Schedule tab merging both, with swipe-to-delete by role
- Playbook with a drawable field editor and animated plays
- Live game stats: lines, O/D, pull timer, stat sheets and season stats
- USA Ultimate tournaments, rankings and team search, scraped live in the app
- Light/dark theme setting
- Role-based privacy enforced by `firestore.rules`: paid/USA Ultimate status and the invite code are admin-only; personal events are private

## Versioning

The version is in `pubspec.yaml` (`version: 0.0.4+4`) and `appVersion` in `lib/ui/core/ui/brand.dart`, and shows on the Profile screen. Each feature branch bumps the patch version and adds an entry to [docs/CHANGELOG.md](docs/CHANGELOG.md); `test/version_test.dart` checks the three agree.

## Architecture

The app follows the [Flutter app architecture guide](https://docs.flutter.dev/app-architecture) (MVVM):

```
lib/
  config/dependencies.dart    provider wiring (services -> repositories)
  data/services/              thin wrappers over Firebase SDKs
  data/repositories/<x>/      abstract repository + Firebase implementation
  domain/models/              immutable models, no Firebase types
  routing/                    go_router with auth redirect
  ui/<feature>/view_models/   ChangeNotifier ViewModels exposing Commands
  ui/<feature>/widgets/       Views, no business logic
  utils/                      Result, Command, platform support
functions/                    Cloud Functions (TypeScript): USA Ultimate sync (not deployed yet)
firestore.rules               security rules (the trust boundary for membership and privacy)
docs/                         user guide, version log, iOS release steps
```

Team membership changes are written by the client and validated by `firestore.rules`, so they work on every platform. (`cloud_functions` has no Windows plugin, which is why team actions are not callables.)

## One-time setup

The Firebase project `frisbee-app-brianrhonea` and its apps are already registered.

In the [Firebase console](https://console.firebase.google.com/project/frisbee-app-brianrhonea/overview):

1. **Firestore**: Build > Firestore Database > Create database (location `nam5`, production mode).
2. **Authentication**: Build > Authentication > Get started, then enable:
   - Email/Password
   - Google
   - Apple (needs an Apple Developer Services ID + key; see Firebase docs)
3. **Blaze plan**: only needed once the Cloud Functions are deployed (see [USA Ultimate data](#usa-ultimate-data)).
4. **Android Google sign-in**: add your debug/release SHA-1 under Project settings > Android app, then re-run `flutterfire configure` to refresh `google-services.json`.
   ```
   cd android && ./gradlew signingReport
   ```
5. **iOS/macOS (on a Mac)**:
   - After enabling Google sign-in, re-run `flutterfire configure`, then add `GIDClientID` and the `REVERSED_CLIENT_ID` URL scheme from `GoogleService-Info.plist` to `ios/Runner/Info.plist` and `macos/Runner/Info.plist`.
   - In Xcode, add the **Sign in with Apple** capability to the iOS Runner target, and set your signing team for both iOS and macOS (macOS entitlements already include network, keychain and Apple sign-in).
   - Set `platform :ios, '15.0'` in `ios/Podfile` if `pod install` complains.

Then deploy the security rules:

```
firebase deploy --only firestore:rules
```

Don't deploy `functions` (or run a bare `firebase deploy`) until you're ready to move USA Ultimate collection to the cloud; see below.

## Secrets

API keys are kept out of git (see `CLAUDE.md`). On a fresh clone:

1. Copy `secrets.example.json` to `secrets.local.json` and fill in the Firebase API keys
   (Firebase console > Project settings > Your apps).
2. Download `google-services.json` to `android/app/` (and `GoogleService-Info.plist` to
   `ios/Runner/` and `macos/Runner/` on a Mac), or run
   `flutterfire configure --out=lib/firebase_options.generated.dart`.

## Running

```
flutter run -d windows --dart-define-from-file=secrets.local.json
flutter run -d <android-device> --dart-define-from-file=secrets.local.json
```

VS Code launch configs in `.vscode/launch.json` pass the file for you.

Against local emulators (needs Java 21+ for the Firestore emulator):

```
cd functions && npm run serve          # auth, firestore, functions emulators
flutter run -d windows --dart-define-from-file=secrets.local.json --dart-define=USE_EMULATORS=true
curl http://127.0.0.1:5001/frisbee-app-brianrhonea/us-central1/refreshUsau   # populate USAU data
```

## Tests

```
flutter analyze && flutter test        # models, ViewModels, router redirect, widgets
cd functions && npm test               # USA Ultimate HTML parsers (real page snapshots)
cd functions && npm run test:rules     # Firestore security rules (needs Java for the emulator)
```

## USA Ultimate data

USA Ultimate has no public API, so its pages on `play.usaultimate.org` are scraped.

**Today: live, in the app.** `TournamentRepositoryUsau`, `RankingRepositoryUsau` and `UsauTeamRepositoryUsau` fetch pages on the device (client and parser in `lib/data/services/usau/`) and keep them in memory. No Firebase usage is spent on it.

**Later: Cloud Functions.** `functions/src/usau/` does the same server-side on a schedule (every two months for now: `0 5 1 */2 *` and `30 5 1 */2 *`, Denver time) and writes:

- `/events/tournament/` -> `usau_tournaments/{slug}`
- `/teams/events/rankings/` lists rank sets -> each `team_rankings/?RankSet=...` -> `usau_rankings/{key}`

The functions are deliberately **not deployed** while the user base is small. To switch: deploy them (`firebase deploy --only functions`, needs the Blaze plan) and use `TournamentRepositoryFirebase` and `RankingRepositoryFirebase` in `lib/config/dependencies.dart`.

Server-side parsers live in `parse.ts` with HTML fixtures in `functions/test/fixtures/`. If USAU changes its layout, sync throws instead of wiping data; update the parser and fixture. The rankings-page parser maps columns by header name and is tested against a **synthetic** fixture; check it against a real page after the first sync.

The app shows attribution and links back to USA Ultimate. Review USA Ultimate's terms of use before releasing publicly, and consider asking them for permission or a data feed.
