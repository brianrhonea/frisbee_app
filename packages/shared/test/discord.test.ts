// Ports of apps/mobile/test/ui/discord_import_test.dart (DiscordImport.of)
// and apps/mobile/test/domain/discord_team_split_test.dart
// (DiscordTeamSplit, TeamChatImport): the website and the API map a plan
// exactly as the app does.
import { describe, expect, it } from "vitest";
import {
  emptiedFolders,
  type ImportPlan,
  type ImportTeam,
  importIsEmpty,
  importPlanSchema,
  movingRooms,
  planFor,
  planImport,
  splitPlan,
  splitTeams,
  storedAccess,
  teamChatImport,
  teamChatImportIsEmpty,
} from "../src/discord.js";

/** What preview returns for the synthetic fixture (as the Dart test's planMap). */
const plan: ImportPlan = {
  serverName: "Rockets Ultimate",
  roles: [
    { key: "4", name: "Admin", color: 0xffe74c3c, position: 0, perms: ["manageTeam", "manageMembers", "manageChats", "manageEvents", "moderate"] },
    { key: "3", name: "Captains", color: 0xff3498db, position: 1, perms: ["manageMembers", "manageChats", "manageEvents"] },
    { key: "1", name: "Handlers", color: 0, position: 2, perms: [] },
  ],
  folders: [
    { key: "10", name: "Info", position: 0, readRoles: ["everyone"], writeRoles: ["4", "3"] },
    { key: "20", name: "Team", position: 1, readRoles: ["everyone"], writeRoles: ["everyone"] },
  ],
  rooms: [
    { name: "announcements", folderKey: "10", position: 0, readRoles: ["everyone"], writeRoles: ["4", "3"] },
    { name: "general", folderKey: "20", position: 0, readRoles: ["everyone"], writeRoles: ["everyone"] },
    { name: "handlers-only", folderKey: "20", position: 1, readRoles: ["4", "1"], writeRoles: ["4", "1"] },
    { name: "off-topic", folderKey: null, position: 0, readRoles: ["everyone"], writeRoles: ["everyone"] },
  ],
  skipped: [{ name: "Practice voice", reason: "Voice channel" }],
  skippedRoles: [],
};

let n = 0;
const ids = () => `id${++n}`;

describe("planImport (DiscordImport.of)", () => {
  it("maps template keys to new roles, folders and rooms", () => {
    n = 0;
    const i = planImport(plan, {}, [], [{ id: "general", name: "General", folderId: null, position: 0 }], ids);
    expect(i.newRoles).toEqual(["Admin", "Captains", "Handlers"]);
    const byName = Object.fromEntries(Object.entries(i.roles).map(([id, r]) => [r.name, { id, ...r }]));
    expect(byName.Admin!.position).toBe(0);
    expect(byName.Handlers!.position).toBe(2);
    expect(i.folders.map((f) => f.name)).toEqual(["Info", "Team"]);
    expect(new Set(i.folders[0]!.writeRoles)).toEqual(new Set([byName.Admin!.id, byName.Captains!.id]));
    expect(i.rooms.map((r) => r.name)).toEqual(["announcements", "general", "handlers-only", "off-topic"]);
    const handlersOnly = i.rooms[2]!;
    expect(handlersOnly.folderId).toBe(i.folders[1]!.id);
    expect(handlersOnly.position).toBe(1);
    expect(new Set(handlersOnly.readRoles)).toEqual(new Set([byName.Admin!.id, byName.Handlers!.id]));
    // "general" goes in the Team folder, so it doesn't clash with General; off-topic goes after General.
    expect(i.rooms[1]!.folderId).toBe(i.folders[1]!.id);
    expect(i.rooms[3]!.folderId).toBeNull();
    expect(i.rooms[3]!.position).toBe(1);
    expect(i.alreadyHere).toEqual([]);
    expect(importIsEmpty(i)).toBe(false);
  });

  it("importing again adds nothing", () => {
    const first = planImport(plan, {}, [], [], ids);
    const again = planImport(
      plan,
      { roles: first.roles },
      first.folders,
      first.rooms.map((r, k) => ({ ...r, id: `r${k}` })),
      ids,
    );
    expect(importIsEmpty(again)).toBe(true);
    expect(again.alreadyHere).toHaveLength(4);
    expect(Object.keys(again.roles)).toEqual(Object.keys(first.roles));
  });

  it("reuses roles by name and stays within the role limit", () => {
    const roles: ImportTeam["roles"] = { mine: { name: "handlers", position: 0 } };
    for (let k = 0; k < 48; k++) roles[`r${k}`] = { name: `Role ${k}`, position: k + 1 };
    const i = planImport(plan, { roles }, [], [], ids);
    expect(i.newRoles).toEqual(["Admin"]);
    expect(i.tooManyRoles).toEqual(["Captains"]);
    expect(Object.keys(i.roles)).toHaveLength(50);
    // Captains is dropped from access lists, narrowing access rather than widening it.
    expect(i.rooms.find((r) => r.name === "handlers-only")!.readRoles).toContain("mine");
    expect(i.rooms[0]!.writeRoles).toHaveLength(1);
  });

  it("stores write access folded into read (accessMap)", () => {
    expect(storedAccess({ readRoles: ["everyone"], writeRoles: ["b", "a"] })).toEqual({
      readRoles: ["a", "b", "everyone"],
      writeRoles: ["a", "b"],
      readUsers: [],
      writeUsers: [],
    });
  });
});

