import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

// A static check of the two rules files against the account gate
// (docs/specifications/contracts/account-gate.md, section 4): every client
// write allow (create, update, delete or write) is led by accountOk(),
// readOrAccountOk() or ageOk(), is `if false`, or is on the explicit list of
// paths a new account may write. A new unguarded write rule fails here until
// someone decides, in this file, that it is meant to be open.
// Also: both files check the CURRENT Terms version (packages/shared
// termsVersion) as a literal, and every Storage upload refuses the API's
// `stall10Checked` mark.

const root = join(__dirname, "../../..");
const firestoreRules = readFileSync(join(root, "firestore.rules"), "utf8");
const storageRules = readFileSync(join(root, "storage.rules"), "utf8");
const sharedTerms = Number(/export const termsVersion = (\d+);/.exec(readFileSync(join(root, "../packages/shared/src/agreements.ts"), "utf8"))?.[1]);

/** Removes // comments that are not inside a quoted string. */
function stripComments(src: string): string {
  return src
    .split("\n")
    .map((line) => {
      let quote = "";
      for (let i = 0; i < line.length; i++) {
        const c = line[i]!;
        if (quote) {
          if (c === "\\") i++;
          else if (c === quote) quote = "";
        } else if (c === "'" || c === '"') quote = c;
        else if (c === "/" && line[i + 1] === "/") return line.slice(0, i);
      }
      return line;
    })
    .join("\n");
}

interface Allow {
  path: string;
  methods: string[];
  condition: string;
}

