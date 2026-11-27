# Signed-in browser tests (emulators, synthetic data)

Never real projects, never secret files. Everything uses the `demo-stall10` project.

1. Emulators (from the repo's `firebase/` folder; needs Java):

       firebase --config firebase.json emulators:start --only firestore,auth,storage --project demo-stall10

2. The API on port 8788, against the emulators (from `apps/api`, after `pnpm --filter @stall10/shared build`):

       FIREBASE_PROJECT_ID=demo-stall10 FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
       FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 \
       STORAGE_BUCKET=demo-stall10.appspot.com PORT=8788 TRUST_PROXY_HOPS=0 \
       CORS_ORIGINS=http://localhost:3102 \
       PERSONAL_DETAILS_LOCAL_KEY=$(node -e "console.log(require('crypto').randomBytes(32).toString('base64'))") \
       pnpm exec tsx src/server.ts

   (Run `tsx` directly, not `pnpm dev`, which loads `.env`.)

3. The tests, from `apps/web`: `E2E_WORLD=1 pnpm exec playwright test --project=world-setup --project=world-375 --project=world-1440`.
   The setup project clears both emulators, seeds the world (`seed.mjs`: Ada, Ben, Cam, two teams with chat,
   events single and weekly, posts, DMs, notifications, a community, an unmarked minor profile) and signs Ada in
   through the real form. The website is started on port 3102 with the emulators' env values.
   `REVIEW_PHASE=before|after` names the screenshots, which land in `<worktree>/review/web/H*/`.

The API limits "who am I" checks to 10 a minute per account, so these tests run with one worker and space page loads out.
