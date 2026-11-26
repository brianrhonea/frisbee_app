import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";
import { open } from "./helpers";

// The shared components (Sprint 2 C1-C4) in every state, on the non-production
// gallery at /dev/ui: accessibility, hit areas, keyboard and 200% text. jsdom
// has no layout, so sizes are checked here.

// The gallery is a development and test route (a 404 in production builds), so
// against a deployed site (E2E_BASE_URL) only the source guard below runs.
test.beforeEach(({}, info) => {
  test.skip(!!process.env.E2E_BASE_URL && !info.title.startsWith("the gallery is not offered"), "the gallery is not served by production builds");
});
for (const theme of ["light", "dark"] as const) {
  test(`gallery has no axe violations (${theme})`, async ({ page }) => {
    await open(page, "/dev/ui", theme);
    const result = await new AxeBuilder({ page })
      .include("[data-showcase]")
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
      .analyze();
    expect(result.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(" ")).join(", ")}`)).toEqual([]);
  });
}

test("the gallery is not offered in production builds", async () => {
  // The route's own guard; asserted on the source so no production build is needed here.
  const { readFileSync } = await import("node:fs");
  const { join } = await import("node:path");
  const source = readFileSync(join(__dirname, "../../app/dev/ui/page.tsx"), "utf8");
  expect(source).toContain('process.env.NODE_ENV === "production"');
  expect(source).toContain("notFound()");
});

test("every button and icon button has a 48 px target", async ({ page }) => {
  await open(page, "/dev/ui");
  const controls = page.locator('[data-showcase="button"] :is(button, a)');
  const n = await controls.count();
  expect(n).toBeGreaterThan(10);
  for (let i = 0; i < n; i++) {
    const c = controls.nth(i);
    await c.evaluate((el) => el.scrollIntoView({ block: "center" }));
    const hit = await c.evaluate((el) => {
      const r = el.getBoundingClientRect();
      const cx = r.left + r.width / 2;
      const cy = r.top + r.height / 2;
      const at = (y: number) => {
        const t = document.elementFromPoint(cx, y);
        return !!t && el.contains(t);
      };
      // The points 23 px above and below the centre are inside the target.
      return { top: at(cy - 23), bottom: at(cy + 23), name: el.textContent || el.getAttribute("aria-label") };
    });
    expect(hit, `${hit.name}`).toMatchObject({ top: true, bottom: true });
  }
});

test("tabs and chips: arrows, Home and End work in the browser", async ({ page }) => {
  await open(page, "/dev/ui");
  const first = page.getByRole("tab", { name: "Chats" });
  await first.focus();
  await page.keyboard.press("ArrowRight");
  const requests = page.getByRole("tab", { name: "Requests (2)" });
  await expect(requests).toBeFocused();
  await expect(requests).toHaveAttribute("aria-selected", "true");
  await page.keyboard.press("ArrowRight"); // Archived
  await page.keyboard.press("ArrowRight"); // skips the disabled tab, wrapping to Chats
  await expect(first).toBeFocused();
  await page.keyboard.press("End");
  await expect(page.getByRole("tab", { name: "Archived" })).toHaveAttribute("aria-selected", "true");
  await page.keyboard.press("Home");
  await expect(first).toHaveAttribute("aria-selected", "true");

  const all = page.getByRole("radio", { name: "All" });
  await all.focus();
  await page.keyboard.press("ArrowRight");
  await expect(page.getByRole("radio", { name: "Games" })).toBeChecked();
});

test("tabs and chips: targets are 48 px tall", async ({ page }) => {
  await open(page, "/dev/ui");
  const boxes = await page.locator('[data-showcase="tabs"] [role="tab"], [data-showcase="chips"] button').evaluateAll((els) => els.map((e) => Math.round(e.getBoundingClientRect().height)));
  expect(boxes.length).toBeGreaterThan(15);
  for (const h of boxes) expect(h).toBeGreaterThanOrEqual(48);
});

test("tabs and chips hold up at a 320 px width and large text: they scroll, the page does not", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 700 });
  await open(page, "/dev/ui");
  // 200% text: the root size doubles for everything that is in rem/em and the bars still fit by scrolling.
  await page.addStyleTag({ content: ".ui-tabs, .ui-tabs button { font-size: 200% !important; }" });
  const page_overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(page_overflow).toBeLessThanOrEqual(0);
  const long = page.getByRole("tablist", { name: "Many tabs, scrolling" });
  const scrolls = await long.evaluate((el) => el.scrollWidth > el.clientWidth);
  expect(scrolls).toBe(true);
  // Every tab stays on one line.
  const lines = await long.locator("[role=tab] .ui-face").evaluateAll((els) => els.map((e) => e.getBoundingClientRect().height));
  for (const h of lines) expect(h).toBeLessThan(100);
  // A selected tab off to the right is scrolled into view by the keyboard.
  const last = page.getByRole("tab", { name: "Settings" });
  await page.getByRole("tab", { name: "Playbook" }).focus();
  await page.keyboard.press("End");
  await expect(last).toBeFocused();
  const inView = await last.evaluate((el) => {
    const r = el.getBoundingClientRect();
    return r.right <= window.innerWidth + 1;
  });
  expect(inView).toBe(true);
});

test("a loading button is busy and keeps focus", async ({ page }) => {
  await open(page, "/dev/ui");
  const saving = page.getByRole("button", { name: "Saving", exact: true }).first();
  await saving.focus();
  await expect(saving).toBeFocused();
  await expect(saving).toHaveAttribute("aria-busy", "true");
  expect(await saving.evaluate((el) => el.hasAttribute("disabled"))).toBe(false);
});

test("pages that use the new bars do not scroll sideways at phone width", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 700 });
  for (const path of ["/explore", "/learn", "/sign-in"]) {
    await open(page, path);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow, path).toBeLessThanOrEqual(0);
  }
});
