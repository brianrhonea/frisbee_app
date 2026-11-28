import { readFileSync } from "node:fs";
import { api } from "./world/seed.mjs";

// Helpers for the signed-in (world) specs: the seeded ids, and a few emulator-only calls (synthetic data,
// demo-stall10, never a real project). Hosts come from the same env the seed uses.
const AUTH = process.env.FIREBASE_AUTH_EMULATOR_HOST || process.env.E2E_AUTH_HOST || "127.0.0.1:9099";
const FS = process.env.FIRESTORE_EMULATOR_HOST || process.env.E2E_FIRESTORE_HOST || "127.0.0.1:8080";

export type World = { password: string; teamId: string; users: Record<"ada" | "ben" | "cam", { email: string; uid: string }> };
export const world = () => JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as World;

/** A signed-in synthetic person for API calls (token only). */
export async function personFor(email: string) {
  const res = await fetch(`http://${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, password: world().password, returnSecureToken: true }),
  });
  const json = (await res.json()) as { idToken: string };
  if (!res.ok) throw new Error(`sign in ${email}: ${JSON.stringify(json)}`);
  return { token: json.idToken };
}

/** The id of the team or group named [name] (an emulator read as the owner; the API has no by-name lookup). */
export async function teamIdByName(name: string): Promise<string> {
  const res = await fetch(`http://${FS}/v1/projects/demo-stall10/databases/(default)/documents:runQuery`, {
    method: "POST",
    headers: { authorization: "Bearer owner", "content-type": "application/json" },
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId: "teams" }], where: { fieldFilter: { field: { fieldPath: "name" }, op: "EQUAL", value: { stringValue: name } } }, limit: 1 } }),
  });
  const rows = (await res.json()) as { document?: { name: string } }[];
  const doc = rows.find((r) => r.document)?.document?.name;
  if (!doc) throw new Error(`no team named ${name}`);
  return doc.split("/").pop()!;
}

/** A youth team (Cam owns it; Ada is not on it), made once. Its roster must stay private to visitors and non-members. */
export async function ensureYouthTeam(): Promise<string> {
  const name = "Cascade Youth Team";
  const have = await teamIdByName(name).catch(() => null);
  if (have) return have;
  const cam = await personFor(world().users.cam.email);
  const t = await api(cam, "POST", "/v1/teams", { name, division: "open", level: "youth", city: "Tacoma" });
  return t.id as string;
}

/** Takes the youth team away again: the Teams search tests count the teams a member can find, so it must not outlive the specs that use it. */
export async function removeYouthTeam(): Promise<void> {
  const id = await teamIdByName("Cascade Youth Team").catch(() => null);
  if (!id) return;
  const cam = await personFor(world().users.cam.email);
  await api(cam, "DELETE", `/v1/teams/${id}`, { name: "Cascade Youth Team" });
}

export { api };
