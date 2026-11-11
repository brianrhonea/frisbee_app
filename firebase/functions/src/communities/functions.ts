import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

import {
  type Data,
  isOrg,
  membershipUpdate,
  mirrorUpdate,
  type OrgDoc,
  planOrgChange,
  syncUpdate,
  type TeamDoc,
} from "./model";

/**
 * Keeps school and club communities and their teams in step (see
 * model.ts). On a community: people who gain one of a team's roles join
 * the team, those who lose it leave (if the community added them), and a
 * team the community lists or drops is linked or let go. On a team: one
 * that stops naming its community leaves it, and one that names a
 * community already listing it is linked.
 */
export const sync = onDocumentWritten("teams/{teamId}", async (event) => {
  const { teamId } = event.params;
  const before = event.data?.before.data() as Data | undefined;
  const after = event.data?.after.data() as Data | undefined;
  if (isOrg(before as OrgDoc) || isOrg(after as OrgDoc)) {
    await syncOrg(teamId, before as OrgDoc | undefined, after as OrgDoc | undefined);
  } else {
    await syncTeam(teamId, before as TeamDoc | undefined, after as TeamDoc | undefined);
  }
});

async function syncOrg(orgId: string, before: OrgDoc | undefined, after: OrgDoc | undefined) {
  const db = getFirestore();
  for (const change of planOrgChange(before, after)) {
    const ref = db.doc(`teams/${change.teamId}`);
    await db.runTransaction(async (tx) => {
      const team = (await tx.get(ref)).data() as TeamDoc | undefined;
      // Only a team that asked to be in this community.
      if (!team || team.orgId !== orgId) return;
      const names = after?.memberNames ?? before?.memberNames ?? {};
      if (!change.listed) {
        const update = membershipUpdate(team, [], team.orgMembers ?? [], names) ?? {};
        // Its copies of community roles become plain team roles.
        tx.update(ref, { ...update, orgId: null, orgName: "", orgLinked: false, orgMembers: [], orgRoles: {} });
        logger.info("Team left its community", { orgId, teamId: change.teamId });
        return;
      }
      const joining = team.orgLinked !== true;
      const update =
        syncUpdate(team, after, joining ? change.all : change.add, joining ? [] : change.remove, names) ?? {};
      if (joining) Object.assign(update, { orgLinked: true });
      if (joining || change.renamed) Object.assign(update, { orgName: (after?.name ?? "").slice(0, 80) });
      if (Object.keys(update).length > 0) tx.update(ref, update);
    });
  }
}

async function syncTeam(teamId: string, before: TeamDoc | undefined, after: TeamDoc | undefined) {
  const was = before?.orgId ?? null;
  const now = after?.orgId ?? null;
  const db = getFirestore();
  if (was === now) {
    if (now && after?.orgLinked && mirrorInputsChanged(before, after)) await mirror(teamId, now);
    return;
  }

  // Left (or deleted): drop who the community added, and the listing.
  if (was && before?.orgLinked) {
    if (after) {
      const ref = db.doc(`teams/${teamId}`);
      await db.runTransaction(async (tx) => {
        const team = (await tx.get(ref)).data() as TeamDoc | undefined;
        if (!team || (team.orgId ?? null) === was) return;
        const update = membershipUpdate(team, [], team.orgMembers ?? [], {}) ?? {};
        tx.update(ref, { ...update, orgLinked: false, orgMembers: [], orgRoles: {} });
      });
    }
    await db
      .doc(`teams/${was}`)
      .update({ [`linkedTeams.${teamId}`]: FieldValue.delete() })
      .catch((e) => logger.warn("Couldn't unlist team", { orgId: was, teamId, error: String(e) }));
  }

  // Named a community that already lists it (e.g. created inside it).
  if (now && after) {
    const org = (await db.doc(`teams/${now}`).get()).data() as OrgDoc | undefined;
    if (!org || !isOrg(org) || !org.linkedTeams?.[teamId]) return;
    const change = planOrgChange({ ...org, linkedTeams: {} }, org).find((c) => c.teamId === teamId);
    const ref = db.doc(`teams/${teamId}`);
    await db.runTransaction(async (tx) => {
      const team = (await tx.get(ref)).data() as TeamDoc | undefined;
      if (!team || team.orgId !== now || team.orgLinked) return;
      const update = syncUpdate(team, org, change?.all ?? [], [], org.memberNames ?? {}) ?? {};
      tx.update(ref, { ...update, orgLinked: true, orgName: (org.name ?? "").slice(0, 80) });
    });
  }
}

/** What decides who holds a team's copies of community roles. */
function mirrorInputsChanged(before: TeamDoc | undefined, after: TeamDoc): boolean {
  const key = (t: TeamDoc | undefined) =>
    JSON.stringify([t?.orgRoles ?? {}, Object.keys(t?.roles ?? {}).sort(), [...(t?.memberIds ?? [])].sort()]);
  return key(before) !== key(after);
}

/** Brings a linked team's copies of community roles in step. */
async function mirror(teamId: string, orgId: string) {
  const db = getFirestore();
  const org = (await db.doc(`teams/${orgId}`).get()).data() as OrgDoc | undefined;
  if (!org || !isOrg(org) || !org.linkedTeams?.[teamId]) return;
  const ref = db.doc(`teams/${teamId}`);
  await db.runTransaction(async (tx) => {
    const team = (await tx.get(ref)).data() as TeamDoc | undefined;
    if (!team || team.orgId !== orgId || !team.orgLinked) return;
    const update = mirrorUpdate(team, org);
    if (update) tx.update(ref, update);
  });
}
