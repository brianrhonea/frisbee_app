// Visitors' tournament pages (`/v1/public/tournaments*`) with fakes: open
// without a token, the rules' visible() (no drafts) plus private-group
// hosts hidden, nothing about people in the answers, and the visitor limit.
import { publicDraftedName } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { BrowseRepository } from "../src/browse/repository.js";
import { webKeyHeader } from "../src/browse/routes.js";
import type { RateLimiter } from "../src/limits/limiter.js";
import type { Data, Doc, PublicTournamentRepository } from "../src/tournaments/public_repository.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.parse("2026-11-15T18:00:00Z");
const day = 24 * 60 * 60 * 1000;
const iso = (ms: number) => new Date(ms).toISOString();

class FakeTournaments implements PublicTournamentRepository {
  tournaments = new Map<string, Data>();
  divisionDocs = new Map<string, Doc[]>();
  entryDocs = new Map<string, Doc[]>();
  gameDocs = new Map<string, Doc[]>();
  listingMap = new Map<string, Data>();
  groupListings = new Map<string, Data>();
  gamesAsked: string[] = [];
  endingFails = false;

  private upcoming(field: string, statuses: readonly string[], since: Date, max: number) {
    return [...this.tournaments]
      .filter(([, d]) => statuses.includes(d.status as string) && typeof d[field] === "string" && Date.parse(d[field] as string) >= since.getTime())
      .sort(([, a], [, b]) => (a[field] as string).localeCompare(b[field] as string))
      .slice(0, max)
      .map(([id, data]) => ({ id, data }));
  }
  async startingFrom(statuses: readonly string[], since: Date, max: number) {
    return this.upcoming("startsOn", statuses, since, max);
  }
  async endingFrom(statuses: readonly string[], since: Date, max: number) {
    if (this.endingFails) throw new Error("needs an index");
    return this.upcoming("endsOn", statuses, since, max);
  }
  async tournament(id: string) {
    return this.tournaments.get(id) ?? null;
  }
  async divisions(id: string) {
    return this.divisionDocs.get(id) ?? [];
  }
  async entries(id: string) {
    // As the Firestore query's select(): these three fields only.
    return (this.entryDocs.get(id) ?? []).map((e) => ({
      id: e.id,
      data: { teamName: e.data.teamName, divisionId: e.data.divisionId, status: e.data.status },
    }));
  }
  async games(id: string, divisionId: string) {
    this.gamesAsked.push(`${id}/${divisionId}`);
    return this.gameDocs.get(`${id}/${divisionId}`) ?? [];
  }
  async listings(ids: string[]) {
    return new Map(ids.flatMap((id) => (this.listingMap.has(id) ? [[id, this.listingMap.get(id)!] as const] : [])));
  }
  async groupListing(id: string) {
    return this.groupListings.get(id) ?? null;
  }
}

class FakeLimiter implements RateLimiter {
  allow = true;
  keys: string[] = [];
  async admit(key: string) {
    this.keys.push(key);
    return this.allow;
  }
}

const noBrowse = {} as BrowseRepository;

function setup(opts: { webServerKey?: string; enforceAppCheck?: boolean } = {}) {
  const repo = new FakeTournaments();
  const limiter = new FakeLimiter();
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    now: () => now,
    enforceAppCheck: opts.enforceAppCheck,
    browse: { repo: noBrowse, limiter, imageUrl: (p) => p, webServerKey: opts.webServerKey },
    publicTournaments: repo,
  });
  const get = (url: string, headers: Record<string, string> = {}) => app.inject({ method: "GET", url, headers });
  return { app, repo, limiter, get };
}

const fee = { amountCents: 2500, currency: "USD", instructions: "Venmo @host-person, or call 555-0100", dueAt: iso(now + 3 * day) };

/** A tournament document as the app writes it (HostedTournament.toMap). */
const tournament = (extra: Data = {}): Data => ({
  hostId: "club",
  hostName: "Austin Ultimate",
  hostKind: "organization",
  hostOfficial: false,
  name: "Fall Classic",
  startsOn: iso(now + 5 * day),
  endsOn: iso(now + 6 * day),
  description: "Two days of games.",
  location: "Zilker Park",
  visibility: "public",
  entryType: "teams",
  status: "registration",
  bidFee: fee,
  kind: "tournament",
  season: null,
  draftMode: "balanced",
  divisions: [
    { id: "open", division: "open", level: "club" },
    { id: "mixed", division: "mixed", level: "youth" },
  ],
  format: null,
  createdBy: "hostUid",
  createdAt: iso(now - 30 * day),
  ...extra,
});

