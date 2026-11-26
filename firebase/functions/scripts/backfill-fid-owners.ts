// One-off backfill for fidOwners/{fid} (the deviceOwnership trigger keeps it
// up to date from then on). Scans every users/{uid}/devices/{fid}, writes
// fidOwners/{fid} = {uid, updatedAt} for the newest registration of each
// FID, and, with --apply, deletes the older accounts' copies of a FID that
// more than one account registered.
//
// Dry run (the default: reads only, prints the plan):
//   npx tsx scripts/backfill-fid-owners.ts --project frisbee-app-brianrhonea-dev
// Then for real:
//   npx tsx scripts/backfill-fid-owners.ts --project frisbee-app-brianrhonea-dev --apply
//
// Runs only against the dev project or a Firestore emulator
// (FIRESTORE_EMULATOR_HOST set). Needs Application Default Credentials for
// dev (`gcloud auth application-default login`).

import { initializeApp } from "firebase-admin/app";
import { type Firestore, getFirestore, Timestamp } from "firebase-admin/firestore";

import { millisOf, ownersCollection } from "../src/devices/owners";

export const devProject = "frisbee-app-brianrhonea-dev";

/** Throws unless [project] is the dev project or an emulator is in use. */
export function assertAllowedProject(project: string | undefined, emulatorHost: string | undefined): void {
  if (emulatorHost) return;
  if (project !== devProject) {
    throw new Error(`Refusing to run against "${project ?? ""}": only ${devProject} or a Firestore emulator.`);
  }
}

export interface Device {
  uid: string;
  fid: string;
  at: number;
}

export interface Plan {
  /** The newest registration of each FID. */
  owners: Device[];
  /** Older accounts' registrations of a FID someone newer registered. */
  losers: Device[];
}

/** Newest updatedAt wins; a tie goes to the larger uid, so reruns agree. */
export function planBackfill(devices: Device[]): Plan {
  const byFid = new Map<string, Device[]>();
  for (const d of devices) byFid.set(d.fid, [...(byFid.get(d.fid) ?? []), d]);
  const owners: Device[] = [];
  const losers: Device[] = [];
  for (const group of byFid.values()) {
    const sorted = [...group].sort((a, b) => b.at - a.at || (a.uid < b.uid ? 1 : -1));
    owners.push(sorted[0]);
    losers.push(...sorted.slice(1));
  }
  return { owners, losers };
}

export async function runBackfill(db: Firestore, apply: boolean, log: (m: string) => void = console.log) {
  const snap = await db.collectionGroup("devices").get();
  const devices: Device[] = [];
  for (const d of snap.docs) {
    // Only users/{uid}/devices, whatever else is named "devices".
    const user = d.ref.parent.parent;
    if (!user || user.parent.id !== "users") continue;
    devices.push({ uid: user.id, fid: d.id, at: millisOf(d.get("updatedAt"), 0) });
  }
  const plan = planBackfill(devices);
  log(`${devices.length} devices, ${plan.owners.length} FIDs, ${plan.losers.length} stale copies.`);
  for (const l of plan.losers) log(`${apply ? "delete" : "would delete"} users/${l.uid}/devices/${l.fid}`);

  if (!apply) {
    log("Dry run: nothing written. Rerun with --apply.");
    return { ...plan, written: 0, deleted: 0 };
  }
  let written = 0;
  for (const o of plan.owners) {
    // Keep a mapping the trigger already wrote if it is at least as new.
    await db.runTransaction(async (tx) => {
      const ref = db.collection(ownersCollection).doc(o.fid);
      const current = await tx.get(ref);
      if (current.exists && millisOf(current.get("updatedAt"), 0) >= o.at) return;
      tx.set(ref, { uid: o.uid, updatedAt: Timestamp.fromMillis(o.at) });
      written++;
    });
  }
  let deleted = 0;
  for (const l of plan.losers) {
    await db.doc(`users/${l.uid}/devices/${l.fid}`).delete();
    deleted++;
  }
  log(`Wrote ${written} mappings, deleted ${deleted} stale device docs.`);
  return { ...plan, written, deleted };
}

async function main() {
  const args = process.argv.slice(2);
  const i = args.indexOf("--project");
  const project = i >= 0 ? args[i + 1] : undefined;
  if (!project || project.startsWith("--")) {
    console.error("usage: tsx scripts/backfill-fid-owners.ts --project <id> [--apply]");
    process.exit(2);
  }
  try {
    assertAllowedProject(project, process.env.FIRESTORE_EMULATOR_HOST);
  } catch (e) {
    console.error(String(e instanceof Error ? e.message : e));
    process.exit(2);
  }
  initializeApp({ projectId: project });
  await runBackfill(getFirestore(), args.includes("--apply"));
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
