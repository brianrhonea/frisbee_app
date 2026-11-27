// The one-off under-13 marker backfill (src/account/backfill_under13.ts and
// src/scripts/backfill_under13.ts): dry run by default, marks only readable
// under-13 refusals, never an adult-only one, and the script's guard refuses
// any project that isn't dev (or demo-* on the emulator).
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { describe, expect, it } from "vitest";
import { backfillUnder13Marker, type RefusalRecord } from "../src/account/backfill_under13.js";
import { PersonalService } from "../src/personal/service.js";
import { FakeCipher, FakeStore, FakeUsers } from "./fakes.js";

const now = Date.UTC(2026, 10, 20, 12);

async function world() {
  const store = new FakeStore(() => now);
  const cipher = new FakeCipher();
  const personal = new PersonalService(store, new FakeUsers(), cipher, () => now);
  const seal = async (uid: string, plain: string) => {
    const sealed = await cipher.seal(Buffer.from(plain, "utf8"), `ageRefusals/${uid}`);
    return { ciphertext: sealed.ciphertext, key: sealed.key, format: 1, refusedAt: new Date(now) };
  };
  store.put("ageRefusals/kid", await seal("kid", JSON.stringify({ birthDate: "2018-01-01" })));
  store.put("ageRefusals/kidDone", { ...(await seal("kidDone", JSON.stringify({ birthDate: "2018-02-02" }))), under13: true });
  store.put("ageRefusals/teen", await seal("teen", JSON.stringify({ birthDate: "2011-01-01" })));
  store.put("ageRefusals/empty", await seal("empty", "{}"));
  store.put("ageRefusals/garbled", { ciphertext: "not-base64-for-this-context", key: "fake-key", format: 1, refusedAt: new Date(now) });
  const ids: RefusalRecord[] = [
    { id: "kid" },
    { id: "kidDone", under13: true },
    { id: "teen" },
    { id: "empty" },
    { id: "garbled" },
  ];
  async function* refusals() {
    yield* ids;
  }
  const marked: string[] = [];
  const run = (apply: boolean) =>
    backfillUnder13Marker({ refusals: refusals(), personal, mark: async (u) => void marked.push(u), apply });
  return { run, marked };
}

describe("backfillUnder13Marker", () => {
  it("a dry run counts what it would mark and writes nothing", async () => {
    const w = await world();
    const r = await w.run(false);
    expect(r).toMatchObject({ scanned: 5, alreadyMarked: 1, marked: 1, adultOnly: 1, applied: false });
    expect(r.unreadable.sort()).toEqual(["empty", "garbled"]);
    expect(w.marked).toEqual([]);
  });

  it("applying marks only the readable unmarked under-13 refusal, never an adult-only or unreadable one", async () => {
    const w = await world();
    const r = await w.run(true);
    expect(r).toMatchObject({ marked: 1, applied: true, writeFailures: [] });
    expect(w.marked).toEqual(["kid"]);
  });

  it("reports a failed write instead of counting it", async () => {
    const store = new FakeStore(() => now);
    const cipher = new FakeCipher();
    const personal = new PersonalService(store, new FakeUsers(), cipher, () => now);
    const sealed = await cipher.seal(Buffer.from(JSON.stringify({ birthDate: "2018-01-01" }), "utf8"), "ageRefusals/kid");
    store.put("ageRefusals/kid", { ciphertext: sealed.ciphertext, key: sealed.key, format: 1, refusedAt: new Date(now) });
    const r = await backfillUnder13Marker({
      refusals: (async function* () {
        yield { id: "kid" };
      })(),
      personal,
      mark: async () => Promise.reject(new Error("write failed")),
      apply: true,
    });
    expect(r).toMatchObject({ marked: 0, writeFailures: ["kid"] });
  });
});

describe("backfill_under13.ts guard", () => {
  const run = async (args: string[], extra: Record<string, string> = {}) => {
    const env = { PATH: process.env.PATH ?? "", SystemRoot: process.env.SystemRoot ?? "", ...extra };
    try {
      await promisify(execFile)(process.execPath, ["--import", "tsx", "src/scripts/backfill_under13.ts", ...args], { cwd: process.cwd(), env, timeout: 60_000 });
      return { code: 0, err: "" };
    } catch (e) {
      const x = e as { code?: number; stderr?: string };
      return { code: x.code ?? -1, err: x.stderr ?? "" };
    }
  };

  it("needs --project", async () => {
    const r = await run([]);
    expect(r.code).toBe(1);
    expect(r.err).toMatch(/Pass --project/);
  }, 120_000);

  it("refuses production and any other project, and demo-* without the emulator", async () => {
    for (const project of ["frisbee-app-prod", "some-other-project", "demo-stall10"]) {
      const r = await run(["--project", project, "--apply"]);
      expect(r.code, project).toBe(1);
      expect(r.err, project).toMatch(/Refusing project/);
    }
  }, 120_000);
});
