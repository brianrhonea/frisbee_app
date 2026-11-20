"use client";
// Import from Discord (the app's DiscordImportScreen, opened from Roles):
// the owner pastes a server template link, previews the roles, folders and
// rooms it would add, and imports them. The preview maps the plan onto the
// team with the same shared functions the API applies, so what's shown is
// what's written. The owner picks which text channels come across (all to
// start with; pickRooms cuts the plan down before anything else sees it, so
// unticked rooms are never made or moved). In a community with teams, rooms
// only one team's roles read go to that team's chat (teams the owner also
// owns), and the owner can send any room elsewhere.
import {
  allChannels,
  audienceLabel,
  type ChannelGroup,
  channelGroups,
  type DiscordImportResult,
  type ImportPlan,
  importIsEmpty,
  movingRooms,
  pickedDestinations,
  pickRooms,
  planFor,
  planImport,
  splitPlan,
  type TeamPermission,
} from "@stall10/shared";
import { doc, getDoc } from "firebase/firestore";
import Link from "next/link";
import { type FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { firestoreDb } from "@/lib/firebase";
import { useLiveQuery } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import type { ManagedFolder, ManagedRoom } from "./ChatManager";
import { useTeamHub } from "./TeamContext";
import { permissionInfo } from "./TeamRoles";
import "./discord_import.css";

const permLabel = (p: TeamPermission) => permissionInfo[p]?.label ?? p;

export function DiscordImport() {
  const { user } = useAuth();
  const { teamId, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const owner = member?.tier === "owner";
  const [open, setOpen] = useState(false);
  const [link, setLink] = useState("");
  const [plan, setPlan] = useState<ImportPlan | null>(null);
  const [busy, setBusy] = useState<"preview" | "import" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<DiscordImportResult | null>(null);
  /** Where rooms go, by index into the whole plan. */
  const [overrides, setOverrides] = useState<Map<number, string | null>>(new Map());
  /** The channels ticked, by index into the whole plan. */
  const [picked, setPicked] = useState<Set<number>>(new Set());
  const folders = useLiveQuery<ManagedFolder>(owner && open ? `teams/${teamId}/chatFolders` : null, [], `${teamId}-folders`);
  const rooms = useLiveQuery<ManagedRoom>(owner && open ? `teams/${teamId}/chats` : null, [], `${teamId}-rooms`);
  const team = member?.team;
  const linked = useMemo(() => Object.entries(team?.linkedTeams ?? {}), [team?.linkedTeams]);
  const sortsIntoTeams = team?.kind === "organization" && linked.length > 0;
  const owned = useOwnedTeams(sortsIntoTeams && open ? linked.map(([id]) => id) : [], user?.uid);

  const existing = useMemo(
    () => ({
      folders: (folders.data ?? []).map((f) => ({ id: f.id, name: f.name ?? "", position: f.position ?? 0 })),
      rooms: (rooms.data ?? []).map((r) => ({ id: r.id, name: r.name ?? "", folderId: r.folderId ?? null, position: r.position ?? 0 })),
    }),
    [folders.data, rooms.data],
  );
  const view = useMemo(() => {
    if (!plan || !team) return null;
    const picking = pickRooms(plan, picked, overrides);
    const chosen = picking.plan;
    const whole = planImport(chosen, team, existing.folders, existing.rooms);
    let split = null;
    if (sortsIntoTeams) {
      const forced = new Map(picking.overrides);
      splitPlan(chosen, team, whole.roleIdsByKey, picking.overrides).destinations.forEach((d, i) => {
        if (d !== null && !owned.has(d)) forced.set(i, null);
      });
      split = splitPlan(chosen, team, whole.roleIdsByKey, forced);
    }
    const here = split ? planImport(planFor(chosen, split, null), team, existing.folders, existing.rooms) : whole;
    const moving = split ? movingRooms(chosen, split, existing.folders, existing.rooms) : [];
    return { picking, split, here, moving, toTeams: split ? split.destinations.filter((d) => d !== null).length : 0 };
  }, [plan, team, existing, sortsIntoTeams, overrides, owned, picked]);
  const groups = useMemo(() => (plan ? channelGroups(plan) : []), [plan]);

  if (!owner) return null;

  async function preview(e: FormEvent) {
    e.preventDefault();
    if (!user || !link.trim()) return;
    setBusy("preview");
    setError(null);
    setDone(null);
    setOverrides(new Map());
    try {
      const next = await callApi<ImportPlan>(user, `/v1/teams/${encodeURIComponent(teamId)}/discord/preview`, { method: "POST", body: { link: link.trim() } });
      setPicked(new Set(allChannels(next)));
      setPlan(next);
    } catch (err) {
      setPlan(null);
      setError(problem(err, "Couldn't read that template. Try again."));
    } finally {
      setBusy(null);
    }
  }

  async function apply() {
    if (!user || !plan || !view) return;
    if (
      view.moving.length > 0 &&
      !window.confirm(
        `Move ${view.moving.length} room${view.moving.length === 1 ? "" : "s"} to teams? These are in the community chat now and will be deleted there once their team has them, with any messages in them: ${view.moving.map((r) => `#${r.name}`).join(", ")}.`,
      )
    ) {
      return;
    }
    setBusy("import");
    setError(null);
    try {
      // Only the picked channels, with destinations by their index there.
      const body = { plan: view.picking.plan, destinations: pickedDestinations(view.picking) };
      setDone(await callApi<DiscordImportResult>(user, `/v1/teams/${encodeURIComponent(teamId)}/discord/import`, { method: "POST", body }));
    } catch (err) {
      setError(problem(err, "Couldn't import. Try again."));
    } finally {
      setBusy(null);
    }
  }

  if (!open) {
    return (
      <section className="card discord-import">
        <div className="card-head">
          <h2 className="card-title">Import from Discord</h2>
          <button type="button" className="btn btn-small" onClick={() => setOpen(true)}>
            Import
          </button>
        </div>
        <p className="muted small">Copy a Discord server&apos;s roles, categories and text channels from a server template link.</p>
      </section>
    );
  }

  const here = view?.here;
  const newRoles = here ? Object.entries(here.roles).filter(([, r]) => here.newRoles.includes(r.name)).sort(([, a], [, b]) => a.position - b.position) : [];
  const folderNames = new Map([...(here?.folders ?? []).map((f) => [f.id, f.name] as const), ...existing.folders.map((f) => [f.id, f.name] as const)]);
  const label = (id: string) => (here ? audienceLabel(id, here.roles) : id);
  const accessText = (read: string[], write: string[]) => {
    const r = [...new Set([...read, ...write])].map(label).join(", ");
    const w = write.map(label).join(", ");
    if (!r) return "Owner only";
    return r === w ? r : `Read: ${r} · Write: ${w || "owner only"}`;
  };
  const nothing = !!view && importIsEmpty(view.here) && view.toTeams === 0 && view.moving.length === 0;
  const teamName = (id: string) => linked.find(([tid]) => tid === id)?.[1]?.name ?? "Team";
  const pick = (indexes: number[], on: boolean) => {
    const next = new Set(picked);
    for (const i of indexes) {
      if (on) next.add(i);
      else next.delete(i);
    }
    setPicked(next);
    setDone(null);
  };

  return (
    <section className="card discord-import">
      <div className="card-head">
        <h2 className="card-title">Import from Discord</h2>
        <button type="button" className="text-btn" onClick={() => setOpen(false)}>
          Close
        </button>
      </div>
      <p className="muted small">
        In Discord, open Server Settings → Server Template, create a template, and paste its link here. Members and messages aren&apos;t copied: give
        people their roles above.
      </p>
      <form className="discord-link" onSubmit={(e) => void preview(e)}>
        <input
          aria-label="Server template link"
          placeholder="https://discord.new/…"
          value={link}
          disabled={busy !== null}
          onChange={(e) => {
            setLink(e.target.value);
            setPlan(null);
            setPicked(new Set());
            setDone(null);
          }}
        />
        <button type="submit" className="btn" disabled={busy !== null || !link.trim()}>
          {busy === "preview" ? "Reading…" : "Preview"}
        </button>
      </form>
      {error && <p className="form-error">{error}</p>}

      {plan && here && view && (
        <div className="discord-preview">
          <h3>{plan.serverName}</h3>
          <ChannelPicker plan={plan} groups={groups} picked={picked} disabled={busy !== null} onPick={pick} />
          {view.split && view.picking.plan.rooms.length > 0 && (
            <div className="discord-split">
              <h4>Where rooms go</h4>
              <p className="muted small">Rooms only one team&apos;s roles can read go to that team&apos;s chat. Teams you don&apos;t own keep theirs here.</p>
              <ul>
                {view.picking.plan.rooms.map((r, i) => (
                  <li key={view.picking.from[i]}>
                    <span>#{r.name}</span>
                    <select
                      aria-label={`Where #${r.name} goes`}
                      value={view.split!.destinations[i] ?? ""}
                      onChange={(e) => {
                        const next = new Map(overrides);
                        next.set(view.picking.from[i]!, e.target.value || null);
                        setOverrides(next);
                        setDone(null);
                      }}
                    >
                      <option value="">Community chat</option>
                      {linked
                        .filter(([id]) => owned.has(id))
                        .map(([id, t]) => (
                          <option key={id} value={id}>
                            {t?.name ?? "Team"}
                          </option>
                        ))}
                    </select>
                  </li>
                ))}
              </ul>
              {view.toTeams > 0 && (
                <p className="muted small">
                  {view.toTeams} room{view.toTeams === 1 ? "" : "s"} go to{" "}
                  {[...new Set(view.split.destinations.filter((d): d is string => d !== null))].map(teamName).join(", ")}, with copies of the community roles
                  that get on each team.
                </p>
              )}
              <h4>Community chat</h4>
            </div>
          )}
          <h4>Roles ({newRoles.length} new)</h4>
          {newRoles.length === 0 ? (
            <p className="muted small">No new roles.</p>
          ) : (
            <ul className="discord-list">
              {newRoles.map(([id, r]) => (
                <li key={id}>
                  <span className="role-dot" style={{ background: r.color ? `#${(r.color & 0xffffff).toString(16).padStart(6, "0")}` : undefined }} />
                  <b>{r.name}</b>
                  <small className="muted">{r.perms.length ? r.perms.map(permLabel).join(", ") : "No permissions"}</small>
                </li>
              ))}
            </ul>
          )}
          {here.tooManyRoles.length > 0 && <p className="muted small">Left out (a team has up to 50 roles): {here.tooManyRoles.join(", ")}</p>}
          <h4>
            Folders ({here.folders.length} new) and rooms ({here.rooms.length} new)
          </h4>
          <ul className="discord-list">
            {here.folders.map((f) => (
              <li key={f.id}>📁 {f.name}</li>
            ))}
            {here.rooms.map((r, i) => (
              <li key={i}>
                <b>
                  # {r.folderId ? `${folderNames.get(r.folderId) ?? "Existing folder"} / ` : ""}
                  {r.name}
                </b>
                <small className="muted">{accessText(r.readRoles, r.writeRoles)}</small>
              </li>
            ))}
          </ul>
          {here.alreadyHere.length > 0 && <p className="muted small">Already here: {here.alreadyHere.join(", ")}</p>}
          {plan.skipped.length > 0 && <p className="muted small">Skipped: {plan.skipped.map((s) => `${s.name} (${s.reason})`).join(", ")}</p>}
          {done ? (
            <p className="discord-done">
              Imported. <Link href={`/teams/${encodeURIComponent(teamId)}/chat`}>Open chat</Link>
            </p>
          ) : (
            <button type="button" className="btn btn-primary" disabled={busy !== null || nothing} onClick={() => void apply()}>
              {busy === "import" ? "Importing…" : nothing ? "Nothing new to import" : "Import"}
            </button>
          )}
        </div>
      )}
    </section>
  );
}

/** The template's text channels by category, a box each: only ticked ones become rooms. */
function ChannelPicker({
  plan,
  groups,
  picked,
  disabled,
  onPick,
}: {
  plan: ImportPlan;
  groups: ChannelGroup[];
  picked: Set<number>;
  disabled: boolean;
  onPick: (indexes: number[], on: boolean) => void;
}) {
  const total = plan.rooms.length;
  const all = allChannels(plan);
  return (
    <fieldset className="discord-pick" disabled={disabled}>
      <legend>
        <h4>Pick channels</h4>
      </legend>
      {total === 0 ? (
        <p className="muted small">This template has no text channels.</p>
      ) : (
        <>
          <div className="discord-pick-head">
            <span className="muted small">
              {picked.size} of {total} text channel{total === 1 ? "" : "s"} picked. Only these become rooms; roles all come across.
            </span>
            <span className="discord-pick-all">
              <button type="button" className="text-btn" disabled={picked.size === total} onClick={() => onPick(all, true)}>
                All
              </button>
              <button type="button" className="text-btn" disabled={picked.size === 0} onClick={() => onPick(all, false)}>
                None
              </button>
            </span>
          </div>
          {groups.map((g) => (
            <div key={g.folderKey ?? ""} className="discord-pick-group">
              {g.name !== null && <GroupBox name={g.name} rooms={g.rooms} picked={picked} onPick={onPick} />}
              <ul className={g.name !== null ? "discord-pick-rooms nested" : "discord-pick-rooms"}>
                {g.rooms.map((i) => (
                  <li key={i}>
                    <label className="check-row">
                      <input type="checkbox" checked={picked.has(i)} onChange={(e) => onPick([i], e.target.checked)} /># {plan.rooms[i]!.name}
                    </label>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </>
      )}
    </fieldset>
  );
}

/** A category's box: ticked when all its channels are, a dash when some are. */
function GroupBox({ name, rooms, picked, onPick }: { name: string; rooms: number[]; picked: Set<number>; onPick: (indexes: number[], on: boolean) => void }) {
  const ref = useRef<HTMLInputElement>(null);
  const all = rooms.every((i) => picked.has(i));
  const some = !all && rooms.some((i) => picked.has(i));
  useEffect(() => {
    if (ref.current) ref.current.indeterminate = some;
  }, [some]);
  return (
    <label className="check-row discord-pick-folder">
      <input ref={ref} type="checkbox" checked={all} onChange={() => onPick(rooms, !all)} />
      {name}
    </label>
  );
}

/** Which of a community's teams the viewer owns (only those can take rooms). */
function useOwnedTeams(ids: string[], uid: string | undefined): Set<string> {
  const [owned, setOwned] = useState<Set<string>>(new Set());
  const key = ids.join(",");
  useEffect(() => {
    const db = firestoreDb();
    if (!db || !uid || !key) return setOwned(new Set());
    let live = true;
    void Promise.all(
      key.split(",").map(async (id) => {
        try {
          const snap = await getDoc(doc(db, "teams", id));
          return (snap.data()?.members as Record<string, string> | undefined)?.[uid] === "owner" ? id : null;
        } catch {
          return null; // Not a member: the rules refuse the doc.
        }
      }),
    ).then((r) => live && setOwned(new Set(r.filter((x): x is string => x !== null))));
    return () => {
      live = false;
    };
  }, [key, uid]);
  return owned;
}
