// @vitest-environment node
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { contrast, resolveColor, type Theme, webRoot } from "./cssContrast";

// C4 (replaces the K5-D check on the sidebar's hashed team tints, which are
// gone): a team is drawn by its kind in token colours, never one colour per
// team. The initials on each kind must stay readable in light and dark.
const read = (p: string) => readFileSync(join(webRoot, p), "utf8");
const hex = (c: number[]) => "#" + c.map((v) => Math.round(v).toString(16).padStart(2, "0")).join("");
const rgb = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const mix = (a: number[], b: number[], p: number) => a.map((v, i) => v * p + b[i]! * (1 - p));
const themes: Theme[] = ["light", "dark"];
const c = (v: string, t: Theme) => resolveColor(v, t)!;

describe("TeamLogo tones (C4)", () => {
  it.each(themes)("team: light initials on the team tone pass 4.5:1 in %s", (theme) => {
    // Light: the team blue as is. Dark: 50% team over the board colour (the CSS above).
    const bg = theme === "light" ? c("var(--team)", theme) : hex(mix(rgb(c("var(--team)", theme)), rgb(c("var(--board)", theme)), 0.5));
    expect(contrast(c("var(--on-media)", theme), bg)).toBeGreaterThanOrEqual(4.5);
  });

  it.each(themes)("community: on-accent on accent passes 4.5:1 in %s", (theme) => {
    expect(contrast(c("var(--on-accent)", theme), c("var(--accent)", theme))).toBeGreaterThanOrEqual(4.5);
  });

  it.each(themes)("organization: accent-ink on accent-soft passes 4.5:1 in %s", (theme) => {
    expect(contrast(c("var(--accent-ink)", theme), c("var(--accent-soft)", theme))).toBeGreaterThanOrEqual(4.5);
  });

  it.each(themes)("people: accent-ink on accent-soft (the avatar) and the +N chip pass 4.5:1 in %s", (theme) => {
    expect(contrast(c("var(--accent-ink)", theme), c("var(--accent-soft)", theme))).toBeGreaterThanOrEqual(4.5);
    expect(contrast(c("var(--ink-soft)", theme), c("var(--field)", theme))).toBeGreaterThanOrEqual(4.5);
  });

  it("the CSS still draws the team tone the way the maths above does", () => {
    const css = read("components/ui/ui.css");
    expect(css).toContain(".ui-logo-team { background: var(--team); color: var(--on-media); }");
    expect(css).toContain('.ui-logo-team { background: color-mix(in srgb, var(--team) 50%, var(--board)); }');
  });
});

describe("no per-team tints", () => {
  it("the sidebar and the strip colour by kind, not by a hash of the team's id", () => {
    for (const file of ["components/SideTeams.tsx", "components/home/TeamStrip.tsx"]) {
      const source = read(file);
      expect(source, file).not.toMatch(/--tint|tint\(|#[0-9a-fA-F]{6}/);
      expect(source, file).toContain("TeamLogo");
    }
    expect(read("app/app.css")).not.toContain("var(--tint");
  });
});
