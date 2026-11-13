# Text alerts (Google Cloud Monitoring)

Google Cloud Monitoring texts you, for free, when:

| Alert | When |
|---|---|
| Website down | `<project>.web.app` fails its uptime check from more than one region for 5+ minutes |
| API down | `api-health` (one cheap Firestore read) fails the same way. Catches Firestore or Functions outages |
| Functions failing | More than 10 server errors from Cloud Functions in 5 minutes |
| Traffic flood | More than 3,000 function runs in 5 minutes (fake traffic or a loop) |
| Firestore read spike | More than 100,000 document reads in 5 minutes (scraping or a listener loop) |
| Many users muted | More than 10 rate-limit mutes in an hour |

Uptime checks run every 5 minutes, so an outage texts you within about 10
minutes, and you get another text when it clears. Deploy and build updates
aren't texted: GitHub emails you when a deploy or rollback run fails, and
Codemagic emails build results.

## Set up (once per project)

The script needs `gcloud`. The easiest place to run it is **Cloud Shell**,
which has gcloud and is already signed in:

1. Open https://console.cloud.google.com/?cloudshell=true and pick the
   project.
2. Run:
   ```
   git clone https://github.com/brianrhonea/frisbee_app.git && cd frisbee_app
   git checkout hardening/scale-and-abuse   # or development once merged
   bash firebase/scripts/monitoring/setup-alerts.sh dev +1XXXXXXXXXX
   ```
3. Google texts you a code. Type it when the script asks.
4. Once it works on dev, run it again with `prod` and the same number.

The `api` functions must be deployed first, or the API check alerts right
away. Running the script again is safe: anything that exists is skipped.

Thresholds are environment variables, for example
`READS_PER_5MIN=250000 bash firebase/scripts/monitoring/setup-alerts.sh prod +1…`.
To change a threshold that's already set, edit the policy in the console
(Monitoring → Alerting) or delete it and re-run the script.

## Test that texts arrive

Monitoring → Alerting → pick a policy → **Edit** → Notifications → *Send
test notification*. Or, on dev only, deploy `api-health` returning 503,
wait about 10 minutes for the text, then redeploy.

## Change number, silence, remove

- **Change number:** Monitoring → Alerting → Edit notification channels → SMS.
- **Silence for a while** (e.g. planned maintenance): Monitoring →
  Alerting → Snooze.
- **Remove:** delete the policies and uptime checks under Monitoring.
