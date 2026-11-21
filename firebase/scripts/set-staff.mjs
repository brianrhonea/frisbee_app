// Makes an account Stall 10 staff (or takes it away): sets the `staff`
// custom claim the API reads from the ID token (Caller.staff), which opens
// the website's /staff report queue (remove, dismiss, warn, suspend).
//
// The person must sign out and back in (or wait up to an hour for their
// token to refresh) before it takes effect.
//
//   cd firebase/functions && npm ci            # for firebase-admin
//   node ../scripts/set-staff.mjs you@example.com                 # dev
//   node ../scripts/set-staff.mjs you@example.com --project prod  # prod
//   node ../scripts/set-staff.mjs you@example.com --remove        # take it away
//   node ../scripts/set-staff.mjs --list                          # who is staff
//
// Uses Application Default Credentials (`gcloud auth application-default
// login`); never a service-account key. Other custom claims are kept.

import { createRequire } from "node:module";

// firebase-admin is installed in firebase/functions, not beside this script.
const require = createRequire(new URL("../functions/package.json", import.meta.url));
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");

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
const who = args.find((a, i) => !a.startsWith("--") && i !== at + 1);
if (!project || project.startsWith("--") || (!who && !list)) {
  console.error("usage: node set-staff.mjs <email or uid> [--remove] [--project dev|prod|<id>]");
  console.error("       node set-staff.mjs --list [--project dev|prod|<id>]");
  process.exit(2);
}

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
console.log(
  `${remove ? "Removed staff from" : "Made staff:"} ${user.email ?? user.uid} on ${project}. ` +
    "They need to sign out and back in.",
);