const settings = {
  format: "poolsSingleElim",
  playersOnField: 7,
  poolCount: 2,
  gameMinutes: 90,
  breakMinutes: 15,
  scoreCap: 15,
  timeoutsPerHalf: 2,
  fields: 4,
  startsAt: iso(now + 5 * day),
  idealEndsAt: null,
  laterDays: [iso(now + 6 * day)],
  scoring: "points",
};

const division = (extra: Data = {}): Data => ({
  division: "open",
  level: "club",
  settings,
  maxTeams: 8,
  seeds: ["haze", "doublewide"],
  captains: { haze: ["capUid1"], doublewide: ["capUid2"] },
  placements: [],
  minRoster: 12,
  teams: [],
  ...extra,
});

const entry = (id: string, teamName: string, status: string, divisionId = "open"): Doc => ({
  id,
  data: { teamName, divisionId, status, captainIds: [`${id}Captain`], updatedAt: iso(now) },
});

const gameDoc = (id: string, extra: Data = {}): Doc => ({
  id,
  data: {
    order: 0,
    stage: "pool",
    round: 1,
    label: "Pool A",
    pool: "A",
    field: 1,
    startsAt: iso(now + 5 * day),
    teamA: "haze",
    teamB: "doublewide",
    sourceA: null,
    sourceB: null,
    status: "done",
    scoreA: 15,
    scoreB: 12,
    report: null,
    ifNeeded: false,
    ...extra,
  },
});

/** Every string anywhere in [value]. */
function strings(value: unknown): string[] {
  if (typeof value === "string") return [value];
  if (Array.isArray(value)) return value.flatMap(strings);
  if (value && typeof value === "object") return Object.entries(value).flatMap(([k, v]) => [k, ...strings(v)]);
  return [];
}

