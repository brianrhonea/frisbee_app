import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

const callApi = vi.fn();
const push = vi.fn();
let auth: { user: { uid: string } | null } = { user: { uid: "me" } };
let hub: Record<string, unknown> = {};

vi.mock("@/lib/client", async () => {
  const actual = await vi.importActual<typeof import("@/lib/client")>("@/lib/client");
  return { ...actual, callApi: (...a: unknown[]) => callApi(...a) };
});
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => auth }));
vi.mock("@/components/team/TeamContext", () => ({ useTeamHub: () => hub }));
vi.mock("@/components/ProfileDashboard", () => ({ roleLabel: (t: string) => t[0]!.toUpperCase() + t.slice(1) }));

import { ApiError } from "@/lib/client";
import { MessageStaff, peopleOf, staffOf } from "@/components/team/MessageStaff";

const team = {
  memberIds: ["me", "own", "co", "cap", "pl1"],
  memberNames: { me: "Me Myself", own: "Olive Owner", co: "Cory Coach", cap: "Cass Captain", pl1: "Pat Player" },
  members: { me: "coach", own: "owner", co: "coach", cap: "captain", pl1: "player" },
};
const member = (uid = "me") => ({ state: "member", uid, team, tier: "player", can: () => false, audience: [] });

// jsdom has no <dialog> modal support; the open state is stubbed (the browser behaviour is in the e2e tests).
beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal(this: HTMLDialogElement) {
    this.setAttribute("open", "");
  };
  HTMLDialogElement.prototype.close = function close(this: HTMLDialogElement) {
    this.removeAttribute("open");
  };
});

beforeEach(() => {
  callApi.mockReset();
  push.mockReset();
  auth = { user: { uid: "me" } };
  hub = { teamId: "t1", kind: "team", youth: false, viewer: member() };
});

describe("staffOf", () => {
  it("keeps owner, coach and captain, in that order then by name, and never the viewer or a plain player", () => {
    const people = [
      { uid: "pl1", name: "Pat", tier: "player" },
      { uid: "me", name: "Me", tier: "owner" },
      { uid: "capB", name: "Bea", tier: "captain" },
      { uid: "cap", name: "Abe", tier: "captain" },
      { uid: "coB", name: "Zed", tier: "coach" },
      { uid: "co", name: "Cory", tier: "coach" },
      { uid: "own", name: "Olive", tier: "owner" },
    ];
    expect(staffOf(people, "me").map((p) => p.uid)).toEqual(["own", "co", "coB", "cap", "capB"]);
  });

  it("drops people without a uid (the API keeps it from outsiders for non-staff and hidden people)", () => {
    const people = [
      { name: "Hidden Coach", tier: "coach" },
      { uid: "own", name: "Olive", tier: "owner" },
    ];
    expect(staffOf(people, "me").map((p) => p.name)).toEqual(["Olive"]);
  });

  it("does not count permission-based admins or custom roles as staff, for members too", () => {
    const t = {
      memberIds: ["a", "b", "c", "d"],
      memberNames: { a: "A", b: "B", c: "C", d: "Dee" },
      members: { a: "player", b: "player", c: "player", d: "coach" },
      memberPerms: { a: ["manageTeam"] },
      memberRoles: { b: ["r1"] },
      roles: { r1: { name: "Coordinators", perms: ["manageTeam"] } },
    };
    expect(staffOf(peopleOf(t as never), "x").map((p) => p.uid)).toEqual(["d"]);
  });
});

