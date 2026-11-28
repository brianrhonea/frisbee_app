import { expect, test, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { axeViolations, describeViolations, openMember } from "./helpers";

// Sprint 5 lane Q-web: the restyled athlete profile (Q1), Discover (Q2), Community (Q3) and post detail and
// composer (Q4), signed in as Ada, at 375 and 1440 px, light and dark: they open, nothing scrolls sideways,
// the shared components are on the page, and axe (WCAG 2.2 A/AA) finds nothing.
type World = { teamId: string; users: Record<"ada" | "ben" | "cam", { email: string; uid: string }> };
const world = () => JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as World;
test.setTimeout(240_000);

async function noSideScroll(page: Page) {
  const wide = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(wide, "horizontal scroll").toBeLessThanOrEqual(0);
}

async function axeBothThemes(page: Page, name: string) {
  for (const theme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
    await page.waitForTimeout(300);
    expect(describeViolations(await axeViolations(page)), `${name} ${theme}`).toEqual([]);
  }
}

test("Q1 athlete profile: cover header, Follow and Message, quiet Report and Block, stat tiles", async ({ page }) => {
  const w = world();
  await openMember(page, `/players/${w.users.ben.uid}`);
  const head = page.locator(".ui-cover");
  await expect(head.getByRole("heading", { level: 1, name: "Ben Okafor" })).toBeVisible();
  await expect(head.getByText("@benokafor")).toBeVisible();
  await expect(head.locator(".ui-cover-actions").getByRole("button", { name: "Follow" })).toBeVisible();
  await expect(head.locator(".ui-cover-actions").getByRole("button", { name: "Message" })).toBeVisible();
  const safety = head.locator(".profile-secondary");
  await expect(safety.getByRole("button", { name: "Report" })).toBeVisible();
  await expect(safety.getByRole("button", { name: "Block" })).toBeVisible();
  // Stats and teams stay beside the posts; with no games yet the stat card says so.
  await expect(page.getByText("No stats yet. Stats come from games kept in the app.")).toBeVisible();
  await expect(page.getByRole("heading", { name: "Posts" })).toBeVisible();
  // The Posts count (a Firestore count of the posts this member may see): Ben has one.
  const counts = head.getByRole("list", { name: "Activity" });
  await expect(counts).toContainText("1", { timeout: 15_000 });
  await expect(counts).toContainText("Post");
  // No header photo: the designed default band with the initials.
  await expect(head.locator(".ui-cover-default")).toHaveAttribute("data-initials", "BO");
  await noSideScroll(page);
  await axeBothThemes(page, "Q1 profile");
});

test("Q1 athlete profile: your own page keeps Edit profile and the Roster spots card", async ({ page }) => {
  const w = world();
  await openMember(page, `/players/${w.users.ada.uid}`);
  await expect(page.locator(".ui-cover").getByRole("heading", { level: 1, name: "Ada Rivers" })).toBeVisible();
  await expect(page.locator(".ui-cover").getByRole("link", { name: "Edit profile" })).toBeVisible();
  // Nobody reports or blocks themselves.
  await expect(page.locator(".profile-secondary")).toHaveCount(0);
  await expect(page.getByRole("region", { name: "Roster spots" })).toBeVisible({ timeout: 15_000 });
  await noSideScroll(page);
  await axeBothThemes(page, "Q1 own profile");
});

test("Q2 Discover: search results are list rows, empty and hint states are the shared ones", async ({ page }) => {
  await openMember(page, "/explore");
  await expect(page.getByRole("search")).toBeVisible();
  await expect(page.getByRole("searchbox", { name: "Search Stall 10" })).toBeVisible();
  await expect(page.getByRole("radiogroup", { name: "Show" }).or(page.getByRole("group", { name: "Show" })).first()).toBeVisible();
  await noSideScroll(page);
  await axeBothThemes(page, "Q2 discover");
  await page.getByRole("searchbox", { name: "Search Stall 10" }).fill("cascade");
  await expect(page.locator(".explore-rows .ui-row").first()).toBeVisible({ timeout: 30_000 });
  // The title comes back with the page after the address changes (search rewrites ?q=).
  await expect(page).toHaveTitle(/Discover/);
  await noSideScroll(page);
  await axeBothThemes(page, "Q2 discover results");
  // Teams and communities Ada belongs to say Joined (a success pill with words, not colour alone).
  await page.getByRole("searchbox", { name: "Search Stall 10" }).fill("seattle");
  await expect(page.locator(".explore-rows .ui-row", { hasText: "Seattle Ultimate Community" }).getByText("Joined")).toBeVisible({ timeout: 30_000 });
  await expect(page.getByText("Your group")).toHaveCount(0);
  await page.getByRole("searchbox", { name: "Search Stall 10" }).fill("zzzzqq");
  await expect(page.getByText("Nothing found")).toBeVisible({ timeout: 30_000 });
  await expect(page).toHaveTitle(/Discover/);
  await axeBothThemes(page, "Q2 discover nothing found");
});

test("Q2 Discover as a visitor: public lists and search, no Players chip", async ({ browser, baseURL, page }) => {
  const ctx = await browser.newContext({ baseURL: baseURL!, viewport: page.viewportSize()!, storageState: { cookies: [], origins: [] } });
  const visitor = await ctx.newPage();
  await visitor.goto("/explore", { waitUntil: "domcontentloaded" });
  await expect(visitor.getByRole("searchbox", { name: "Search Stall 10" })).toBeVisible({ timeout: 30_000 });
  await expect(visitor.getByText("Log in to search people")).toBeVisible();
  await expect(visitor.getByRole("radio", { name: "Players" })).toHaveCount(0);
  await noSideScroll(visitor);
  await axeBothThemes(visitor, "Q2 visitor");
  await ctx.close();
});

test("Q3 community hub: next pickup, chat rooms and organizers use the shared rows", async ({ page }) => {
  await openMember(page, "/teams");
  const link = page.getByRole("main").locator('a[href^="/teams/"]', { hasText: "Seattle Ultimate Community" }).first();
  await expect(link).toBeVisible({ timeout: 30_000 });
  await openMember(page, (await link.getAttribute("href"))!);
  await expect(page.getByRole("heading", { name: "Next pickup" })).toBeVisible();
  await expect(page.getByText("No pickup scheduled")).toBeVisible();
  const rooms = page.locator(".community-chat");
  await expect(rooms.getByRole("heading", { name: "Chat rooms" })).toBeVisible();
  await expect(rooms.locator(".ui-row").first()).toContainText("general");
  const organizers = page.locator(".community-organizers");
  await expect(organizers.locator(".ui-row").first()).toContainText("Ada Rivers");
  await expect(organizers.locator(".ui-row").first()).toContainText("Owner");
  await noSideScroll(page);
  await axeBothThemes(page, "Q3 community");
});

test("Q3 Community feed: posts list, and no sign-up prompt for a signed-in member", async ({ page }) => {
  await openMember(page, "/community");
  await expect(page.getByRole("heading", { level: 1, name: "Community" })).toBeVisible();
  await expect(page.locator("article.post").first()).toBeVisible({ timeout: 30_000 });
  await expect(page.getByRole("link", { name: "Sign up free" })).toHaveCount(0);
  await noSideScroll(page);
  await axeBothThemes(page, "Q3 community feed");
});

test("Q4 post detail: back link, the post, comments with an empty state, a comment box", async ({ page }) => {
  await openMember(page, "/community");
  const first = page.locator("a.post-time").first();
  await expect(first).toBeVisible({ timeout: 30_000 });
  await openMember(page, (await first.getAttribute("href"))!);
  await expect(page.getByRole("link", { name: /Community/ }).first()).toBeVisible();
  await expect(page.locator("article.post")).toBeVisible();
  const comments = page.getByRole("region", { name: "Comments" });
  await expect(comments).toBeVisible({ timeout: 15_000 });
  await expect(comments.getByText("No comments yet. Start the conversation.")).toBeVisible({ timeout: 15_000 });
  const send = comments.getByRole("button", { name: "Comment" });
  await expect(send).toBeDisabled();
  await comments.getByRole("textbox", { name: "Write a comment" }).fill("See you there");
  await expect(send).toBeEnabled();
  await comments.getByRole("textbox", { name: "Write a comment" }).fill("");
  await noSideScroll(page);
  await axeBothThemes(page, "Q4 post");
});

test("Q4 composer: Send is off until there are words, Photo and Workout are toggles with names", async ({ page }) => {
  await openMember(page, "/home");
  const composer = page.locator("form.composer, .composer").first();
  await expect(composer).toBeVisible({ timeout: 30_000 });
  const send = composer.getByRole("button", { name: "Send" });
  await expect(send).toBeDisabled();
  await composer.getByRole("textbox").first().fill("Pickup at the north field on Saturday");
  await expect(send).toBeEnabled();
  await expect(composer.getByRole("button", { name: /workout/i })).toHaveAttribute("aria-pressed", "false");
  await composer.getByRole("button", { name: /workout/i }).click();
  await expect(composer.getByRole("group", { name: "Workout" }).or(composer.locator("fieldset.workout-fields"))).toBeVisible();
  await expect(composer.getByRole("button", { name: "Add an exercise" })).toBeVisible();
  await noSideScroll(page);
  await axeBothThemes(page, "Q4 composer");
});
