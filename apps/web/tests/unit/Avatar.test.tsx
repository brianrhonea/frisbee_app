import { describe, expect, it } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { Avatar, AvatarStack, TeamLogo } from "@/components/ui/Avatar";
import { Avatar as ReExported } from "@/components/Avatar";
import { TeamBadge } from "@/components/team/TeamBadge";

describe("Avatar (C4)", () => {
  it("shows the image when there is one, sized, with no alt text (decorative)", () => {
    const { container } = render(<Avatar name="Sam Rivera" url="https://example.test/a.png" size={48} />);
    const img = container.querySelector("img")!;
    expect(img).toHaveAttribute("src", "https://example.test/a.png");
    expect(img).toHaveAttribute("alt", "");
    expect(img).toHaveAttribute("width", "48");
    expect(img).toHaveClass("avatar");
  });

  it("falls back to the initial when the image fails to load", () => {
    const { container } = render(<Avatar name="Sam Rivera" url="https://example.test/gone.png" />);
    fireEvent.error(container.querySelector("img")!);
    expect(container.querySelector("img")).toBeNull();
    expect(screen.getByText("S")).toHaveClass("avatar");
  });

  it("gives a new address a fresh chance after a failure", () => {
    const { container, rerender } = render(<Avatar name="Sam" url="https://example.test/gone.png" />);
    fireEvent.error(container.querySelector("img")!);
    rerender(<Avatar name="Sam" url="https://example.test/new.png" />);
    expect(container.querySelector("img")).toHaveAttribute("src", "https://example.test/new.png");
  });

  it("shows one initial for a name and no image", () => {
    render(<Avatar name="sam rivera" />);
    expect(screen.getByText("S")).toBeInTheDocument();
  });

  it("shows a neutral glyph, not a question mark, with neither name nor image", () => {
    const { container } = render(<Avatar />);
    expect(container.querySelector("svg")).toHaveAttribute("aria-hidden", "true");
    expect(container).not.toHaveTextContent("?");
    const blank = render(<Avatar name="   " />);
    expect(blank.container.querySelector("svg")).not.toBeNull();
  });

  it("is hidden from assistive tech unless it has a label", () => {
    const { container, rerender } = render(<Avatar name="Sam" />);
    expect(container.firstElementChild).toHaveAttribute("aria-hidden", "true");
    rerender(<Avatar name="Sam" label="Sam Rivera" />);
    expect(screen.getByRole("img", { name: "Sam Rivera" })).toBeInTheDocument();
  });

  it("a labelled photo carries the label as its alt text", () => {
    render(<Avatar name="Sam" url="https://example.test/a.png" label="Sam Rivera" />);
    expect(screen.getByRole("img", { name: "Sam Rivera" })).toHaveAttribute("src", "https://example.test/a.png");
  });

  it("is still exported from its old place", () => {
    expect(ReExported).toBe(Avatar);
  });
});

describe("TeamLogo (C4)", () => {
  it.each(["team", "community", "organization"] as const)("%s has its own kind class and two initials", (kind) => {
    render(<TeamLogo name="Seattle Ultimate" kind={kind} size={40} />);
    expect(screen.getByText("SU")).toHaveClass("ui-logo", `ui-logo-${kind}`);
  });

  it("defaults to a team", () => {
    render(<TeamLogo name="Sockeye" />);
    expect(screen.getByText("SO")).toHaveClass("ui-logo-team");
  });

  it("shows the logo image, then the initials if it fails", () => {
    const { container } = render(<TeamLogo name="Sockeye" url="https://example.test/l.png" />);
    const img = container.querySelector("img")!;
    expect(img).toHaveClass("ui-logo");
    fireEvent.error(img);
    expect(screen.getByText("SO")).toBeInTheDocument();
  });

  it("an empty name still shows something, never nothing", () => {
    const { container } = render(<TeamLogo name="" />);
    expect(container).toHaveTextContent("TE");
  });

  it("one colour per kind: the same name in two teams of one kind looks the same", () => {
    const { container } = render(
      <>
        <TeamLogo name="Alpha" />
        <TeamLogo name="Zulu" />
      </>,
    );
    const [a, b] = [...container.querySelectorAll(".ui-logo")];
    expect(a!.className).toBe(b!.className);
    expect(a!.getAttribute("style")).toBe(b!.getAttribute("style"));
    expect(a!.getAttribute("style")).not.toMatch(/color|--tint/);
  });

  it("TeamBadge is the same logo", () => {
    render(<TeamBadge name="Seattle Ultimate" kind="community" />);
    expect(screen.getByText("SU")).toHaveClass("ui-logo-community");
  });
});

describe("AvatarStack (C4)", () => {
  const people = ["Ann Lee", "Bo Chen", "Cy Diaz", "Di Evans", "Ed Fox", "Fay Gu"].map((name, i) => ({ id: `u${i}`, name }));

  it("shows up to max avatars and +N for the rest", () => {
    const { container } = render(<AvatarStack people={people} max={4} />);
    expect(container.querySelectorAll(".avatar")).toHaveLength(4);
    expect(screen.getByText("+2")).toHaveClass("avatar-stack-more");
  });

  it("shows no +N when everyone fits", () => {
    const { container } = render(<AvatarStack people={people.slice(0, 3)} max={4} />);
    expect(container.querySelectorAll(".avatar")).toHaveLength(3);
    expect(container.querySelector(".avatar-stack-more")).toBeNull();
  });

  it("an empty stack is empty", () => {
    const { container } = render(<AvatarStack people={[]} />);
    expect(container.querySelectorAll(".avatar")).toHaveLength(0);
    expect(container.querySelector(".avatar-stack-more")).toBeNull();
  });

  it("is decorative by default and one named image with a label", () => {
    const { container, rerender } = render(<AvatarStack people={people} />);
    expect(container.firstElementChild).toHaveAttribute("aria-hidden", "true");
    rerender(<AvatarStack people={people} label="6 members" />);
    expect(screen.getByRole("img", { name: "6 members" })).toBeInTheDocument();
  });

  it("sizes the avatars and the +N to the same size", () => {
    const { container } = render(<AvatarStack people={people} max={2} size={20} />);
    expect(container.querySelector(".avatar")).toHaveAttribute("style", expect.stringContaining("width: 20px"));
    expect(container.querySelector(".avatar-stack-more")).toHaveAttribute("style", expect.stringContaining("width: 20px"));
  });
});
