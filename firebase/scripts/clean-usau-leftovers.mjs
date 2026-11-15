// One-off clean-up of data left over from the removed USA Ultimate features,
// so the app's read-side tolerance for it can be deleted afterwards:
//
//   1. Roster entries (teams/{teamId}/roster/{uid}) that still carry `paid`
//      or the retired `onUsau` flag. As the app's _moveLegacyStatus does
//      when an admin opens the roster: copies `paid` into
//      teams/{teamId}/rosterStatus/{uid} when that doc doesn't exist yet,
//      then deletes both fields from the roster entry.
//   2. Follows of USA Ultimate events (users/{uid}/follows/{key} with
//      type "event"), which Follow.isKnown filters out. Deletes them. The
//      `followCount` trigger (functions group `follows`) fires for each
//      delete and takes it off followCounts/{key}.followers and the
//      follower's followCounts/user_{uid}.following, as for any unfollow.
//
// Dry run by default: prints what it would change and writes nothing.
// Dev project by default. Writes only with --apply.
//
//   cd firebase/functions && npm ci            # for firebase-admin
//   node ../scripts/clean-usau-leftovers.mjs                     # dev, dry run
//   node ../scripts/clean-usau-leftovers.mjs --apply             # dev, for real
//   node ../scripts/clean-usau-leftovers.mjs --project prod      # prod, dry run
//
// Uses Application Default Credentials (`gcloud auth application-default
// login`); never a service-account key. Run on dev first. Scans every team
// and user document's subcollection (no new indexes needed).
//
// After it has run on every project, delete from apps/mobile:
// TeamRepositoryFirebase._legacyStatusKeys, _legacyStatus and
// _moveLegacyStatus, and Follow.isKnown (and its callers).

import { createRequire } from "node:module";

// firebase-admin is installed in firebase/functions, not beside this script.
const require = createRequire(new URL("../functions/package.json", import.meta.url));
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

const projects = {
  dev: "frisbee-app-brianrhonea-dev",
  prod: "frisbee-app-brianrhonea",
};

const args = process.argv.slice(2);
const at = args.indexOf("--project");
const name = at >= 0 ? args[at + 1] : "dev";
const project = projects[name] ?? name;
const apply = args.includes("--apply");
if (!project || project.startsWith("--")) {
  console.error("usage: node clean-usau-leftovers.mjs [--project dev|prod|<id>] [--apply]");
  process.exit(2);
}

initializeApp({ credential: applicationDefault(), projectId: project });
const db = getFirestore();
const legacyStatusKeys = ["onUsau", "paid"];

console.log(`${apply ? "APPLYING to" : "Dry run on"} ${project}`);

const writer = apply ? db.bulkWriter() : null;
let rosterEntries = 0;
let statusCreated = 0;
let eventFollows = 0;

for (const team of await db.collection("teams").listDocuments()) {
  const roster = await team.collection("roster").get();
  for (const entry of roster.docs) {
    const data = entry.data();
    if (!legacyStatusKeys.some((k) => k in data)) continue;
    rosterEntries++;
    const fields = legacyStatusKeys.filter((k) => k in data).map((k) => `${k}=${JSON.stringify(data[k])}`);
    const status = team.collection("rosterStatus").doc(entry.id);
    const hasStatus = (await status.get()).exists;
    if (!hasStatus) statusCreated++;
    console.log(
      `${apply ? "" : "would "}clean ${entry.ref.path} (${fields.join(", ")})` +
        (hasStatus ? "" : `; ${apply ? "" : "would "}create ${status.path} {paid: ${data.paid === true}}`),
    );
    if (!writer) continue;
    if (!hasStatus) writer.create(status, { paid: data.paid === true });
    writer.update(entry.ref, Object.fromEntries(legacyStatusKeys.map((k) => [k, FieldValue.delete()])));
  }
}

for (const user of await db.collection("users").listDocuments()) {
  const follows = await user.collection("follows").where("type", "==", "event").get();
  for (const follow of follows.docs) {
    eventFollows++;
    console.log(`${apply ? "delete" : "would delete"} ${follow.ref.path}`);
    writer?.delete(follow.ref);
  }
}

await writer?.close();
console.log(
  `${apply ? "Done" : "Dry run done"}: ${rosterEntries} roster entries ` +
    `(${statusCreated} new rosterStatus docs), ${eventFollows} event follows.` +
    (apply ? "" : " Rerun with --apply to write."),
);
