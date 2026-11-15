// The app's team builder, seeded generator and snake order against
// drafts.ts and groupEngine, on the vectors in fixtures/drafts (written by
// apps/mobile/test/shared_fixtures/drafts_fixtures_test.dart). The same
// seed has to deal the same teams on the app and the website.
import { describe, expect, it } from "vitest";
import {
  autoPick,
  balancedDraft,
  blankTeams,
  type DraftedTeam,
  type DraftPlayer,
  draftTeamOf,
  groupEngine,
  leagueTeamName,
  movePlayer,
  onTheClock,
  pickProblem,
  seededRandom,
  signupOrder,
  snakeIndex,
  startProblem,
  teamsFromDraft,
} from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

describe("the seeded generator matches the app (fixtures/drafts/seeded_random.json)", () => {
  it.each(fixture<{ seed: number; doubles: number[]; ints: number[] }>("drafts/seeded_random.json").cases)("seed $seed", (c) => {
    const r = seededRandom(c.seed);
    expect(Array.from({ length: 10 }, r)).toEqual(c.doubles);
    const s = seededRandom(c.seed);
    expect(Array.from({ length: 10 }, () => Math.floor(s() * 10))).toEqual(c.ints);
  });
});

describe("balanced drafts match the app (fixtures/drafts/balanced_draft.json)", () => {
  it.each(
    fixture<{ name: string; players: DraftPlayer[]; teams: DraftedTeam[]; seed: number; mixed: boolean; expected: DraftedTeam[] }>(
      "drafts/balanced_draft.json",
    ).cases,
  )("$name", (c) => {
    expect(balancedDraft(c.players, c.teams, { seed: c.seed, mixed: c.mixed })).toEqual(c.expected);
  });
});

type BuilderCase =
  | { kind: "dealPlayers"; players: Array<{ uid: string; name: string }>; teams: DraftedTeam[]; seed: number; expected: DraftedTeam[] }
  | { kind: "blankTeams"; count: number; existing: DraftedTeam[]; expected: DraftedTeam[] }
  | { kind: "movePlayer"; teams: DraftedTeam[]; player: { uid: string; name: string }; teamId: string | null; expected: DraftedTeam[] };

describe("team building matches the app (fixtures/drafts/team_builder.json)", () => {
  it.each(fixture<BuilderCase>("drafts/team_builder.json").cases.map((c, i) => ({ ...c, i })))("$i: $kind", (c) => {
    switch (c.kind) {
      case "dealPlayers":
        expect(groupEngine.dealPlayers(c.players, c.teams, seededRandom(c.seed))).toEqual(c.expected);
        break;
      case "blankTeams":
        expect(blankTeams(c.count, c.existing)).toEqual(c.expected);
        expect(groupEngine.blankTeams(c.count, c.existing)).toEqual(c.expected);
        break;
      case "movePlayer":
        expect(movePlayer(c.teams, c.player, c.teamId)).toEqual(c.expected);
        expect(groupEngine.movePlayer(c.teams, c.player, c.teamId)).toEqual(c.expected);
        break;
    }
  });
});

describe("the signup order matches the app (fixtures/drafts/signup_order.json)", () => {
  it.each(fixture<{ signups: Array<{ uid: string; name: string }>; expected: string[] }>("drafts/signup_order.json").cases)("by name", (c) => {
    expect([...c.signups].sort(signupOrder).map((s) => s.uid)).toEqual(c.expected);
  });
});

describe("the snake order matches the app (fixtures/drafts/snake_order.json)", () => {
  type Pick = { uid: string; captainId: string };
  it.each(
    fixture<{ captains: string[]; poolSize: number; snake: number[]; onTheClock: Array<string | null>; picks: Pick[]; teams: Record<string, string[]> }>(
      "drafts/snake_order.json",
    ).cases,
  )("$captains.length captains, $poolSize players", (c) => {
    expect(Array.from({ length: c.poolSize }, (_, p) => snakeIndex(c.captains.length, p))).toEqual(c.snake);
    expect(c.onTheClock.map((_, i) => onTheClock(c.captains, c.picks.slice(0, i), c.poolSize))).toEqual(c.onTheClock);
    expect(Object.fromEntries(c.captains.map((id) => [id, draftTeamOf(c.picks, id)]))).toEqual(c.teams);
  });
});

// Hand-written (the live draft's rules are the server's, not the app's);
// firebase/functions/test/tournaments/draft_fixtures.test.ts checks the
// functions' draft_model.ts against the same cases.
type LiveCase = { name: string; kind: string; expected: unknown } & Record<string, never>;
describe("live draft rules match the server (fixtures/drafts/live_draft.json)", () => {
  it.each(fixture<LiveCase>("drafts/live_draft.json").cases)("$kind: $name", (c) => {
    const pool = (uids: string[]) => uids.map((uid) => ({ uid }));
    const got =
      c.kind === "autoPick"
        ? (autoPick(c.left, c.team, c.mixed)?.uid ?? null)
        : c.kind === "startProblem"
          ? startProblem({ captainIds: c.captainIds, accepted: new Set<string>(c.accepted), poolSize: c.poolSize })
          : c.kind === "pickProblem"
            ? pickProblem({ status: c.status, captainIds: c.captainIds, picks: c.picks, pool: pool(c.pool), uid: c.uid })
            : c.kind === "leagueTeamName"
              ? leagueTeamName(c.team, c.league)
              : teamsFromDraft({ captains: c.captains, picks: c.picks, names: c.names, teamNames: c.teamNames });
    expect(got).toEqual(c.expected);
  });
});
