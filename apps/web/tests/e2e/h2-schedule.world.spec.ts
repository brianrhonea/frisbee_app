import { expect, test } from "@playwright/test";
import { openMember, shootMember } from "./helpers";

// H2 Schedule (signed in, synthetic world): List, Week and Month, each showing event cards, and
// the picked day's events under the week strip and the month grid.
test("Schedule: List shows event cards by day, with RSVP states", async ({ page }) => {
  await openMember(page, "/schedule");
  await page.getByRole("tab", { name: "List" }).click();
  const cards = page.locator(".sched-item .ui-event");
  await expect(cards.first()).toBeVisible();
  expect(await cards.count()).toBeGreaterThanOrEqual(3);
  await expect(page.locator(".sched-item", { hasText: "Tuesday practice" })).toContainText("Needs RSVP");
  await expect(page.locator(".sched-item", { hasText: "Thursday throwing" }).first()).toContainText("Repeats");
});

test("Schedule: Week has a seven-day strip, previous and next week, and the picked day's events", async ({ page }) => {
  await openMember(page, "/schedule");
  await page.getByRole("tab", { name: "Week" }).click();
  const strip = page.getByRole("grid");
  await expect(strip.getByRole("gridcell")).toHaveCount(7);
  const start = await page.locator(".sched-month-head b").innerText();
  await page.getByRole("button", { name: "Next week" }).click();
  expect(await page.locator(".sched-month-head b").innerText()).not.toBe(start);
  await page.getByRole("button", { name: "Previous week" }).click();
  expect(await page.locator(".sched-month-head b").innerText()).toBe(start);
  // Pick the day after tomorrow: a "Thursday throwing" is on it (the weekly series starts then).
  const day = new Date();
  day.setDate(day.getDate() + 2);
  await page.getByRole("gridcell", { name: day.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" }) }).click();
  await expect(page.locator(".sched-day.picked .ui-event", { hasText: "Thursday throwing" })).toBeVisible();
  // Only the picked day's events are listed.
  expect(await page.locator(".sched-day.picked .ui-event").count()).toBe(1);
});

// Sprint 4 C1: the Month view lists the whole month under the grid; the picked day is highlighted in that list.
test("Schedule: Month shows the grid and the picked day's events in the month list; the view is remembered", async ({ page }) => {
  await openMember(page, "/schedule");
  await page.getByRole("tab", { name: "Month" }).click();
  expect(await page.getByRole("gridcell").count()).toBeGreaterThanOrEqual(28);
  const day = new Date();
  day.setDate(day.getDate() + 1);
  await page.getByRole("gridcell", { name: day.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" }) }).click();
  await expect(page.locator(".sched-day.picked .ui-event", { hasText: "Tuesday practice" })).toBeVisible();
  expect(await page.evaluate(() => localStorage.getItem("stall10.schedule.view"))).toBe("month");
});

// Pictures of the other two views (review/web/H2-schedule/H2-schedule_<width>_<theme>_after_<view>.png).
for (const view of ["week", "month"]) {
  test(`pictures: ${view}`, async ({ page }) => {
    await page.addInitScript((v) => localStorage.setItem("stall10.schedule.view", v), view);
    await shootMember(page, "H2-schedule", "/schedule", `_${view}`);
  });
}
