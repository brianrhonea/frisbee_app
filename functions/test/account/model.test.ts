import { describe, expect, it } from "vitest";

import {
  attachmentFolder,
  eventResponsesOf,
  nextOwner,
  postFolder,
  signedInRecently,
  tournamentWithout,
} from "../../src/account/model";

describe("nextOwner", () => {
  it("prefers coaches, then captains, then players, in join order", () => {
    const members = { me: "owner", p1: "player", c1: "captain", k1: "coach", k2: "coach" };
    expect(nextOwner({ members, memberIds: ["me", "p1", "c1", "k1", "k2"] }, "me")).toBe("k1");
    const noCoach = { me: "owner", p1: "player", c1: "captain", c2: "captain" };
    expect(nextOwner({ members: noCoach, memberIds: ["me", "p1", "c2", "c1"] }, "me")).toBe("c2");
    expect(nextOwner({ members: { me: "owner", p2: "player", p1: "player" }, memberIds: ["me", "p2", "p1"] }, "me")).toBe(
      "p2",
    );
  });

  it("is undefined when nobody else is on the team", () => {
    expect(nextOwner({ members: { me: "owner" }, memberIds: ["me"] }, "me")).toBeUndefined();
    expect(nextOwner({}, "me")).toBeUndefined();
  });
});

describe("signedInRecently", () => {
  const now = Date.UTC(2026, 9, 31, 12);
  it("allows a sign-in within five minutes", () => {
    expect(signedInRecently(now / 1000 - 60, now)).toBe(true);
    expect(signedInRecently(now / 1000 - 301, now)).toBe(false);
    expect(signedInRecently(undefined, now)).toBe(false);
    expect(signedInRecently("123", now)).toBe(false);
  });
});

describe("eventResponsesOf", () => {
  it("lists the response maps with an entry for the user", () => {
    const event = { rsvps: { me: "going", you: "maybe" }, reactions: { you: ["fire"] }, votes: { me: [0] } };
    expect(eventResponsesOf(event, "me")).toEqual(["rsvps", "votes"]);
    expect(eventResponsesOf({ rsvps: {} }, "me")).toEqual([]);
    expect(eventResponsesOf({}, "me")).toEqual([]);
  });
});

describe("tournamentWithout", () => {
  const tournament = {
    teams: [
      { id: "a", name: "A", captainId: "me", playerIds: ["me", "x"], playerNames: { me: "Me", x: "X" } },
      { id: "b", name: "B", captainId: "y", playerIds: ["y"], playerNames: { y: "Y" } },
    ],
    participantIds: ["me", "x", "y"],
    captains: { a: "me", b: "y" },
  };

  it("takes the user off their team, and as its captain", () => {
    const next = tournamentWithout(tournament, "me")!;
    expect(next.teams[0]).toMatchObject({ captainId: null, playerIds: ["x"], playerNames: { x: "X" } });
    expect(next.teams[1]).toMatchObject({ captainId: "y", playerIds: ["y"] });
    expect(next.participantIds).toEqual(["x", "y"]);
    expect(next.captains).toEqual({ b: "y" });
  });

  it("is null for someone not playing", () => {
    expect(tournamentWithout(tournament, "z")).toBeNull();
  });
});

describe("storage folders", () => {
  it("finds a message's attachments", () => {
    expect(attachmentFolder("teams/t1/chats/r1/messages/m1", "me")).toBe("teams/t1/chats/r1/me/m1/");
    expect(attachmentFolder("conversations/a_b/messages/m1", "a")).toBe("conversations/a_b/a/m1/");
    expect(attachmentFolder("teams/t1/meetings/x/messages/m1", "me")).toBeUndefined();
  });

  it("finds a post's photos", () => {
    expect(postFolder("teams/t1/posts/p1")).toBe("teams/t1/posts/p1/");
    expect(postFolder("teams/t1/plays/p1")).toBeUndefined();
  });
});
