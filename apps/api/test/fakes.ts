import type { CreateTeamInput, NameListing } from "@stall10/shared";
import type { Caller, TokenVerifier } from "../src/auth.js";
import type { Owner } from "../src/teams/documents.js";
import type { TeamRepository } from "../src/teams/repository.js";

/** Accepts tokens "token:<uid>[:<name>]" and App Check token "good". */
export class FakeVerifier implements TokenVerifier {
  async verifyIdToken(token: string): Promise<Caller> {
    const [kind, uid, name] = token.split(":");
    if (kind !== "token" || !uid) throw new Error("bad token");
    return { uid, name, email: `${uid}@x.test` };
  }

  async verifyAppCheck(token: string): Promise<void> {
    if (token !== "good") throw new Error("bad app check");
  }
}

export class FakeTeamRepository implements TeamRepository {
  muted = new Map<string, number>();
  leagues = new Map<string, boolean>();
  listings: Array<NameListing & { keywords: string[] }> = [];
  created: Array<{ id: string; input: CreateTeamInput; owner: Owner }> = [];

  async mutedUntil(uid: string) {
    return this.muted.get(uid) ?? null;
  }

  async leagueTakesTeams(id: string) {
    return this.leagues.get(id) ?? false;
  }

  async listingsWithKeywords(keywords: string[], limit: number) {
    return this.listings.filter((l) => l.keywords.some((k) => keywords.includes(k))).slice(0, limit);
  }

  async createTeam(input: CreateTeamInput, owner: Owner) {
    const id = `team${this.created.length + 1}`;
    this.created.push({ id, input, owner });
    return id;
  }
}
