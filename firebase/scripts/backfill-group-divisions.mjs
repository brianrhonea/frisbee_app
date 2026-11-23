// One-off clean-up: pickup communities and schools/clubs no longer have a
// division or level (hasDivision in packages/shared/src/team.ts), so this
// removes `division` and `level` from every group's team doc and its
// directory listing (teamDirectory/{id}). Teams keep theirs.
//
// Dry run by default: prints what it would change and writes nothing.
// Dev project by default. Writes only with --apply.
//
//   cd firebase/functions && npm ci            # for firebase-admin
//   node ../scripts/backfill-group-divisions.mjs                  # dev, dry run
//   node ../scripts/backfill-group-divisions.mjs --apply          # dev, for real
//   node ../scripts/backfill-group-divisions.mjs --project prod   # prod, dry run
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
const at = args.indexOf("--project");
const name = at >= 0 ? args[at + 1] : "dev";
const project = projects[name] ?? name;
const apply = args.includes("--apply");

process.env.GOOGLE_CLOUD_QUOTA_PROJECT ??= project;
initializeApp({ credential: applicationDefault(), projectId: project });
const db = getFirestore();

const drop = { division: FieldValue.delete(), level: FieldValue.delete() };
let changed = 0;
for (const kind of ["community", "organization"]) {
  const groups = await db.collection("teams").where("kind", "==", kind).get();
  for (const g of groups.docs) {
    const listing = await db.doc(`teamDirectory/${g.id}`).get();
    const teamHas = g.get("division") !== undefined || g.get("level") !== undefined;
    const listingHas = listing.exists && (listing.get("division") !== undefined || listing.get("level") !== undefined);
    if (!teamHas && !listingHas) continue;
    changed++;
    console.log(`${apply ? "Cleaning" : "Would clean"} ${kind} ${g.id} (${g.get("name")})`);
    if (!apply) continue;
    const batch = db.batch();
    if (teamHas) batch.update(g.ref, drop);
    if (listingHas) batch.update(listing.ref, drop);
    await batch.commit();
  }
}
console.log(`${changed} group(s) ${apply ? "cleaned" : "to clean (dry run; --apply to write)"} on ${project}.`);
