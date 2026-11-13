#!/usr/bin/env bash
# Text alerts when the backend goes down or misbehaves (Google Cloud
# Monitoring, free SMS channel). Run once per project from a shell with
# gcloud signed in as a project owner:
#
#   firebase/scripts/monitoring/setup-alerts.sh dev  +15551234567
#   firebase/scripts/monitoring/setup-alerts.sh prod +15551234567
#
# The phone number is only passed to Google; it's never written to the
# repo. Re-running is safe: things that already exist are skipped.
# See firebase/docs/monitoring.md.
set -euo pipefail

env_name="${1:-}"
phone="${2:-}"
case "$env_name" in
  dev) project="frisbee-app-brianrhonea-dev" ;;
  prod) project="frisbee-app-brianrhonea" ;;
  *) echo "usage: $0 dev|prod +1XXXXXXXXXX" >&2; exit 2 ;;
esac
if [[ ! "$phone" =~ ^\+[0-9]{8,15}$ ]]; then
  echo "Give the phone number in E.164 form, like +15551234567." >&2
  exit 2
fi

# Thresholds: raise them as real traffic grows.
ERRORS_PER_5MIN="${ERRORS_PER_5MIN:-10}"        # function 5xx responses
REQUESTS_PER_5MIN="${REQUESTS_PER_5MIN:-3000}"  # all function invocations
READS_PER_5MIN="${READS_PER_5MIN:-100000}"      # Firestore document reads
MUTES_PER_HOUR="${MUTES_PER_HOUR:-10}"          # rate-limit mutes

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
g() { gcloud --project "$project" --quiet "$@"; }

echo "== $project"
g services enable monitoring.googleapis.com logging.googleapis.com >/dev/null

# --- SMS channel --------------------------------------------------------------
channel=$(g beta monitoring channels list \
  --filter="type=\"sms\" AND labels.number=\"$phone\"" --format="value(name)" | head -1)
if [ -z "$channel" ]; then
  channel=$(g beta monitoring channels create --type=sms \
    --display-name="Text alerts" --channel-labels="number=$phone" \
    --format="value(name)")
  g beta monitoring channels send-verification-code "$channel"
  read -r -p "Enter the code Google just texted you: " code
  g beta monitoring channels verify "$channel" --verification-code="$code"
fi
echo "SMS channel: $channel"

# --- Uptime checks ------------------------------------------------------------
make_uptime() { # name host path
  local id
  id=$(g monitoring uptime list-configs --filter="displayName=\"$1\"" \
    --format="value(name)" | head -1)
  if [ -z "$id" ]; then
    id=$(g monitoring uptime create "$1" --resource-type=uptime-url \
      --resource-labels="host=$2,project_id=$project" --path="$3" \
      --protocol=https --period=5 --timeout=10 --format="value(name)")
  fi
  basename "$id"
}
site_check=$(make_uptime "Website up" "$project.web.app" "/")
api_check=$(make_uptime "API health" "us-central1-$project.cloudfunctions.net" "/api-health")

# --- Log-based metric: rate-limit mutes (functions/src/api) -------------------
if ! g logging metrics describe rate_limit_mutes >/dev/null 2>&1; then
  g logging metrics create rate_limit_mutes \
    --description="Users muted for flooding (functions/src/api)" \
    --log-filter='jsonPayload.message="Rate limit hit; muting"'
fi

# --- Alert policies -----------------------------------------------------------
policy() { # template, then KEY=VALUE substitutions
  local file="$here/policies/$1.json" out="$tmp/$1.json" name
  cp "$file" "$out"
  shift
  for kv in "CHANNEL=$channel" "$@"; do
    sed -i "s|\${${kv%%=*}}|${kv#*=}|g" "$out"
  done
  name=$(sed -n 's/.*"displayName": *"\([^"]*\)".*/\1/p' "$out" | head -1)
  if [ -n "$(g alpha monitoring policies list --filter="displayName=\"$name\"" --format="value(name)")" ]; then
    echo "Policy exists: $name"
  else
    g alpha monitoring policies create --policy-from-file="$out" >/dev/null
    echo "Policy created: $name"
  fi
}
policy uptime NAME="Website down" CHECK="$site_check"
policy uptime NAME="API down" CHECK="$api_check"
policy function-errors THRESHOLD="$ERRORS_PER_5MIN"
policy function-flood THRESHOLD="$REQUESTS_PER_5MIN"
policy firestore-reads THRESHOLD="$READS_PER_5MIN"
policy mutes THRESHOLD="$MUTES_PER_HOUR"

echo "Done. Test it: see firebase/docs/monitoring.md."
