import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
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

const local = (h: number) => `2030-06-12T${String(h).padStart(2, "0")}:00`;
const iso = (h: number) => new Date(2030, 5, 12, h).toISOString();
const others = [
  { id: "a", title: "Tuesday practice", startsAt: iso(18), endsAt: iso(20) },
  { id: "b", title: "Cancelled game", startsAt: iso(9), endsAt: iso(11), status: "cancelled" },
];

function setup(onDone = vi.fn()) {
  render(
    <ConfirmProvider>
      <TeamEventEditor others={others} onDone={onDone} />
    </ConfirmProvider>,
  );
  return onDone;
}
function fill(title: string, startHour: number, endHour: number) {
  fireEvent.change(screen.getByLabelText("Title"), { target: { value: title } });
  const [starts, ends] = Array.from(document.querySelectorAll<HTMLInputElement>('input[type="datetime-local"]'));
  fireEvent.change(starts!, { target: { value: local(startHour) } });
  fireEvent.change(ends!, { target: { value: local(endHour) } });
}

beforeEach(() => callApi.mockReset());

describe("Overlap warning in the team event editor (S4 C5)", () => {
  it("asks 'This overlaps with ...' and saves when the user says Save anyway", async () => {
    callApi.mockResolvedValueOnce({ id: "new1" });
    const onDone = setup();
    fill("Film session", 19, 21);
    fireEvent.click(screen.getByRole("button", { name: "Add" }));
    const dialog = await screen.findByRole("dialog", { name: "Overlapping event" });
    expect(dialog).toHaveTextContent(/This overlaps with Tuesday practice \(.+\)\. Save anyway\?/);
    expect(callApi).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Save anyway" }));
    await waitFor(() => expect(onDone).toHaveBeenCalledWith("new1"));
    expect(callApi).toHaveBeenCalledTimes(1);
  });

  it("does not save when the user cancels, and nothing is lost", async () => {
    setup();
    fill("Film session", 19, 21);
    fireEvent.click(screen.getByRole("button", { name: "Add" }));
    const dialog = await screen.findByRole("dialog", { name: "Overlapping event" });
    fireEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));
    await waitFor(() => expect(screen.queryByRole("dialog", { name: "Overlapping event" })).toBeNull());
    expect(callApi).not.toHaveBeenCalled();
    expect(screen.getByLabelText("Title")).toHaveValue("Film session");
  });

  it("saves without asking when nothing overlaps, and ignores a cancelled event", async () => {
    callApi.mockResolvedValueOnce({ id: "new2" });
    const onDone = setup();
    fill("Morning run", 9, 10);
    fireEvent.click(screen.getByRole("button", { name: "Add" }));
    await waitFor(() => expect(onDone).toHaveBeenCalledWith("new2"));
    expect(screen.queryByRole("dialog", { name: "Overlapping event" })).toBeNull();
  });
});
