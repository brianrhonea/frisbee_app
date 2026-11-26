import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import {
  MAX_REPORTS,
  MAX_STACK,
  buildPayload,
  installGlobalErrorReporting,
  redact,
  reportClientError,
  resetErrorReports,
} from "@/lib/errorReport";
import ErrorPage from "@/app/error";
import GlobalError from "@/app/global-error";

vi.mock("next/link", () => ({
  default: ({ href, children }: { href: string; children: React.ReactNode }) => <a href={href}>{children}</a>,
}));
// global-error imports the site's stylesheets.
vi.mock("@/app/site.css", () => ({}));

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  resetErrorReports();
  fetchMock = vi.fn(() => Promise.resolve(new Response(null, { status: 204 })));
  vi.stubGlobal("fetch", fetchMock);
  window.history.replaceState({}, "", "/teams/abc?token=secret&email=a@b.co#frag");
});
afterEach(() => vi.unstubAllGlobals());

const bodyOf = (i = 0) => JSON.parse(fetchMock.mock.calls[i][1].body as string);

describe("crash reporter payload", () => {
  it("sends message, stack, path only, release and digest to /v1/client-errors", () => {
    const e = Object.assign(new Error("boom"), { digest: "d123" });
    expect(reportClientError(e)).toBe(true);
    const [url, init] = fetchMock.mock.calls[0];
    expect(String(url)).toMatch(/\/v1\/client-errors$/);
    expect(init.method).toBe("POST");
    expect(init.keepalive).toBe(true);
    expect(init.credentials).toBe("omit");
    const p = bodyOf();
    expect(Object.keys(p).sort()).toEqual(["digest", "message", "release", "stack", "url"]);
    expect(p.message).toBe("boom");
    expect(p.digest).toBe("d123");
    expect(p.url).toBe("/teams/abc");
    expect(JSON.stringify(p)).not.toContain("secret");
    expect(JSON.stringify(p)).not.toContain("frag");
  });

  it("redacts emails, query strings, bearer tokens and long ids in message and stack", () => {
    const e = new Error("failed for jo@example.com at https://x.app/p?session=abc123");
    e.stack = "Error\n at f (https://x.app/_next/a.js?v=secretvalue:1:2)\n Bearer abc.def " + "k".repeat(40);
    const p = buildPayload(e);
    for (const text of [p.message, p.stack]) {
      expect(text).not.toContain("jo@example.com");
      expect(text).not.toContain("abc123");
      expect(text).not.toContain("secretvalue");
      expect(text).not.toContain("k".repeat(40));
    }
    expect(p.message).toContain("[email]");
    expect(redact("a?b=c")).toBe("a?b=c");
  });

  it("trims the stack to 8 KB", () => {
    const e = new Error("big");
    e.stack = "Error\n" + "at x (a.js:1:1)\n".repeat(2000);
    expect(buildPayload(e).stack.length).toBeLessThanOrEqual(MAX_STACK);
  });

  it("handles non-Error values and omits an empty digest", () => {
    const p = buildPayload({ weird: true });
    expect(p.message).toBe("Non-error value thrown");
    expect(p.stack).toBe("");
    expect("digest" in p).toBe(false);
  });
});

describe("dedupe, cap and silent failure", () => {
  it("reports the same error once per page load", () => {
    const first = new Error("same");
    const again = new Error("same");
    again.stack = first.stack; // the same failure at the same place
    expect(reportClientError(first)).toBe(true);
    expect(reportClientError(again)).toBe(false);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it(`stops after ${MAX_REPORTS} reports`, () => {
    for (let i = 0; i < 12; i++) reportClientError(new Error(`distinct ${i}`));
    expect(fetchMock).toHaveBeenCalledTimes(MAX_REPORTS);
  });

  it("stays silent when the endpoint 404s or the network fails", async () => {
    fetchMock.mockResolvedValueOnce(new Response("nope", { status: 404 }));
    expect(() => reportClientError(new Error("a"))).not.toThrow();
    fetchMock.mockRejectedValueOnce(new TypeError("offline"));
    expect(() => reportClientError(new Error("b"))).not.toThrow();
    fetchMock.mockImplementationOnce(() => {
      throw new Error("sync failure");
    });
    expect(reportClientError(new Error("c"))).toBe(false);
    await Promise.resolve();
  });

  it("falls back to sendBeacon when fetch is missing", () => {
    vi.stubGlobal("fetch", undefined);
    const beacon = vi.fn(() => true);
    Object.defineProperty(navigator, "sendBeacon", { value: beacon, configurable: true });
    expect(reportClientError(new Error("beacon"))).toBe(true);
    expect(beacon).toHaveBeenCalledTimes(1);
  });
});

describe("window listeners", () => {
  it("reports window errors and unhandled rejections, deduped, and can be removed", () => {
    const off = installGlobalErrorReporting();
    const err = new Error("uncaught");
    window.dispatchEvent(new ErrorEvent("error", { error: err, message: "uncaught" }));
    window.dispatchEvent(new ErrorEvent("error", { error: err, message: "uncaught" }));
    const rej = new Event("unhandledrejection") as Event & { reason?: unknown };
    rej.reason = new Error("rejected");
    window.dispatchEvent(rej);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    const removed = vi.spyOn(window, "removeEventListener");
    off();
    expect(removed.mock.calls.map((c) => c[0])).toEqual(["error", "unhandledrejection"]);
  });
});

describe("error pages", () => {
  it("error.tsx shows a message, retries, links home and reports once", () => {
    const retry = vi.fn();
    render(<ErrorPage error={new Error("page broke")} retry={retry} />);
    expect(screen.getByRole("alert")).toHaveTextContent("Something went wrong");
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(retry).toHaveBeenCalledTimes(1);
    expect(screen.getByRole("link", { name: "Go to the home page" })).toHaveAttribute("href", "/");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(bodyOf().message).toBe("page broke");
  });

  it("error.tsx still accepts the older reset prop", () => {
    const reset = vi.fn();
    render(<ErrorPage error={new Error("x")} reset={reset} />);
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(reset).toHaveBeenCalledTimes(1);
  });

  it("global-error.tsx renders its own document with retry, home link and a report", () => {
    const retry = vi.fn();
    const err = Object.assign(new Error("layout broke"), { digest: "g1" });
    // <html> inside a div is invalid DOM to jsdom; React warns, the content still renders.
    vi.spyOn(console, "error").mockImplementation(() => {});
    render(<GlobalError error={err} retry={retry} />);
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(retry).toHaveBeenCalledTimes(1);
    expect(screen.getByRole("link", { name: "Go to the home page" })).toHaveAttribute("href", "/");
    expect(bodyOf().digest).toBe("g1");
  });
});
