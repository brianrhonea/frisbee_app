# apps/web — Stall 10 website (phase 3)

Next.js (App Router) deployed on Vercel. It replaces the Flutter web build
that Firebase Hosting serves today (`firebase/scripts/build_site.sh`).

- Talks only to the API (`apps/api`) at `NEXT_PUBLIC_API_BASE_URL`, signing
  members in with Firebase Auth and sending their ID token. No Firestore
  access from the browser.
- Uses types and schemas from `@stall10/shared`.

```
pnpm --filter @stall10/shared build
pnpm --filter @stall10/web dev
```

Vercel: set the project's Root Directory to `apps/web`; Vercel detects
pnpm workspaces and builds `@stall10/shared` through the workspace
dependency (add `pnpm --filter @stall10/shared build &&` to the build
command if it doesn't).
