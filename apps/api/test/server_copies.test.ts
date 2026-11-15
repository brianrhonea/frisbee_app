// The API keeps copies of two firebase/functions files while both serve
// clients: browse/model.ts (the `browse` callables) and discord/template.ts
// (discord-previewTemplate). firebase/functions is a standalone npm
// project that `firebase deploy` uploads on its own, so it can't import
// @stall10/shared; this test keeps the copies identical instead. Change
// both together.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const root = join(import.meta.dirname, "../../..");
const read = (path: string) => readFileSync(join(root, path), "utf8").replace(/\r\n/g, "\n");

/** [text] from the line starting with [from] up to (not including) the line starting with [to], or to the end. */
function section(text: string, from: string, to?: string): string {
  const start = text.indexOf(`\n${from}`);
  expect(start, `missing "${from}"`).toBeGreaterThanOrEqual(0);
  const end = to === undefined ? text.length : text.indexOf(`\n${to}`, start + 1);
  expect(end, `missing "${to}"`).toBeGreaterThan(start);
  return text.slice(start, end);
}

describe("server copies stay in step with firebase/functions", () => {
  it("browse/model.ts is the functions' file below its header", () => {
    const api = read("apps/api/src/browse/model.ts");
    const functions = read("firebase/functions/src/browse/model.ts");
    const header = api.indexOf("\n\n");
    expect(api.slice(0, header)).toMatch(/^\/\/ Copied from firebase\/functions\/src\/browse\/model\.ts/);
    expect(api.slice(header + 2)).toBe(functions);
  });

  it("discord/template.ts has the same logic (the plan's types come from @stall10/shared in the API)", () => {
    const api = read("apps/api/src/discord/template.ts");
    const functions = read("firebase/functions/src/discord/template.ts");
    const perms = "/** Discord permission bits the import looks at. */";
    const limits = "/** Limits from the app and firestore.rules. */";
    expect(section(api, perms, "// The plan's shapes are shared")).toBe(section(functions, perms, "/** The app's permission names"));
    expect(section(api, limits)).toBe(section(functions, limits));
    expect(section(api, "// Pure Discord server template logic", "import type")).toBe(section(`\n${functions}`, "// Pure Discord server template logic", perms));
  });
});
