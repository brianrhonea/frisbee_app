import { expect, test } from "@playwright/test";
import { axeViolations, describeViolations, open, watchErrors } from "./helpers";

// Checks the browser-test setup on two public pages (board task P6). The
// full route list comes in N8; screenshots of the P0 pages in P7.
for (const path of ["/learn", "/sign-in"]) {
  test(`${path} loads with no errors`, async ({ page }) => {
    const { errors, offline } = watchErrors(page);
    const res = await open(page, path);
    expect(res?.status()).toBeLessThan(400);
    await expect(page.locator("main").first()).toBeVisible();
    expect(errors).toEqual([]);
    if (offline.length) console.log(`${path}: ${offline.length} request(s) to a stopped local service`);
  });

  test(`${path} accessibility scan (report only)`, async ({ page }, info) => {
    await open(page, path);
    const found = describeViolations(await axeViolations(page));
    // Today's violations are recorded, not failed on: the UI rework fixes
    // them. A later task turns this into a failing check per page.
    await info.attach("axe-violations", { body: found.join("\n") || "none", contentType: "text/plain" });
    console.log(`${path} [${info.project.name}] axe: ${found.length ? found.join("; ") : "none"}`);
  });
}
