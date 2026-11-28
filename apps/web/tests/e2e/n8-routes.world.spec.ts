import { expect, test, type BrowserContext } from "@playwright/test";
import { openMember, watchErrors } from "./helpers";
import { ignorableConsole, routesWith, syntheticIds } from "./routeMap";
import { world } from "./worldApi";

// N8 (signed in): every website route in the route map opens for a signed-in member, with no console
// errors and no error screen. The list is read from app/**/page.tsx, like routes.spec.ts (signed out).
// The team's id is real; the other ids are made up, so those pages show their "not found" or "not
// allowed" state, which is a load. Pages that move a member on are named below and checked for where
// they end up.
//
// The member is Ben (a player on the seeded team), not Ada: the API caps the "who am I" call at 200 a
// day per account and every full page load makes one, so about 80 routes at two widths would not fit
// beside the other signed-in specs, which are Ada's. Ben signs in once per browser through the real form.
//
// (The world file is written by the setup project, so ids are filled in when a test runs, not when the
// files are listed: the titles carry TEAM and UID.)

const routes = routesWith({ ...syntheticIds, teamId: "TEAM", uid: "UID" });
const me = () => world().users.ben;
const fill = (r: string) => r.replace("TEAM", world().teamId).replace("UID", me().uid);

/** Where a member ends up after opening these (matched against the final URL). */
const moved = (r: string): RegExp | null => {
  const map: Record<string, RegExp> = {
    "/sign-in": /\/$/,
    "/sign-up": /\/$/,
    "/home": /\/$/,
    "/profile": new RegExp(`/players/${me().uid}$`),
    "/settings": /\/settings\/profile$/,
    "/settings/requests": /\/notifications\/requests$/,
    "/teams/TEAM/more": new RegExp(`/teams/${world().teamId}/\\w+`),
    "/teams/TEAM/plays": /\/playbook$/,
    "/teams/TEAM/whiteboards": /\/playbook\?view=whiteboard$/,
  };
  return map[r] ?? null;
};

let ctx: BrowserContext;

test.beforeAll(async ({ browser }) => {
  test.setTimeout(120_000);
  const use = test.info().project.use;
  ctx = await browser.newContext({ storageState: { cookies: [], origins: [] }, baseURL: use.baseURL, viewport: use.viewport, isMobile: use.isMobile, hasTouch: use.hasTouch, userAgent: use.userAgent, deviceScaleFactor: use.deviceScaleFactor });
  const page = await ctx.newPage();
  await page.goto("/sign-in", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(4000); // the dev server hydrates late
  await page.getByLabel("Email or username").fill(world().users.ben.email);
  await page.getByLabel("Password", { exact: true }).fill(world().password);
  await page.getByRole("button", { name: /^Log in$|^Sign in$/ }).click();
  await expect(page).not.toHaveURL(/sign-in/, { timeout: 60_000 });
  await page.close();
});
test.afterAll(async () => {
  await ctx?.close();
});

test("the route list covers the route map", () => {
  expect(routes.length).toBeGreaterThanOrEqual(75);
  for (const must of ["/", "/explore", "/learn", "/schedule", "/teams", "/messages", "/profile", "/settings/profile", "/tournaments", "/sign-in", "/staff", "/teams/TEAM/chat"]) expect(routes, must).toContain(must);
});

for (const route of routes) {
  test(route, async () => {
    test.skip(route === "/dev/ui" && !!process.env.E2E_BASE_URL, "the gallery is not served by production builds");
    test.setTimeout(90_000);
    const page = await ctx.newPage();
    try {
      const { errors } = watchErrors(page);
      const path = fill(route);
      const res = await openMember(page, path, "light", 3000);
      expect(res?.status(), "status").toBeLessThan(500);
      await expect(page.locator("main").first()).toBeVisible();
      await expect(page.getByText("Something went wrong")).toHaveCount(0);
      const to = moved(route);
      if (to) await expect(page).toHaveURL(to, { timeout: 20_000 });
      else expect(new URL(page.url()).pathname, "stays on the page").toBe(path);
      expect(errors.filter((e) => !ignorableConsole.test(e))).toEqual([]);
    } finally {
      await page.close();
    }
  });
}
