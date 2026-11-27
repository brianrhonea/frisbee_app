import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import { openMember } from "./helpers";

// The signed-in fixture works: Ada's session survives from the setup project and the member
// shell shows with her data (emulators, synthetic world).
test("Ada is signed in and sees her home", async ({ page }) => {
  await openMember(page, "/");
  await expect(page.locator("main").first()).toBeVisible();
  // Her name is in the account menu, and the unread counts the seed gave her are on the shell.
  await expect(page.locator("a:visible", { hasText: "Chats" }).first()).toBeVisible();
  await expect(page.getByRole("link", { name: /Notifications.*new/ })).toBeVisible();
});

test("the world is on the API: Ada's team, its events and a direct thread", async () => {
  const w = JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as { teamId: string };
  expect(w.teamId.length).toBeGreaterThan(5);
});
