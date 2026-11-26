import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { EmptyState, ErrorNote, LiveList, Loading } from "@/components/StatusViews";

// Checks the component-test setup on the site's shared state views (board
// task P6). The new components in Phase 2 get tests in this style.
describe("StatusViews", () => {
  it("loading is announced as a busy status", () => {
    render(<Loading />);
    const status = screen.getByRole("status");
    expect(status).toHaveTextContent("Loading…");
    expect(status).toHaveAttribute("aria-busy", "true");
  });

  it("an error is announced as an alert and offers a retry", () => {
    const retry = vi.fn();
    render(<ErrorNote onRetry={retry}>Couldn't load the schedule.</ErrorNote>);
    expect(screen.getByRole("alert")).toHaveTextContent("Couldn't load the schedule.");
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(retry).toHaveBeenCalledTimes(1);
  });

  it("an error without a retry has no button", () => {
    render(<ErrorNote>Offline.</ErrorNote>);
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("empty state shows its next step", () => {
    render(<EmptyState action={<a href="/teams/new">Create a team</a>}>No teams yet.</EmptyState>);
    expect(screen.getByText("No teams yet.")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Create a team" })).toHaveAttribute("href", "/teams/new");
  });

  it("a live list picks error, loading, empty or rows", () => {
    const rows = (r: string[]) => <ul>{r.map((x) => <li key={x}>{x}</li>)}</ul>;
    const { rerender } = render(<LiveList live={{ error: "Denied" }} empty="None">{rows}</LiveList>);
    expect(screen.getByRole("alert")).toHaveTextContent("Denied");
    rerender(<LiveList live={{ error: null }} empty="None">{rows}</LiveList>);
    expect(screen.getByRole("status")).toBeInTheDocument();
    rerender(<LiveList live={{ data: [], error: null }} empty="None">{rows}</LiveList>);
    expect(screen.getByText("None")).toBeInTheDocument();
    rerender(<LiveList live={{ data: ["Practice"], error: null }} empty="None">{rows}</LiveList>);
    expect(screen.getByRole("listitem")).toHaveTextContent("Practice");
  });
});