/** Every `allow` with the match path it sits under, tracked by brace depth. */
function allows(src: string): Allow[] {
  const text = stripComments(src);
  const out: Allow[] = [];
  const stack: Array<{ depth: number; seg: string }> = [];
  let depth = 0;
  let i = 0;
  let quote = "";
  while (i < text.length) {
    const c = text[i]!;
    if (quote) {
      if (c === "\\") i++;
      else if (c === quote) quote = "";
      i++;
      continue;
    }
    if (c === "'" || c === '"') {
      quote = c;
      i++;
      continue;
    }
    const open = /^match\s+(\/[^\s{]*(?:\{[^}]*\}[^\s{]*)*)\s*\{/.exec(text.slice(i, i + 300));
    if (open && /\s/.test(text[i - 1] ?? " ")) {
      depth++;
      stack.push({ depth, seg: open[1]! });
      i += open[0].length;
      continue;
    }
    if (c === "{") {
      depth++;
      i++;
      continue;
    }
    if (c === "}") {
      if (stack.length && stack[stack.length - 1]!.depth === depth) stack.pop();
      depth--;
      i++;
      continue;
    }
    const m = /^allow\s+([a-z, \n]+?)\s*(?::\s*if\s+|;)/.exec(text.slice(i, i + 200));
    if (m && /\s/.test(text[i - 1] ?? " ")) {
      // The condition runs to the next ; outside quotes.
      let j = i + m[0].length;
      let q = "";
      const begin = j;
      for (; j < text.length; j++) {
        const ch = text[j]!;
        if (q) {
          if (ch === "\\") j++;
          else if (ch === q) q = "";
        } else if (ch === "'" || ch === '"') q = ch;
        else if (ch === ";") break;
      }
      out.push({
        path: stack.map((s) => s.seg).join(""),
        methods: m[1]!.split(",").map((x) => x.trim()),
        condition: m[0].endsWith(";") ? "true" : text.slice(begin, j).replace(/\s+/g, " ").trim(),
      });
      i = j;
      continue;
    }
    i++;
  }
  return out;
}

const writeMethods = new Set(["create", "update", "delete", "write"]);
const writesOf = (src: string) => allows(src).filter((a) => a.methods.some((m) => writeMethods.has(m)));
const gated = /^(accountOk|readOrAccountOk|ageOk)\(\)\s*(&&|$)/;
const keyOf = (a: Allow) => `${a.path.replace("/databases/{database}/documents", "").replace("/b/{bucket}/o", "")} ${a.methods.join(",")}`;

/**
 * Write rules that are deliberately not led by the account check, each with
 * why. Key: "<match path> <methods>".
 */
const openFirestore: Record<string, string> = {
  "/users/{userId} read,delete": "own users doc: reads, and removing it with the account",
  "/users/{userId} create,update": "own users doc: sign-in details and onboarding; only the allow-listed fields",
  "/users/{userId}/dmReads/{convId} read,delete": "own read markers",
  "/users/{userId}/dmReads/{convId} create,update": "own read markers",
  "/users/{userId}/chatReads/{teamId} read,delete": "own read markers",
  "/users/{userId}/chatReads/{teamId} create,update": "own read markers",
  "/users/{userId}/settings/notifications read,delete": "own notification settings",
  "/users/{userId}/settings/notifications create,update": "own notification settings",
  "/users/{userId}/devices/{fid} read,delete": "push registration",
  "/users/{userId}/devices/{fid} create,update": "push registration",
  "/users/{userId}/notifications/{id} read,delete": "own notification inbox",
  "/users/{userId}/notifications/{id} update": "marking own notifications read",
  "/profiles/{userId} delete": "removing one's own profile stays open (leaving, account deletion)",
  "/profiles/{userId}/private/{doc} delete": "removing one's own private profile details stays open",
};
/**
 * Write rules that may be gated by `ageOk()` alone (the adult check, not the
 * email or Terms), each with why (N6). Anything else led by `ageOk()` is a
 * mistake: it would let an account with a pending email or Terms write.
 * Key: "<match path> <methods>".
 */
const ageOnlyFirestore: Record<string, string> = {
  "/profiles/{userId} create": "the profile card: an adult may publish it before the email or Terms are done (F1)",
  "/profiles/{userId} update": "the profile card (F1)",
  "/profiles/{userId}/private/{doc} create,update": "private profile details (F1)",
  "/usernames/{name} create": "claiming a username (F1)",
};
const ageOnlyStorage: Record<string, string> = {
  "/users/{userId}/profile/{fileName} create,update": "profile pictures, part of the adult-checked profile (F1)",
};
const openStorage: Record<string, string> = {
  "/users/{userId}/profile/{fileName} delete": "removing one's own profile picture stays open",
};

describe("the rules parser", () => {
  it("finds allows under nested matches and ignores comments", () => {
    const found = allows(`
      service x { match /a/{x} {
        // allow write: if true;
        allow create, update: if accountOk() && foo('//');
        match /b/{y} { allow delete: if false; }
      } }`);
    expect(found).toEqual([
      { path: "/a/{x}", methods: ["create", "update"], condition: "accountOk() && foo('//')" },
      { path: "/a/{x}/b/{y}", methods: ["delete"], condition: "false" },
    ]);
  });
});

function check(name: string, src: string, open: Record<string, string>, ageOnly: Record<string, string>) {
  describe(`${name}: every write is gated`, () => {
    const writes = writesOf(src);
    it("finds the write rules", () => {
      expect(writes.length).toBeGreaterThan(5);
    });
    it("each is accountOk()/readOrAccountOk()/ageOk()-led, `if false`, or on the open list", () => {
      const bad = writes
        .filter((a) => !gated.test(a.condition) && a.condition !== "false")
        .map(keyOf)
        .filter((k) => !(k in open));
      expect(bad).toEqual([]);
    });
    it("only the age-only list's rules are gated by ageOk() alone (N6)", () => {
      const bad = writes
        .filter((a) => /^ageOk\(\)\s*(&&|$)/.test(a.condition))
        .map(keyOf)
        .filter((k) => !(k in ageOnly));
      expect(bad).toEqual([]);
    });
    it("the age-only list has no stale entries", () => {
      const keys = new Set(writes.filter((a) => /^ageOk\(\)\s*(&&|$)/.test(a.condition)).map(keyOf));
      expect(Object.keys(ageOnly).filter((k) => !keys.has(k))).toEqual([]);
    });
    it("the open list has no stale entries", () => {
      const keys = new Set(writes.map(keyOf));
      expect(Object.keys(open).filter((k) => !keys.has(k))).toEqual([]);
    });
  });
}
check("firestore.rules", firestoreRules, openFirestore, ageOnlyFirestore);
check("storage.rules", storageRules, openStorage, ageOnlyStorage);

describe("the current Terms version", () => {
  const literal = (src: string) => Number(/token\.get\('terms', 0\) >= (\d+)/.exec(src)?.[1]);
  it("packages/shared termsVersion is a number", () => expect(sharedTerms).toBeGreaterThanOrEqual(1));
  it("firestore.rules checks it as a literal", () => expect(literal(firestoreRules)).toBe(sharedTerms));
  it("storage.rules checks it as a literal", () => expect(literal(storageRules)).toBe(sharedTerms));
});

describe("storage.rules: the API's screening mark", () => {
  const uploads = writesOf(storageRules).filter((a) => a.methods.includes("create") || a.methods.includes("update") || a.methods.includes("write"));
  it("finds the upload rules", () => expect(uploads.length).toBe(6));
  it.each(uploads.map((a) => [keyOf(a), a] as const))("%s refuses a client's stall10Checked mark", (_, a) => {
    expect(a.condition).toContain("unmarked()");
  });
});
