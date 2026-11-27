// @vitest-environment node
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// Phones' bottom tab bar covers the foot of the screen, so every sticky or
// fixed bar at the foot is offset above it (Sprint 3 S3). Those bars' own CSS
// loads with their pages, so this reads the shell's rule.
const css = readFileSync(resolve(dirname(fileURLToPath(import.meta.url)), "../../app/app.css"), "utf8").replace(/\r\n/g, "\n");
const phone = css.slice(css.indexOf("@media (max-width: 599px) {\n  .fab-post"));

describe("bottom bars sit above the phone tab bar", () => {
  it.each([".fab-post", ".frame .voice-bar", ".frame .gt-bar", ".frame .st-dock", ".frame .team-hub .wb-toast"])("%s", (sel) => {
    const rule = phone.split("\n").find((l) => l.includes(sel) && l.includes("bottom:"));
    expect(rule ?? phone.slice(phone.indexOf(sel), phone.indexOf(sel) + 400), sel).toMatch(/bottom: calc\(var\(--tabbar-h\)[^;]*env\(safe-area-inset-bottom/);
  });
});
