// Shared helpers for the CSS tests: read the website's stylesheets, resolve the
// theme variables in site.css and compute WCAG contrast. No dependencies.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
export const webRoot = resolve(here, "../..");

export interface Rule {
  file: string;
  selector: string;
  decls: string;
}

function cssFiles(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    if (name === "node_modules" || name === ".next") continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) cssFiles(p, out);
    else if (name.endsWith(".css")) out.push(p);
  }
  return out;
}

/** Every rule (selector list + declarations) in app/ and components/, media queries flattened. */
export function allRules(): Rule[] {
  const rules: Rule[] = [];
  for (const dir of ["app", "components"]) {
    for (const file of cssFiles(join(webRoot, dir))) {
      const text = readFileSync(file, "utf8").replace(/\/\*[\s\S]*?\*\//g, "");
      for (const m of text.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
        rules.push({ file: file.slice(webRoot.length + 1).replace(/\\/g, "/"), selector: m[1].trim(), decls: m[2].trim() });
      }
    }
  }
  return rules;
}

const siteCss = readFileSync(join(webRoot, "app/site.css"), "utf8");
function blockAfter(open: string): string {
  const start = siteCss.indexOf(open);
  if (start < 0) throw new Error(`block not found: ${open}`);
  const body = siteCss.indexOf("{", start) + 1;
  return siteCss.slice(body, siteCss.indexOf("}", body));
}
function vars(block: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const m of block.matchAll(/(--[\w-]+):\s*([^;]+);/g)) out[m[1]] = m[2].trim();
  return out;
}

export type Theme = "light" | "dark";
const lightVars = vars(blockAfter(":root {"));
const darkVars = { ...lightVars, ...vars(blockAfter(':root[data-theme="dark"]')) };
export const themes: Record<Theme, Record<string, string>> = { light: lightVars, dark: darkVars };

/** A `var(--x)` or `#hex` value to a hex colour for a theme, following alias chains. */
export function resolveColor(value: string, theme: Theme): string | null {
  let v = value.trim();
  for (let i = 0; i < 6; i++) {
    if (/^#[0-9a-f]{6}$/i.test(v)) return v;
    const m = /^var\((--[\w-]+)\)$/.exec(v);
    if (!m) return null;
    const next = themes[theme][m[1]];
    if (!next) return null;
    v = next;
  }
  return null;
}

function channel(c: number): number {
  const s = c / 255;
  return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
}
export function luminance(hex: string): number {
  const n = parseInt(hex.slice(1), 16);
  return 0.2126 * channel((n >> 16) & 255) + 0.7152 * channel((n >> 8) & 255) + 0.0722 * channel(n & 255);
}
export function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

/** The value of one declaration in a rule body, or null. */
export function decl(decls: string, prop: string): string | null {
  const m = new RegExp(`(?:^|;)\\s*${prop}\\s*:\\s*([^;]+)`).exec(decls);
  return m ? m[1].trim() : null;
}
