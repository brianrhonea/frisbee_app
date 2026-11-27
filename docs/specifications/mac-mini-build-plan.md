# Moving Hylite iOS builds from Codemagic to the owner's Mac mini

**Status:** draft for owner approval, written 2026-11-26 for the owner's setup session on 2026-11-27. Nothing here has been run. Items marked *(unverified)* must be confirmed on the Mac.

**Baseline:** `feature/jan-4-release` at `9d71225`. The Crashlytics changes were read from `sprint3/lane-b`.

**Why move:** Codemagic is pay-as-you-go. "Private hosting" here means a self-hosted build machine. Moving the website off Vercel or the API off Cloud Run is out of scope (§9).

**Not yet covered:** a section on the always-on Windows PC (golden tests, bulk test runs, later Android builds) has been requested and will be added.

## Summary and recommendation

- **Option (a), local scripts.** Two scripts the owner runs on the Mac: `flutter build ipa`, then an upload using an App Store Connect API key. No fastlane and no self-hosted runner for January.
- **Build numbers** follow exactly the same rule as today. The script reads the latest numbers with `codemagic-cli-tools`, the open-source tool behind Codemagic's own `app-store-connect` command.
- **Signing:**
  - The archive is signed automatically with the owner's development certificate.
  - The export is signed manually with the Apple Distribution certificate and the existing App Store profile.
  - No `match`.
- **Golden tests** stay on Windows. The Mac does iOS builds, signing, the simulator and physical-device runs.
- **Codemagic** stays as a fallback you start by hand, until two Mac releases have succeeded. Its automatic triggers go off at the first Mac release; otherwise every push to `development` still costs money.

## 1. What Codemagic does today

References are to `codemagic.yaml` unless another file is named.

| Area | What it does | Ref |
|---|---|---|
| Workflows | `ios-testflight` (dev). `ios-app-store` (prod) inherits from it | 25-26, 127-129 |
| Machine | `mac_mini_m2`, 60-minute limit, runs in `apps/mobile` | 27-29 |
| Triggers | A push to `development` runs the dev build; a push to `main` runs prod. Earlier builds are cancelled. It skips unless `apps/mobile/`, `packages/` or `codemagic.yaml` changed | 52-65, 138-145 |
| Flutter | Pinned to 3.41.2, the same pin as `ci-flutter.yml:39-43` and `_deploy-backend.yml:124-127` | 36 |
| Xcode and CocoaPods | `xcode: latest` (not pinned); CocoaPods at its default version | 37-38 |
| Secrets | Groups `frisbee_secrets_dev` and `frisbee_secrets`, each holding `SECRETS_LOCAL_JSON` and `GOOGLE_SERVICE_INFO_PLIST` in base64. They are decoded to files at build time, and the build fails unless `API_BASE_URL` starts with `https://` | 17-22, 40, 67-75 |
| Google Sign-In | Writes `ios/Flutter/Secrets.xcconfig` from the plist (the file is gitignored) | 76-83 |
| Signing | `use-profiles` with the Apple Distribution certificate and the "Stall 10 App Store" profile. Bundle ID `com.brianrhonea.frisbeeApp` | 41-46, 84-85 |
| Packages | `flutter pub get`, then `pod install --repo-update`. No `Podfile.lock` is committed | 86-94 |
| Checks | `flutter analyze` and `flutter test`. Golden tests skip because the machine isn't Windows | 95-98 |
| Build number | The higher of the latest App Store and TestFlight build numbers, plus 1. A failed lookup counts as 0 | 99-109 |
| Build | `flutter build ipa --release --dart-define-from-file=secrets.local.json --build-number=N --export-options-plist=…` | 110-117 |
| Publish | Uploads to TestFlight through an API key. Prod has `submit_to_app_store: false` | 30-32, 122-125, 146-151 |

**Other facts from the repo:**
- **Xcode scheme:** there is only one, `Runner`.
- **Bundle ID:** hard-coded as `com.brianrhonea.frisbeeApp` at `pbxproj:503, 686, 709`.
- **iOS minimum version:** 15.0.
- **Crashlytics (lane B):** adds an "Upload Crashlytics Symbols" phase (`${PODS_ROOT}/FirebaseCrashlytics/run`) and the `firebase_crashlytics: ^6.0.1` dependency.
- **Podfile:** pins Firebase SDK 12.19.0.
- **`.github/workflows/ci-flutter.yml`:** runs on Ubuntu and doesn't depend on Codemagic.
- **Release audit:**
  - Q14: dev and prod share one bundle ID, so the two apps can't be installed side by side.
  - INF-1: a push to `main` still starts a paid prod build.

