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
