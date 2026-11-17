// One-off backfill for security review S1 (private profiles' posts):
// stamps `private` on every person's post from its author's profile, as
// the `follows` functions postPrivacy and profilePrivacy do for new posts
// and privacy changes, and marks the follows of each private profile
// `approved` (its accepted followers), so the app asks for its posts one
// author at a time.
//
// Run once per project after deploying functions:follows (so nothing new
// is missed), and before the rules' list check (S1 phase B) is turned on.
//
// Dry run by default: prints what it would change and writes nothing.
// Dev project by default. Writes only with --apply.
//
//   cd firebase/functions && npm ci            # for firebase-admin
//   node ../scripts/backfill-post-privacy.mjs                  # dev, dry run
//   node ../scripts/backfill-post-privacy.mjs --apply          # dev, for real
//   node ../scripts/backfill-post-privacy.mjs --project prod   # prod, dry run
//
// Uses Application Default Credentials (`gcloud auth application-default
// login`); never a service-account key. Reads every post (by document id,
// 450 at a time) and each author's profile once.

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
  console.error("usage: node backfill-post-privacy.mjs [--project dev|prod|<id>] [--apply]");
  process.exit(2);
}

initializeApp({ credential: applicationDefault(), projectId: project });
const db = getFirestore();
const page = 450;

console.log(`${apply ? "APPLYING to" : "Dry run on"} ${project}`);

/** Each author's profile privacy, read once. */
const privacy = new Map();
async function isPrivate(uid) {
  if (!privacy.has(uid)) {
    const profile = (await db.doc(`profiles/${uid}`).get()).data();
    privacy.set(uid, profile?.private === true);
  }
  return privacy.get(uid);
}

/** Updates each document [q] finds with what [change] gives it. */
async function eachPage(q, change) {
  let after;
  let seen = 0;
  let changed = 0;
  for (;;) {
    const snap = await (after ? q.startAfter(after) : q).limit(page).get();
    if (snap.empty) break;
    const batch = db.batch();
    let writes = 0;
    for (const d of snap.docs) {
      seen++;
      const update = await change(d);
      if (!update) continue;
      changed++;
      writes++;
      batch.update(d.ref, update);
    }
    if (apply && writes > 0) await batch.commit();
    if (snap.size < page) break;
    after = snap.docs[snap.docs.length - 1];
  }
  return { seen, changed };
}

const posts = await eachPage(db.collection("posts").orderBy("__name__"), async (d) => {
  const authorId = d.get("authorId");
  if (typeof authorId !== "string" || !authorId) return null;
  const want = await isPrivate(authorId);
  return d.get("private") === want ? null : { private: want };
});
console.log(`posts: ${posts.seen} read, ${posts.changed} ${apply ? "stamped" : "to stamp"}`);

const privateProfiles = await db.collection("profiles").where("private", "==", true).select().get();
let follows = 0;
for (const p of privateProfiles.docs) {
  const r = await eachPage(db.collectionGroup("follows").where("key", "==", `user_${p.id}`), async (d) =>
    d.get("approved") === true ? null : { approved: true },
  );
  follows += r.changed;
}
console.log(
  `private profiles: ${privateProfiles.size}; follows ${apply ? "marked" : "to mark"} approved: ${follows}`,
);
