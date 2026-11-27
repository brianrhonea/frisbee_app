# Releasing the iOS app

Main route: build on the owner's Mac mini with `scripts/ios/` (next section).
Fallback: Codemagic, described from "Fallback: Codemagic" on. Keep Codemagic
until two Mac releases have installed on a device (plan Q-H, Q-G).

## Building on the Mac mini (main route)

Plan: `docs/specifications/mac-mini-build-plan.md` (owner approved 2026-11-26).
Per-build checklist: `docs/specifications/release-checklist-ios.md`.

One-time setup is plan section 3 (Mac, toolchain, certificate, profile, API
key, secret files). Then, from the repo root on the Mac:

1. `scripts/ios/mac-doctor.sh` prints an OK / FIX list: Xcode, Flutter 3.41.2,
   CocoaPods, Node, pnpm, codemagic-cli-tools, the Apple Distribution
   identity, key and secret-file presence and modes, energy settings.
2. Copy `scripts/ios/release.env.example` to `~/.hylite-release.env`, fill it
   in, `chmod 600` it. It holds the API key ID, issuer ID, key path and Team
   ID. The `.p8` key goes in `~/.appstoreconnect/private_keys/`, mode 600.
3. Put `secrets.local.json` and `GoogleService-Info.plist` in
   `~/hylite-secrets/dev/` (the owner copies them; nobody opens them).
4. `scripts/ios/release-ios.sh dev --dry-run` shows every step without running
   Flutter or touching Apple.
5. `scripts/ios/release-ios.sh dev` builds, checks and keeps the build in
   `~/hylite-releases/dev/<version>+<build>/`. Add `--upload` to send it to
   App Store Connect with `xcrun altool`. `--ref <sha|tag>` rebuilds an
   earlier commit on `development`.

What the script does: requires a clean tree on `development`, checks Flutter is
exactly 3.41.2, runs `pub get`, `pod install`, `flutter analyze`, `flutter test`
and the version check, takes the build number as the higher of the latest App
Store and TestFlight numbers plus 1 (it stops if a lookup fails), builds with
`--dart-define-from-file=secrets.local.json`, reads the bundle ID, version and
build from the IPA, makes a local tag `ios-dev-<version>+<build>` (never
pushed), and removes the copied secret files when it exits.

Limits until the owner changes them:
- **Prod is refused** (`HYLITE_PROD_READY=1` is required) until #9 and R3.
  Dev and prod share one bundle ID today (release-audit Q14).
- **Golden tests skip on the Mac.** Run them on Windows before UI approval.
- Pushing the tag, `development` or `main` needs the owner each time.
- At the first Mac release, make Codemagic's triggers manual-only
  (`codemagic.yaml`; waiting for that release) so pushes stop costing money
  and build numbers don't clash.
- Rollback: ship a new, higher build from the last good commit
  (`--ref <tag>`), or start Codemagic's dev workflow by hand.

---

# Fallback: Codemagic (no Mac needed)

Everything below is the original Codemagic route, kept as the fallback.

`codemagic.yaml` builds the app on a cloud Mac, signs it, and uploads it to
TestFlight. These are the one-time setup steps, in order.

The app lives in `apps/mobile` (monorepo; see `ARCHITECTURE.md`). Paths
below such as `ios/Runner/...` and `secrets.local.json` are relative to
`apps/mobile`; Codemagic runs every script there (`working_directory`).
Pushes that change nothing under `apps/mobile/` or `packages/` skip the
build.

## 1. Apple Developer Program

1. Enroll at <https://developer.apple.com/programs/enroll/> ($99/year).
   Approval can take a day or two.
2. In **Certificates, Identifiers & Profiles → Identifiers**, register the
   App ID `com.brianrhonea.frisbeeApp` and tick **Sign in with Apple** and
   **Push Notifications**. If the App ID already exists, edit it to add Push
   Notifications; `ios/Runner/Runner.entitlements` asks for it, so signing
   fails until the App ID has it. Make the App Store provisioning profile
   (step 3.3) after this, so it includes push.
3. In **App Store Connect → Apps → +**, create the app with that bundle ID.
   Copy its numeric **Apple ID** (App Information) into `APP_STORE_APPLE_ID`
   in `codemagic.yaml`. It's an identifier, not a secret.

## 2. Firebase iOS app

1. Firebase console → Project settings → **Add app → iOS**, bundle ID
   `com.brianrhonea.frisbeeApp` (skip if it exists already).
2. **Authentication → Sign-in method**: enable **Apple** and **Google**.
   Enable Google *before* downloading the plist, or it has no `CLIENT_ID`.
3. Download `GoogleService-Info.plist`. Keep it out of git; it goes into
   Codemagic in step 3.
