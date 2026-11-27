import { expect, test, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { openMember, shootMember } from "./helpers";

// Sprint 4 (lane C) review pictures: review/web/S4-<name>/S4-<name>_<width>_<theme>_<before|after>[_view].png.
// The same file runs against the baseline (REVIEW_PHASE=before) and the changed tree (after); a picture of
// something the baseline does not have is simply skipped there. Nothing is asserted beyond "it opened".
type World = { teamId: string; password: string; users: Record<"ada" | "ben" | "cam", { email: string; uid: string }> };
const world = () => JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as World;
test.setTimeout(240_000);
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

test("pictures: Month view", async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem("stall10.schedule.view", "month"));
  await shootMember(page, "S4-month", "/schedule");
});

test("pictures: Roster, Roles tab, Add member, link picker", async ({ page }) => {
  const w = world();
  await openMember(page, `/teams/${w.teamId}/roster`);
  await snap(page, "S4-roster");
  const main = page.getByRole("main");
  const roles = main.getByRole("tab", { name: "Roles" });
  if (await roles.count()) {
    await roles.click();
    await page.waitForTimeout(300);
    await snap(page, "S4-roster", "_roles");
    await main.getByRole("tab", { name: "Roster" }).click();
  }
  const add = main.getByRole("button", { name: "Add member" });
  if (await add.count()) {
    await add.click();
    await page.waitForTimeout(200);
    await snap(page, "S4-roster", "_addmember");
    await page.getByRole("menuitem", { name: "Add player to roster" }).click();
    await page.waitForTimeout(300);
    await snap(page, "S4-roster", "_linkpicker");
    const picker = page.getByLabel(/Link to a member/);
    if ((await picker.locator("option").count()) > 1) {
      await picker.selectOption({ index: 1 });
      await page.waitForTimeout(200);
      await snap(page, "S4-roster", "_linkpicker-picked");
    }
  }
});

test("pictures: Teams search with Join", async ({ page }) => {
  await openMember(page, "/teams");
  await page.getByRole("searchbox", { name: "Search teams and communities by name" }).fill("cascade");
  await expect(page.locator(".team-finder-list .ui-row").first()).toBeVisible({ timeout: 30_000 });
  await page.waitForTimeout(800);
  await page.locator("#find").scrollIntoViewIfNeeded();
  await snap(page, "S4-teams-search");
});

test("pictures: profile and the roster spots (no claiming)", async ({ page, browser, baseURL }) => {
  const w = world();
  await shootMember(page, "S4-profile", `/players/${w.users.ada.uid}`);
  // A member with no spot (Ben): the baseline offers "This is me" on the unlinked spot; the change does not.
  const ctx = await browser.newContext({ baseURL: baseURL!, viewport: page.viewportSize()!, storageState: { cookies: [], origins: [] } });
  const ben = await ctx.newPage();
  await ben.goto("/sign-in", { waitUntil: "domcontentloaded" });
  await ben.waitForTimeout(5000); // the dev server hydrates late
  await ben.getByLabel("Email or username").fill(w.users.ben.email);
  await ben.getByLabel("Password", { exact: true }).fill(w.password);
  await ben.getByRole("button", { name: /^Log in$|^Sign in$/ }).click();
  await expect(ben).not.toHaveURL(/sign-in/, { timeout: 60_000 });
  await openMember(ben, `/teams/${w.teamId}/stats/players`);
  await snap(ben, "S4-profile", "_roster-spots");
  await ctx.close();
});

test("pictures: overlap confirm", async ({ page }) => {
  const w = world();
  await openMember(page, `/teams/${w.teamId}/schedule?new=event`);
  const form = page.locator("form.event-editor");
  await form.getByLabel("Title").fill("Film session");
  const t = new Date();
  t.setDate(t.getDate() + 1);
  const day = `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, "0")}-${String(t.getDate()).padStart(2, "0")}`;
  await form.getByLabel(/^Starts/).fill(`${day}T19:00`);
  await form.getByLabel(/^Ends/).fill(`${day}T20:30`);
  await snap(page, "S4-overlap", "_form");
  // The baseline would save the event (it has no warning), so only the changed tree submits.
  if (phase() === "after") {
    await form.getByRole("button", { name: "Add", exact: true }).click();
    await expect(page.getByRole("dialog", { name: "Overlapping event" })).toBeVisible();
    await snap(page, "S4-overlap", "_confirm");
  }
});

test("pictures: team header and its Message dialog", async ({ page }) => {
  const w = world();
  await shootMember(page, "S4-team-header", `/teams/${w.teamId}`);
  const message = page.locator(".team-head").getByRole("button", { name: "Message" });
  if (await message.count()) {
    await message.click();
    await page.waitForTimeout(300);
    await snap(page, "S4-team-header", "_message");
  }
});
