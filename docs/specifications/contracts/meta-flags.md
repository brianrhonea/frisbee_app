# Contract: `meta/flags` (Sprint 2, Q19)

Status: approved by the product owner (Q19). Types and defaults:
`packages/shared/src/meta_flags.ts` (`MetaFlags`, `metaFlagDefaults`,
`parseMetaFlags`, `isBuildAllowed`).

## Where it lives

Firestore document `meta/flags`, the same document the app already reads for
its kill switches (`use_api_*`, `compress_images`; `feature_flags.dart`). Those
keys are untouched. The two new fields sit beside them.

## Fields

| Field | Type | Default | Meaning |
|---|---|---|---|
| `minBuild` | map `{ ios: number, android: number }` | `{ ios: 0, android: 0 }` | Lowest app build number (the `+N` in `pubspec.yaml`, shown by the OS as the build) allowed to run. `0` means no gate. Whole numbers `>= 0`. |
| `videoUploads` | boolean | `false` | Native video upload is open. Only literal `true` opens it. |

A missing, mistyped (string, negative, fractional) or unreadable value takes
the default **per field** (`parseMetaFlags`). A console typo therefore can never
lock anyone out or open video uploads.

### Why there is no web version gate

The website ships as one atomic deploy, so every page load is the current
build; there is no installed old copy to retire. An open stale tab is covered
by the API's own versioning (`x-stall10-api-version`) and a reload. A `minWeb`
field would only add a way to break the site, so none is defined. If the owner
later wants one, it is a new contract change.

## Read path

- Clients read `meta/flags` directly from Firestore (live snapshot or one get).
- Rules (`firebase/firestore.rules`): **anyone may read `meta/flags`, signed out
  too**, because the build gate must run before sign-in. It holds no personal
  data. The other `meta/*` documents (e.g. `meta/health`) stay signed-in only.
- **No client can write it** (no `write` rule; creates, updates and deletes are
  all denied). Only the Firebase console or the Admin SDK changes it.
- The API reads it with the Admin SDK on each video upload request (see below).

## Fail-open / fail-closed

| Field | If the flags can't be read (offline, timeout, permission error, missing document, bad value) |
|---|---|
| `minBuild` | **Fail OPEN.** The client treats the build as allowed (`isBuildAllowed(null, ...)` is `true`). An outage must never lock everyone out. |
| `videoUploads` | **Fail CLOSED.** Treated as `false`. Video upload stays off until the flag is read as `true`. |

Clients use a short timeout (suggest 3 s) on the first read and must not block
app start on it beyond that: show the app, and apply the gate when the value
arrives. A client that cannot read the flags never shows the update screen.

## How the owner sets them (Firebase console, Firestore, `meta/flags`)

- Force an update: set `minBuild.ios` / `minBuild.android` (a map field) to the
  lowest build number still allowed. Set it back to `0` to lift the gate. Do
  this only after the fixed build is available in TestFlight / the store.
- Open video upload: set `videoUploads` to boolean `true`. Set `false` (or
  delete the field) to close it again.
- Dev and prod have separate documents; setting one does not touch the other.

## What the server enforces for `videoUploads`

When `videoUploads` is not `true`:

- `storage.rules`: a direct upload of a video is refused in team videos
  (`teams/{t}/videos/...`), team chat attachments and DM/group attachments. A
  file counts as a video if its content type is a video type **or** its name
  ends in a video extension (`.mp4 .mov .m4v .webm .3gp`). The rule reads
  `meta/flags`; a missing document means closed.
- API `POST /v1/uploads` (and `complete`): video purposes and chat videos are
  refused with 412 `failed_precondition` ("Video uploads aren't available
  right now."). Photos and documents are unaffected. Existing videos still play.
- Signed upload URLs last 15 minutes (`urlLifetimeMs`). Nothing in the API
  signs a playback URL; playback uses Firebase download tokens, which are not
  time-limited (see the #13 note in the completion report).

## What each client must do

**App (Flutter, `apps/mobile`)**
1. Read `meta/flags` before sign-in (short timeout; no auth needed).
2. If `build < minBuild[platform]`, show a blocking "Update required" screen
   with a store link. Otherwise carry on. Any read failure: carry on.
3. Hide or disable the video picker / "add video" entry points unless
   `videoUploads == true`. Treat read failure as `false`.
4. Follow changes live; re-check on app resume.

**Website (`apps/web`)**
1. No `minBuild` handling (there is none for web).
2. Hide or disable video upload controls unless `videoUploads == true`
   (read failure is `false`). Parity with the app (same flag, same rule).

Client checks are convenience only; storage rules and the API are the
enforcement.

## Tests

- `packages/shared/test/meta_flags.test.ts` (parsing, defaults, fail-open).
- `firebase/functions/test/rules/firestore.rules.test.ts`, "meta": signed-out read
  of `meta/flags`, other `meta` docs private, no client writes.
