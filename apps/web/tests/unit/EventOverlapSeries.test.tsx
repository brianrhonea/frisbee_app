import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

const callApi = vi.fn();
const user = { uid: "me" };

vi.mock("@/lib/client", async () => {
  const actual = await vi.importActual<typeof import("@/lib/client")>("@/lib/client");
  return { ...actual, callApi: (...a: unknown[]) => callApi(...a) };
});
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => ({ user }) }));
vi.mock("@/components/team/TeamContext", async () => {
  const actual = await vi.importActual<typeof import("@/components/team/TeamContext")>("@/components/team/TeamContext");
  return {
    ...actual,
    useTeamHub: () => ({ teamId: "t1", privateGroup: false, viewer: { state: "member", uid: "me", team: { kind: "team" }, tier: "owner", can: () => true, audience: [] } }),
  };
});

import { ConfirmProvider } from "@/components/ui/ConfirmDialog";
import { TeamEventEditor } from "@/components/team/TeamEventEditor";

beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal(this: HTMLDialogElement) {
    this.setAttribute("open", "");
  };
  HTMLDialogElement.prototype.close = function close(this: HTMLDialogElement) {
    this.removeAttribute("open");
  };
});
beforeEach(() => callApi.mockReset());

const iso = (h: number) => new Date(2030, 5, 12, h).toISOString();
const series = { id: "s1", index: 0, count: 3, freq: "weekly" as const, until: "2030-06-26" };
const editing = { id: "s1_0", title: "Practice", startsAt: iso(18), endsAt: iso(20), series } as never;
// Another event of the same series sitting on the same hour.
const sibling = { id: "s1_1", title: "Practice", startsAt: iso(18), endsAt: iso(20), series: { ...series, index: 1 } };
const stranger = { id: "z", title: "Film session", startsAt: iso(19), endsAt: iso(21) };

function edit(others: Array<Record<string, unknown>>) {
  render(
    <ConfirmProvider>
      <TeamEventEditor event={editing} others={others as never} onDone={vi.fn()} />
    </ConfirmProvider>,
  );
}

describe("Overlap warning when editing an event of a series (S5 FX1)", () => {
  it("saving 'this and following' does not warn about the event's own series", async () => {
    callApi.mockResolvedValueOnce({ id: "s1_0" });
    edit([sibling]);
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    fireEvent.click(await screen.findByRole("button", { name: "Save this and following events" }));
    await waitFor(() => expect(callApi).toHaveBeenCalledTimes(1));
    expect(screen.queryByRole("dialog", { name: "Overlapping event" })).toBeNull();
    expect(callApi.mock.calls[0]![1]).toBe("/v1/teams/t1/events/s1_0?scope=following");
  });

  it("still warns about a different event that overlaps", async () => {
    edit([sibling, stranger]);
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    fireEvent.click(await screen.findByRole("button", { name: "Save this and following events" }));
    const dialog = await screen.findByRole("dialog", { name: "Overlapping event" });
    expect(dialog).toHaveTextContent(/This overlaps with Film session/);
    expect(callApi).not.toHaveBeenCalled();
  });
});
