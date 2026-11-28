import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const callApi = vi.fn();
let user: { uid: string } | null = { uid: "ada" };

vi.mock("@/lib/client", async () => {
  const actual = await vi.importActual<typeof import("@/lib/client")>("@/lib/client");
  return { ...actual, callApi: (...a: unknown[]) => callApi(...a) };
});
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => ({ user }) }));

import { ApiError } from "@/lib/client";
import { historyStatLine, TeamHistory } from "@/components/TeamHistory";

const totals = (o: Partial<Record<string, number>> = {}) => ({ games: 0, points: 0, goals: 0, assists: 0, blocks: 0, completions: 0, throwaways: 0, catches: 0, drops: 0, ...o });
const entry = (o: Record<string, unknown> = {}) => ({
  teamId: "t1",
  teamName: "Hawks",
  teamKind: "team",
  current: true,
  spot: { id: "p1", name: "Ada Rivers", number: 7 },
  seasons: { "2026": totals({ games: 3, points: 10, goals: 4, assists: 2, blocks: 1 }), "2025": totals({ games: 1, points: 1 }) },
  ...o,
});

beforeEach(() => {
  callApi.mockReset();
  user = { uid: "ada" };
});

describe("historyStatLine", () => {
  it("uses singular forms for one and shows zeros", () => {
    expect(historyStatLine({ games: 1, points: 1, goals: 1, assists: 1, blocks: 1 })).toBe("1 game · 1 point · 1 goal · 1 assist · 1 block");
    expect(historyStatLine({ games: 0, points: 2, goals: 0, assists: 0, blocks: 0 })).toBe("0 games · 2 points · 0 goals · 0 assists · 0 blocks");
  });
});

describe("Team history card", () => {
  it("lists teams in server order with spot, and only the latest season until expanded", async () => {
    callApi.mockResolvedValue({ teams: [entry(), entry({ teamId: "t2", teamName: "Owls", current: false, spot: { id: "p2", name: "", number: null }, seasons: {} })] });
    render(<TeamHistory uid="ada" isMe />);
    expect(await screen.findByRole("heading", { name: "Team history" })).toBeInTheDocument();
    expect(callApi).toHaveBeenCalledWith(user, "/v1/players/ada/team-history");
    const names = screen.getAllByText(/^(Hawks|Owls)$/).map((n) => n.textContent);
    expect(names).toEqual(["Hawks", "Owls"]);
    expect(screen.getByText("Ada Rivers · #7")).toBeInTheDocument();
    expect(screen.getByText("2026").parentElement).toHaveTextContent("2026 3 games · 10 points · 4 goals · 2 assists · 1 block");
    expect(screen.queryByText("2025")).not.toBeInTheDocument();
    // No spot name or number: no second line; no seasons: said so.
    expect(screen.getByText("No games tracked yet")).toBeInTheDocument();
    // Only the Owls (left the team) are Past.
    expect(screen.getAllByText("Past")).toHaveLength(1);

    const more = screen.getByRole("button", { name: "Show all seasons (2)" });
    expect(more).toHaveAttribute("aria-expanded", "false");
    fireEvent.click(more);
    expect(screen.getByText("2025").parentElement).toHaveTextContent("2025 1 game · 1 point · 0 goals · 0 assists · 0 blocks");
    const less = screen.getByRole("button", { name: "Hide other seasons" });
    expect(less).toHaveAttribute("aria-expanded", "true");
    fireEvent.click(less);
    expect(screen.queryByText("2025")).not.toBeInTheDocument();
  });

  it("leaves the spot out when it has neither a name nor a number, and drops a missing number", async () => {
    callApi.mockResolvedValue({ teams: [entry({ spot: { id: "p1", name: "Ada", number: null }, seasons: { "2026": totals() } }), entry({ teamId: "t2", teamName: "Owls", spot: { id: "p2", name: "", number: 3 }, seasons: { "2026": totals() } })] });
    render(<TeamHistory uid="ada" isMe />);
    expect(await screen.findByText("Ada")).toBeInTheDocument();
    expect(screen.getByText("#3")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /seasons/ })).not.toBeInTheDocument();
  });

  it("says totals are capped once, when any team is partial", async () => {
    callApi.mockResolvedValue({ teams: [entry({ partial: true }), entry({ teamId: "t2", partial: true })] });
    render(<TeamHistory uid="ada" isMe />);
    expect(await screen.findAllByText("Totals may not include every game")).toHaveLength(1);
  });

  it("has no caption when nothing is partial", async () => {
    callApi.mockResolvedValue({ teams: [entry()] });
    render(<TeamHistory uid="ada" isMe />);
    await screen.findByText("Hawks");
    expect(screen.queryByText(/Totals cover/)).not.toBeInTheDocument();
  });

  it("own profile: a loading status, then the empty message", async () => {
    callApi.mockResolvedValue({ teams: [] });
    render(<TeamHistory uid="ada" isMe />);
    expect(screen.getByRole("status")).toHaveAttribute("aria-busy", "true");
    expect(await screen.findByText("No team history yet. A team admin links you to your spot on a roster.")).toBeInTheDocument();
  });

  it("own profile: an error says what failed and Retry loads again", async () => {
    callApi.mockRejectedValueOnce(new ApiError("The server is busy.", 500, "internal"));
    callApi.mockResolvedValueOnce({ teams: [entry()] });
    render(<TeamHistory uid="ada" isMe />);
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Couldn't load your team history");
    fireEvent.click(screen.getByRole("button", { name: "Retry" }));
    expect(await screen.findByText("Hawks")).toBeInTheDocument();
    expect(callApi).toHaveBeenCalledTimes(2);
  });

  it("a response that does not match the schema is an error on your own profile", async () => {
    callApi.mockResolvedValue({ teams: [{ teamId: "t1" }] });
    render(<TeamHistory uid="ada" isMe />);
    expect(await screen.findByRole("alert")).toHaveTextContent("Couldn't load your team history");
    expect(screen.queryByText("Hawks")).not.toBeInTheDocument();
  });

  it("someone else's profile: the card only appears with at least one team", async () => {
    callApi.mockResolvedValue({ teams: [entry()] });
    const a = render(<TeamHistory uid="ben" isMe={false} />);
    expect(a.container).toBeEmptyDOMElement(); // nothing while loading
    expect(await screen.findByRole("heading", { name: "Team history" })).toBeInTheDocument();
    a.unmount();
  });

  it("someone else's profile: nothing when empty, on error or on an invalid response", async () => {
    for (const reply of [() => Promise.resolve({ teams: [] }), () => Promise.reject(new ApiError("no", 500, "internal")), () => Promise.resolve({ nope: true })]) {
      callApi.mockReset();
      callApi.mockImplementation(reply);
      const r = render(<TeamHistory uid="ben" isMe={false} />);
      await waitFor(() => expect(callApi).toHaveBeenCalled());
      await new Promise((res) => setTimeout(res, 20));
      expect(r.container).toBeEmptyDOMElement();
      r.unmount();
    }
  });

  it("a signed-out visitor never calls the server and sees no card", () => {
    user = null;
    const r = render(<TeamHistory uid="ben" isMe={false} />);
    expect(callApi).not.toHaveBeenCalled();
    expect(r.container).toBeEmptyDOMElement();
  });
});
