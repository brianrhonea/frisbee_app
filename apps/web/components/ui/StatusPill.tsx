import type { ReactNode } from "react";
import "./ui.css";

/**
 * One pill for every status (Going, Open, Live, Captain, Needs you, ...), the
 * website's StatusPill and the app's counterpart: a soft tone fill with its
 * own dark/light text, a label and an optional icon. The label always says it,
 * so the tone is never the only signal.
 *
 * Tones: neutral (Maybe, Archived, Final), accent (Captain, Private, your
 * team), success (Going, Open, Paid), attention (Needs you, Pending, Overdue),
 * live (Live now) and error (Declined, Failed).
 */
export type StatusTone = "neutral" | "accent" | "success" | "attention" | "live" | "error";

/** Built-in icons; pass your own node for anything else. */
export type StatusIcon = "check" | "dot" | "alert";

const icons: Record<StatusIcon, ReactNode> = {
  check: (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M5 12l5 5L20 7" />
    </svg>
  ),
  dot: (
    <svg width="8" height="8" viewBox="0 0 8 8" aria-hidden="true">
      <circle cx="4" cy="4" r="4" fill="currentColor" />
    </svg>
  ),
  alert: (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M12 5v9M12 19v.01" />
    </svg>
  ),
};

export interface StatusPillProps {
  tone?: StatusTone;
  /** The words. A pill without a label is not accepted. */
  children: ReactNode;
  icon?: StatusIcon | ReactNode;
  /** Layout hooks from the caller (margins, alignment), not colours. */
  className?: string;
  title?: string;
}

export function StatusPill({ tone = "neutral", children, icon, className, title }: StatusPillProps) {
  const glyph = typeof icon === "string" && icon in icons ? icons[icon as StatusIcon] : icon;
  return (
    <span className={`ui-pill ui-pill-${tone}${className ? ` ${className}` : ""}`} title={title}>
      {glyph ? <span className="ui-pill-icon">{glyph}</span> : null}
      {children}
    </span>
  );
}
