import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const callApi = vi.fn();
const user = { uid: "u1" };

vi.mock("@/lib/client", async () => {
  const actual = await vi.importActual<typeof import("@/lib/client")>("@/lib/client");
  return { ...actual, callApi: (...a: unknown[]) => callApi(...a) };
});
vi.mock("next/navigation", () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => ({ user }) }));
vi.mock("@/components/payments/Payments", () => ({ PayoutsCard: () => null }));
vi.mock("@/components/team/InviteDialog", () => ({
  InviteButton: () => null,
  useInvite: () => ({ hasRequests: false, requests: [], requestCount: 0 }),
}));
vi.mock("@/components/team/JoinRequests", () => ({ JoinRequests: () => null }));
vi.mock("@/components/team/TeamRoles", () => ({ TeamRoles: () => null }));
vi.mock("@/components/team/MemberPermissions", () => ({ MemberPermissions: () => null, ownPermissionsLabel: () => "" }));
vi.mock("@/components/team/DiscordImport", () => ({ DiscordImport: () => null }));
vi.mock("@/components/team/CommunityAdmin", () => ({ TeamCommunity: () => null }));
vi.mock("@/components/team/TeamReports", () => ({ TeamReports: () => null }));
vi.mock("@/components/team/TeamNav", () => ({ MembersOnlySection: () => null }));
vi.mock("@/components/team/SectionGate", () => ({ optionalSectionInfo: {} }));
vi.mock("@/components/ProfileDashboard", () => ({ roleLabel: (t: string) => t }));
vi.mock("@/components/team/TeamContext", () => ({
  LEAVE_CONFIRM: "Leave?",
  useTeamHub: () => ({
    teamId: "t1",
    name: "Hawks",
    kind: "team",
    viewer: {
      state: "member",
      tier: "coach",
      uid: "u1",
      can: (p: string) => p === "manageTeam",
      team: { name: "Hawks", level: "college", city: "Austin", leagueId: "x", memberIds: ["u1"] },
    },
  }),
}));

import { ApiError } from "@/lib/client";
import { switchToClubNote, TeamSettings } from "@/components/team/TeamSettings";

const message =
  "This team can't switch to the club level: 2 people on it are under 16 or haven't added a date of birth. Club teams are for players 16 and over.";

beforeEach(() => {
  callApi.mockReset();
});

describe("Team settings: switching to club", () => {
  it("shows the 412 level message by the field and keeps what the user typed", async () => {
    callApi.mockImplementation(() => Promise.reject(new ApiError("Request failed", 412, "failed_precondition", { level: message })));
    render(<TeamSettings />);
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "Hawks Reborn" } });
    fireEvent.change(screen.getByLabelText("City"), { target: { value: "Dallas" } });
    fireEvent.change(screen.getByLabelText(/Level/), { target: { value: "club" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(message);
    expect(screen.getAllByRole("alert")).toHaveLength(1);
    expect(screen.getByLabelText(/Level/)).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByLabelText("Name")).toHaveValue("Hawks Reborn");
    expect(screen.getByLabelText("City")).toHaveValue("Dallas");
    expect(screen.getByLabelText(/Level/)).toHaveValue("club");
    await waitFor(() => expect(screen.getByRole("button", { name: "Save" })).toBeEnabled());
  });

  it("falls back to the form error for a failure without a level field", async () => {
    callApi.mockImplementation(() => Promise.reject(new ApiError("Couldn't save.", 500)));
    render(<TeamSettings />);
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Couldn't save.");
    expect(screen.getByLabelText(/Level/)).not.toHaveAttribute("aria-invalid");
  });

  it("explains the rule when moving a non-club team to club", () => {
    render(<TeamSettings />);
    fireEvent.change(screen.getByLabelText(/Level/), { target: { value: "club" } });
    expect(screen.getByText(new RegExp(switchToClubNote.slice(0, 30)))).toBeInTheDocument();
    expect(screen.queryByText(/stay on it/)).toBeNull();
  });
});
