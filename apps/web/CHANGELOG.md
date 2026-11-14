# Stall 10 website changelog

The website's version is `version` in `apps/web/package.json`, shown in
the site's footer. Bump it with every change to the site and add an entry
here; `pnpm test` fails without one (`scripts/check-versions.mjs`).

## 0.10.1 — 2026-11-14

**Changed**
- New logo and favicon: the app's "10" disc mark in white and silver on
  graphite instead of lime on green, so it suits light, dark and any
  accent colour. `public/logo.png` and `public/favicon.png` are drawn by
  `apps/mobile/tool/brand/stall10_logo.py`.

**Deploys**
- Vercel builds only `main` (production) and `development` (the dev site,
  and only when `apps/web/` or `packages/` changed). Other branches no
  longer get preview deployments. See `vercel.json` and
  `scripts/vercel-ignore.sh`.

## 0.10.0 — 2026-11-14

**Changed**
- New look: an indigo palette (light) and "Midnight" (dark), with an amber
  call-to-action colour, squarer buttons and softer cards.
- The frame has a top bar on every page: the Stall 10 wordmark, a search
  box (players, teams and events; it opens Explore) and notifications and
  your account. The sidebar gains Learn, a **Create a post** button
  (**Join Stall 10** for visitors), your teams, and an About card.
- Home for members is "Your daily huddle.": the composer, then
  **Following** and **Community** feed tabs, with a right column for
  finding pickup, what's coming up on your teams and Learn. Your profile
  card and stats stay on your profile page.
- Home for visitors, and the right column on other pages, use the same
  layout: the community preview with pickup, upcoming events and sign-up
  cards beside it.
- Upcoming events show as date badges in a list; empty states and card
  spacing are consistent across pages.
- The top bar's search sits centred between the wordmark and your account,
  with even gaps at every width.
- Sign-up is two steps, as in the app: **Account details** (first and last
  name, a username suggested from your name that you can change, with a
  live "available" check, birthday, email and password), then **About
  you** (your personal details). With email, under 13 is refused before an
  account is made. Signing up with Google or Apple (as in the app) asks
  your username, then About you, whose birthday removes an account under
  13.
- Log in and sign up have a new look to match the rest of the site;
  "Forgot your password?" sits beside the password field.
- Form fields are the same height across sign-up and settings, and button
  labels are bold everywhere.

**Added**
- A light/dark switch (sun/moon) in the top bar, for visitors and members.
  The choice is kept in that browser; until someone picks, the site follows
  the system setting.
- Events has a week strip like the app's Schedule: seven days from today,
  dots for each day's team events (indigo) and tournaments (amber), and
  previous/next week. Pick a day to see just its events.
- Team hubs on desktops show Playbook, Videos, Stats and Tournaments as
  tabs of their own; narrower screens keep them under More.
- "Your spaces" in the sidebar labels each one (Team, Community or
  School/club) with its member count (128, 1.2k), and leaves out teams a
  community of yours lists, as the Teams page does.

## 0.9.3 — 2026-11-14

**Fixed**
- Ask to follow a private player: the button says **Requested** as soon as
  the API answers, and **Ask to follow** again once a request is taken
  back, instead of waiting for the live listener, which sometimes took
  15 s or more right after the profile turned private.

## 0.9.2 — 2026-11-14

**Fixed**
- `WEB_SERVER_KEY` is trimmed when sent to the API and when checking the
  API's refresh calls (`/api/revalidate`), so stray whitespace in either
  copy can't make them differ.

## 0.9.1 — 2026-11-13

Fixes from the two-person live test, for a more real-time feel. Needs API
0.9.0 and the `notifications` functions from the same change.

**Fixed**
- **Private profiles for approved followers**: a player page showed "This
  profile is private" even to people the player had accepted. Members now
  see each player's page as the API builds it for them
  (`/v1/players/:uid`, `components/PlayerPage.tsx`), so an accepted
  follower sees the bio, stats and posts the moment the request is
  accepted.
- **Stale pages**: player and post pages were cached for a minute, so a
  profile turned private or a post edited or deleted still showed. For
  members, they're now refetched whenever the profile, the player's
  posts, their own follow, or the post changes (Firestore listeners as
  change signals, `useChangeSignal` in `lib/live.ts`); likes and reposts
  by others update the counts too, and a deleted post says "This post was
  deleted." For visitors, the API expires the cached copy at once through
  the new `POST /api/revalidate` (shared `WEB_SERVER_KEY`; cache tags in
  `lib/api.ts`). A private author's post page now asks visitors to log in
  instead of showing "not found", and members who were approved see it.
- **Notification links**: the website opened the app's route, so some
  links were 404s (a follow request opened `/settings/follow-requests`).
  Each now opens the website's page for it (`webRoute` in
  `@stall10/shared`, tested against every route the functions send);
  things only the app has open "Get the app".
