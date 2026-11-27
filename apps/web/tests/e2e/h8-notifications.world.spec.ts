import { expect, test } from "@playwright/test";
import { openMember } from "./helpers";

// H8 Notifications (signed in, synthetic world): filter chips, groups by day, unread dots, and the
// requests row. (Nothing is marked read or cleared here, so the later specs still see 2 unread.)
test("Notifications: chips, day groups, unread dots, and filtering", async ({ page }) => {
  await openMember(page, "/notifications");
  const chips = page.getByRole("radiogroup", { name: "Show" });
  for (const c of ["All", "People", "Posts", "Teams and events"]) await expect(chips.getByText(c, { exact: true })).toBeVisible();
  const rows = page.locator(".notice-list .notice");
  await expect(rows).toHaveCount(4);
  // The seed has two unread (the like and the new event), shown as dots.
  await expect(page.locator(".notice-list .notice.unread")).toHaveCount(2);
  // Every row sits under a Today or an Earlier heading.
  const heads = await page.locator(".notice-group-head").allInnerTexts();
  expect(heads.some((h) => /today|earlier/i.test(h))).toBe(true);
  await expect(page.getByRole("link", { name: /Follow requests/ })).toHaveAttribute("href", "/notifications/requests");

  await chips.getByText("People", { exact: true }).click();
  await expect(rows.filter({ hasText: "Practice moved" })).toHaveCount(0);
  await expect(rows.filter({ hasText: "Ben Okafor liked your post" })).toHaveCount(1);
});
