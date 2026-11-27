import { expect, test } from "@playwright/test";
import { openMember } from "./helpers";

// H4 My teams (signed in, synthetic world): your teams and communities as list rows, the create and
// join actions, and the finder with its results as rows.
test("Teams: your teams and communities as rows, the actions, and the finder", async ({ page }) => {
  await openMember(page, "/teams");
  const mine = page.locator(".teams-section", { has: page.getByRole("heading", { name: "Your teams" }) });
  const rows = mine.locator(".ui-row");
  await expect(rows).toHaveCount(2);
  await expect(rows.filter({ hasText: "Seattle Sidewinders" })).toContainText("Owner");
  await expect(rows.filter({ hasText: "Capitol Hill Pickup Crew" })).toContainText("Player");
  await expect(rows.first().locator("a.ui-row-main")).toHaveAttribute("href", /\/teams\//);
  await expect(page.locator(".teams-section", { has: page.getByRole("heading", { name: "Communities" }) })).toContainText("Seattle Ultimate Community");
  for (const name of ["Create a team", "Start a group", "Start a school or club", "Join with a code"]) {
    await expect(page.getByRole("main").getByText(name, { exact: true })).toBeVisible();
  }
  await page.getByRole("searchbox", { name: "Search teams and communities by name" }).fill("sidewinders");
  await expect(page.locator(".team-finder-list .ui-row").first()).toContainText("Seattle Sidewinders");
});
