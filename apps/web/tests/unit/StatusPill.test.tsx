import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { StatusPill, type StatusTone } from "@/components/ui/StatusPill";
import { NeedsPill, RsvpPill } from "@/components/RsvpPill";
import { entryTone, hostedTone } from "@/components/tournaments/tones";

const tones: StatusTone[] = ["neutral", "accent", "success", "attention", "live", "error"];
const css = readFileSync(join(__dirname, "../../components/ui/ui.css"), "utf8");

describe("StatusPill (C1)", () => {
  it.each(tones)("%s: shows its label as text and carries the tone class", (tone) => {
    render(<StatusPill tone={tone}>Label</StatusPill>);
    const pill = screen.getByText("Label");
    expect(pill).toHaveClass("ui-pill", `ui-pill-${tone}`);
  });

  it.each(tones)("%s: has a rule for its fill and text in ui.css", (tone) => {
    expect(css).toMatch(new RegExp(`\\.ui-pill-${tone}\\s*\\{[^}]*background:[^}]*color:`));
  });

  it("defaults to neutral", () => {
    render(<StatusPill>Archived</StatusPill>);
    expect(screen.getByText("Archived")).toHaveClass("ui-pill-neutral");
  });

  it("never relies on colour: the icon is hidden from assistive tech and the label stays", () => {
    const { container } = render(
      <StatusPill tone="success" icon="check">
        Going
      </StatusPill>,
    );
    expect(screen.getByText("Going")).toBeInTheDocument();
    const svg = container.querySelector("svg");
    expect(svg).toHaveAttribute("aria-hidden", "true");
  });

  it.each(["check", "dot", "alert"] as const)("built-in icon %s renders", (icon) => {
    const { container } = render(<StatusPill icon={icon}>Word</StatusPill>);
    expect(container.querySelector(".ui-pill-icon svg")).not.toBeNull();
  });

  it("accepts a custom icon node and no icon at all", () => {
    const { container, rerender } = render(<StatusPill icon={<i data-testid="custom" />}>Word</StatusPill>);
    expect(screen.getByTestId("custom")).toBeInTheDocument();
    rerender(<StatusPill>Word</StatusPill>);
    expect(container.querySelector(".ui-pill-icon")).toBeNull();
  });

  it("passes layout classes and a title through", () => {
    render(
      <StatusPill className="explore-mine" title="Why">
        Mine
      </StatusPill>,
    );
    const pill = screen.getByText("Mine");
    expect(pill).toHaveClass("explore-mine");
    expect(pill).toHaveAttribute("title", "Why");
  });
});

describe("RsvpPill on StatusPill", () => {
  it("going is a success pill with a check and the word", () => {
    const { container } = render(<RsvpPill answer="going" />);
    const pill = screen.getByText("Going");
    expect(pill).toHaveClass("ui-pill-success", "rsvp-pill", "going");
    expect(container.querySelector("svg")).not.toBeNull();
  });

  it("tournaments say Attending", () => {
    render(<RsvpPill answer="going" type="tournament" />);
    expect(screen.getByText("Attending")).toBeInTheDocument();
  });

  it("maybe and can't go are neutral", () => {
    render(
      <>
        <RsvpPill answer="maybe" />
        <RsvpPill answer="notGoing" />
      </>,
    );
    expect(screen.getByText("Maybe")).toHaveClass("ui-pill-neutral");
    expect(screen.getByText("Can't go")).toHaveClass("ui-pill-neutral", "notGoing");
  });

  it("unanswered shows Needs RSVP only when asked, in the attention tone", () => {
    const { container, rerender } = render(<RsvpPill />);
    expect(container).toBeEmptyDOMElement();
    rerender(<RsvpPill needs />);
    expect(screen.getByText("Needs RSVP")).toHaveClass("ui-pill-attention", "needs");
  });

  it("NeedsPill carries the same hooks", () => {
    render(<NeedsPill>Vote</NeedsPill>);
    expect(screen.getByText("Vote")).toHaveClass("ui-pill-attention", "rsvp-pill", "needs");
  });
});

describe("competition tones", () => {
  it("entries: accepted success, applied and invited accent, declined error, the rest neutral", () => {
    expect(entryTone("accepted")).toBe("success");
    expect(entryTone("applied")).toBe("accent");
    expect(entryTone("invited")).toBe("accent");
    expect(entryTone("declined")).toBe("error");
    expect(entryTone("waitlisted")).toBe("neutral");
    expect(entryTone("withdrawn")).toBe("neutral");
  });

  it("hosted status: registration success, live live, the rest neutral", () => {
    expect(hostedTone("registration")).toBe("success");
    expect(hostedTone("live")).toBe("live");
    expect(hostedTone("draft")).toBe("neutral");
    expect(hostedTone("finished")).toBe("neutral");
  });
});
