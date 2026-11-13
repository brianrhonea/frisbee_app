# Stall 10 website changelog

The website's version is `version` in `apps/web/package.json`, shown in
the site's footer. Bump it with every change to the site and add an entry
here; `pnpm test` fails without one (`scripts/check-versions.mjs`).

## 0.5.0 — 2026-11-12

Website parity, slice W1 (`docs/product-spec.md` §8.1): posting,
comments, follows, notifications and settings. Needs API 0.4.0.

**Added**
- **Write posts** from Home: words, up to 4 photos (choose, drag in or
  paste; they upload while you type, through `/v1/uploads`) and up to 5
  links. Ctrl+Enter posts.
- **Edit and delete** your posts from the ⋯ menu, in place.
- **Comments** under every post, live: comment, reply (one level deep),
  like, edit and delete your own; the post's author can delete any.
  Enter sends.
- **Follow** players, teams and groups from their pages, with a bell for
  post notifications; private profiles get "Ask to follow" and
  "Requested". (Approved followers still see a private profile's page as
  private here; the app shows it.)
- **Notifications** (`/notifications`), live, with filters, an unread
  badge in the sidebar, mark-as-read as you look, follow back, and clear.
- **Settings** (`/settings`): profile details, privacy and what your
  profile shows, people you follow (a table with notification switches),
  and follow requests.
- Keyboard: `n` writes a post, `/` searches, `g` then `h`/`e`/`v`/`t`/`m`/`n`
  goes to Home, Explore, Events, Teams, Messages or Notifications.

**Changed**
- Member pages read Firestore in the browser (live), as the app does;
  every write goes through the API. `NEXT_PUBLIC_FIRESTORE_EMULATOR_HOST`
  points them at the emulator.

**Fixed**
- This changelog's 0.4.0 heading had a stray Windows-1252 byte.

## 0.4.0 — 2026-11-12

**Changed**
- New layout with the app's five tabs: Home, Explore, Events, Teams and
  Messages, in a left sidebar (icons only on tablets) and along the bottom
  on phones. Members get a Profile link; Learn, About and Help sit under
  the tabs; the account menu is at the bottom of the sidebar.
- Wide screens show what's coming up, and a sign-up card for visitors, in
  a right column.

**Added**
- Teams (`/teams`): your teams and groups; visitors get a sign-up prompt.
- Messages (`/messages`): points to the app until messages come to the web.

## 0.3.1 — 2026-11-12

**Fixed**
- The build compiles `@stall10/shared` first, so it works on a fresh
  checkout such as Vercel's (it failed with "Can't resolve
  '@stall10/shared'").

## 0.3.0 — 2026-11-11

**Added**
- Members like and repost posts (with an optional note) on every feed,
  profile and post page; a repost's likes and reposts go to its original,
  as in the app. Replies stay in the app ("Reply in the app").
- Reposts show the original post under the reposter's note.
- Members page through the community feed ("Older posts").

**Changed**
- Navigation follows who's signed in: members get Home, Community,
  Explore, Events and Learn, and an account menu (dashboard, public
  profile, log out); visitors get Community, Explore, Events, Learn and
  About, with Log in and Sign up.
- Sign-up prompts show only to visitors.

## 0.2.0 — 2026-11-11

**Added**
- Home page for everyone at `/`. Visitors see a preview (three recent
  posts, upcoming events, locked cards for teams, schedule and stats) with
  sign-up prompts; members see their profile dashboard: profile card,
  season stats, their teams, upcoming events with their RSVP, and their
  feed (`GET /v1/me/home`).
- Pick-a-username step for accounts made on the web.
- `/learn`: the rules of ultimate for beginners.
- Profiles use the dashboard layout.
- Version in the footer.

**Changed**
- `/home` and `/profile` go to `/`; signing in lands on `/`.
- The community feed and profiles show the newest page only; signing up
  shows the rest.
- Phones show the site links as a scrollable row under the header (they
  were hidden).
- A photo that won't load shows "Photo unavailable" instead of a broken
  image.

## 0.1.0 — 2026-11-11

First version: the public site ported from the Flutter web build and
`firebase/hosting` (community, posts, profiles, teams, events, search,
About/Help/legal pages, invite-link fallbacks, sign-in and sign-up).
