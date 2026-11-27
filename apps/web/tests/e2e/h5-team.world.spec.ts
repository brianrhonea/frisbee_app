import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import { openMember } from "./helpers";

// H5 Team overview and feed (signed in, synthetic world): the cover header (logo, name, member
// stack, role, actions), the section tabs, the post and what is coming up as event cards.
const teamId = () => (JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as { teamId: string }).teamId;

test("Team: cover header, section tabs, feed post and upcoming event cards", async ({ page }) => {
  await openMember(page, `/teams/${teamId()}`);
  const cover = page.locator(".team-head .ui-cover");
  await expect(cover.getByRole("heading", { level: 1 })).toHaveText("Seattle Sidewinders");
  await expect(cover.getByRole("link", { name: /3 members/ })).toHaveAttribute("href", `/teams/${teamId()}/roster`);
  await expect(cover.getByRole("link", { name: "Invite" }).or(cover.getByRole("button", { name: "Invite" })).first()).toBeVisible();
  await expect(cover.getByRole("link", { name: "Settings" })).toBeVisible();
  for (const t of ["Feed", "Schedule", "Chat", "Roster"]) await expect(page.getByRole("link", { name: t, exact: true }).first()).toBeVisible();
  await expect(page.getByText("Practice moves to the north field this week.")).toBeVisible();
  const coming = page.locator(".coming-up .ui-event");
  expect(await coming.count()).toBeGreaterThanOrEqual(3);
  await expect(coming.first().locator("a.ui-event-main")).toHaveAttribute("href", /\/schedule\?event=/);
});
