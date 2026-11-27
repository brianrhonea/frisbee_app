#!/usr/bin/env bash
# Checks the Mac mini is ready for scripts/ios/release-ios.sh and prints an
# OK / FIX list. Read-only. Never prints secret values: presence and file
# modes only; the env file is read for variable NAMES, never shown.
# Plan: docs/specifications/mac-mini-build-plan.md section 2.3.
set -euo pipefail

FLUTTER_PIN="3.41.2"
OKS=0; FIXES=0; WARNS=0
ok()   { OKS=$((OKS+1));     printf 'OK    %s\n' "$*"; }
fix()  { FIXES=$((FIXES+1)); printf 'FIX   %s\n' "$*"; }
warn() { WARNS=$((WARNS+1)); printf 'WARN  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
file_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || echo "?"; }

echo "Hylite Mac doctor"
echo

IS_MAC=0
if [ "$(uname -s)" = Darwin ]; then
  IS_MAC=1
  ok "macOS $(sw_vers -productVersion) ($(uname -m))"
else
  fix "Not macOS (uname: $(uname -s)). iOS builds only work on the Mac mini."
fi

# --- Tools
if [ "$IS_MAC" = 1 ] && have xcodebuild; then
  XV="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' || true)"
  if [ -n "$XV" ]; then ok "Xcode: $XV"; else fix "xcodebuild fails: install Xcode, open it once, accept the licence, run: sudo xcodebuild -runFirstLaunch"; fi
else
  fix "Xcode not found (xcodebuild). Install Xcode from the App Store."
fi
if have flutter; then
  FV="$(flutter --version 2>/dev/null | sed -n 's/^Flutter \([0-9][0-9.]*\).*/\1/p' | head -n 1 || true)"
  if [ "$FV" = "$FLUTTER_PIN" ]; then ok "Flutter $FV"
  else fix "Flutter is '${FV:-unknown}', must be exactly $FLUTTER_PIN (git checkout $FLUTTER_PIN in the Flutter folder; do not upgrade)."; fi
else fix "flutter not on PATH (install 3.41.2)."; fi
if have pod; then ok "CocoaPods $(pod --version 2>/dev/null || echo '?')"; else fix "CocoaPods missing: brew install cocoapods"; fi
if have node; then ok "Node $(node --version)"; else fix "Node missing: brew install node"; fi
if have pnpm; then ok "pnpm $(pnpm --version 2>/dev/null || echo '?')"; else fix "pnpm missing: brew install pnpm"; fi
if have git; then ok "$(git --version)"; else fix "git missing."; fi
if have python3; then ok "python3 present (API_BASE_URL check)"; else fix "python3 missing (release-ios.sh needs it)."; fi
if have app-store-connect; then ok "codemagic-cli-tools: app-store-connect present"
else fix "codemagic-cli-tools missing: pipx install codemagic-cli-tools"; fi
if [ -x /usr/libexec/PlistBuddy ]; then ok "PlistBuddy present"; else fix "PlistBuddy missing (macOS only)."; fi
if have xcrun && xcrun --find altool >/dev/null 2>&1; then ok "xcrun altool found"
else warn "xcrun altool not found; use app-store-connect publish or Transporter for uploads."; fi

# --- Signing identity
if [ "$IS_MAC" = 1 ] && have security; then
  IDS="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Distribution' || true)"
  if [ -n "$IDS" ]; then
    N="$(printf '%s\n' "$IDS" | wc -l | tr -d ' ')"
    ok "Apple Distribution identities: $N"
    printf '%s\n' "$IDS" | sed -e 's/^ *[0-9]*) *[0-9A-F]* *//' | sed 's/^/        /'
  else
    fix "No Apple Distribution identity in the keychain: import the .p12 or create one in Xcode > Settings > Accounts > Manage Certificates."
  fi
  PROFDIR="$HOME/Library/MobileDevice/Provisioning Profiles"
  PN="$(ls "$PROFDIR"/*.mobileprovision 2>/dev/null | wc -l | tr -d ' ' || true)"
  if [ "${PN:-0}" -gt 0 ]; then ok "Provisioning profiles installed: $PN (contents not read)"
  else warn "No provisioning profiles in ~/Library/MobileDevice/Provisioning Profiles (Xcode or a double-click installs one)."; fi
fi

# --- Release env file and key
ENV_FILE="$HOME/.hylite-release.env"
if [ -f "$ENV_FILE" ]; then
  if [ "$(file_mode "$ENV_FILE")" = 600 ]; then
    ok "~/.hylite-release.env exists, mode 600"
    set -a; . "$ENV_FILE"; set +a
    MISS=""
    for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH APPLE_TEAM_ID; do [ -n "${!v:-}" ] || MISS="$MISS $v"; done
    if [ -z "$MISS" ]; then ok "Env file sets ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, APPLE_TEAM_ID"
    else fix "~/.hylite-release.env is missing (names only):$MISS"; fi
    KP="${ASC_KEY_PATH:-}"; KP="${KP/#\~/$HOME}"
    if [ -n "$KP" ]; then
      if [ ! -f "$KP" ]; then fix "The API key file named by ASC_KEY_PATH does not exist."
      elif [ "$(file_mode "$KP")" = 600 ]; then ok "API key file exists, mode 600"
      else fix "API key file mode is $(file_mode "$KP"); run chmod 600 on it."; fi
    fi
  else fix "~/.hylite-release.env must be mode 600: chmod 600 ~/.hylite-release.env"; fi
else
  fix "~/.hylite-release.env missing: copy scripts/ios/release.env.example there, fill it in, chmod 600."
fi

# --- Secret files (presence only)
for f in secrets.local.json GoogleService-Info.plist; do
  P="$HOME/hylite-secrets/dev/$f"
  if [ -f "$P" ]; then ok "~/hylite-secrets/dev/$f present"; else fix "~/hylite-secrets/dev/$f missing (owner copies it; nobody opens it)."; fi
done
if [ -d "$HOME/hylite-secrets/prod" ]; then warn "~/hylite-secrets/prod exists: prod files should not be on the Mac until #9 is done."; fi

# --- Energy
if have pmset; then
  PM="$(pmset -g 2>/dev/null || true)"
  SL="$(printf '%s\n' "$PM" | awk '$1=="sleep"{print $2; exit}')"
  if [ "${SL:-}" = 0 ]; then ok "System sleep: never (pmset sleep 0)"
  else fix "System sleep is '${SL:-unknown}': run sudo pmset -c sleep 0 (or System Settings > Energy: prevent sleep)."; fi
  AR="$(printf '%s\n' "$PM" | awk '$1=="autorestart"{print $2; exit}')"
  if [ "${AR:-}" = 1 ]; then ok "Start up after power failure: on"; else warn "Start up after power failure is off: sudo pmset -a autorestart 1"; fi
  WN="$(printf '%s\n' "$PM" | awk '$1=="womp"{print $2; exit}')"
  if [ "${WN:-}" = 1 ]; then ok "Wake for network access: on"; else warn "Wake for network access is off: sudo pmset -a womp 1"; fi
else
  fix "pmset not found (macOS only): energy settings not checked."
fi
if have fdesetup; then
  if fdesetup status 2>/dev/null | grep -q 'FileVault is On'; then ok "FileVault: on"
  else fix "FileVault is not on (plan Q-C): turn it on in System Settings > Privacy & Security."; fi
fi

echo
echo "Result: $OKS OK, $WARNS WARN, $FIXES FIX"
if [ "$FIXES" -gt 0 ]; then echo "Not ready: fix the FIX lines above."; exit 1; fi
echo "Ready for: scripts/ios/release-ios.sh dev --dry-run"
