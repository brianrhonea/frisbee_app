// One-off: mark existing under-13 refusals `under13: true` (see
// src/account/backfill_under13.ts), so the purge can find them.
//
//   dry run (default, writes nothing):
//     pnpm --filter @stall10/api exec tsx src/scripts/backfill_under13.ts --project frisbee-app-brianrhonea-dev
//   apply:
//     ... backfill_under13.ts --project frisbee-app-brianrhonea-dev --apply
//
// Needs Application Default Credentials that may read and write Firestore and
// use the personal-details KMS key (PERSONAL_DETAILS_KMS_KEY, the same value
// the dev API runs with). Run it from the owner's machine. With the emulator
// (FIRESTORE_EMULATOR_HOST set) the project may be demo-* and
// PERSONAL_DETAILS_LOCAL_KEY is used instead of KMS.
//
// Refuses the production project and any project that isn't dev or demo-*.
import { initializeApp } from "firebase-admin/app";
import { FieldPath, getFirestore } from "firebase-admin/firestore";
import { backfillUnder13Marker, type RefusalRecord } from "../account/backfill_under13.js";
import { FirestoreDocStore } from "../firestore_store.js";
import { LocalCipher, type PersonalCipher } from "../personal/cipher.js";
import { KmsCipher } from "../personal/kms.js";
import { PersonalService } from "../personal/service.js";
import { DEV_PROJECT_ID } from "../startup_env.js";

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

const projectId = arg("--project") ?? fail("Pass --project <id> (the dev project, or demo-* with the emulator).");
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
if (projectId !== DEV_PROJECT_ID && !(emulated && projectId.startsWith("demo-"))) {
  fail(`Refusing project ${projectId}: this script runs only against ${DEV_PROJECT_ID}, or demo-* with the emulator.`);
}
const apply = process.argv.includes("--apply");

function cipher(): PersonalCipher {
  const kms = process.env.PERSONAL_DETAILS_KMS_KEY?.trim();
  if (kms) return new KmsCipher(kms);
  const local = process.env.PERSONAL_DETAILS_LOCAL_KEY?.trim();
  if (local && emulated) return new LocalCipher(local);
  return fail("Set PERSONAL_DETAILS_KMS_KEY (or PERSONAL_DETAILS_LOCAL_KEY with the emulator).");
}

const app = initializeApp({ projectId });
const db = getFirestore(app);
const personal = new PersonalService(new FirestoreDocStore(db), { lookup: async () => null }, cipher());

async function* refusals(): AsyncGenerator<RefusalRecord> {
  let after: string | undefined;
  for (;;) {
    let q = db.collection("ageRefusals").orderBy(FieldPath.documentId()).limit(300);
    if (after) q = q.startAfter(after);
    const page = await q.get();
    for (const d of page.docs) yield { id: d.id, under13: d.get("under13") };
    if (page.size < 300) return;
    after = page.docs[page.docs.length - 1]!.id;
  }
}

console.log(`${apply ? "APPLYING" : "Dry run (no writes; pass --apply to write)"} against ${projectId}`);
const report = await backfillUnder13Marker({
  refusals: refusals(),
  personal,
  mark: async (uid) => void (await db.doc(`ageRefusals/${uid}`).set({ under13: true }, { merge: true })),
  apply,
});
console.log(JSON.stringify(report, null, 2));
if (report.unreadable.length || report.writeFailures.length) process.exitCode = 2;
