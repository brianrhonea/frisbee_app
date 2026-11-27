import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

const callApi = vi.fn();
const openInvite = vi.fn();
const user = { uid: "me" };
let hub: Record<string, unknown> = {};
let invite = { canInvite: true, requestCount: 0, open: openInvite };

vi.mock("@/lib/client", async () => {
  const actual = await vi.importActual<typeof import("@/lib/client")>("@/lib/client");
  return { ...actual, callApi: (...a: unknown[]) => callApi(...a) };
});
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => ({ user }) }));
vi.mock("@/components/team/TeamContext", async () => {
  const actual = await vi.importActual<typeof import("@/components/team/TeamContext")>("@/components/team/TeamContext");
  return { ...actual, useTeamHub: () => hub };
});
vi.mock("@/components/team/InviteDialog", () => ({ useInvite: () => invite }));
vi.mock("@/components/ProfileDashboard", () => ({ roleLabel: (t: string) => t[0]!.toUpperCase() + t.slice(1) }));

import type { TeamRoster } from "@stall10/shared";
import { ApiError } from "@/lib/client";
import { AddMember } from "@/components/team/AddMember";
import { RolesTab } from "@/components/team/RolesTab";
import { draftOf, RosterPlayerForm, saveRosterPlayer } from "@/components/team/RosterPlayerForm";

beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal(this: HTMLDialogElement) {
    this.setAttribute("open", "");
  };
  HTMLDialogElement.prototype.close = function close(this: HTMLDialogElement) {
    this.removeAttribute("open");
  };
});

const roster: TeamRoster = {
  kind: "team",
  players: [{ id: "p1", name: "Ada L", person: { uid: "ada", name: "Ada Lovelace" } }],
  members: [
    { uid: "me", name: "Me Owner", tier: "owner", roles: [] },
    { uid: "ada", name: "Ada Lovelace", tier: "captain", roles: ["Handlers"] },
    { uid: "ben", name: "Ben Okafor", tier: "player", roles: ["Handlers"] },
    { uid: "cam", name: "Cam Reyes", tier: "coach", roles: [] },
  ],
} as TeamRoster;

const team = {
  roles: { r1: { name: "Handlers", position: 0, perms: [] }, r2: { name: "Tournament lead", position: 1, perms: [] } },
  memberRoles: { ada: ["r1"], ben: ["r1"] },
};
const viewerWith = (tier: string, can: string[]) => ({ state: "member", uid: "me", tier, team, can: (p: string) => can.includes(p), audience: [] });

beforeEach(() => {
  callApi.mockReset();
  openInvite.mockReset();
  invite = { canInvite: true, requestCount: 0, open: openInvite };
  hub = { teamId: "t1", kind: "team", name: "Hawks", viewer: viewerWith("owner", ["manageTeam", "manageMembers"]) };
});

describe("saveRosterPlayer: one call, with the linked member in the body", () => {
  it("creates the spot already linked", async () => {
    callApi.mockResolvedValueOnce({ id: "p9" });
    const r = await saveRosterPlayer(user as never, "t1", { ...draftOf(), name: "Ben", number: "7", userId: "ben" });
    expect(r).toEqual({ id: "p9", error: "" });
    expect(callApi).toHaveBeenCalledTimes(1);
    expect(callApi).toHaveBeenCalledWith(user, "/v1/teams/t1/roster-players", {
      method: "POST",
      body: { name: "Ben", number: 7, position: "hybrid", userId: "ben", paid: false },
    });
  });

  it("creates an unlinked spot, and edits a spot with PUT", async () => {
    callApi.mockResolvedValue({ id: "p9" });
    await saveRosterPlayer(user as never, "t1", { ...draftOf(), name: "Walk-on" });
    expect(callApi).toHaveBeenCalledWith(user, "/v1/teams/t1/roster-players", expect.objectContaining({ method: "POST", body: expect.objectContaining({ userId: null }) }));
    callApi.mockClear();
    await saveRosterPlayer(user as never, "t1", { ...draftOf(), id: "p1", name: "Ada L", userId: "ada" });
    expect(callApi).toHaveBeenCalledTimes(1);
    expect(callApi).toHaveBeenCalledWith(user, "/v1/teams/t1/roster-players/p1", expect.objectContaining({ method: "PUT", body: expect.objectContaining({ userId: "ada" }) }));
  });

  it("returns the server's message, without an id, when the member is already on another spot", async () => {
    callApi.mockRejectedValueOnce(new ApiError("That member is already on another spot.", 412));
    expect(await saveRosterPlayer(user as never, "t1", { ...draftOf(), name: "Ben", userId: "ben" })).toEqual({ id: "", error: "That member is already on another spot." });
  });
});

