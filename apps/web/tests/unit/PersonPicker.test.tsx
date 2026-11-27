import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";

// The only website query that lists profiles. The Firestore rules refuse a list unless it
// filters `adult == true` (a server-only marker), so the filter must be in the query.
const calls: { wheres: unknown[][]; max: number | null } = { wheres: [], max: null };
vi.mock("firebase/firestore", () => ({
  collection: (_db: unknown, path: string) => ({ path }),
  where: (...args: unknown[]) => {
    calls.wheres.push(args);
    return { args };
  },
  limit: (n: number) => {
    calls.max = n;
    return { n };
  },
  query: (...parts: unknown[]) => parts,
  getDocs: async () => ({ docs: [{ id: "u2", data: () => ({ name: "Ben Okafor", username: "benokafor" }) }] }),
}));
vi.mock("@/lib/firebase", () => ({ firestoreDb: () => ({}) }));
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => ({ user: { uid: "me" } }) }));

import { PersonPicker } from "@/components/PersonPicker";

describe("PersonPicker", () => {
  it("lists only adult profiles, keeps the keyword filter and the limit", async () => {
    render(<PersonPicker onPick={() => undefined} />);
    fireEvent.change(screen.getByRole("searchbox"), { target: { value: "ben" } });
    await waitFor(() => expect(calls.wheres.length).toBeGreaterThan(0), { timeout: 2000 });
    expect(calls.wheres).toContainEqual(["keywords", "array-contains", "ben"]);
    expect(calls.wheres).toContainEqual(["adult", "==", true]);
    expect(calls.max).toBe(20);
    expect(await screen.findByText("Ben Okafor")).toBeInTheDocument();
  });
});
