import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

const callApi = vi.fn();
const getDocs = vi.fn();
let user: { uid: string } | null = { uid: "ada" };

vi.mock("@/lib/client", async () => {
  const actual = await vi.importActual<typeof import("@/lib/client")>("@/lib/client");
  return { ...actual, callApi: (...a: unknown[]) => callApi(...a) };
});
vi.mock("@/lib/firebase", () => ({ firestoreDb: () => ({}) }));
vi.mock("firebase/firestore", () => ({
  collection: (_db: unknown, path: string) => ({ path }),
  where: () => ({}),
  limit: () => ({}),
  query: (c: { path: string }) => c,
  getDocs: (q: { path: string }) => getDocs(q.path),
}));
vi.mock("@/components/useMyTeams", () => ({ useMyTeams: () => ({ data: teams, error: null }) }));
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => ({ user }) }));

import { ApiError } from "@/lib/client";
import { RosterSpots } from "@/components/RosterSpots";
import { ConfirmProvider } from "@/components/ui/ConfirmDialog";

beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal(this: HTMLDialogElement) {
    this.setAttribute("open", "");
  };
  HTMLDialogElement.prototype.close = function close(this: HTMLDialogElement) {
    this.removeAttribute("open");
  };
});

const teams = [
  { id: "t1", name: "Hawks", kind: "team" as const },
  { id: "t2", name: "Owls" },
  { id: "g1", name: "Sunday pickup", kind: "community" as const },
];
const snap = (rows: Array<{ id: string; name: string; number?: number }>) => ({ docs: rows.map((r) => ({ id: r.id, data: () => r })) });

function setup(uid = "ada") {
  return render(
    <ConfirmProvider>
      <RosterSpots uid={uid} />
    </ConfirmProvider>,
  );
}

beforeEach(() => {
  callApi.mockReset();
  getDocs.mockReset();
  user = { uid: "ada" };
  getDocs.mockImplementation(async (path: string) => (path === "teams/t1/roster" ? snap([{ id: "p1", name: "Ada L", number: 7 }]) : snap([])));
});

describe("Roster spots on your own profile (S4 fix)", () => {
  it("lists the spots an admin linked you to, never reading a community's roster", async () => {
    setup();
    expect(await screen.findByRole("heading", { name: "Roster spots" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Hawks" })).toHaveAttribute("href", "/teams/t1");
    expect(screen.getByText("Ada L · #7")).toBeInTheDocument();
    expect(getDocs).toHaveBeenCalledWith("teams/t1/roster");
    expect(getDocs).toHaveBeenCalledWith("teams/t2/roster");
    expect(getDocs).not.toHaveBeenCalledWith("teams/g1/roster");
  });

  it("shows nothing when you have no spot, or on another person's profile", async () => {
    getDocs.mockResolvedValue(snap([]));
    const a = setup();
    await waitFor(() => expect(getDocs).toHaveBeenCalled());
    expect(a.container).toBeEmptyDOMElement();
    a.unmount();
    getDocs.mockClear();
    const b = setup("someone-else");
    expect(b.container).toBeEmptyDOMElement();
  });

  it("asks first, then unlinks with PUT .../link { userId: null } and drops the row", async () => {
    callApi.mockResolvedValueOnce(undefined);
    setup();
    fireEvent.click(await screen.findByRole("button", { name: "Unlink from Hawks" }));
    expect(await screen.findByText(/stop counting on your profile/)).toBeInTheDocument();
    expect(callApi).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: /^Unlink$/ }));
    await waitFor(() =>
      expect(callApi).toHaveBeenCalledWith(user, "/v1/teams/t1/roster-players/p1/link", { method: "PUT", body: { userId: null } }),
    );
    await waitFor(() => expect(screen.queryByRole("heading", { name: "Roster spots" })).toBeNull());
  });

  it("does nothing when the confirmation is cancelled", async () => {
    setup();
    fireEvent.click(await screen.findByRole("button", { name: "Unlink from Hawks" }));
    fireEvent.click(await screen.findByRole("button", { name: "Cancel" }));
    await waitFor(() => expect(screen.queryByText(/stop counting on your profile/)).toBeNull());
    expect(callApi).not.toHaveBeenCalled();
    expect(screen.getByRole("link", { name: "Hawks" })).toBeInTheDocument();
  });

  it("keeps the row and says why when the API refuses", async () => {
    callApi.mockRejectedValueOnce(new ApiError("Couldn't unlink right now.", 500));
    setup();
    fireEvent.click(await screen.findByRole("button", { name: "Unlink from Hawks" }));
    await screen.findByText(/stop counting on your profile/);
    fireEvent.click(screen.getByRole("button", { name: /^Unlink$/ }));
    expect(await screen.findByText("Couldn't unlink right now.")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Hawks" })).toBeInTheDocument();
  });
});
