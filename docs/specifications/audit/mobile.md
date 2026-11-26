# Mobile (Flutter) audit — `apps/mobile` at 39c8a53

Read-only audit, 2026-11-25. Evidence comes from reading code and grep. I didn't run any tests; the owner's run today gave flutter test 1,522 pass / 68 skipped, and analyze was clean. **The 68 skips are the opt-in screenshot tests** (`test/screenshots/*`, skipped unless `--dart-define=SCREENSHOTS`). There are no golden tests (no `matchesGoldenFile`) and no `integration_test/` folder. The app has 446 Dart files and about 134k lines.

## Corrections to the prior assessment

1. **The hardcoded colour count is wrong (C-35, U2).** Of the "about 619" uses, 492 are `AppColors.of(context)`, which reads the theme tokens. The real literals are 29 `Color(0x…)` (9 are the user-pickable calendar palette in `domain/models/calendar.dart`, 9 are in `disc_throw_hero.dart`), 1 `Color.fromARGB`, and 74 `Colors.white/black/transparent`, mostly painter overlays. U2 drops from about 10 h to about 3 h.
2. **Support link and blocked list already exist.** "Contact support" (support@stall10.app) is in `ui/learn/widgets/guide_screens.dart:11,125`, and `ui/moderation/widgets/blocked_accounts_screen.dart` exists. F5 shrinks to adding the link in Settings with the app version; F11 is done.
3. **Search.** `use_api_search` defaults to **false** (`data/services/feature_flags.dart:22`). Unless `meta/flags` turns it on, DM and people search query Firestore `profiles` keywords directly (`direct_message_repository_firebase.dart:134`). Readiness row 9 says the app uses the callable, which is true only when the flag is on.
4. **The roster bypasses the API flags.** `savePlayer`, `linkPlayer` and `deletePlayer` (`team_repository_firebase.dart:1105–1165`) always write Firestore. Removing the `use_api_*` fallbacks (S4) won't close them.
5. **Self-reported team history, not only rankings (C-39).** `publishSummary` (`profile_repository_firebase.dart:286–305`) writes the player's own `teams`, `stats`, `teamStats` and `games` to their public profile. `firestore.rules:2664–2672` checks only types and sizes. The U4 "team history" card would show this unverified data.

## Readiness table

V = I checked the code. C = carried over from `readiness-assessment.md`, not re-verified.

| Area | State | Basis | Notes |
|---|---|---|---|
| Auth / onboarding | Fix | V | Sign-up writes `users` and `profiles` directly (`auth_repository_firebase.dart:163–187`, 229) even with `use_api_profiles` on. Minimum age is 13 (`personal_details.dart:8`). No email-verified check. Onboarding sign-outs leak the push device (M-B1). |
| Profiles | Fix | V | `setHeader` and `publishSummary` write directly; other writes are API with fallback. |
| Feed / posts / comments | Fix | C, partly V | 11 + 4 direct writes. Server text filter is a backstop (`text_filter.ts`). |
| Teams / roster / roles | Fix | V | 27 methods are API with direct fallback. Roster writes and two client-side data migrations are direct (M-B5). |
| Communities / hat / drafts | Ready | V | Draft start, pick and finish are server callables (`hosted_tournament_repository_firebase.dart:866–915`). Division and team saves are direct. |
| Chat / DMs | Fix | V | Direct sends. Sends are idempotent: the id is picked once and the outbox retries under it (`chat_repository_firebase.dart:366`). `authorName` can be spoofed (M-B3). |
| Voice / meetings | Fix | V | LiveKit lifecycle is guarded. No microphone foreground service on Android (M-B7). |
| Schedule / RSVP | Ready | V | RSVPs use field-path updates (no clobbering). Series are capped at 100 (200 batch ops). Deleting a series takes two non-atomic batches. |
| Discover / search | Fix | V | See correction 3. Player rankings come from self-written data (`explore_viewmodel.dart:89`). |
| Tournaments / leagues | Fix | V | 42 write lines. Status, entries and publishing use the API with fallback; `saveTournament`, divisions, `reportScore`, `savePayment` and the host team are direct-only. |
| Payments UI | Off at launch | V | Pay shows only when the server says `online` (`payments_viewmodels.dart:135`). The payouts WebView is pinned to `https://<host>/embed/payouts` (`payouts_setup_screen.dart:97–121`), which is good. |
| Notifications | Fix | V | See M-B1 and M-B2. No crash or error reporting hook (no `FlutterError.onError` or `PlatformDispatcher.onError`). |
| Moderation | Ready | C, partly V | Report sheet, blocked list and team reports screens exist. |
| Stats tracker | Fix | V | Local copy always wins (M-B4). A save counts as done after 5 s even if the server hasn't confirmed it (`stats_repository_firebase.dart:98,100`). |
| Playbook / video | Fix | V | Native upload goes straight to Storage (`video_repository_firebase.dart:105–110`, up to 500 MB, admins only per `storage.rules:148–155`). Download-URL links are bearer tokens (M-B6). |
| Settings / deletion / export | Ready | V | Deletion re-authenticates, then calls the function. Export calls `GET /v1/me/export` with a 90 s timeout. |
| Release gating | Gate | V | No minimum-version check anywhere (grep for min build / update required finds nothing). Codemagic stops the build if `API_BASE_URL` is missing (`codemagic.yaml:72–75`). |

