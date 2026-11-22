"use client";
import { cleanRsvpNote, rsvpNoteMax } from "@stall10/shared";
import { type FormEvent, useEffect, useRef, useState } from "react";
import "./rsvp_note.css";

/**
 * "Add a note (optional)" under an answer (the app's RsvpNoteField): a
 * short line such as "Late 15 min", saved with Save or Enter. Shows the
 * saved [note] until the member edits it. The API cleans it and drops it
 * when the answer is taken back.
 */
export function RsvpNoteField({
  note,
  disabled,
  onSave,
}: {
  note: string;
  disabled?: boolean;
  onSave: (note: string) => void | Promise<void>;
}) {
  const [text, setText] = useState(note);
  const saved = useRef(note);
  // A newly saved note replaces the text unless the member is mid-edit.
  useEffect(() => {
    setText((t) => (t.trim() === saved.current.trim() ? note : t));
    saved.current = note;
  }, [note]);
  const dirty = cleanRsvpNote(text) !== cleanRsvpNote(note);

  function submit(e: FormEvent) {
    e.preventDefault();
    if (dirty && !disabled) void onSave(cleanRsvpNote(text));
  }

  return (
    <form className="rsvp-note-field" onSubmit={submit}>
      <input
        value={text}
        maxLength={rsvpNoteMax}
        placeholder="Add a note (optional)"
        aria-label="Note on your answer"
        disabled={disabled}
        onChange={(e) => setText(e.target.value)}
      />
      {dirty && (
        <button type="submit" className="btn btn-small btn-primary" disabled={disabled}>
          Save
        </button>
      )}
      {text.length > rsvpNoteMax - 20 && (
        <small className="muted rsvp-note-count">
          {text.length}/{rsvpNoteMax}
        </small>
      )}
    </form>
  );
}

/** A note after someone's name in the responses, in quotes (as the app shows it). */
export function NoteQuote({ note }: { note?: string }) {
  return note ? <span className="rsvp-note"> “{note}”</span> : null;
}
