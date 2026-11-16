import { describe, expect, it } from "vitest";
import { normalizeLink, postLinkMax } from "../src/index.js";

// The same cases as the app's TeamPost.normalizeLink test (team_home_test.dart).
describe("normalizeLink", () => {
  it("adds https:// and keeps http(s) links", () => {
    expect(normalizeLink("example.com/a")).toBe("https://example.com/a");
    expect(normalizeLink(" http://x.org ")).toBe("http://x.org");
    expect(normalizeLink("Https://X.org/Path")).toBe("https://X.org/Path");
  });
  it("refuses other schemes, spaces, hosts without a dot and long links", () => {
    expect(normalizeLink("ftp://x.org")).toBeNull();
    expect(normalizeLink("javascript:alert(1)")).toBeNull();
    expect(normalizeLink("not a link")).toBeNull();
    expect(normalizeLink("localhost")).toBeNull();
    expect(normalizeLink("")).toBeNull();
    expect(normalizeLink(`example.com/${"a".repeat(postLinkMax)}`)).toBeNull();
  });
});
