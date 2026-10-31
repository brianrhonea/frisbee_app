# Releasing the iOS app (Codemagic, no Mac needed)

`codemagic.yaml` builds the app on a cloud Mac, signs it, and uploads it to
TestFlight. These are the one-time setup steps, in order.

## 1. Apple Developer Program

1. Enroll at <https://developer.apple.com/programs/enroll/> ($99/year).
   Approval can take a day or two.
2. In **Certificates, Identifiers & Profiles → Identifiers**, register the
   App ID `com.brianrhonea.frisbeeApp` and tick **Sign in with Apple** and
   **Push Notifications**. If the App ID already exists, edit it to add Push
   Notifications; `ios/Runner/Runner.entitlements` asks for it, so signing
   fails until the App ID has it. Delete any old App Store provisioning
   profile for the app so Codemagic makes a new one that includes push.
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
3. **App → Environment variables**: create group **`frisbee_secrets`** with
   two **Secure** variables (base64-encode each file in PowerShell):

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("secrets.local.json")) | Set-Clipboard
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("GoogleService-Info.plist")) | Set-Clipboard
   ```

   | Variable | Value |
   |---|---|
   | `SECRETS_LOCAL_JSON` | base64 of `secrets.local.json` |
   | `GOOGLE_SERVICE_INFO_PLIST` | base64 of `GoogleService-Info.plist` |

4. Start the **iOS release (TestFlight)** workflow by hand. It runs
   `flutter analyze` and `flutter test`, builds with the next build number,
   and uploads to TestFlight.

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
- **USA Ultimate content**: the app shows data from play.usaultimate.org.
  Apple can reject apps that use another organisation's content without
  permission (guideline 5.2). Written permission from USA Ultimate is the
  safest path; mention it in the review notes if you have it.
