import { adultOnlyMessage, birthDateLockedMessage } from "@stall10/shared";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const callApi = vi.fn();
const deleteOwnAccount = vi.fn();
const signOut = vi.fn();
const sendEmailVerification = vi.fn();
let user: Record<string, unknown>;
let pathname = "/";

vi.mock("firebase/auth", () => ({
  signOut: (...a: unknown[]) => signOut(...a),
  sendEmailVerification: (...a: unknown[]) => sendEmailVerification(...a),
}));
vi.mock("@/lib/client", () => ({
  callApi: (...a: unknown[]) => callApi(...a),
  problem: (e: unknown, f: string) => (e instanceof Error ? e.message : f),
  ApiError: class ApiError extends Error {
    constructor(
      message: string,
      readonly status: number,
      readonly code?: string,
      readonly fields?: Record<string, string>,
    ) {
      super(message);
    }
  },
}));
vi.mock("@/lib/firebase", () => ({ deleteOwnAccount: (...a: unknown[]) => deleteOwnAccount(...a), firebaseAuth: () => ({}) }));
vi.mock("@/lib/live", () => ({ useLiveDoc: () => ({ data: { username: "sam" } }) }));
vi.mock("@/lib/signupDraft", () => ({ signupDraft: { takeBirthDate: () => undefined, takeName: () => undefined } }));
vi.mock("next/navigation", () => ({ usePathname: () => pathname }));
vi.mock("next/link", () => ({ default: ({ children, href }: { children: React.ReactNode; href: string }) => <a href={href}>{children}</a> }));
vi.mock("@/components/AuthProvider", () => ({ useAuth: () => ({ user }) }));
vi.mock("@/components/AgreeTerms", () => ({ AgreeTerms: () => <p>AGREE-TERMS</p> }));
vi.mock("@/components/SignUpSteps", () => ({ SignUpSteps: () => null }));
vi.mock("@/components/UsernameStep", () => ({
  stepAsksName: () => false,
  usernameStepCopy: () => ({ title: "", subtitle: "" }),
  UsernameStep: () => <p>USERNAME-STEP</p>,
}));

import { PersonalDetailsForm } from "@/components/PersonalDetailsForm";
import { PersonalGate } from "@/components/PersonalGate";
import { announceIncomplete, clearIncomplete } from "@/lib/accountGate";
import { ApiError } from "@/lib/client";

let status: unknown;
let me: unknown;
const renderGate = () =>
  render(
    <PersonalGate>
      <p>APP-CONTENT</p>
    </PersonalGate>,
  );

beforeEach(() => {
  pathname = "/";
  user = {
    uid: "u1",
    displayName: "Sam Lee",
    email: "s@example.com",
    emailVerified: true,
    reload: vi.fn(async () => {}),
    getIdToken: vi.fn(async () => "t"),
  };
  status = { complete: true, required: false };
  me = {};
  localStorage.clear();
  clearIncomplete();
  for (const f of [callApi, deleteOwnAccount, signOut, sendEmailVerification]) f.mockReset();
  callApi.mockImplementation(async (_u: unknown, path: string) => {
    if (path === "/v1/me/personal/status") return status;
    if (path === "/v1/me/personal") return me;
    return { agreed: true };
  });
});

