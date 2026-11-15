import { describe, expect, it } from "vitest";
import { legacyMessageDraftsKey, messageDraftsKey, messageDraftsMax, withDraft } from "../src/index.js";

describe("message drafts", () => {
  it("keeps each member's drafts under their own key", () => {
    expect(messageDraftsKey("u1")).toBe("messageDrafts_u1");
    expect(messageDraftsKey("u1")).not.toBe(messageDraftsKey("u2"));
    expect(messageDraftsKey("u1")).not.toBe(legacyMessageDraftsKey);
  });

  it("moves a saved draft to the end and forgets a blank one", () => {
    const d = withDraft({ dm_a: "hi", dm_b: "yo" }, "dm_a", "hello");
    expect(Object.entries(d)).toEqual([
      ["dm_b", "yo"],
      ["dm_a", "hello"],
    ]);
    expect(withDraft(d, "dm_b", "   ")).toEqual({ dm_a: "hello" });
  });

  it("keeps only the newest", () => {
    let d: Record<string, string> = {};
    for (let i = 0; i < messageDraftsMax + 5; i++) d = withDraft(d, `dm_${i}`, `t${i}`);
    expect(Object.keys(d)).toHaveLength(messageDraftsMax);
    expect(Object.keys(d)[0]).toBe("dm_5");
  });
});
