import { expect, test } from "@playwright/test";

// N13: motion follows the K7 tokens (120 / 200 / 300 ms) and is off under reduced motion.
test.beforeEach(() => test.skip(!!process.env.E2E_BASE_URL, "the gallery is not served by production builds"));

// Custom properties come back as written ("120ms") or normalised ("0s"), so read milliseconds.
const tokens = () => {
  const cs = getComputedStyle(document.documentElement);
  const ms = (n: string) => {
    const v = cs.getPropertyValue(n).trim();
    return v.endsWith("ms") ? parseFloat(v) : parseFloat(v) * 1000;
  };
  return { fast: ms("--dur-fast"), base: ms("--dur-base"), sheet: ms("--dur-sheet"), scroll: cs.scrollBehavior };
};

test("with motion allowed the tokens are 120, 200 and 300 ms and a dialog opens over the sheet time", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await page.goto("/dev/ui");
  await page.waitForLoadState("networkidle");
  await page.waitForTimeout(1500);
  expect(await page.evaluate(tokens)).toMatchObject({ fast: 120, base: 200, sheet: 300 });
  await page.getByRole("button", { name: "Open confirm" }).click();
  const dialog = page.getByRole("dialog", { name: "Publish the schedule?" });
  await expect(dialog).toBeVisible();
  const anim = await dialog.evaluate((el) => {
    const cs = getComputedStyle(el);
    return { name: cs.animationName, ms: parseFloat(cs.animationDuration) * 1000 };
  });
  expect(anim).toEqual({ name: "dialog-in", ms: 300 });
});

test("with reduced motion every token is 0, nothing transitions or animates, and scrolling is instant", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/dev/ui");
  await page.waitForLoadState("networkidle");
  await page.waitForTimeout(1500);
  expect(await page.evaluate(tokens)).toMatchObject({ fast: 0, base: 0, sheet: 0, scroll: "auto" });
  // Buttons, tabs and the rest: no transition time anywhere in the page.
  const moving = await page.evaluate(() =>
    Array.from(document.querySelectorAll("body *")).flatMap((el) => {
      const cs = getComputedStyle(el);
      const t = cs.transitionDuration.split(",").some((d) => parseFloat(d) > 0);
      const a = cs.animationName !== "none" && cs.animationDuration.split(",").some((d) => parseFloat(d) > 0);
      return t || a ? [`${el.tagName.toLowerCase()}.${String(el.className).slice(0, 40)}`] : [];
    }),
  );
  expect(moving).toEqual([]);
  await page.getByRole("button", { name: "Open confirm" }).click();
  const dialog = page.getByRole("dialog", { name: "Publish the schedule?" });
  await expect(dialog).toBeVisible();
  expect(await dialog.evaluate((el) => parseFloat(getComputedStyle(el).animationDuration))).toBe(0);
  expect(await page.evaluate(() => parseFloat(getComputedStyle(document.querySelector("dialog[open]")!, "::backdrop").animationDuration))).toBe(0);
});

test("changing width keeps the page, the scroll place and the focus (no remount)", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/explore");
  await page.waitForLoadState("networkidle");
  await page.evaluate(() => { (window as unknown as { __mark: number }).__mark = 1; window.scrollTo(0, 300); });
  const y = await page.evaluate(() => window.scrollY);
  for (const w of [1000, 700, 375, 1440]) {
    await page.setViewportSize({ width: w, height: 900 });
    await page.waitForTimeout(150);
    expect(await page.evaluate(() => (window as unknown as { __mark?: number }).__mark), `${w}: page not reloaded`).toBe(1);
    expect(page.url()).toMatch(/\/explore$/);
  }
  expect(Math.abs((await page.evaluate(() => window.scrollY)) - y)).toBeLessThan(400);
});
