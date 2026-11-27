import { afterEach, describe, expect, it, vi } from "vitest";
import { prefersReducedMotion, scrollBehavior } from "@/lib/motion";

const mock = (matches: boolean) => vi.stubGlobal("matchMedia", (q: string) => ({ matches: matches && q.includes("reduce") }));
afterEach(() => vi.unstubAllGlobals());

describe("motion helpers", () => {
  it("scrolls smoothly unless reduced motion is on", () => {
    mock(false);
    expect(prefersReducedMotion()).toBe(false);
    expect(scrollBehavior()).toBe("smooth");
    mock(true);
    expect(prefersReducedMotion()).toBe(true);
    expect(scrollBehavior()).toBe("auto");
  });
});
