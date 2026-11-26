import { readFileSync } from "node:fs";
import { join } from "node:path";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { SegmentedTabs, type TabItem } from "@/components/ui/SegmentedTabs";
import { FilterChips, type ChipItem } from "@/components/ui/FilterChips";

const css = readFileSync(join(__dirname, "../../components/ui/ui.css"), "utf8");
const items: TabItem[] = [
  { id: "a", label: "Alpha" },
  { id: "b", label: "Beta" },
  { id: "c", label: "Gamma" },
];

function Tabs({ list = items, variant, onChange }: { list?: TabItem[]; variant?: "segmented" | "underline"; onChange?: (id: string) => void }) {
  const [v, setV] = useState("a");
  return (
    <SegmentedTabs
      label="Demo"
      items={list}
      value={v}
      variant={variant}
      onChange={(id) => {
        setV(id);
        onChange?.(id);
      }}
      tabId={(id) => `t-${id}`}
      panelId={(id) => `p-${id}`}
    />
  );
}
const tab = (name: string) => screen.getByRole("tab", { name });

describe("SegmentedTabs (C3)", () => {
  it("is a tablist named by its label, with one selected tab", () => {
    render(<Tabs />);
    expect(screen.getByRole("tablist", { name: "Demo" })).toBeInTheDocument();
    expect(screen.getAllByRole("tab")).toHaveLength(3);
    expect(tab("Alpha")).toHaveAttribute("aria-selected", "true");
    expect(tab("Beta")).toHaveAttribute("aria-selected", "false");
  });

  it("only the selected tab is a Tab stop (roving tabindex)", () => {
    render(<Tabs />);
    expect(tab("Alpha")).toHaveAttribute("tabindex", "0");
    expect(tab("Beta")).toHaveAttribute("tabindex", "-1");
    expect(tab("Gamma")).toHaveAttribute("tabindex", "-1");
  });

  it("clicking selects", () => {
    const onChange = vi.fn();
    render(<Tabs onChange={onChange} />);
    fireEvent.click(tab("Gamma"));
    expect(onChange).toHaveBeenCalledWith("c");
    expect(tab("Gamma")).toHaveAttribute("aria-selected", "true");
  });

  it("ArrowRight and ArrowLeft move focus and select, and wrap", () => {
    render(<Tabs />);
    tab("Alpha").focus();
    fireEvent.keyDown(tab("Alpha"), { key: "ArrowRight" });
    expect(tab("Beta")).toHaveFocus();
    expect(tab("Beta")).toHaveAttribute("aria-selected", "true");
    fireEvent.keyDown(tab("Beta"), { key: "ArrowLeft" });
    fireEvent.keyDown(tab("Alpha"), { key: "ArrowLeft" });
    expect(tab("Gamma")).toHaveFocus();
    expect(tab("Gamma")).toHaveAttribute("aria-selected", "true");
    fireEvent.keyDown(tab("Gamma"), { key: "ArrowRight" });
    expect(tab("Alpha")).toHaveFocus();
  });

  it("Home and End jump to the first and last", () => {
    render(<Tabs />);
    tab("Alpha").focus();
    fireEvent.keyDown(tab("Alpha"), { key: "End" });
    expect(tab("Gamma")).toHaveFocus();
    expect(tab("Gamma")).toHaveAttribute("aria-selected", "true");
    fireEvent.keyDown(tab("Gamma"), { key: "Home" });
    expect(tab("Alpha")).toHaveFocus();
    expect(tab("Alpha")).toHaveAttribute("aria-selected", "true");
  });

  it("skips a disabled tab", () => {
    render(<Tabs list={[items[0]!, { ...items[1]!, disabled: true }, items[2]!]} />);
    tab("Alpha").focus();
    fireEvent.keyDown(tab("Alpha"), { key: "ArrowRight" });
    expect(tab("Gamma")).toHaveFocus();
    expect(tab("Beta")).toBeDisabled();
  });

  it("ignores other keys and modified arrows", () => {
    const onChange = vi.fn();
    render(<Tabs onChange={onChange} />);
    tab("Alpha").focus();
    fireEvent.keyDown(tab("Alpha"), { key: "a" });
    fireEvent.keyDown(tab("Alpha"), { key: "ArrowRight", altKey: true });
    fireEvent.keyDown(tab("Alpha"), { key: "ArrowDown" });
    expect(onChange).not.toHaveBeenCalled();
    expect(tab("Alpha")).toHaveFocus();
  });

  it("names the tab and the panel it controls (only for the selected tab)", () => {
    render(<Tabs />);
    expect(tab("Alpha")).toHaveAttribute("id", "t-a");
    expect(tab("Alpha")).toHaveAttribute("aria-controls", "p-a");
    expect(tab("Beta")).not.toHaveAttribute("aria-controls");
  });

  it("with no matching value the first tab stays reachable", () => {
    render(<SegmentedTabs label="x" items={items} value="zzz" onChange={() => {}} />);
    expect(tab("Alpha")).toHaveAttribute("tabindex", "0");
    expect(screen.getAllByRole("tab").filter((t) => t.getAttribute("aria-selected") === "true")).toHaveLength(0);
  });

  it.each(["segmented", "underline"] as const)("%s variant carries its class", (variant) => {
    render(<Tabs variant={variant} />);
    expect(screen.getByRole("tablist")).toHaveClass("ui-tabs", `ui-tabs-${variant}`);
  });

  it("keeps the caller's layout class", () => {
    render(<SegmentedTabs label="x" className="schedule-view" items={items} value="a" onChange={() => {}} />);
    expect(screen.getByRole("tablist")).toHaveClass("schedule-view");
  });

  it("the bar scrolls instead of wrapping, and selection is not colour alone", () => {
    expect(css).toMatch(/\.ui-tabs\s*\{[^}]*overflow-x:\s*auto/);
    expect(css).toMatch(/\.ui-face\s*\{[^}]*white-space:\s*nowrap/);
    expect(css).toMatch(/\.ui-tabs-segmented > button\[aria-selected="true"\]\s*\{[^}]*font-weight:\s*700/);
    expect(css).toMatch(/\.ui-tabs-segmented > button\[aria-selected="true"\] \.ui-face\s*\{[^}]*var\(--chip-on\)/);
  });

  it("each tab is a 48 px target", () => {
    expect(css).toMatch(/\.ui-tabs > button\s*\{[^}]*min-height:\s*48px/);
  });
});

