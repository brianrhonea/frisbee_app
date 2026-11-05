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

Invite links (`https://frisbee-app-brianrhonea.web.app/join/<code>`) open
the app on Android already. On iPhone they open the web page until these
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
     <string>applinks:frisbee-app-brianrhonea.web.app</string>
   </array>
   ```

   Do step 1 first: a build with this entitlement fails to sign until the
   App ID has the capability.
3. `hosting/.well-known/apple-app-site-association` names Team ID
   `UR7V8Z48NR` (developer.apple.com > Membership). Deploy it with
   `firebase deploy --only hosting`.

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
- **USA Ultimate content**: the app shows data from play.usaultimate.org.
  Apple can reject apps that use another organisation's content without
  permission (guideline 5.2). Written permission from USA Ultimate is the
  safest path; mention it in the review notes if you have it.
