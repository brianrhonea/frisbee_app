// imageUrl (browse/model.ts, copied in the functions): our buckets and the
// lh3 Google photo host only (3a-F). Mirrored in
// firebase/functions/test/browse/image_url.test.ts.
import { afterEach, describe, expect, it } from "vitest";
import { configureImageBuckets, imageUrl } from "../src/browse/model.js";

afterEach(() => configureImageBuckets([]));

describe("imageUrl", () => {
  it("allows lh3 Google photos but not other googleusercontent hosts", () => {
    expect(imageUrl("https://lh3.googleusercontent.com/a/p")).toBe("https://lh3.googleusercontent.com/a/p");
    for (const u of ["https://evil.googleusercontent.com/p", "https://lh4.googleusercontent.com/p", "http://lh3.googleusercontent.com/p"]) {
      expect(imageUrl(u), u).toBeUndefined();
    }
  });

  it("allows only the configured buckets once set", () => {
    configureImageBuckets(["mine.firebasestorage.app"]);
    expect(imageUrl("https://firebasestorage.googleapis.com/v0/b/mine.firebasestorage.app/o/users%2Fa%2Fp.jpg?alt=media")).toBeDefined();
    expect(imageUrl("https://storage.googleapis.com/mine.firebasestorage.app/p.jpg")).toBeDefined();
    expect(imageUrl("https://firebasestorage.googleapis.com/v0/b/theirs/o/p.jpg")).toBeUndefined();
    expect(imageUrl("https://storage.googleapis.com/theirs/p.jpg")).toBeUndefined();
  });

  it("refuses other hosts, ports, credentials and long values", () => {
    for (const u of ["https://tracker.example/p.gif", "https://user:pw@lh3.googleusercontent.com/p", "https://lh3.googleusercontent.com:8443/p", "not a url", `https://lh3.googleusercontent.com/${"a".repeat(2000)}`]) {
      expect(imageUrl(u), u).toBeUndefined();
    }
    expect(imageUrl(42)).toBeUndefined();
  });
});
