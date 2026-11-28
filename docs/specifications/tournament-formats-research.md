# Tournament formats: reference notes (2026-11-27)

Owner asked to compare our engine with published ultimate tournament formats. Source read: the UPA Manual of Tournament Formats, version 2.1 (1993), https://www.cs.rochester.edu/u/ferguson/ultimate/upa-formats/upa-formats-all.html. USA Ultimate also hosts a later copy (version 4.3, 2008): https://usaultimate.org/wp-content/uploads/2020/11/USAU_TournamentFormats.pdf (not read). These are references for general structure only, in our own words: no USA Ultimate data, names or documents go into the product.

## Common patterns

- **Seeding into two pools:** snake. Pool A gets seeds 1, 4, 5, 8, 9, 12; pool B gets 2, 3, 6, 7, 10, 11. Three pools snake the same way (A1 B2 C3, then C4 B5 A6...).
- **Pool sizes:** pools of four to six are preferred; pools of three are discouraged.
- **First bracket round mixes pools:** 8 teams in two pools of four give A1 v B4, B2 v A3, A2 v B3, B1 v A4.
- **Pool winners get byes, others cross over:** 10 teams in two pools of five give crossovers A2 v B3, A3 v B2, A4 v B5, A5 v B4, with A1 and B1 waiting. 16 teams in four pools of four give crossovers A2 v B3, B2 v A3, C2 v D3, D2 v C3, with pool winners waiting.
- **Two tiers:** with many teams, the top two of each pool play a championship bracket and the rest a second bracket, so everyone keeps playing for places.
- **Placement games** (5th, 7th, and so on) come from the bracket's losers.
- **Pool tiebreakers, in order:** head-to-head among the tied teams; point difference among the tied teams; point difference against common opponents; points scored among the tied teams; points scored against common opponents; then a disc flip. When a rule splits a tie, start again within each smaller group.
- **Game load:** up to four games per team per day, with roughly two-hour slots.

## How our engine compares

| | Our engine today | Reference pattern |
|---|---|---|
| Pool seeding | Snake (8 teams: A = 1, 4, 5, 8; B = 2, 3, 6, 7) | Same |
| First bracket round | Pairs 1st seed with last seed, often from the same pool (A1 v A4) | Always across pools (A1 v B4); see board BR1 |
| Crossovers | Same-pool (A2 v A3) with 4 pools of 3 | A2 v B3, B2 v A3 |
| Byes | Top seeds, only when the bracket isn't full | Pool winners wait while others cross over, chosen by the format |
| Tiebreakers | Wins, head-to-head, point difference, points scored | Head-to-head, then point difference and points among tied teams, then common opponents, restarting within subgroups |
| Two tiers | Placement format plays every place | Championship and second brackets |
