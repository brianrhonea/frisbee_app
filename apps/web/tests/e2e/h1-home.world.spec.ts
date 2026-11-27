import { expect, test } from "@playwright/test";
import { openMember } from "./helpers";

// H1 Home (signed in, synthetic world): the greeting, the summary tiles, the upcoming events as
// event cards, and everything Home already did (three feed tabs, the composer).
test("Home: greeting, tiles, upcoming event cards, the three feed tabs and the composer", async ({ page }) => {
  await openMember(page, "/");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Ada");
  const tiles = page.getByRole("list", { name: "Your week" });
  await expect(tiles.getByRole("listitem")).toHaveCount(3);
  await expect(tiles).toContainText("Upcoming");
  // The seed has three teams and spaces, five upcoming events, none answered.
  await expect(tiles.locator("li").first()).toContainText("3");
  // Upcoming events are C8 event cards, each a link to the event.
  const cards = page.locator(".home-upcoming:visible .ui-event");
  expect(await cards.count()).toBeGreaterThanOrEqual(3);
  await expect(cards.first().locator("a.ui-event-main")).toHaveAttribute("href", /\/teams\/.+\/schedule\?event=/);
  await expect(cards.first()).toContainText("Needs RSVP");
  // Feed tabs and composer are still there.
  for (const t of ["Your teams", "Following", "Everyone"]) await expect(page.getByRole("tab", { name: t })).toBeVisible();
  await expect(page.getByPlaceholder("What's happening on the field?")).toBeVisible();
});

test("Home: the summary tiles are links to Teams and Schedule", async ({ page }) => {
  await openMember(page, "/");
  const tiles = page.getByRole("list", { name: "Your week" });
  await expect(tiles.getByRole("link", { name: /Teams/ })).toHaveAttribute("href", "/teams");
  await expect(tiles.getByRole("link", { name: /Upcoming/ })).toHaveAttribute("href", "/schedule");
});
