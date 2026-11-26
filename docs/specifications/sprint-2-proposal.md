# Sprint 2 (Nov 27 – Dec 11, 2026)

**Status:** approved by the owner on 2026-11-26, together with **Q19** (minimum-version gate and video-upload flag) and **Q15** (Crashlytics in the app, Cloud Error Reporting on the website; no new vendor).

**Baseline:** `feature/jan-4-release` at `344b2eb`. The #3a client work starts from `hold/3a-account-gate` at `9865cd4`, which is the release branch plus #3a.

**Capacity:** the owner has about 20 h a week, about 40 h for the sprint, of which about 15 h goes to reviews and device checks and about 6 h is held for defects. Agent work is about 55 h.

## Items

| # | Item | P | Lane | h | Depends on | Done when |
|---|---|---|---|---|---|---|
| 3a-S | Fixes from the #3a security review, on the held branch | P0 | A | 3 | Review | Reviewer re-checks |
| 3a-C | App and website handle `account_incomplete`: status call, token refresh, one retry, then route to verify email, birth date or Terms. A dead-end 18+ screen. Sign-up forms for 18+ only, no guardian step. The birth date is read-only once saved. Token refresh after email verification | P0 | B + C | 10 | Contract (approved) | Widget and component tests per error. **Owner device check:** new sign-up, verify, post |
| 3a-R | Release #3a to dev: merge, then API, then TestFlight build and website, then rules last | P0 | Orchestrator | 2 | 3a-C, 3a-S | Owner OK for each deploy |
| 14 | Photo screening fails closed; DM attachments checked against the conversation and blocks | P0 | A | 6 | — | Rules and functions tests |
| 6 | Minimum-version gate: `meta/flags.minBuild` and an "Update required" screen on the app and website | P0 | A + B + C | 5 | Q19 ✔ | Unit and widget tests |
| 13 | Native video upload behind a server flag (`meta/flags.videoUploads`); short-lived signed URLs | P0 | A + B | 3 | Q19 ✔ | Widget and rules tests |
| 7 | Crash reporting: Crashlytics in the app, startup guard; `global-error.tsx` plus Cloud Error Reporting on the website | P0 | B + C | 6 | Q15 ✔ | A forced test crash shows up (device) |
| K6 / K7 | Text, spacing, corner and motion tokens on both platforms | P1 | B + C | 6 | — | K8 has 0 skips; goldens and screenshots reviewed |
| C1–C4 | Status pill, buttons, segmented tabs and chips, avatar and team logo, on both platforms | P1 | B + C | 12 | K6/K7, **owner visual OK on K2–K5** | Widget, golden and component tests; UI review |
| 24 | Home feed shows load errors instead of "caught up" | P2 | B | 1 | — | Widget test |
| INF-1 | Turn off App Store auto-submit in `codemagic.yaml` | P0 | Release | 1 | — | Config reviewed |

## Lanes (at most 3 implementation agents; no shared files)

| Lane | Owns |
|---|---|
| A, backend | `apps/api`, `firebase/**`, `packages/shared` |
| B, Flutter | `apps/mobile` |
| C, website | `apps/web` |
| Release | `codemagic.yaml` |

**Order:**
- The `meta/flags` contract comes before the clients' parts of #6 and #13.
- 3a-S lands on the held branch before 3a-R.
- K6/K7 come before C1–C4.

## Owner answers (2026-11-26)

- **Q9:** the Jan 4 beta runs on **dev**. Prod stand-up (#9, #11, #12) is needed only for the Jan 18 public release, so it moves to Sprint 3–4.
- **Q14: yes**, separate dev and prod iOS bundle IDs before the beta. This is planned for Sprint 3 and needs owner console steps:
  - a new App ID and TestFlight app;
  - the iOS app registered in the dev Firebase project;
  - its config file placed by the owner.
- **Android:** not in the beta. #10 moves after the beta.

## Still open

- Visual OK on K2–K5.
- Q16 and Q17 for later sprints.

## Not in this sprint

- #9 prod stand-up, #11 backups, #12 alerts: Sprint 3, after Q9.
- #17 and #25 (writes through the API, rules lockdown): Sprint 3–4.
- #26, #27, #29, #30.
- Shells S1–S3, navigation N1–N12, screens H/Q/L.
- #10 Android.
- New board features (L3).
