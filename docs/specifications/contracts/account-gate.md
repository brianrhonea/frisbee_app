# Account gate contract (SEC-2, release-audit item #3a)

Status: **approved by the owner 2026-11-26 (D14).** No staff birth-date override (D16). Held on its branch until the Sprint 2 client work is ready; deploy order API → clients → rules.
Owner decisions this rests on: Q5 (email is limited to Firebase verification and
password reset) and Q6 (adult-only launch: 18+, enforced on the server).

Until an account has a verified email, a saved birth date that makes it 18 or
over, and the current Terms agreed, it can **read but not write**. The API and
both rules files enforce it; the clients only explain it.

## 1. Custom claims

Set by the API with the Admin SDK (`UserLookup.setClaims`, which merges into the
Auth user's existing claims so `staff` stays). Clients can never set them.

| Claim | Type | Set when | Notes |
|---|---|---|---|
| `ageOk` | `true` | a saved birth date (sign-up birth date or full details) makes the person 18 or over, counted in UTC+14 like every other age check | never set for under 18; never unset (the birth date is locked) |
| `terms` | number | the Terms are agreed (`PUT /v1/me/agreement`) | the version agreed; the API requires it to be at least the current `termsVersion`; the rules require a number of at least 1 |

Two claims, not one: the error can say exactly what is missing without a
database read, and a Terms version bump makes the API ask again without
touching `ageOk`. `email_verified` is Firebase's own claim; the API does not set it.

Constants: `ageOkClaim`, `termsClaim`, `accountGateFields`, `accountGateMessages`,
`adultOnlyMessage`, `birthDateLockedMessage` in `packages/shared/src/account_gate.ts`.

### Getting a fresh token

Claims reach the client only in a new ID token. When the API sets a claim it says
so: the response of `PUT /v1/me/personal`, `PUT /v1/me/personal/birth-date`,
`PUT /v1/me/agreement` and `GET /v1/me/personal/status` carries
`"refreshToken": true`. The client must then call `getIdToken(true)` (Flutter:
`getIdToken(true)`; web: `getIdToken(true)`) before its next write. The field is
absent when nothing changed. Also call `getIdToken(true)` after the user verifies
their email (that claim comes from Auth, not the API). Firestore and Storage see
the new claims on the next request made with the refreshed token.

## 2. Error for a gated write

`403` with code `account_incomplete` (a new `ApiErrorCode`, `apiErrorStatus` 403):

```json
{ "error": { "code": "account_incomplete",
             "message": "Verify your email address to continue.",
             "fields": { "email_unverified": "...", "age": "...", "terms": "..." } } }
```

`fields` holds one entry per missing requirement, always in this order:
`email_unverified`, `age`, `terms`. `message` is the first one's text. `age` covers
"no birth date saved" and "under 18" alike. The check runs before the body is
read, so a bad body from an incomplete account is a 403, not a 400.

### What a client does on `account_incomplete`

1. Call `GET /v1/me/personal/status` (never gated). If it says `refreshToken: true`,
   call `getIdToken(true)` and retry the write once (this is the migration path for
   accounts that already had everything, see section 5).
2. Otherwise route by `fields`: `email_unverified` to the verify-email screen
   (then `getIdToken(true)` and retry), `age` to About you (a birth date under 18
   is refused with 412 `failed_precondition`, message `adultOnlyMessage`: show a
   dead-end "Stall 10 is for players 18 and older" screen, do not loop), `terms`
   to the agreement step.
3. Never treat it as a sign-out: the session is fine.

## 3. API enforcement

Implemented in `registerAuth` (`apps/api/src/auth.ts`), so it covers every route
without each handler opting in:

- A signed-in caller on any method other than GET, HEAD or OPTIONS needs
  `email_verified`, `ageOk` and `terms >= termsVersion` in the ID token, or gets
  `account_incomplete`. Fail-closed: a new write route is gated by default.
- Reads (GET) stay open, including `GET /v1/me/personal`, `/agreement`, `/personal/status`.
- Public routes (`config.public`, such as the payment jobs) are not caller routes and are unaffected.
- Staff routes are gated too: a staff account must be complete.

**Exempt write routes** (route config `accountGate: "open"`), exactly what a new
account needs to finish onboarding plus its own settings:

| Route | Why |
|---|---|
| `PUT /v1/me/personal`, `PUT /v1/me/personal/birth-date` | give the birth date and details |
| `PUT /v1/me/agreement` | agree to the Terms |
| `PUT /v1/me/identity` | name and photo during onboarding |
| `POST /v1/me/username` | claim a username |
| `PUT /v1/me/profile/details`, `/profile/privacy`, `/profile/visibility`, `PUT /v1/me/message-policy` | own profile basics (the rules leave `profiles/{uid}` open too) |
| `PUT /v1/me/read-receipts`, `PUT /v1/me/notification-settings/category`, `/mute`, `DELETE /v1/me/notification-settings/teams/:teamId` | own preferences |

Not in the API at all (so nothing to exempt): account deletion is the
`deleteAccount` callable, and push device registration writes the user's own
`users/{uid}/devices` document directly (open in the rules, below). Neither is
touched by this change.

### Age and birth date

- `PUT /v1/me/personal` and `PUT /v1/me/personal/birth-date`: a birth date under
  18 is refused with `412 failed_precondition`, message `adultOnlyMessage`,
  `fields.birthDate`; nothing is stored and no claim is set. Under 13 keeps its
  own message (`tooYoungMessage`). A 13 to 17 year old is no longer asked for a
  guardian (the guardian is never kept now). The clients' own 13+ forms still
  exist until Sprint 2.
- **The birth date is locked once saved** (pentest P4). A save naming a different
  date than the stored one is refused with `412 failed_precondition`, message
  `birthDateLockedMessage`, `fields.birthDate`. Re-saving the same date, and
  changing every other detail, still works. This covers the sign-up date and the
  full details, both ways. Only deleting the account clears it. There is no
  support or staff override; if one is needed later it must be a staff-only,
  audited route (not built).
- `GET /v1/me/personal/status` response is unchanged apart from the optional
  `refreshToken: true`. The birth date is decrypted server side only while the
  caller's token lacks `ageOk`; it is never returned.

## 4. Rules enforcement (`firestore.rules`, `storage.rules`)

`accountOk()` = signed in, `email_verified == true`, `ageOk == true`, `terms` a
number of at least 1. (Rules can't know the current version, the API does.)
`readOrAccountOk()` is used where one rule covers both reads and deletes.

Required on **every create, update and delete** in Firestore and on **every
upload, metadata update and delete** in Storage, except:

| Path | Why open |
|---|---|
| `users/{uid}` (own doc, only the existing allow-listed fields) | sign-in details and onboarding; `agreedTerms` and everything else stay API-only |
| `users/{uid}/devices/*`, `settings/notifications`, `notifications/*`, `dmReads/*`, `chatReads/*` | push registration, own preferences, read markers |
| `profiles/{uid}` and `profiles/{uid}/private/*` (own), `usernames/*` create | onboarding: profile and username claim |
| Storage `users/{uid}/profile/*` | profile picture during onboarding |

Everything else is gated: teams (create, update, delete), joins, join and link
requests, invites, chats and messages, posts and comments, events and RSVPs,
videos, tournaments and entries, signups, payments docs, directories, follows
(and follow requests), calendars-related writes, conversations and typing,
invite codes; and all other Storage uploads (chat, DM, team post, team video and
user post photos). Reads are unchanged. Writes that were already `if false` stay.

A malformed claim (`terms` as a string, `ageOk` as `"true"`) is a deny.

## 5. Existing accounts (lazy backfill)

Accounts made before the gate have no claims. `GET /v1/me/personal/status` (never
gated) runs the same sync the saves do: it opens the stored birth date and the
`users/{uid}.agreedTerms` record, sets `ageOk` and `terms` for whichever the
records already earn, and answers `refreshToken: true`. So an existing account
with details and agreement saved needs one status call and one token refresh, then
works as before. Clients should call status once at sign-in / app start and
refresh the token if told to.

What existing dev accounts will see:

| Account | Experience |
|---|---|
| 18+, details and agreement on file, email verified | one status call, one token refresh; nothing visible |
| 18+, never agreed to the Terms | writes refused with `terms`; the agreement step already exists |
| 18+, no personal details (older than the 2026-11-14 cutoff, "may wait") | writes refused with `age` until they fill in About you |
| 13 to 17 | **permanently read-only**: no `ageOk`, writes refused with `age`, and the 18+ rule refuses any new birth date. They cannot be fixed by the user (the birth date is locked). Needs an owner decision (data clean-up, or a support route) |
| email not verified (email/password accounts that never verified) | writes refused with `email_unverified` until they verify |
| Google or Apple accounts | `email_verified` is true from the provider |

## 6. Email (Q5)

Searched `apps/api/src` and `firebase/functions/src` for mail libraries, SMTP,
mail collections and link generators: **none found**. The only email the project
causes is Firebase Auth's own verification and password reset. One thing to
confirm outside the code: payment calls pass the payer's email to Stripe
(`payments/service.ts` lines 363, 534, 619) to prefill Checkout; whether Stripe
then emails receipts is a Stripe Dashboard setting. Payments are off for launch.

## 7. Sprint 2 client work

Both platforms (app and website, exact parity, mirrored tests):

1. Treat `account_incomplete` (403) as a first-class error: follow section 2.
2. Call `GET /v1/me/personal/status` after sign-in; on `refreshToken: true` call
   `getIdToken(true)`. Do the same after the save-details, birth-date and
   agreement responses carry `refreshToken: true`.
3. Refresh the token after the user verifies their email.
4. Birth date forms: 18+ only (current forms accept 13+ and ask for a guardian);
   show `adultOnlyMessage` on the 412; no guardian step; the birth date field
   becomes read-only once saved (the API refuses changes), with a "contact
   support" hint.
5. `PersonalGate` fails closed (audit item #3): on an error from the status call,
   block with a retry screen instead of letting the user through.
6. Anything that writes Firestore or Storage directly before onboarding
   completes (other than the open paths in section 4) will now fail with
   permission-denied: audit those flows (for example profile photo upload is
   open; chat and post uploads are not).

## 8. Operational notes and risks

- **Deploy order**: API first (it sets the claims and enforces), clients next, rules
  last. Deploying the rules before every active account has a claim locks them out
  of direct writes until they call status and refresh. Because most writes go
  through the API in the old clients too, deploying rules to dev after the API is
  the safe order. Owner approves every deploy.
- Claims are only as fresh as the ID token (up to an hour); clients refresh on
  the API's say-so, so the delay is not user-visible in the normal flow.
- `setClaims` is read-modify-write on the Auth user's claims; a concurrent claim
  change to the same user (for example granting `staff` at the same moment) could
  lose one. Accepted: staff grants are rare manual operations.
- App Check (the other half of SEC-2 in the audit) is separate and not part of this change.
- The Firebase Auth emulator integration tests (`pnpm test:emulator`) mint tokens
  with `ageOk` and `terms` custom claims and verified emails for the same reason.
