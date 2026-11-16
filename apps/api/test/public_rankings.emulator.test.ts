// Visitors' rankings against the Firestore emulator (pnpm test:emulator):
// the real reads, field masks and timestamps over seeded data.
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { publicRankingsSchema } from "@stall10/shared";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { BrowseRepository } from "../src/browse/repository.js";
import { FirestoreRateLimiter } from "../src/limits/limiter.js";
import { FirestorePublicRankingRepository } from "../src/rankings/public_repository.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const projectId = "demo-stall10";
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run with `pnpm test:emulator`.");

const firebase = initializeApp({ projectId }, "public-rankings-emulator-test");
const db = getFirestore(firebase);
const repo = new FirestorePublicRankingRepository(db);
const app = buildApp({
  verifier: new FakeVerifier(),
  users: new FakeUsers(),
  teams: new FakeTeamRepository(),
  browse: { repo: {} as BrowseRepository, limiter: new FirestoreRateLimiter(db), imageUrl: (p) => p },
  publicRankings: repo,
});

const updatedAt = Timestamp.fromDate(new Date("2026-11-15T09:15:00Z"));
const team = (rank: number, teamId: string) => ({ rank, teamId, name: teamId, rating: 1300 - rank, wins: 5, losses: rank });

beforeAll(async () => {
  const batch = db.batch();
  const listed = (id: string, extra: Record<string, unknown> = {}) => {
    batch.set(db.doc(`teams/${id}`), { name: id, level: "club", members: { owner1: "owner" }, memberIds: ["owner1"], ...extra });
    batch.set(db.doc(`teamDirectory/${id}`), { name: id, level: "club", ...extra });
  };
  listed("rk_adult");
  listed("rk_adult2");
  listed("rk_youth", { level: "youth" });
  listed("rk_private", { kind: "community", requiresApproval: true });
  batch.set(db.doc("rankings/club-mixed"), {
    level: "club",
    division: "mixed",
    minGames: 5,
    updatedAt,
    teams: [team(1, "rk_youth"), team(2, "rk_adult"), team(3, "rk_private"), team(4, "rk_adult2")],
  });
  batch.set(db.doc("rankings/youth-mixed"), { level: "youth", division: "mixed", minGames: 5, updatedAt, teams: [team(1, "rk_youth")] });
  await batch.commit();
});

afterAll(() => deleteApp(firebase));

describe("visitors' rankings (emulator)", () => {
  it("reads listings and team docs with the field mask only", async () => {
    const teams = await repo.teams(["rk_adult", "rk_missing"]);
    expect([...teams.keys()]).toEqual(["rk_adult"]);
    expect(teams.get("rk_adult")).toEqual({ level: "club" });
    const listings = await repo.listings(["rk_private"]);
    expect(listings.get("rk_private")).toEqual({ kind: "community", requiresApproval: true, level: "club" });
  });

  it("answers without a token: no youth, no private groups, timestamps as ISO strings", async () => {
    const res = await app.inject({ method: "GET", url: "/v1/public/rankings", headers: { "x-forwarded-for": "198.51.100.31" } });
    expect(res.statusCode).toBe(200);
    const body = publicRankingsSchema.parse(res.json());
    const clubMixed = body.rankings.find((r) => r.key === "club-mixed")!;
    expect(body.rankings.some((r) => r.level === ("youth" as string))).toBe(false);
    expect(clubMixed.updatedAt).toBe("2026-11-15T09:15:00.000Z");
    expect(clubMixed.teams.map((t) => [t.rank, t.teamId])).toEqual([
      [1, "rk_adult"],
      [2, "rk_adult2"],
    ]);
  });
});
