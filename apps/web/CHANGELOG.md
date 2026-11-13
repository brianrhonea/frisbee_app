# Stall 10 website changelog

The website's version is `version` in `apps/web/package.json`, shown in
the site's footer. Bump it with every change to the site and add an entry
here; `pnpm test` fails without one (`scripts/check-versions.mjs`).

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
