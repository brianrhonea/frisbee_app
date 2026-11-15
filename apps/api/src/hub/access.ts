// Who may read and write in a team's chat rooms and events: ports of
// chatRole, rolesOf, inAudience, canReadRoom and canWriteRoom in
// firestore.rules. Keep the two in step.
import { audienceTier } from "@stall10/shared";
import type { Data } from "../store.js";
import { can, isOrg, isOwner, mapOf, roleIn, strings } from "../teams/access.js";

/** chatRole(): a legacy "stats" member counts as a player. */
export const chatRole = (team: Data, uid: string) => audienceTier(roleIn(team, uid));

/** rolesOf(): the member's custom role ids (the rule checks the first 10). */
const rolesOf = (team: Data, uid: string) => strings(mapOf(team.memberRoles)[uid]).slice(0, 10);

/** inAudience(team, ids, users). */
export function inAudience(team: Data, uid: string, ids: string[], users: string[]): boolean {
  const role = chatRole(team, uid);
  return (
    ids.includes("everyone") || (!!role && ids.includes(role)) || rolesOf(team, uid).some((r) => ids.includes(r)) || users.includes(uid)
  );
}

export const canReadRoom = (team: Data, uid: string, room: Data) =>
  isOwner(team, uid) || inAudience(team, uid, strings(room.readRoles), strings(room.readUsers));

export const canWriteRoom = (team: Data, uid: string, room: Data) =>
  isOwner(team, uid) || inAudience(team, uid, strings(room.writeRoles), strings(room.writeUsers));

/** sees(e) in the events rule: a community's events go to their audience; managers see all. */
export const seesEvent = (team: Data, uid: string, event: Data) =>
  !isOrg(team) || can(team, uid, "manageEvents") || inAudience(team, uid, strings(event.audience), []);
