import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import { openMember } from "./helpers";

// H3 Event details and RSVP (signed in, synthetic world): event cards in the list, the open event
// under a cover header, and Going / Maybe / Can't go with the attendee counts.
const teamId = () => (JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as { teamId: string }).teamId;

test("Event: list of event cards, the open one under a cover header, and an answer that can be taken back", async ({ page }) => {
  await openMember(page, `/teams/${teamId()}/schedule`);
  const cards = page.locator(".sched-list .ui-event");
  expect(await cards.count()).toBeGreaterThanOrEqual(3);
  await expect(cards.first()).toContainText("Needs RSVP");

  // Open the scrimmage: the cover header names it; the answers start at nothing.
  await cards.filter({ hasText: "Scrimmage vs Rainiers" }).locator("a.ui-event-main").click();
  const detail = page.locator("article.event-detail");
  await expect(detail.locator(".ui-cover-title")).toHaveText("Scrimmage vs Rainiers");
  await expect(cards.filter({ hasText: "Scrimmage vs Rainiers" })).toHaveClass(/ui-event-selected/);
  const answer = detail.getByRole("group", { name: "Your answer" });
  await expect(answer.getByRole("button", { name: /Going/ })).toHaveAttribute("aria-pressed", "false");

  // Answer Going, see it on the card and the pressed button, then take it back.
  await answer.getByRole("button", { name: /Going/ }).click();
  await expect(answer.getByRole("button", { name: /Going/ })).toHaveAttribute("aria-pressed", "true");
  await expect(cards.filter({ hasText: "Scrimmage vs Rainiers" })).toContainText("Going");
  await answer.getByRole("button", { name: /Going/ }).click();
  await expect(answer.getByRole("button", { name: /Going/ })).toHaveAttribute("aria-pressed", "false");
  await expect(cards.filter({ hasText: "Scrimmage vs Rainiers" })).toContainText("Needs RSVP");
});