## Bugs and incomplete workflows

| ID | Sev | Status | file:line | Scenario |
|---|---|---|---|---|
| M-B1 | P1 | CONFIRMED | `ui/auth/view_models/agree_terms_viewmodel.dart:16`, `choose_username_viewmodel.dart:39`, `personal_details_viewmodel.dart:21,85`; registration at `main.dart:148` | `_onAuth` registers the device for any signed-in uid. Only Profile's sign-out unregisters it (`profile_viewmodel.dart:42–44`). If A signs out from the terms, username or personal-details screen with OS push already allowed, `users/A/devices/{fid}` stays. B then signs in on the same phone, the FID is unchanged, and `_saveDevice` doesn't delete A's doc (`notification_repository_firebase.dart:279–288`). `deliver.ts:107–139` prunes only dead tokens, so A's DM previews reach B's screen. |
| M-B2 | P2 | CONFIRMED (Firestore semantics) | `notification_repository_firebase.dart:300–308`, `profile_viewmodel.dart:206–219` | Sign-out waits for `devices/{fid}.delete()` before signing out. Offline, that wait doesn't finish until the server answers, so the button spins and sign-out stalls. If deleting the account then fails, push stays unregistered until the uid changes. |
| M-B3 | P2 | CONFIRMED | `firestore.rules:1641–1645` (messages; also 229–232, 1272–1274, 1327–1330, 1388–1390) | `authorName` is checked only by `validString(…, 80)`. A user writing straight to Firestore can post team chat as "Coach Sarah". The client sets it from `author.label` (`chat_repository_firebase.dart:418`). |
| M-B4 | P2 | CONFIRMED | `ui/stats/view_models/game_tracker_viewmodel.dart:55–64`, `stats_repository_firebase.dart:93–98` | The tracker loads the game once and ignores later snapshots. Each save is a whole-document `set`. A second recorder's edits are silently overwritten, and a game deleted on another device comes back on the next tap. |
| M-B5 | P2 | CONFIRMED | `team_repository_firebase.dart:839–888` (`migrateTiersToRoles`), `1073–1098` (`_moveLegacyStatus`) | Data migrations run on the client in several steps that aren't atomic. If step 1 commits and step 3 fails, roles exist but members stay on the old tiers. The legacy-status move runs whenever an admin views the roster. CLAUDE.md asks for approval of migrations. |
| M-B6 | P2 | CONFIRMED (by design) | `video_repository_firebase.dart:131–132` | `getDownloadURL()` returns a link with a token that skips `storage.rules` `get`. A removed member, or anyone the link is forwarded to, can keep streaming team film. |
| M-B7 | P2 | SUSPECTED (device) | `android/app/src/main/AndroidManifest.xml:12–13,82`; merged release manifest has only `mediaProjection` and `location` foreground services | There's no `FOREGROUND_SERVICE_MICROPHONE` service, and `FlutterBackground` starts only for screen share (`meeting_call_livekit.dart:285–303`). On Android 14+, the mic likely goes silent when a voice room or meeting is in the background or the screen locks. The iOS `UIBackgroundModes` couldn't be checked (Info.plist is off-limits). |
| M-B8 | P2 | CONFIRMED | `ios/Runner/Runner.entitlements` (only `aps-environment` and Sign in with Apple) | No `associated-domains` entitlement, so `https://stall10.app/join/<code>` opens Safari on iPhone. It's documented as pending in `docs/ios-release.md:88–110`, with the "Open in Stall 10" button as a workaround. Beta team invites will feel broken. |
| M-B9 | P3 | CONFIRMED (debug only) | Example: `ui/calendar/view_models/calendars_viewmodel.dart:23,67–75`; same pattern in `payments_viewmodels.dart:21,50` and about 30 more | A view model calls `notifyListeners()` after an `await` with no disposed guard. `Command` guards itself (`utils/command.dart:47–56`), but the action inside doesn't. Closing the screen during a load trips the debug "used after disposed" assert as an unhandled async error. In release it does nothing. |
| M-B10 | P3 | SUSPECTED | `payments_viewmodels.dart:178–181` | After the payment sheet finishes, `load.execute()` does nothing if a load is already running. `_awaitingReturn` stays true and the old options can still show. |
| M-B11 | P3 | CONFIRMED | `notification_repository_firebase.dart:272–275` | `registrations.listen((fid) => _saveDevice(...))` drops the returned future. A failed write becomes an uncaught zone error with nothing logging it. |
| M-B12 | P3 | SUSPECTED | `game_tracker_viewmodel.dart:759–761` with `game_screen.dart:130–139` | `dispose()` flushes a pending debounced save (3 s window). If the delete finishes inside that window, the flush `set` brings the deleted game back. |
| M-B13 | P3 | CONFIRMED | `domain/models/play.dart:71,93` | `map['id'] as String` with no fallback. One malformed element written by the website or an older build throws while parsing the play. |
| M-B14 | P3 | CONFIRMED | `main.dart:66–68` | `Firebase.initializeApp` and `AppCheck` run before `runApp` with no error handling. A startup failure gives a blank screen and nothing is reported. |

