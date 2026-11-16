#!/usr/bin/env bash
# Builds firebase/build/site, which Firebase Hosting serves: the static
# pages and invite-link fallbacks in firebase/hosting/ (/about, /help,
# /terms, /privacy, /cookies, /delete-account, /join/…, /g/…, /p/… and
# .well-known/). Nothing is compiled.
#
# The website itself is apps/web (Next.js on Vercel); the old Flutter web
# app that Hosting used to serve at / is gone. See ARCHITECTURE.md.
#
# Runs before every `firebase deploy --only hosting` (firebase.json
# predeploy). Run it by hand to preview:
#   bash firebase/scripts/build_site.sh
#   cd firebase && firebase emulators:start --only hosting
set -euo pipefail

firebase_dir="$(cd "$(dirname "$0")/.." && pwd)"
site="$firebase_dir/build/site"

rm -rf "$site"
mkdir -p "$site"
# The trailing /. copies dotfiles too (.well-known for app links).
cp -R "$firebase_dir/hosting/." "$site/"
echo "Built firebase/build/site"
