import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const callApi = vi.fn();
let pathname = "/";
let user = { uid: "u1", displayName: "Sam Lee", email: "s@example.com" };

vi.mock("@/lib/client", () => ({ callApi: (...a: unknown[]) => callApi(...a) }));
vi.mock("@/lib/firebase", () => ({ deleteOwnAccount: vi.fn() }));
vi.mock("@/lib/live", () => ({ useLiveDoc: () => ({ data: { username: "sam" } }) }));
vi.mock("@/lib/signupDraft", () => ({ signupDraft: { takeBirthDate: () => undefined, takeName: () => undefined } }));
vi.mock("next/navigation", () => ({ usePathname: () => pathname }));
vi.mock("next/link", () => ({ default: ({ children, href }: { children: React.ReactNode; href: string }) => <a href={href}>{children}</a> }));
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => ({ user }) }));
vi.mock("@/components/AgreeTerms", () => ({ AgreeTerms: () => <p>AGREE-TERMS</p> }));
vi.mock("@/components/PersonalDetailsForm", () => ({ PersonalDetailsForm: ({ onSaved }: { onSaved: () => void }) => (
    <button type="button" onClick={onSaved}>
      DETAILS-FORM
    </button>
  ) }));
vi.mock("@/components/SignUpSteps", () => ({ SignUpSteps: () => null }));
vi.mock("@/components/UsernameStep", () => ({
  stepAsksName: () => false,
  usernameStepCopy: () => ({ title: "", subtitle: "" }),
  UsernameStep: () => null,
}));

import { PersonalGate } from "@/components/PersonalGate";

type Answers = { status?: unknown; agreement?: unknown; me?: unknown };
/** Each answer is a value (resolves) or an Error (rejects). */
let answers: Answers;
const reply = (v: unknown) => (v instanceof Error ? Promise.reject(v) : Promise.resolve(v));

beforeEach(() => {
  pathname = "/";
  user = { uid: "u1", displayName: "Sam Lee", email: "s@example.com" };
  localStorage.clear();
  answers = { status: { complete: true, required: false }, agreement: { agreed: true }, me: {} };
  callApi.mockReset();
  callApi.mockImplementation((_u: unknown, path: string) => {
    if (path === "/v1/me/personal/status") return reply(answers.status);
    if (path === "/v1/me/personal") return reply(answers.me);
    return reply(answers.agreement);
  });
});

const renderGate = () =>
  render(
    <PersonalGate>
      <p>APP-CONTENT</p>
    </PersonalGate>,
  );

