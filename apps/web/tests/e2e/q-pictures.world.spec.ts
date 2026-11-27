import { expect, test, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { openMember, shootMember } from "./helpers";

// Sprint 5 lane Q-web review pictures:
//   review/web/Q<n>-<name>/Q<n>-<name>_<width>_<theme>_<before|after>[_variant].png
// The same file runs against the baseline (REVIEW_PHASE=before) and the changed tree (after); a picture of
// something the baseline does not have is simply skipped there. Nothing is asserted beyond "it opened".
type World = { teamId: string; password: string; users: Record<"ada" | "ben" | "cam", { email: string; uid: string }> };
const world = () => JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as World;
test.setTimeout(240_000);
// PIC_PREFIX names a fix round's folders (Q-fix-...); empty by default.
const P = process.env.PIC_PREFIX ?? "";
const phase = () => process.env.REVIEW_PHASE ?? "after";

/** Light and dark pictures of what is on screen now. */
async function snap(page: Page, screen: string, suffix = "") {
  const width = page.viewportSize()!.width;
  for (const theme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
    await page.waitForTimeout(300);
    await page.screenshot({ path: `../../review/web/${screen}/${screen}_${width}_${theme}_${phase()}${suffix}.png`, fullPage: false });
  }
}

test("pictures Q1: athlete profile (someone else's, then your own)", async ({ page }) => {
  const w = world();
  await shootMember(page, `${P}Q1-profile`, `/players/${w.users.ben.uid}`);
  await page.evaluate(() => window.scrollTo(0, 600));
  await snap(page, `${P}Q1-profile`, "_scrolled");
  await shootMember(page, `${P}Q1-profile`, `/players/${w.users.ada.uid}`, "_own");
  const spots = page.getByRole("region", { name: "Roster spots" });
  await spots.waitFor({ timeout: 15_000 }).catch(() => undefined);
  if (await spots.count()) {
    await spots.scrollIntoViewIfNeeded();
    await snap(page, `${P}Q1-profile`, "_own-spots");
  }
});

test("pictures Q2: Discover (member, search, visitor)", async ({ page, browser, baseURL }) => {
  await shootMember(page, `${P}Q2-discover`, "/explore");
  await page.evaluate(() => window.scrollTo(0, 700));
  await snap(page, `${P}Q2-discover`, "_scrolled");
  await shootMember(page, `${P}Q2-discover`, "/explore?q=cascade", "_search");
  const ctx = await browser.newContext({ baseURL: baseURL!, viewport: page.viewportSize()!, storageState: { cookies: [], origins: [] } });
  const visitor = await ctx.newPage();
  await visitor.goto("/explore", { waitUntil: "domcontentloaded" });
  await visitor.waitForTimeout(5000);
  await snap(visitor, `${P}Q2-discover`, "_visitor");
  await ctx.close();
});

test("pictures Q3: community hub and the Community feed", async ({ page }) => {
  await openMember(page, "/teams");
  const link = page.getByRole("main").locator('a[href^="/teams/"]', { hasText: "Seattle Ultimate Community" }).first();
  await expect(link).toBeVisible({ timeout: 30_000 });
  const href = await link.getAttribute("href");
  await shootMember(page, `${P}Q3-community`, href!);
  await page.evaluate(() => window.scrollTo(0, 500));
  await snap(page, `${P}Q3-community`, "_scrolled");
  await shootMember(page, `${P}Q3-community`, "/community", "_feed");
});

test("pictures Q4: post detail and composer", async ({ page }) => {
  await openMember(page, "/community");
  const first = page.locator("a.post-time").first();
  await expect(first).toBeVisible({ timeout: 30_000 });
  const href = await first.getAttribute("href");
  await shootMember(page, `${P}Q4-post`, href!);
  await shootMember(page, `${P}Q4-post`, "/home", "_composer");
  const box = page.locator("form.composer, .composer").first();
  if (await box.count()) {
    await box.scrollIntoViewIfNeeded();
    const field = box.locator("textarea").first();
    if (await field.count()) {
      await field.fill("Pickup at the north field on Saturday, 10 am. Bring a dark and a light shirt.");
      await page.waitForTimeout(300);
    }
    await snap(page, `${P}Q4-post`, "_composer-filled");
  }
});
