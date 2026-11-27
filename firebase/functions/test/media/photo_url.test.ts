// The functions' copy of the trusted-profile-photo rule (3a-F), and the paths
// that use it: the ranking card and the LiveKit participant photo.
import { describe, expect, it } from "vitest";

import { playerInput } from "../../src/rankings/players";
import { projectBuckets, trustedPhotoUrl } from "../../src/media/photo_url";

const buckets = ["p.firebasestorage.app"];
const own = "https://firebasestorage.googleapis.com/v0/b/p.firebasestorage.app/o/users%2Fu1%2Fprofile%2Fme.jpg?alt=media";

describe("trustedPhotoUrl", () => {
  it("trusts the person's own profile folder and Google lh3 photos", () => {
    expect(trustedPhotoUrl(own, "u1", buckets)).toBe(own);
    expect(trustedPhotoUrl("https://lh3.googleusercontent.com/a/x", "u1", buckets)).toBe("https://lh3.googleusercontent.com/a/x");
  });

  it("refuses someone else's folder, other buckets, other hosts, traversal and long values", () => {
    expect(trustedPhotoUrl(own, "u2", buckets)).toBeNull();
    expect(trustedPhotoUrl(own, "u1", ["other"])).toBeNull();
    expect(trustedPhotoUrl("https://tracker.example/p.gif", "u1", buckets)).toBeNull();
    expect(trustedPhotoUrl("https://lh4.googleusercontent.com/a/x", "u1", buckets)).toBeNull();
    expect(trustedPhotoUrl(own.replace("me.jpg", "..%2Fposts%2Fx.jpg"), "u1", buckets)).toBeNull();
    expect(trustedPhotoUrl(`https://lh3.googleusercontent.com/${"a".repeat(2000)}`, "u1", buckets)).toBeNull();
    expect(trustedPhotoUrl(null, "u1", buckets)).toBeNull();
  });
});

describe("projectBuckets", () => {
  it("is the project's two default buckets and the configured one", () => {
    expect(projectBuckets({ GCLOUD_PROJECT: "p", FIREBASE_CONFIG: JSON.stringify({ storageBucket: "custom" }) })).toEqual([
      "custom",
      "p.firebasestorage.app",
      "p.appspot.com",
    ]);
    expect(projectBuckets({})).toEqual([]);
  });
});

describe("ranking cards", () => {
  const profile = { name: "Pat", username: "pat", stats: {} };
  it("copy only a trusted photo", () => {
    expect(playerInput("u1", { ...profile, photoUrl: "https://tracker.example/p.gif" })?.photoUrl).toBeNull();
    expect(playerInput("u1", { ...profile, photoUrl: "https://lh3.googleusercontent.com/a/x" })?.photoUrl).toBe("https://lh3.googleusercontent.com/a/x");
  });
});