describe("PersonalGate routes an unresolved account_incomplete", () => {
  it("email_unverified shows the verify page; I've verified reloads the user and refreshes the token", async () => {
    user.emailVerified = false;
    renderGate();
    await screen.findByText("APP-CONTENT");
    act(() => announceIncomplete(["email_unverified", "terms"]));
    expect(await screen.findByRole("heading", { name: "Verify your email" })).toBeInTheDocument();
    // Still unverified: says so, stays.
    fireEvent.click(screen.getByRole("button", { name: "I've verified" }));
    expect(await screen.findByText(/can't see that yet/)).toBeInTheDocument();
    expect(user.getIdToken).not.toHaveBeenCalledWith(true);
    // Verified now.
    (user.reload as ReturnType<typeof vi.fn>).mockImplementation(async () => {
      user.emailVerified = true;
    });
    fireEvent.click(screen.getByRole("button", { name: "I've verified" }));
    await waitFor(() => expect(user.getIdToken).toHaveBeenCalledWith(true));
    // Back to the app: the member repeats the action, and any still-missing step is announced again.
    expect(await screen.findByText("APP-CONTENT")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Verify your email" })).toBeNull();
  });

  it("resend sends the verification email", async () => {
    user.emailVerified = false;
    renderGate();
    await screen.findByText("APP-CONTENT");
    act(() => announceIncomplete(["email_unverified"]));
    fireEvent.click(await screen.findByRole("button", { name: "Resend email" }));
    await waitFor(() => expect(sendEmailVerification).toHaveBeenCalledWith(user));
    expect(await screen.findByText("Email sent. Check your inbox and spam folder.")).toBeInTheDocument();
  });

  it("terms shows the agreement step", async () => {
    renderGate();
    await screen.findByText("APP-CONTENT");
    act(() => announceIncomplete(["terms"]));
    expect(await screen.findByText("AGREE-TERMS")).toBeInTheDocument();
  });

  it("age shows About you, with a saved birth date read-only", async () => {
    me = { details: null, email: "s@example.com", signUpBirthDate: "1990-02-03" };
    renderGate();
    await screen.findByText("APP-CONTENT");
    act(() => announceIncomplete(["age"]));
    expect(await screen.findByRole("heading", { name: "About you" })).toBeInTheDocument();
    const birth = (await screen.findByLabelText(/Date of birth/)) as HTMLInputElement;
    expect(birth.readOnly).toBe(true);
    expect(birth.value).toBe("1990-02-03");
  });

  it("a saved birth date under 18 goes straight to the dead end", async () => {
    me = { details: null, email: "s@example.com", signUpBirthDate: "2015-02-03" };
    renderGate();
    await screen.findByText("APP-CONTENT");
    act(() => announceIncomplete(["age"]));
    expect(await screen.findByRole("heading", { name: "Stall 10 is for players 18 and older" })).toBeInTheDocument();
    expect(screen.getByText(adultOnlyMessage)).toBeInTheDocument();
    expect(screen.queryByRole("textbox")).toBeNull();
  });
});

describe("onboarding order (review F1)", () => {
  it("a new account is asked its birth date before any username step", async () => {
    status = { complete: false, required: true };
    renderGate();
    expect(await screen.findByRole("heading", { name: "About you" })).toBeInTheDocument();
    expect(screen.queryByText("USERNAME-STEP")).toBeNull();
  });
});

describe("adult-only dead end", () => {
  async function deadEnd() {
    me = { details: null, email: "s@example.com", signUpBirthDate: "2015-02-03" };
    renderGate();
    await screen.findByText("APP-CONTENT");
    act(() => announceIncomplete(["age"]));
    await screen.findByRole("heading", { name: "Stall 10 is for players 18 and older" });
  }

  it("offers sign out and delete account only", async () => {
    await deadEnd();
    fireEvent.click(screen.getByRole("button", { name: "Sign out" }));
    expect(signOut).toHaveBeenCalled();
  });

  it("delete account asks first, then removes the whole account", async () => {
    await deadEnd();
    fireEvent.click(screen.getByRole("button", { name: "Delete account" }));
    expect(deleteOwnAccount).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Yes, delete my account" }));
    await waitFor(() => expect(deleteOwnAccount).toHaveBeenCalledWith({ loginOnlyFallback: false }));
  });
});

describe("PersonalDetailsForm: adults only, read-only birth date", () => {
  const fill = () => {
    fireEvent.change(screen.getByLabelText("First name"), { target: { value: "Sam" } });
    fireEvent.change(screen.getByLabelText("Last name"), { target: { value: "Lee" } });
    fireEvent.change(screen.getByLabelText("Phone"), { target: { value: "+1 555 010 1234" } });
    fireEvent.change(screen.getByLabelText(/Gender/), { target: { value: "woman" } });
    fireEvent.change(screen.getByLabelText("Street address"), { target: { value: "1 Main St" } });
    fireEvent.change(screen.getByLabelText("City"), { target: { value: "Austin" } });
    fireEvent.change(screen.getByLabelText("State"), { target: { value: "TX" } });
    fireEvent.change(screen.getByLabelText("ZIP code"), { target: { value: "78701" } });
  };
  const setBirth = (v: string) => fireEvent.change(screen.getByLabelText(/Date of birth/), { target: { value: v } });

  it("has no guardian section, even for a minor's date", () => {
    render(<PersonalDetailsForm user={user as never} email="s@example.com" initial={null} />);
    setBirth("2015-01-01");
    expect(screen.queryByText("Parent or guardian")).toBeNull();
  });

  it("under 18 with onUnderAge: calls it and sends nothing", async () => {
    const onUnderAge = vi.fn();
    render(<PersonalDetailsForm user={user as never} email="s@example.com" initial={null} onUnderAge={onUnderAge} />);
    fill();
    setBirth("2015-01-01");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() => expect(onUnderAge).toHaveBeenCalled());
    expect(callApi).not.toHaveBeenCalled();
  });

  it("under 18 without onUnderAge: shows the adult-only message in the form", async () => {
    render(<PersonalDetailsForm user={user as never} email="s@example.com" initial={null} />);
    fill();
    setBirth("2015-01-01");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(await screen.findByText(adultOnlyMessage)).toBeInTheDocument();
    expect(callApi).not.toHaveBeenCalled();
  });

  it("a server 412 under-18 refusal goes to the dead end handler", async () => {
    const onUnderAge = vi.fn();
    callApi.mockRejectedValue(new ApiError(adultOnlyMessage, 412, "failed_precondition", { birthDate: adultOnlyMessage }));
    render(<PersonalDetailsForm user={user as never} email="s@example.com" initial={null} onUnderAge={onUnderAge} />);
    fill();
    setBirth("1990-01-01");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() => expect(onUnderAge).toHaveBeenCalled());
  });

  it("a locked birth date is read-only with a support hint, and a 412 locked shows the message and support address", async () => {
    const onUnderAge = vi.fn();
    callApi.mockRejectedValue(new ApiError(birthDateLockedMessage, 412, "failed_precondition", { birthDate: birthDateLockedMessage }));
    render(
      <PersonalDetailsForm
        user={user as never}
        email="s@example.com"
        initial={null}
        prefill={{ birthDate: "1990-01-01" }}
        birthDateLocked
        onUnderAge={onUnderAge}
      />,
    );
    const birth = screen.getByLabelText(/Date of birth/) as HTMLInputElement;
    expect(birth.readOnly).toBe(true);
    expect(screen.getByText(/support@stall10\.app/)).toBeInTheDocument();
    fill();
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() => expect(callApi).toHaveBeenCalled());
    expect(onUnderAge).not.toHaveBeenCalled();
    expect((await screen.findAllByText(new RegExp(birthDateLockedMessage.slice(0, 20)))).length).toBeGreaterThan(0);
  });

  it("the PUT body never carries a guardian", async () => {
    callApi.mockResolvedValue({});
    render(<PersonalDetailsForm user={user as never} email="s@example.com" initial={null} />);
    fill();
    setBirth("1990-01-01");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() => expect(callApi).toHaveBeenCalled());
    const body = callApi.mock.calls[0]![2].body as Record<string, unknown>;
    expect(body).not.toHaveProperty("guardian");
    expect(body.birthDate).toBe("1990-01-01");
  });
});