describe("Link to a member picker", () => {
  const members = [
    { uid: "ada", name: "Ada Lovelace" },
    { uid: "ben", name: "Ben Okafor" },
    { uid: "cam", name: "Cam Reyes" },
  ];
  it("offers only members not yet linked, and picking one fills the name", () => {
    const onSave = vi.fn();
    render(<RosterPlayerForm draft={draftOf()} members={members} linkedElsewhere={new Set(["ada"])} busy={false} onCancel={() => undefined} onSave={onSave} />);
    const picker = screen.getByLabelText(/Link to a member/);
    const options = Array.from((picker as HTMLSelectElement).options).map((o) => o.textContent);
    expect(options).toEqual(["Not linked (no account)", "Ben Okafor", "Cam Reyes"]);
    fireEvent.change(picker, { target: { value: "ben" } });
    expect(screen.getByLabelText("Name")).toHaveValue("Ben Okafor");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(onSave).toHaveBeenCalledWith(expect.objectContaining({ name: "Ben Okafor", userId: "ben" }));
  });

  it("does not overwrite a name someone typed, but replaces one a pick filled", () => {
    render(<RosterPlayerForm draft={draftOf()} members={members} linkedElsewhere={new Set()} busy={false} onCancel={() => undefined} onSave={() => undefined} />);
    const name = screen.getByLabelText("Name");
    fireEvent.change(name, { target: { value: "Benji" } });
    fireEvent.change(screen.getByLabelText(/Link to a member/), { target: { value: "ben" } });
    expect(name).toHaveValue("Benji");
    fireEvent.change(name, { target: { value: "" } });
    fireEvent.change(screen.getByLabelText(/Link to a member/), { target: { value: "cam" } });
    expect(name).toHaveValue("Cam Reyes");
    fireEvent.change(screen.getByLabelText(/Link to a member/), { target: { value: "ben" } });
    expect(name).toHaveValue("Ben Okafor");
  });
});

