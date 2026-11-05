import { readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import {
  appPermissions,
  channelPermissions,
  type GuildTemplate,
  mapTemplate,
  maxRoles,
  Perm,
  templateCode,
} from "../../src/discord/template";

const fixture = JSON.parse(
  readFileSync(join(__dirname, "../fixtures/discord_template_synthetic.json"), "utf8"),
) as GuildTemplate;

describe("templateCode", () => {
  it("reads codes from template links and bare codes", () => {
    expect(templateCode("https://discord.new/abc123XYZ")).toBe("abc123XYZ");
    expect(templateCode("discord.new/abc123XYZ")).toBe("abc123XYZ");
    expect(templateCode("https://discord.com/template/abc123XYZ")).toBe("abc123XYZ");
    expect(templateCode("https://www.discord.com/template/abc123XYZ?x=1")).toBe("abc123XYZ");
    expect(templateCode("  abc123XYZ  ")).toBe("abc123XYZ");
  });

  it("rejects anything else", () => {
    expect(templateCode("https://discord.gg/invite123")).toBeNull();
    expect(templateCode("https://evil.example/template/abc123")).toBeNull();
    expect(templateCode("https://discord.com/channels/1/2")).toBeNull();
    expect(templateCode("not a link at all")).toBeNull();
    expect(templateCode(42)).toBeNull();
  });
});

describe("appPermissions", () => {
  it("maps Discord bits to app permissions", () => {
    expect(appPermissions(Perm.manageChannels | Perm.manageMessages)).toEqual(["manageChats", "moderate"]);
    expect(appPermissions(Perm.kickMembers)).toEqual(["manageMembers"]);
    expect(appPermissions(Perm.manageEvents | Perm.manageGuild)).toEqual(["manageTeam", "manageEvents"]);
    expect(appPermissions(0n)).toEqual([]);
  });

  it("gives administrators everything but stats", () => {
    expect(appPermissions(Perm.administrator)).toEqual([
      "manageTeam",
      "manageMembers",
      "manageChats",
      "manageEvents",
      "moderate",
    ]);
  });
});

describe("channelPermissions", () => {
  const everyone = Perm.viewChannel | Perm.sendMessages;

  it("applies @everyone's overwrite, then the role's", () => {
    const overwrites = [
      { id: 0, type: 0, allow: "0", deny: String(Perm.viewChannel) },
      { id: 7, type: 0, allow: String(Perm.viewChannel), deny: "0" },
    ];
    const base = channelPermissions(everyone, null, overwrites, "0");
    expect(base & Perm.viewChannel).toBe(0n);
    const role = channelPermissions(everyone, { key: "7", perms: 0n }, overwrites, "0");
    expect(role & Perm.viewChannel).toBe(Perm.viewChannel);
    const other = channelPermissions(everyone, { key: "8", perms: 0n }, overwrites, "0");
    expect(other & Perm.viewChannel).toBe(0n);
  });

  it("ignores member overwrites and lets administrators through", () => {
    const overwrites = [
      { id: 0, type: 0, allow: "0", deny: String(Perm.viewChannel) },
      { id: 9, type: 1, allow: String(Perm.viewChannel), deny: "0" },
    ];
    expect(channelPermissions(everyone, { key: "9", perms: 0n }, overwrites, "0") & Perm.viewChannel).toBe(0n);
    expect(
      channelPermissions(everyone, { key: "1", perms: Perm.administrator }, overwrites, "0") & Perm.viewChannel,
    ).toBe(Perm.viewChannel);
  });
});

describe("mapTemplate", () => {
  const plan = mapTemplate(fixture);

  it("names the server", () => {
    expect(plan.serverName).toBe("Rockets Ultimate");
  });

  it("imports roles highest first, without @everyone", () => {
    expect(plan.roles.map((r) => [r.key, r.name, r.position])).toEqual([
      ["4", "Admin", 0],
      ["3", "Captains", 1],
      ["2", "Moderator", 2],
      ["1", "Handlers", 3],
    ]);
    const [admin, captains, moderator, handlers] = plan.roles;
    expect(admin.color).toBe(0xffe74c3c);
    expect(handlers.color).toBe(0);
    expect(captains.perms).toEqual(["manageMembers", "manageChats", "manageEvents"]);
    expect(moderator.perms).toEqual(["moderate"]);
    expect(handlers.perms).toEqual([]);
    expect(plan.skippedRoles).toEqual([]);
  });

  it("turns categories into folders with their access", () => {
    expect(plan.folders).toEqual([
      { key: "10", name: "Info", position: 0, readRoles: ["everyone"], writeRoles: ["4", "3"] },
      { key: "20", name: "Team", position: 1, readRoles: ["everyone"], writeRoles: ["everyone"] },
    ]);
  });

  it("turns text, announcement and forum channels into rooms", () => {
    expect(plan.rooms.map((r) => [r.name, r.folderKey, r.position])).toEqual([
      ["announcements", "10", 0],
      ["general", "20", 0],
      ["rules", "10", 1],
      ["handlers-only", "20", 1],
      ["captains", "20", 2],
      ["off-topic", null, 0],
      ["drills", "20", 3],
    ]);
    expect(plan.skipped).toEqual([{ name: "Practice voice", reason: "Voice channel" }]);
  });

  it("works out who can read and write each room", () => {
    const access = Object.fromEntries(plan.rooms.map((r) => [r.name, [r.readRoles, r.writeRoles]]));
    // Everyone reads; only Captains (by overwrite) and Admin post.
    expect(access["announcements"]).toEqual([["everyone"], ["4", "3"]]);
    // Everyone reads; Captains' overwrite isn't on this channel.
    expect(access["rules"]).toEqual([["everyone"], ["4"]]);
    // Hidden from everyone; Handlers see it and can post (sending isn't denied).
    expect(access["handlers-only"]).toEqual([
      ["4", "1"],
      ["4", "1"],
    ]);
    expect(access["captains"]).toEqual([
      ["4", "3"],
      ["4", "3"],
    ]);
    expect(access["general"]).toEqual([["everyone"], ["everyone"]]);
  });

  it("keeps at most the app's number of roles", () => {
    const many: GuildTemplate = {
      serialized_source_guild: {
        roles: [
          { id: 0, name: "@everyone", permissions: "0" },
          ...Array.from({ length: maxRoles + 3 }, (_, i) => ({ id: i + 1, name: `R${i + 1}`, permissions: "0" })),
        ],
        channels: [],
      },
    };
    const p = mapTemplate(many);
    expect(p.roles).toHaveLength(maxRoles);
    expect(p.roles[0].name).toBe(`R${maxRoles + 3}`);
    expect(p.skippedRoles).toEqual(["R3", "R2", "R1"]);
  });

  it("copes with an empty template", () => {
    expect(mapTemplate({})).toEqual({
      serverName: "Discord server",
      roles: [],
      folders: [],
      rooms: [],
      skipped: [],
      skippedRoles: [],
    });
  });
});
