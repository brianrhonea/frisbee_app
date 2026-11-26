// @vitest-environment node
import { describe, expect, it } from "vitest";
import { allRules, contrast, decl, resolveColor, type Theme } from "./cssContrast";

const rules = allRules();
const themeNames: Theme[] = ["light", "dark"];

// Selected / pressed / current state of a control.
const selectedState = /\.(on|active|chosen|mine|selected)\b|\[aria-pressed="true"\]|\[aria-current="page"\]/;
const softFill = /^var\(--accent-soft\)$/;
const hasAccentOutline = (decls: string) =>
  /box-shadow:[^;]*(?:inset\s+0\s+0\s+0\s+(?:[2-9]|1\.[5-9])px|inset\s+3px\s+0\s+0|inset\s+0\s+-3px\s+0)[^;]*var\(--accent\)/.test(decls) ||
  /(?:^|;)\s*(?:border|outline)(?:-color)?:[^;]*var\(--accent\)/.test(decls);

// Selected rules that are not marked by the fill alone: they carry another
// non-colour cue (an indicator bar, a changed icon/text weight) in the same
// component, so the fill is not the only signal.
const otherCue = [
  /\.nav-item\.active$/, // sidebar item: the accent bar beside it (.nav-item.active::before)
  /\.post-action\.on$/, // like/comment toggle: the count and icon change, the label is the accent colour
];

describe("selected state is not marked by the soft fill alone (K5-B)", () => {
  const selectedSoft = rules.filter((r) => {
    const bg = decl(r.decls, "background") ?? decl(r.decls, "background-color");
    return bg !== null && softFill.test(bg) && r.selector.split(",").some((s) => selectedState.test(s));
  });

  it("finds the selected soft-fill rules", () => {
    expect(selectedSoft.length).toBeGreaterThan(15);
  });

  it.each(selectedSoft.map((r) => [`${r.file}: ${r.selector}`, r] as const))("%s has an accent outline", (_n, r) => {
    const exempt = r.selector.split(",").every((s) => otherCue.some((o) => o.test(s.trim())));
    if (!exempt) expect(hasAccentOutline(r.decls), r.decls).toBe(true);
  });

  it("the segmented control's selected segment carries an accent outline", () => {
    const seg = rules.filter((r) => /^\.segmented (button|a)\.on$/.test(r.selector));
    expect(seg.length).toBe(2);
    for (const r of seg) expect(hasAccentOutline(r.decls), r.decls).toBe(true);
  });

  it("the accent outline is at least 3:1 against the card in both themes", () => {
    for (const theme of themeNames) {
      expect(contrast(resolveColor("var(--accent)", theme)!, resolveColor("var(--card)", theme)!)).toBeGreaterThanOrEqual(3);
    }
  });
});

describe("green means success only (K5-A)", () => {
  const accentOnDone = rules.filter((r) =>
    r.selector
      .split(",")
      .some((s) => /(\.form-ok|\.rsvp-pill\.going|\.rsvp-mine\.going|\.rsvp-group\.going|\.video-status\.ok|\.username-input\.ok|\.spots-left|\.hosted-champion|\.gt-champion|\.st-win|\.st-pos|\.hosted-plus|li\.done)/.test(s)),
  );
  it("done, going, ok, champion and positive-number rules use the success tokens, not the accent", () => {
    expect(accentOnDone.length).toBeGreaterThan(10);
    for (const r of accentOnDone) {
      expect(/var\(--(accent|accent-soft|accent-ink|glow)\)/.test(r.decls), `${r.file}: ${r.selector}`).toBe(false);
    }
  });
});

describe("tone pills: tinted fill with coloured text pass 4.5:1 (K5-C)", () => {
  // Every rule that sets a fill and a text colour from theme variables.
  const pairs = rules
    .map((r) => ({ r, bg: decl(r.decls, "background") ?? decl(r.decls, "background-color"), fg: decl(r.decls, "color") }))
    .filter((p) => p.bg && p.fg && /^var\(--[\w-]+\)$/.test(p.bg) && /^var\(--[\w-]+\)$/.test(p.fg));
  const tones = pairs.filter((p) => /-soft\)$/.test(p.bg!) || /^var\(--(disc|live|error|success|accent)\)$/.test(p.bg!));

  it("finds the tone pill rules", () => {
    expect(tones.length).toBeGreaterThan(30);
  });

  it.each(tones.map((p) => [`${p.r.file}: ${p.r.selector} (${p.fg} on ${p.bg})`, p] as const))("%s", (_n, p) => {
    for (const theme of themeNames) {
      const fg = resolveColor(p.fg!, theme);
      const bg = resolveColor(p.bg!, theme);
      if (!fg || !bg) continue;
      expect(contrast(fg, bg), `${theme}: ${fg} on ${bg}`).toBeGreaterThanOrEqual(4.5);
    }
  });
});
