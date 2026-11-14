# Stall 10 requirements

What the product must do, and where each requirement stands in each
client. Every feature ships in **both** the mobile app (`apps/mobile`,
iOS and Android) and the website (`apps/web`); purely visual changes may
be one platform only. Behaviour lives in the API (`apps/api`) where it can,
so both clients share it.

Update a row's status in the same change that moves it. Statuses:
**Done**, **Partial** (what's missing is listed), **Missing**.

Last audited: 2026-11-13, on `feature/personal-details`.

## 1. Every user

| # | Requirement | Mobile | Web | Gaps |
|---|---|---|---|---|
| U1 | **Sign in** with email (or username), Google, or Apple (Apple where the platform offers it) | Done: email or username, Google, Apple | Partial: email and Google | Web: Sign in with Apple; sign in with a username (`account-signInEmail`) |
| U2 | **Sign up** at 13 or older; under 18 needs a parent or guardian's permission | Partial | Partial | Both: 13+ check and guardian contact details are built (API 0.7.0, web 0.8.0, app 0.0.19; not deployed yet). Missing: guardian approval by email (D1) |
| U3 | **Search** all other users, and **browse rankings** of teams and players | Done: Explore search; Rankings (teams by division, players) | Partial: search (`/explore`) | Web: rankings pages |
| U4 | **Post** text with up to 4 photos or one video (D2), plus workouts and recordings | Partial: text, 4 photos, workouts, GPS recordings | Partial: text and 4 photos | Both: video in posts (one, up to 100 MB, compressed by the API's media pipeline). Web: workout posts and recordings |
| U5 | **Feed** of posts from people they follow (and their own); tapping Home or scrolling to the top refreshes it | Partial: feed of own posts, follows and teams; tapping Home again scrolls to the top | Partial: feed on the home dashboard, with a Retry button | Both: an explicit refresh on Home tap and on pull-down/scroll-up. Feed sources stay as they are (D3) |
| U6 | **Interact** with posts: like, repost, share to people in a DM, and share a link outside the app | Done: like, repost, send in a DM, share sheet and copy link | Partial: like and repost | Web: send a post in a DM; share or copy its link |
| U7 | **Messages** with one person or a group | Done: direct messages and groups (up to 10), message requests | Missing: "Messages are in the app" | Web: conversations list, threads, sending, groups, requests |
| U8 | **Private or public profile**, and who can follow and message them | Done: private profile with follow approval; message policy (everyone / followers / nobody) | Partial: private profile, follow requests | Web: message policy setting |
| U9 | **Follow teams and communities** | Done | Done (follow from a team or community page) | |
| U10 | **Delete** their profile and data from Settings | Done: Settings → Delete account (`account-deleteAccount`) | Missing: only an instructions page (`/delete-account`) | Web: Settings → Delete account (re-authenticate, then the same function). Deploy the `account` group so the personal details record is removed too |
| U11 | **Personal events**, and share their calendar with other users (not just teams and communities) | Partial: personal events on the schedule | Missing | Both: calendar sharing with chosen people (D4). Web: the personal schedule itself |
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
  compression) or one video up to 100 MB per post, as chat attachments
  and ARCHITECTURE.md §6 already allow.
- **D3. Feed (U5), 2026-11-13.** The player's own posts, the people,
  teams and communities they follow, and their teams' posts. Not posts
  from followers they don't follow back.
- **D4. Calendar sharing (U11), 2026-11-13.** The player picks people to
  share their personal calendar with. Those people see its events
  (title, time, place) read-only in their own schedule. Sharing can be
  stopped at any time.
