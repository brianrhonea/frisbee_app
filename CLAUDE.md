# Frisbee App — project instructions

## Secrets: never commit them

All secrets (API keys, tokens, credentials, service-account files) live in
gitignored local files and must never be committed or pushed to GitHub.

- Firebase API keys live in `secrets.local.json` (gitignored). The app reads
  them at build time via `--dart-define-from-file=secrets.local.json`;
  `lib/firebase_options.dart` only references `String.fromEnvironment(...)`.
- `secrets.example.json` is the committed template — keys only, empty values.
  When adding a new secret, add the key to both files and read it with
  `String.fromEnvironment` (Dart) or `defineSecret` (Cloud Functions).
- Native Firebase config files are gitignored local files:
  `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`,
  `macos/Runner/GoogleService-Info.plist`. Get them from the Firebase console
  or `flutterfire configure`.
- iOS Google Sign-In IDs live in `ios/Flutter/Secrets.xcconfig` (gitignored;
  template `ios/Flutter/Secrets.example.xcconfig`), filled from
  `GoogleService-Info.plist`'s `REVERSED_CLIENT_ID` and `CLIENT_ID`.
- Codemagic (`codemagic.yaml`) gets every secret from its `frisbee_secrets`
  environment group and App Store Connect API key integration. Never put
  secrets, `.p8` keys, certificates or provisioning profiles in the repo.
- Never hardcode a secret in source, tests, docs, or commit messages. Never
  paste one into a published artifact or external service.
- `flutterfire configure` rewrites `lib/firebase_options.dart` with hardcoded
  keys. Re-run it with `--out=lib/firebase_options.generated.dart` (gitignored),
  copy any new/changed keys into `secrets.local.json`, then delete the
  generated file.
- Before every commit, check that no secret is staged:
  `git diff --cached | grep -E "AIza[0-9A-Za-z_-]{20,}|BEGIN (RSA )?PRIVATE KEY|\"private_key\""`
  must print nothing, and `git status` must not list any of the files above.
- If a secret is ever committed, stop and tell the user. Rotate the key; don't
  just delete it in a follow-up commit.

## Running and building

Always pass the secrets file:

```
flutter run -d windows --dart-define-from-file=secrets.local.json
flutter build web --dart-define-from-file=secrets.local.json
```

VS Code launch configs in `.vscode/launch.json` already do this.

iOS App Store builds run on Codemagic (no Mac needed); see
`docs/ios-release.md`.

## Architecture

Follow the official Flutter MVVM architecture guide: `data/services` →
`data/repositories` (abstract + Firebase impl) → `ui/<feature>/view_models`
(ChangeNotifier + `Command`s) → `ui/<feature>/widgets` (no logic). DI via
`provider`; no Riverpod. Team membership writes are validated only by
`firestore.rules`, so update the rules (and `functions/test/rules`) with any
membership change.

## USA Ultimate data

play.usaultimate.org's robots.txt disallows Claude/Anthropic agents. Don't
fetch it directly; work from the fixtures in `functions/test/fixtures/` or ask
the user for a page snapshot.

## Checks

```
flutter analyze && flutter test
cd functions && npm run build && npm test
```
