// @vitest-environment node
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// Confirmations go through useConfirm() (ConfirmDialog: focus trap, destructive
// variant), not the browser's window.confirm. These three were left on purpose
// (Sprint 3 C10): two are payment screens, whose behaviour is not touched
// without approval, and one returns the answer synchronously to its caller.
const web = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const allowed = ["components/payments/ConfirmSignIn.tsx", "components/payments/Payments.tsx", "components/payments/StaffPayments.tsx", "components/team/stats/StatsHome.tsx", "components/ui/ConfirmDialog.tsx"];

function files(dir: string, out: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) files(p, out);
    else if (/\.tsx?$/.test(e.name)) out.push(p);
  }
  return out;
}

describe("native confirm dialogs", () => {
  it("are only where they were left on purpose", () => {
    const found = [...files(join(web, "components")), ...files(join(web, "app"))]
      .filter((f) => /\b(window\.)?confirm\(/.test(readFileSync(f, "utf8").replace(/askConfirm\(/g, "")))
      .map((f) => relative(web, f).replace(/\\/g, "/"))
      .filter((f) => !allowed.includes(f));
    expect(found).toEqual([]);
  });
});
