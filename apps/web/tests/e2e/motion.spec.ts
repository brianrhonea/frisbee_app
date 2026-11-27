import { expect, test, type Page } from "@playwright/test";

// N13: the main journeys, recorded as video for the owner's review. Opt-in: these run only in
// the motion-* projects (E2E_MOTION=1), which turn video on and leave reduced motion off.
// Videos: review/web/motion/<width>-<theme>/. Pauses are slow on purpose so a person can watch.
const pause = (page: Page, ms = 1200) => page.waitForTimeout(ms);

async function go(page: Page, path: string) {
  await page.goto(path);
  await page.waitForLoadState("networkidle");
  await hideDevBadge(page);
  await pause(page, 2600); // the dev server hydrates late
}

// The Next dev badge sits over the first tab at phone width (dev server only), and would be in the video.
const hideDevBadge = (page: Page) => page.addStyleTag({ content: "nextjs-portal { display: none !important; }" });

async function nav(page: Page, name: RegExp | string) {
  const phone = page.viewportSize()!.width < 600;
  const link = page.locator(phone ? ".tab-bar" : ".side-tabs").getByRole("link", { name }).first();
  await link.click();
  await page.waitForLoadState("networkidle");
  await hideDevBadge(page);
  await pause(page);
}

test("visitor: home, learn, events, tournaments, sign-in", async ({ page }) => {
  test.setTimeout(180_000);
  await go(page, "/");
  await page.mouse.wheel(0, 500);
  await pause(page);
  await go(page, "/learn");
  await page.mouse.wheel(0, 500);
  await pause(page);
  await go(page, "/explore");
  await go(page, "/tournaments");
  await go(page, "/sign-in");
  await pause(page);
  expect(page.url()).toContain("/sign-in");
});

test("the shell tabs and the Discover to Learn path", async ({ page }) => {
  test.setTimeout(180_000);
  await go(page, "/explore");
  for (const name of [/Tournaments/, /Pickup/, /Communities/, /Learn/, /Discover/]) await nav(page, name);
  await page.getByRole("link", { name: /New to ultimate/ }).click();
  await page.waitForLoadState("networkidle");
  await hideDevBadge(page);
  await pause(page, 2000);
  await page.goBack();
  await pause(page, 1500);
});

test("open and close a confirm dialog", async ({ page }) => {
  test.skip(!!process.env.E2E_BASE_URL, "the gallery is not served by production builds");
  await go(page, "/dev/ui");
  const opener = page.getByRole("button", { name: "Open destructive confirm" });
  await opener.scrollIntoViewIfNeeded();
  await pause(page);
  await opener.click();
  await pause(page, 1800);
  await page.keyboard.press("Escape");
  await pause(page, 1200);
  await page.getByRole("button", { name: "Open confirm" }).click();
  await pause(page, 1800);
  await page.getByRole("button", { name: "Publish" }).click();
  await pause(page, 1200);
});
