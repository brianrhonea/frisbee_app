// "Allow join requests" (F26): which teams and groups take requests, as the
// API, the website and the app (TeamListing.takesRequests) all decide it.
import { describe, expect, it } from "vitest";
import { allowsJoinRequests, setAllowJoinRequestsRequestSchema, takesJoinRequests } from "../src/index.js";

describe("join requests (F26)", () => {
  it("a team takes them only when its switch is stored as true", () => {
    expect(allowsJoinRequests({})).toBe(false);
    expect(allowsJoinRequests({ allowJoinRequests: false })).toBe(false);
    expect(allowsJoinRequests({ allowJoinRequests: true })).toBe(true);
    expect(allowsJoinRequests({ kind: "team", allowJoinRequests: true })).toBe(true);
    expect(allowsJoinRequests(null)).toBe(false);
  });

  it("a group goes by requiresApproval, never the team switch", () => {
    expect(allowsJoinRequests({ kind: "community", allowJoinRequests: true })).toBe(false);
    expect(takesJoinRequests({ kind: "community", requiresApproval: true })).toBe(true);
    expect(takesJoinRequests({ kind: "organization", requiresApproval: false, allowJoinRequests: true })).toBe(false);
    expect(takesJoinRequests({ allowJoinRequests: true })).toBe(true);
    expect(takesJoinRequests({ requiresApproval: true })).toBe(false);
  });

  it("the switch's body is exactly { on }", () => {
    expect(setAllowJoinRequestsRequestSchema.safeParse({ on: true }).success).toBe(true);
    expect(setAllowJoinRequestsRequestSchema.safeParse({ on: "yes" }).success).toBe(false);
    expect(setAllowJoinRequestsRequestSchema.safeParse({ on: true, extra: 1 }).success).toBe(false);
  });
});
