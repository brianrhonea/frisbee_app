import { adultOnlyMessage, birthDateLockedMessage } from "@stall10/shared";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/firebase", () => ({ appCheckToken: async () => null }));

import { adultBirthDateProblem, announceIncomplete, clearIncomplete, isUnderAge, missingFields, subscribeIncomplete } from "@/lib/accountGate";
import { ApiError, callApi } from "@/lib/client";
import { saveSignUpDetails } from "@/lib/signupAccount";

type Reply = { status: number; body?: unknown };
let calls: { path: string; method: string }[];
let replies: Record<string, Reply[]>;
const getIdToken = vi.fn();
const user = { getIdToken: (force?: boolean) => getIdToken(force) } as never;

const incomplete = (fields: Record<string, string>): Reply => ({
  status: 403,
  body: { error: { code: "account_incomplete", message: Object.values(fields)[0], fields } },
});

beforeEach(() => {
  calls = [];
  replies = {};
  getIdToken.mockReset();
  getIdToken.mockResolvedValue("tok");
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: URL, init: { method?: string }) => {
      const path = url.pathname;
      calls.push({ path, method: init.method ?? "GET" });
      const r = replies[path]?.shift() ?? { status: 200, body: {} };
      return { ok: r.status < 400, status: r.status, json: async () => r.body } as Response;
    }),
  );
  clearIncomplete();
});
afterEach(() => vi.unstubAllGlobals());

const seen = () => {
  let last: unknown = "none";
  const off = subscribeIncomplete((m) => (last = m));
  return { get: () => last, off };
};

describe("callApi and the account gate", () => {
  it("on account_incomplete: status says refresh, token refreshed, write retried once and succeeds", async () => {
    replies["/v1/teams"] = [incomplete({ terms: "Agree" }), { status: 200, body: { id: "t1" } }];
    replies["/v1/me/personal/status"] = [{ status: 200, body: { complete: true, required: false, refreshToken: true } }];
    const s = seen();
    await expect(callApi(user, "/v1/teams", { method: "POST", body: {} })).resolves.toEqual({ id: "t1" });
    expect(calls.map((c) => c.path)).toEqual(["/v1/teams", "/v1/me/personal/status", "/v1/teams"]);
    expect(getIdToken).toHaveBeenCalledWith(true);
    expect(s.get()).toBeNull();
    s.off();
  });

  it("still incomplete after the retry: announces the first field, throws, and does not loop", async () => {
    const again = incomplete({ email_unverified: "Verify", terms: "Agree" });
    replies["/v1/teams"] = [incomplete({ email_unverified: "Verify", terms: "Agree" }), again];
    replies["/v1/me/personal/status"] = [{ status: 200, body: { complete: true, required: false, refreshToken: true } }];
    const s = seen();
    await expect(callApi(user, "/v1/teams", { method: "POST", body: {} })).rejects.toMatchObject({ code: "account_incomplete" });
    expect(calls.filter((c) => c.path === "/v1/teams")).toHaveLength(2);
    expect(calls.filter((c) => c.path === "/v1/me/personal/status")).toHaveLength(1);
    expect(s.get()).toEqual(["email_unverified", "terms"]);
    s.off();
  });

  it("status says nothing changed: no retry, routes by fields in contract order", async () => {
    replies["/v1/teams"] = [incomplete({ terms: "Agree", age: "Add your date of birth" })];
    replies["/v1/me/personal/status"] = [{ status: 200, body: { complete: false, required: true } }];
    const s = seen();
    await expect(callApi(user, "/v1/teams", { method: "POST", body: {} })).rejects.toBeInstanceOf(ApiError);
    expect(calls.map((c) => c.path)).toEqual(["/v1/teams", "/v1/me/personal/status"]);
    expect(s.get()).toEqual(["age", "terms"]);
    s.off();
  });

  it("a failing status call still shows the step from the original error", async () => {
    replies["/v1/teams"] = [incomplete({ age: "Add your date of birth" })];
    replies["/v1/me/personal/status"] = [{ status: 500, body: { error: { code: "internal", message: "x" } } }];
    const s = seen();
    await expect(callApi(user, "/v1/teams", { method: "POST", body: {} })).rejects.toBeInstanceOf(ApiError);
    expect(s.get()).toEqual(["age"]);
    s.off();
  });

  it("never loops on the status route itself", async () => {
    replies["/v1/me/personal/status"] = [incomplete({ age: "x" })];
    await expect(callApi(user, "/v1/me/personal/status")).rejects.toBeInstanceOf(ApiError);
    expect(calls).toHaveLength(1);
  });

  it("other errors (403 forbidden, 400) are not routed", async () => {
    replies["/v1/teams"] = [{ status: 403, body: { error: { code: "forbidden", message: "No" } } }];
    const s = seen();
    await expect(callApi(user, "/v1/teams", { method: "POST", body: {} })).rejects.toMatchObject({ code: "forbidden" });
    expect(calls).toHaveLength(1);
    expect(s.get()).toBeNull();
    s.off();
  });

  it("refreshToken: true on any answer refreshes the token; its absence does not", async () => {
    replies["/v1/me/agreement"] = [{ status: 200, body: { agreed: true, version: 1, refreshToken: true } }];
    await callApi(user, "/v1/me/agreement", { method: "PUT", body: { version: 1 } });
    expect(getIdToken).toHaveBeenCalledWith(true);
    getIdToken.mockClear();
    replies["/v1/me/agreement"] = [{ status: 200, body: { agreed: true, version: 1 } }];
    await callApi(user, "/v1/me/agreement");
    expect(getIdToken).not.toHaveBeenCalledWith(true);
  });
});

