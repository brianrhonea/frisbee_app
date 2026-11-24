// Makes an account Stall 10 staff (or takes it away): sets the `staff`
// custom claim the API reads from the ID token (Caller.staff), which opens
// the website's /staff report queue (remove, dismiss, warn, suspend), and
// writes `staff/{uid}`, the "Stall 10 staff" badge on their profile.
//
// The person must sign out and back in (or wait up to an hour for their
// token to refresh) before it takes effect.
//
//   cd firebase/functions && npm ci            # for firebase-admin
//   node ../scripts/set-staff.mjs you@example.com                 # dev
//   node ../scripts/set-staff.mjs you@example.com --project prod  # prod
//   node ../scripts/set-staff.mjs you@example.com --remove        # take it away
//   node ../scripts/set-staff.mjs --list                          # who is staff
//   node ../scripts/set-staff.mjs you@example.com --host <teamId> # also host as Stall 10
//
// --host names the official Stall 10 organization (an organization marked
// official with set-official.mjs; find its id with
// `set-official.mjs --find "Stall 10"`). Staff join it as coaches, so they
// can host any event as Stall 10 (listed first under "Official organizer"
// when hosting), with the "Stall 10 verified" badge, without running any
// other team or club. With --remove they leave it (its owner stays).
//
// Uses Application Default Credentials (`gcloud auth application-default
// login`); never a service-account key. Other custom claims are kept.

import { createRequire } from "node:module";

// firebase-admin is installed in firebase/functions, not beside this script.
const require = createRequire(new URL("../functions/package.json", import.meta.url));
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const projects = {
  dev: "frisbee-app-brianrhonea-dev",
  prod: "frisbee-app-brianrhonea",
};

const args = process.argv.slice(2);
const at = args.indexOf("--project");
const name = at >= 0 ? args[at + 1] : "dev";
const project = projects[name] ?? name;
const remove = args.includes("--remove");
const list = args.includes("--list");
const hostAt = args.indexOf("--host");
const hostId = hostAt >= 0 ? args[hostAt + 1] : undefined;
const who = args.find((a, i) => !a.startsWith("--") && (at < 0 || i !== at + 1) && (hostAt < 0 || i !== hostAt + 1));
if (hostAt >= 0 && (!hostId || hostId.startsWith("--"))) {
  console.error("--host needs the Stall 10 organization's team id (set-official.mjs --find \"Stall 10\").");
  process.exit(2);
}
if (!project || project.startsWith("--") || (!who && !list)) {
  console.error("usage: node set-staff.mjs <email or uid> [--remove] [--project dev|prod|<id>]");
  console.error("       node set-staff.mjs --list [--project dev|prod|<id>]");
  process.exit(2);
}

// With local (user) credentials the Auth admin API needs a quota project,
// or Google answers 403 "requires a quota project".
process.env.GOOGLE_CLOUD_QUOTA_PROJECT ??= project;
initializeApp({ credential: applicationDefault(), projectId: project });
const auth = getAuth();

if (list) {
  let token;
  let n = 0;
  do {
    const page = await auth.listUsers(1000, token);
    for (const u of page.users) {
      if (u.customClaims?.staff === true) {
        console.log(`${u.uid}  ${u.email ?? ""}  ${u.displayName ?? ""}`);
        n++;
      }
    }
    token = page.pageToken;
  } while (token);
  console.log(`${n} staff on ${project}`);
  process.exit(0);
}

const user = who.includes("@") ? await auth.getUserByEmail(who) : await auth.getUser(who);
const claims = { ...(user.customClaims ?? {}) };
if (remove) delete claims.staff;
else claims.staff = true;
await auth.setCustomUserClaims(user.uid, claims);
// The "Stall 10 staff" badge on their profile (firestore.rules: read-only).
const badge = getFirestore().doc(`staff/${user.uid}`);
if (remove) await badge.delete();
else await badge.set({ since: FieldValue.serverTimestamp() });

// Hosting as Stall 10: a coach on the official Stall 10 organization
// (coaches manage its events; can() in apps/api/src/teams/access.ts).
if (hostId) {
  const db = getFirestore();
  const ref = db.doc(`teams/${hostId}`);
  await db.runTransaction(async (tx) => {
    const team = (await tx.get(ref)).data();
    if (!team) throw new Error(`No team ${hostId} on ${project}.`);
    if (team.official !== true || team.kind !== "organization") {
      throw new Error(`${team.name ?? hostId} isn't an official organization. Mark it with set-official.mjs first.`);
    }
    if (team.ownerId === user.uid) return; // The owner already runs it.
    if (remove) {
      tx.update(ref, {
        [`members.${user.uid}`]: FieldValue.delete(),
        [`memberPerms.${user.uid}`]: FieldValue.delete(),
        [`memberRoles.${user.uid}`]: FieldValue.delete(),
        memberIds: FieldValue.arrayRemove(user.uid),
      });
    } else {
      tx.update(ref, { [`members.${user.uid}`]: "coach", memberIds: FieldValue.arrayUnion(user.uid) });
    }
  });
  console.log(`${remove ? "Took" : "Added"} ${user.email ?? user.uid} ${remove ? "off" : "to"} ${hostId} (host as Stall 10).`);
}
console.log(
  `${remove ? "Removed staff from" : "Made staff:"} ${user.email ?? user.uid} on ${project}. ` +
    "They need to sign out and back in.",
);
