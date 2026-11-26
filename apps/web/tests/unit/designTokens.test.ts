// @vitest-environment node
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// K3: site.css must carry the approved design tokens. The fixture is the
// single list; this test fails if the CSS drifts from it.
const here = dirname(fileURLToPath(import.meta.url));
const fixture = JSON.parse(
  readFileSync(resolve(here, "../../../../packages/shared/fixtures/design_tokens/tokens.json"), "utf8"),
) as {
  color: Record<string, { web: string | null; light: string; dark: string }>;
  webAliases: Record<string, string>;
  contrast: [string, string, number][];
};
const css = readFileSync(resolve(here, "../../app/site.css"), "utf8");

// Body of the block that starts at `open` (text up to its closing brace).
function blockAfter(open: string): string {
  const start = css.indexOf(open);
  if (start < 0) throw new Error(`block not found: ${open}`);
  const body = css.indexOf("{", start) + 1;
  return css.slice(body, css.indexOf("}", body));
}
function vars(block: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const m of block.matchAll(/(--[\w-]+):\s*([^;]+);/g)) out[m[1]] = m[2].trim();
  return out;
}

const light = vars(blockAfter(":root {"));
const darkMedia = vars(blockAfter(':root:not([data-theme="light"])'));
const darkAttr = vars(blockAfter(':root[data-theme="dark"]'));

const withWeb = Object.entries(fixture.color).filter(([, c]) => c.web);

describe("design tokens in site.css", () => {
  it("light :root holds the fixture light values", () => {
    for (const [, c] of withWeb) expect(light[c.web!], c.web!).toBe(c.light);
  });

  it("both dark blocks hold the fixture dark values", () => {
    for (const [, c] of withWeb) {
      expect(darkMedia[c.web!], `media ${c.web}`).toBe(c.dark);
      expect(darkAttr[c.web!], `attr ${c.web}`).toBe(c.dark);
    }
  });

  it("the two dark blocks define identical variables", () => {
    expect(darkMedia).toEqual(darkAttr);
  });

  it("aliases point where the fixture says", () => {
    for (const [alias, target] of Object.entries(fixture.webAliases)) {
      for (const set of [light, darkMedia, darkAttr]) expect(set[alias], alias).toBe(`var(${target})`);
    }
  });

  it("media variables (dark call/video surfaces) are the same in all blocks and readable", () => {
    const media = { "--media": "#18181B", "--media-2": "#27272A", "--on-media": "#FAFAFA", "--on-media-muted": "#A1A1AA" };
    for (const set of [light, darkMedia, darkAttr]) expect(set).toMatchObject(media);
    const lum = (hex: string) => {
      const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
      return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    };
    const ratio = (a: string, b: string) => (Math.max(lum(a), lum(b)) + 0.05) / (Math.min(lum(a), lum(b)) + 0.05);
    for (const fg of ["--on-media", "--on-media-muted"]) {
      for (const bg of ["--media", "--media-2"]) expect(ratio(light[fg], light[bg]), `${fg} on ${bg}`).toBeGreaterThanOrEqual(4.5);
    }
  });

  it("every fixture contrast pair meets its ratio in both themes", () => {
    const lum = (hex: string) => {
      const [r, g, b] = [1, 3, 5]
        .map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
        .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    };
    const ratio = (a: string, b: string) => {
      const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
      return (hi + 0.05) / (lo + 0.05);
    };
    const webName = (key: string) => {
      const name = fixture.color[key]?.web;
      if (!name) throw new Error(`no web name for ${key}`);
      return name;
    };
    for (const [fg, bg, min] of fixture.contrast) {
      // Pairs that use an app-only token (none today) are skipped by the throw above.
      for (const [theme, set] of [["light", light], ["dark", darkMedia]] as const) {
        const r = ratio(set[webName(fg)], set[webName(bg)]);
        expect(r, `${fg} on ${bg} (${theme})`).toBeGreaterThanOrEqual(min);
      }
    }
  });
});
