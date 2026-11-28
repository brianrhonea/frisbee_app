import { fireEvent, render, screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

// Sprint 5 lane Q-web: the restyled athlete profile (Q1), Community hub sections (Q3) and post page states (Q4)
// use the shared components (CoverHeader, SummaryTiles, ListRow, EventCard, States).

let auth: { user: { uid: string } | null | undefined } = { user: { uid: "me" } };
let hub: Record<string, unknown> = {};
const callApi = vi.fn();
const push = vi.fn();

vi.mock("@/components/AuthProvider", () => ({ useAuth: () => auth }));
vi.mock("@/components/team/TeamContext", () => ({ useTeamHub: () => hub }));
vi.mock("@/lib/client", async () => {
  const actual = await vi.importActual<typeof import("@/lib/client")>("@/lib/client");
  return { ...actual, callApi: (...a: unknown[]) => callApi(...a) };
});
vi.mock("@/lib/live", () => ({ useChangeSignal: () => 0, useLiveDoc: () => ({ data: null, error: null }) }));
let blocked: "none" | "mine" | "theirs" = "none";
vi.mock("@/lib/moderation", () => ({
  useBlocks: () => ({ hides: () => blocked !== "none", blockedByMe: () => blocked === "mine" }),
  unblockPerson: vi.fn(),
}));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push, replace: vi.fn() }), usePathname: () => "/players/u1", useSearchParams: () => new URLSearchParams() }));
vi.mock("@/components/FollowButton", () => ({ FollowButton: () => <button type="button">Follow</button> }));
vi.mock("@/components/MessageButton", () => ({ MessageButton: () => <button type="button">Message</button> }));
vi.mock("@/components/Report", () => ({
  ReportButton: ({ className }: { className?: string }) => <button type="button" className={className}>Report</button>,
  BlockButton: ({ label, className }: { label?: string; className?: string }) => <button type="button" className={className}>{label ?? "Block"}</button>,
}));
vi.mock("@/components/RosterSpots", () => ({ RosterSpots: () => <section aria-label="Roster spots">spots</section> }));
vi.mock("@/components/ForVisitors", () => ({ ForVisitors: () => null }));
vi.mock("@/components/ui/ConfirmDialog", () => ({ useConfirm: () => vi.fn().mockResolvedValue(false) }));
vi.mock("@/components/PostCard", () => ({ PostCard: ({ post }: { post: { id: string } }) => <article>post {post.id}</article> }));
vi.mock("@/components/team/TeamNav", () => ({ JoinButton: () => <button type="button">Join</button> }));

import { ProfileCard, StatTiles, TeamList } from "@/components/ProfileDashboard";
import { CommunityChat, CommunityOrganizers, NextPickupCard } from "@/components/team/CommunitySections";
import { LivePost } from "@/components/PostPage";
import { PlayerView } from "@/components/PlayerPage";

beforeEach(() => {
  auth = { user: { uid: "me" } };
  blocked = "none";
  callApi.mockReset();
  push.mockReset();
});