4. **Push notifications**: in Apple Developer → **Keys → +**, create a key
   with **Apple Push Notifications service (APNs)** and download the `.p8`
   (you can only download it once). In Firebase → Project settings →
   **Cloud Messaging → Apple app configuration**, upload it with its Key ID
   and your Team ID. Keep the `.p8` out of git, like every other key.

## 3. Codemagic

1. Sign up at <https://codemagic.io> with GitHub and add this repository.
   Codemagic then reads `codemagic.yaml` from the repo.
2. **Team settings → Integrations → Developer Portal**: add an App Store
   Connect API key named exactly **Frisbee App Store Connect**.
   Create the key in App Store Connect → Users and Access → Integrations
   → App Store Connect API (role: App Manager). Upload the `.p8` file only
   to Codemagic, never to the repo.
3. **Signing** (Codemagic finds these by bundle ID; it doesn't create
   them, and the build fails with "No matching profiles found" until they
   exist):
   1. Codemagic → **Team settings → codemagic.yaml settings → Code signing
      identities → iOS certificates → Generate certificate**: type
      **Apple Distribution**, with the Frisbee App Store Connect key.
      Codemagic keeps it (download the `.p12` and its password somewhere
      safe, never the repo).
   2. Apple Developer → **Profiles → +** → **App Store Connect** (under
      Distribution) → App ID `com.brianrhonea.frisbeeApp` → that
      certificate → name it `Stall 10 App Store` → **Generate**. Turn on
      the App ID's capabilities (step 1) first; changing them later makes
      the profile invalid, so edit and regenerate it.
   3. Codemagic → **iOS provisioning profiles → Fetch profiles** → pick
      `Stall 10 App Store` → **Download selected**.
4. **App → Environment variables**: create two groups, each with two
   **Secure** variables (base64-encode each file in PowerShell):

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("secrets.local.json")) | Set-Clipboard
   ```

   | Group | `SECRETS_LOCAL_JSON` | `GOOGLE_SERVICE_INFO_PLIST` |
   |---|---|---|
   | `frisbee_secrets_dev` | `secrets.local.json` | `GoogleService-Info.dev.plist` |
   | `frisbee_secrets` (production) | `secrets.prod.local.json` | `GoogleService-Info.plist` |

   Each secrets file has `FIREBASE_ENV` set (`dev` or `prod`); a build
   without it stops at launch.

5. Push to `development` (or start the **iOS TestFlight (dev)** workflow by
   hand): it runs `flutter analyze` and `flutter test`, builds against the
   dev Firebase project with the next build number, and uploads to
   TestFlight. Merging to `main` runs **iOS App Store (production)**, which
   builds against production and submits for App Store review; release it
   by hand in App Store Connect once Apple approves.

### Invite links (Universal Links)

Invite links (`https://stall10.app/join/<code>`; `dev.stall10.app` in
dev builds, and the old `frisbee-app-brianrhonea.web.app` for links shared
before 0.0.20) open the app on Android already. On iPhone they open the web page until these
are done; the page's **Open in Stall 10** button works meanwhile, through
the app's `stall10://` scheme.

1. In the Apple Developer portal, open the App ID
   `com.brianrhonea.frisbeeApp` and turn on **Associated Domains**. Then
   edit the App Store profile so it's valid again (Profiles → Stall 10
   App Store → Edit → Save) and fetch it again in Codemagic.
2. Add to `ios/Runner/Runner.entitlements`:

   ```xml
   <key>com.apple.developer.associated-domains</key>
   <array>
     <string>applinks:stall10.app</string>
     <string>applinks:dev.stall10.app</string>
   </array>
   ```

   Do step 1 first: a build with this entitlement fails to sign until the
   App ID has the capability.
3. `apps/web/public/.well-known/apple-app-site-association` names Team ID
   `UR7V8Z48NR` (developer.apple.com > Membership); the website serves it
   on both domains.

Android verifies links with `hosting/.well-known/assetlinks.json`, which
lists the signing key's SHA-256. It holds the debug key's for now (release
builds are signed with it too); add the release key's when there is one.

## 4. Before submitting for review

- **Version**: bump `version:` in `pubspec.yaml` (e.g. `1.0.0`) for each
  App Store release. Codemagic sets the build number itself.
- **App icon**: replace the default Flutter icon in
  `ios/Runner/Assets.xcassets/AppIcon.appiconset` (1024×1024, no transparency).
- **Store listing**: screenshots (6.7" and 6.5" iPhone; iPad as well, since
  the app supports iPad), description, keywords, support URL, and a
  **privacy policy URL** (required, because the app has accounts).
- **App Privacy** questionnaire: declare account data (name, email) used for
  app functionality, plus anything Firebase collects.
- **Review notes**: give reviewers a demo email/password account; they
  can't use your Google or Apple login.