// A Discord server like the user's: Admin, Woof and Whiplash roles.
const orgPlan: ImportPlan = {
  serverName: "Tech Ultimate",
  roles: [
    { key: "r1", name: "Admin", color: 0, position: 0, perms: [] },
    { key: "r2", name: "Woof Captain", color: 0, position: 1, perms: [] },
    { key: "r3", name: "Woof Player", color: 0, position: 2, perms: [] },
    { key: "r4", name: "Whiplash Coach", color: 0, position: 3, perms: [] },
  ],
  folders: [{ key: "f1", name: "Woof", position: 0, readRoles: ["r1", "r2", "r3"], writeRoles: [] }],
  rooms: [
    { name: "general", folderKey: null, position: 0, readRoles: ["everyone"], writeRoles: [] },
    { name: "woof-chat", folderKey: "f1", position: 0, readRoles: ["r1", "r2", "r3"], writeRoles: ["r2", "r3"] },
    { name: "woof-captains", folderKey: "f1", position: 1, readRoles: ["r1", "r2"], writeRoles: ["r2"] },
    { name: "admin", folderKey: null, position: 1, readRoles: ["r1"], writeRoles: [] },
    { name: "captains", folderKey: null, position: 2, readRoles: ["r2", "r4"], writeRoles: [] },
  ],
  skipped: [],
  skippedRoles: [],
};
const roleIds = { r1: "admin", r2: "woofCap", r3: "woofP", r4: "whipC" };
const org: ImportTeam = {
  roles: {
    admin: { name: "Admin", position: 0 },
    woofCap: { name: "Woof Captain", position: 1, perms: ["manageEvents"] },
    woofP: { name: "Woof Player", position: 2 },
    whipC: { name: "Whiplash Coach", position: 3 },
  },
  linkedTeams: {
    woof: { name: "Woof", roles: ["woofCap", "woofP"] },
    whip: { name: "Whiplash", roles: ["whipC"] },
  },
};