describe("Q1 athlete profile", () => {
  const profile = { id: "u1", name: "Jamie Carter", username: "jamiecarter", pronouns: "she/her", bio: "Captain.", hometown: "Seattle, WA", playingSince: 2015 };

  it("shows the name as the page heading in the shared cover header, with handle, bio and facts", () => {
    render(<ProfileCard profile={profile} />);
    expect(screen.getByRole("heading", { level: 1, name: "Jamie Carter" })).toBeInTheDocument();
    expect(screen.getByText("@jamiecarter · she/her")).toBeInTheDocument();
    expect(screen.getByText("Captain.")).toBeInTheDocument();
    expect(screen.getByText("Seattle, WA")).toBeInTheDocument();
    expect(screen.getByText("Playing since 2015")).toBeInTheDocument();
    // The cover is decoration: no alt text, no stray image role.
    expect(document.querySelector(".ui-cover")).not.toBeNull();
  });

  it("draws the default cover with the initials when there is no header photo, and the photo when there is", () => {
    const { rerender } = render(<ProfileCard profile={profile} />);
    const band = () => document.querySelector(".ui-cover-photo") as HTMLElement;
    expect(band()).toHaveClass("ui-cover-default");
    expect(band()).toHaveAttribute("data-initials", "JC");
    // The watermark is a pseudo-element, so no text for assistive tech or a contrast check.
    expect(band()).toHaveTextContent("");
    rerender(<ProfileCard profile={{ ...profile, headerUrl: "https://example.test/h.jpg" }} />);
    expect(band()).not.toHaveClass("ui-cover-default");
    expect(band().querySelector("img")).toHaveAttribute("src", "https://example.test/h.jpg");
  });

  it("shows the Posts count tile under the details only when a count is given", () => {
    const { rerender } = render(<ProfileCard profile={profile} />);
    expect(document.querySelector(".profile-counts")).toBeNull();
    rerender(<ProfileCard profile={profile} counts={<ul aria-label="Activity"><li>7 Posts</li></ul>} />);
    expect(screen.getByRole("list", { name: "Activity" })).toHaveTextContent("7 Posts");
  });

  it("keeps the actions beside the picture and the quieter safety actions under the details", () => {
    render(<ProfileCard profile={profile} actions={<button type="button">Follow</button>} secondary={<button type="button">Report</button>} />);
    expect(document.querySelector(".ui-cover-actions")).toContainElement(screen.getByRole("button", { name: "Follow" }));
    expect(document.querySelector(".profile-secondary")).toContainElement(screen.getByRole("button", { name: "Report" }));
  });

  it("says Stall 10 staff and Private profile in words (pills), never colour alone", () => {
    render(<ProfileCard profile={{ ...profile, private: true }} staff />);
    expect(screen.getByText("Stall 10 staff")).toBeInTheDocument();
    expect(screen.getByText("Private profile")).toBeInTheDocument();
  });

  it("draws the season's totals as summary tiles, and says so when there are none", () => {
    const { rerender } = render(<StatTiles stats={{ "2025": { games: 3 }, "2026": { games: 12, goals: 20, assists: 7, blocks: 4 } }} teamName="Sidewinders" />);
    expect(screen.getByRole("heading", { name: "2026 season · Sidewinders" })).toBeInTheDocument();
    const tiles = screen.getByRole("list", { name: "2026 season" });
    expect(within(tiles).getAllByRole("listitem")).toHaveLength(4);
    expect(within(tiles).getByText("20").nextSibling).toHaveTextContent("Goals");
    rerender(<StatTiles stats={{}} />);
    expect(screen.getByText("No stats yet. Stats come from games kept in the app.")).toBeInTheDocument();
  });

  it("lists teams as rows that open the team", () => {
    render(<TeamList teams={[{ id: "t 1", name: "Sidewinders", subtitle: "Mixed · Seattle" }]} />);
    const link = screen.getByRole("link", { name: /Sidewinders/ });
    expect(link).toHaveAttribute("href", "/teams/t%201");
    expect(link).toHaveTextContent("Mixed · Seattle");
  });
});

