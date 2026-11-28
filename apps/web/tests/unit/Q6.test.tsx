import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

// Sprint 5 Q6 (website half; the app's mirror is test/ui/q6_app_test.dart): the "…" menu over the profile
// cover (Report, Block, Share), Discover's Events chip and Athletes rename, and the profile's Media tab.

let auth: { user: { uid: string } | null | undefined } = { user: { uid: "me" } };
let blocked: "none" | "mine" | "theirs" = "none";
const block = vi.fn();
const shareLink = vi.fn();

vi.mock("@/components/AuthProvider", () => ({ useAuth: () => auth }));
vi.mock("@/lib/live", () => ({ useChangeSignal: () => 0, useLiveDoc: () => ({ data: null, error: null }) }));
vi.mock("@/lib/moderation", () => ({
  useBlocks: () => ({ hides: () => blocked !== "none", blockedByMe: () => blocked === "mine" }),
  unblockPerson: vi.fn(),
}));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push: vi.fn(), replace: vi.fn() }), usePathname: () => "/players/u1", useSearchParams: () => new URLSearchParams() }));
vi.mock("@/components/FollowButton", () => ({ FollowButton: () => <button type="button">Follow</button> }));
vi.mock("@/components/MessageButton", () => ({ MessageButton: () => <button type="button">Message</button> }));
vi.mock("@/components/Report", () => ({
  ReportDialog: ({ onClose }: { onClose: () => void }) => (
    <div role="dialog" aria-label="Report this profile">
      <button type="button" onClick={onClose}>Close report</button>
    </div>
  ),
  useBlockPerson: () => ({ block, busy: false }),
}));
vi.mock("@/components/ShareButton", () => ({
  playerUrl: (uid: string) => `https://site.test/players/${uid}`,
  shareLink: (...a: unknown[]) => shareLink(...a),
}));
vi.mock("@/components/MemberImage", () => ({ MemberImage: ({ path, alt }: { path: string; alt: string }) => <img alt={alt} src={`/img/${path}`} /> }));
vi.mock("@/components/RosterSpots", () => ({ RosterSpots: () => null }));
vi.mock("@/components/TeamHistory", () => ({ TeamHistory: () => null }));
vi.mock("@/components/ForVisitors", () => ({ ForVisitors: () => null }));
vi.mock("@/components/ui/ConfirmDialog", () => ({ useConfirm: () => vi.fn().mockResolvedValue(false) }));
vi.mock("@/components/PostCard", () => ({ PostCard: ({ post }: { post: { id: string } }) => <article>post {post.id}</article> }));

import { PlayerView } from "@/components/PlayerPage";
import { CoverMenu } from "@/components/ui/CoverMenu";
import { eventsFor, hostedFor, parseFilter } from "@/components/explore/filters";

beforeEach(() => {
  auth = { user: { uid: "me" } };
  blocked = "none";
  block.mockReset();
  shareLink.mockReset();
});

const profile = { id: "u1", name: "Jamie Carter", username: "jamiecarter", teams: [] };
const img = (path: string) => ({ path, name: path, contentType: "image/jpeg", size: 1, url: `https://x.test/${path}` });
const page = (posts: unknown[] = []) => ({ profile, posts }) as never;

