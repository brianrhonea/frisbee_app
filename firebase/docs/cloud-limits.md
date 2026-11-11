# Cloud and database limits

What the app gets free on its current plans, what the app limits on its
own, and which feature hits which limit first. Prices and quotas were
read from the official pricing pages on **2026-11-05**. They change, so
check the links before deciding anything that costs money:
- https://firebase.google.com/pricing
- https://livekit.com/pricing
- https://cloud.google.com/firestore/pricing
- https://cloud.google.com/storage/pricing

## Current plans

| Service | Plan | Notes |
|---|---|---|
| Firebase (dev and prod projects) | **Blaze** (pay as you go) | Includes the Spark no-cost amounts below. Past them, usage is billed, not shut off. Cloud Storage and Cloud Functions require Blaze. |
| LiveKit Cloud | **Build** (free), assumed | Nothing in the repo shows a paid plan. If you've upgraded to Ship ($50/month) or higher, use that column below. |
| GitHub Actions | Free for the repo | Deploy and rollback runs use a few minutes each. |
| Codemagic | Your existing plan | iOS builds; not covered here. |
| OpenStreetMap tiles, Nominatim, YouTube oEmbed | Free public services | Fair-use policies, no quota numbers. Nominatim asks for at most 1 request a second. |

> **Set a billing budget.** Blaze has no spending cap. In Google Cloud
> console → Billing → Budgets & alerts, add a budget (e.g. $10/month) on
> each project's billing account so you get an email at 50%, 90% and 100%.

---

## 1. Free amounts per service

### Firebase

| Service | Free each period | Then |
|---|---|---|
| **Firestore**: document reads | 50,000 / day | Google Cloud Firestore rates |
| **Firestore**: document writes | 20,000 / day | Google Cloud Firestore rates |
| **Firestore**: document deletes | 20,000 / day | Google Cloud Firestore rates |
| **Firestore**: stored data | 1 GiB | Google Cloud Firestore rates |
| **Firestore**: network egress | 10 GiB / month | Google Cloud rates |
| **Cloud Storage** (`*.firebasestorage.app`): stored | 5 GB-months | Cloud Storage rates |
| **Cloud Storage**: downloaded | 100 GB / month | Cloud Storage rates |
| **Cloud Storage**: upload operations | 5,000 / month | Cloud Storage rates |
| **Cloud Storage**: download operations | 50,000 / month | Cloud Storage rates |
| **Cloud Functions**: invocations | 2,000,000 / month | $0.40 per million |
| **Cloud Functions**: compute | 400,000 GB-seconds and 200,000 CPU-seconds / month | Google Cloud rates |
| **Cloud Functions**: outbound networking | 5 GB / month | $0.12 / GB |
| **Cloud Functions**: Cloud Build (deploys) | 120 minutes / day | $0.003 / minute |
| **Hosting**: storage | 10 GB | $0.026 / GB |
| **Hosting**: data transfer | 360 MB / day | $0.15 / GB |
| **Authentication** | 50,000 monthly active users | Identity Platform rates |
| **Cloud Messaging (push)** | Free, no quota | – |
| **App Check** | Free | Subject to each attestation provider's quota (below) |
| **Remote Config** (not used by the app) | 100,000 fetches / day | $0.06 per 10,000 |

Things to know:
- **Firestore quotas are per day** and reset at midnight Pacific time.
  Storage and Functions quotas are per month.
- **Storage's free amounts only apply to buckets in `us-central1`,
  `us-west1` or `us-east1`.** Check the bucket's location in Firebase
  console → Storage. A bucket elsewhere pays from the first byte.
- **The Functions free amounts are per billing account,** not per
  project. If dev and prod share a billing account, they share the 2
  million invocations.
- The Firestore and Storage paid rates aren't on the Firebase page; they
  link to Google Cloud. They're a few cents per 100,000 operations or per
  GB.

### App Check providers

| Provider | Quota |
|---|---|
| Play Integrity (Android) | 10,000 calls a day on the Standard tier, shared by every app in the Google Cloud project. Past it, some devices can't get a token. Request a higher tier in Play Console; approval takes days. |
| App Attest / DeviceCheck (Apple) | No quota listed by Firebase. |
| Debug provider (Windows, debug builds) | For development only. |

