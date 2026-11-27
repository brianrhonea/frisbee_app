import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import { openMember } from "./helpers";

// H6 Roster and permissions (signed in, synthetic world): members as list rows with role pills
// (the owner's in the accent tone), the filter, and Invite.
const teamId = () => (JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as { teamId: string }).teamId;

test("Roster: members as rows with role pills, a filter, and Invite", async ({ page }) => {
  await openMember(page, `/teams/${teamId()}/roster`);
  const rows = page.locator(".roster-rows .ui-row");
  await expect(rows).toHaveCount(3);
  await expect(rows.filter({ hasText: "Ada Rivers" })).toContainText("Owner");
  await expect(rows.filter({ hasText: "Ben Okafor" })).toContainText("Player");
  await expect(rows.filter({ hasText: "Ada Rivers" }).locator("a.ui-row-main")).toHaveAttribute("href", /\/players\//);
  await page.getByRole("searchbox", { name: "Filter the roster" }).fill("cam");
  await expect(rows).toHaveCount(1);
  await expect(rows.first()).toContainText("Cam Lindqvist");
  await expect(page.getByRole("main").getByRole("button", { name: "Invite" }).or(page.getByRole("main").getByRole("link", { name: "Invite" })).first()).toBeVisible();
});
