import { describe, expect, it } from "vitest";
import { cleanRsvpNote, meetingRsvpRequestSchema, nextRsvpNotes, rsvpNoteMax, rsvpRequestSchema } from "../src/index.js";

describe("cleanRsvpNote", () => {
  it("keeps one trimmed line without control characters", () => {
    expect(cleanRsvpNote("  Late 15 min ")).toBe("Late 15 min");
    expect(cleanRsvpNote("Bringing\r\ndiscs\tand  cones")).toBe("Bringing discs and cones");
    expect(cleanRsvpNote("a\u0000b\u007fc\u009f")).toBe("abc");
    expect(cleanRsvpNote(" \n\t ")).toBe("");
  });
});

describe("rsvp request schemas", () => {
  it("take an optional note, cleaned and at most 140 characters", () => {
    expect(rsvpRequestSchema.parse({ status: "going" })).toEqual({ status: "going" });
    expect(rsvpRequestSchema.parse({ status: "going", note: " Late " }).note).toBe("Late");
    expect(rsvpRequestSchema.parse({ status: "maybe", note: null }).note).toBeNull();
    expect(rsvpRequestSchema.parse({ status: "going", note: "x".repeat(rsvpNoteMax) }).note).toHaveLength(rsvpNoteMax);
    // Spaces cleaned away don't count.
    expect(rsvpRequestSchema.safeParse({ status: "going", note: ` ${"x".repeat(rsvpNoteMax)}  ` }).success).toBe(true);
    expect(rsvpRequestSchema.safeParse({ status: "going", note: "x".repeat(rsvpNoteMax + 1) }).success).toBe(false);
    expect(rsvpRequestSchema.safeParse({ status: "going", note: 3 }).success).toBe(false);
    expect(meetingRsvpRequestSchema.parse({ answer: "attending", note: "Joining late" }).note).toBe("Joining late");
    expect(meetingRsvpRequestSchema.safeParse({ answer: "attending", note: "y".repeat(141) }).success).toBe(false);
  });
});

describe("nextRsvpNotes", () => {
  const notes = { me: "Late", you: "Discs" };
  it("keeps the note when left out, sets or removes it, and drops it with the answer", () => {
    expect(nextRsvpNotes(notes, "me", true, undefined)).toEqual(notes);
    expect(nextRsvpNotes(notes, "me", true, "Early")).toEqual({ me: "Early", you: "Discs" });
    expect(nextRsvpNotes(notes, "me", true, "")).toEqual({ you: "Discs" });
    expect(nextRsvpNotes(notes, "me", true, null)).toEqual({ you: "Discs" });
    expect(nextRsvpNotes(notes, "me", false, "Ignored")).toEqual({ you: "Discs" });
    expect(nextRsvpNotes(undefined, "me", true, "New")).toEqual({ me: "New" });
    expect(nextRsvpNotes({ me: 3, you: "Discs" }, "x", true, undefined)).toEqual({ you: "Discs" });
  });
});
