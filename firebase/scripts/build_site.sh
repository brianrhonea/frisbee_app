#!/usr/bin/env bash
# Builds the website into firebase/build/site, which Firebase Hosting serves:
#   /                   the Flutter web app (apps/mobile/lib/main_web.dart)
#   /about, /privacy…   static pages and invite fallbacks (firebase/hosting/)
#
# Transitional: the Flutter web build is replaced by the Next.js app in
# apps/web (on Vercel) in phase 3; see ARCHITECTURE.md.
#
# Runs before every `firebase deploy --only hosting` (firebase.json
# predeploy). Picks the secrets file from the project being deployed:
# apps/mobile/secrets.prod.local.json for frisbee-app-brianrhonea, else
# apps/mobile/secrets.local.json (dev). Run it by hand to preview:
#   bash firebase/scripts/build_site.sh
#   cd firebase && firebase emulators:start --only hosting
set -euo pipefail

firebase_dir="$(cd "$(dirname "$0")/.." && pwd)"
mobile_dir="$(cd "$firebase_dir/../apps/mobile" && pwd)"

# The Flutter web target was removed; the website moves to apps/web on
# Vercel. Until hosting is reworked, refuse instead of failing in flutter.
if [[ ! -d "$mobile_dir/web" ]]; then
  echo "apps/mobile/web was removed: the Flutter website can't be built. The site is moving to Vercel (apps/web); see ARCHITECTURE.md §9. Hosting stays as last deployed." >&2
  exit 1
fi

project="${GCLOUD_PROJECT:-}"
if [[ "$project" == "frisbee-app-brianrhonea" ]]; then
  secrets="secrets.prod.local.json"
else
  secrets="secrets.local.json"
fi
if [[ ! -f "$mobile_dir/$secrets" ]]; then
  echo "Missing apps/mobile/$secrets; see apps/mobile/secrets.example.json and CLAUDE.md." >&2
  exit 1
fi
echo "Building the website with apps/mobile/$secrets${project:+ for $project}"

cd "$mobile_dir"
# Git Bash would otherwise turn / into a Windows path.
MSYS_NO_PATHCONV=1 flutter build web \
  -t lib/main_web.dart \
  --release \
  --base-href / \
  --no-wasm-dry-run \
  --dart-define-from-file="$secrets"

site="$firebase_dir/build/site"
rm -rf "$site"
mkdir -p "$site"
# hosting/ has no index.html, so the app's files don't collide with it.
cp -R "$firebase_dir/hosting/." "$site/"
cp -R "$mobile_dir/build/web/." "$site/"
echo "Built firebase/build/site"
