# Website audit: apps/web (web 0.59.5, `39c8a53`)

Read-only audit. I ran no tests (typecheck already passed today).

**What I read in full:** `lib/` (api, client, live, firebase, calendar, the outbox's load and auth handling), `AuthForm`, `AuthProvider`, `PersonalGate`, `MembersOnly`, the staff pages, `Payments` and `PaymentPages`, `FollowingSettings`, `Notifications`, `CalendarSettings`, `app/` routes and config, and the legal HTML.

**Not read in depth:** `TournamentPage`, `Schedule`, `GamePage`/`useTracker`, `Messages` and `TeamChat`. I checked those by grep only.

**CONFIRMED** means I read the code at that line. **SUSPECTED** means I inferred the behaviour.

Overall, the code is disciplined:
- I compared `callApi` counts against catch counts in every file. The files I opened all wrap calls in `run()`/`try` or a two-argument `.then`.
- A multiline grep found no `onClick` on a `div`, `span`, `li`, `td` or `p`.
- A grep for unlabelled `icon-btn` buttons found none.
- Modals use native `<dialog>` + `showModal()`.
- Live reads return `error` and `denied`.
- Storage access is wrapped in `try`.

Most defects are fail-open gates, swallowed errors and missing infrastructure (tests, error reporting).

## Readiness table

| Area | Web state | Jan 18 | Evidence / gap |
|---|---|---|---|
| Sign-in / sign-up | Email or username, Google, Apple, reset (`AuthForm.tsx:196,257`) | Fix | No `sendEmailVerification` in the web code (C-26). Gates are client-side only (W-B1) |
| Profiles, follows | `players/[uid]` members only (`page.tsx:13`) | Ready | W-B4 |
| Feed, posts, comments | Comments are read only when signed in (`Comments.tsx:47`) | Ready (not reviewed in depth) | — |
| Teams, roster, roles | `TeamContext.tsx:134-140` (outsider/denied), `SectionGate` | Fix | W-B8 |
| Communities, hat tournaments | `CommunityTeams.tsx`, `group_tournaments/*` | Ready (not reviewed in depth) | — |
| Chat / DMs | Done; IndexedDB outbox | Fix | W-B2 |
| Meetings (LiveKit) | Room, watch-together | Ready, device check needed | W-B6 |
| Schedule, RSVP, ICS | ICS download, feed URL with Reset and Turn off (`CalendarSettings.tsx:431,442`) | Ready | W-B5 |
| Discover, public pages | Server-rendered, `revalidate = 60` | Fix | W-B8 |
| Tournaments / leagues | Done | Ready (not reviewed in depth; needs an E2E run) | — |
| Payments / payouts | Hidden until the API says `available` (`Payments.tsx:248,365,527`) | Off | Keep the server switch off |
| Notifications | Feed, no web push | Fix | W-B4 |
| Moderation | `Report.tsx`, `team/TeamReports.tsx`, `StaffQueue.tsx` | Ready | — |
| Staff `/staff` | Queue + payments | Gate | No MFA or scoped roles (C-27); W-B7 |
| Stats | Done | Fix | Whole-document saves (C-38). Player ratings from self-written stats shown to members (`Rankings.tsx:247`, pentest P7) |
| Playbook / videos | YouTube links only | Fix | Parity 1 |
| Settings, deletion, export | `settings/DownloadData.tsx`, `AccountSettings.tsx` | Ready (not exercised) | — |
| Legal pages | Drafts | Gate | W-B3 |

## Bugs & incomplete workflows

| ID | Sev | Status | Location | Scenario |
|---|---|---|---|---|
| W-B1 | P0 | CONFIRMED | `components/PersonalGate.tsx:63-80, 99-122`; API `account/service.ts:131-145`, `personal/service.ts:54` | Any error on `/v1/me/personal/status` or `/v1/me/agreement` sets `status` or `agreed` to `null`. The gate blocks only on `agreed === false` or `status.required`, so it fails open. The API reads `agreedTerms` and `personalDetailsRequiredSince` only in those status routes, never on writes. A new account hit by an API blip, or one calling the API directly, can post and message without accepting the Terms or giving a birth date. Related to pentest P4 and P0-04. |
| W-B2 | P1 | CONFIRMED | `lib/outbox.ts:29,121-124`; `AuthProvider.tsx:27`; `HeaderAuth.tsx:34` | Unsent DMs and posts, with their text previews, stay in IndexedDB `stall10-outbox` after **Log out**. On a shared computer the next person can read them. The outbox's auth listener only re-emits and drains; it never deletes jobs. Log out also gives no warning that items are unsent. |
| W-B3 | P0 | CONFIRMED | `content/privacy.html:5,14,123,161,182`; `terms.html:5,10,63,142`; draft banners in `cookies.html:5`, `delete-account.html:2-6`, `guidelines.html:5` | Public pages show "Draft" banners and `[bracketed]` placeholders, such as "[legal name of the…]". `terms.html:53-134` describes paid fees and payouts, which a free-only launch doesn't offer. |
| W-B4 | P3 | CONFIRMED | `settings/FollowingSettings.tsx:105,109`; `Notifications.tsx:58,83-88,117-130` | Follow Notify and Unfollow use `.catch(() => undefined)`, so a failure gives no message, and Unfollow has no busy state. Mark read and Clear swallow errors the same way. The unread badge reads at most 100 unread notices, then drops chat and DM notices (`isMessages`, line 58). A member with 100+ unread chat notices sees 0 even if other unread notices exist. |
| W-B5 | P3 | CONFIRMED | `settings/CalendarSettings.tsx:311`, with `run` at `68-79` | `run` catches the error itself, so `.then` always runs. A failed "New calendar" closes the form and clears the typed name. |
| W-B6 | P3 | CONFIRMED | `team/meetings/WatchTogether.tsx:199` (file player: `play: () => v.play()`, line 311); `CalendarSettings.tsx:407` | `void player.current?.play()` (autoplay `NotAllowedError`) and `void navigator.clipboard?.writeText()` have no rejection handler, so they cause unhandled rejections with no feedback. |
| W-B7 | P3 | CONFIRMED | `app/staff/page.tsx:11-19`; `StaffPayments.tsx:54-61,107`; `StaffQueue.tsx:~74` | A non-staff member sees the "Reports" and "Payments" headings. Under "This page is for Stall 10's staff", `problem(e)` shows the API's 403 message. The staff note input has only a placeholder, no label. |
| W-B8 | P2 | CONFIRMED | `lib/api.ts:19`; `app/api/revalidate/route.ts:9` (no `team:` tag); `app/teams/[teamId]/roster/page.tsx:23` (untagged); `lib/teamPage.ts:6` | After a team switches to youth or turns its public page off, visitors still get the cached team page and adult roster (players' names) for up to 60 s, plus any API-side TTL. The API can't expire these entries early because the route accepts no team tags. |
| W-B9 | P1 | CONFIRMED | `app/error.tsx` ignores `error`/`digest`; there is no `app/global-error.tsx` | Render failures are never reported (C-32), and an error in the root layout shows Next's default page. |
| W-B10 | P3 | SUSPECTED | `app/app.css:674` | `.composer textarea:focus { outline: none }` on a borderless field, with no `.composer:focus-within` rule. Keyboard users get no focus indicator (WCAG 2.4.7). |

**Signed-out Firestore reads:** no leak found in the web code.
- **Gated by sign-in:**
  - `Comments.tsx:47`
  - `useTournamentDays.ts` (`uid` required, line 17)
  - `useForYou.ts:88`
  - `TeamContext.tsx:134`
  - `PersonPicker` (used only in Messages, Schedule and Calendar settings, behind `MembersOnly`)
- **Through the API, not Firestore:** `usePublicEvents.ts:18`.
- **Rules check:** `profiles` list is allowed to any signed-in user, capped at 50 (`firestore.rules:2696`). Private profiles keep only their card. The Firestore rules themselves belong to the security review.

## Parity gaps

This is a sample, not an exhaustive check. I checked about 15 features in both directions against the 59 `*_screen.dart` files.
- **App to web:** pins, room settings, group members, share card, team reports, roles, export, change password and the calendar feed.
- **Web to app:** watch-together, read receipts, message policy, earnings and player rankings.

All of those exist on both platforms. The gaps:
1. **Video file upload is app only.** The web says "upload a video file in the app" (`team/videos/TeamVideos.tsx:220`). The app uploads straight to Storage without screening (P0-05). Resolve it by hiding the app's upload, not by adding one to the web.
2. **GPS workout recording is app only.** This is an accepted device exception.
3. **Push notifications and the device-permissions panel are app only.** This is accepted.
4. **The staff portal is web only.** This is accepted.

## Tech debt

- **Large files:** `app/app.css` 1,859 lines, `TournamentPage.tsx` 1,043, `Schedule.tsx` 968, `stats/GamePage.tsx` 954, `TournamentForm.tsx` 944, `Messages.tsx` 836, `TournamentEditor.tsx` 828.
- **Hardcoded colours:** usage is mostly tokenised. About 40 hex values sit outside the token definitions:
  - `app.css:1011-1049`
  - `voice/voice.css:9-22`
  - `team_hub.css:305-308`
  - `SideTeams.tsx:15`
  - `Payments.tsx:187`, which duplicates `--accent` for Stripe

  There are also 26 `rgb()`/`rgba()` values and 24 inline `style={{}}` uses.
- **Breakpoints are ad hoc:** 480, 560, 640, 720, 760, 860, 900 and 1000 px.
- **Dialogs:** 67 `window.confirm` and about 10 `alert` calls against a themed `Dialog` that only 15 files use.
- **ARIA tabs:** 19 `role="tab"` but arrow keys only in `Dashboard.tsx:174`.
- **Raw error messages:** about 40 sites show `(e as Error).message`. For API failures that is the API's own wording (`ApiError`), so it's usually fine, but Firestore or SDK errors would show raw text (SUSPECTED).
- **No ESLint:** there's no ESLint dependency in `apps/web/package.json` or the root `package.json`, so 17 `eslint-disable … react-hooks/exhaustive-deps` comments have no effect.
- **No `loading.tsx` routes:** the server-awaited team and tournament pages show no skeleton while loading.
- **Thin CSP:** `next.config.ts` sets only `frame-ancestors`, `base-uri` and `object-src`, with no `script-src` or `connect-src`. The only `dangerouslySetInnerHTML` uses are static repo HTML and a local QR SVG.
- **Client components:** 202 of the 318 files start with `"use client"`. That's largely justified because the data is member-scoped.
- **Dependencies:** `next 16.4.6`, `react 19.3.1`, `firebase ^13.2.0` (resolved 13.2.0), `livekit-client 2.23.0`. Most are pinned exactly; `firebase`, `typescript` and `@types/*` use caret ranges. I couldn't check them against advisories offline. Add `pnpm audit` to CI.
- **Tests:** the website has **no tests at all**: no component tests, no Playwright, no a11y checks. The root `pnpm test` excludes `@stall10/web` (`package.json:10`), and CI only typechecks and builds it (`ci-node.yml:46`). Nothing covers the auth gates, the outbox, the `safeNext` open-redirect guard (`AuthForm.tsx:67-79`), the `/api/revalidate` key check, or `lib/live.ts`.

## Suggested issues

| Title | Pri | Hours |
|---|---|---|
| Enforce Terms agreement and the adult or birth-date gate on API writes; make `PersonalGate` fail closed with a retry (W-B1) | P0 | 8 |
| Fill the legal placeholders, remove the draft banners, align the terms with a free-only launch (W-B3; lawyer time extra) | P0 | 4 |
| Website error reporting: `global-error.tsx` and reporting in `error.tsx` (W-B9) | P1 | 4 |
| Clear the outbox on Log out; warn when items are unsent (W-B2) | P1 | 3 |
| Web test harness (Vitest + RTL) plus Playwright smoke tests for sign-up, gates, RSVP, chat send and a visitor team page, in CI | P1 | 16 |
| Add `team:`/`roster:` cache tags; have the API send them on visibility changes (W-B8) | P2 | 4 |
| Show swallowed errors: Following, Notifications, calendar form, clipboard, `play()` (W-B4–B6) | P2 | 4 |
| Accessibility pass: focus indicators, ARIA tabs keyboard support, axe in Playwright (W-B10) | P2 | 6 |
| ESLint with `react-hooks` and `jsx-a11y` in CI | P2 | 3 |
| Full CSP, in report-only mode first | P2 | 4 |
| Staff page: hide sections for non-staff, label the note input (W-B7) | P3 | 1 |
| Replace `window.confirm`/`alert` with `Dialog`; put remaining colours on tokens; one breakpoint scale | P3 | 10 |
| Split `TournamentPage`, `Schedule`, `GamePage` and `app.css` | P3 | 12 |