App Check tokens are cached and refreshed about once an hour per device,
so 10,000 a day covers a few thousand daily Android users.

### LiveKit Cloud

| | **Build** ($0) | Ship ($50 / month) | Scale ($500 / month) |
|---|---|---|---|
| WebRTC participant minutes | **5,000** | 150,000, then $0.0005 / min | 1.5M, then $0.0004 / min |
| Concurrent connections | **100** | 1,000 | 5,000 |
| Downstream data | **50 GB** | 250 GB, then $0.12 / GB | 3 TB, then $0.10 / GB |
| Recording and export transcode | 60 min | 600 min, then $0.02 / min (video) | 8,000 min, then $0.015 / min |
| Track egress | 60 min | 600 min | 8,000 min |
| Concurrent exports and imports | 2 | 100 | 500 |

- A **participant minute** is one person connected for one minute. A
  10-person, 1-hour meeting uses 600.
- The pricing page doesn't say what Build does when it runs out; plan on
  calls failing to connect until the next month.
- The app doesn't record meetings, so recording minutes aren't used
  today.
- Agent, inference, telephony and SIP minutes are for AI agents and
  phone calls, which the app doesn't use.

---

## 2. Limits the app sets itself

| Limit | Value | Where |
|---|---|---|
| Chat, DM and post attachment | 10 MB per file | `maxAttachmentBytes` (`lib/domain/models/chat.dart`), `storage.rules` |
| Photo before compression | 50 MB (shrunk to ≤ 1920 px, JPEG 80) | `ImageCompressor` |
| Uploaded video | 500 MB per file | `TeamVideo.maxFileBytes`, rules |
| Uploaded video per team | 5 GB (app only) | `TeamVideo.teamQuotaBytes` |
| Messages | 20 a minute per person | `functions/src/api/model.ts` |
| Posts | 10 an hour | same |
| Comments | 30 per 10 minutes | same |
| Follows | 60 an hour | same |
| Group join requests | 20 an hour | same |
| New teams | 5 a day | same |
| Server searches | 30 a minute, 50 results each | same |
| Username sign-in attempts | 10 per 15 minutes per username | same |
| Going over a limit | Extra items deleted; muted for 10 minutes | `muteMs` |
| Function instances | At most 10 per function (`api-health`: 2) | `functions/src/options.ts` |
| Chat history page | 50 messages | `MessageThreadViewModel.pageSize` |
| Home feed page | 20 posts per source | `home_feed.dart` |
| Notifications and comments on screen | Newest 100 | repositories |
| Feed entries kept | 60 days | `eventReminders` prunes |
| LiveKit tokens | 6 hours | `functions/src/meetings` |

## 3. Platform hard limits worth knowing

These are fixed by Firebase, whatever the plan:

- **Firestore document:** 1 MiB maximum. Stats games keep every point in
  one doc (`statsGames/{id}`), which is fine for a game but would not be
  for a season.
- **One document:** about 1 sustained write a second. Busy shared docs
  (a team doc during a big import, `followCounts` for a popular person)
  are where this shows up first.
- **Security rules:** at most 10 `get()`/`exists()` lookups for a
  single-document request and 20 for a batch or transaction. Team and
  room rules are close to this; keep it in mind when adding checks.
- **Callable functions:** 10 MB request size; event functions time out
  at 9 minutes (`deleteAccount` is set to 540 s).

---

## 4. Each feature and the limit it uses

Rough estimates for planning, not measurements. The debug read counter
(`FirestoreReads`) and Firebase console → Usage show real numbers.

