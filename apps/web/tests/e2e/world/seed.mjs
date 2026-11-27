// A synthetic world for signed-in browser tests (Sprint 3 H screens). EMULATORS ONLY:
// Auth 9099, Firestore 8080 and the local API on 8787, all with the demo-stall10 project.
// Everything goes through the real API (so the data has the shape the API writes), except
// notifications, which Cloud Functions write in production: those go to the Firestore
// emulator's REST endpoint. No secret files, no real project, no network beyond localhost.
//
//   node tests/e2e/world/seed.mjs        seeds (and prints the world as JSON)
//
// Starts from an empty emulator: it clears the demo project's accounts and documents first.

const AUTH = process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
const FS = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const API = process.env.E2E_API_URL || "http://127.0.0.1:8788";
const PROJECT = "demo-stall10";
export const password = "Passw0rd!test";

const must = (ok, what, body) => {
  if (!ok) throw new Error(`${what}: ${typeof body === "string" ? body : JSON.stringify(body)}`);
};

async function authCall(path, body) {
  const res = await fetch(`http://${AUTH}/identitytoolkit.googleapis.com/v1/${path}?key=demo`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  return { ok: res.ok, json: await res.json() };
}

async function user(email, name, birthDate, handle) {
  let r = await authCall("accounts:signUp", { email, password, displayName: name, returnSecureToken: true });
  let fresh = true;
  if (!r.ok) {
    r = await authCall("accounts:signInWithPassword", { email, password, returnSecureToken: true });
    fresh = false;
  }
  must(r.ok, `sign in ${email}`, r.json);
  const u = { uid: r.json.localId, email, name, token: r.json.idToken };
  // Verified, so the "Verify your email" screen does not stand in front of the app (emulator admin call).
  const v = await fetch(`http://${AUTH}/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:update`, {
    method: "POST",
    headers: { authorization: "Bearer owner", "content-type": "application/json" },
    body: JSON.stringify({ localId: u.uid, emailVerified: true }),
  });
  must(v.ok, "verify email", await v.text());
  // The order the sign-up form uses: the birth date first (the API sets the ageOk claim), then the username.
  // Safe to repeat: a second run gets refusals for what is already saved, which are ignored.
  void fresh;
  await api(u, "PUT", "/v1/me/personal/birth-date", { birthDate }).catch(() => undefined);
  u.token = await refresh(email);
  await api(u, "POST", "/v1/me/username", { username: handle }).catch(() => undefined);
  // The "Before you start" agreement, accepted the way the screen does.
  await api(u, "PUT", "/v1/me/agreement", { version: 1 }).catch((e) => console.error("agreement:", String(e.message).slice(0, 200)));
  // The "About you" step the account gate asks for (all synthetic: example.test, 555 numbers).
  const [first, ...rest] = name.split(" ");
  await api(u, "PUT", "/v1/me/personal", {
    legalFirstName: first,
    legalLastName: rest.join(" "),
    birthDate,
    phone: "+12065550100",
    gender: "unspecified",
    address: { line1: "100 Test Street", line2: "", city: "Seattle", region: "WA", postalCode: "98101", country: "US" },
  }).catch((e) => console.error("personal details:", String(e.message).slice(0, 200)));
  u.token = await refresh(email);
  return u;
}

async function refresh(email) {
  const r = await authCall("accounts:signInWithPassword", { email, password, returnSecureToken: true });
  must(r.ok, "refresh", r.json);
  return r.json.idToken;
}

export async function api(u, method, path, body) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: { authorization: `Bearer ${u.token}`, ...(body ? { "content-type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  must(res.ok, `${method} ${path}`, text);
  return json;
}

// Firestore REST value encoding, for the few documents written straight to the emulator.
function enc(v) {
  if (v === null) return { nullValue: null };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, enc(x)])) } };
}
async function fsSet(path, data) {
  const res = await fetch(`http://${FS}/v1/projects/${PROJECT}/databases/(default)/documents/${path}`, {
    method: "PATCH",
    headers: { authorization: "Bearer owner", "content-type": "application/json" },
    body: JSON.stringify({ fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, enc(v)])) }),
  });
  must(res.ok, `firestore ${path}`, await res.text());
}

/** Sets only [data]'s fields, leaving the rest of the document as it is. */
async function fsMerge(path, data) {
  const mask = Object.keys(data).map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join("&");
  const res = await fetch(`http://${FS}/v1/projects/${PROJECT}/databases/(default)/documents/${path}?${mask}`, {
    method: "PATCH",
    headers: { authorization: "Bearer owner", "content-type": "application/json" },
    body: JSON.stringify({ fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, enc(v)])) }),
  });
  must(res.ok, `firestore ${path}`, await res.text());
}

