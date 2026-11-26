import { describe, expect, it } from "vitest";

import { assertAllowedProject, devProject, planBackfill } from "../../scripts/backfill-fid-owners";

describe("assertAllowedProject", () => {
  it("allows the dev project", () => {
    expect(() => assertAllowedProject(devProject, undefined)).not.toThrow();
  });

  it("allows any project name when a Firestore emulator is in use", () => {
    expect(() => assertAllowedProject("demo-frisbee", "127.0.0.1:8080")).not.toThrow();
  });

  it("refuses anything else, including prod-looking and missing projects", () => {
    expect(() => assertAllowedProject("frisbee-app-prod", undefined)).toThrow(/Refusing/);
    expect(() => assertAllowedProject("demo-frisbee", undefined)).toThrow(/Refusing/);
    expect(() => assertAllowedProject(undefined, undefined)).toThrow(/Refusing/);
  });
});

describe("planBackfill", () => {
  it("makes the newest registration of each FID the owner and the rest losers", () => {
    const plan = planBackfill([
      { uid: "a", fid: "f1", at: 100 },
      { uid: "b", fid: "f1", at: 300 },
      { uid: "c", fid: "f1", at: 200 },
      { uid: "a", fid: "f2", at: 100 },
    ]);
    expect(plan.owners).toEqual([
      { uid: "b", fid: "f1", at: 300 },
      { uid: "a", fid: "f2", at: 100 },
    ]);
    expect(plan.losers.map((l) => l.uid).sort()).toEqual(["a", "c"]);
  });

  it("breaks a tie the same way every run", () => {
    const devices = [
      { uid: "a", fid: "f", at: 100 },
      { uid: "b", fid: "f", at: 100 },
    ];
    expect(planBackfill(devices).owners[0].uid).toBe("b");
    expect(planBackfill([...devices].reverse()).owners[0].uid).toBe("b");
  });
});
