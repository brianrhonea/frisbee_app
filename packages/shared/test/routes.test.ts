import { existsSync, readdirSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { appOnlyRoute, webRoute } from "../src/routes.js";

const repo = new URL("../../../", import.meta.url);
const webApp = new URL("apps/web/app/", repo);

/** Whether apps/web has a page for [path] (dynamic segments match [x] folders). */
function webHasPage(path: string): boolean {
  let dir = webApp;
  for (const part of path.split("/").filter(Boolean)) {
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
    for (const m of src.matchAll(/route:\s*(?:`([^`]*)`|"([^"]*)")/g)) {
      const raw = (m[1] ?? m[2]) as string;
      // meetingRoute(...) is a helper; spell it out.
      const filled = raw.replace(/\$\{meetingRoute\([^)]*\)\}/g, "/team-meetings/t1/m1").replace(/\$\{[^}]+\}/g, "x1");
      if (filled.startsWith("/")) found.add(filled);
    }
  }
  return [...found];
}

describe("webRoute", () => {
  it("maps app routes to the website's pages", () => {
    expect(webRoute("/settings/follow-requests")).toBe("/settings/requests");
    expect(webRoute("/posts/p1")).toBe("/posts/p1");
    expect(webRoute("/players/u1")).toBe("/players/u1");
    expect(webRoute("/messages/c1")).toBe("/messages");
    expect(webRoute("/teams/t1/chats/r1")).toBe("/teams/t1/chat");
    expect(webRoute("/teams/t1/events")).toBe("/teams/t1/schedule");
    expect(webRoute("/teams/t1/members")).toBe("/teams/t1/roster");
    expect(webRoute("/team-events/t1/e1")).toBe("/teams/t1/schedule");
    expect(webRoute("/team-meetings/t1/m1/room")).toBe("/teams/t1");
    expect(webRoute("/my-events/e1")).toBe("/schedule");
    expect(webRoute("/tournaments/t1/live-draft/d1")).toBe("/events");
    expect(webRoute("/somewhere/new")).toBe(appOnlyRoute);
    expect(webRoute(null)).toBeNull();
    expect(webRoute("https://example.com")).toBeNull();
  });

  it("covers every route the notification functions send, each to a page the website has", () => {
    const routes = functionRoutes();
    expect(routes.length).toBeGreaterThan(10);
    for (const r of routes) {
      const to = webRoute(r);
      expect(to, r).not.toBe(appOnlyRoute);
      expect(webHasPage(to!), `${r} -> ${to}`).toBe(true);
    }
  });
});