## 2. Target design

### 2.1 Options compared

| | (a) Local scripts | (b) fastlane | (c) Self-hosted GitHub Actions runner |
|---|---|---|---|
| Moving parts | bash, `flutter`, `xcodebuild`, `xcrun`, `codemagic-cli-tools` | Adds Ruby, Bundler and a Fastfile | Adds a runner service, a workflow, and a trust link between GitHub and the Mac |
| How a build starts | The owner runs a command | The owner runs a command | A push, or a manual start |
| Owner approval for each build | Yes, built in | Yes, built in | Weaker |
| Attack surface | Smallest | Medium (gem supply chain) | Largest |
| Fit for January | **Best** | OK | Poor |

**Recommendation: (a).** Fastlane or a runner can call the same script later, so this closes off nothing. Look at (c) again only after two successful releases, and only as a manual start.

### 2.2 Design decisions

1. **API key:**
   - Create a new App Store Connect key with the App Manager role. Codemagic's `.p8` can't be downloaded again.
   - Store it at `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`, mode 0600.
   - Put the Key ID and Issuer ID in `~/.hylite-release.env`, mode 0600.
   - None of these ever go in the repo, shell history or screenshots.
   - Revoke the Codemagic key after cut-over.
2. **Signing:**
   - Archive with automatic signing.
   - Export with a manual `ExportOptions.plist`: `app-store-connect` method, manual signing style, the team ID, and the profile map.
   - Import the original distribution `.p12` if it still exists. Otherwise create a new certificate and regenerate the profile.
   - *(Unverified)* whether `flutter build ipa` passes `-allowProvisioningUpdates`. If not, the fallback is `flutter build ios --no-codesign`, then `xcodebuild` archive and export.
3. **Build number:** the same rule as today. The script **stops** if a lookup fails, rather than using 0. This is a deliberate hardening; please confirm it.
4. **Dev and prod bundle IDs (Q14 / R3):**
   - Replace the three hard-coded IDs with `$(APP_BUNDLE_ID)`, set in the gitignored `Secrets.xcconfig`. This uses the same mechanism as Google Sign-In.
   - Each environment needs its own App ID, App Store Connect app, profile, Firebase iOS app with its plist, and APNs key. Only the owner can create these.
   - Until R3 is done, the Mac builds dev only.
5. **Crashlytics dSYMs:** the phase runs inside the archive step. Check these on the first archive *(unverified)*:
   - the phase appears in the build log;
   - `ENABLE_USER_SCRIPT_SANDBOXING` doesn't block it;
   - the dSYM shows up in the Firebase console.

   The script keeps the `.xcarchive` and dSYMs for re-upload.
6. **Podfile.lock:** the owner generates it on the Mac after lane B merges, and the orchestrator commits it once approved. This makes builds reproducible and closes release-audit line 170.

### 2.3 Scripts (design only)

`scripts/ios/release-ios.sh <dev|prod> [--upload]` runs with `set -euo pipefail`. Steps:
1. Refuse to run unless the tree is clean and on the right branch (`development` for dev, `main` for prod).
2. Read `~/.hylite-release.env` and the environment's files from `~/hylite-secrets/<env>/`.
3. Copy in the plist and write `Secrets.xcconfig`. Check that `API_BASE_URL` starts with `https://` without printing it.
4. Run `flutter pub get`, `pod install`, `flutter analyze`, `flutter test` and the version check.
5. Work out the build number.
6. Run `flutter build ipa --release --dart-define-from-file=secrets.local.json --build-number=$BUILD --export-options-plist=…`.
7. Check the IPA exists. Print only its bundle ID, version and build number.
8. Keep the IPA, `.xcarchive`, dSYMs and logs in `~/hylite-releases/<env>/<version>+<build>/`.
9. With `--upload`, upload with `xcrun altool --upload-app … --apiKey … --apiIssuer …`. *(Unverified)* whether altool still supports this; the fallbacks are `app-store-connect publish` or Transporter.
10. Make a local tag `ios-<env>-<version>+<build>`. Pushing the tag needs the owner's approval.

`scripts/ios/mac-doctor.sh` checks the setup and prints what it finds:
- the Flutter version pin;
- Xcode;
- CocoaPods;
- the key file's permissions;
- that the secret files exist (presence only, never their contents);
- the signing certificate and profile.

