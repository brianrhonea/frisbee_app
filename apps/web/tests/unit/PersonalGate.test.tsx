import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const callApi = vi.fn();
let pathname = "/";
const user = { uid: "u1", displayName: "Sam Lee", email: "s@example.com" };

vi.mock("@/lib/client", () => ({ callApi: (...a: unknown[]) => callApi(...a) }));
vi.mock("@/lib/firebase", () => ({ deleteOwnAccount: vi.fn() }));
vi.mock("@/lib/live", () => ({ useLiveDoc: () => ({ data: { username: "sam" } }) }));
vi.mock("@/lib/signupDraft", () => ({ signupDraft: { takeBirthDate: () => undefined, takeName: () => undefined } }));
vi.mock("next/navigation", () => ({ usePathname: () => pathname }));
vi.mock("next/link", () => ({ default: ({ children, href }: { children: React.ReactNode; href: string }) => <a href={href}>{children}</a> }));
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => ({ user }) }));
vi.mock("@/components/AgreeTerms", () => ({ AgreeTerms: () => <p>AGREE-TERMS</p> }));
vi.mock("@/components/PersonalDetailsForm", () => ({ PersonalDetailsForm: () => <p>DETAILS-FORM</p> }));
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
    expect(await screen.findByText("DETAILS-FORM")).toBeInTheDocument();
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
});
