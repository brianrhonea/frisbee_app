# iOS release checklist (per build)

For one TestFlight build made on the Mac mini. Plan:
`docs/specifications/mac-mini-build-plan.md`. Steps and commands:
`docs/ios-release.md`. Copy this list into the release issue for each build and
tick it. Nothing here claims App Store approval: a TestFlight build is not a
store release, and the store decision is Apple's.

**Environment:** dev only until #9 and R3 (prod is refused by the script).
**Who:** [OWNER] steps need the owner at the Mac (credentials, Apple accounts, the iPhone). The rest can be run by whoever is at the Mac.

## A. Before the build

- [ ] Branch: the commit to ship is on `development` (the script refuses other branches; `--ref` only takes ancestors of `development`).
- [ ] **Golden tests, on Windows, before any UI approval.** They only compare on Windows (`apps/mobile/test/ui_harness/harness.dart`) and skip on the Mac. From `apps/mobile` on the laptop (or the PC once its baseline matches, plan Q-R): `flutter test`. Record the counts. If UI changed and the goldens were not run, the build is not UI-approved.
- [ ] Version: `apps/mobile/pubspec.yaml` has the intended `X.Y.Z`, and `docs/CHANGELOG.md` has its row (`node scripts/check-versions.mjs` checks this).
- [ ] Open blockers (release-audit, `docs/specifications/release-audit.md`) reviewed for this build; note any that ship knowingly.
- [ ] Codemagic is not about to build the same push: until its triggers are manual-only, a push to `development` costs money and can take the same build number. [OWNER] approves every push.

## B. Doctor

- [ ] `scripts/ios/mac-doctor.sh` on the Mac: **no FIX lines** (WARN lines read and accepted). It checks macOS, Xcode, Flutter 3.41.2, CocoaPods, Node, pnpm, `codemagic-cli-tools`, the Apple Distribution identity, the API key (mode 600), the secret files (presence), sleep disabled.
- [ ] Xcode, macOS, Flutter and CocoaPods versions noted (for the version log, section F).

## C. Release script

- [ ] `scripts/ios/release-ios.sh dev --dry-run`: steps look right (branch, build lookups, upload line if you pass `--upload`).
- [ ] `scripts/ios/release-ios.sh dev` (add `--upload` when this build should go to TestFlight). Do not push anything. Expect: Flutter 3.41.2 check, `pub get`, `pod install`, analyze, test, version check, build-number lookup (max of App Store and TestFlight, plus 1), `flutter build ipa`.
- [ ] The script printed the bundle ID, version and build from the IPA, and they are the expected values.
- [ ] `~/hylite-releases/dev/<version>+<build>/` holds the `.ipa`, `Runner.xcarchive`, `dSYMs/` and `release.log`.
- [ ] Crashlytics symbols (first build after lane B, then spot checks): the "Upload Crashlytics Symbols" phase appears in the log, and the dSYM appears in the Firebase console. If not, re-upload from the kept `dSYMs/`.
- [ ] No secret files left in the repo: `git status` clean, and `apps/mobile/secrets.local.json` and `apps/mobile/ios/Runner/GoogleService-Info.plist` do not exist (the script removes them on exit).
- [ ] A local tag `ios-dev-<version>+<build>` exists (`git tag -l 'ios-*'`). It is **not pushed**; pushing needs the owner each time.
- [ ] If the upload failed: the fallback lines the script printed (`app-store-connect publish`, or Transporter). Re-running creates a new build number, so prefer the fallback for the same IPA.

## D. TestFlight processing

- [ ] [OWNER] App Store Connect > TestFlight shows the new build. Wait for "Processing" to finish (minutes to an hour; unverified).
- [ ] Any "Missing compliance" or export-compliance prompt answered by the owner.
- [ ] Internal testers group has the build. No external review is requested for the founding-team beta unless the owner decides so.

## E. Install check on the iPhone [OWNER]

Simulator results do not count as physical-device compatibility (CLAUDE.md section 10).

- [ ] TestFlight installs and launches the build; the About or version screen matches `<version>+<build>`.
- [ ] Sign-in works (email, Apple, Google as configured for dev).
- [ ] Core flows from the beta list open without crashing: Home, Discover, Teams, Schedule, Chats.
- [ ] Physical-only checks for this build, as the changes require: push notifications, camera and microphone permissions, media playback, background and network changes, LiveKit, Universal Links.
- [ ] Crashlytics test crash (once, after the first build with it): appears in the Firebase console.
- [ ] Anything failing is written up as an issue with the build number, not fixed in place.

## F. Version log

- [ ] The script appended a line to `~/hylite-releases/release-log.tsv` (date, env, `<version>+<build>`, commit). Add to the release issue: commit SHA, tag, build number, macOS / Xcode / Flutter / CocoaPods versions, how long the build took, test counts (Flutter test run on the Mac, goldens on Windows), and the device and iOS version used for the install check.
- [ ] Back up `~/hylite-releases/` (plan Q-F), alongside `~/hylite-secrets` and `~/.appstoreconnect`, to the encrypted backup disk.
- [ ] After the first Mac release: [OWNER] switch Codemagic's triggers to manual-only (separate approved change to `codemagic.yaml`).
- [ ] After two Mac releases installed on a device: decide Q-H (Codemagic deleted or kept unused) and revoke Codemagic's API key (Q-E).

## G. Rollback

TestFlight builds can't be edited; a bad build is replaced, not fixed in place.

- [ ] **Stop** the bad build: in App Store Connect, remove it from the testers' group or expire it [OWNER]. Tell testers not to update.
- [ ] **Ship a new, higher build** from the last good commit: `scripts/ios/release-ios.sh dev --ref <last-good-tag-or-sha> --upload`. The build number keeps rising by rule; versions never go back.
- [ ] If the problem is the toolchain (Xcode or macOS update): reinstall the previous Xcode (keep it until the next release succeeds) and rebuild; or start Codemagic's dev workflow by hand (the fallback in `docs/ios-release.md`).
- [ ] If the Mac is unusable: Codemagic by hand, with the restored backup of secrets and keys if the Mac must be rebuilt.
- [ ] A compromised API key or signing key: revoke the key in App Store Connect and create a new one [OWNER]; update `~/.hylite-release.env`. Never paste keys into chats or the repo.
- [ ] Backend or data problems are not fixed by an app rollback: API and Firebase rules roll back through their own runbook (`docs/specifications/3a-rollout-runbook.md`).

## Not verified by this checklist

Apple's processing time and any App Review outcome. Do not report a build as approved by Apple or on the App Store from this list; only the owner's App Store Connect view shows that.