const chips: ChipItem[] = [
  { id: "all", label: "All" },
  { id: "games", label: "Games" },
  { id: "practice", label: "Practices" },
];
const chip = (name: string) => screen.getByRole("radio", { name });

function One({ onChange }: { onChange?: (id: string) => void }) {
  const [v, setV] = useState("all");
  return (
    <FilterChips
      label="Show"
      items={chips}
      value={v}
      onChange={(id) => {
        setV(id);
        onChange?.(id);
      }}
    />
  );
}

describe("FilterChips (C3), one choice", () => {
  it("is a radio group with one checked chip and one Tab stop", () => {
    render(<One />);
    expect(screen.getByRole("radiogroup", { name: "Show" })).toBeInTheDocument();
    expect(chip("All")).toHaveAttribute("aria-checked", "true");
    expect(chip("Games")).toHaveAttribute("aria-checked", "false");
    expect(chip("All")).toHaveAttribute("tabindex", "0");
    expect(chip("Games")).toHaveAttribute("tabindex", "-1");
  });

  it("click chooses", () => {
    const onChange = vi.fn();
    render(<One onChange={onChange} />);
    fireEvent.click(chip("Games"));
    expect(onChange).toHaveBeenCalledWith("games");
    expect(chip("Games")).toHaveAttribute("aria-checked", "true");
  });

  it("arrows (either axis), Home and End move and choose, and wrap", () => {
    render(<One />);
    chip("All").focus();
    fireEvent.keyDown(chip("All"), { key: "ArrowRight" });
    expect(chip("Games")).toHaveFocus();
    expect(chip("Games")).toHaveAttribute("aria-checked", "true");
    fireEvent.keyDown(chip("Games"), { key: "ArrowDown" });
    expect(chip("Practices")).toHaveFocus();
    fireEvent.keyDown(chip("Practices"), { key: "ArrowRight" });
    expect(chip("All")).toHaveFocus();
    fireEvent.keyDown(chip("All"), { key: "ArrowUp" });
    expect(chip("Practices")).toHaveFocus();
    fireEvent.keyDown(chip("Practices"), { key: "Home" });
    expect(chip("All")).toHaveFocus();
    fireEvent.keyDown(chip("All"), { key: "End" });
    expect(chip("Practices")).toHaveAttribute("aria-checked", "true");
  });

  it("a disabled chip cannot be chosen", () => {
    const onChange = vi.fn();
    render(<FilterChips label="x" items={[chips[0]!, { ...chips[1]!, disabled: true }]} value="all" onChange={onChange} />);
    fireEvent.click(chip("Games"));
    expect(onChange).not.toHaveBeenCalled();
  });

  it("the on chip is filled indigo; the bar scrolls", () => {
    expect(css).toMatch(/\.ui-chips > button\[aria-checked="true"\] \.ui-face\s*\{[^}]*var\(--chip-on\)/);
    expect(css).toMatch(/\.ui-chips > button\[aria-pressed="true"\] \.ui-face/);
  });
});

describe("FilterChips, several choices", () => {
  function Many({ onChange }: { onChange?: (ids: string[]) => void }) {
    const [v, setV] = useState<string[]>(["games"]);
    return (
      <FilterChips
        multiple
        label="Types"
        items={chips}
        value={v}
        onChange={(ids) => {
          setV(ids);
          onChange?.(ids);
        }}
      />
    );
  }

  it("is a group of toggle buttons with aria-pressed", () => {
    render(<Many />);
    expect(screen.getByRole("group", { name: "Types" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Games" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("button", { name: "All" })).toHaveAttribute("aria-pressed", "false");
  });

  it("toggles each chip on and off", () => {
    const onChange = vi.fn();
    render(<Many onChange={onChange} />);
    fireEvent.click(screen.getByRole("button", { name: "Practices" }));
    expect(onChange).toHaveBeenLastCalledWith(["games", "practice"]);
    fireEvent.click(screen.getByRole("button", { name: "Games" }));
    expect(onChange).toHaveBeenLastCalledWith(["practice"]);
  });
});
