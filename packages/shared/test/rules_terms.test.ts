import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { termsVersion } from "../src/agreements.js";

// firestore.rules and storage.rules can't import termsVersion, so each checks
// the CURRENT Terms version as a literal (`token.get('terms', 0) >= N`). A
// bump here must be matched in both files, or members who agreed to the new
// version are refused (or, if the rules lag the other way, an old agreement
// still writes). This fails until they agree.
const rules = (name: string) => readFileSync(join(__dirname, "../../../firebase", name), "utf8");
const literal = (src: string) => [...src.matchAll(/token\.get\('terms', 0\) >= (\d+)/g)].map((m) => Number(m[1]));

describe("the rules' Terms literal equals termsVersion", () => {
  it.each(["firestore.rules", "storage.rules"])("%s", (file) => {
    const found = literal(rules(file));
    expect(found.length).toBeGreaterThan(0);
    expect(found.every((n) => n === termsVersion)).toBe(true);
  });
});