## 3. Owner checklist for 2026-11-27

**[OWNER ONLY]** marks steps that involve credentials, Apple accounts, sign-ins or secret files.

### A. Mac
1. **[OWNER ONLY]** Update macOS to a version the latest Xcode supports, then reboot.
2. **[OWNER ONLY]** Create a standard user for builds (for example `hylitebuild`). Turn on FileVault (see Q-C) and the firewall.
3. **[OWNER ONLY]** Turn on SSH or Screen Sharing only if you want them, for your user only. Set the Mac never to sleep on power.
4. **[OWNER ONLY]** Sign in to Xcode (Settings, Accounts) with the Apple Developer account.

### B. Toolchain
5. **[OWNER ONLY]** Install Xcode:
   - Open it once and accept the licence.
   - Add the iOS platform and the simulator.
   - Run `sudo xcodebuild -runFirstLaunch`.
6. Install Homebrew, then `brew install cocoapods node pnpm git pipx`. Note the versions.
7. Install Flutter at **3.41.2** exactly (`git checkout 3.41.2`), add it to your PATH, and don't upgrade it. Check with `flutter --version` and `flutter doctor -v`.
8. Run `pipx install codemagic-cli-tools`, then `app-store-connect --help`.
9. Clone the repo and check out `development`. Don't push from the Mac without approval.

### C. Certificates, profile and key
10. **[OWNER ONLY]** Apple Distribution certificate: import the saved `.p12`, or create a new certificate in Xcode → Settings → Accounts → Manage Certificates.
11. **[OWNER ONLY]** Make sure the "Stall 10 App Store" profile includes that certificate; regenerate it if needed. Download and install it.
12. **[OWNER ONLY]** Create the new API key with the App Manager role:
    - Save the `.p8` to `~/.appstoreconnect/private_keys/` and run `chmod 600` on it.
    - Put the Key ID and Issuer ID in `~/.hylite-release.env`, also with `chmod 600`.
13. **[OWNER ONLY]** Put the dev `secrets.local.json` and the dev `GoogleService-Info.plist` in `~/hylite-secrets/dev/`. Copy them over USB or AirDrop. No agent opens them. Prod waits for #9.

### D. First builds
14. Check the setup: `flutter doctor -v`, `pod --version`, `xcodebuild -version`, and `security find-identity -v -p codesigning`, which should list an Apple Distribution identity.
15. In `apps/mobile`:
    - `flutter pub get`
    - `cd ios && pod install --repo-update`
    - `flutter analyze`
    - `flutter test` (the golden tests skip here). Note the counts.
16. **[OWNER ONLY]** Build locally without uploading, and check that `build/ios/ipa/*.ipa` exists.
17. **[OWNER ONLY]** Upload a dev build to TestFlight. Check it finishes processing, then install it on the iPhone.
18. Note the macOS, Xcode, Flutter and CocoaPods versions, the build number and how long it took.
19. Leave Codemagic running for now (see §5).

## 4. Repo changes to prepare after approval

Nothing is written yet. Each change needs approval, and none is pushed without it.

| File | Change |
|---|---|
| `scripts/ios/release-ios.sh`, `scripts/ios/mac-doctor.sh` | New (§2.3) |
| `scripts/ios/ExportOptions.{dev,prod}.plist.template` | New: templates with placeholders |
| `docs/ios-release.md` | The Mac becomes the main route and Codemagic the fallback |
| `.gitignore` | Add guards for `.p8`, `.p12`, `.mobileprovision`, generated `ExportOptions*.plist` and `*.env` |
| `.github/workflows/ci-flutter.yml` | Comment-only change at lines 3-4 |
| `codemagic.yaml` | Make both trigger blocks manual-only at the first Mac release |
| `project.pbxproj` (R3) | Use `$(APP_BUNDLE_ID)`, plus a committed default |
| `ios/Flutter/Secrets.example.xcconfig` | Add an example `APP_BUNDLE_ID` key |
| `ios/Podfile.lock` | Generated on the Mac, then committed once with approval |

## 5. Cut-over and rollback

**Cut-over:**
1. **Nov 27:** the first local archive and a dev TestFlight upload. Codemagic stays unchanged.
2. **First real Mac release:** switch Codemagic's triggers to manual-only. This avoids paid builds and clashing build numbers.
3. Keep Codemagic, its key and its signing setup until **two** Mac releases have installed successfully on a device.
4. Then decide whether to delete `codemagic.yaml` or keep it unused (Q-H).
5. The `main` and prod route stays blocked on #9 and INF-1.

