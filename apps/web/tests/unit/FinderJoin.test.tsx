import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const callApi = vi.fn();
let auth: { user: { uid: string } | null } = { user: { uid: "me" } };

vi.mock("@/lib/client", async () => {
  const actual = await vi.importActual<typeof import("@/lib/client")>("@/lib/client");
  return { ...actual, callApi: (...a: unknown[]) => callApi(...a) };
});
vi.mock("next/navigation", () => ({ useSearchParams: () => new URLSearchParams() }));
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => auth }));
vi.mock("@/components/useMyTeams", () => ({ useMyTeams: () => ({ data: [] }) }));

import { ApiError } from "@/lib/client";
import { FinderJoin, joinPathOf } from "@/components/TeamFinder";

beforeEach(() => {
  callApi.mockReset();
  auth = { user: { uid: "me" } };
});

describe("joinPathOf: the same rules as the team header's Join button", () => {
  it("lets an open group be joined and an approval group be asked", () => {
    expect(joinPathOf({ kind: "community" })).toMatchObject({ label: "Join", path: "members" });
    expect(joinPathOf({ kind: "organization", requiresApproval: false })).toMatchObject({ label: "Join", path: "members" });
    expect(joinPathOf({ kind: "community", requiresApproval: true })).toMatchObject({ label: "Ask to join", path: "join-requests" });
  });
  it("asks to join a team only when it takes join requests; otherwise there is no path", () => {
    expect(joinPathOf({ kind: "team", allowJoinRequests: true })).toMatchObject({ label: "Ask to join", path: "join-requests" });
    expect(joinPathOf({ kind: "team" })).toBeNull();
    expect(joinPathOf({})).toBeNull();
  });
});

describe("Join on a Teams search result (S4 C3)", () => {
  it("joins an open group through the members call", async () => {
    callApi.mockResolvedValueOnce(undefined);
    render(<FinderJoin team={{ id: "g1", name: "Austin Pickup", kind: "community" }} />);
    fireEvent.click(screen.getByRole("button", { name: "Join: Austin Pickup" }));
    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Joined"));
    expect(callApi).toHaveBeenCalledWith(auth.user, "/v1/teams/g1/members", { method: "POST" });
  });

  it("asks to join an approval group, and a team that takes requests", async () => {
    callApi.mockResolvedValue(undefined);
    const a = render(<FinderJoin team={{ id: "g2", name: "Club", kind: "organization", requiresApproval: true }} />);
    fireEvent.click(screen.getByRole("button", { name: "Ask to join: Club" }));
    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Requested"));
    expect(callApi).toHaveBeenCalledWith(auth.user, "/v1/teams/g2/join-requests", { method: "POST" });
    a.unmount();
    render(<FinderJoin team={{ id: "t2", name: "Hawks", kind: "team", allowJoinRequests: true }} />);
    fireEvent.click(screen.getByRole("button", { name: "Ask to join: Hawks" }));
    await waitFor(() => expect(callApi).toHaveBeenCalledWith(auth.user, "/v1/teams/t2/join-requests", { method: "POST" }));
  });

  it("shows nothing for a plain team that joins only by code, and nothing when signed out", () => {
    const a = render(<FinderJoin team={{ id: "t3", name: "Plain", kind: "team" }} />);
    expect(a.container).toBeEmptyDOMElement();
    a.unmount();
    auth = { user: null };
    const b = render(<FinderJoin team={{ id: "g1", name: "Open", kind: "community" }} />);
    expect(b.container).toBeEmptyDOMElement();
  });

  it("shows the server's refusal (the club 16+ rule) and lets them try again", async () => {
    callApi.mockRejectedValueOnce(new ApiError("Club teams are for players 16 and over. Add your date of birth first.", 403));
    render(<FinderJoin team={{ id: "t4", name: "Club Hawks", kind: "team", allowJoinRequests: true }} />);
    fireEvent.click(screen.getByRole("button", { name: "Ask to join: Club Hawks" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Club teams are for players 16 and over");
    expect(screen.getByRole("button", { name: "Ask to join: Club Hawks" })).toBeEnabled();
  });
});
