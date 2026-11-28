import { expect, test } from "@playwright/test";
import { openMember } from "./helpers";

// N9: arrow keys move between tabs. The shared tab bar's keys are unit-tested (SegmentedTabs.test.tsx),
// Discover's chips and the gallery's tablist are browser-tested (shell-keyboard.spec.ts). These are the
// two real signed-in pages that use the tab bar: Home's Feed tabs and Schedule's View tabs.

async function arrows(page: import("@playwright/test").Page, name: string) {
  const list = page.getByRole("tablist", { name });
  await expect(list).toBeVisible();
  const tabs = list.getByRole("tab");
  const n = await tabs.count();
  expect(n).toBeGreaterThan(1);
  await list.getByRole("tab", { selected: true }).focus();
  await page.keyboard.press("Home");
  await expect(tabs.first()).toHaveAttribute("aria-selected", "true");
  await page.keyboard.press("ArrowRight");
  await expect(tabs.nth(1)).toBeFocused();
  await expect(tabs.nth(1)).toHaveAttribute("aria-selected", "true");
  await page.keyboard.press("ArrowLeft");
  await expect(tabs.first()).toBeFocused();
  await expect(tabs.first()).toHaveAttribute("aria-selected", "true");
  await page.keyboard.press("End");
  await expect(tabs.last()).toHaveAttribute("aria-selected", "true");
  // Only the selected tab is a Tab stop (roving tabindex).
  await expect(list.locator('[role="tab"][tabindex="0"]')).toHaveCount(1);
}

test("Home's Feed tabs: arrows, Home and End move and select", async ({ page }) => {
  await openMember(page, "/");
  await arrows(page, "Feed");
});

test("Schedule's View tabs: arrows, Home and End move and select", async ({ page }) => {
  await openMember(page, "/schedule");
  await arrows(page, "View");
});
