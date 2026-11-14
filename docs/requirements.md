# Stall 10 requirements

What the product must do, and where each requirement stands in each
client. Every feature ships in **both** the mobile app (`apps/mobile`,
iOS and Android) and the website (`apps/web`); purely visual changes may
be one platform only. Behaviour lives in the API (`apps/api`) where it can,
so both clients share it.

Update a row's status in the same change that moves it. Statuses:
**Done**, **Partial** (what's missing is listed), **Missing**.

Last audited: 2026-11-13, on `feature/core-parity`.

## 1. Every user

| # | Requirement | Mobile | Web | Gaps |
|---|---|---|---|---|
| U1 | **Sign in** with email (or username), Google, or Apple (Apple where the platform offers it) | Done: email or username, Google, Apple | Done: email or username, Google, Apple (web 0.9.0) | Web: Apple needs its Services ID and return URL set in the Firebase console |
| U2 | **Sign up** at 13 or older; under 18 needs a parent or guardian's permission | Partial | Partial | Both: 13+ check and guardian contact details are built (API 0.7.0, web 0.8.0, app 0.0.19; not deployed yet). Missing: guardian approval by email (D1) |
| U3 | **Search** all other users, and **browse rankings** of teams and players | Done: Explore search; Rankings (teams by division, players) | Done: search (`/explore`); `/rankings` (web 0.9.0) | |
| U4 | **Post** text with up to 4 photos (D2), plus workouts and recordings | Done: text, 4 photos, workouts, GPS recordings | Done: text, 4 photos, workouts typed in (web 0.9.0) | GPS recordings stay in the app: a browser can't track a run |
| U5 | **Feed** of posts from people they follow (and their own); tapping Home or scrolling to the top refreshes it | Done: pull down, or tap Home again, to refresh (0.0.20) | Done: clicking Home again scrolls up and reloads (web 0.9.0) | Feed sources stay as they are (D3) |
| U6 | **Interact** with posts: like, repost, share to people in a DM, and share a link outside the app | Done: like, repost, send in a DM, share sheet and copy link | Partial: like, repost, share sheet or copy link (web 0.9.0) | Web: send a post in a DM (with messages, U7) |
| U7 | **Messages** with one person or a group | Done: direct messages and groups (up to 10), message requests | Missing: "Messages are in the app" | Web: conversations list, threads, sending, groups, requests |
| U8 | **Private or public profile**, and who can follow and message them | Done: private profile with follow approval; message policy (everyone / followers / nobody) | Done: private profile, follow requests, who can message you (web 0.9.0, API 0.8.0) | |
| U9 | **Follow teams and communities** | Done | Done (follow from a team or community page) | |
| U10 | **Delete** their profile and data from Settings | Done: Settings → Delete account (`account-deleteAccount`) | Done: Settings → Account (web 0.9.0) | Deploy the `account` functions group so the personal details record is removed too |
| U11 | **Personal events**, and share their calendar with other users (not just teams and communities) | Partial: calendars with invites and roles, Settings → Calendars, the Schedule tab, Add to calendar, subscription link (0.0.20) | Partial: `/schedule` and Settings → Calendars (web 0.9.0) | Calendars other than My calendar aren't live (they load with the schedule and on pull-down). Team schedules aren't in the subscription feed. Outlook and Google subscriptions not yet tried against a deployed API |
| U12 | **Personal details** (legal name, birthday, phone, gender, address, guardian under 18), private to the player and encrypted | Done on this branch | Done on this branch | Deploy API 0.7.0, the KMS key in prod, and the `account` functions group |

## 2. Teams and communities

_To come._

## Decisions

- **D1. Parent permission (U2), 2026-11-13.** A player under 18 signs up
  with a guardian's details; we email the guardian an approve link.
  Until they approve, the account can browse but not post, message or
  join teams. Without approval in 14 days the account is removed. Needs
  an email sender (none is set up yet).
- **D2. Post media (U4), 2026-11-13.** Up to 4 photos (10 MB each before
  compression) per post. No video in posts for now, to keep storage costs
  down; revisit later (one video up to 100 MB, as chat attachments allow).
- **D3. Feed (U5), 2026-11-13.** The player's own posts, the people,
  teams and communities they follow, and their teams' posts. Not posts
  from followers they don't follow back.
- **D4. Calendars (U11), 2026-11-13, revised the same day.** Calendars
  work like Outlook or Apple Calendar. Everyone has My calendar and may
  make more (up to 20), each with a name and color. The owner invites
  people as **Can view** (title, type, time and place; never notes) or
  **Can edit** (add, change and delete events; sees notes); an invite is
  pushed, and nothing is shared until it's accepted. The owner changes
  roles or removes people at any time; anyone can leave. New events go
  on a calendar picked in the editor (the app also offers team
  schedules; the website, calendars only for now). For other calendar
  apps: **Add to calendar** on each event (an .ics file) and a private
  subscription link (webcal/ICS) of every calendar the player is on,
  which they can reset or turn off.
