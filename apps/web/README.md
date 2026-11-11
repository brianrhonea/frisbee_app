# apps/web — Stall 10 website (phase 3)

Next.js 16 (App Router) on Vercel. It replaces the Flutter web build that
Firebase Hosting serves today (`firebase/scripts/build_site.sh`); every
platform other than iOS and Android uses it.

## What's here

| Path | What |
|---|---|
| `/community`, `/posts/[id]` | The public feed and one post |
| `/players/[uid]`, `/teams/[id]` | Public profiles (private ones show only their card) and team/group pages |
| `/events`, `/explore?q=` | Upcoming public events and tournaments; player and team search |
| `/about`, `/help`, `/terms`, `/privacy`, `/cookies`, `/delete-account` | Static pages ported from `firebase/hosting` (`content/*.html`, served by `app/[slug]`) |
| `/join/[code]`, `/g/[id]`, `/p/[id]` | Invite and share link fallbacks; `public/.well-known` opens them in the app |
| `/sign-in`, `/sign-up` | Firebase Auth (email/password, Google) |
| `/home`, `/profile` | Members-only placeholders; the member area comes next |

- **Reads:** server components call the API's public routes
  (`lib/api.ts` → `GET /v1/public/*` at `API_BASE_URL`), cached 60 seconds.
  The server sends `x-stall10-web-key: WEB_SERVER_KEY`, so the API doesn't
  rate-limit it as a single visitor; Vercel's firewall limits visitors.
- **Writes:** none yet. Member actions will go through the API with the
  user's ID token. The browser uses Firebase only to sign in, and later
  for live listeners (chat, feeds, live stats).
- Types come from `@stall10/shared` (`browse.ts`).
- Styles: `app/site.css` (ported from `firebase/hosting/site.css`, follows
  the system's light/dark setting) and `app/app.css`.

## Running

```
cp apps/web/.env.example apps/web/.env.local   # fill in; never commit it
pnpm install
pnpm dev:api                                   # the API on :8787
pnpm --filter @stall10/web dev                 # the site on :3000
```

Against the emulators: start `firebase emulators:start` in `firebase/`,
point the API at them (`apps/api/.env`), and set
`NEXT_PUBLIC_FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099` to sign in there.

## Vercel

- Root Directory `apps/web`. Vercel detects the pnpm workspace; if
  `@stall10/shared` isn't built first, set the build command to
  `pnpm --filter @stall10/shared build && next build`.
- Environment variables: those in `.env.example`. Previews use the dev
  Firebase project and dev API; production uses prod.
- In Firebase Auth (each project), add the Vercel domains to
  **Authorized domains**, or sign-in fails with "isn't set up for this web
  address".
- Add a firewall rate-limit rule for visitors (the API trusts this server
  through `WEB_SERVER_KEY`).
- Keep store URLs in step: `lib/site.ts`, `apps/mobile/lib/config/store_links.dart`.
