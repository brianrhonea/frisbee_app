#!/usr/bin/env bash
# Build (and optionally upload) a Hylite iOS release on the Mac mini.
# Plan: docs/specifications/mac-mini-build-plan.md section 2.3.
#
#   scripts/ios/release-ios.sh <dev|prod> [--upload] [--ref <sha|tag>] [--dry-run]
#
# Never prints secret values and never runs with `set -x`. Reads the secret
# files only to copy them (and PlistBuddy reads two IDs from the plist into
# Secrets.xcconfig, as codemagic.yaml does). Pushes nothing.
set -euo pipefail

FLUTTER_PIN="3.41.2"
DEV_APPLE_ID_DEFAULT="6830314904"          # codemagic.yaml:49 (an identifier)
DEV_BUNDLE_DEFAULT="com.brianrhonea.frisbeeApp"
DEV_PROFILE_DEFAULT="Stall 10 App Store"

usage() {
  cat <<'EOF'
Usage: scripts/ios/release-ios.sh <dev|prod> [--upload] [--ref <sha|tag>] [--dry-run]

  dev | prod     environment; dev must be on `development`, prod on `main`
  --upload       upload the IPA to App Store Connect with xcrun altool
  --ref <ref>    rebuild a commit/tag in detached HEAD (must be an ancestor of
                 the environment's branch)
  --dry-run      print the steps; run no Flutter, Pod, Apple or upload commands
  prod           refused until HYLITE_PROD_READY=1 is set (waits for #9)
EOF
}

ENVNAME=""
UPLOAD=0
REF=""
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    dev|prod) [ -z "$ENVNAME" ] || { echo "Only one environment allowed." >&2; exit 2; }; ENVNAME="$1" ;;
    --upload) UPLOAD=1 ;;
    --dry-run) DRY=1 ;;
    --ref) shift; [ $# -gt 0 ] || { echo "--ref needs a value." >&2; exit 2; }; REF="$1" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ -n "$ENVNAME" ] || { usage >&2; exit 2; }

# ---------------------------------------------------------------- helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
MOBILE="$REPO/apps/mobile"
LOG="$(mktemp "${TMPDIR:-/tmp}/hylite-release.XXXXXX")"
WORK=""                 # temp dir for the generated ExportOptions file
SECRETS_COPIED=0
START_REF=""
DETACHED=0

say()  { printf '%s\n' "$*" | tee -a "$LOG"; }
step() { say ""; say "== $*"; }
die()  { say "ERROR: $*" >&2; exit 1; }
# In a dry run a failed check is a warning, so the remaining steps still show.
check_fail() { if [ "$DRY" = 1 ]; then say "WARN (would stop a real run): $*"; else die "$*"; fi; }
run() {          # run <cmd...>
  if [ "$DRY" = 1 ]; then say "[dry-run] would run: $*"; else "$@" 2>&1 | tee -a "$LOG"; fi
}
run_in() {       # run_in <dir> <cmd...>
  local d="$1"; shift
  if [ "$DRY" = 1 ]; then say "[dry-run] would run (in ${d#"$REPO"/}): $*"
  else (cd "$d" && "$@") 2>&1 | tee -a "$LOG"; fi
}
file_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || echo "?"; }

