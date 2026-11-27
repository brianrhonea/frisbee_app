"use client";
import Link from "next/link";
import type { ReactNode } from "react";
import "./ui.css";

/**
 * One row of a list (the app's ListRow): a leading picture or icon, a title
 * with a line under it, and trailing text or a control. At least 56 px high,
 * never a fixed height, so large text grows it. It is a link when given
 * [href], a button when given [onClick], otherwise plain content.
 *
 * [unread] adds an indigo dot and the word "Unread" for assistive tech;
 * [muted] quiets the title and adds "Muted". Both are said in text as well
 * as drawn.
 */
export interface ListRowProps {
  leading?: ReactNode;
  title: ReactNode;
  subtitle?: ReactNode;
  /** Time, count: small text at the end. */
  meta?: ReactNode;
  /** A control or pill at the end (kept outside the row's link). */
  trailing?: ReactNode;
  href?: string;
  onClick?: () => void;
  unread?: boolean;
  muted?: boolean;
  selected?: boolean;
}

export function ListRow({ leading, title, subtitle, meta, trailing, href, onClick, unread = false, muted = false, selected = false }: ListRowProps) {
  const inner = (
    <>
      {leading ? <span className="ui-row-lead">{leading}</span> : null}
      <span className="ui-row-text">
        <span className="ui-row-title">
          {title}
          {unread ? <span className="sr-only"> (Unread)</span> : null}
          {muted ? <span className="sr-only"> (Muted)</span> : null}
        </span>
        {subtitle ? <span className="ui-row-sub">{subtitle}</span> : null}
      </span>
      {meta ? <span className="ui-row-meta">{meta}</span> : null}
      {unread ? <span className="ui-row-dot" aria-hidden="true" /> : null}
    </>
  );
  const cls = `ui-row-main${href || onClick ? " ui-row-action" : ""}`;
  return (
    <div className={`ui-row${muted ? " ui-row-muted" : ""}${unread ? " ui-row-unread" : ""}${selected ? " ui-row-selected" : ""}`}>
      {href ? (
        <Link className={cls} href={href} aria-current={selected ? "true" : undefined}>
          {inner}
        </Link>
      ) : onClick ? (
        <button type="button" className={cls} onClick={onClick} aria-pressed={selected || undefined}>
          {inner}
        </button>
      ) : (
        <div className={cls}>{inner}</div>
      )}
      {trailing ? <span className="ui-row-trailing">{trailing}</span> : null}
    </div>
  );
}
