// One-off fix for league teams drafted from a YOUTH division before the
// draft kept their level: `leagueTeamDoc` (packages/shared/src/drafts.ts,
// and teamDoc in firebase/functions/src/tournaments/league.ts) wrote
// `level: "league"` on every drafted team and its teamDirectory listing,
// so a youth league's teams read as adult teams and their rosters were
// public to visitors. Sets `level: "youth"` on both documents of each
// drafted team (`league_…` ids) in a youth division:
//
//   - the division's drafted teams (divisions/{divisionId}.teams, real
//     ids once created), and
//   - the league's accepted entries in that division with a `league_` id.
//
// Dry run by default: prints what it would change and writes nothing.
// Dev project by default. Writes only with --apply.
//
//   cd firebase/functions && npm ci            # for firebase-admin
//   node ../scripts/backfill-youth-league-teams.mjs                  # dev, dry run
//   node ../scripts/backfill-youth-league-teams.mjs --apply          # dev, for real
//   node ../scripts/backfill-youth-league-teams.mjs --project prod   # prod, dry run
//
// Uses Application Default Credentials (`gcloud auth application-default
// login`); never a service-account key. Run on dev first. Reads every
// league (tournaments where kind == "league") and its divisions and
// entries; no new indexes needed.

import { createRequire } from "node:module";

// firebase-admin is installed in firebase/functions, not beside this script.
const require = createRequire(new URL("../functions/package.json", import.meta.url));
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

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
  console.error("usage: node backfill-youth-league-teams.mjs [--project dev|prod|<id>] [--apply]");
  process.exit(2);
}

initializeApp({ credential: applicationDefault(), projectId: project });
const db = getFirestore();
const leaguePrefix = "league_";

console.log(`${apply ? "APPLYING to" : "Dry run on"} ${project}`);

let leagues = 0;
let youthDivisions = 0;
let fixed = 0;

const leagueSnap = await db.collection("tournaments").where("kind", "==", "league").get();
for (const league of leagueSnap.docs) {
  leagues++;
  const summaries = Array.isArray(league.get("divisions")) ? league.get("divisions") : [];
  const divisions = await league.ref.collection("divisions").get();
  const youth = divisions.docs.filter(
    (d) => d.get("level") === "youth" || summaries.some((s) => s && s.id === d.id && s.level === "youth"),
  );
  if (youth.length === 0) continue;
  const entries = await league.ref.collection("entries").get();
  for (const division of youth) {
    youthDivisions++;
    const ids = new Set();
    for (const t of Array.isArray(division.get("teams")) ? division.get("teams") : []) {
      if (t && typeof t.id === "string" && t.id.startsWith(leaguePrefix)) ids.add(t.id);
    }
    for (const e of entries.docs) {
      if (e.id.startsWith(leaguePrefix) && e.get("divisionId") === division.id) ids.add(e.id);
    }
    for (const teamId of ids) {
      const team = db.doc(`teams/${teamId}`);
      const listing = db.doc(`teamDirectory/${teamId}`);
      const [teamSnap, listingSnap] = await db.getAll(team, listing);
      // Only the league's own drafted teams.
      if (!teamSnap.exists || teamSnap.get("leagueId") !== league.id) continue;
      const writes = [];
      if (teamSnap.get("level") !== "youth") writes.push(team);
      if (listingSnap.exists && listingSnap.get("level") !== "youth") writes.push(listing);
      if (writes.length === 0) continue;
      fixed++;
      console.log(
        `${apply ? "" : "would "}set level youth on ${writes.map((r) => r.path).join(" and ")}` +
          ` (league ${league.id}, division ${division.id}, was ${JSON.stringify(teamSnap.get("level"))})`,
      );
      if (!apply) continue;
      // Both in one batch, so the team and its listing never disagree.
      const batch = db.batch();
      for (const ref of writes) batch.update(ref, { level: "youth" });
      await batch.commit();
    }
  }
}

console.log(
  `${leagues} leagues, ${youthDivisions} youth divisions: ${fixed} teams ${apply ? "fixed" : "to fix"}.` +
    (apply ? "" : " Run again with --apply to write."),
);