cleanup() {
  local rc=$?
  # Remove the secret copies even on failure (gitignored, but don't leave them).
  if [ "$SECRETS_COPIED" = 1 ]; then
    rm -f "$MOBILE/secrets.local.json" \
          "$MOBILE/ios/Runner/GoogleService-Info.plist" \
          "$MOBILE/ios/Flutter/Secrets.xcconfig"
    printf '%s\n' "Cleanup: removed the copied secret files from the repo."
  fi
  [ -z "$WORK" ] || rm -rf "$WORK"
  if [ "$DETACHED" = 1 ] && [ -n "$START_REF" ]; then
    git -C "$REPO" checkout --quiet "$START_REF" 2>/dev/null \
      && printf '%s\n' "Cleanup: back on $START_REF." \
      || printf '%s\n' "Cleanup: could not return to $START_REF; run git checkout $START_REF."
  fi
  if [ "$rc" != 0 ] && [ "$DRY" = 0 ]; then printf '%s\n' "Run failed (exit $rc). Log kept at $LOG"
  else rm -f "$LOG" 2>/dev/null || true; fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

say "Hylite iOS release: env=$ENVNAME upload=$UPLOAD ref=${REF:-<branch tip>} dry-run=$DRY"
[ "$DRY" = 0 ] || say "DRY RUN: no Flutter, Pod, Apple or upload command will run."

# ------------------------------------------------------- 0. prod guard
if [ "$ENVNAME" = prod ] && [ "${HYLITE_PROD_READY:-}" != 1 ]; then
  say "REFUSED: prod builds are blocked until the prod setup (#9) is done:"
  say "  no prod bundle ID (R3), Firebase project, profile, plist or secrets yet."
  say "  When the owner has approved prod, run with HYLITE_PROD_READY=1 set."
  exit 3
fi
[ "$(uname -s)" = Darwin ] || check_fail "Not macOS (uname: $(uname -s)); iOS builds need the Mac."

# ------------------------------------------------- 1. git state / branch
step "1. Git state"
EXPECT_BRANCH=development; [ "$ENVNAME" = prod ] && EXPECT_BRANCH=main
cd "$REPO"
if [ -n "$(git status --porcelain)" ]; then
  check_fail "The working tree is not clean. Commit or stash first."
else say "OK: working tree clean."; fi
CUR_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
START_REF="$CUR_BRANCH"
if [ -n "$REF" ]; then
  git rev-parse --verify --quiet "$REF^{commit}" >/dev/null || die "--ref '$REF' is not a known commit or tag."
  if git rev-parse --verify --quiet "$EXPECT_BRANCH" >/dev/null; then
    git merge-base --is-ancestor "$REF" "$EXPECT_BRANCH" \
      || die "--ref '$REF' is not on $EXPECT_BRANCH (not an ancestor of its tip)."
  else
    check_fail "Local branch $EXPECT_BRANCH not found to validate --ref against."
  fi
  if [ "$DRY" = 1 ]; then say "[dry-run] would check out $REF (detached) and return to $CUR_BRANCH afterwards."
  else
    [ "$CUR_BRANCH" != HEAD ] || START_REF="$(git rev-parse HEAD)"
    git checkout --quiet --detach "$REF"; DETACHED=1
    say "Checked out $REF (detached)."
  fi
else
  if [ "$CUR_BRANCH" != "$EXPECT_BRANCH" ]; then
    check_fail "On branch '$CUR_BRANCH'; $ENVNAME builds run from '$EXPECT_BRANCH' (or use --ref)."
  else say "OK: on $EXPECT_BRANCH."; fi
fi
SHA="$(git rev-parse --short=8 HEAD)"
say "Commit: $SHA"

# ---------------------------------------------------- 2. release env file
step "2. Release environment (~/.hylite-release.env)"
ENV_FILE="$HOME/.hylite-release.env"
if [ ! -f "$ENV_FILE" ]; then
  check_fail "$ENV_FILE not found. Copy scripts/ios/release.env.example there, fill it in, chmod 600."
else
  [ "$(file_mode "$ENV_FILE")" = 600 ] || check_fail "$ENV_FILE must be mode 600 (chmod 600 it)."
  set -a; . "$ENV_FILE"; set +a
fi
MISSING=""
for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH APPLE_TEAM_ID; do
  [ -n "${!v:-}" ] || MISSING="$MISSING $v"
done
if [ "$ENVNAME" = dev ]; then
  BUNDLE_ID="${BUNDLE_ID_DEV:-$DEV_BUNDLE_DEFAULT}"
  PROFILE_NAME="${PROFILE_NAME_DEV:-$DEV_PROFILE_DEFAULT}"
  APPLE_ID="${APP_STORE_APPLE_ID_DEV:-$DEV_APPLE_ID_DEFAULT}"
else
  BUNDLE_ID="${BUNDLE_ID_PROD:-}"; PROFILE_NAME="${PROFILE_NAME_PROD:-}"; APPLE_ID="${APP_STORE_APPLE_ID_PROD:-}"
  for v in BUNDLE_ID_PROD PROFILE_NAME_PROD APP_STORE_APPLE_ID_PROD; do
    [ -n "${!v:-}" ] || MISSING="$MISSING $v"
  done
fi
if [ -n "$MISSING" ]; then check_fail "Missing in $ENV_FILE (names only):$MISSING"
else say "OK: required variables present (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, APPLE_TEAM_ID, profile, bundle, Apple ID)."; fi
ASC_KEY_PATH="${ASC_KEY_PATH:-}"
ASC_KEY_PATH="${ASC_KEY_PATH/#\~/$HOME}"
if [ -n "$ASC_KEY_PATH" ]; then
  if [ ! -f "$ASC_KEY_PATH" ]; then check_fail "The API key file named by ASC_KEY_PATH does not exist."
  elif [ "$(file_mode "$ASC_KEY_PATH")" != 600 ]; then check_fail "The API key file must be mode 600 (chmod 600 it)."
  else say "OK: API key file exists, mode 600."; fi
fi
# Values go into the generated plist and a sed script: allow identifier characters only.
for pair in "BUNDLE_ID:${BUNDLE_ID}" "PROFILE_NAME:${PROFILE_NAME}" "APPLE_TEAM_ID:${APPLE_TEAM_ID:-}"; do
  if [ -n "${pair#*:}" ] && ! printf '%s' "${pair#*:}" | grep -Eq '^[A-Za-z0-9 ._-]+$'; then
    check_fail "${pair%%:*} has characters outside A-Z a-z 0-9 space . _ -."
  fi
done
case "$APPLE_ID" in ''|*[!0-9]*) check_fail "The app's Apple ID for $ENVNAME must be numeric." ;; esac

