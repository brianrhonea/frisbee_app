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

import { ApiError } from "@/lib/client";
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

  it("checks every occurrence of a repeating event: a later one that clashes asks too", async () => {
    // Weekly from Wed Jun 12 2030 at 09:00 to Jun 26 (Jun 12, 19, 26): only the last one meets "Late game".
    const later = { id: "c", title: "Late game", startsAt: new Date(2030, 5, 26, 9, 30).toISOString(), endsAt: new Date(2030, 5, 26, 11).toISOString() };
    render(
      <ConfirmProvider>
        <TeamEventEditor others={[later]} onDone={vi.fn()} />
      </ConfirmProvider>,
    );
    fill("Morning run", 9, 10);
    fireEvent.change(screen.getByLabelText("Repeat"), { target: { value: "weekly" } });
    fireEvent.change(screen.getByLabelText("Ends on"), { target: { value: "2030-06-26" } });
    fireEvent.click(screen.getByRole("button", { name: "Add" }));
    const dialog = await screen.findByRole("dialog", { name: "Overlapping event" });
    expect(dialog).toHaveTextContent(/This overlaps with Late game/);
    expect(callApi).not.toHaveBeenCalled();
  });
});

describe("New team events carry a client id (S4 fix D1)", () => {
  const idRule = /^[A-Za-z0-9]{1,40}$/;

  it("sends an id that fits the API's rule", async () => {
    callApi.mockResolvedValueOnce({ id: "x" });
    const onDone = setup();
    fill("Morning run", 9, 10);
    fireEvent.click(screen.getByRole("button", { name: "Add" }));
    await waitFor(() => expect(onDone).toHaveBeenCalled());
    const body = callApi.mock.calls[0]![2].body as { id: string };
    expect(body.id).toMatch(idRule);
  });

  it("reuses the same id on a retry after a failure", async () => {
    callApi.mockRejectedValueOnce(new ApiError("Couldn't reach Stall 10.", 0)).mockResolvedValueOnce({ id: "x" });
    const onDone = setup();
    fill("Morning run", 9, 10);
    fireEvent.click(screen.getByRole("button", { name: "Add" }));
    await screen.findByRole("alert");
    fireEvent.click(screen.getByRole("button", { name: "Add" }));
    await waitFor(() => expect(onDone).toHaveBeenCalled());
    expect(callApi).toHaveBeenCalledTimes(2);
    expect(callApi.mock.calls[1]![2].body.id).toBe(callApi.mock.calls[0]![2].body.id);
  });

  it("treats a 409 already_exists replay as success, with the id it sent", async () => {
    callApi.mockRejectedValueOnce(new ApiError("Already exists.", 409, "already_exists"));
    const onDone = setup();
    fill("Morning run", 9, 10);
    fireEvent.click(screen.getByRole("button", { name: "Add" }));
    await waitFor(() => expect(onDone).toHaveBeenCalledTimes(1));
    const sent = callApi.mock.calls[0]![2].body.id as string;
    expect(onDone).toHaveBeenCalledWith(sent);
  });

  it("a double-click sends one id, so the API can't make two events", async () => {
    let resolve!: (v: { id: string }) => void;
    let posts = 0;
    callApi.mockImplementation((_u: unknown, _path: string, init?: { method?: string }) => {
      if (init?.method !== "POST") return Promise.resolve([]);
      return posts++ === 0 ? new Promise((r) => (resolve = r)) : Promise.reject(new ApiError("Already exists.", 409, "already_exists"));
    });
    const onDone = setup();
    fill("Morning run", 9, 10);
    const add = screen.getByRole("button", { name: "Add" });
    fireEvent.click(add);
    fireEvent.click(add);
    resolve({ id: "x" });
    await waitFor(() => expect(onDone).toHaveBeenCalled());
    const ids = new Set(callApi.mock.calls.filter((c) => c[2]?.method === "POST").map((c) => c[2].body.id));
    expect(ids.size).toBe(1);
  });
});