describe("Q1 the whole player page", () => {
  const profile = { id: "u1", name: "Jamie Carter", username: "jamiecarter", teams: [{ id: "t1", name: "Sidewinders", subtitle: "Mixed" }] };
  const page = (over: Record<string, unknown> = {}) => ({ profile, posts: [], ...over }) as never;

  it("shows the header, then stats and teams and an empty posts state, with Follow and Message but no Edit for someone else", () => {
    render(<PlayerView uid="u1" page={page()} locked={false} />);
    expect(screen.getByRole("heading", { level: 1, name: "Jamie Carter" })).toBeInTheDocument();
    expect(document.querySelector(".ui-cover-actions")).toHaveTextContent("FollowMessage");
    expect(screen.getByRole("link", { name: /Sidewinders/ })).toHaveAttribute("href", "/teams/t1");
    expect(screen.getByRole("heading", { name: "Posts" })).toBeInTheDocument();
    expect(screen.getByText("No posts yet.")).toBeInTheDocument();
    // Another player: no Roster spots card (it is only on your own page).
    expect(screen.queryByRole("region", { name: "Roster spots" })).toBeNull();
  });

  it("keeps the Roster spots card on your own page, and gives yourself no Report or Block", () => {
    render(<PlayerView uid="me" page={page()} locked={false} />);
    expect(screen.getByRole("region", { name: "Roster spots" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Report" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Block" })).toBeNull();
  });

  it("hides stats and teams when the player's visibility switches say so", () => {
    render(<PlayerView uid="u1" page={page({ profile: { ...profile, visibility: { stats: false, teams: false } } })} locked={false} />);
    expect(screen.queryByText("No stats yet. Stats come from games kept in the app.")).toBeNull();
    expect(screen.queryByRole("link", { name: /Sidewinders/ })).toBeNull();
  });

  it("shows a private profile you don't follow as the header and the private message, with nothing of theirs", () => {
    render(<PlayerView uid="u1" page={page({ profile: { ...profile, private: true } })} locked />);
    expect(screen.getByRole("heading", { level: 1, name: "Jamie Carter" })).toBeInTheDocument();
    expect(screen.getByText("Private profile")).toBeInTheDocument();
    expect(screen.getByText("This profile is private")).toBeInTheDocument();
    expect(screen.getByText(/shares their stats, teams and posts with the people they approve/)).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Posts" })).toBeNull();
    expect(screen.queryByRole("link", { name: /Sidewinders/ })).toBeNull();
    expect(screen.getByRole("button", { name: "Follow" })).toBeInTheDocument();
  });

  it("shows only the name and an Unblock button for someone you blocked, and no bio, teams or posts", () => {
    blocked = "mine";
    render(<PlayerView uid="u1" page={page({ profile: { ...profile, bio: "Secret bio" } })} locked={false} />);
    expect(screen.getByText("You blocked Jamie")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Unblock" })).toBeInTheDocument();
    expect(screen.queryByText("Secret bio")).toBeNull();
    expect(screen.queryByRole("link", { name: /Sidewinders/ })).toBeNull();
    expect(screen.queryByRole("heading", { name: "Posts" })).toBeNull();
  });

  it("says you can't see the profile of someone who blocked you, with no way to unblock", () => {
    blocked = "theirs";
    render(<PlayerView uid="u1" page={page()} locked={false} />);
    expect(screen.getByText("You can't see this profile")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Unblock" })).toBeNull();
  });
});

describe("Q3 community sections", () => {
  const event = { id: "e1", title: "Sunday pickup", startsAt: "2030-06-02T17:00:00Z", location: "North field", rsvps: { other: "going" } as Record<string, string> };
  const member = (can = false) => ({ state: "member", uid: "me", can: () => can, team: { members: { me: "owner" }, memberNames: { me: "Me" }, memberIds: ["me"] } });

  beforeEach(() => {
    hub = { teamId: "g1", kind: "community", privateGroup: false, viewer: member() };
  });

  it("opens the next pickup as an event card with the Going count and Needs RSVP until answered", () => {
    render(<NextPickupCard event={event} />);
    expect(screen.getByRole("heading", { name: "Next pickup" })).toBeInTheDocument();
    const card = screen.getByRole("link", { name: /Sunday pickup/ });
    expect(card).toHaveAttribute("href", "/teams/g1/schedule?event=e1");
    expect(card).toHaveTextContent("North field");
    expect(card).toHaveTextContent("1 going");
    expect(screen.getByText("Needs RSVP")).toBeInTheDocument();
    expect(screen.getByRole("group", { name: "Your answer" })).toBeInTheDocument();
  });

  it("shows the member's answer instead of Needs RSVP once they have one", () => {
    render(<NextPickupCard event={{ ...event, rsvps: { me: "going" } }} />);
    expect(screen.queryByText("Needs RSVP")).toBeNull();
    expect(screen.getAllByText("Going").length).toBeGreaterThan(0);
  });

  it("gives a member who can add events a next step when nothing is scheduled, and others only the words", () => {
    hub = { ...hub, viewer: member(true) };
    const { unmount } = render(<NextPickupCard />);
    expect(screen.getByText("No pickup scheduled")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "New event" })).toHaveAttribute("href", "/teams/g1/schedule?new=event");
    unmount();
    hub = { ...hub, viewer: member(false) };
    render(<NextPickupCard />);
    expect(screen.getByText("No pickup scheduled")).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "New event" })).toBeNull();
  });

  it("answers an RSVP through the API, and picking the current answer again takes it back", async () => {
    callApi.mockResolvedValue({});
    const { unmount } = render(<NextPickupCard event={event} />);
    fireEvent.click(screen.getByRole("button", { name: /^Going/ }));
    expect(callApi).toHaveBeenCalledWith({ uid: "me" }, "/v1/teams/g1/events/e1/rsvp", { method: "PUT", body: { status: "going" } });
    unmount();
    callApi.mockClear();
    render(<NextPickupCard event={{ ...event, rsvps: { me: "going" } }} />);
    fireEvent.click(screen.getByRole("button", { name: /^Going/ }));
    expect(callApi).toHaveBeenCalledWith({ uid: "me" }, "/v1/teams/g1/events/e1/rsvp", { method: "PUT", body: { status: null } });
  });

  it("lists chat rooms as rows, says Unread in words, and shows the loading and empty states", () => {
    const general = { id: "r1", name: "general" };
    const carpool = { id: "r2", name: "carpool" };
    const { rerender } = render(<CommunityChat chat={undefined} />);
    expect(screen.getByRole("status")).toHaveTextContent("Loading…");
    rerender(<CommunityChat chat={{ rooms: [], unread: [] } as never} />);
    expect(screen.getByText("No rooms yet.")).toBeInTheDocument();
    rerender(<CommunityChat chat={{ rooms: [general, carpool], unread: [carpool] } as never} />);
    const unread = screen.getByRole("link", { name: /carpool/ });
    expect(unread).toHaveAttribute("href", "/teams/g1/chat?room=r2");
    expect(unread).toHaveTextContent("(Unread)");
    expect(screen.getByRole("link", { name: /general/ })).not.toHaveTextContent("Unread");
  });

  it("lists the organizers as rows, with Message for everyone but the viewer", () => {
    hub = {
      teamId: "g1",
      kind: "community",
      viewer: { ...member(), team: { members: { me: "owner", co: "coach" }, memberNames: { me: "Me Myself", co: "Cory Coach" }, memberIds: ["me", "co"] } },
    };
    render(<CommunityOrganizers />);
    expect(screen.getByRole("link", { name: /Me Myself/ })).toHaveAttribute("href", "/players/me");
    expect(screen.getByRole("link", { name: /Cory Coach/ })).toHaveAttribute("href", "/players/co");
    expect(screen.getAllByRole("button", { name: "Message" })).toHaveLength(1);
  });
});

describe("Q4 post page states", () => {
  it("says it is loading while sign-in is still being worked out", () => {
    auth = { user: undefined };
    render(<LivePost postId="p1" initial={null} />);
    expect(screen.getByRole("status")).toHaveTextContent("Loading…");
  });

  it("tells a visitor a private post is not public, with a way to log in", () => {
    auth = { user: null };
    render(<LivePost postId="p1" initial={null} />);
    expect(screen.getByText("This post isn't public.")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Log in" })).toHaveAttribute("href", "/sign-in?next=%2Fposts%2Fp1");
  });

  it("shows the public copy to a visitor, with the open-in-the-app prompt", () => {
    auth = { user: null };
    render(<LivePost postId="p1" initial={{ id: "p1", body: "Hi" } as never} />);
    expect(screen.getByText("post p1")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Open in the app" })).toBeInTheDocument();
  });

  it("offers Try again, as an alert, when a member's post cannot be loaded", async () => {
    callApi.mockRejectedValue(new Error("offline"));
    render(<LivePost postId="p1" initial={null} />);
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(/Couldn't load this post|offline/);
    expect(within(alert).getByRole("button", { name: "Try again" })).toBeInTheDocument();
  });
});
