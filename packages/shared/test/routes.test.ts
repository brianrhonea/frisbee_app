import { existsSync, readdirSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { appOnlyRoute, webParent, webRoute } from "../src/routes.js";

const repo = new URL("../../../", import.meta.url);
const webApp = new URL("apps/web/app/", repo);

/** Whether apps/web has a page for [path] (dynamic segments match [x] folders). */
function webHasPage(path: string): boolean {
  let dir = webApp;
  for (const part of path.split(/[?#]/)[0]!.split("/").filter(Boolean)) {
    const exact = new URL(`${part}/`, dir);
    if (existsSync(exact)) {
      dir = exact;
      continue;
    }
    const dynamic = readdirSync(dir).find((d) => /^\[[^\].]+\]$/.test(d));
    if (!dynamic) return false;
    dir = new URL(`${dynamic}/`, dir);
  }
  return existsSync(new URL("page.tsx", dir));
}

/** Every route the notification functions send, with their ${…} parts filled in. */
function functionRoutes(): string[] {
  const dir = new URL("firebase/functions/src/notifications/", repo);
  const found = new Set<string>();
  for (const file of readdirSync(dir).filter((f) => f.endsWith(".ts"))) {
    const src = readFileSync(new URL(file, dir), "utf8");
    // Every app-route-like literal, so routes built in a variable (a
    // draft's board, an event's deleted-or-not route) count too.
    for (const m of src.matchAll(/`(\/[a-z][^`]*)`|"(\/[a-z][^"]*)"|route:\s*`(\$\{meetingRoute[^`]*)`/g)) {
      const raw = (m[1] ?? m[2] ?? m[3]) as string;
      // meetingRoute(...) is a helper; spell it out.
      const filled = raw.replace(/\$\{meetingRoute\([^)]*\)\}/g, "/team-meetings/t1/m1").replace(/\$\{[^}]+\}/g, "x1");
      if (filled.startsWith("/")) found.add(filled);
    }
  }
  return [...found];
}

describe("webParent: back from a notification goes to the page it belongs under", () => {
  it("goes up to the team, the tournament, Chats or Home", () => {
    expect(webParent("/teams/t1/chat?room=r1")).toBe("/teams/t1");
    expect(webParent("/teams/t1/schedule?event=e")).toBe("/teams/t1");
    expect(webParent("/teams/t1/meetings/m/room")).toBe("/teams/t1");
    expect(webParent("/teams/t1")).toBe("/teams");
    expect(webParent("/messages?c=c1")).toBe("/messages");
    expect(webParent("/posts/p1")).toBe("/");
    expect(webParent("/tournaments/x/bracket?division=d")).toBe("/tournaments/x");
    expect(webParent("/tournaments/x")).toBe("/tournaments");
  });
  it("leaves pages with nothing above them to the usual back", () => {
    expect(webParent("/players/u1")).toBeNull();
    expect(webParent("/notifications/requests")).toBeNull();
    expect(webParent("/messages")).toBeNull();
    expect(webParent("/schedule")).toBeNull();
    expect(webParent("/tournaments/host")).toBeNull();
  });
});

describe("webRoute", () => {
  it("maps app routes to the website's pages", () => {
    expect(webRoute("/settings/follow-requests")).toBe("/notifications/requests");
    expect(webRoute("/notifications/follow-requests")).toBe("/notifications/requests");
    expect(webRoute("/posts/p1")).toBe("/posts/p1");
    expect(webRoute("/players/u1")).toBe("/players/u1");
    expect(webRoute("/messages/c1")).toBe("/messages?c=c1");
    expect(webRoute("/messages/new")).toBe("/messages");
    expect(webRoute("/messages")).toBe("/messages");
    expect(webRoute("/teams/t1/chats/r1")).toBe("/teams/t1/chat?room=r1");
    expect(webRoute("/teams/t1/events")).toBe("/teams/t1/schedule");
    expect(webRoute("/teams/t1/members")).toBe("/teams/t1/roster");
    expect(webRoute("/team-events/t1/e1")).toBe("/teams/t1/schedule?event=e1");
    expect(webRoute("/team-meetings/t1/m1/room")).toBe("/teams/t1/meetings/m1/room");
    expect(webRoute("/team-meetings/t1/m1")).toBe("/teams/t1/meetings/m1");
    expect(webRoute("/my-events/e1")).toBe("/schedule");
    expect(webRoute("/schedule")).toBe("/schedule");
    expect(webRoute("/team-meetings/t1/m1/edit")).toBe("/teams/t1/meetings/m1/edit");
    expect(webRoute("/teams/t1/plays/p1")).toBe("/teams/t1/plays/p1");
    expect(webRoute("/teams/t1?section=playbook")).toBe("/teams/t1/playbook");
    expect(webRoute("/teams/t1?section=videos")).toBe("/teams/t1/videos");
    expect(webRoute("/teams/t1?section=stats")).toBe("/teams/t1/stats");
    expect(webRoute("/teams/t1?section=tournaments")).toBe("/teams/t1/tournaments");
    expect(webRoute("/teams/t1?section=events")).toBe("/teams/t1/schedule");
    expect(webRoute("/teams/t1?section=members")).toBe("/teams/t1/roster");
    expect(webRoute("/teams/t1?section=teams")).toBe("/teams/t1/teams");
    // Only known sections: anything else (More, a stray value) opens the feed.
    expect(webRoute("/teams/t1?section=more")).toBe("/teams/t1");
    expect(webRoute("/teams/t1?section=..%2Fsettings")).toBe("/teams/t1");
    expect(webRoute("/teams/t1?section=constructor")).toBe("/teams/t1");
    expect(webRoute("/teams/t1/whiteboards/w1")).toBe("/teams/t1/whiteboards/w1");
    expect(webRoute("/teams/t1/whiteboards/new")).toBe("/teams/t1/whiteboards/new");
    expect(webRoute("/teams/t1/whiteboards/..")).not.toBe("/teams/t1/whiteboards/..");
    expect(webRoute("/team-videos/t1/v1")).toBe("/teams/t1/videos/v1");
    expect(webRoute("/teams/t1/stats/games/g1")).toBe("/teams/t1/stats/games/g1");
    expect(webRoute("/teams/t1/stats/tournaments/x1")).toBe("/teams/t1/stats/tournaments/x1");
    expect(webRoute("/teams/t1/stats/season")).toBe("/teams/t1/stats/season");
    expect(webRoute("/group-tournaments/g1/x1")).toBe("/teams/g1/tournaments/x1");
    expect(webRoute("/group-tournaments/g1/x1/edit")).toBe("/teams/g1/tournaments/x1/edit");
    expect(webRoute("/tournaments")).toBe("/tournaments");
    expect(webRoute("/tournaments/host")).toBe("/tournaments/host");
    expect(webRoute("/tournaments/new?host=g1&type=hat&x=1")).toBe("/tournaments/new?host=g1&type=hat");
    expect(webRoute("/tournaments/x1")).toBe("/tournaments/x1");
    expect(webRoute("/tournaments/x1?host=g%201")).toBe("/tournaments/x1?host=g%201");
    expect(webRoute("/tournaments/x1/bracket/d1")).toBe("/tournaments/x1/bracket?division=d1");
    expect(webRoute("/tournaments/x1/edit")).toBe("/tournaments/x1/edit");
    expect(webRoute("/tournaments/x1/signups")).toBe("/tournaments/x1/signups");
    // As in the app: draft/ is the host's balanced draft, live-draft/ the captains'.
    expect(webRoute("/tournaments/x1/draft/d1")).toBe("/tournaments/x1/draft/d1");
    expect(webRoute("/tournaments/x1/live-draft/d1")).toBe("/tournaments/x1/live-draft/d1");
    expect(webRoute("/tournaments/x1/somewhere")).toBe(appOnlyRoute);
    expect(webRoute("/somewhere/new")).toBe(appOnlyRoute);
    expect(webRoute(null)).toBeNull();
    expect(webRoute("https://example.com")).toBeNull();
    expect(webRoute("//example.com/posts/p1")).toBeNull();
  });

  it("never lets a stored id climb out of its page", () => {
    for (const r of ["/posts/..", "/tournaments/.", "/group-tournaments/../x", "/posts/a\\..\\settings", "/posts/%2e%2e", "/teams/t1/plays/..%2f"]) {
      expect(webRoute(r)).toBe(appOnlyRoute);
    }
    expect(webRoute("/posts/a.b")).toBe("/posts/a.b");
  });

  it("covers every route the notification functions send, each to a page the website has", () => {
    const routes = functionRoutes();
    expect(routes.length).toBeGreaterThan(15);
    expect(routes).toContain("/tournaments/x1/live-draft/x1");
    for (const r of routes) {
      const to = webRoute(r);
      expect(to, r).not.toBe(appOnlyRoute);
      expect(webHasPage(to!), `${r} -> ${to}`).toBe(true);
    }
  });

  it("sends every app page it maps to a page the website has", () => {
    for (const r of [
      "/team-meetings/t1/m1/edit",
      "/teams/t1/plays/p1",
      "/teams/t1?section=playbook",
      "/teams/t1?section=videos",
      "/teams/t1?section=stats",
      "/teams/t1?section=tournaments",
      "/teams/t1?section=events",
      "/teams/t1?section=chat",
      "/teams/t1?section=members",
      "/teams/t1?section=teams",
      "/team-videos/t1/v1",
      "/teams/t1/stats/games/g1",
      "/teams/t1/stats/tournaments/x1",
      "/teams/t1/stats/season",
      "/group-tournaments/g1/x1",
      "/group-tournaments/g1/x1/edit",
      "/tournaments",
      "/tournaments/host",
      "/tournaments/new?host=g1",
      "/tournaments/x1?host=g1",
      "/tournaments/x1/edit",
      "/tournaments/x1/signups",
      "/tournaments/x1/draft/d1",
      "/tournaments/x1/live-draft/d1",
    ]) {
      const to = webRoute(r)!;
      expect(to, r).not.toBe(appOnlyRoute);
      expect(webHasPage(to), `${r} -> ${to}`).toBe(true);
    }
  });
});
