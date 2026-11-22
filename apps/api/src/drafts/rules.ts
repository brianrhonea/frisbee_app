// Ports of the firestore.rules blocks this slice's writes went through:
// tournaments/{t}/signups/{uid} (validSignup, playerSignsUp, playerEdits,
// playerWithdraws, hostDecides), payments/{id}, and the division update
// (validDivision) the app makes when it saves drafted teams. The Admin SDK
// skips the rules, so these guard the API's writes. Each returns why the
// write is refused, or null; every conjunct of the rule is one check, in
// the rule's order.
import { ApiError } from "../errors.js";
import { type Data, serverTime } from "../store.js";
import { isMap } from "../teams/access.js";

type Problem = ApiError | null;
const bad = (m: string) => new ApiError("invalid_argument", m);
const denied = (m: string) => new ApiError("permission_denied", m);
const closed = (m: string) => new ApiError("failed_precondition", m);

const isInt = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v);
/** validString(v, max). */
const validString = (v: unknown, max: number) => typeof v === "string" && v.length <= max;
/** `x is timestamp`: a stored Date, or the server's clock being written. */
const isTimestamp = (v: unknown) => v instanceof Date || v === serverTime;
const has = (d: Data, k: string) => Object.hasOwn(d, k);
const get = (d: Data, k: string, fallback: unknown) => (has(d, k) ? d[k] : fallback);

function same(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a instanceof Date && b instanceof Date) return a.getTime() === b.getTime();
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => same(x, b[i]));
  if (isMap(a) && isMap(b)) {
    const ka = Object.keys(a);
    return ka.length === Object.keys(b).length && ka.every((k) => has(b, k) && same(a[k], b[k]));
  }
  return false;
}

/** changed(): request.resource.data.diff(resource.data).affectedKeys(). */
export function changedKeys(before: Data, after: Data): Set<string> {
  const out = new Set<string>();
  for (const k of new Set([...Object.keys(before), ...Object.keys(after)])) {
    if (has(before, k) !== has(after, k) || !same(before[k], after[k])) out.add(k);
  }
  return out;
}
const onlyChanged = (keys: Set<string>, allowed: readonly string[]) => [...keys].every((k) => allowed.includes(k));

// ---- signups/{userId} -----------------------------------------------------------

const signupKeys = ["name", "divisionId", "skill", "gender", "status", "createdAt", "updatedAt"];
const signupStatuses = ["applied", "accepted", "waitlisted", "declined", "withdrawn"];

/** validSignup(s): the whole document as it will be stored. */
export function validSignup(s: Data): Problem {
  if (!Object.keys(s).every((k) => signupKeys.includes(k))) return bad("A signup can't have other fields.");
  if (typeof s.name !== "string" || s.name.length === 0 || s.name.length > 100) return bad("Your name has to be 1 to 100 characters.");
  if (typeof s.divisionId !== "string" || s.divisionId.length === 0 || s.divisionId.length > 100) return bad("Pick a division.");
  if (!isInt(s.skill) || s.skill < 1 || s.skill > 5) return bad("Rate your skill from 1 to 5.");
  if (![null, "mmp", "wmp"].includes(get(s, "gender", null) as string | null)) return bad("Pick MMP, WMP or neither.");
  if (typeof s.status !== "string" || !signupStatuses.includes(s.status)) return bad("Unknown status.");
  if (s.updatedAt !== serverTime) return bad("updatedAt must be the server's time.");
  return null;
}

export interface SignupCtx {
  /** The caller. */
  uid: string;
  /** The signup's id (its player). */
  userId: string;
  tournament: Data;
  /** manages(current()): the caller can manage events on the host. */
  manages: boolean;
}

/** allow create: validSignup && playerSignsUp(). [divisionExists]: the exists() on the signup's division. */
export function signupCreateProblem(c: SignupCtx, next: Data, divisionExists: boolean): Problem {
  const v = validSignup(next);
  if (v) return v;
  const t = c.tournament;
  if (c.uid !== c.userId) return denied("You can only sign yourself up.");
  if (t.entryType !== "players") return closed("This event takes teams, not players.");
  if (t.status !== "registration") return closed("Signups are closed.");
  if (t.visibility !== "public") return denied("This event is invite only.");
  if (next.status !== "applied") return bad("A new signup starts as signed up.");
  if (next.createdAt !== serverTime) return bad("createdAt must be the server's time.");
  if (!divisionExists) return new ApiError("not_found", "That division doesn't exist.");
  return null;
}

