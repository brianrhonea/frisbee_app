// One-off: set the account gate's claims (`ageOk`, `terms`) on existing Auth
// users from their stored records, before the rules enforce the gate.
//
//   dry run (default, writes nothing):
//     pnpm --filter @stall10/api exec tsx src/scripts/backfill_claims.ts --project frisbee-app-brianrhonea-dev
//   apply:
//     ... backfill_claims.ts --project frisbee-app-brianrhonea-dev --apply
//
// Needs Application Default Credentials that may list Auth users, write their
// claims, read Firestore, and use the personal-details KMS key
// (PERSONAL_DETAILS_KMS_KEY, the same value the dev API runs with). Run it from
// the owner's machine. Idempotent: run the dry run again after --apply and it
// should report 0 changed. With the emulators (FIRESTORE_EMULATOR_HOST and
// FIREBASE_AUTH_EMULATOR_HOST set) the project may be demo-* and
// PERSONAL_DETAILS_LOCAL_KEY is used instead of KMS.
//
// Refuses the production project and any project that isn't dev or demo-*.
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { AccountGate } from "../account/gate.js";
import { backfillClaims, type BackfillUser } from "../account/backfill.js";
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

const projectId = arg("--project") ?? fail("Pass --project <id> (the dev project, or demo-* with the emulators).");
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
if (projectId !== DEV_PROJECT_ID && !(emulated && projectId.startsWith("demo-"))) {
  fail(`Refusing project ${projectId}: this script runs only against ${DEV_PROJECT_ID}, or demo-* with both emulators.`);
}
const apply = process.argv.includes("--apply");

function cipher(): PersonalCipher {
  const kms = process.env.PERSONAL_DETAILS_KMS_KEY?.trim();
  if (kms) return new KmsCipher(kms);
  const local = process.env.PERSONAL_DETAILS_LOCAL_KEY?.trim();
  if (local && emulated) return new LocalCipher(local);
  return fail("Set PERSONAL_DETAILS_KMS_KEY (or PERSONAL_DETAILS_LOCAL_KEY with the emulators).");
}

async function* authUsers(auth: ReturnType<typeof getAuth>): AsyncGenerator<BackfillUser> {
  let pageToken: string | undefined;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const u of page.users) yield { uid: u.uid, customClaims: u.customClaims ?? null, disabled: u.disabled };
    pageToken = page.pageToken;
  } while (pageToken);
}

const app = initializeApp({ projectId });
const auth = getAuth(app);
const store = new FirestoreDocStore(getFirestore(app));
// Only birthDate() is used: the lookup is never reached.
const births = new PersonalService(store, { lookup: async () => null }, cipher());
const gate = new AccountGate(store, { lookup: async () => null }, births);

console.log(`${apply ? "APPLYING" : "Dry run (no writes; pass --apply to write)"} against ${projectId}`);
const report = await backfillClaims({ users: authUsers(auth), gate, auth, apply });
console.log(JSON.stringify(report, null, 2));
if (report.decryptFailures.length || report.writeFailures.length) process.exitCode = 2;
