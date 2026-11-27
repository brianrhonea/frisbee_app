import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import { axeViolations, describeViolations, openMember } from "./helpers";

// Axe (WCAG 2.2 A/AA) over every H screen, signed in, light and dark. One page load per screen:
// the theme is "system", so the colour scheme switches in place.
const world = () => JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as { teamId: string };
test.setTimeout(180_000);

const screens: [string, (w: { teamId: string }) => string][] = [
  ["H1 home", () => "/"],
  ["H2 schedule", () => "/schedule"],
  ["H7 chats", () => "/messages"],
  ["H3 event", (w) => `/teams/${w.teamId}/schedule`],
  ["H5 team", (w) => `/teams/${w.teamId}`],
  ["H6 roster", (w) => `/teams/${w.teamId}/roster`],
  ["H4 teams", () => "/teams"],
  ["H8 notifications", () => "/notifications"],
  ["H9 settings", () => "/settings"],
];

for (const [name, path] of screens) {
  test(`axe: ${name}`, async ({ page }) => {
    await openMember(page, path(world()), "light");
    for (const theme of ["light", "dark"] as const) {
      await page.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
      await page.waitForTimeout(300);
      expect(describeViolations(await axeViolations(page)), `${name} ${theme}`).toEqual([]);
    }
  });
}
