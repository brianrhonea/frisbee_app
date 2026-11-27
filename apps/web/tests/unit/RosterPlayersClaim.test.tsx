import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const callApi = vi.fn();
const user = { uid: "ben" };
let players: Array<Record<string, unknown>> = [];
let tier = "player";

vi.mock("@/lib/client", async () => {
  const actual = await vi.importActual<typeof import("@/lib/client")>("@/lib/client");
  return { ...actual, callApi: (...a: unknown[]) => callApi(...a) };
});
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => ({ user }) }));
vi.mock("@/components/team/stats/SeasonStatsPage", () => ({ BackToStats: () => null, StatsGate: ({ children }: { children: React.ReactNode }) => <>{children}</> }));
vi.mock("@/components/team/stats/data", async () => {
  const actual = await vi.importActual<typeof import("@/components/team/stats/data")>("@/components/team/stats/data");
  return { ...actual, useStatsPlayers: () => ({ data: players, error: "" }) };
});
vi.mock("@/components/team/TeamContext", () => ({
  useTeamHub: () => ({
    teamId: "t1",
    kind: "team",
    viewer: {
      state: "member",
      uid: "ben",
      tier,
      team: { members: { ben: tier, ada: "captain" }, memberNames: { ben: "Ben", ada: "Ada" }, memberPerms: {}, statKeepers: [] },
      can: () => tier === "captain",
      audience: [],
    },
  }),
}));

import { RosterPlayersPage } from "@/components/team/stats/RosterPlayersPage";

beforeEach(() => {
  callApi.mockReset();
  tier = "player";
  players = [
    { id: "p1", name: "Spare Spot", position: "hybrid", paid: false, userId: null },
    { id: "p2", name: "Ben", position: "cutter", paid: true, userId: "ben" },
    { id: "p3", name: "Ada", position: "handler", paid: true, userId: "ada" },
  ];
});

describe("Roster spots are linked by an admin, never claimed (S4 C4)", () => {
  it("gives a member no way to claim an unlinked spot, while keeping their own link and Unlink me", async () => {
    render(<RosterPlayersPage />);
    expect(screen.queryByRole("button", { name: "This is me" })).toBeNull();
    expect(screen.getByText("You")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Unlink me" }));
    await waitFor(() => expect(callApi).toHaveBeenCalled());
    expect(callApi).toHaveBeenCalledWith(user, "/v1/teams/t1/roster-players/p2/link", { method: "PUT", body: { userId: null } });
  });

  it("offers a member who has no spot nothing to claim either", () => {
    players = players.filter((p) => p.id !== "p2");
    render(<RosterPlayersPage />);
    expect(screen.queryByRole("button", { name: "This is me" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Unlink me" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Add player" })).toBeNull();
  });

  it("lets an admin add a player and link a member through the picker (create, then link)", async () => {
    tier = "captain";
    callApi.mockResolvedValueOnce({ id: "p9" }).mockResolvedValueOnce(undefined);
    players = players.filter((p) => p.id !== "p2");
    render(<RosterPlayersPage />);
    fireEvent.click(screen.getByRole("button", { name: "Add player" }));
    fireEvent.change(screen.getByLabelText(/Link to a member/), { target: { value: "ben" } });
    expect(screen.getByLabelText("Name")).toHaveValue("Ben");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() => expect(callApi).toHaveBeenCalledTimes(2));
    expect(callApi).toHaveBeenNthCalledWith(2, user, "/v1/teams/t1/roster-players/p9/link", { method: "PUT", body: { userId: "ben" } });
  });
});
