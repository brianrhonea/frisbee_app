// Marks a team as an official organizer (or takes it away): sets
// `teams/{id}.official`, which only admin tools can write (firestore.rules
// officialHost). Events it hosts carry the verified badge, it appears under
// "Official organizer" when hosting, and team listings show the mark.
//
//   cd firebase/functions && npm ci            # for firebase-admin
//   node ../scripts/set-official.mjs <teamId>                    # dev
//   node ../scripts/set-official.mjs <teamId> --project prod     # prod
//   node ../scripts/set-official.mjs <teamId> --remove           # take it away
//   node ../scripts/set-official.mjs --list                      # official teams
//   node ../scripts/set-official.mjs --find "Stall 10"           # team ids by name
//
// Uses Application Default Credentials (`gcloud auth application-default
// login`); never a service-account key.

import { createRequire } from "node:module";

// firebase-admin is installed in firebase/functions, not beside this script.
const require = createRequire(new URL("../functions/package.json", import.meta.url));
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const projects = {
  dev: "frisbee-app-brianrhonea-dev",
  prod: "frisbee-app-brianrhonea",
};

const args = process.argv.slice(2);
const valueAfter = (flag) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : undefined;
};
const name = valueAfter("--project") ?? "dev";
const project = projects[name] ?? name;
const remove = args.includes("--remove");
const list = args.includes("--list");
const find = valueAfter("--find");
const flagValues = new Set([valueAfter("--project"), find]);
const teamId = args.find((a) => !a.startsWith("--") && !flagValues.has(a));
if (!project || project.startsWith("--") || (!teamId && !list && !find)) {
  console.error("usage: node set-official.mjs <teamId> [--remove] [--project dev|prod|<id>]");
  console.error("       node set-official.mjs --list | --find <name> [--project dev|prod|<id>]");
  process.exit(2);
}

process.env.GOOGLE_CLOUD_QUOTA_PROJECT ??= project;
initializeApp({ credential: applicationDefault(), projectId: project });
const db = getFirestore();

if (list || find) {
  const q = list ? db.collection("teams").where("official", "==", true) : db.collection("teams").where("name", "==", find);
  const snap = await q.get();
  for (const d of snap.docs) {
    console.log(`${d.id}  ${d.get("name")}  kind=${d.get("kind") ?? "team"}  official=${d.get("official") === true}`);
  }
  console.log(`${snap.size} team(s) on ${project}`);
  process.exit(0);
}

const ref = db.doc(`teams/${teamId}`);
const team = await ref.get();
if (!team.exists) {
  console.error(`No team ${teamId} on ${project}.`);
  process.exit(1);
}
await ref.update({ official: remove ? FieldValue.delete() : true });
console.log(`${remove ? "No longer official" : "Official"}: ${team.get("name")} (${teamId}) on ${project}.`);
