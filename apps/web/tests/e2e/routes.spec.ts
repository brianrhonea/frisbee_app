import { readdirSync } from "node:fs";
import { createServer, type Server } from "node:http";
import { join, relative } from "node:path";
import { expect, test } from "@playwright/test";
import { open, watchErrors } from "./helpers";

// N8: every website route in the route map (docs/specifications/navigation-route-map.md)
// opens signed out. The list is read from app/**/page.tsx, so a new page is covered
// without editing this file. Dynamic segments get synthetic ids. A page passes when
// the server answers below 500, nothing throws in the browser, the error screen
// ("Something went wrong") is not shown and the page has a main region. Member pages
// show their sign-in prompt or "not found" for a made-up id; that is a load.
// Signed-in loads need the Firebase emulators and fixtures (not run here).
const appDir = join(__dirname, "../../app");

function pages(dir: string, out: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) pages(p, out);
    else if (e.name === "page.tsx") out.push("/" + relative(appDir, dir).replace(/\\/g, "/"));
  }
  return out;
}

const synthetic: Record<string, string> = { slug: "about", id: "t1", code: "ABC123", uid: "u1", teamId: "t1", tournamentId: "tn1", divisionId: "d1", meetingId: "m1", playId: "p1", videoId: "v1", gameId: "g1", postId: "post1" };
const routes = pages(appDir)
  .map((r) => (r === "/." ? "/" : r))
  .map((r) => r.replace(/\[(\w+)\]/g, (_m, k: string) => synthetic[k] ?? "x"))
  .sort();

// Server-rendered pages ask the API (port 8787) for public data. With none running they
// would show the error page, so a stub answers 404 "not found" to everything (synthetic;
// no real API, no data). If a real API is already listening, it is used instead.
let stub: Server | null = null;

test.describe("every page opens (signed out)", () => {
  // One worker runs them in order (they share the stub API), and a failure does not skip the rest.
  test.describe.configure({ mode: "default" });
  test.beforeAll(async () => {
    const server = createServer((_req, res) => {
      res.writeHead(404, { "content-type": "application/json", "access-control-allow-origin": "*" });
      res.end(JSON.stringify({ error: { code: "not_found", message: "Not found." } }));
    });
    await new Promise<void>((done) => {
      server.once("error", () => done()); // a real API is there
      server.listen(8787, "127.0.0.1", () => {
        stub = server;
        done();
      });
    });
  });
  test.afterAll(async () => {
    await new Promise<void>((done) => (stub ? stub.close(() => done()) : done()));
  });
  test("the route list covers the route map", () => {
    expect(routes.length).toBeGreaterThanOrEqual(75);
    for (const must of ["/", "/explore", "/learn", "/schedule", "/teams", "/messages", "/profile", "/settings", "/tournaments", "/sign-in", "/staff", "/teams/t1/chat", "/tournaments/tn1/bracket"]) {
      expect(routes, must).toContain(must);
    }
  });
  for (const route of routes) {
    test(route, async ({ page }) => {
      test.skip(route === "/dev/ui" && !!process.env.E2E_BASE_URL, "the gallery is not served by production builds");
      test.setTimeout(90_000);
      const { errors } = watchErrors(page);
      const res = await open(page, route);
      expect(res?.status(), "status").toBeLessThan(500);
      await expect(page.locator("main").first()).toBeVisible();
      await expect(page.getByText("Something went wrong")).toHaveCount(0);
      // A page may refuse to be seen (a member page asks to sign in); it must not crash.
      expect(errors.filter((e) => !/Failed to load resource|ERR_|Firebase|auth\/|Encountered a script tag/i.test(e))).toEqual([]);
    });
  }
});
