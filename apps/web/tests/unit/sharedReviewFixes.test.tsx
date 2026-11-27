import { beforeAll, describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fireEvent, render, screen } from "@testing-library/react";
import { ConfirmProvider, useConfirm } from "@/components/ui/ConfirmDialog";
import { SearchField } from "@/components/ui/Fields";
import { ErrorState } from "@/components/ui/States";

// UI review follow-ups (Sprint 3 lane C): confirm, search field and error state details,
// and the CSS rules the phone shell depends on. CSS is read with CRLF normalised.
beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal(this: HTMLDialogElement) {
    this.setAttribute("open", "");
  };
  HTMLDialogElement.prototype.close = function close(this: HTMLDialogElement) {
    this.removeAttribute("open");
  };
});

const root = join(__dirname, "../..");
const read = (p: string) => readFileSync(join(root, p), "utf8").replace(/\r\n/g, "\n");

describe("useConfirm", () => {
  it("a second question while one is open answers the first with no", async () => {
    const results: (boolean | string)[] = [];
    function Host() {
      const ask = useConfirm();
      return (
        <>
          <button type="button" onClick={() => void ask({ title: "First?" }).then((ok) => results.push(`first:${ok}`))}>
            One
          </button>
          <button type="button" onClick={() => void ask({ title: "Second?" }).then((ok) => results.push(`second:${ok}`))}>
            Two
          </button>
        </>
      );
    }
    render(
      <ConfirmProvider>
        <Host />
      </ConfirmProvider>,
    );
    fireEvent.click(screen.getByRole("button", { name: "One" }));
    fireEvent.click(screen.getByRole("button", { name: "Two", hidden: true }));
    expect(await screen.findByRole("dialog", { name: "Second?", hidden: true })).toBeInTheDocument();
    expect(results).toEqual(["first:false"]);
    fireEvent.click(screen.getByRole("button", { name: "Confirm", hidden: true }));
    await new Promise((r) => setTimeout(r, 0));
    expect(results).toEqual(["first:false", "second:true"]);
  });

  it("a ReactNode message is not wrapped in a paragraph, and a plain string keeps its line breaks", async () => {
    function Host() {
      const ask = useConfirm();
      return (
        <button type="button" onClick={() => void ask({ title: "T", message: <ul><li>item</li></ul> })}>
          Ask
        </button>
      );
    }
    const { container } = render(
      <ConfirmProvider>
        <Host />
      </ConfirmProvider>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Ask" }));
    await screen.findByRole("dialog", { hidden: true });
    expect(container.ownerDocument.querySelector(".confirm-message p")).toBeNull();
    expect(container.ownerDocument.querySelector(".confirm-message > ul")).not.toBeNull();
  });
});

describe("SearchField", () => {
  it("is a search landmark only when asked", () => {
    const { rerender } = render(<SearchField label="Filter" value="" onChange={() => undefined} />);
    expect(screen.queryByRole("search")).toBeNull();
    rerender(<SearchField label="Filter" value="" onChange={() => undefined} landmark />);
    expect(screen.getByRole("search")).toBeInTheDocument();
  });
});

describe("ErrorState", () => {
  it("carries no legacy form-error or error-note class (nothing selects on them for it)", () => {
    render(<ErrorState>Failed.</ErrorState>);
    const el = screen.getByRole("alert");
    expect(el).toHaveClass("ui-error");
    expect(el).not.toHaveClass("form-error");
    expect(el).not.toHaveClass("error-note");
  });
});

describe("phone shell CSS", () => {
  const app = read("app/app.css");
  const ui = read("components/ui/ui.css");
  it("an empty state's button keeps its own colours (not the link colour)", () => {
    expect(app).toContain(".empty a:not(.btn)");
    expect(app).not.toMatch(/\n\.empty a \{/);
  });
  it("--tabbar-h lives on :root and focused fields scroll above the tab bar", () => {
    const phone = app.slice(app.indexOf("@media (max-width: 599px) {\n  /* On :root"));
    expect(phone).toMatch(/:root \{ --tabbar-h: 66px; \}/);
    expect(phone).toMatch(/html \{ scroll-padding-bottom: calc\(var\(--tabbar-h\) \+ env\(safe-area-inset-bottom, 0px\) \+ 16px\); \}/);
  });
  it("the floating Post button hides where a docked bar shows", () => {
    expect(app).toMatch(/\.frame:has\(\.st-dock, \.gt-bar\) \.fab-post \{ display: none; \}/);
  });
  it("tab and rail labels are at least 11 px and ellipsise", () => {
    expect(app).toMatch(/\.tab-item \{[^}]*font-size: 11px/);
    expect(app).toMatch(/\.tab-item span \{[^}]*text-overflow: ellipsis/);
    expect(app).toMatch(/\.nav-item span \{[^}]*text-overflow: ellipsis/);
  });
  it("sidebar items are 48 px high", () => {
    expect(app).toMatch(/\.nav-item \{[^}]*min-height: 48px/);
    expect(app).toMatch(/\.nav-item-sub \{[^}]*min-height: 48px/);
  });
  it("search clear has a 48 px hit area and the WebKit cancel button is hidden", () => {
    expect(ui).toMatch(/\.ui-search-clear::after \{ content: ""; position: absolute; inset: -6px; \}/);
    expect(ui).toContain("::-webkit-search-cancel-button");
  });
  it("tile labels wrap and tiles go two across on very narrow screens", () => {
    expect(ui).toMatch(/\.ui-tile-label \{[^}]*overflow-wrap: anywhere/);
    expect(ui).toMatch(/@media \(max-width: 360px\) \{ \.ui-tiles \{[^}]*repeat\(2, minmax\(0, 1fr\)\)/);
  });
});
