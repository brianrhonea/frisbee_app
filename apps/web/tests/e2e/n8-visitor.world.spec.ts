import { expect, test } from "@playwright/test";
import { open } from "./helpers";
import { ensureYouthTeam, removeYouthTeam, teamIdByName, world } from "./worldApi";

test.afterAll(removeYouthTeam);

// N8 (signed out, against the real API and the synthetic world): the visitor-access rules. Signed-out
// visitors see learn, events, teams and tournaments; youth rosters and communities' members stay private;
// a member-only area asks them to log in and signing in comes back to it.
test.use({ storageState: { cookies: [], origins: [] } });

test("a visitor sees a team's public page; its chat asks them to log in and comes back to the chat", async ({ page }) => {
  const id = world().teamId;
  await open(page, `/teams/${id}`);
  await expect(page.getByRole("heading", { level: 1, name: "Seattle Sidewinders" })).toBeVisible();
  await open(page, `/teams/${id}/chat`);
  await expect(page.getByText("Only members see this team's chat.")).toBeVisible();
  await expect(page.locator("main").getByRole("link", { name: "Log in" })).toHaveAttribute("href", `/sign-in?next=${encodeURIComponent(`/teams/${id}/chat`)}`);
});

test("a visitor does not see a community's members, or a youth team's roster", async ({ page }) => {
  const community = await teamIdByName("Seattle Ultimate Community");
  await open(page, `/teams/${community}/roster`);
  await expect(page.getByText(/Only members see who's in this community/)).toBeVisible();
  const youth = await ensureYouthTeam();
  await open(page, `/teams/${youth}/roster`);
  await expect(page.getByText("Rosters of youth teams are private: only members see them.")).toBeVisible();
  // No names in the page for either (the API answers the public roster with a refusal).
  await expect(page.locator("main")).not.toContainText("Cam Lindqvist");
});

test("a visitor's adult team roster is public (the contrast to the youth rule)", async ({ page }) => {
  await open(page, `/teams/${world().teamId}/roster`);
  await expect(page.locator("main").first()).toBeVisible();
  await expect(page.getByText("Only members see this team's roster.")).toHaveCount(0);
});

test("visitors can open Learn, events (Discover), teams and tournaments", async ({ page }) => {
  for (const path of ["/learn", "/explore", "/teams", "/tournaments"]) {
    await open(page, path);
    await expect(page.locator("main").first()).toBeVisible();
    // (The tournament list carries its own "sign up free" note for entering; that is a call to action, not a gate.)
    if (path !== "/tournaments") await expect(page.locator(".join-prompt")).toHaveCount(0);
    else await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  }
});

test("logging in from a member-only page comes back to it", async ({ page }) => {
  const w = world();
  await open(page, "/schedule");
  await page.locator(".join-prompt").getByRole("link", { name: "Log in" }).click();
  await expect(page).toHaveURL(/\/sign-in\?next=%2Fschedule$/);
  await expect(page.getByRole("link", { name: "Create an account" })).toHaveAttribute("href", "/sign-up?next=%2Fschedule");
  await page.waitForTimeout(2500); // the dev server hydrates late
  await page.getByLabel("Email or username").fill(w.users.ben.email);
  await page.getByLabel("Password", { exact: true }).fill(w.password);
  await page.getByRole("button", { name: /^Log in$|^Sign in$/ }).click();
  await expect(page).toHaveURL(/\/schedule$/, { timeout: 60_000 });
  await expect(page.locator(".join-prompt")).toHaveCount(0);
});
