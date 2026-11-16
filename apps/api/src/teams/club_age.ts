// Club teams are for players 16 and over (packages/shared: isClubTeam,
// clubJoinProblem). Checked whenever someone becomes a member of a club
// team through the API: joining with a code or link, accepting an invite,
// an admin approving a request, and creating one (the creator is its first
// member). Their age is counted on the day they join, from the date of
// birth in their personal details (apps/api/src/personal), which is never
// shown to anyone; the asker only learns yes or no. Members already on a
// club team stay, and changing a team's level to club removes no one.
import { clubCantJoinMessage, clubJoinProblem, isClubTeam } from "@stall10/shared";
import { ApiError } from "../errors.js";
import type { Data } from "../store.js";

/** Reads a player's date of birth (PersonalService.birthDate). */
export interface BirthDates {
  /** YYYY-MM-DD, or null when they haven't given one. */
  birthDate(uid: string): Promise<string | null>;
}

/** Without the personal-details key the API can't read ages, so club joins stop. */
export const clubAgeUnavailableMessage = "Club teams can't take new players right now. Try again later.";

export class ClubAgeGate {
  constructor(
    /** Absent when the API has no personal-details key: club joins are refused (fail closed). */
    private readonly births: BirthDates | undefined,
    private readonly now: () => number = Date.now,
  ) {}

  /**
   * Throws unless [uid] may join [team] today. Nothing is read for teams
   * that aren't club teams. [name] is for an admin adding someone else:
   * the message then names them ("Sam can't join a club team: …").
   */
  async check(team: Data, uid: string, name?: string): Promise<void> {
    if (!isClubTeam(team)) return;
    if (!this.births) throw new ApiError("unavailable", clubAgeUnavailableMessage);
    const birthDate = await this.births.birthDate(uid);
    // The date in the furthest-ahead time zone (UTC+14), as personal
    // details count ages: someone who turned 16 today where they live
    // isn't refused by a day.
    const problem = clubJoinProblem(birthDate, new Date(this.now() + 14 * 3600_000));
    if (problem) throw new ApiError("failed_precondition", name === undefined ? problem : clubCantJoinMessage(name));
  }
}