describe("PersonalGate fails closed", () => {
  it("shows the app when status and agreement are fine", async () => {
    renderGate();
    expect(await screen.findByText("APP-CONTENT")).toBeInTheDocument();
    await waitFor(() => expect(callApi).toHaveBeenCalledTimes(2));
    expect(screen.queryByText("Couldn't check your account")).toBeNull();
  });

  it("blocks with a retry when the status call fails", async () => {
    answers.status = new Error("500");
    renderGate();
    expect(await screen.findByText("Couldn't check your account")).toBeInTheDocument();
    expect(screen.queryByText("APP-CONTENT")).toBeNull();
    expect(screen.getByRole("button", { name: "Try again" })).toBeInTheDocument();
  });

  it("blocks when the agreement call fails", async () => {
    answers.agreement = new Error("500");
    renderGate();
    expect(await screen.findByText("Couldn't check your account")).toBeInTheDocument();
    expect(screen.queryByText("APP-CONTENT")).toBeNull();
  });

  it("a failed check is not bypassed by an earlier prompt dismissal", async () => {
    localStorage.setItem("stall10.personalPrompt.u1", "1");
    answers.status = new Error("500");
    renderGate();
    expect(await screen.findByText("Couldn't check your account")).toBeInTheDocument();
    expect(screen.queryByText("APP-CONTENT")).toBeNull();
  });

  it("shows the app after a retry succeeds", async () => {
    answers.status = new Error("500");
    renderGate();
    const retry = await screen.findByRole("button", { name: "Try again" });
    answers.status = { complete: true, required: false };
    fireEvent.click(retry);
    expect(await screen.findByText("APP-CONTENT")).toBeInTheDocument();
  });

  it("stays blocked while the retry keeps failing", async () => {
    answers.agreement = new Error("500");
    renderGate();
    fireEvent.click(await screen.findByRole("button", { name: "Try again" }));
    await waitFor(() => expect(callApi).toHaveBeenCalledTimes(3));
    expect(await screen.findByText("Couldn't check your account")).toBeInTheDocument();
    expect(screen.queryByText("APP-CONTENT")).toBeNull();
  });

  it("still blocks a new account that is required and missing", async () => {
    answers.status = { complete: false, required: true };
    renderGate();
    expect(await screen.findByRole("button", { name: "DETAILS-FORM" })).toBeInTheDocument();
    expect(screen.queryByText("APP-CONTENT")).toBeNull();
  });

  it("still asks for Terms when not agreed", async () => {
    answers.agreement = { agreed: false };
    renderGate();
    expect(await screen.findByText("AGREE-TERMS")).toBeInTheDocument();
  });

  it("keeps the legal pages readable when a check fails", async () => {
    pathname = "/terms";
    answers.status = new Error("500");
    renderGate();
    expect(await screen.findByText("APP-CONTENT")).toBeInTheDocument();
  });

  it("blocks when the agreement answers 200 with a malformed body", async () => {
    for (const bad of [{}, { agreed: "yes" }, null, "ok"]) {
      answers.agreement = bad;
      const { unmount } = renderGate();
      expect(await screen.findByText("Couldn't check your account")).toBeInTheDocument();
      expect(screen.queryByText("APP-CONTENT")).toBeNull();
      unmount();
    }
  });

  it("blocks when the status answers 200 with a malformed body", async () => {
    for (const bad of [{}, { complete: true }, { required: false }, { complete: "true", required: false }, null]) {
      answers.status = bad;
      const { unmount } = renderGate();
      expect(await screen.findByText("Couldn't check your account")).toBeInTheDocument();
      expect(screen.queryByText("APP-CONTENT")).toBeNull();
      unmount();
    }
  });

  it("ignores a stale answer when the account changes mid-request", async () => {
    let lateStatus!: (v: unknown) => void;
    const first = new Promise((r) => (lateStatus = r));
    callApi.mockImplementation((u: { uid: string }, path: string) => {
      if (path === "/v1/me/personal/status") return u.uid === "u1" ? first : Promise.resolve({ complete: true, required: false });
      return Promise.resolve({ agreed: true });
    });
    const view = renderGate();
    user = { uid: "u2", displayName: "Alex Kim", email: "a@example.com" };
    view.rerender(
      <PersonalGate>
        <p>APP-CONTENT</p>
      </PersonalGate>,
    );
    expect(await screen.findByText("APP-CONTENT")).toBeInTheDocument();
    // The first account's slow answer would block; it must be dropped.
    lateStatus({ complete: false, required: true });
    await new Promise((r) => setTimeout(r, 20));
    expect(screen.queryByRole("button", { name: "DETAILS-FORM" })).toBeNull();
    expect(screen.getByText("APP-CONTENT")).toBeInTheDocument();
  });

  it("blocks when the refresh after finishing sign-up fails", async () => {
    answers.status = { complete: false, required: true };
    renderGate();
    const finish = await screen.findByRole("button", { name: "DETAILS-FORM" });
    answers.status = new Error("500");
    fireEvent.click(finish);
    expect(await screen.findByText("Couldn't check your account")).toBeInTheDocument();
    expect(screen.queryByText("APP-CONTENT")).toBeNull();
    expect(screen.queryByRole("button", { name: "DETAILS-FORM" })).toBeNull();
  });
});