/** playerEdits(): back in after withdrawing, or fixing answers while waiting. */
export function playerEdits(c: SignupCtx, before: Data, next: Data): boolean {
  const was = before.status;
  const now = next.status;
  return (
    c.uid === c.userId &&
    c.tournament.status === "registration" &&
    (((was === "applied" || was === "waitlisted") && now === was) || (was === "withdrawn" && now === "applied")) &&
    onlyChanged(changedKeys(before, next), ["name", "divisionId", "skill", "gender", "status", "updatedAt"])
  );
}

/** playerWithdraws(). */
export function playerWithdraws(c: SignupCtx, before: Data, next: Data): boolean {
  return c.uid === c.userId && next.status === "withdrawn" && before.status !== "withdrawn" && onlyChanged(changedKeys(before, next), ["status", "updatedAt"]);
}

/** hostDecides(). */
export function hostDecides(c: SignupCtx, before: Data, next: Data): boolean {
  return c.manages && onlyChanged(changedKeys(before, next), ["status", "updatedAt"]);
}

/** allow update: validSignup && (playerEdits || playerWithdraws || hostDecides). */
export function signupUpdateProblem(c: SignupCtx, before: Data, next: Data): Problem {
  const v = validSignup(next);
  if (v) return v;
  if (playerEdits(c, before, next) || playerWithdraws(c, before, next) || hostDecides(c, before, next)) return null;
  // Why not, as the person asking would understand it.
  if (c.uid !== c.userId) return denied("Only the event's organizers can do that.");
  if (next.status === "withdrawn" && before.status === "withdrawn") return closed("You've already withdrawn.");
  if (c.tournament.status !== "registration") return closed("Signups are closed.");
  if (before.status === "accepted" || before.status === "declined") return closed("The host has decided on your signup, so it can't be changed. Ask the host.");
  return denied("You can't change this signup.");
}

// ---- payments/{id} ---------------------------------------------------------------

/** allow create, update on payments: manages && the fields. */
export function paymentProblem(manages: boolean, p: Data): Problem {
  if (!manages) return denied("Only the event's organizers can mark fees paid.");
  if (!Object.keys(p).every((k) => ["paid", "paidAt", "note", "offlineAt"].includes(k))) return bad("A payment can't have other fields.");
  if (!(p.offlineAt === undefined || p.offlineAt === null || isTimestamp(p.offlineAt))) return bad("offlineAt must be a time.");
  if (typeof p.paid !== "boolean") return bad("Say whether it's paid.");
  if (!(p.paidAt === null || isTimestamp(p.paidAt))) return bad("paidAt must be a time.");
  if (!validString(p.note, 200)) return bad("The note can be up to 200 characters.");
  return null;
}

// ---- divisions/{divisionId} --------------------------------------------------------

const divisionKeys = ["division", "level", "settings", "maxTeams", "seeds", "captains", "placements", "minRoster", "teams"];

/** validDivision(d), the whole division after the write. */
export function validDivision(d: Data): Problem {
  const invalid = (m: string) => bad(`This division can't be saved: ${m}`);
  if (!Object.keys(d).every((k) => divisionKeys.includes(k))) return invalid("it has unknown fields.");
  const minRoster = get(d, "minRoster", null);
  if (!(minRoster === null || (isInt(minRoster) && minRoster >= 2 && minRoster <= 30))) return invalid("the minimum roster is out of range.");
  const teams = get(d, "teams", []);
  if (!Array.isArray(teams) || teams.length > 32) return invalid("it takes at most 32 drafted teams.");
  if (!["mixed", "open", "women", "masters"].includes(d.division as string)) return invalid("unknown division.");
  if (!["club", "college", "youth", "league", "pickup"].includes(d.level as string)) return invalid("unknown level.");
  if (!isMap(d.settings)) return invalid("it has no settings.");
  if (!isInt(d.maxTeams) || d.maxTeams < 2 || d.maxTeams > 64) return invalid("the team cap is out of range.");
  if (!Array.isArray(d.seeds) || d.seeds.length > d.maxTeams) return invalid(`it takes up to ${d.maxTeams} teams. Raise the cap or draft fewer teams.`);
  if (!isMap(d.captains) || Object.keys(d.captains).length > 64) return invalid("too many captains.");
  if (!Array.isArray(d.placements) || d.placements.length > 64) return invalid("too many placements.");
  return null;
}
