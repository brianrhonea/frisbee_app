"use client";
import type { ButtonHTMLAttributes, MouseEvent, ReactNode } from "react";
import { type ButtonSize, type ButtonVariant, buttonClass } from "./buttonClass";

/**
 * The website's Button (the app's AppButton): primary, secondary, ghost and
 * destructive, small, medium and large, plus an icon button. One look for
 * every state: hover, pressed, focus-visible (the global ring), disabled and
 * loading. The styles are the `.btn*` and `.icon-btn` classes (site.css,
 * app.css); the target is at least 48 px high in every size.
 *
 * Loading keeps the button focusable (so focus is not lost mid-save), shows
 * a spinner and ignores clicks; `aria-busy` tells assistive tech. Use
 * [buttonClass] (buttonClass.ts, usable from server components) for a link
 * that should look like a button.
 */
export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  /** Saving or sending: spinner, no clicks, `aria-busy`. */
  loading?: boolean;
  /** Shown before the label (hidden from assistive tech: the label says it). */
  icon?: ReactNode;
}

export function Button({ variant, size, loading = false, icon, className, type = "button", onClick, children, ...rest }: ButtonProps) {
  function click(e: MouseEvent<HTMLButtonElement>) {
    if (loading) {
      e.preventDefault();
      return;
    }
    onClick?.(e);
  }
  return (
    <button
      {...rest}
      type={type}
      className={buttonClass({ variant, size, className })}
      aria-busy={loading || undefined}
      aria-disabled={loading || undefined}
      onClick={click}
    >
      {icon ? <span aria-hidden="true">{icon}</span> : null}
      {children}
    </button>
  );
}

export interface IconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "aria-label" | "children"> {
  /** What it does. Required: an icon alone has no name. */
  label: string;
  children: ReactNode;
  loading?: boolean;
}

export function IconButton({ label, children, loading = false, className, type = "button", onClick, ...rest }: IconButtonProps) {
  return (
    <button
      {...rest}
      type={type}
      aria-label={label}
      className={`icon-btn${className ? ` ${className}` : ""}`}
      aria-busy={loading || undefined}
      aria-disabled={loading || undefined}
      onClick={(e) => {
        if (loading) e.preventDefault();
        else onClick?.(e);
      }}
    >
      <span aria-hidden="true">{children}</span>
    </button>
  );
}
