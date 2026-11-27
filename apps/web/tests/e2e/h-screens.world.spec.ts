import { test } from "@playwright/test";
import { readFileSync } from "node:fs";
import { shootMember } from "./helpers";

// Review pictures of every H screen, signed in as Ada in the synthetic world, light and dark,
// at 375 and 1440 px: REVIEW_PHASE=before (or after) world-375 / world-1440.
// Output: review/web/H<n>-<name>/<phase>-<width>-<theme>.png
const world = () => JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as { teamId: string };

test.setTimeout(180_000);

const screens: [string, (w: { teamId: string }) => string][] = [
  ["H1-home", () => "/"],
  ["H2-schedule", () => "/schedule"],
  ["H7-chats", () => "/messages"],
  ["H3-event", (w) => `/teams/${w.teamId}/schedule`],
  ["H5-team", (w) => `/teams/${w.teamId}`],
  ["H6-roster", (w) => `/teams/${w.teamId}/roster`],
  ["H4-teams", () => "/teams"],
  ["H8-notifications", () => "/notifications"],
  ["H9-settings", () => "/settings"],
];

for (const [name, path] of screens) {
  test(`${name}`, async ({ page }) => {
    await shootMember(page, name, path(world()));
  });
}

// H10 is for people who are signed out.
test.describe("signed out", () => {
  test.use({ storageState: { cookies: [], origins: [] } });
  for (const [name, path] of [["H10-sign-in", "/sign-in"], ["H10-sign-up", "/sign-up"]] as const) {
    test(name, async ({ page }) => {
      await shootMember(page, name, path);
    });
  }
});