describe("account gate helpers", () => {
  it("missingFields keeps the contract order and drops unknown keys", () => {
    expect(missingFields({ terms: "a", other: "b", email_unverified: "c" })).toEqual(["email_unverified", "terms"]);
    expect(missingFields(undefined)).toEqual([]);
  });

  it("18+ only: 17 and under 13 get the adult-only message, 18 passes", () => {
    expect(adultBirthDateProblem("2010-01-01", "2026-11-26")).toBe(adultOnlyMessage);
    expect(adultBirthDateProblem("2015-01-01", "2026-11-26")).toBe(adultOnlyMessage);
    expect(adultBirthDateProblem("2008-11-27", "2026-11-26")).toBe(adultOnlyMessage);
    expect(adultBirthDateProblem("2008-11-26", "2026-11-26")).toBeNull();
    expect(adultBirthDateProblem("nonsense", "2026-11-26")).toBe("Enter your date of birth.");
    expect(adultBirthDateProblem("2999-01-01", "2026-11-26")).toBe("That date is in the future.");
    expect(isUnderAge("2010-01-01", "2026-11-26")).toBe(true);
    expect(isUnderAge(undefined, "2026-11-26")).toBe(false);
  });
});

describe("sign-up writes in the gate's order (review F1)", () => {
  it("saves the birth date, refreshes the token, and only then claims the username", async () => {
    replies["/v1/me/personal/birth-date"] = [{ status: 200, body: { refreshToken: true } }];
    const order: string[] = [];
    getIdToken.mockImplementation(async (force?: boolean) => {
      if (force) order.push("refresh");
      return "tok";
    });
    (fetch as unknown as ReturnType<typeof vi.fn>).mockImplementation(async (url: URL) => {
      order.push(url.pathname);
      const r = replies[url.pathname]?.shift() ?? { status: 200, body: {} };
      return { ok: true, status: r.status, json: async () => r.body } as Response;
    });
    await expect(saveSignUpDetails(user, "1990-01-01", "sam")).resolves.toBe("saved");
    expect(order).toEqual(["/v1/me/personal/birth-date", "refresh", "/v1/me/username"]);
  });

  it("does not try the username when the birth date isn't saved", async () => {
    replies["/v1/me/personal/birth-date"] = [{ status: 500, body: { error: { code: "internal", message: "x" } } }];
    await expect(saveSignUpDetails(user, "1990-01-01", "sam")).resolves.toBe("skipped");
    expect(calls.map((c) => c.path)).toEqual(["/v1/me/personal/birth-date"]);
  });

  it("an under-18 refusal is adult-only and the username is not attempted", async () => {
    replies["/v1/me/personal/birth-date"] = [
      { status: 412, body: { error: { code: "failed_precondition", message: adultOnlyMessage, fields: { birthDate: adultOnlyMessage } } } },
    ];
    await expect(saveSignUpDetails(user, "2015-01-01", "sam")).resolves.toBe("adultOnly");
    expect(calls).toHaveLength(1);
  });

  it("the locked message is a distinct 412", () => {
    expect(birthDateLockedMessage).not.toBe(adultOnlyMessage);
  });
});
