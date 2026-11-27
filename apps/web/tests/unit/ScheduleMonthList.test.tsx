import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { ScheduleMonthList } from "@/components/ScheduleMonthList";

const label = (d: Date) => d.toLocaleDateString("en-US", { weekday: "long", month: "short", day: "numeric" });
const days = [3, 10, 17].map((n) => ({ day: new Date(2026, 10, n), items: [`event on ${n}`] }));
const row = (s: string) => <li key={s}>{s}</li>;

describe("Schedule Month list (S4 C1)", () => {
  it("lists every day with entries, grouped by day, in order", () => {
    render(<ScheduleMonthList days={days} picked={new Date(2026, 10, 1)} label={label} renderRow={row} />);
    const sections = screen.getAllByRole("heading", { level: 3 });
    expect(sections.map((h) => h.textContent)).toEqual(["Tuesday, Nov 3", "Tuesday, Nov 10", "Tuesday, Nov 17"]);
    expect(screen.getByRole("region", { name: "Events this month" })).toBeInTheDocument();
  });

  it("highlights the picked day", () => {
    render(<ScheduleMonthList days={days} picked={new Date(2026, 10, 10)} label={label} renderRow={row} />);
    expect(screen.getByRole("region", { name: "Tuesday, Nov 10" })).toHaveClass("picked");
    expect(screen.getByRole("region", { name: "Tuesday, Nov 3" })).not.toHaveClass("picked");
  });

  it("goes to the next day with events when the picked day has none", () => {
    render(<ScheduleMonthList days={days} picked={new Date(2026, 10, 11)} label={label} renderRow={row} />);
    expect(screen.getByRole("region", { name: "Tuesday, Nov 17" })).toHaveClass("picked");
  });

  it("scrolls the list box, not the page, to the target day", () => {
    const top = Object.getOwnPropertyDescriptor(HTMLElement.prototype, "offsetTop");
    // A fake layout: each day section is 100 px below the one before; the box starts at 20.
    Object.defineProperty(HTMLElement.prototype, "offsetTop", {
      configurable: true,
      get(this: HTMLElement) {
        if (this.classList.contains("sched-month-list")) return 20;
        const i = this.getAttribute("data-day") ? days.findIndex((d) => String(d.day.getTime()) === this.getAttribute("data-day")) : -1;
        return i < 0 ? 0 : 20 + i * 100;
      },
    });
    try {
      const { container } = render(<ScheduleMonthList days={days} picked={new Date(2026, 10, 17)} label={label} renderRow={row} />);
      expect(container.querySelector<HTMLElement>(".sched-month-list")!.scrollTop).toBe(200);
    } finally {
      if (top) Object.defineProperty(HTMLElement.prototype, "offsetTop", top);
    }
  });

  it("highlights nothing when no later day has entries, and says so when the month is empty", () => {
    const { container, rerender } = render(<ScheduleMonthList days={days} picked={new Date(2026, 10, 20)} label={label} renderRow={row} />);
    expect(container.querySelector(".picked")).toBeNull();
    rerender(<ScheduleMonthList days={[]} picked={new Date(2026, 10, 20)} label={label} renderRow={row} />);
    expect(screen.getByText("Nothing scheduled this month")).toBeInTheDocument();
  });
});
