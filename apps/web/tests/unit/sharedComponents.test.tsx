import { beforeAll, describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen, within } from "@testing-library/react";
import { ConfirmDialog, ConfirmProvider, useConfirm } from "@/components/ui/ConfirmDialog";
import { CoverHeader } from "@/components/ui/CoverHeader";
import { DateBadge } from "@/components/ui/DateBadge";
import { EventCard } from "@/components/ui/EventCard";
import { SearchField, TextArea, TextField } from "@/components/ui/Fields";
import { ListRow } from "@/components/ui/ListRow";
import { EmptyState, ErrorState, LoadingState } from "@/components/ui/States";
import { SummaryTiles } from "@/components/ui/SummaryTiles";
import { useState } from "react";

// Sprint 3 C5-C10 (the website halves): every state and the keyboard behaviour.
// jsdom has no <dialog> modal support, so the open state is stubbed here; the
// focus trap, Esc and focus return are proved in a real browser (tests/e2e/ui-showcase.spec.ts).
beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal(this: HTMLDialogElement) {
    this.setAttribute("open", "");
  };
  HTMLDialogElement.prototype.close = function close(this: HTMLDialogElement) {
    this.removeAttribute("open");
  };
});

describe("CoverHeader", () => {
  it("names the page with the title and shows the actions", () => {
    render(<CoverHeader avatar={<span>pic</span>} title="Jamie Carter" subtitle="@jamie" actions={<button type="button">Edit</button>} />);
    expect(screen.getByRole("heading", { level: 1, name: "Jamie Carter" })).toBeInTheDocument();
    expect(screen.getByText("@jamie")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Edit" })).toBeInTheDocument();
  });
  it("with and without a cover photo; the photo is decoration", () => {
    const { container, rerender } = render(<CoverHeader avatar={null} title="T" coverUrl="data:image/png;base64,AAAA" />);
    expect(container.querySelector("img")).toHaveAttribute("alt", "");
    rerender(<CoverHeader avatar={null} title="T" />);
    expect(container.querySelector("img")).toBeNull();
  });
  it("the heading level can be lowered", () => {
    render(<CoverHeader avatar={null} title="T" as="h2" />);
    expect(screen.getByRole("heading", { level: 2 })).toBeInTheDocument();
  });
});

describe("SummaryTiles", () => {
  it("is a list of value and label, linked when given an href", () => {
    render(<SummaryTiles label="Numbers" items={[{ id: "a", label: "Teams", value: 3, href: "/teams" }, { id: "b", label: "Following", value: 12 }]} />);
    const list = screen.getByRole("list", { name: "Numbers" });
    expect(within(list).getAllByRole("listitem")).toHaveLength(2);
    expect(screen.getByRole("link", { name: "3 Teams" })).toHaveAttribute("href", "/teams");
    expect(screen.getByText("Following")).toBeInTheDocument();
    expect(screen.getAllByRole("link")).toHaveLength(1);
  });
});

describe("ListRow", () => {
  it("is a link with an href and a button with onClick", () => {
    const click = vi.fn();
    const { rerender } = render(<ListRow title="Alex" href="/players/a" />);
    expect(screen.getByRole("link", { name: "Alex" })).toHaveAttribute("href", "/players/a");
    rerender(<ListRow title="Alex" onClick={click} />);
    fireEvent.click(screen.getByRole("button", { name: "Alex" }));
    expect(click).toHaveBeenCalledTimes(1);
  });
  it("says unread and muted in words, not only colour", () => {
    render(<ListRow title="Morgan" unread muted onClick={() => undefined} />);
    expect(screen.getByRole("button", { name: "Morgan (Unread) (Muted)" })).toBeInTheDocument();
  });
  it("plain content has no link or button, and trailing controls stay outside the link", () => {
    render(<ListRow title="Plain" trailing={<button type="button">Go</button>} />);
    expect(screen.getByRole("button", { name: "Go" })).toBeInTheDocument();
    expect(screen.queryByRole("link")).toBeNull();
  });
});

describe("EventCard and DateBadge", () => {
  it("shows the RSVP answer, or Needs RSVP", () => {
    const { rerender } = render(<EventCard startsAt="2027-01-14T19:00:00Z" title="Practice" answer="going" />);
    expect(screen.getByText("Going")).toBeInTheDocument();
    rerender(<EventCard startsAt="2027-01-14T19:00:00Z" title="Practice" needsRsvp />);
    expect(screen.getByText("Needs RSVP")).toBeInTheDocument();
  });
  it("cancelled says so in words and drops the RSVP; recurring says Repeats", () => {
    render(<EventCard startsAt="2027-01-14T19:00:00Z" title="Practice" answer="going" cancelled recurring />);
    expect(screen.getByText("Cancelled")).toBeInTheDocument();
    expect(screen.getByText("Repeats")).toBeInTheDocument();
    expect(screen.queryByText("Going")).toBeNull();
    expect(screen.getByRole("article").getAttribute("data-cancelled")).toBe("true");
  });
  it("with an href the card is one link named by its title and details", () => {
    render(<EventCard startsAt="2027-01-14T19:00:00Z" title="Practice" meta="7 PM" href="/teams/t/schedule" />);
    expect(screen.getByRole("link", { name: /Practice/ })).toHaveAttribute("href", "/teams/t/schedule");
  });
  it("the date badge shows the weekday or the month over the day, and a dash without a date", () => {
    const { container, rerender } = render(<DateBadge startsAt="2027-01-14T12:00:00Z" />);
    expect(container.querySelector("small")?.textContent).toMatch(/^Thu$/);
    rerender(<DateBadge startsAt="2027-01-14T12:00:00Z" unit="month" />);
    expect(container.querySelector("small")?.textContent).toBe("Jan");
    expect(container.firstElementChild).toHaveClass("event-date");
    rerender(<DateBadge startsAt={null} />);
    expect(container.querySelector("b")?.textContent).toBe("–");
    expect(container.firstElementChild).toHaveAttribute("aria-hidden", "true");
  });
});

describe("LoadingState, EmptyState, ErrorState", () => {
  it("loading is a busy status", () => {
    render(<LoadingState label="Loading teams…" />);
    expect(screen.getByRole("status")).toHaveAttribute("aria-busy", "true");
    expect(screen.getByRole("status")).toHaveTextContent("Loading teams…");
  });
  it("empty shows a title, a reason and a next step", () => {
    render(<EmptyState title="No teams" action={<a href="/teams/new">Create</a>}>Join one.</EmptyState>);
    expect(screen.getByText("No teams")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Create" })).toBeInTheDocument();
  });
  it("error is an alert; retry is a button that calls back; none without onRetry", () => {
    const retry = vi.fn();
    const { rerender } = render(<ErrorState onRetry={retry}>Failed.</ErrorState>);
    expect(screen.getByRole("alert")).toHaveTextContent("Failed.");
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(retry).toHaveBeenCalledTimes(1);
    rerender(<ErrorState>Failed.</ErrorState>);
    expect(screen.queryByRole("button")).toBeNull();
  });
});

describe("TextField, TextArea, SearchField", () => {
  it("the label names the input; the hint and error describe it", () => {
    render(<TextField label="Username" hint="Letters only" error="Taken" />);
    const input = screen.getByLabelText("Username");
    expect(input).toHaveAttribute("aria-invalid", "true");
    expect(input.getAttribute("aria-describedby")).toContain("-hint");
    expect(input.getAttribute("aria-describedby")).toContain("-error");
    expect(screen.getByRole("alert")).toHaveTextContent("Taken");
  });
  it("without an error it is valid and has no alert", () => {
    render(<TextField label="Name" />);
    expect(screen.getByLabelText("Name")).not.toHaveAttribute("aria-invalid");
    expect(screen.queryByRole("alert")).toBeNull();
  });
  it("disabled and multi-line work", () => {
    render(
      <>
        <TextField label="Off" disabled />
        <TextArea label="About" error="Too long" />
      </>,
    );
    expect(screen.getByLabelText("Off")).toBeDisabled();
    expect(screen.getByLabelText("About")).toHaveAttribute("aria-invalid", "true");
  });
  it("search: typing, Clear, Esc and Enter", () => {
    const submit = vi.fn();
    function Host() {
      const [v, setV] = useState("");
      return <SearchField label="Search" value={v} onChange={setV} onSubmit={submit} />;
    }
    render(<Host />);
    const box = screen.getByRole("searchbox", { name: "Search" });
    expect(screen.queryByRole("button", { name: "Clear search" })).toBeNull();
    fireEvent.change(box, { target: { value: "ultimate" } });
    fireEvent.keyDown(box, { key: "Enter" });
    expect(submit).toHaveBeenCalledWith("ultimate");
    fireEvent.click(screen.getByRole("button", { name: "Clear search" }));
    expect(box).toHaveValue("");
    fireEvent.change(box, { target: { value: "x" } });
    fireEvent.keyDown(box, { key: "Escape" });
    expect(box).toHaveValue("");
  });
});

describe("ConfirmDialog", () => {
  it("confirms and cancels with its buttons", () => {
    const ok = vi.fn();
    const no = vi.fn();
    render(<ConfirmDialog title="Publish?" message="Teams are notified." confirmLabel="Publish" onConfirm={ok} onCancel={no} />);
    expect(screen.getByRole("dialog", { name: "Publish?", hidden: true })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Publish", hidden: true }));
    expect(ok).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByRole("button", { name: "Cancel", hidden: true }));
    expect(no).toHaveBeenCalledTimes(1);
  });
  it("the destructive variant paints the confirm button red and focuses Cancel first", () => {
    render(<ConfirmDialog title="Delete?" confirmLabel="Delete" destructive onConfirm={() => undefined} onCancel={() => undefined} />);
    expect(screen.getByRole("button", { name: "Delete", hidden: true })).toHaveClass("btn-destructive");
    expect(screen.getByRole("button", { name: "Cancel", hidden: true })).toHaveFocus();
  });
  it("a plain confirm focuses the confirm button", () => {
    render(<ConfirmDialog title="Go?" confirmLabel="Go" onConfirm={() => undefined} onCancel={() => undefined} />);
    expect(screen.getByRole("button", { name: "Go", hidden: true })).toHaveFocus();
  });
  it("Esc asks to cancel", () => {
    const no = vi.fn();
    render(<ConfirmDialog title="Delete?" onConfirm={() => undefined} onCancel={no} />);
    fireEvent(screen.getByRole("dialog", { hidden: true }), new Event("cancel", { cancelable: true }));
    expect(no).toHaveBeenCalledTimes(1);
  });
  it("useConfirm resolves true or false from the provider's dialog", async () => {
    let answer: boolean | null = null;
    function Host() {
      const confirm = useConfirm();
      return (
        <button
          type="button"
          onClick={async () => {
            answer = await confirm({ title: "Delete it?", message: "Gone.", confirmLabel: "Delete", destructive: true });
          }}
        >
          Ask
        </button>
      );
    }
    render(
      <ConfirmProvider>
        <Host />
      </ConfirmProvider>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Ask" }));
    fireEvent.click(await screen.findByRole("button", { name: "Delete", hidden: true }));
    await vi.waitFor(() => expect(answer).toBe(true));
    fireEvent.click(screen.getByRole("button", { name: "Ask" }));
    fireEvent.click(await screen.findByRole("button", { name: "Cancel", hidden: true }));
    await vi.waitFor(() => expect(answer).toBe(false));
  });
  it("without a provider useConfirm falls back to the browser's confirm", async () => {
    const spy = vi.spyOn(window, "confirm").mockReturnValue(true);
    let answer: boolean | null = null;
    function Host() {
      const confirm = useConfirm();
      return (
        <button type="button" onClick={async () => (answer = await confirm("Sure?"))}>
          Ask
        </button>
      );
    }
    render(<Host />);
    fireEvent.click(screen.getByRole("button", { name: "Ask" }));
    await vi.waitFor(() => expect(answer).toBe(true));
    expect(spy).toHaveBeenCalledWith("Sure?");
    spy.mockRestore();
  });
});