const at = (days, hour, minute = 0) => {
  const d = new Date();
  d.setDate(d.getDate() + days);
  d.setHours(hour, minute, 0, 0);
  return d.toISOString();
};
const ago = (hours) => new Date(Date.now() - hours * 3600_000).toISOString();

/** Empties the demo project in both emulators (they refuse any other project id). */
export async function resetEmulators() {
  const a = await fetch(`http://${AUTH}/emulator/v1/projects/${PROJECT}/accounts`, { method: "DELETE" });
  const f = await fetch(`http://${FS}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: "DELETE" });
  must(a.ok && f.ok, "reset emulators", `${a.status} ${f.status}`);
}

export async function seedWorld() {
  await resetEmulators();
  const ada = await user("ada@example.test", "Ada Rivers", "1991-04-12", "adarivers");
  const ben = await user("ben@example.test", "Ben Okafor", "1993-09-30", "benokafor");
  const cam = await user("cam@example.test", "Cam Lindqvist", "1995-01-20", "camlindqvist");

  const mine = await api(ada, "GET", "/v1/me/home").catch(() => null);
  const existing = mine?.teams?.find?.((t) => t.name === "Seattle Sidewinders");
  let teamId = existing?.id;
  if (!teamId) {
    const t = await api(ada, "POST", "/v1/teams", { name: "Seattle Sidewinders", division: "mixed", level: "club", city: "Seattle" });
    teamId = t.id;
    for (const m of [ben, cam]) {
      await api(ada, "POST", `/v1/teams/${teamId}/invites`, { uid: m.uid });
      await api(m, "POST", `/v1/me/team-invites/${teamId}/accept`);
    }
    // Events: one single, one weekly series, one later game.
    const tz = "America/Los_Angeles";
    await api(ada, "POST", `/v1/teams/${teamId}/events`, { title: "Tuesday practice", type: "practice", startsAt: at(1, 18), endsAt: at(1, 20), location: "Magnuson Park", notes: "Bring both jerseys." });
    await api(ada, "POST", `/v1/teams/${teamId}/events`, { title: "Thursday throwing", type: "workout", startsAt: at(2, 19), endsAt: at(2, 20, 30), location: "Green Lake", timeZone: tz, repeat: { freq: "weekly", until: at(30, 0).slice(0, 10) } });
    const game = await api(ada, "POST", `/v1/teams/${teamId}/events`, { title: "Scrimmage vs Rainiers", type: "scrimmage", startsAt: at(4, 10), endsAt: at(4, 12), location: "Marymoor Park", public: true });
    await api(ben, "PUT", `/v1/teams/${teamId}/events/${game.id}/rsvp`, { status: "going" });
    await api(cam, "PUT", `/v1/teams/${teamId}/events/${game.id}/rsvp`, { status: "maybe" });
    // Team posts and a team chat.
    await api(ada, "POST", `/v1/teams/${teamId}/posts`, { body: "Practice moves to the north field this week. See you there!" });
    await api(ben, "POST", `/v1/teams/${teamId}/chats/general/messages`, { text: "Who has a spare disc for Tuesday?" });
    await api(cam, "POST", `/v1/teams/${teamId}/chats/general/messages`, { text: "I have two. See you at 6." });
    await api(ada, "POST", `/v1/teams/${teamId}/chats/general/messages`, { text: "Thanks both. Bring water, it will be warm." });
    // A second team (Ada is only a member) and a community Ada owns.
    const other = await api(cam, "POST", "/v1/teams", { name: "Capitol Hill Pickup Crew", division: "open", level: "pickup", city: "Seattle" });
    await api(cam, "POST", `/v1/teams/${other.id}/invites`, { uid: ada.uid });
    await api(ada, "POST", `/v1/me/team-invites/${other.id}/accept`);
    await api(ada, "POST", "/v1/teams", { name: "Seattle Ultimate Community", kind: "community", city: "Seattle", description: "Pickup, leagues and events around Seattle." });
    // Stats on (the roster spots page lives there).
    await api(ada, "PUT", `/v1/teams/${teamId}/sections`, { stats: true });
    // Sprint 4: a roster with one linked and one unlinked spot, and custom roles (new coaches and captains are
    // made with roles now): Cam, an admin through a role that manages the team; Ben, a handler.
    await api(ada, "POST", `/v1/teams/${teamId}/roster-players`, { name: "Ada Rivers", number: 1, position: "handler", userId: ada.uid, paid: true });
    await api(ada, "POST", `/v1/teams/${teamId}/roster-players`, { name: "Sam Walk-on", number: 42, position: "cutter", userId: null, paid: false });
    await api(ada, "PUT", `/v1/teams/${teamId}/roles`, {
      roles: {
        coordinators: { name: "Coordinators", color: 0, position: 0, perms: ["manageTeam"] },
        handlers: { name: "Handlers", color: 0, position: 1, perms: [] },
      },
      memberRoles: { [cam.uid]: ["coordinators"], [ben.uid]: ["handlers"] },
    });
    // Teams and groups Ada is not on: a team that takes join requests, an open group, an approval group and a plain team.
    const cascade = await api(cam, "POST", "/v1/teams", { name: "Cascade Request Team", division: "open", level: "college", city: "Tacoma" });
    await api(cam, "PUT", `/v1/teams/${cascade.id}/allow-join-requests`, { on: true });
    // (Ben makes the groups: team creation is limited per person per minute.) One open and one approval group per browser width (A for 375, B for 1440): the tests join them.
    for (const x of ["A", "B"]) {
      await api(ben, "POST", "/v1/teams", { name: `Cascade Open Group ${x}`, kind: "community", city: "Tacoma", description: "Open pickup." });
      await api(ben, "POST", "/v1/teams", { name: `Cascade Approval Group ${x}`, kind: "organization", city: "Tacoma", requiresApproval: true });
    }
    await api(cam, "POST", "/v1/teams", { name: "Cascade Plain Team", division: "open", level: "college", city: "Tacoma" });
  }
  // Profile feed posts, then a direct message thread (Ben writes to Ada, so Ada has an unread count).
  const feed = await api(ada, "GET", "/v1/feed").catch(() => ({ posts: [] }));
  if (!(feed.posts ?? feed.items ?? []).length) {
    await api(ben, "POST", "/v1/posts", { body: "Great tournament weekend. Thanks to everyone who came out." });
    await api(cam, "POST", "/v1/posts", { body: "Looking for a pickup game on Sunday near Capitol Hill." });
    await api(ada, "POST", "/v1/posts", { body: "New season, new cleats." });
  }
  const conv = await api(ben, "POST", "/v1/conversations", { with: ada.uid });
  if (conv?.id) {
    await api(ben, "POST", `/v1/conversations/${conv.id}/messages`, { text: "Are you coming Tuesday?" });
    await api(ben, "POST", `/v1/conversations/${conv.id}/messages`, { text: "I can bring the cones." });
  }
  const conv2 = await api(ada, "POST", "/v1/conversations", { with: cam.uid });
  await api(ada, "POST", `/v1/conversations/${conv2.id}/messages`, { text: "Sunday pickup still on?" });
  await api(cam, "PUT", `/v1/conversations/${conv2.id}/request`, { accept: true });
  // Ben's thread: Ada accepts it but has not read it, so it shows two unread.
  await api(ada, "PUT", `/v1/conversations/${conv.id}/request`, { accept: true });
  await api(cam, "POST", `/v1/conversations/${conv2.id}/messages`, { text: "Yes, 10am at the field." });
  // The directory's server-only `adult` marker (the API sets it in production; the emulator API of
  // an older build may not). Members search profiles with `adult == true`, so adults carry it and
  // one unmarked profile, "Ben Minor", must never show up in a search for "ben".
  for (const u of [ada, ben, cam]) await fsMerge(`profiles/${u.uid}`, { adult: true });
  await fsSet("profiles/unmarked-minor", { name: "Ben Minor", username: "benminor", photoUrl: null, keywords: ["b", "be", "ben", "m", "mi", "min", "mino", "minor"] });
  // Notifications (written by Cloud Functions in production).
  await fsSet(`users/${ada.uid}/notifications/n1`, { category: "social", title: "Ben Okafor liked your post", body: "New season, new cleats.", route: "/home", createdAt: ago(1), read: false });
  await fsSet(`users/${ada.uid}/notifications/n2`, { category: "team", title: "New event: Scrimmage vs Rainiers", body: "Saturday at 10:00", route: `/teams/${teamId}/schedule`, createdAt: ago(3), read: false });
  await fsSet(`users/${ada.uid}/notifications/n3`, { category: "posts", title: "Cam Lindqvist commented on your post", body: "Nice!", route: "/home", createdAt: ago(30), read: true });
  await fsSet(`users/${ada.uid}/notifications/n4`, { category: "team", title: "Practice moved", body: "Tuesday practice is on the north field", route: `/teams/${teamId}`, createdAt: ago(80), read: true });

  return { password, teamId, users: { ada: { email: ada.email, uid: ada.uid }, ben: { email: ben.email, uid: ben.uid }, cam: { email: cam.email, uid: cam.uid } } };
}

if (import.meta.url === `file:///${process.argv[1]?.replace(/\\/g, "/")}`) {
  seedWorld().then((w) => console.log(JSON.stringify(w, null, 1)), (e) => { console.error(e); process.exit(1); });
}
