"use client";
import { type InputHTMLAttributes, type KeyboardEvent, type TextareaHTMLAttributes, useId } from "react";
import { NavIcon } from "../NavIcons";
import "./ui.css";

/**
 * A labelled text input (the app's TextField): the label above it (always
 * visible, never a placeholder), an optional hint, and an error that is read
 * out when it appears (`role="alert"`) and tied to the input
 * (`aria-invalid`, `aria-describedby`). The border is 3:1 against the page
 * (`--line-2`), the target 48 px.
 */
type Shared = { label: string; hint?: string; error?: string | null };

export function TextField({ label, hint, error, id, className, ...rest }: Shared & InputHTMLAttributes<HTMLInputElement>) {
  const auto = useId();
  const fid = id ?? auto;
  const describedBy = [hint ? `${fid}-hint` : "", error ? `${fid}-error` : ""].filter(Boolean).join(" ") || undefined;
  return (
    <div className={`ui-field${error ? " ui-field-error" : ""}${className ? ` ${className}` : ""}`}>
      <label htmlFor={fid}>{label}</label>
      {hint ? (
        <small id={`${fid}-hint`} className="ui-field-hint">
          {hint}
        </small>
      ) : null}
      <input {...rest} id={fid} aria-invalid={error ? true : undefined} aria-describedby={describedBy} />
      {error ? (
        <p id={`${fid}-error`} className="ui-field-error-text" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  );
}

/** [TextField] for several lines. */
export function TextArea({ label, hint, error, id, className, ...rest }: Shared & TextareaHTMLAttributes<HTMLTextAreaElement>) {
  const auto = useId();
  const fid = id ?? auto;
  const describedBy = [hint ? `${fid}-hint` : "", error ? `${fid}-error` : ""].filter(Boolean).join(" ") || undefined;
  return (
    <div className={`ui-field${error ? " ui-field-error" : ""}${className ? ` ${className}` : ""}`}>
      <label htmlFor={fid}>{label}</label>
      {hint ? (
        <small id={`${fid}-hint`} className="ui-field-hint">
          {hint}
        </small>
      ) : null}
      <textarea {...rest} id={fid} aria-invalid={error ? true : undefined} aria-describedby={describedBy} />
      {error ? (
        <p id={`${fid}-error`} className="ui-field-error-text" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  );
}

/**
 * A search box (the app's SearchField): a magnifier, the input, and a Clear
 * button once there is text; Esc clears too. [label] names it for assistive
 * tech (there is no visible label). Enter calls [onSubmit].
 */
export interface SearchFieldProps extends Omit<InputHTMLAttributes<HTMLInputElement>, "value" | "onChange" | "type" | "onSubmit"> {
  label: string;
  value: string;
  onChange: (value: string) => void;
  onSubmit?: (value: string) => void;
  clearLabel?: string;
  /** Marks the box as the page's search landmark; leave off for a filter box inside a list. */
  landmark?: boolean;
}

export function SearchField({ label, value, onChange, onSubmit, clearLabel = "Clear search", landmark = false, className, onKeyDown, ...rest }: SearchFieldProps) {
  function key(e: KeyboardEvent<HTMLInputElement>) {
    onKeyDown?.(e);
    if (e.defaultPrevented) return;
    if (e.key === "Escape" && value) {
      e.preventDefault();
      onChange("");
    } else if (e.key === "Enter" && onSubmit) {
      e.preventDefault();
      onSubmit(value);
    }
  }
  return (
    <div className={`ui-search${className ? ` ${className}` : ""}`} role={landmark ? "search" : undefined}>
      <NavIcon name="search" size={18} />
      <input {...rest} type="search" aria-label={label} value={value} onChange={(e) => onChange(e.target.value)} onKeyDown={key} enterKeyHint="search" autoComplete="off" />
      {value ? (
        <button type="button" className="ui-search-clear" aria-label={clearLabel} onClick={() => onChange("")}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" aria-hidden="true">
            <path d="M6 6l12 12M18 6L6 18" />
          </svg>
        </button>
      ) : null}
    </div>
  );
}