Checked, nothing found: no TODO, FIXME or `UnimplementedError` in `lib/`. Stream subscriptions are cancelled in every view model I sampled (lists cancelled in `dispose`). No dead `onPressed: () {}` buttons. Not-found and error states exist on every detail screen. There are 222 `onError` handlers for 200 `.listen` calls in `ui/`. Widgets never import Firestore (MVVM boundary holds).

## Direct writes

Method: grep `.set( .update( .add( .delete( runTransaction batch() putFile putData` across `data/repositories`. That gives 373 raw lines, or 359 after excluding `*_api.dart`. Removing `List.add`, stream `sink.add`, `FieldValue.delete()` inside maps and local-only stores leaves **about 291 Firestore write call lines** (each batch op counted).

| Repository | Lines | API path behind a flag? |
|---|---|---|
| team | 69 | 27 methods use API with direct fallback (`use_api_teams` and `use_api_membership`, default true). Roster CRUD and the 2 migrations are direct-only. |
| hosted_tournament | 42 | About 9 methods use the API under `use_api_tournaments`. Tournament, divisions, scores, payments and host team are direct-only. Draft runs on callables. |
| direct_message | 23 | No flag, direct |
| chat | 22 | Direct. Pins, polls and event cards are API-only. |
| event (team + My calendar) | 19 | Direct (calendar sharing is API) |
| profile | 16 | 3 methods under `use_api_profiles`. `setHeader` and `publishSummary` are direct. |
| group_tournament | 16 | Direct |
| meeting | 15 | Direct (tokens come from the API) |
| video | 15 | Direct, plus Storage `putFile` |
| user_post 11, notification 9, follow 9, auth 7 (1 behind a flag), team_post 4, stats 4, post_comment 4, discord 4, playbook 2 | 54 | Direct |

Storage uploads: `video_repository_firebase.dart:107` (`putFile`) and `data/services/attachment_storage.dart:30,68` (`putData`, for chat, DM and post photos). `outbox_store.putFile` writes to local disk, not Storage.

Flag hazard: every `use_api_*` flag is also a kill switch. Setting one to false in `meta/flags` sends writes straight to Firestore, so the rules for those paths can't be locked down while the fallback exists.

## Tech debt