# --------------------------------------------------- 3. secret files
step "3. Secret files (~/hylite-secrets/$ENVNAME/)"
SRC="$HOME/hylite-secrets/$ENVNAME"
S_JSON="$SRC/secrets.local.json"; S_PLIST="$SRC/GoogleService-Info.plist"
D_JSON="$MOBILE/secrets.local.json"
D_PLIST="$MOBILE/ios/Runner/GoogleService-Info.plist"
D_XCC="$MOBILE/ios/Flutter/Secrets.xcconfig"
for f in "$S_JSON" "$S_PLIST"; do
  if [ -f "$f" ]; then
    say "OK: found $(basename "$f")."
    [ "$(file_mode "$f")" = 600 ] || say "WARN: $(basename "$f") is not mode 600."
  else check_fail "Missing $f (owner copies it there; no agent opens it)."; fi
done
for f in "$D_JSON" "$D_PLIST" "$D_XCC"; do
  [ ! -e "$f" ] || check_fail "$(basename "$f") already exists in the repo; remove it first (this run deletes its copies afterwards)."
done
if [ "$DRY" = 1 ]; then
  say "[dry-run] would copy both files in, write ios/Flutter/Secrets.xcconfig with PlistBuddy,"
  say "[dry-run] and check that API_BASE_URL starts with https:// (value never printed)."
else
  SECRETS_COPIED=1
  cp "$S_JSON" "$D_JSON"; cp "$S_PLIST" "$D_PLIST"
  chmod 600 "$D_JSON" "$D_PLIST"
  # Same check as codemagic.yaml:67-75; prints no value.
  python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get("API_BASE_URL"); sys.exit(0 if isinstance(v,str) and v.startswith("https://") else 1)' "$D_JSON" \
    || die "secrets.local.json has no API_BASE_URL starting with https:// (fix it in ~/hylite-secrets/$ENVNAME/)."
  say "OK: API_BASE_URL is set and starts with https://."
  # Same as codemagic.yaml:76-83 (Google Sign-In config).
  REV="$(/usr/libexec/PlistBuddy -c 'Print :REVERSED_CLIENT_ID' "$D_PLIST")" || die "GoogleService-Info.plist has no REVERSED_CLIENT_ID (enable Google sign-in before downloading it)."
  CID="$(/usr/libexec/PlistBuddy -c 'Print :CLIENT_ID' "$D_PLIST")" || die "GoogleService-Info.plist has no CLIENT_ID."
  { echo "GOOGLE_REVERSED_CLIENT_ID = $REV"; echo "GOOGLE_IOS_CLIENT_ID = $CID"; } > "$D_XCC"
  unset REV CID
  say "OK: wrote ios/Flutter/Secrets.xcconfig."
fi

# ------------------------------------------------------------ 4. checks
step "4. Toolchain, packages and checks"
if [ "$DRY" = 1 ]; then
  say "[dry-run] would require 'flutter --version' to report $FLUTTER_PIN."
else
  FV="$(flutter --version 2>&1 | tee -a "$LOG" | sed -n 's/^Flutter \([0-9][0-9.]*\).*/\1/p' | head -n 1)"
  [ "$FV" = "$FLUTTER_PIN" ] || die "Flutter is '${FV:-unknown}', must be exactly $FLUTTER_PIN (do not upgrade it)."
  say "OK: Flutter $FV."
