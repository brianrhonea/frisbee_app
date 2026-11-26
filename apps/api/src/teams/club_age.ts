// Club teams are for players 16 and over (packages/shared: isClubTeam,
// clubJoinProblem). Checked whenever someone becomes a member of a club
// team through the API: joining with a code or link, accepting an invite,
// an admin approving a request, and creating one (the creator is its first
// member). Their age is counted on the day they join, from the date of
// birth in their personal details (apps/api/src/personal), which is never
// shown to anyone; the asker only learns yes or no. Members already on a
// club team stay. Changing a team's level to club (the API is the only way:
// firestore.rules no longer lets a client write `level`) re-checks everyone
// on it first (checkEveryone), so a team can't collect under-16 players at
// another level and then switch.
import { clubCantJoinMessage, clubJoinProblem, clubMinimumAge, isClubTeam } from "@stall10/shared";
import { ApiError } from "../errors.js";
import type { Data } from "../store.js";

/** Reads a player's date of birth (PersonalService.birthDate). */
export interface BirthDates {
  /** YYYY-MM-DD, or null when they haven't given one. */
  birthDate(uid: string): Promise<string | null>;
}

/** Without the personal-details key the API can't read ages, so club joins stop. */
export const clubAgeUnavailableMessage = "Club teams can't take new players right now. Try again later.";

/** How many date-of-birth lookups run at once when checking a whole team. */
const lookupBatch = 20;

/** Why a team can't become a club team yet ([count] people fail); names are never given. */
export const clubSwitchPrefix = "This team can't switch to the club level";
export const clubSwitchMessage = (count: number) =>
  `${clubSwitchPrefix}: ${count === 1 ? "1 person on it is" : `${count} people on it are`} under ${clubMinimumAge} or ` +
  "haven't added a date of birth. Club teams are for players 16 and over.";

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

  /**
   * Throws unless every one of [uids] may be on a club team today: used when
   * an existing team switches to the club level. Fails closed without the
   * personal-details key, on a missing or invalid date of birth, and when
   * anyone is too young; the error says how many, never who.
   */
  async checkEveryone(uids: readonly string[]): Promise<void> {
    const births = this.births;
    if (!births) throw new ApiError("unavailable", clubAgeUnavailableMessage);
    const today = new Date(this.now() + 14 * 3600_000);
    let failing = 0;
    for (let i = 0; i < uids.length; i += lookupBatch) {
      const dates = await Promise.all(uids.slice(i, i + lookupBatch).map((u) => births.birthDate(u)));
      failing += dates.filter((d) => clubJoinProblem(d, today) !== null).length;
    }
    if (failing > 0) {
      throw new ApiError("failed_precondition", clubSwitchMessage(failing), { level: clubSwitchMessage(failing) });
    }
  }
}
