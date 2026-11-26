// @vitest-environment node
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { contrast, resolveColor, themes, webRoot, type Theme } from "./cssContrast";

// K5-D: the sidebar's per-team tile colours are a decorative palette, but the
// initials on each must stay readable. .team-tile (app.css) paints the fill as
// 15% tint over the card and the initials as 75% tint over the ink.
const source = readFileSync(join(webRoot, "components/SideTeams.tsx"), "utf8");
const tints = [...(/const tints = \[([^\]]+)\]/.exec(source)?.[1] ?? "").matchAll(/"([^"]+)"/g)].map((m) => m[1]);

const hex = (c: number[]) => "#" + c.map((v) => v.toString(16).padStart(2, "0")).join("");
const rgb = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const mix = (a: number[], b: number[], p: number) => a.map((v, i) => Math.round(v * p + b[i] * (1 - p)));

describe("sidebar team tints", () => {
  it("has six tints and none is the retired --team / --personal literal", () => {
    expect(tints).toHaveLength(6);
    expect(tints.map((t) => t.toLowerCase())).not.toContain("#2c6fb7");
    expect(tints.map((t) => t.toLowerCase())).not.toContain("#a8407a");
    expect(tints).toContain("var(--team)");
    expect(tints).toContain("var(--personal)");
  });

  it.each(["light", "dark"] as Theme[])("initials pass 4.5:1 on every tint in %s", (theme) => {
    const card = rgb(resolveColor("var(--card)", theme)!);
    const ink = rgb(resolveColor("var(--ink)", theme)!);
    for (const t of tints) {
      const base = rgb(resolveColor(t, theme)!);
      const ratio = contrast(hex(mix(base, ink, 0.75)), hex(mix(base, card, 0.15)));
      expect(ratio, `${t} in ${theme}`).toBeGreaterThanOrEqual(4.5);
    }
  });

  it("the tile rule still mixes 15% / 75% (the maths above matches the CSS)", () => {
    const css = readFileSync(join(webRoot, "app/app.css"), "utf8");
    expect(css).toContain("color-mix(in srgb, var(--tint, var(--accent)) 15%, var(--card))");
    expect(css).toContain("color-mix(in srgb, var(--tint, var(--accent)) 75%, var(--ink))");
    expect(themes.light["--team"]).toBeDefined();
  });
});
