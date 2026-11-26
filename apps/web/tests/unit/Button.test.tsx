import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { Button, buttonClass, IconButton } from "@/components/ui/Button";

const root = join(__dirname, "../..");
const css = readFileSync(join(root, "app/site.css"), "utf8") + readFileSync(join(root, "app/app.css"), "utf8");

describe("Button (C2)", () => {
  it("is a type=button by default and passes props through", () => {
    render(<Button data-x="1">Save</Button>);
    const b = screen.getByRole("button", { name: "Save" });
    expect(b).toHaveAttribute("type", "button");
    expect(b).toHaveAttribute("data-x", "1");
  });

  it.each([
    ["primary", "btn-primary"],
    ["ghost", "btn-ghost"],
    ["destructive", "btn-destructive"],
  ] as const)("variant %s adds %s", (variant, cls) => {
    render(<Button variant={variant}>Go</Button>);
    expect(screen.getByRole("button")).toHaveClass("btn", cls);
  });

  it("secondary is the plain .btn", () => {
    render(<Button variant="secondary">Go</Button>);
    expect(screen.getByRole("button").className).toBe("btn");
  });

  it.each([
    ["small", "btn-small"],
    ["large", "btn-large"],
  ] as const)("size %s adds %s; medium adds nothing", (size, cls) => {
    const { rerender } = render(<Button size={size}>Go</Button>);
    expect(screen.getByRole("button")).toHaveClass(cls);
    rerender(<Button size="medium">Go</Button>);
    expect(screen.getByRole("button").className).toBe("btn");
  });

  it("keeps the caller's class", () => {
    render(<Button className="extra">Go</Button>);
    expect(screen.getByRole("button")).toHaveClass("btn", "extra");
  });

  it("calls onClick", () => {
    const onClick = vi.fn();
    render(<Button onClick={onClick}>Go</Button>);
    fireEvent.click(screen.getByRole("button"));
    expect(onClick).toHaveBeenCalledTimes(1);
  });

  it("disabled cannot be clicked", () => {
    const onClick = vi.fn();
    render(
      <Button disabled onClick={onClick}>
        Go
      </Button>,
    );
    expect(screen.getByRole("button")).toBeDisabled();
    fireEvent.click(screen.getByRole("button"));
    expect(onClick).not.toHaveBeenCalled();
  });

  it("loading is busy, ignores clicks and keeps focus", () => {
    const onClick = vi.fn();
    render(
      <Button loading onClick={onClick}>
        Saving
      </Button>,
    );
    const b = screen.getByRole("button", { name: "Saving" });
    expect(b).toHaveAttribute("aria-busy", "true");
    expect(b).toHaveAttribute("aria-disabled", "true");
    expect(b).not.toBeDisabled();
    b.focus();
    expect(b).toHaveFocus();
    fireEvent.click(b);
    expect(onClick).not.toHaveBeenCalled();
  });

  it("not loading has no busy or disabled attributes", () => {
    render(<Button>Go</Button>);
    expect(screen.getByRole("button")).not.toHaveAttribute("aria-busy");
    expect(screen.getByRole("button")).not.toHaveAttribute("aria-disabled");
  });

  it("an icon is hidden from assistive tech and the name is the label", () => {
    render(<Button icon={<i data-testid="ic" />}>Add</Button>);
    expect(screen.getByTestId("ic").parentElement).toHaveAttribute("aria-hidden", "true");
    expect(screen.getByRole("button", { name: "Add" })).toBeInTheDocument();
  });

  it("is a native button, so Tab, Space and Enter work (no key handlers to get wrong)", () => {
    render(<Button>Go</Button>);
    const b = screen.getByRole("button");
    expect(b.tagName).toBe("BUTTON");
    expect(b).not.toHaveAttribute("tabindex", "-1");
    b.focus();
    expect(b).toHaveFocus();
  });
});

describe("IconButton", () => {
  it("is named by its label and hides the glyph", () => {
    render(<IconButton label="Close">×</IconButton>);
    const b = screen.getByRole("button", { name: "Close" });
    expect(b).toHaveClass("icon-btn");
    expect(b.querySelector("[aria-hidden='true']")).not.toBeNull();
  });

  it("loading ignores clicks", () => {
    const onClick = vi.fn();
    render(
      <IconButton label="Refresh" loading onClick={onClick}>
        ↻
      </IconButton>,
    );
    fireEvent.click(screen.getByRole("button"));
    expect(onClick).not.toHaveBeenCalled();
    expect(screen.getByRole("button")).toHaveAttribute("aria-busy", "true");
  });

  it("calls onClick and honours disabled", () => {
    const onClick = vi.fn();
    const { rerender } = render(
      <IconButton label="Next" onClick={onClick}>
        ›
      </IconButton>,
    );
    fireEvent.click(screen.getByRole("button"));
    expect(onClick).toHaveBeenCalledTimes(1);
    rerender(
      <IconButton label="Next" disabled onClick={onClick}>
        ›
      </IconButton>,
    );
    fireEvent.click(screen.getByRole("button"));
    expect(onClick).toHaveBeenCalledTimes(1);
  });
});

describe("buttonClass for links", () => {
  it("builds the same classes", () => {
    expect(buttonClass()).toBe("btn");
    expect(buttonClass({ variant: "primary", size: "small", className: "x" })).toBe("btn btn-primary btn-small x");
  });
});

describe("button states exist in the stylesheets", () => {
  const has = (re: RegExp) => expect(css).toMatch(re);
  it("hover, pressed, disabled, busy, ghost, destructive, large", () => {
    has(/\.btn-primary:hover:not\(:disabled\)/);
    has(/\.btn:active:not\(:disabled\)/);
    has(/\.btn:disabled,\s*\.btn\[aria-disabled="true"\]/);
    has(/\.btn\[aria-busy="true"\]::before/);
    has(/\.btn-ghost\s*\{/);
    has(/\.btn-destructive,\s*\.btn-danger\s*\{[^}]*var\(--error\)/);
    has(/\.btn-large\s*\{[^}]*min-height:\s*52px/);
    has(/\.icon-btn:active:not\(:disabled\)/);
  });

  it("focus-visible has one ring for buttons and icon buttons", () => {
    has(/\.btn:focus-visible,\s*\.icon-btn:focus-visible/);
  });

  it("every size keeps a 48 px target (height or hit band)", () => {
    const num = (re: RegExp) => Number(re.exec(css)?.[1]);
    // The band is measured from the padding box, inside the 1 px border (2 px in all):
    // .btn 44 - 2 + 3 each side; .btn-small 36 - 2 + 7 each side; .icon-btn 36 + 6 each side (no border); large is 52.
    expect(num(/\.btn\s*\{[^}]*min-height:\s*(\d+)px/) - 2 + 2 * 3).toBeGreaterThanOrEqual(48);
    expect(num(/\.btn-small\s*\{[^}]*min-height:\s*(\d+)px/) - 2 + 2 * 7).toBeGreaterThanOrEqual(48);
    expect(num(/\.icon-btn\s*\{[^}]*height:\s*(\d+)px/) + 2 * 6).toBeGreaterThanOrEqual(48);
    expect(css).toMatch(/\.btn::after\s*\{[^}]*inset:\s*-3px 0/);
    expect(css).toMatch(/\.btn-small::after\s*\{[^}]*inset:\s*-7px 0/);
    expect(css).toMatch(/\.icon-btn::after\s*\{[^}]*inset:\s*-6px/);
  });
});