describe("Add member (S4 C2)", () => {
  it("offers Invite people and Add player to roster to someone who manages both", () => {
    render(<AddMember roster={roster} onAdded={() => undefined} />);
    fireEvent.click(screen.getByRole("button", { name: "Add member" }));
    fireEvent.click(screen.getByRole("menuitem", { name: "Invite people" }));
    expect(openInvite).toHaveBeenCalledWith("people");
  });

  it("adds a player to the roster, linked to a member who has no spot yet", async () => {
    callApi.mockResolvedValueOnce({ id: "p2" });
    const onAdded = vi.fn();
    render(<AddMember roster={roster} onAdded={onAdded} />);
    fireEvent.click(screen.getByRole("button", { name: "Add member" }));
    fireEvent.click(screen.getByRole("menuitem", { name: "Add player to roster" }));
    const picker = screen.getByLabelText(/Link to a member/) as HTMLSelectElement;
    // Ada already has a spot (p1): not offered.
    expect(Array.from(picker.options).map((o) => o.textContent)).toEqual(["Not linked (no account)", "Me Owner", "Ben Okafor", "Cam Reyes"]);
    fireEvent.change(picker, { target: { value: "ben" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() => expect(onAdded).toHaveBeenCalled());
    expect(callApi).toHaveBeenCalledWith(user, "/v1/teams/t1/roster-players", expect.objectContaining({ method: "POST", body: expect.objectContaining({ name: "Ben Okafor", userId: "ben" }) }));
    expect(screen.queryByLabelText(/Link to a member/)).toBeNull();
  });

  it("shows the server's error and keeps the form open", async () => {
    callApi.mockRejectedValueOnce(new ApiError("Only admins can change the roster.", 403));
    render(<AddMember roster={roster} onAdded={() => undefined} />);
    fireEvent.click(screen.getByRole("button", { name: "Add member" }));
    fireEvent.click(screen.getByRole("menuitem", { name: "Add player to roster" }));
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "Walk-on" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(await screen.findByText("Only admins can change the roster.")).toBeInTheDocument();
    expect(screen.getByLabelText("Name")).toHaveValue("Walk-on");
  });

  it("goes straight to the invite dialog for someone who can only invite", () => {
    hub = { ...hub, viewer: viewerWith("player", ["manageMembers"]) };
    render(<AddMember roster={roster} onAdded={() => undefined} />);
    fireEvent.click(screen.getByRole("button", { name: "Add member" }));
    expect(openInvite).toHaveBeenCalledWith("people");
    expect(screen.queryByRole("menuitem")).toBeNull();
  });

  it("goes straight to the player form on a team for someone who can only manage the team but not invite", () => {
    invite = { ...invite, canInvite: false };
    render(<AddMember roster={roster} onAdded={() => undefined} />);
    fireEvent.click(screen.getByRole("button", { name: "Add member" }));
    expect(screen.getByLabelText(/Link to a member/)).toBeInTheDocument();
  });

  it("is hidden from a member who manages nothing", () => {
    invite = { ...invite, canInvite: false };
    hub = { ...hub, viewer: viewerWith("player", []) };
    const { container } = render(<AddMember roster={roster} onAdded={() => undefined} />);
    expect(container).toBeEmptyDOMElement();
  });

  it("offers no roster spot in a community, only the invite", () => {
    hub = { ...hub, kind: "community", viewer: viewerWith("owner", ["manageTeam", "manageMembers"]) };
    render(<AddMember roster={{ ...roster, kind: "community" }} onAdded={() => undefined} />);
    fireEvent.click(screen.getByRole("button", { name: "Add member" }));
    expect(openInvite).toHaveBeenCalledWith("people");
  });
});

describe("Roles tab (S4 C2)", () => {
  it("lists each tier and custom role with who holds it", () => {
    render(<RolesTab roster={roster} />);
    const items = screen.getAllByRole("heading", { level: 3 }).map((h) => h.textContent?.replace(/\s+/g, " ").trim());
    expect(items).toEqual(["Owner 1", "Coach 1", "Captain 1", "Stats 0", "Handlers 2", "Tournament lead 0"]);
    const handlers = screen.getByRole("heading", { level: 3, name: /Handlers/ }).closest("li")!;
    expect(handlers).toHaveTextContent("Ada Lovelace");
    expect(handlers).toHaveTextContent("Ben Okafor");
    expect(screen.getByRole("link", { name: "Me Owner" })).toHaveAttribute("href", "/players/me");
  });

  it("gives the owner Edit roles, linking to the roles editor in settings", () => {
    render(<RolesTab roster={roster} />);
    expect(screen.getByRole("link", { name: "Edit roles" })).toHaveAttribute("href", "/teams/t1/settings#team-roles");
  });

  it("gives a member manager the members' roles in settings, and a player nothing to edit", () => {
    hub = { ...hub, viewer: viewerWith("captain", ["manageMembers"]) };
    const a = render(<RolesTab roster={roster} />);
    expect(screen.getByRole("link", { name: "Edit roles" })).toHaveAttribute("href", "/teams/t1/settings#member-roles");
    a.unmount();
    hub = { ...hub, viewer: viewerWith("player", []) };
    render(<RolesTab roster={roster} />);
    expect(screen.queryByRole("link", { name: "Edit roles" })).toBeNull();
    expect(screen.getByRole("heading", { level: 3, name: /Handlers/ })).toBeInTheDocument();
  });

  it("leaves out the stats tier on a community, and shows nothing to an outsider", () => {
    hub = { ...hub, kind: "community" };
    const a = render(<RolesTab roster={roster} />);
    expect(screen.queryByRole("heading", { level: 3, name: /Stats/ })).toBeNull();
    a.unmount();
    hub = { ...hub, viewer: { state: "outsider", uid: "x" } };
    const b = render(<RolesTab roster={roster} />);
    expect(b.container).toBeEmptyDOMElement();
  });
});
