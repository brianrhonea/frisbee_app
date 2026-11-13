import {
  type CreateTeamInput,
  createTeamRequestSchema,
  nameTakenMessage,
  teamNameClashes,
  teamNameProbe,
} from "@stall10/shared";
import { type Caller, callerLabel, type UserLookup } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import type { TeamRepository } from "./repository.js";

/** How many listings the name check looks through, as the app does. */
const nameCheckLimit = 200;

/** "You're going too fast…", as RateLimitedException says in the app. */
export function tooFastMessage(until: number, now: number): string {
  const minutes = Math.floor((until - now) / 60_000) + 1;
  return `You're going too fast. Try again in ${minutes <= 1 ? "a minute" : `${minutes} minutes`}.`;
}

/**
 * Team rules. The Admin SDK skips firestore.rules, so everything the rules
 * check on a team create is checked here: the body's shape and limits
 * (schema), the owner (the caller, never the body), the flood mute
 * (notMuted), a league spot only in a league taking teams (validLeagueRef),
 * plus the unique-name check the app runs before writing.
 */
export class TeamService {
  constructor(
    private readonly repo: TeamRepository,
    private readonly users: UserLookup,
    private readonly now: () => number = Date.now,
  ) {}

  async createTeam(caller: Caller, body: unknown): Promise<string> {
    const parsed = createTeamRequestSchema.safeParse(body);
    if (!parsed.success) throw fromZod(parsed.error);
    const input: CreateTeamInput = parsed.data;

    const [until, leagueOk, listings, user] = await Promise.all([
      this.repo.mutedUntil(caller.uid),
      input.leagueId == null ? true : this.repo.leagueTakesTeams(input.leagueId),
      this.repo.listingsWithKeywords(teamNameProbe(input.name), nameCheckLimit),
      this.users.lookup(caller.uid),
    ]);
    const now = this.now();
    if (until != null && until > now) {
      throw new ApiError("resource_exhausted", tooFastMessage(until, now));
    }
    if (!leagueOk) {
      throw new ApiError("failed_precondition", "That league isn't taking teams.");
    }
    const clash = listings.find((l) =>
      teamNameClashes(l, { name: input.name, kind: input.kind, division: input.division }),
    );
    if (clash) {
      throw new ApiError("already_exists", nameTakenMessage(clash.name, input.kind, input.division));
    }

    const label = callerLabel({ uid: caller.uid, ...(user ?? { name: caller.name, email: caller.email }) });
    return this.repo.createTeam(input, { uid: caller.uid, label });
  }
}
