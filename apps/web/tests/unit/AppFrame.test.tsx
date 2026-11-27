import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, within } from "@testing-library/react";

// The shell's tab lists (Sprint 3 S3): members get the approved order, visitors
// keep Learn as a tab. Everything the frame loads from Firebase is replaced.
const state = { user: null as null | { uid: string }, path: "/" };

vi.mock("next/navigation", () => ({
  usePathname: () => state.path,
  useRouter: () => ({ push: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => ({ user: state.user }) }));
vi.mock("@/components/team/meetings/MeetingAlerts", () => ({ MeetingAlerts: () => null }));
vi.mock("@/components/HeaderAuth", () => ({ HeaderAuth: () => null }));
vi.mock("@/components/HomeCards", () => ({ BrandCard: () => null }));
vi.mock("@/components/OfflineBanner", () => ({ OfflineBanner: () => null }));
vi.mock("@/components/useUnreadChats", () => ({ useUnreadChats: () => 0 }));
vi.mock("@/components/Notifications", () => ({ useUnreadCount: () => 0 }));
vi.mock("@/components/SideTeams", () => ({ SideTeams: () => null }));
vi.mock("@/components/ThemeToggle", () => ({ ThemeToggle: () => null }));
vi.mock("@/components/UpcomingAside", () => ({ UpcomingAside: () => null }));
vi.mock("@/components/voice/VoiceBar", () => ({ VoiceBar: () => null }));

import { AppFrame } from "@/components/AppFrame";

const links = (nav: HTMLElement) => within(nav).getAllByRole("link").map((a) => [a.textContent, a.getAttribute("href")]);

describe("AppFrame tabs", () => {
  beforeEach(() => {
    state.user = null;
    state.path = "/";
  });

  it("members: Home, Discover, Teams, Schedule, Chats in the bottom bar, no Learn tab", () => {
    state.user = { uid: "u1" };
    render(<AppFrame footer={null}>x</AppFrame>);
    expect(links(screen.getByRole("navigation", { name: "Tabs" }))).toEqual([
      ["Home", "/"],
      ["Discover", "/explore"],
      ["Teams", "/teams"],
      ["Schedule", "/schedule"],
      ["Chats", "/messages"],
    ]);
  });

  it("members: the sidebar has the same tabs with Learn to play under Discover", () => {
    state.user = { uid: "u1" };
    render(<AppFrame footer={null}>x</AppFrame>);
    const side = links(screen.getByRole("navigation", { name: "Site" }));
    expect(side.map((l) => l[0])).toEqual(["Home", "Discover", "Learn to play", "Teams", "Schedule", "Chats"]);
    expect(side[2]).toEqual(["Learn to play", "/learn"]);
  });

  it("members: /learn highlights Discover in the bottom bar", () => {
    state.user = { uid: "u1" };
    state.path = "/learn";
    render(<AppFrame footer={null}>x</AppFrame>);
    const bar = screen.getByRole("navigation", { name: "Tabs" });
    expect(within(bar).getByRole("link", { name: "Discover" })).toHaveAttribute("aria-current", "page");
    expect(within(bar).getAllByRole("link").filter((a) => a.getAttribute("aria-current"))).toHaveLength(1);
  });

  it("visitors: Learn stays a tab, and there is one active tab on /learn", () => {
    state.path = "/learn";
    render(<AppFrame footer={null}>x</AppFrame>);
    const bar = screen.getByRole("navigation", { name: "Tabs" });
    expect(links(bar)).toEqual([
      ["Discover", "/explore"],
      ["Tournaments", "/tournaments"],
      ["Pickup", "/explore?only=pickup"],
      ["Communities", "/explore?only=groups"],
      ["Learn", "/learn"],
    ]);
    expect(within(bar).getAllByRole("link").filter((a) => a.getAttribute("aria-current")).map((a) => a.textContent)).toEqual(["Learn"]);
  });

  it("has a skip link to the main region", () => {
    render(<AppFrame footer={null}>x</AppFrame>);
    expect(screen.getByRole("link", { name: "Skip to content" })).toHaveAttribute("href", "#main");
    expect(screen.getByRole("main")).toHaveAttribute("id", "main");
  });
});