describe("Q6 the cover menu", () => {
  it("is a menu button with the right ARIA, closed until opened", () => {
    render(<PlayerView uid="u1" page={page()} locked={false} />);
    const btn = screen.getByRole("button", { name: "More options" });
    expect(btn).toHaveAttribute("aria-haspopup", "menu");
    expect(btn).toHaveAttribute("aria-expanded", "false");
    expect(screen.queryByRole("menu")).toBeNull();
    fireEvent.click(btn);
    expect(btn).toHaveAttribute("aria-expanded", "true");
    expect(within(screen.getByRole("menu")).getAllByRole("menuitem").map((i) => i.textContent)).toEqual(["Report", "Block", "Share"]);
  });

  it("holds Share only on your own page", () => {
    render(<PlayerView uid="me" page={page()} locked={false} />);
    fireEvent.click(screen.getByRole("button", { name: "More options" }));
    expect(screen.getAllByRole("menuitem").map((i) => i.textContent)).toEqual(["Share"]);
  });

  it("Report opens the report dialog, Block runs the block, Share shares the profile link", async () => {
    shareLink.mockResolvedValue("copied");
    render(<PlayerView uid="u1" page={page()} locked={false} />);
    fireEvent.click(screen.getByRole("button", { name: "More options" }));
    fireEvent.click(screen.getByRole("menuitem", { name: "Report" }));
    expect(screen.getByRole("dialog", { name: "Report this profile" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Close report" }));

    fireEvent.click(screen.getByRole("button", { name: "More options" }));
    fireEvent.click(screen.getByRole("menuitem", { name: "Block" }));
    expect(block).toHaveBeenCalledTimes(1);

    fireEvent.click(screen.getByRole("button", { name: "More options" }));
    fireEvent.click(screen.getByRole("menuitem", { name: "Share" }));
    expect(shareLink).toHaveBeenCalledWith("https://site.test/players/u1", "Jamie Carter on Stall 10");
    expect(await screen.findByRole("status")).toHaveTextContent("Link copied");
  });

  it("no longer shows the ghost Report and Block buttons under the details", () => {
    render(<PlayerView uid="u1" page={page()} locked={false} />);
    expect(screen.queryByRole("button", { name: "Report" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Block" })).toBeNull();
    expect(document.querySelector(".profile-safety")).toBeNull();
  });

  it("keeps Report and Share (no Block) on a profile you blocked", () => {
    blocked = "mine";
    render(<PlayerView uid="u1" page={page()} locked={false} />);
    fireEvent.click(screen.getByRole("button", { name: "More options" }));
    expect(screen.getAllByRole("menuitem").map((i) => i.textContent)).toEqual(["Report", "Share"]);
  });

  it("works from the keyboard: Down opens on the first item, arrows move, Escape closes and refocuses the button", async () => {
    render(
      <CoverMenu
        items={[
          { id: "a", label: "One", onSelect: vi.fn() },
          { id: "b", label: "Two", onSelect: vi.fn() },
        ]}
      />,
    );
    const btn = screen.getByRole("button", { name: "More options" });
    btn.focus();
    fireEvent.keyDown(btn, { key: "ArrowDown" });
    const [one, two] = await screen.findAllByRole("menuitem");
    await waitFor(() => expect(one).toHaveFocus());
    fireEvent.keyDown(one, { key: "ArrowDown" });
    expect(two).toHaveFocus();
    fireEvent.keyDown(two, { key: "ArrowDown" });
    expect(one).toHaveFocus();
    fireEvent.keyDown(one, { key: "End" });
    expect(two).toHaveFocus();
    fireEvent.keyDown(two, { key: "Escape" });
    expect(screen.queryByRole("menu")).toBeNull();
    expect(btn).toHaveFocus();
  });

  it("closes on a click outside", () => {
    render(<CoverMenu items={[{ id: "a", label: "One", onSelect: vi.fn() }]} />);
    fireEvent.click(screen.getByRole("button", { name: "More options" }));
    expect(screen.getByRole("menu")).toBeInTheDocument();
    fireEvent.pointerDown(document.body);
    expect(screen.queryByRole("menu")).toBeNull();
  });
});

describe("Q6 the Media tab", () => {
  const posts = [
    { id: "a", images: [img("a1.jpg")] },
    { id: "b", images: [] },
    { id: "c", images: [img("c1.jpg"), img("c2.jpg")] },
  ];

  it("lists only the photos in the posts the page loaded, each linking to its post", () => {
    render(<PlayerView uid="u1" page={page(posts)} locked={false} />);
    expect(screen.getByRole("tab", { name: "Posts" })).toHaveAttribute("aria-selected", "true");
    fireEvent.click(screen.getByRole("tab", { name: "Media" }));
    expect(screen.getByRole("heading", { name: "Media" })).toBeInTheDocument();
    const links = screen.getAllByRole("link", { name: "Photo from Jamie's post" });
    expect(links).toHaveLength(3);
    expect(links.map((l) => l.getAttribute("href"))).toEqual(["/posts/a", "/posts/c", "/posts/c"]);
    expect(screen.queryByText("post b")).toBeNull();
  });

  it("says so when there are no photos", () => {
    render(<PlayerView uid="u1" page={page([{ id: "b", images: [] }])} locked={false} />);
    fireEvent.click(screen.getByRole("tab", { name: "Media" }));
    expect(screen.getByText("No photos or videos yet.")).toBeInTheDocument();
  });

  it("is not there on a locked (private) profile, which lists no posts at all", () => {
    render(<PlayerView uid="u1" page={page(posts)} locked />);
    expect(screen.queryByRole("tab", { name: "Media" })).toBeNull();
  });

  it("is not there on a blocked profile", () => {
    blocked = "theirs";
    render(<PlayerView uid="u1" page={page(posts)} locked={false} />);
    expect(screen.queryByRole("tab", { name: "Media" })).toBeNull();
  });
});

describe("Q6 Discover filters", () => {
  const hosted = [{ kind: "tournament" }, { kind: "league" }] as never[];

  it("Events shows every hosted event and every public team event, like All", () => {
    expect(hostedFor(hosted, "events")).toHaveLength(2);
    expect(eventsFor([{ type: "pickup" }, { type: "practice" }], "events")).toHaveLength(2);
    // Pickup still narrows to pickup games.
    expect(eventsFor([{ type: "pickup" }, { type: "practice" }], "pickup")).toHaveLength(1);
  });

  it("?only=events and ?only=athletes open the filters", () => {
    expect(parseFilter("events")).toBe("events");
    expect(parseFilter("athletes")).toBe("players");
    expect(parseFilter("people")).toBe("players");
    expect(parseFilter("players")).toBe("players");
  });
});