| Feature | Uses | Limit it reaches first | Rough headroom on free amounts |
|---|---|---|---|
| **Team chat and DMs** | Firestore reads (50 per room opened, then 1 per new message per reader), writes (1 per message + conversation preview), 2 function runs per message (flood check + notification) | Firestore reads/day | ~50–150 daily active users before reads cost money (cents a day after) |
| **Chat photos and files** | Storage: 1 upload op per file, 1 download op per view (cached per session) | Storage **download operations, 50,000/month** | ~50,000 photo/file opens a month. Compressed photos are ~200–600 KB, so the 100 GB transfer lasts much longer |
| **Home feed and posts** | Firestore reads (20 per source on open, one page per scroll), writes, 2 function runs per post | Firestore reads/day | Shared with chat above |
| **Comments, likes, follows** | Firestore writes; follow/comment counters and notifications in Functions | Firestore writes/day (20,000) | Far off at current size |
| **Schedule, events, reminders** | Firestore reads via `MySchedule`; `eventReminders` runs 720 times a month | Firestore reads/day | Small |
| **Team videos (uploads)** | Storage stored, downloaded, operations | **Storage stored, 5 GB** | One team at its 5 GB quota uses all the free storage. Each full play of a 500 MB file uses 0.5 GB of the 100 GB/month |
| **Team videos (YouTube)** | Nothing on Firebase; YouTube hosts and streams | – | Unlimited; the cheapest way to share film |
| **Meetings** | LiveKit participant minutes and downstream data; Firestore for chat, lobby and watch-together | **LiveKit 5,000 minutes/month** | ~8 one-hour meetings of 10 people a month |
| **Voice channels** | LiveKit participant minutes for as long as someone stays connected, even while using other pages | **LiveKit 5,000 minutes/month** and **100 concurrent connections** | ~83 person-hours a month in total, shared with meetings. One person left connected all day uses ~1,400 |
| **Watch together** | Each viewer streams the video themselves (YouTube or Storage), not through LiveKit | Storage downloads for uploaded files | 10 viewers × a 500 MB file = 5 GB per session |
| **Screen share and camera** | LiveKit downstream data | **LiveKit 50 GB/month** | Roughly 30–60 person-hours of video received; audio-only uses far less |
| **Notifications and push** | Functions runs and Firestore writes (feed entries); FCM free | Functions invocations | 2M/month is about 1M chat messages |
| **Search** | Firestore reads (up to 50 per search); `api-search` adds 1 function run and 1 rate-limit write | Firestore reads/day | Debounced, so a typed name is 1–3 searches |
| **Sign-in and accounts** | Auth MAU, `account-*` functions | Auth 50,000 MAU | Far off |
| **App Check** | Play Integrity calls on Android | 10,000/day | A few thousand daily Android users |
| **Join pages and hosting** | Hosting transfer, cached at the CDN | 360 MB/day | Thousands of page views a day |
| **Monitoring and alerts** | 2 uptime checks, 6 alert policies, 1 log metric | Cloud Monitoring's own free allotment | Expected to stay inside it at this size |
| **Deploys and rollbacks** | Cloud Build minutes for functions | 120 min/day | A full deploy uses a few minutes |

## 5. What happens at a limit

| Service | When the free amount runs out |
|---|---|
| Firebase on Blaze | Keeps working and bills the overage. Nothing shuts off, which is why the budget alert matters. |
| LiveKit Build | No overage billing listed; expect new calls to fail until the month resets. Upgrade to Ship for 150,000 minutes. |
| Play Integrity | Some Android devices can't get an App Check token. Once App Check is enforced, their requests fail. |
| App rate limits | The extra item is deleted and the person is muted for 10 minutes. |

## 6. What to watch and when to upgrade

- **Firebase console → Usage and billing** for Firestore reads, Storage
  and Functions; **LiveKit dashboard** for minutes and bandwidth.
- The text alerts in `docs/monitoring.md` cover read spikes (100,000 in 5
  minutes), function floods and mass mutes.
- **First to run out at today's size:**
  1. **LiveKit minutes:** voice channels and meetings share 5,000 a
     month. If teams use them weekly, move to Ship. Consider
     disconnecting voice after a period of no activity.
  2. **Storage space for uploaded videos:** suggest YouTube links for
     film, or lower the per-team quota.
  3. **Storage download operations:** 50,000 a month across all photos,
     files and videos.
  4. **Firestore reads:** grows with daily users; paging and
     `SharedStreams` keep it near one page per screen.
