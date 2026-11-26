// @vitest-environment node
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { contrast } from "./cssContrast";

// K8: fills the gaps left by designTokens.test.ts. Reads the shared fixture and
// site.css and fails when the two differ. Groups for tokens the stylesheet does
// not define yet (text, space, motion, --radius-pill: K6/K7 not built) are
// skipped with a reason and switch on by themselves once the variable exists.
const here = dirname(fileURLToPath(import.meta.url));
type Entry = { web: string | null; light: string; dark: string; retired?: unknown };
const fixture = JSON.parse(
  readFileSync(resolve(here, "../../../../packages/shared/fixtures/design_tokens/tokens.json"), "utf8"),
) as {
  color: Record<string, Entry>;
  webAliases: Record<string, string>;
  contrast: [string, string, number][];
  text: Record<string, { web: string; size: number; line: number; weight: number }>;
  space: Record<string, unknown>;
  radius: Record<string, unknown>;
  motion: { fast: number; base: number; sheet: number; easing: number[] } & Record<string, unknown>;
};
const css = readFileSync(resolve(here, "../../app/site.css"), "utf8");

function block(open: string): string {
  const start = css.indexOf(open);
  if (start < 0) throw new Error(`block not found: ${open}`);
  const body = css.indexOf("{", start) + 1;
  return css.slice(body, css.indexOf("}", body));
}
function vars(b: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const m of b.matchAll(/(--[\w-]+):\s*([^;]+);/g)) out[m[1]] = m[2].trim();
  return out;
}
const light = vars(block(":root {"));
const darkMedia = vars(block(':root:not([data-theme="light"])'));
const darkAttr = vars(block(':root[data-theme="dark"]'));
const blocks = { light, "dark (media query)": darkMedia, "dark ([data-theme=dark])": darkAttr } as const;
const dark = { light: "light", "dark (media query)": "dark", "dark ([data-theme=dark])": "dark" } as const;

const named = Object.entries(fixture.color).filter(([, c]) => c.web) as [string, Entry & { web: string }][];
const norm = (s: string) => s.toUpperCase();

describe("site.css colour tokens vs fixture (every block, every named entry, retired included)", () => {
  for (const [label, set] of Object.entries(blocks)) {
    it(`${label}: all ${named.length} web-named colours present with the fixture value`, () => {
      const problems: string[] = [];
      for (const [key, c] of named) {
        const want = c[dark[label as keyof typeof dark]];
        const got = set[c.web];
        if (got === undefined) problems.push(`${key}: ${c.web} missing`);
        else if (norm(got) !== norm(want)) problems.push(`${key}: ${c.web} is ${got}, fixture ${want}`);
      }
      expect(problems).toEqual([]);
    });
  }

  it("the dark media-query block really sits inside prefers-color-scheme: dark", () => {
    const at = css.indexOf(':root:not([data-theme="light"])');
    expect(css.slice(css.lastIndexOf("@media", at), at)).toContain("prefers-color-scheme: dark");
  });

  it("fixture web names are unique", () => {
    const names = named.map(([, c]) => c.web);
    expect(new Set(names).size).toBe(names.length);
  });

  it("no hex colour variable in site.css is missing from the fixture or webAliases", () => {
    const known = new Set([...named.map(([, c]) => c.web), ...Object.keys(fixture.webAliases)]);
    const extra = Object.entries(light)
      .filter(([k, v]) => /^#[0-9a-f]{6}$/i.test(v) && !known.has(k))
      .map(([k]) => k);
    expect(extra, "colour variables the fixture does not list").toEqual([]);
  });
});

describe("webAliases", () => {
  const webNames = new Set(named.map(([, c]) => c.web));
  for (const [alias, target] of Object.entries(fixture.webAliases)) {
    it(`${alias} -> ${target}`, () => {
      expect(webNames.has(target), `${target} must be a fixture web name`).toBe(true);
      expect(webNames.has(alias), `${alias} must not also be a real token`).toBe(false);
      for (const [label, set] of Object.entries(blocks)) expect(set[alias], label).toBe(`var(${target})`);
    });
  }
});

describe("contrast pairs from the fixture, computed from site.css", () => {
  for (const [label, set] of Object.entries(blocks)) {
    it(`${label}: every pair (${fixture.contrast.length}) meets its threshold`, () => {
      const problems: string[] = [];
      for (const [fg, bg, min] of fixture.contrast) {
        const f = fixture.color[fg]?.web, b = fixture.color[bg]?.web;
        if (!f || !b) {
          problems.push(`${fg}/${bg}: no web name (cannot test on web)`);
          continue;
        }
        const r = contrast(set[f], set[b]);
        if (r < min) problems.push(`${fg} on ${bg}: ${r.toFixed(2)} < ${min}`);
      }
      expect(problems).toEqual([]);
    });
  }
});

// ---- Scalar tokens (text, space, radius, motion) ----
const defined = (name: string) => light[name] !== undefined;
const px = (v: string | undefined) => (v === undefined ? NaN : parseFloat(v));
const ms = (v: string | undefined) => (v === undefined ? NaN : v.endsWith("ms") ? parseFloat(v) : parseFloat(v) * 1000);
const NOT_BUILT = "K6/K7 not built: site.css does not define this variable yet";
const run = (name: string) => (defined(name) ? it : it.skip);

describe("radius", () => {
  const web = (fixture.radius["$names"] as { web: Record<string, string> }).web;
  for (const [key, cssName] of Object.entries(web)) {
    const want = fixture.radius[key] as number;
    run(cssName)(`${cssName} = ${want}px (radius.${key}) ${defined(cssName) ? "" : NOT_BUILT}`, () => {
      expect(px(light[cssName])).toBe(want);
    });
  }
});

describe("space", () => {
  for (const [key, want] of Object.entries(fixture.space)) {
    if (key.startsWith("$")) continue;
    const cssName = `--space-${key}`;
    run(cssName)(`${cssName} = ${want}px ${defined(cssName) ? "" : NOT_BUILT}`, () => {
      expect(px(light[cssName])).toBe(want);
    });
  }
});

describe("text styles", () => {
  for (const [key, t] of Object.entries(fixture.text)) {
    run(t.web)(`${t.web} (${key}) defines ${t.size}px / ${t.line}px / ${t.weight} ${defined(t.web) ? "" : NOT_BUILT}`, () => {
      // Accept the shorthand `<weight> <size>/<line> family` or a bare size.
      const v = light[t.web];
      const m = /^(?:(\d{3})\s+)?(\d+(?:\.\d+)?)px(?:\s*\/\s*(\d+(?:\.\d+)?)px)?/.exec(v);
      expect(m, `unparsable value: ${v}`).not.toBeNull();
      expect(Number(m![2])).toBe(t.size);
      if (m![3]) expect(Number(m![3])).toBe(t.line);
      if (m![1]) expect(Number(m![1])).toBe(t.weight);
    });
  }
});

describe("motion", () => {
  for (const key of ["fast", "base", "sheet"] as const) {
    const cssName = `--dur-${key}`;
    run(cssName)(`${cssName} = ${fixture.motion[key]}ms ${defined(cssName) ? "" : NOT_BUILT}`, () => {
      expect(ms(light[cssName])).toBe(fixture.motion[key]);
    });
  }
  run("--ease")(`--ease = cubic-bezier(${fixture.motion.easing.join(", ")}) ${defined("--ease") ? "" : NOT_BUILT}`, () => {
    const nums = /cubic-bezier\(([^)]+)\)/.exec(light["--ease"])![1].split(",").map(Number);
    expect(nums).toEqual(fixture.motion.easing);
  });
});
