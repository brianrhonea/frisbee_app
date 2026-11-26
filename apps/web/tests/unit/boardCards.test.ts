// @vitest-environment node
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// K3 review fixes: --board is now a light card value, so a rule that fills with it
// and sets a transparent border has no edge on the page.
const here = dirname(fileURLToPath(import.meta.url));

function cssFiles(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? cssFiles(join(dir, e.name)) : e.name.endsWith(".css") ? [join(dir, e.name)] : [],
  );
}

const rules: { sel: string; body: string }[] = [];
for (const root of ["../../app", "../../components"])
  for (const file of cssFiles(resolve(here, root)))
    for (const m of readFileSync(file, "utf8").matchAll(/([^{}]+)\{([^{}]*)\}/g))
      rules.push({ sel: m[1].trim().replace(/^\/\*.*?\*\/\s*/s, ""), body: m[2] });

const fillsBoard = (body: string) => /background:\s*var\(--board\)/.test(body);

describe("board-filled cards keep an edge", () => {
  it("no rule combines a var(--board) background with a transparent border", () => {
    const bad = rules.filter((r) => fillsBoard(r.body) && /border(-color)?:[^;]*transparent/.test(r.body));
    expect(bad.map((r) => r.sel)).toEqual([]);
  });

  it("the card rules that fill with --board declare the line border", () => {
    for (const sel of [".st-scoreboard", ".tournament-day", ".hosted-board", ".explore-live", ".draft-banner"]) {
      const r = rules.find((x) => x.sel.endsWith(sel) && fillsBoard(x.body));
      expect(r, sel).toBeTruthy();
      expect(r!.body, sel).toMatch(/border(-color)?:[^;]*var\(--line\)/);
    }
  });

  it("organization badges use the soft accent, not the card colour", () => {
    for (const sel of [".ui-logo-organization", ".host-mark-organization"]) {
      const r = rules.find((x) => x.sel === sel)!;
      expect(r.body, sel).toContain("var(--accent-soft)");
      expect(r.body, sel).not.toContain("var(--board)");
    }
  });

  it("today markers use accent-soft with a 2px accent outline", () => {
    for (const sel of [".week-day.today b", ".team-hub .sched-list a.team-sched-row.today"]) {
      const r = rules.find((x) => x.sel === sel)!;
      expect(r, sel).toBeTruthy();
      expect(r.body, sel).toContain("background: var(--accent-soft)");
      expect(r.body, sel).toContain("color: var(--accent-ink)");
      expect(r.body, sel).toMatch(/box-shadow:\s*inset 0 0 0 2px var\(--accent\)/);
    }
  });
});
