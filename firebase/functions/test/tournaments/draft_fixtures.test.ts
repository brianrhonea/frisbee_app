// draft_model.ts against the shared vectors in packages/shared/fixtures/drafts:
// the app's snake order (snake_order.json, written by the app's tests) and
// the live draft's rules (live_draft.json, which packages/shared's drafts.ts
// port is checked against too).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  autoPick,
  onTheClock,
  pickProblem,
  snakeIndex,
  startProblem,
  teamsFromDraft,
} from "../../src/tournaments/draft_model";

const fixtures = join(__dirname, "../../../../packages/shared/fixtures/drafts");
const cases = <C>(file: string): C[] => JSON.parse(readFileSync(join(fixtures, file), "utf8")).cases;

type Pick = { uid: string; captainId: string };

describe("the snake order matches the app (snake_order.json)", () => {
  it.each(
    cases<{ captains: string[]; poolSize: number; snake: number[]; onTheClock: Array<string | null>; picks: Pick[] }>("snake_order.json"),
  )("$captains.length captains, $poolSize players", (c) => {
    expect(Array.from({ length: c.poolSize }, (_, p) => snakeIndex(c.captains.length, p))).toEqual(c.snake);
    expect(c.onTheClock.map((_, i) => onTheClock(c.captains, c.picks.slice(0, i), c.poolSize))).toEqual(c.onTheClock);
  });
});

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type LiveCase = { name: string; kind: string; expected: unknown } & Record<string, any>;
describe("live draft rules (live_draft.json)", () => {
  it.each(cases<LiveCase>("live_draft.json"))("$kind: $name", (c) => {
    const pool = (uids: string[]) => uids.map((uid) => ({ uid, name: uid, skill: 1, gender: null }));
    const got =
      c.kind === "autoPick"
        ? (autoPick(c.left, c.team, c.mixed)?.uid ?? null)
        : c.kind === "startProblem"
          ? startProblem({ captainIds: c.captainIds, accepted: new Set<string>(c.accepted), poolSize: c.poolSize })
          : c.kind === "pickProblem"
            ? pickProblem({ status: c.status, captainIds: c.captainIds, picks: c.picks, pool: pool(c.pool), uid: c.uid })
            : teamsFromDraft({ captains: c.captains, picks: c.picks, names: c.names, teamNames: c.teamNames });
    expect(got).toEqual(c.expected);
  });
});
