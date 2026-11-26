import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";
import { open } from "./helpers";

// The shared components (Sprint 2 C1-C4) in every state, on the non-production
// gallery at /dev/ui: accessibility, hit areas, keyboard and 200% text. jsdom
// has no layout, so sizes are checked here.
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

test("a loading button is busy and keeps focus", async ({ page }) => {
  await open(page, "/dev/ui");
  const saving = page.getByRole("button", { name: "Saving", exact: true }).first();
  await saving.focus();
  await expect(saving).toBeFocused();
  await expect(saving).toHaveAttribute("aria-busy", "true");
  expect(await saving.evaluate((el) => el.hasAttribute("disabled"))).toBe(false);
});