- **Notification counts** (the `notifications` functions): repeats by the
  same person no longer count up, so asking to follow again, or liking,
  unliking and liking, stays "Jordan wants to follow you" / "Jordan liked
  your post". Undoing takes it back out: an unlike, a request taken back,
  declined or accepted, a deleted comment, an undone repost or an
  unfollow re-words the notification or removes it.
- The career table and recent games on a player page follow the player's
  "Show on my profile" switches, like the stat tiles.

## 0.9.0 — 2026-11-13

Core features to match the app. Needs API 0.8.0.

**Added**
- **Settings → Account**: delete your account and its data. Confirms it's
  you (password, Google or Apple), then runs `account-deleteAccount`.
- **Share** on every post: the device's share sheet, or copies the link.
- **Settings → Privacy → Who can message you** (`/v1/me/message-policy`).
- **Continue with Apple** on sign-in and sign-up. Needs Apple set up in the
  Firebase console (Services ID, return URL) and the site's domain in
  Authentication's authorized domains.
- Sign in with a **username** as well as an email (`account-signInEmail`).
- **Rankings** (`/rankings`, linked from Explore): teams by division and
  player ratings, read live like the app's Rankings screen. Members only.
- **Workout posts**: the composer's workout button adds an activity,
  minutes, distance (km or mi), effort and exercises. GPS recordings stay
  in the app. Workouts show their activity's name.
- **Your schedule** (`/schedule`, from Events), like Outlook or Apple
  Calendar: every calendar you're on in its color, shown or hidden on
  this browser; invites to accept or decline; add, edit and delete events
  on any calendar you can edit, picking which one. Viewers see title,
  time and place, never notes. **Add to calendar** on each event
  downloads an .ics file.
- **Settings → Calendars**: make calendars (name and color), invite people
  as Can view or Can edit (they see nothing until they accept), change
  roles, cancel invites, remove people, leave others' calendars, and a
  private subscription link for Apple Calendar, Outlook and Google
  Calendar (reset or turn off).
- **Add to calendar** on team and group events.

**Changed**
- Clicking **Home** while on Home scrolls to the top and reloads the feed.

**Fixed**
- Editing a post showed the old words until a reload; the card now
  shows the edit at once.
- Username sign-in errors no longer end in the HTTP status (" [401]").

## 0.8.0 — 2026-11-13

Personal details at sign-up. Needs API 0.7.0.

**Added**
- Sign-up asks the date of birth first; under 13 can't make an account.
- New accounts finish signing up with their legal name, birthday, phone,
  gender, mailing address and, under 18, a parent or guardian, before
  using the site (`PersonalGate`). The legal pages and help stay open.
  If the API can't say, nobody is held up.
- Older accounts see a **Complete your details** card they can dismiss.
- **Settings → Personal details** to see and change them.
- A birthday under 13 when finishing sign-up (Google sign-ups aren't
  asked first) removes the new account without sending the details
  (`account-deleteAccount`, or the login alone if that can't be reached).

**Changed**
- The sign-up form's name field is now **Name on your profile**, said to
  be public; the legal name is asked separately and stays private.

## 0.7.0 — 2026-11-13

Communities and their teams. Needs API 0.6.0.

**Added**
- A community's page has a **Teams** tab listing its teams. Its member
  managers invite people to each one from there.
- A team's member managers invite people by name from **Roster**.

**Changed**
- **Teams** groups like the app: your teams first, then each community
  with its teams under it, folded when it has more than three. A team
  one of your communities lists sits only under the community.
  Read live from Firestore instead of `/v1/me/home`.

## 0.6.0 — 2026-11-12

Website parity, slice W2 (`docs/product-spec.md` §8.1): team pages as a
hub. Needs API 0.5.0.

**Added**
- Team and group pages are a hub with tabs in the URL: Feed, Schedule,
  Roster (Members for a group), and for members Chat and More.
- **Feed:** members see every post live, marked "Members only" where it
  isn't public; everyone else sees the public posts. "Coming up" beside it.
- **Schedule:** events down the left, the open one beside them
  (`?event=`): when, where (a map link), notes, and for members who's
  going, maybe or out, reactions and poll results. Members also get past
  events.
- **Roster:** anyone signed in sees the roster as a table (number, name,
  position) and the members with their roles, each linking to their
  profile, with a filter. Visitors are asked to log in.
- **Chat** (members): rooms by folder beside the open room (`?room=`),
  live, with replies, photos and reactions. Read only for now.
- **More** (members): the playbook drawn on a field, videos (YouTube plays
  in place), tracked games with the record, and hosted tournaments. A
  group's More is its tournaments.
- Join an open group, or ask to join one that approves members, from its
  page; members see their role there.

**Not yet:** posting to the team, RSVPs, votes and reactions, and sending
chat messages happen in the app until their API endpoints exist.

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