fi
run_in "$MOBILE" flutter pub get
if [ -f "$MOBILE/ios/Podfile.lock" ]; then run_in "$MOBILE/ios" pod install
else say "No Podfile.lock: using --repo-update."; run_in "$MOBILE/ios" pod install --repo-update; fi
run_in "$MOBILE" flutter analyze
run_in "$MOBILE" flutter test
if command -v node >/dev/null 2>&1; then run_in "$REPO" node scripts/check-versions.mjs
else say "SKIP: node not found; version check not run."; fi
say "Note: golden tests skip on macOS; run them on Windows before UI approval."

# -------------------------------------------------- 5. build number
step "5. Build number"
if [ "$DRY" = 1 ]; then
  say "[dry-run] would run app-store-connect get-latest-app-store-build-number / get-latest-testflight-build-number"
  say "[dry-run] for the app's Apple ID, and use max+1 (stop if either lookup fails)."
  BUILD="<BUILD>"
else
  command -v app-store-connect >/dev/null 2>&1 || die "app-store-connect not found (pipx install codemagic-cli-tools)."
  export APP_STORE_CONNECT_KEY_IDENTIFIER="$ASC_KEY_ID"
  export APP_STORE_CONNECT_ISSUER_ID="$ASC_ISSUER_ID"
  export APP_STORE_CONNECT_PRIVATE_KEY="@file:$ASC_KEY_PATH"
  LATEST="$(app-store-connect get-latest-app-store-build-number "$APPLE_ID" 2>>"$LOG")" || die "App Store build-number lookup failed; not guessing 0."
  TESTFLIGHT="$(app-store-connect get-latest-testflight-build-number "$APPLE_ID" 2>>"$LOG")" || die "TestFlight build-number lookup failed; not guessing 0."
  LATEST="$(printf '%s' "$LATEST" | tail -n 1 | tr -d '[:space:]')"
  TESTFLIGHT="$(printf '%s' "$TESTFLIGHT" | tail -n 1 | tr -d '[:space:]')"
  case "$LATEST$TESTFLIGHT" in ''|*[!0-9]*) die "A build-number lookup returned something that is not a number." ;; esac
  [ -n "$LATEST" ] && [ -n "$TESTFLIGHT" ] || die "A build-number lookup returned nothing."
  BUILD=$(( (LATEST > TESTFLIGHT ? LATEST : TESTFLIGHT) + 1 ))
  say "Latest App Store: $LATEST; latest TestFlight: $TESTFLIGHT; new build number: $BUILD."
fi

# ----------------------------------------------------------- 6. build
step "6. Build the IPA"
TEMPLATE="$SCRIPT_DIR/ExportOptions.plist.template"
[ -f "$TEMPLATE" ] || die "Missing $TEMPLATE."
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hylite-export.XXXXXX")"
EXPORT_PLIST="$WORK/ExportOptions.plist"
sed -e "s|__TEAM_ID__|${APPLE_TEAM_ID:-TEAMID}|g" \
    -e "s|__BUNDLE_ID__|${BUNDLE_ID:-BUNDLEID}|g" \
    -e "s|__PROFILE_NAME__|${PROFILE_NAME:-PROFILE}|g" "$TEMPLATE" > "$EXPORT_PLIST"
say "Generated ExportOptions in a temp dir outside the repo."
rm -rf "$MOBILE/build/ios/ipa" "$MOBILE/build/ios/archive"
run_in "$MOBILE" flutter build ipa --release \
  --dart-define-from-file=secrets.local.json \
  --build-number="$BUILD" \
  --export-options-plist="$EXPORT_PLIST"

# ------------------------------------------------------ 7. verify IPA
step "7. Verify the IPA"
PUBSPEC_VER="$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' "$MOBILE/pubspec.yaml" | head -n 1)"
if [ "$DRY" = 1 ]; then
  say "[dry-run] would check exactly one build/ios/ipa/*.ipa exists, read CFBundleIdentifier,"
  say "[dry-run] CFBundleShortVersionString and CFBundleVersion from its Info.plist (a build product),"
  say "[dry-run] and require bundle ID = expected and build = $BUILD."
  VERSION="$PUBSPEC_VER"
