/**
 * The classes of a button, for `<Link>` and `<a>` that should look like one.
 * A plain module (no "use client"), so server components can call it; the
 * Button component itself is a client component.
 */
export type ButtonVariant = "primary" | "secondary" | "ghost" | "destructive";
export type ButtonSize = "small" | "medium" | "large";

const variantClass: Record<ButtonVariant, string> = {
  primary: " btn-primary",
  secondary: "",
  ghost: " btn-ghost",
  destructive: " btn-destructive",
};
const sizeClass: Record<ButtonSize, string> = { small: " btn-small", medium: "", large: " btn-large" };

export function buttonClass({ variant = "secondary", size = "medium", className }: { variant?: ButtonVariant; size?: ButtonSize; className?: string } = {}) {
  return `btn${variantClass[variant]}${sizeClass[size]}${className ? ` ${className}` : ""}`;
}
