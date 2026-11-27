import { beforeEach, describe, expect, it, vi } from "vitest";

const callApi = vi.fn();
vi.mock("@/lib/client", async () => {
  const actual = await vi.importActual<typeof import("@/lib/client")>("@/lib/client");
  return { ...actual, callApi: (...a: unknown[]) => callApi(...a) };
});

import { ApiError } from "@/lib/client";
import { newEventId, postNewEvent } from "@/lib/createOnce";

const user = { uid: "me" } as never;
beforeEach(() => callApi.mockReset());

describe("client ids for new events (S4 fix D1)", () => {
  it("makes ids that fit the API's ^[A-Za-z0-9]{1,40}$ and differ each time", () => {
    const ids = Array.from({ length: 50 }, () => newEventId());
    for (const id of ids) expect(id).toMatch(/^[A-Za-z0-9]{1,40}$/);
    expect(new Set(ids).size).toBe(50);
  });

  it("posts the body with the id and returns the API's id", async () => {
    callApi.mockResolvedValueOnce({ id: "srv" });
    await expect(postNewEvent(user, "/v1/calendars/c1/events", { title: "Run" }, "abc123")).resolves.toEqual({ id: "srv" });
    expect(callApi).toHaveBeenCalledWith(user, "/v1/calendars/c1/events", { method: "POST", body: { title: "Run", id: "abc123" } });
  });

  it("treats 409 already_exists (a replay of the same id) as success", async () => {
    callApi.mockRejectedValueOnce(new ApiError("Already there.", 409, "already_exists"));
    await expect(postNewEvent(user, "/p", {}, "abc123")).resolves.toEqual({ id: "abc123" });
  });

  it("still fails for any other error, including a 409 with another code", async () => {
    callApi.mockRejectedValueOnce(new ApiError("Nope.", 403, "forbidden"));
    await expect(postNewEvent(user, "/p", {}, "abc123")).rejects.toThrow("Nope.");
    callApi.mockRejectedValueOnce(new ApiError("Busy.", 409, "conflict"));
    await expect(postNewEvent(user, "/p", {}, "abc123")).rejects.toThrow("Busy.");
  });
});
