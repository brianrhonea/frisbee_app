import { test } from "@playwright/test";
import { open } from "./helpers";

// Before/after pictures for owner review (Sprint 2 C1-C4), written to
// <worktree>/review/web (untracked). Not a pass/fail check, so it only runs
// when asked:
//   REVIEW_PHASE=before|after pnpm exec playwright test review --project=phone --project=desktop
// Signed out and synthetic: the showcase (app/dev/ui, non-production only)
// carries every component state; member pages need a test account.
const phase = process.env.REVIEW_PHASE;
const out = "../../review/web";
const pages = [
  ["home", "/"],
  ["discover", "/explore"],
  ["teams", "/teams"],
  ["tournaments", "/tournaments"],
  ["learn", "/learn"],
  ["events", "/events"],
  ["sign-in", "/sign-in"],
] as const;
// [showcase section, picture name]
const showcases = [
  ["statuspill", "c1_statuspill"],
  ["button", "c2_button"],
  ["tabs", "c3_tabs"],
  ["chips", "c3_chips"],
  ["avatar", "c4_avatar"],
] as const;

test.skip(!phase, "set REVIEW_PHASE=before|after to capture review pictures");

for (const theme of ["light", "dark"] as const) {
  test(`pages ${theme}`, async ({ page }, info) => {
    const size = info.project.name === "phone" ? "mobile" : "desktop";
    for (const [name, path] of pages) {
      await open(page, path, theme);
      await page.screenshot({ path: `${out}/${name}_${size}_${theme}_${phase}.png`, fullPage: true });
    }
  });

  test(`showcase ${theme}`, async ({ page }, info) => {
    const size = info.project.name === "phone" ? "mobile" : "desktop";
    await open(page, "/dev/ui", theme);
    await page.screenshot({ path: `${out}/gallery_${size}_${theme}_${phase}.png`, fullPage: true });
    for (const [section, name] of showcases) {
      await page.locator(`[data-showcase="${section}"]`).screenshot({ path: `${out}/${name}_${size}_${theme}_${phase}.png` });
    }
  });
}
