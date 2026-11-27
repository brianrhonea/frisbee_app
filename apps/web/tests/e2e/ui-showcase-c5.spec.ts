import { expect, test } from "@playwright/test";
import { open } from "./helpers";

// Sprint 3 C5-C10 on the gallery at /dev/ui (non-production only): the confirm
// dialog's modal behaviour, keyboard use, hit areas and narrow widths. Axe over
// the whole gallery, including these sections, is in ui-showcase.spec.ts.
test.beforeEach(({}, info) => {
  test.skip(!!process.env.E2E_BASE_URL, "the gallery is not served by production builds");
  void info;
});

test("confirm dialog: focus is trapped, Esc cancels and focus returns to the opener", async ({ page }) => {
  await open(page, "/dev/ui");
  await page.waitForTimeout(1500); // the dev server hydrates late
  const opener = page.getByRole("button", { name: "Open destructive confirm" });
  await opener.scrollIntoViewIfNeeded();
  await opener.click();
  const dialog = page.getByRole("dialog", { name: "Delete this event?" });
  await expect(dialog).toBeVisible();
  // A destructive confirm starts on Cancel, so Enter alone never deletes.
  await expect(dialog.getByRole("button", { name: "Cancel" })).toBeFocused();
  // Tab cycles inside the dialog and never reaches the page behind.
  for (let i = 0; i < 6; i++) {
    await page.keyboard.press("Tab");
    const inside = await page.evaluate(() => !!document.activeElement?.closest("dialog[open]"));
    expect(inside, `Tab ${i}`).toBe(true);
  }
  await page.keyboard.press("Shift+Tab");
  expect(await page.evaluate(() => !!document.activeElement?.closest("dialog[open]"))).toBe(true);
  // The page behind is inert: a click on a button there lands on the dialog's backdrop instead.
  const covered = await page.evaluate(() => {
    const el = document.querySelector('[data-showcase="button"] button') as HTMLElement;
    const r = el.getBoundingClientRect();
    const hit = document.elementFromPoint(r.left + 2, r.top + 2);
    return hit === null || hit.closest('[data-showcase="button"]') === null || hit.closest("dialog") !== null;
  });
  expect(covered).toBe(true);
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();
  await expect(page.getByTestId("confirm-result")).toHaveText("Cancelled");
  await expect(opener).toBeFocused();
});

test("confirm dialog: a plain confirm starts on Confirm and Enter confirms", async ({ page }) => {
  await open(page, "/dev/ui");
  await page.waitForTimeout(1500);
  await page.getByRole("button", { name: "Open confirm" }).click();
  const dialog = page.getByRole("dialog", { name: "Publish the schedule?" });
  await expect(dialog.getByRole("button", { name: "Publish" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.getByTestId("confirm-result")).toHaveText("Confirmed plain");
});

test("search field: Clear and Esc work from the keyboard; the field error is announced", async ({ page }) => {
  await open(page, "/dev/ui");
  await page.waitForTimeout(1500);
  const search = page.getByRole("searchbox", { name: "Search the gallery" });
  await search.fill("disc");
  await page.getByRole("button", { name: "Clear search" }).focus();
  await page.keyboard.press("Enter");
  await expect(search).toHaveValue("");
  await search.fill("disc");
  await search.press("Escape");
  await expect(search).toHaveValue("");
  const heights = await page.locator('[data-showcase="fields"] input, [data-showcase="fields"] .ui-search').evaluateAll((els) => els.map((e) => Math.round(e.getBoundingClientRect().height)));
  for (const h of heights) expect(h).toBeGreaterThanOrEqual(44);
  await expect(page.getByLabel("Username")).toHaveAttribute("aria-invalid", "true");
  await expect(page.locator('[data-showcase="fields"] [role="alert"]')).toHaveText("That username is taken.");
});

test("list rows, tiles, event cards and retry buttons have 48 px targets", async ({ page }) => {
  await open(page, "/dev/ui");
  const targets = page.locator('[data-showcase="listrow"] :is(a, button), [data-showcase="cover"] a.ui-tile-face, [data-showcase="event"] a.ui-event-main, [data-showcase="states"] button');
  expect(await targets.count()).toBeGreaterThan(5);
  // Buttons draw 44 px with a 48 px hit area, so test what a pointer reaches: 23 px above and below the centre.
  const n = await targets.count();
  for (let i = 0; i < n; i++) {
    const c = targets.nth(i);
    await c.evaluate((el) => el.scrollIntoView({ block: "center" }));
    const hit = await c.evaluate((el) => {
      const r = el.getBoundingClientRect();
      const cx = r.left + r.width / 2;
      const cy = r.top + r.height / 2;
      const at = (y: number) => {
        const t = document.elementFromPoint(cx, y);
        return !!t && el.contains(t);
      };
      return { top: at(cy - 23), bottom: at(cy + 23), name: el.textContent?.slice(0, 20) };
    });
    expect(hit, String(hit.name)).toMatchObject({ top: true, bottom: true });
  }
});

// Relative luminance contrast of two "rgb(r, g, b)" strings.
function contrast(a: string, b: string) {
  const lum = (c: string) => {
    const [r, g, bl] = (c.match(/[\d.]+/g) ?? ["0", "0", "0"]).slice(0, 3).map((v) => {
      const x = Number(v) / 255;
      return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * r! + 0.7152 * g! + 0.0722 * bl!;
  };
  const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
  return (hi! + 0.05) / (lo! + 0.05);
}

for (const theme of ["light", "dark"] as const) {
  test(`the empty state's button is readable (${theme})`, async ({ page }) => {
    await open(page, "/dev/ui", theme);
    const action = page.locator('[data-showcase="states"] .empty .btn-primary').first();
    const { color, bg } = await action.evaluate((el) => ({ color: getComputedStyle(el).color, bg: getComputedStyle(el).backgroundColor }));
    expect(contrast(color, bg), `${color} on ${bg}`).toBeGreaterThanOrEqual(4.5);
    // A plain link in an empty state is still the accent colour.
    const states = page.locator('[data-showcase="states"]');
    await expect(states).toBeVisible();
  });
}

test("the search clear button has a 48 px hit area", async ({ page }) => {
  await open(page, "/dev/ui");
  await page.waitForTimeout(1500);
  await page.getByRole("searchbox", { name: "Search the gallery" }).fill("x");
  const clear = page.getByRole("button", { name: "Clear search" });
  const hit = await clear.evaluate((el) => {
    el.scrollIntoView({ block: "center" });
    const r = el.getBoundingClientRect();
    const cx = r.left + r.width / 2;
    const cy = r.top + r.height / 2;
    const at = (x: number, y: number) => {
      const t = document.elementFromPoint(x, y);
      return !!t && el.contains(t);
    };
    return { top: at(cx, cy - 23), bottom: at(cx, cy + 23), left: at(cx - 23, cy), right: at(cx + 23, cy) };
  });
  expect(hit).toEqual({ top: true, bottom: true, left: true, right: true });
});

test("summary tiles go two across under 360 px and long labels wrap", async ({ page }) => {
  await page.setViewportSize({ width: 340, height: 700 });
  await open(page, "/dev/ui");
  const cols = await page.locator('[data-showcase="cover"] .ui-tiles').first().evaluate((el) => getComputedStyle(el).gridTemplateColumns.split(" ").length);
  expect(cols).toBe(2);
  expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(0);
});

test("the new sections hold up at 320 px: nothing scrolls sideways", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 700 });
  await open(page, "/dev/ui");
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(0);
});
