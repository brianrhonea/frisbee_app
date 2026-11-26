import { test } from "@playwright/test";
import { open } from "./helpers";

// Before-pictures of the website for the UI rework (board task P7), written
// to docs/ui-baseline/web for side-by-side review. Not a pass/fail check, so
// it only runs when asked:
//   BASELINE=1 pnpm exec playwright test baseline --project=phone --project=desktop
// Signed out: member pages need a test account (see the route map).
const pages = [
  ["home", "/"],
  ["discover", "/explore"],
  ["learn", "/learn"],
  ["teams", "/teams"],
  ["schedule", "/schedule"],
  ["tournaments", "/tournaments"],
  ["sign-in", "/sign-in"],
  ["sign-up", "/sign-up"],
] as const;

test.skip(!process.env.BASELINE, "set BASELINE=1 to capture before-pictures");

for (const [name, path] of pages) {
  test(`before-picture: ${name}`, async ({ page }, info) => {
    for (const theme of ["light", "dark"] as const) {
      await open(page, path, theme);
      await page.screenshot({
        path: `../../docs/ui-baseline/web/${theme}/${name}-${info.project.name}.png`,
        fullPage: true,
      });
    }
  });
}
