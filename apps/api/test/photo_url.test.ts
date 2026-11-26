import { describe, expect, it } from "vitest";
import { trustedPhotoUrl } from "../src/media/photo_url.js";

const buckets = ["proj.firebasestorage.app", "proj.appspot.com"];
const own = (name: string, bucket = buckets[0]!, uid = "u1") =>
  `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(`users/${uid}/profile/${name}`)}?alt=media&token=abc`;

const raw = (tail: string) => `https://firebasestorage.googleapis.com/v0/b/${buckets[0]}/o/users%2Fu1%2Fprofile%2F${tail}?alt=media`;

describe("trustedPhotoUrl (F5: a client can set its own Auth photoURL)", () => {
  it("trusts the person's own profile folder in our buckets, and Google account photos", () => {
    expect(trustedPhotoUrl(own("me.jpg"), "u1", buckets)).toBe(own("me.jpg"));
    expect(trustedPhotoUrl(own("me.jpg", buckets[1]), "u1", buckets)).not.toBeNull();
    const google = "https://lh3.googleusercontent.com/a/abc=s96-c";
    expect(trustedPhotoUrl(google, "u1", buckets)).toBe(google);
  });

  it.each([
    ["a tracking pixel", "https://evil.example/p.gif"],
    ["http", "http://lh3.googleusercontent.com/a/x"],
    ["a lookalike host", "https://lh3.googleusercontent.com.evil.example/a"],
    ["another bucket", own("me.jpg", "other.firebasestorage.app")],
    ["another person's folder", own("me.jpg", buckets[0], "u2")],
    ["a non-profile folder", `https://firebasestorage.googleapis.com/v0/b/${buckets[0]}/o/${encodeURIComponent("users/u1/posts/p.jpg")}?alt=media`],
    ["a nested path", raw("a%2Fb.jpg")],
    ["a traversal", raw("..%2F..%2Fx.jpg")],
    ["no file name", own("")],
    ["an emulator URL outside the emulator", own("me.jpg").replace("https://firebasestorage.googleapis.com", "http://127.0.0.1:9199")],
    ["too long", own("x".repeat(2000))],
    ["empty", ""],
  ])("refuses %s", (_, url) => {
    expect(trustedPhotoUrl(url, "u1", buckets)).toBeNull();
  });

  it("refuses null and undefined", () => {
    expect(trustedPhotoUrl(null, "u1", buckets)).toBeNull();
    expect(trustedPhotoUrl(undefined, "u1", buckets)).toBeNull();
  });

  it("allows the Storage emulator's URL only when running against it", () => {
    const url = own("me.jpg").replace("https://firebasestorage.googleapis.com", "http://127.0.0.1:9199");
    expect(trustedPhotoUrl(url, "u1", buckets, "127.0.0.1:9199")).toBe(url);
    expect(trustedPhotoUrl(url, "u1", buckets, "127.0.0.1:1")).toBeNull();
  });
});