describe("splitPlan (DiscordTeamSplit)", () => {
  it("rooms only one team reads go to it; the rest stay", () => {
    const split = splitPlan(orgPlan, org, roleIds);
    expect(split.destinations).toEqual([null, "woof", "woof", null, null]);
    expect(splitTeams(split)).toEqual(new Set(["woof"]));
    expect(planFor(orgPlan, split, "woof").rooms.map((r) => r.name)).toEqual(["woof-chat", "woof-captains"]);
    expect(planFor(orgPlan, split, "woof").folders.map((f) => f.name)).toEqual(["Woof"]);
    expect(planFor(orgPlan, split, null).rooms.map((r) => r.name)).toEqual(["general", "admin", "captains"]);
    expect(planFor(orgPlan, split, null).folders).toEqual([]);
  });

  it("the owner can send a room somewhere else", () => {
    const split = splitPlan(
      orgPlan,
      org,
      roleIds,
      new Map<number, string | null>([
        [1, null],
        [4, "whip"],
        [3, "nowhere"],
      ]),
    );
    expect(split.destinations).toEqual([null, null, "woof", null, "whip"]);
    expect(split.suggested[1]).toBe("woof");
  });

  it("a team gets copies of its roles, and rooms open to the team", () => {
    const split = splitPlan(orgPlan, org, roleIds);
    let k = 0;
    const t = teamChatImport(planFor(orgPlan, split, "woof"), org, "woof", {}, roleIds, [], [], () => `id${k++}`);
    const roles = Object.entries(t.import.roles).map(([id, r]) => ({ id, ...r }));
    expect(roles.map((r) => r.name)).toEqual(["Woof Captain", "Woof Player"]);
    const cap = roles.find((r) => r.name === "Woof Captain")!;
    expect(cap.perms).toEqual(["manageEvents"]);
    expect(new Set(Object.values(t.orgRoles))).toEqual(new Set(["woofCap", "woofP"]));
    expect(t.orgRoles[cap.id]).toBe("woofCap");
    expect(t.import.rooms.find((r) => r.name === "woof-chat")!.readRoles).toEqual(["everyone"]);
    const captains = t.import.rooms.find((r) => r.name === "woof-captains")!;
    expect(captains.readRoles).toEqual([cap.id]);
    expect(captains.writeRoles).toEqual([cap.id]);
    expect(t.import.folders.map((f) => f.name)).toEqual(["Woof"]);

    // Running it again reuses the copies and adds nothing.
    const team = { roles: t.import.roles, orgRoles: t.orgRoles };
    const again = teamChatImport(
      planFor(orgPlan, split, "woof"),
      org,
      "woof",
      team,
      roleIds,
      t.import.folders,
      t.import.rooms.map((r) => ({ ...r, id: r.name })),
    );
    expect(teamChatImportIsEmpty(again, team)).toBe(true);
  });

  it("finds the community's old copies of rooms that now go to a team", () => {
    const split = splitPlan(orgPlan, org, roleIds);
    const folders = [{ id: "fW", name: "woof" }];
    const rooms = [
      { id: "old", name: "Woof-Chat", folderId: "fW" },
      { id: "cap", name: "woof-captains", folderId: "fW" },
      { id: "gen", name: "general", folderId: null },
    ];
    const moving = movingRooms(orgPlan, split, folders, rooms);
    expect(moving.map((r) => r.id)).toEqual(["old", "cap"]);
    expect(emptiedFolders(moving, folders, rooms).map((f) => f.id)).toEqual(["fW"]);
    expect(emptiedFolders(moving.slice(0, 1), folders, rooms)).toEqual([]);
  });
});

describe("plan keys", () => {
  it("refuses Object.prototype's names, so lookups can't reach inherited values", () => {
    for (const key of ["__proto__", "constructor", "toString"]) {
      const bad = { ...plan, roles: [{ ...plan.roles[0]!, key }] };
      expect(importPlanSchema.safeParse(bad).success).toBe(false);
    }
    expect(importPlanSchema.safeParse(plan).success).toBe(true);
  });

  it("never moves the General room out", () => {
    const split = { destinations: plan.rooms.map(() => "t2"), teams: [] } as unknown as Parameters<typeof movingRooms>[1];
    const rooms = [
      { id: "general", name: "general", folderId: "f20" },
      { id: "r2", name: "off-topic", folderId: null },
    ];
    const moving = movingRooms(plan, split, [{ id: "f20", name: "Team" }], rooms);
    expect(moving.map((r) => r.id)).toEqual(["r2"]);
  });
});
