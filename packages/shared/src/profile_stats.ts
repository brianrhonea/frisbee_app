import type { ProfileTeam, StatTotals } from "./browse.js";

/** A profile's stats narrowed to one team, or every team (ProfileStatsChoice in the app). */
export interface ProfileStatsChoice {
  /** The teams to pick from, in the profile's teams order; empty when there's no filter to show. */
  options: ProfileTeam[];
  /** The team picked; null for every team. */
  team: string | null;
  /** Season → totals for `team`, or for every team. */
  seasons: Record<string, StatTotals>;
}

const hasStats = (s: StatTotals) => (s.games ?? 0) > 0 || (s.points ?? 0) > 0;

/**
 * The Team filter on a profile's stats: the published teams that have
 * per-team stats, in their order, offered only when there are two or
 * more. A team it doesn't offer means every team (`stats`). Checked on
 * fixtures/profile_stats/choice.json, which the app writes.
 */
export function profileStatsChoice(
  profile: {
    teams?: ProfileTeam[];
    stats?: Record<string, StatTotals>;
    teamStats?: Record<string, Record<string, StatTotals>>;
  },
  team?: string | null,
): ProfileStatsChoice {
  const per = profile.teamStats ?? {};
  const options = (profile.teams ?? []).filter((t) => Object.values(per[t.id] ?? {}).some(hasStats));
  const shown = options.length >= 2 ? options : [];
  const picked = team && shown.some((t) => t.id === team) ? team : null;
  return { options: shown, team: picked, seasons: picked ? per[picked]! : (profile.stats ?? {}) };
}
