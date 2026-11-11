#!/usr/bin/env bash
# Builds the website into build/site, which Firebase Hosting serves:
#   /                   the Flutter web app (lib/main_web.dart)
#   /about, /privacy…   static pages and invite fallbacks (hosting/)
#
# Runs before every `firebase deploy --only hosting` (firebase.json
# predeploy). Picks the secrets file from the project being deployed:
# secrets.prod.local.json for frisbee-app-brianrhonea, else
# secrets.local.json (dev). Run it by hand to preview:
#   bash scripts/build_site.sh && firebase emulators:start --only hosting
set -euo pipefail

cd "$(dirname "$0")/.."

project="${GCLOUD_PROJECT:-}"
if [[ "$project" == "frisbee-app-brianrhonea" ]]; then
  secrets="secrets.prod.local.json"
else
  secrets="secrets.local.json"
fi
if [[ ! -f "$secrets" ]]; then
  echo "Missing $secrets; see secrets.example.json and CLAUDE.md." >&2
  exit 1
fi
echo "Building the website with $secrets${project:+ for $project}"

# Git Bash would otherwise turn / into a Windows path.
MSYS_NO_PATHCONV=1 flutter build web \
  -t lib/main_web.dart \
  --release \
  --base-href / \
  --no-wasm-dry-run \
  --dart-define-from-file="$secrets"

rm -rf build/site
mkdir -p build/site
# hosting/ has no index.html, so the app's files don't collide with it.
cp -R hosting/. build/site/
cp -R build/web/. build/site/
echo "Built build/site"