describe("visitors' tournament pages", () => {
  let t: ReturnType<typeof setup>;
  beforeEach(() => {
    t = setup();
    t.repo.listingMap.set("club", { name: "Austin Ultimate", kind: "organization", requiresApproval: false });
    t.repo.listingMap.set("secret", { name: "Secret Pickup", kind: "community", requiresApproval: true });
    t.repo.listingMap.set("team1", { name: "Haze", kind: "team", requiresApproval: true });
  });

  describe("GET /v1/public/tournaments", () => {
    it("lists upcoming published events without a token, soonest first, cached publicly", async () => {
      t.repo.tournaments.set("later", tournament({ name: "Later", startsOn: iso(now + 20 * day), endsOn: null }));
      t.repo.tournaments.set("soon", tournament({ name: "Soon", status: "live", startsOn: iso(now - day), endsOn: iso(now) }));
      // A league that began weeks ago and still runs.
      t.repo.tournaments.set("league", tournament({ name: "League", kind: "league", status: "scheduled", startsOn: iso(now - 40 * day), endsOn: iso(now + 20 * day) }));
      const res = await t.get("/v1/public/tournaments");
      expect(res.statusCode).toBe(200);
      expect(res.headers["cache-control"]).toMatch(/^public, max-age=30/);
      expect(res.json().tournaments.map((x: { id: string }) => x.id)).toEqual(["league", "soon", "later"]);
    });

    it("hides drafts, finished ones, and events of private groups or hosts without a listing", async () => {
      t.repo.tournaments.set("draft", tournament({ status: "draft" }));
      t.repo.tournaments.set("done", tournament({ status: "finished" }));
      t.repo.tournaments.set("odd", tournament({ status: "archived" }));
      t.repo.tournaments.set("private", tournament({ hostId: "secret", hostKind: "community" }));
      t.repo.tournaments.set("ghost", tournament({ hostId: "gone" }));
      // A team that requires approval isn't a private group: its events show.
      t.repo.tournaments.set("teamHosted", tournament({ hostId: "team1", hostKind: "team" }));
      t.repo.tournaments.set("ok", tournament());
      const ids = (await t.get("/v1/public/tournaments")).json().tournaments.map((x: { id: string }) => x.id);
      expect(ids.sort()).toEqual(["ok", "teamHosted"]);
    });

    it("gives cards' fields only: no fee instructions or who made it", async () => {
      t.repo.tournaments.set("ok", tournament({ visibility: "inviteOnly" }));
      const [card] = (await t.get("/v1/public/tournaments")).json().tournaments;
      expect(card).toEqual({
        id: "ok",
        hostId: "club",
        hostName: "Austin Ultimate",
        hostKind: "organization",
        hostOfficial: false,
        name: "Fall Classic",
        startsOn: iso(now + 5 * day),
        endsOn: iso(now + 6 * day),
        location: "Zilker Park",
        visibility: "inviteOnly",
        entryType: "teams",
        teamEntry: false,
        kind: "tournament",
        status: "registration",
        bidFee: { amountCents: 2500, currency: "USD", dueAt: fee.dueAt },
        divisions: [
          { id: "open", division: "open", level: "club" },
          { id: "mixed", division: "mixed", level: "youth" },
        ],
      });
    });

    it("still lists what's starting when the running query fails", async () => {
      t.repo.endingFails = true;
      t.repo.tournaments.set("ok", tournament());
      expect((await t.get("/v1/public/tournaments")).json().tournaments).toHaveLength(1);
    });
  });

  describe("GET /v1/public/tournaments/:id", () => {
    beforeEach(() => {
      t.repo.tournaments.set("fall", tournament({ status: "live" }));
      t.repo.divisionDocs.set("fall", [
        { id: "mixed", data: division({ division: "mixed", level: "youth", seeds: ["kids"], captains: { kids: ["kidCaptain"] } }) },
        { id: "open", data: division({ placements: ["haze", "doublewide"] }) },
        // Not in the tournament's list any more.
        { id: "stray", data: division() },
      ]);
      t.repo.entryDocs.set("fall", [
        entry("haze", "Haze", "accepted"),
        entry("doublewide", "Doublewide", "accepted"),
        entry("kids", "Austin Youth", "accepted", "mixed"),
        entry("hopeful", "Hopeful Hucks", "applied"),
        entry("waiting", "Waitlisted Wonders", "waitlisted"),
        entry("asked", "Invited Ones", "invited"),
        entry("nope", "Declined Discs", "declined"),
      ]);
      t.repo.gameDocs.set("fall/open", [
        gameDoc("g1"),
        gameDoc("g2", { order: 1, teamA: "haze", teamB: null, sourceB: { type: "winner", game: "g1" }, status: "reported", scoreA: null, scoreB: null, report: { scoreA: 15, scoreB: 9, byTeam: "haze" } }),
      ]);
      t.repo.gameDocs.set("fall/mixed", [gameDoc("m1", { teamA: "kids", teamB: null, status: "scheduled", scoreA: null, scoreB: null })]);
    });

    it("shows the page without a token: overview, divisions in order, accepted teams, the first division's games", async () => {
      const res = await t.get("/v1/public/tournaments/fall");
      expect(res.statusCode).toBe(200);
      expect(res.headers["cache-control"]).toMatch(/^public/);
      const page = res.json();
      expect(page.tournament).toMatchObject({ id: "fall", name: "Fall Classic", description: "Two days of games.", status: "live", teamFee: null, season: null, draftMode: "balanced" });
      expect(page.divisions.map((d: { id: string }) => d.id)).toEqual(["open", "mixed"]);
      expect(page.divisions[0]).toEqual({
        id: "open",
        division: "open",
        level: "club",
        settings,
        maxTeams: 8,
        minRoster: 12,
        seeds: ["haze", "doublewide"],
        placements: ["haze", "doublewide"],
        teams: [],
      });
      expect(page.divisionId).toBe("open");
      expect(page.games.map((g: { id: string }) => g.id)).toEqual(["g1", "g2"]);
      expect(page.games[0]).toMatchObject({ teamA: "haze", teamB: "doublewide", scoreA: 15, scoreB: 12, status: "done", field: 1, pool: "A" });
      expect(page.games[1].report).toEqual({ scoreA: 15, scoreB: 9, byTeam: "haze" });
      expect(page.entries).toEqual([
        { id: "kids", teamName: "Austin Youth", divisionId: "mixed", status: "accepted" },
        { id: "doublewide", teamName: "Doublewide", divisionId: "open", status: "accepted" },
        { id: "haze", teamName: "Haze", divisionId: "open", status: "accepted" },
      ]);
      expect(page.names).toEqual({ haze: "Haze", doublewide: "Doublewide", kids: "Austin Youth" });
    });

    it("gives another division's games with ?division=, and the first for an unknown one", async () => {
      const mixed = (await t.get("/v1/public/tournaments/fall?division=mixed")).json();
      expect(mixed.divisionId).toBe("mixed");
      expect(mixed.games.map((g: { id: string }) => g.id)).toEqual(["m1"]);
      expect((await t.get("/v1/public/tournaments/fall?division=stray")).json().divisionId).toBe("open");
      expect((await t.get("/v1/public/tournaments/fall?division=../x")).json().divisionId).toBe("open");
      expect(t.repo.gamesAsked).toEqual(["fall/mixed", "fall/open", "fall/open"]);
    });

    it("leaves out signups, captains, contact and payment details, and teams that aren't in", async () => {
      const body = (await t.get("/v1/public/tournaments/fall")).json();
      const all = strings(body);
      for (const hidden of [
        "capUid1",
        "kidCaptain",
        "hazeCaptain",
        "hostUid",
        "captains",
        "captainIds",
        "createdBy",
        "createdAt",
        "updatedAt",
        "instructions",
        fee.instructions,
        "Hopeful Hucks",
        "Waitlisted Wonders",
        "Invited Ones",
        "Declined Discs",
        "signups",
        "playerIds",
        "playerNames",
      ]) {
        expect(all, hidden).not.toContain(hidden);
      }
      expect(body.tournament.bidFee).toEqual({ amountCents: 2500, currency: "USD", dueAt: fee.dueAt });
      expect(Object.keys(body.tournament).sort()).toEqual(
        [
          "id",
          "hostId",
          "hostName",
          "hostKind",
          "hostOfficial",
          "name",
          "startsOn",
          "endsOn",
          "location",
          "visibility",
          "entryType",
          "teamEntry",
          "kind",
          "status",
          "bidFee",
          "divisions",
          "description",
          "teamFee",
          "season",
          "draftMode",
        ].sort(),
      );
    });

    it("gives drafted teams their id and name only, never a player's name", async () => {
      t.repo.tournaments.set("hat", tournament({ entryType: "players", kind: "league", season: { weeks: 6, playoffWeeks: 1, playoffTeams: 4, gamesPerNight: 1, skipDates: [] } }));
      t.repo.divisionDocs.set("hat", [
        {
          id: "open",
          data: division({
            level: "youth",
            seeds: ["d1", "d2", "d3"],
            captains: { d1: ["kid1"] },
            teams: [
              { id: "d1", name: "Team Riley", captainId: "kid1", playerIds: ["kid1", "kid2"], playerNames: { kid1: "Riley Parker", kid2: "Jo Smith" } },
              { id: "d2", name: "Sky Pilots", captainId: "kid3", playerIds: ["kid3"], playerNames: { kid3: "Max Lee" } },
              { id: "d3", name: "Parker's Picks", captainId: null, playerIds: ["kid4"], playerNames: { kid4: "Ava Parker" } },
            ],
          }),
        },
      ]);
      t.repo.entryDocs.set("hat", []);
      t.repo.gameDocs.set("hat/open", [gameDoc("w1", { teamA: "d1", teamB: "d2" })]);
      const body = (await t.get("/v1/public/tournaments/hat")).json();
      expect(body.divisions[0].teams).toEqual([
        { id: "d1", name: "Team 1" },
        { id: "d2", name: "Sky Pilots" },
        { id: "d3", name: "Team 3" },
      ]);
      expect(body.names).toEqual({ d1: "Team 1", d2: "Sky Pilots", d3: "Team 3" });
      expect(body.tournament.season).toEqual({ weeks: 6, playoffWeeks: 1, playoffTeams: 4, gamesPerNight: 1, skipDates: [] });
      const all = strings(body).join(" ");
      for (const name of ["Riley", "Parker", "Jo Smith", "Max Lee", "kid1", "kid3"]) expect(all).not.toContain(name);
    });

    it("hides drafts, even from their host's managers, and unknown ids, with the same 404", async () => {
      t.repo.tournaments.set("draft", tournament({ status: "draft" }));
      t.repo.tournaments.set("odd", tournament({ status: undefined }));
      for (const url of ["/v1/public/tournaments/draft", "/v1/public/tournaments/odd", "/v1/public/tournaments/none", "/v1/public/tournaments/bad%20id"]) {
        const res = await t.get(url, { authorization: "Bearer token:hostUid" });
        expect(res.statusCode, url).toBe(404);
        expect(res.json().error.message, url).toMatch(/isn't here/);
      }
      expect(t.repo.gamesAsked).toEqual([]);
    });

    it("hides events of private groups and of hosts without a listing", async () => {
      t.repo.tournaments.set("private", tournament({ hostId: "secret", hostKind: "community" }));
      t.repo.tournaments.set("ghost", tournament({ hostId: "gone" }));
      expect((await t.get("/v1/public/tournaments/private")).statusCode).toBe(404);
      expect((await t.get("/v1/public/tournaments/ghost")).statusCode).toBe(404);
    });

    it("works for every published status", async () => {
      for (const status of ["registration", "seeding", "scheduled", "live", "finished"]) {
        t.repo.tournaments.set("fall", tournament({ status }));
        expect((await t.get("/v1/public/tournaments/fall")).statusCode, status).toBe(200);
      }
    });
  });

  describe("GET /v1/public/group-tournaments/:groupId/:id", () => {
    beforeEach(() => {
      t.repo.listingMap.set("pickup", { name: "Pickup", kind: "community", requiresApproval: false });
      const listing = (groupId: string, tournamentId: string): Data => ({
        groupId,
        tournamentId,
        name: "Hat Day",
        startsAt: iso(now + day),
        endsOn: null,
        status: "scheduled",
        format: "roundRobin",
      });
      t.repo.groupListings.set("pickup_t1", listing("pickup", "t1"));
      t.repo.groupListings.set("secret_t2", listing("secret", "t2"));
      t.repo.groupListings.set("pickup_t3", listing("other", "t3"));
    });

    it("gives an open group's tournament listing without a token", async () => {
      const res = await t.get("/v1/public/group-tournaments/pickup/t1");
      expect(res.statusCode).toBe(200);
      expect(res.json()).toEqual({ groupId: "pickup", tournamentId: "t1", name: "Hat Day", startsAt: iso(now + day), endsOn: null, status: "scheduled", format: "roundRobin" });
    });

    it("hides private groups' tournaments, mismatched listings and bad ids", async () => {
      expect((await t.get("/v1/public/group-tournaments/secret/t2")).statusCode).toBe(404);
      expect((await t.get("/v1/public/group-tournaments/pickup/t3")).statusCode).toBe(404);
      expect((await t.get("/v1/public/group-tournaments/pickup/none")).statusCode).toBe(404);
      expect((await t.get("/v1/public/group-tournaments/pickup/a.b")).statusCode).toBe(404);
    });
  });

  describe("limits", () => {
    it("limits visitors by a hash of their IP, and turns them away when over", async () => {
      t.repo.tournaments.set("fall", tournament());
      t.repo.divisionDocs.set("fall", []);
      await t.get("/v1/public/tournaments", { "x-forwarded-for": "203.0.113.9" });
      await t.get("/v1/public/tournaments/fall", { "x-forwarded-for": "203.0.113.9" });
      await t.get("/v1/public/group-tournaments/pickup/t1", { "x-forwarded-for": "203.0.113.9" });
      expect(t.limiter.keys).toHaveLength(3);
      expect(new Set(t.limiter.keys).size).toBe(1);
      expect(t.limiter.keys[0]).toMatch(/^ip_[0-9a-f]{32}$/);
      expect(t.limiter.keys[0]).not.toContain("203.0.113.9");
      t.limiter.allow = false;
      for (const url of ["/v1/public/tournaments", "/v1/public/tournaments/fall", "/v1/public/group-tournaments/pickup/t1"]) {
        expect((await t.get(url)).statusCode, url).toBe(429);
      }
    });

    it("lets the website's server past the visitor limit with its key, and counts members by uid", async () => {
      const s = setup({ webServerKey: "k3y" });
      s.limiter.allow = false;
      expect((await s.get("/v1/public/tournaments", { [webKeyHeader]: "k3y" })).statusCode).toBe(200);
      expect((await s.get("/v1/public/tournaments", { [webKeyHeader]: "wrong" })).statusCode).toBe(429);
      expect((await s.get("/v1/public/tournaments", { authorization: "Bearer token:m1" })).statusCode).toBe(200);
      expect(s.limiter.keys).toHaveLength(1);
    });

    it("needs no App Check, even when it's enforced", async () => {
      const s = setup({ enforceAppCheck: true });
      expect((await s.get("/v1/public/tournaments")).statusCode).toBe(200);
    });
  });
});

describe("publicDraftedName", () => {
  it("renames teams named after one of their players", () => {
    expect(publicDraftedName("Team Riley", ["Riley Parker"], 0)).toBe("Team 1");
    expect(publicDraftedName("Riley Parker's team", ["Riley Parker"], 1)).toBe("Team 2");
    expect(publicDraftedName("Sky Pilots", ["Riley Parker"], 2)).toBe("Sky Pilots");
    expect(publicDraftedName("Team 4", [], 3)).toBe("Team 4");
    expect(publicDraftedName("  ", [], 4)).toBe("Team 5");
  });
});
