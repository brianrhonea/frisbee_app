"use client";
// Team chat @mentions on the website (the app's _MentionSuggestions and
// LinkifiedText mentions in message_thread_view.dart): who can be
// mentioned, a message's mentions drawn, and suggestions while typing.
// The parsing is shared (packages/shared mentions.ts).
import { type MentionSpan, type MentionSuggestion, type MentionTargets, mentionQuery, mentionSpans, mentionSuggestions } from "@stall10/shared";
import type { ReactNode } from "react";
import type { TeamDoc } from "./team/TeamContext";

/** What a team chat's composer and messages need for @mentions. */
export interface MentionContext {
  targets: MentionTargets;
  /** @everyone and roles: the owner, coaches, captains and chat managers. */
  groups: boolean;
  /** Whether a mention is of the reader: by name, a role of theirs, or everyone. */
  isMe: (span: MentionSpan) => boolean;
  /** The reader, who isn't offered themselves. */
  me: string;
}

export function teamMentions(team: TeamDoc, me: string, groups: boolean): MentionContext {
  const memberIds = new Set(team.memberIds ?? []);
  const myRoles = team.memberRoles?.[me] ?? [];
  return {
    targets: {
      members: Object.entries(team.memberNames ?? {})
        .filter(([uid, name]) => memberIds.has(uid) && typeof name === "string")
        .map(([uid, name]) => ({ uid, name })),
      roles: Object.entries(team.roles ?? {}).map(([id, r]) => ({ id, name: String(r?.name ?? "") })),
    },
    groups,
    me,
    isMe: (s) => s.kind === "everyone" || (s.kind === "user" ? s.id === me : myRoles.includes(s.id)),
  };
}

/** [text] with its @mentions marked; the reader's brighter. */
export function MentionText({ text, mentions }: { text: string; mentions?: MentionContext }): ReactNode {
  const spans = mentions && text.includes("@") ? mentionSpans(text, mentions.targets) : [];
  if (spans.length === 0) return text;
  const out: ReactNode[] = [];
  let at = 0;
  for (const s of spans) {
    if (s.start > at) out.push(text.slice(at, s.start));
    out.push(
      <mark key={s.start} className={`mention${mentions!.isMe(s) ? " mention-me" : ""}`}>
        {text.slice(s.start, s.end)}
      </mark>,
    );
    at = s.end;
  }
  if (at < text.length) out.push(text.slice(at));
  return out;
}

/** The suggestions for the @word at [cursor] in [text], or none. */
export function suggestionsAt(text: string, cursor: number, mentions?: MentionContext): { start: number; options: MentionSuggestion[] } | null {
  // A cursor below 0: closed with Escape until the next keystroke.
  if (!mentions || cursor < 0 || mentions.targets.members.length === 0) return null;
  const found = mentionQuery(text, cursor);
  if (!found) return null;
  const options = mentionSuggestions(found.query, mentions.targets, mentions.groups, 6).filter((o) => o.kind !== "user" || o.id !== mentions.me);
  return options.length ? { start: found.start, options } : null;
}

/** The list above the composer; [active] is highlighted and Enter or Tab picks it. */
export function MentionMenu({ options, active, onPick }: { options: MentionSuggestion[]; active: number; onPick: (o: MentionSuggestion) => void }) {
  return (
    <ul className="mention-menu" role="listbox" aria-label="Mention someone">
      {options.map((o, i) => (
        <li key={`${o.kind}-${o.id}`} role="option" aria-selected={i === active}>
          <button
            type="button"
            className={i === active ? "active" : undefined}
            // Before the box loses focus.
            onMouseDown={(e) => {
              e.preventDefault();
              onPick(o);
            }}
          >
            <span aria-hidden="true">{o.kind === "everyone" ? "📣" : o.kind === "role" ? "🛡️" : "👤"}</span>
            <b>@{o.label}</b>
            <small className="muted">{o.kind === "everyone" ? "Everyone in this room" : o.kind === "role" ? "Role" : ""}</small>
          </button>
        </li>
      ))}
    </ul>
  );
}