- **15 largest files:** hosted_tournament_screen 3,010; team_home_screen 2,820; message_thread_view 2,585; game_screen 1,990; domain/hosted_tournament 1,661; profile_screen 1,642; hosted_tournament_viewmodel 1,618; router 1,243; team_repository_firebase 1,204; chat_tab 1,181; inbox_screen 1,148; domain/chat 1,145; hosted_tournament_form_screen 1,126; event_editor_screen 1,083; post_widgets 1,048.
- **Strings:** 758 `Text('…')` literals and no l10n (`.arb`). Fine for an English-only launch.
- **Dialogs:** 49 raw `AlertDialog`s beside the `confirm_dialog.dart` helper, which is inconsistent. Duplicated private widgets are rare (`_Heading` ×5, `_InviteCard` ×3).
- **State patterns:** consistent. Provider, ChangeNotifier and `Command`; 3 `FutureBuilder`s, no `StreamBuilder`, 61 widget files with local `setState`. No deprecated APIs found (`withOpacity`, `WillPopScope`, `MaterialState`, `textScaleFactor` all at 0); 1 lint ignore.
- **Accessibility signals:** 52 `Semantics` and 182 tooltips. Not audited.
- **Pinned dependencies to watch:** `flutter_webrtc 1.6.3`, `add_2_calendar 3.0.1`, `permission_handler 12.0.1`, `flutter_stripe 14.2.0`, `webview_flutter 4.14.1`.

## Device-only validation

- **Push (FCM):** the iOS APNs token wait (15 s) and FID registration (`push_service.dart:90–143`); iOS foreground banners are suppressed on purpose; the cold-start route (`getInitialMessage`); notification clearing through a native channel (`stall10/notifications`). Test sign-out and switching accounts on one phone (M-B1). Android 13+ `POST_NOTIFICATIONS` is present in the merged manifest.
- **Camera, mic, photos:** `permission_handler` (`device_permissions.dart`). Android uses the photo picker with no library permission. Check limited-photo access on iOS.
- **Background:** GPS workouts (location foreground service plus iOS `allowBackgroundLocationUpdates`, `location_service.dart:73–91`); meeting and voice audio when the screen locks (M-B7); screen share (mediaProjection).
- **Payments:** the Stripe PaymentSheet and the payouts WebView (off at launch, but they're in the build).
- **Links:** Android App Links autoVerify for stall10.app, dev.stall10.app and the legacy host; iOS universal links are missing (M-B8).
- **Not verifiable under the audit rules:** iOS `Info.plist` usage strings and background modes.

## Suggested issues

| Title | Pri | Est (h) |
|---|---|---|
| Unregister the push device on every sign-out path, and delete other users' docs for the same FID when registering (M-B1, M-B11) | P1 | 3 |
| Sign out without waiting for the device delete; fire it and log failures (M-B2) | P2 | 1 |
| Rules: `authorName` must equal `profiles/{uid}.name`, or the server fills it in (M-B3) | P1 | 3 |
| Minimum-version gate from `meta/flags` with an "Update required" screen (S5) | P0 | 3 |
| Crash and error reporting: `FlutterError.onError`, `PlatformDispatcher.onError`, wrap startup in `main.dart` (M-B14, R3) | P0 | 3 |
| Stats tracker: show remote changes and stop on remote delete; one recorder per game (M-B4, M-B12, R6) | P1 | 6 |
| Move roster CRUD to the API, or decide it's phase 2 (correction 4) | P1 | 4 |
| Move `migrateTiersToRoles` and `_moveLegacyStatus` server-side or retire them after a one-time backfill (M-B5; needs approval) | P2 | 4 |
| Profile summary: hide public team history and stats, or derive them on the server (correction 5, C-39) | P1 | 3 |
| Native video upload behind a server flag; signed short-lived URLs (F8, M-B6) | P0 | 3 |
| Android meeting audio in the background: microphone foreground service, device test (M-B7) | P2 | 4 |
| iOS Associated Domains entitlement and App ID capability (M-B8) | P2 | 1 |
| Shared disposed-guard mixin for view models (M-B9) | P3 | 2 |
| Re-estimate U2 colour clean-up to about 3 h (correction 1) | P2 | 3 |
| Contact support in Settings with the app version (F5 remainder) | P1 | 1 |
