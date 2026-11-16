"use client";
import { type SaveTeamEventRequest, type TeamEventType, teamEventTypeLabels, teamEventTypes } from "@stall10/shared";
import { type FormEvent, useState } from "react";
import { callApi } from "@/lib/client";
import { type ShareChoice, ShareEventField, shareEvent } from "./ShareEvent";
import { newId } from "@/lib/upload";
import { useAuth } from "../AuthProvider";
import { rolesInOrder, useTeamHub } from "./TeamContext";
import type { TeamEventDoc } from "./TeamSchedule";
import { fromLocalInput, toLocalInput } from "@/lib/dates";


/**
 * Adds or edits a team event (members with manageEvents): what, when,
 * where, notes, an optional poll, whether it shows on the public page and,
 * in a school or club community, who sees it.
 */
export function TeamEventEditor({
  event,
  onDone,
}: {
  event?: TeamEventDoc & { id: string; audience?: string[] };
  onDone: (id: string | null) => void;
}) {
  const { user } = useAuth();
  const { teamId, viewer, privateGroup } = useTeamHub();
  // A new event may be shared on the member's profile, except in a private group (canShare).
  const canShare = !event && !privateGroup;
  const [share, setShare] = useState<ShareChoice>({ on: false, message: "" });
  const team = viewer.state === "member" ? viewer.team : null;
  const org = team?.kind === "organization";
  // `roles` is a map of id to role on the team doc.
  const roles = rolesInOrder(team?.roles);
  const [title, setTitle] = useState(event?.title ?? "");
  const [type, setType] = useState<TeamEventType>((event?.type as TeamEventType) ?? "practice");
  const [startsAt, setStartsAt] = useState(toLocalInput(event?.startsAt));
  const [endsAt, setEndsAt] = useState(toLocalInput(event?.endsAt));
  const [location, setLocation] = useState(event?.location ?? "");
  const [notes, setNotes] = useState(event?.notes ?? "");
  const [isPublic, setPublic] = useState(event?.public === true);
  const [audience, setAudience] = useState<string[]>(event?.audience?.length ? event.audience : ["everyone"]);
  const [poll, setPoll] = useState(event?.poll?.options?.length ? event.poll : null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const options = poll?.options ?? [];
  function setOption(i: number, text: string) {
    setPoll({ ...poll, options: options.map((o, j) => (j === i ? { ...o, text } : o)) });
  }

  async function save(e: FormEvent) {
    e.preventDefault();
    if (!user) return;
    const start = fromLocalInput(startsAt);
    if (!start) return setError("Give a date and time.");
    setBusy(true);
    setError(null);
    const body: SaveTeamEventRequest = {
      title: title.trim(),
      type,
      startsAt: start,
      endsAt: fromLocalInput(endsAt),
      location: location.trim(),
      notes,
      public: isPublic,
      poll: poll
        ? {
            question: (poll.question ?? "").trim(),
            options: options.filter((o) => o.text.trim()).map((o) => ({ id: o.id, text: o.text.trim() })),
            multiple: poll.multiple === true,
          }
        : null,
      ...(org && { audience: audience.length ? audience : ["everyone"] }),
    };
    const base = `/v1/teams/${encodeURIComponent(teamId)}/events`;
    try {
      const res = event
        ? await callApi<{ id: string }>(user, `${base}/${encodeURIComponent(event.id)}`, { method: "PATCH", body })
        : await callApi<{ id: string }>(user, base, { method: "POST", body });
      if (canShare && share.on && !(await shareEvent(user, teamId, res.id, share.message))) {
        window.alert("Event created, but it couldn't be shared. Try posting it.");
      }
      onDone(res.id);
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  return (
    <form className="card settings-form event-editor" onSubmit={(e) => void save(e)}>
      <h2>{event ? "Edit event" : "New event"}</h2>
      <label>
        Title
        <input value={title} required maxLength={100} autoFocus onChange={(e) => setTitle(e.target.value)} />
      </label>
      <label>
        Type
        <select value={type} onChange={(e) => setType(e.target.value as TeamEventType)}>
          {teamEventTypes.map((t) => (
            <option key={t} value={t}>
              {teamEventTypeLabels[t]}
            </option>
          ))}
        </select>
      </label>
      <div className="form-row">
        <label>
          Starts
          <input type="datetime-local" required value={startsAt} onChange={(e) => setStartsAt(e.target.value)} />
        </label>
        <label>
          Ends <small className="muted">(optional)</small>
          <input type="datetime-local" value={endsAt} min={startsAt} onChange={(e) => setEndsAt(e.target.value)} />
        </label>
      </div>
      <label>
        Where <small className="muted">(optional)</small>
        <input value={location} maxLength={200} onChange={(e) => setLocation(e.target.value)} />
      </label>
      <label>
        Notes <small className="muted">(members see these)</small>
        <textarea value={notes} rows={3} maxLength={5000} onChange={(e) => setNotes(e.target.value)} />
      </label>
      <label className="switch-row">
        <input type="checkbox" checked={isPublic} onChange={(e) => setPublic(e.target.checked)} /> Show on the public page (details
        only, never who&apos;s going)
      </label>
      {org && (
        <fieldset>
          <legend>Who sees it</legend>
          {[{ id: "everyone", name: "Everyone" }, ...roles].map((r) => (
            <label key={r.id} className="switch-row">
              <input
                type="checkbox"
                checked={audience.includes(r.id)}
                onChange={(e) => setAudience(e.target.checked ? [...audience, r.id] : audience.filter((a) => a !== r.id))}
              />{" "}
              {r.name || r.id}
            </label>
          ))}
        </fieldset>
      )}
      {poll ? (
        <fieldset className="poll-editor">
          <legend>Poll</legend>
          <input
            aria-label="Question"
            placeholder="Question"
            value={poll.question ?? ""}
            maxLength={200}
            onChange={(e) => setPoll({ ...poll, question: e.target.value })}
          />
          {options.map((o, i) => (
            <div key={o.id} className="input-row">
              <input aria-label={`Option ${i + 1}`} placeholder={`Option ${i + 1}`} value={o.text} maxLength={100} onChange={(e) => setOption(i, e.target.value)} />
              {options.length > 2 && (
                <button type="button" className="text-btn" onClick={() => setPoll({ ...poll, options: options.filter((_, j) => j !== i) })}>
                  Remove
                </button>
              )}
            </div>
          ))}
          <div className="form-actions">
            {options.length < 10 && (
              <button type="button" className="btn btn-small" onClick={() => setPoll({ ...poll, options: [...options, { id: newId().slice(0, 8), text: "" }] })}>
                Add option
              </button>
            )}
            <label className="switch-row">
              <input type="checkbox" checked={poll.multiple === true} onChange={(e) => setPoll({ ...poll, multiple: e.target.checked })} /> Allow
              more than one
            </label>
            <button type="button" className="text-btn" onClick={() => setPoll(null)}>
              Remove poll
            </button>
          </div>
          {event?.poll && <p className="muted small">Changing the poll starts its votes over.</p>}
        </fieldset>
      ) : (
        <p>
          <button
            type="button"
            className="btn btn-small"
            onClick={() =>
              setPoll({
                question: "",
                options: [
                  { id: newId().slice(0, 8), text: "" },
                  { id: newId().slice(0, 8), text: "" },
                ],
                multiple: false,
              })
            }
          >
            Add a poll
          </button>
        </p>
      )}
      {canShare && <ShareEventField value={share} onChange={setShare} />}
      <div className="form-actions">
        {error && (
          <span className="form-error" role="alert">
            {error}
          </span>
        )}
        <button type="button" className="btn" disabled={busy} onClick={() => onDone(null)}>
          Cancel
        </button>
        <button type="submit" className="btn btn-primary" disabled={busy}>
          {busy ? "Saving…" : event ? "Save" : "Add"}
        </button>
      </div>
    </form>
  );
}
