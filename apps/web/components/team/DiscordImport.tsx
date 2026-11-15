"use client";
// Import from Discord (the app's DiscordImportScreen, opened from Roles):
// the owner pastes a server template link, previews the roles, folders and
// rooms it would add, and imports them. The preview maps the plan onto the
// team with the same shared functions the API applies, so what's shown is
// what's written. In a community with teams, rooms only one team's roles
// read go to that team's chat (teams the owner also owns), and the owner
// can send any room elsewhere.
import {
  audienceLabel,
  type DiscordImportResult,
  type ImportPlan,
  importIsEmpty,
  movingRooms,
  planFor,
  planImport,
  splitPlan,
  type TeamPermission,
} from "@stall10/shared";
import { doc, getDoc } from "firebase/firestore";
import Link from "next/link";
import { type FormEvent, useEffect, useMemo, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
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
  const [overrides, setOverrides] = useState<Map<number, string | null>>(new Map());
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
    const whole = planImport(plan, team, existing.folders, existing.rooms);
    let split = null;
    if (sortsIntoTeams) {
      const forced = new Map(overrides);
      splitPlan(plan, team, whole.roleIdsByKey, overrides).destinations.forEach((d, i) => {
        if (d !== null && !owned.has(d)) forced.set(i, null);
      });
      split = splitPlan(plan, team, whole.roleIdsByKey, forced);
    }
    const here = split ? planImport(planFor(plan, split, null), team, existing.folders, existing.rooms) : whole;
    const moving = split ? movingRooms(plan, split, existing.folders, existing.rooms) : [];
    return { split, here, moving, toTeams: split ? split.destinations.filter((d) => d !== null).length : 0 };
  }, [plan, team, existing, sortsIntoTeams, overrides, owned]);

  if (!owner) return null;

  async function preview(e: FormEvent) {
    e.preventDefault();
    if (!user || !link.trim()) return;
    setBusy("preview");
    setError(null);
    setDone(null);
    setOverrides(new Map());
    try {
      setPlan(await callApi<ImportPlan>(user, `/v1/teams/${encodeURIComponent(teamId)}/discord/preview`, { method: "POST", body: { link: link.trim() } }));
    } catch (err) {
      setPlan(null);
      setError(err instanceof ApiError ? err.message : "Couldn't read that template. Try again.");
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
      const destinations = [...overrides].map(([room, id]) => ({ room, teamId: id }));
      setDone(await callApi<DiscordImportResult>(user, `/v1/teams/${encodeURIComponent(teamId)}/discord/import`, { method: "POST", body: { plan, destinations } }));
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Couldn't import. Try again.");
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
            setDone(null);
          }}
        />
        <button type="submit" className="btn" disabled={busy !== null || !link.trim()}>
          {busy === "preview" ? "Reading…" : "Preview"}
        </button>
      </form>
      {error && <p className="form-error">{error}</p>}

      {plan && here && (
        <div className="discord-preview">
          <h3>{plan.serverName}</h3>
          {view?.split && (
            <div className="discord-split">
              <h4>Where rooms go</h4>
              <p className="muted small">Rooms only one team&apos;s roles can read go to that team&apos;s chat. Teams you don&apos;t own keep theirs here.</p>
              <ul>
                {plan.rooms.map((r, i) => (
                  <li key={i}>
                    <span>#{r.name}</span>
                    <select
                      aria-label={`Where #${r.name} goes`}
                      value={view.split!.destinations[i] ?? ""}
                      onChange={(e) => {
                        const next = new Map(overrides);
                        next.set(i, e.target.value || null);
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
