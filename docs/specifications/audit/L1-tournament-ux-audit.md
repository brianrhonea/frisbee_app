# L1 tournament page UX audit (2026-11-27)

Read-only audit on `feature/jan-4-release` by the ui-ux-reviewer agent. No screens were run, so contrast, tap sizes and 200% text are read from code and need device or browser checks.

## Summary

The tournament page already has nearly everything; the problem is order and emphasis.

1. One page, six tabs (Overview, Players, Teams, Schedule, Results or Standings, News), one layout for every role. It opens on Overview, or Schedule while live. A scheduled event on game day still opens on Overview.
2. Fans get one flat, time-ordered list of every game, with no "Live now" grouping and no jump to now. Reported but unconfirmed games show no score.
3. A captain's next game, report and confirm sit in two places on the app (Overview guide card, Schedule "Your game" card). The guide's "Report the score" button only switches tabs. On the website "my games" is captains only and there's no guide card.
4. The host's Overview checklist covers setup. During play there's no list of games needing action (reported and unconfirmed, past start with no score). The publish dialog says "You can still move games", but no move-game endpoint or screen exists.
5. The website lags the app for non-captain players and live scores (visitors refresh every 60 s).

Check-in, spirit scores, per-game reschedule, per-game push alerts and public unconfirmed scores do not exist; any of them is new behaviour.

## Today, by role

Roles (both platforms): host = manageEvents on the host team (app `hosted_tournament_viewmodel.dart:400`, web `useTournament.ts:48`); team member = `myTeamIds` (vm :552, web :60); captain = `division.captains` (vm :1313, web :91). Only captains report, confirm and keep live scores (vm :1328, :1374); the host sets or corrects finals (vm :1355). Signed-out visitors get a read-only page on the web (`PublicTournament.tsx:91`); the app has no visitor mode.

### Fan
- Live score: navy header shows one live game plus "+N more" (`event_page_header.dart:202-235`; web `TournamentPage.tsx:167`).
- All games: Schedule, one list per day (`hosted_tournament_screen.dart:1790-1874`; web `TournamentGames.tsx:537-547`); no scroll to now; scores only when done (`tournament_parts.dart:389`).
- Standings: Results tab; app pools table lacks PF/PA and the tiebreak rule isn't explained (`tournament_engine.ts:160-202`).
- Bracket: Results, then scroll or Open bracket (screen :2740-2808), sideways 300 px columns.
- Division chips repeated per tab (screen :459-487); no "everything live" view.
- Web visitors: 60 s refresh (`PublicTournament.tsx:31`), sign-up banner on every tab, tab not in the URL (`TournamentPage.tsx:78`).
- Empty Schedule/Results are bare text, not EmptyState; no offline state on either platform.

### Player or captain
- Next game: app guide card (`event_guide.dart:410-443`), Schedule "Your game" card (screen :1997-2127), "Your next games" (:1831). Web: captains only (`useTournament.ts:139`).
- No "my schedule and results" view on either platform; own standing only on the Home day card (`tournament_day_card.dart:70-73`).
- Report/confirm reachable three ways, all ending in the same sheet (screen :2306-2584). Wording is clear; keep it.
- Two teams in one event: only the first is surfaced (`event_guide.dart:410`, vm :1346).
- Overview puts fees, roster and invite replies far down (screen :672-825). Withdraw/Decline are small text buttons beside Roster (:1137-1202).

### Host
- Needs attention: guide card plus Next steps (`event_guide_cards.dart:222`; web RunEvent `TournamentPage.tsx:299-506`), setup only.
- Publish reachable from three places (Teams, Overview, Schedule PublishCard :2138-2272).
- Scores: open a game, "Set final score" or "Correct the score" (:2545-2562).
- Schedule changes: only Regenerate, which wipes scores (:2158-2255); no move-game API (`apps/api/src/tournaments/routes.ts:43-97`); misleading publish copy (:626-628).
- Check-in: none. Messaging: chat per team row, Captains' channel, News FAB.
- Bracket advance depends on a manager's open page (web `useReconcile`, app VM equivalent); worth a server check later.
- Unlabelled popup menus (:901, :1310, :1516); Delete beside Edit (:304-314).

### Layout and accessibility (from code)
- Many labels 11–12.5 px (`tournament_parts.dart:353,371`); approved base 16, 14 in dense lists.
- Game rows lack a merged screen-reader label; scores don't say which team; winner shown by weight only.
- Header clipped at large text (`event_page_header.dart:42-87,287`).
- Web tabs are buttons, not a tablist; about 44 px tall; live-score minus 44 px (`tournaments.css:227`).
- Navy board header, dark day card, amber and red accents sit outside zinc + indigo: owner ruling needed.
- Web desktop is one stacked column; no side-by-side Schedule and Standings.

### Parity gaps
Guide card and next game (web missing); member-based "mine" highlight (web captains only); live streaming vs 60 s; pools columns; publish copy; route names (/respond vs /enter); visitor banner web-only; champion highlight.

## Proposed role-based layout (REARRANGE unless marked NEW)

Same URL and tabs for everyone; the role changes what sits at the top. Host wins, but a host who also plays sees the player card too.

**Viewer:** open on Schedule when live or on game day; header shows up to three live games; Schedule order: Live now, Latest results, Up next, All games with Jump to now; Results: standings, then bracket, then final standings once finished.

**Team member or captain:** Overview starts with one "My team" card (record, pool place, next game time/field/opponent, and the one action that applies: Report score, Confirm, Waiting for the other captain, Respond to invite, Pay fee, Finish roster), and the button opens the game sheet directly. Schedule gets "My games / All games" for every member, with a team switcher for two teams. Drop the duplicate Your game card when My team is on screen.

**Host:** Overview starts with "Needs attention" by urgency: teams waiting, roster or fee missing, seeds to confirm, ready to publish, and during play scores waiting for confirmation and games past start with no score. One primary Publish there. Quick links: Message captains, Post update, Edit details; Delete in an overflow with confirm. NEW (small): a badge on the Schedule tab for games needing host action.

**Navigation:** keep the six tabs; sticky division bar shared by Schedule, Results and Teams; web tab in the URL, role="tablist", 48 px tabs; web desktop Schedule and Standings side by side. Live score entry unchanged (raise the web minus to 48 px).

**Accessibility pass:** merged game-row labels, labelled menus with team names, text sizes, 200% header check, 48 px targets.

**Copy fixes:** the "move games" line; matching app and web publish text.

## Owner decisions

1. NEW: show reported but unconfirmed scores publicly as "Pending confirmation".
2. NEW: per-game time/field edits with a "moved" alert (at minimum fix the copy).
3. NEW: check-in.
4. NEW: spirit scores.
5. NEW: "your team is up" push alerts.
6. NEW: live streaming for web visitors (keep 60 s for January otherwise).
7. Policy: keep the navy header, dark day card and amber/red accents as exceptions?
8. Policy: may non-captain team members report scores (today captains only, enforced by the API)?
9. Rename Overview to Home?

Not covered: leagues beyond the shared page, the form/draft/sign-up/respond screens in depth, the mock-up boards and baseline pictures.
