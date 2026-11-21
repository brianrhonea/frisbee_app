// The one "Subscribe" button's options (calendar.ts); the app's
// subscribeOptions (calendar.dart) has the same tests.
import { describe, expect, it } from "vitest";
import { subscribeOptions } from "../src/index.js";

const feed = { url: "https://api.stall10.app/v1/ical/tok.ics", webcal: "webcal://api.stall10.app/v1/ical/tok.ics" };
const targets = (...a: Parameters<typeof subscribeOptions> extends [unknown, ...infer R] ? R : never) =>
  subscribeOptions(feed, ...a).map((o) => o.target);

describe("subscribeOptions", () => {
  it("puts Apple Calendar first on Apple devices, and only there", () => {
    expect(targets("ios")).toEqual(["apple", "google", "outlook", "outlookWork"]);
    expect(targets("macos")[0]).toBe("apple");
    expect(targets("android")).not.toContain("apple");
    expect(targets("other")).not.toContain("apple");
  });
  it("puts Google first on Android, Outlook first elsewhere", () => {
    expect(targets("android")).toEqual(["google", "outlook", "outlookWork", "other"]);
    expect(targets("other")).toEqual(["outlook", "outlookWork", "google", "other"]);
  });
  it("moves installed apps first", () => {
    expect(targets("android", ["outlook"])).toEqual(["outlook", "google", "outlookWork", "other"]);
  });
  it("builds each link", () => {
    const by = Object.fromEntries(subscribeOptions(feed, "other").map((o) => [o.target, o.url]));
    expect(by.google).toBe(`https://calendar.google.com/calendar/r?cid=${encodeURIComponent(feed.webcal)}`);
    expect(by.outlook).toBe(`https://outlook.live.com/calendar/0/addfromweb?url=${encodeURIComponent(feed.url)}&name=Stall%2010`);
    expect(by.outlookWork).toMatch(/^https:\/\/outlook\.office\.com\/calendar\/0\/addfromweb\?url=/);
    expect(by.other).toBe(feed.webcal);
  });
});
