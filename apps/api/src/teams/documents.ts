// The documents a new team starts with. Mirrors newTeamDocs in
// apps/mobile/lib/data/repositories/team/team_repository_firebase.dart;
// both are checked against packages/shared/fixtures/team_create.json.
import { type CreateTeamInput, type GroupLocation, isGroupLike, searchKeywords } from "@stall10/shared";

export interface Owner {
  uid: string;
  label: string;
}

type Doc<T> = Record<string, unknown> & { createdAt?: T };

const everyone = ["everyone"];
const openAccess = () => ({
  readRoles: [...everyone],
  writeRoles: [...everyone],
  readUsers: [] as string[],
  writeUsers: [] as string[],
});

const generalRoomId = "general";
const voiceFolderId = "voice";
const voiceRooms: ReadonlyArray<readonly [string, string]> = [
  ["voice-lounge", "Lounge"],
  ["voice-sideline", "Sideline"],
  ["voice-film", "Film Room"],
];

/** A group's own fields (communityFields in the app); none for a team. */
function communityFields(t: CreateTeamInput, location: GroupLocation | null) {
  return isGroupLike(t.kind)
    ? { kind: t.kind, description: t.description, requiresApproval: t.requiresApproval, location }
    : {};
}

/** The community a new team is made in (NewTeam.inCommunity in the app). */
export interface OrgRef {
  id: string;
  name: string;
}

/**
 * Every document a new team starts with, by path, with [createdAt] as each
 * timestamp (FieldValue.serverTimestamp() when writing). A team made in a
 * community ([org]) names it (orgId, orgName).
 */
export function newTeamDocuments<T>(
  teamId: string,
  t: CreateTeamInput,
  owner: Owner,
  createdAt: T,
  org?: OrgRef,
): Record<string, Doc<T>> {
  // A private group's location is for members only.
  const privateGroup = isGroupLike(t.kind) && t.requiresApproval;
  const base = { name: t.name, division: t.division, level: t.level, city: t.city };
  const room = (name: string, kind: "text" | "voice", folderId: string | null, position: number) => ({
    name,
    ...openAccess(),
    folderId,
    position,
    kind,
    createdBy: owner.uid,
    createdAt,
  });

  const docs: Record<string, Doc<T>> = {
    [`teams/${teamId}`]: {
      ...base,
      ...communityFields(t, t.location),
      ...(org && { orgId: org.id, orgName: org.name }),
      ...(t.leagueId != null && { leagueId: t.leagueId }),
      ownerId: owner.uid,
      members: { [owner.uid]: "owner" },
      memberIds: [owner.uid],
      memberNames: { [owner.uid]: owner.label },
      createdAt,
    },
    [`teamDirectory/${teamId}`]: {
      ...base,
      ...communityFields(t, privateGroup ? null : t.location),
      keywords: searchKeywords(`${t.name} ${t.city}`),
    },
    [`teams/${teamId}/chats/${generalRoomId}`]: room("General", "text", null, 0),
    [`teams/${teamId}/chatFolders/${voiceFolderId}`]: {
      name: "Voice Channels",
      position: 1000,
      ...openAccess(),
      createdBy: owner.uid,
      createdAt,
    },
  };
  voiceRooms.forEach(([id, name], i) => {
    docs[`teams/${teamId}/chats/${id}`] = room(name, "voice", voiceFolderId, i);
  });
  return docs;
}
