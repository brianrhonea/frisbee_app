import { expect, test as setup } from "@playwright/test";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { seedWorld } from "./world/seed.mjs";

// Seeds the synthetic world (emulators only) and signs Ada in through the real sign-in form,
// saving the browser state, IndexedDB included, for the signed-in projects.
setup("seed the world and sign Ada in", async ({ page }) => {
  setup.setTimeout(180_000);
  const w = await seedWorld();
  mkdirSync("review/web/.auth", { recursive: true });
  writeFileSync("review/web/.auth/world.json", JSON.stringify(w));
  await page.goto("/sign-in");
  await page.waitForLoadState("networkidle");
  await page.waitForTimeout(2500); // the dev server hydrates late
  await page.getByLabel("Email or username").fill(w.users.ada.email);
  await page.getByLabel("Password", { exact: true }).fill(w.password);
  await page.getByRole("button", { name: /^Log in$|^Sign in$/ }).click();
  await expect(page).not.toHaveURL(/sign-in/, { timeout: 60_000 });
  await page.waitForLoadState("networkidle");
  await page.context().storageState({ path: "review/web/.auth/ada.json", indexedDB: true });
  void dirname;
});