**Rollback:**
- **Bad build:** stop sending it out and ship a new, higher-numbered build from the last good commit.
- **The Mac is unusable:** start Codemagic's dev workflow by hand.
- **Backups:** back up `~/hylite-secrets`, `~/.appstoreconnect` and the `.p12` to an encrypted Time Machine disk.
- **Xcode updates:** keep the previous Xcode installed until the next release succeeds.

## 6. Security

- **Secrets:**
  - They live in the build user's home folder, mode 0600, on a FileVault disk.
  - The signing key stays in the keychain.
  - Scripts never print secrets and never run with `set -x`.
- **Who can start a build:** only someone logged in to the Mac. Option (a) has no remote trigger.
- **If a runner is added later (option c):**
  - a non-admin user;
  - registered to this repository only;
  - started by hand, or by pushes to protected branches only;
  - **never** run for pull requests or forks;
  - a separate keychain;
  - `permissions: contents: read`;
  - pinned actions.
- **FileVault:** after an unattended reboot, the password has to be typed before the Mac starts up (Q-C).
- **Production:** no prod profile, plist or secrets go on the Mac until #9 is done.

## 7. What the Mac also makes possible

- **iOS Simulator:**
  - `flutter run -d <sim> --dart-define-from-file=secrets.local.json`;
  - screen recordings with `xcrun simctl io recordVideo` for the navigation motion review (N13).
  - There are no `integration_test` or Maestro flows in the repo yet (release-audit #29).
- **iPhone over USB:** `flutter run -d <iphone> --dart-define-from-file=secrets.local.json`, with Developer Mode on.
- **These still need the physical device:**
  - push notifications;
  - camera, microphone and photo access;
  - media playback;
  - background behaviour and network changes;
  - LiveKit;
  - Apple and Google sign-in in a release build;
  - Universal Links;
  - the TestFlight test crash for Crashlytics;
  - how navigation feels: frame rate and the back-swipe.
- **Golden tests:** keep them on Windows. A second, macOS set of goldens isn't worth it for January: it doubles the review work, the fonts differ, and it causes false failures.

## 8. Risks

1. **One machine, one person.** Mitigated by the Codemagic fallback and backups.
2. **Apple's minimum Xcode and SDK for uploads.** Check it on the first upload and again before Jan 18 *(unverified)*.
3. **Flutter 3.41.2 with the latest Xcode** *(unverified)*. The fallback is the previous Xcode.
4. **A missing `.p12`** means a new certificate and a new profile.
5. **Upload support in altool** may have changed *(unverified)*. Fallbacks are listed in §2.3.
6. **Script sandboxing** may block the Crashlytics phase *(unverified)*.
7. **Build-number clashes** with Codemagic, until its triggers are switched off.
8. **Prod** is blocked by INF-1 and #9.
9. **No `Podfile.lock`**, so pod versions can drift.
10. **Owner time:** this has to fit alongside R2, R3 and 9-P.

## 9. Out of scope

Hosting the website or the API on your own hardware would bring public IP or tunnel setup, TLS, uptime, backups and scaling. That works against January's reliability and security priorities. If you want it, plan it as its own task after the beta.

## Decisions for the owner

| # | Decision | Recommendation |
|---|---|---|
| Q-A | Which environment keeps `com.brianrhonea.frisbeeApp` | Dev keeps it; prod gets a new ID |
| Q-B | Option (a): local scripts plus `codemagic-cli-tools` | Yes; fastlane only as a fallback |
| Q-C | FileVault on a Mac that runs on its own | On, and type the password after reboots |
| Q-D | Does the original distribution `.p12` still exist? | Owner to answer |
| Q-E | A new API key for the Mac, and revoking Codemagic's after cut-over | Yes |
| Q-F | Where release logs and archives live | `~/hylite-releases/`, plus a backup |
| Q-G | Codemagic manual-only from the first Mac release | Yes |
| Q-H | After two Mac releases: delete `codemagic.yaml`, or keep it unused | Decide then |
| Q-I | Commit a `Podfile.lock` generated on the Mac | Yes |
| Q-J | Golden tests stay on Windows | Yes |
| Q-K | The Mac mini's model and macOS version (they decide which Xcode it can run) | Owner to answer |
| Q-L | The beta runs on dev only until #9 | Yes |
| Q-M | A self-hosted runner and moving off Vercel or Cloud Run are later decisions | Yes |