describe("Team header Message (S4 C6)", () => {
  it("shows a member Team chat at the top, then the staff without themselves or players", () => {
    render(<MessageStaff />);
    fireEvent.click(screen.getByRole("button", { name: "Message" }));
    const chat = screen.getByRole("link", { name: "Team chat" });
    expect(chat).toHaveAttribute("href", "/teams/t1/chat");
    expect(screen.getByRole("button", { name: "Message Olive Owner" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Message Cory Coach" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Message Cass Captain" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Message Me Myself" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Message Pat Player" })).toBeNull();
    expect(callApi).not.toHaveBeenCalled();
  });

  it("opens a normal direct conversation with the person picked", async () => {
    callApi.mockResolvedValueOnce({ id: "conv9" });
    render(<MessageStaff />);
    fireEvent.click(screen.getByRole("button", { name: "Message" }));
    fireEvent.click(screen.getByRole("button", { name: "Message Cory Coach" }));
    await waitFor(() => expect(push).toHaveBeenCalledWith("/messages?c=conv9"));
    expect(callApi).toHaveBeenCalledWith(auth.user, "/v1/conversations", { method: "POST", body: { with: "co" } });
  });

  it("shows the server's refusal when the conversation can't be opened", async () => {
    callApi.mockRejectedValueOnce(new ApiError("Cory doesn't take messages from you.", 403));
    render(<MessageStaff />);
    fireEvent.click(screen.getByRole("button", { name: "Message" }));
    fireEvent.click(screen.getByRole("button", { name: "Message Cory Coach" }));
    expect(await screen.findByText("Cory doesn't take messages from you.")).toBeInTheDocument();
    expect(push).not.toHaveBeenCalled();
    // Can try someone else.
    expect(screen.getByRole("button", { name: "Message Olive Owner" })).toBeEnabled();
  });

  it("gives a signed-in outsider the staff only, read from the roster", async () => {
    hub = { teamId: "t1", kind: "team", youth: false, privateGroup: false, viewer: { state: "outsider", uid: "me" } };
    callApi.mockResolvedValueOnce({
      kind: "team",
      players: [],
      members: [
        { uid: "own", name: "Olive Owner", tier: "owner", roles: [] },
        { uid: "me", name: "Me Myself", tier: "coach", roles: [] },
        { uid: "pl1", name: "Pat Player", tier: "player", roles: [] },
        { name: "Hidden Coach", tier: "coach", roles: [] },
      ],
    });
    render(<MessageStaff />);
    fireEvent.click(screen.getByRole("button", { name: "Message" }));
    expect(await screen.findByRole("button", { name: "Message Olive Owner" })).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Team chat" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Message Me Myself" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Message Pat Player" })).toBeNull();
    expect(screen.queryByText("Hidden Coach")).toBeNull();
    expect(callApi).toHaveBeenCalledWith(auth.user, "/v1/teams/t1/roster");
  });

  it("shows why the staff couldn't load", async () => {
    hub = { teamId: "t1", kind: "team", youth: false, privateGroup: false, viewer: { state: "outsider", uid: "me" } };
    callApi.mockRejectedValueOnce(new ApiError("Only members can see this roster.", 403));
    render(<MessageStaff />);
    fireEvent.click(screen.getByRole("button", { name: "Message" }));
    expect(await screen.findByText("Only members can see this roster.")).toBeInTheDocument();
  });

  it("is not there for signed-out visitors, outsiders of a youth team or a private group, or while loading", () => {
    hub = { teamId: "t1", kind: "team", youth: false, viewer: { state: "visitor" } };
    auth = { user: null };
    const a = render(<MessageStaff />);
    expect(a.container).toBeEmptyDOMElement();
    a.unmount();
    auth = { user: { uid: "me" } };
    hub = { teamId: "t1", kind: "team", youth: true, viewer: { state: "outsider", uid: "me" } };
    const b = render(<MessageStaff />);
    expect(b.container).toBeEmptyDOMElement();
    b.unmount();
    hub = { teamId: "g1", kind: "community", youth: false, privateGroup: true, viewer: { state: "outsider", uid: "me" } };
    const c = render(<MessageStaff />);
    expect(c.container).toBeEmptyDOMElement();
    c.unmount();
    hub = { teamId: "t1", kind: "team", youth: false, viewer: { state: "loading" } };
    const d = render(<MessageStaff />);
    expect(d.container).toBeEmptyDOMElement();
    expect(callApi).not.toHaveBeenCalled();
  });

  it("says so when there is no one else to message", () => {
    hub = { teamId: "t1", kind: "team", youth: false, viewer: member("own") };
    // Only the owner is staff, and they are the viewer.
    (hub.viewer as { team: unknown }).team = { memberIds: ["own", "pl1"], memberNames: { own: "Olive", pl1: "Pat" }, members: { own: "owner", pl1: "player" } };
    auth = { user: { uid: "own" } };
    render(<MessageStaff />);
    fireEvent.click(screen.getByRole("button", { name: "Message" }));
    expect(screen.getByText("No one else to message.")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Team chat" })).toBeInTheDocument();
  });
});