else
  shopt -s nullglob
  IPAS=("$MOBILE"/build/ios/ipa/*.ipa)
  shopt -u nullglob
  [ "${#IPAS[@]}" = 1 ] || die "Expected exactly one IPA in apps/mobile/build/ios/ipa, found ${#IPAS[@]}."
  IPA="${IPAS[0]}"
  ARCHIVE="$MOBILE/build/ios/archive/Runner.xcarchive"
  [ -d "$ARCHIVE" ] || die "The .xcarchive is missing at build/ios/archive/Runner.xcarchive."
  unzip -p "$IPA" 'Payload/*.app/Info.plist' > "$WORK/Info.plist" || die "Could not read Info.plist from the IPA."
  PB=/usr/libexec/PlistBuddy
  IPA_BUNDLE="$($PB -c 'Print :CFBundleIdentifier' "$WORK/Info.plist")"
  VERSION="$($PB -c 'Print :CFBundleShortVersionString' "$WORK/Info.plist")"
  IPA_BUILD="$($PB -c 'Print :CFBundleVersion' "$WORK/Info.plist")"
  say "IPA bundle ID: $IPA_BUNDLE"
  say "IPA version:   $VERSION"
  say "IPA build:     $IPA_BUILD"
  [ "$IPA_BUNDLE" = "$BUNDLE_ID" ] || die "IPA bundle ID differs from the expected $ENVNAME bundle ID."
  [ "$IPA_BUILD" = "$BUILD" ] || die "IPA build ($IPA_BUILD) is not the requested build number ($BUILD)."
fi

# ---------------------------------------------------- 8. keep artifacts
step "8. Keep the artifacts"
OUT="$HOME/hylite-releases/$ENVNAME/${VERSION}+${BUILD}"
if [ "$DRY" = 1 ]; then
  say "[dry-run] would copy the IPA, Runner.xcarchive, dSYMs and the log to $OUT"
  say "[dry-run] would create the local tag ios-$ENVNAME-${VERSION}+${BUILD} (never pushed)."
else
  [ ! -e "$OUT" ] || die "$OUT already exists; not overwriting."
  mkdir -p "$OUT"
  cp "$IPA" "$OUT/"
  cp -R "$ARCHIVE" "$OUT/"
  if [ -d "$ARCHIVE/dSYMs" ]; then cp -R "$ARCHIVE/dSYMs" "$OUT/dSYMs"; else say "WARN: no dSYMs in the archive; check the Crashlytics symbols phase."; fi
  cp "$LOG" "$OUT/release.log"
  say "Saved to $OUT"
  TAG="ios-$ENVNAME-${VERSION}+${BUILD}"
  if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then say "WARN: tag $TAG already exists; not moved."
  else git tag "$TAG" HEAD; say "Created local tag $TAG. It is NOT pushed; pushing needs the owner."; fi
  printf '%s\t%s\t%s+%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$ENVNAME" "$VERSION" "$BUILD" "$SHA" >> "$HOME/hylite-releases/release-log.tsv"
fi

# ------------------------------------------------------------ 9. upload
step "9. Upload"
if [ "$UPLOAD" = 1 ]; then
  if [ "$DRY" = 1 ]; then
    say "[dry-run] would run: xcrun altool --upload-app -f <ipa> -t ios --apiKey <ASC_KEY_ID> --apiIssuer <ASC_ISSUER_ID>"
  else
    case "$ASC_KEY_PATH" in
      "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8") ;;
      *) say "WARN: altool looks for the key at ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8; yours is elsewhere, so the upload may fail." ;;
    esac
    if xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee -a "$LOG"; then
      cp "$LOG" "$OUT/release.log"
      say "Upload command finished. Wait for TestFlight processing before installing."
    else
      cp "$LOG" "$OUT/release.log"
      say "Upload failed. Fallbacks (the build is kept in $OUT):"
      say "  app-store-connect publish --path \"$OUT/$(basename "$IPA")\" --testflight   (needs the APP_STORE_CONNECT_* env or key flags)"
      say "  or open the IPA in Transporter and Deliver."
      exit 1
    fi
  fi
else
  say "Not uploading (no --upload). To upload this build later:"
  say "  xcrun altool --upload-app -f \"$OUT/<the .ipa>\" -t ios --apiKey \"\$ASC_KEY_ID\" --apiIssuer \"\$ASC_ISSUER_ID\""
  say "  or: app-store-connect publish --path <ipa> --testflight, or Transporter."
fi

step "Done"
say "Env: $ENVNAME  Version: ${VERSION}+${BUILD}  Commit: $SHA"
[ "$DRY" = 1 ] && say "DRY RUN finished: nothing was built or uploaded."
exit 0
