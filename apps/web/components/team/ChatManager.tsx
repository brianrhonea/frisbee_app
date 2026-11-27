"use client";
import { chatRoomLimits, type SaveChatRoomRequest } from "@stall10/shared";
import { type FormEvent, useState } from "react";
import { callApi } from "@/lib/client";
import type { Doc } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { rolesInOrder, useTeamHub } from "./TeamContext";
import { useConfirm } from "@/components/ui/ConfirmDialog";

export interface ManagedRoom {
  name?: string;
  kind?: "text" | "voice";
  folderId?: string | null;
  position?: number;
  readRoles?: string[];
  writeRoles?: string[];
  readUsers?: string[];
  writeUsers?: string[];
}
export interface ManagedFolder {
  name?: string;
  position?: number;
  readRoles?: string[];
  writeRoles?: string[];
  readUsers?: string[];
  writeUsers?: string[];
}

type Level = "none" | "read" | "write";
interface Access {
  readRoles: string[];
  writeRoles: string[];
  readUsers: string[];
  writeUsers: string[];
}

const tierNames: Record<string, string> = { everyone: "Everyone", coach: "Coaches", captain: "Captains", player: "Players" };
const levelOf = (read: string[], write: string[], id: string): Level => (write.includes(id) ? "write" : read.includes(id) ? "read" : "none");
function withLevel(read: string[], write: string[], id: string, level: Level): [string[], string[]] {
  const r = read.filter((x) => x !== id);
  const w = write.filter((x) => x !== id);
  if (level !== "none") r.push(id);
  if (level === "write") w.push(id);
  return [r, w];
}
const accessOf = (d: ManagedRoom | ManagedFolder | undefined): Access => ({
  readRoles: d?.readRoles ?? ["everyone"],
  writeRoles: d?.writeRoles ?? ["everyone"],
  readUsers: d?.readUsers ?? [],
  writeUsers: d?.writeUsers ?? [],
});

const levels: Array<[Level, string]> = [
  ["none", "None"],
  ["read", "Read"],
  ["write", "Read & write"],
];

/** Who reads and writes: Everyone, roles (and legacy tiers already set), and single members. */
function AccessEditor({ value, onChange }: { value: Access; onChange: (a: Access) => void }) {
  const { viewer } = useTeamHub();
  const [person, setPerson] = useState("");
  if (viewer.state !== "member") return null;
  const team = viewer.team;
  const roles = rolesInOrder(team.roles);
  const legacy = [...new Set([...value.readRoles, ...value.writeRoles])].filter((id) => id !== "everyone" && tierNames[id]);
  const rows: Array<[string, string]> = [["everyone", "Everyone"], ...legacy.map((id) => [id, tierNames[id]!] as [string, string]), ...roles.map((r) => [r.id, r.name] as [string, string])];
  const people = (team.memberIds ?? []).filter((u) => !value.readUsers.includes(u));
  const name = (u: string) => team.memberNames?.[u] || "Member";

  // None / Read / Read & write as a segmented control (the app's room access picker).
  const picker = (label: string, level: Level, set: (l: Level) => void) => (
    <span className="segmented access-picker" role="radiogroup" aria-label={`${label} access`}>
      {levels.map(([l, text]) => (
        <button key={l} type="button" role="radio" aria-checked={level === l} className={level === l ? "on" : ""} onClick={() => set(l)}>
          {text}
        </button>
      ))}
    </span>
  );
  const roleSelect = (id: string, label: string) =>
    picker(label, levelOf(value.readRoles, value.writeRoles, id), (l) => {
      const [readRoles, writeRoles] = withLevel(value.readRoles, value.writeRoles, id, l);
      onChange({ ...value, readRoles, writeRoles });
    });
  const userSelect = (uid: string) =>
    picker(name(uid), levelOf(value.readUsers, value.writeUsers, uid), (l) => {
      const [readUsers, writeUsers] = withLevel(value.readUsers, value.writeUsers, uid, l);
      onChange({ ...value, readUsers, writeUsers });
    });
  return (
    <div className="access-table">
      {rows.map(([id, label]) => (
        <div className="access-row" key={id}>
          <span>{label}</span>
          {roleSelect(id, label)}
        </div>
      ))}
      {value.readUsers.map((uid) => (
        <div className="access-row" key={uid}>
          <span>{name(uid)}</span>
          {userSelect(uid)}
        </div>
      ))}
      {people.length > 0 && value.readUsers.length < chatRoomLimits.users && (
        <div className="access-row">
          <select aria-label="Add a member" value={person} onChange={(e) => setPerson(e.target.value)}>
            <option value="">Add a member…</option>
            {people.map((u) => (
              <option key={u} value={u}>
                {name(u)}
              </option>
            ))}
          </select>
          <button
            type="button"
            className="btn btn-small"
            disabled={!person}
            onClick={() => {
              onChange({ ...value, readUsers: [...value.readUsers, person], writeUsers: [...value.writeUsers, person] });
              setPerson("");
            }}
          >
            Add
          </button>
        </div>
      )}
      <p className="muted small">The owner can always read and write. Members who manage chats see every room here.</p>
    </div>
  );
}

type Editing = { type: "room"; id: string | null; kind: "text" | "voice" } | { type: "folder"; id: string | null } | null;

/**
 * Rooms and folders, for members who manage chats: make, rename, set who
 * reads and writes, move between folders, reorder and delete.
 */
export function ChatManager({
  rooms,
  folders,
  onDone,
}: {
  rooms: Doc<ManagedRoom>[];
  folders: Doc<ManagedFolder>[];
  onDone: () => void;
}) {
  const askConfirm = useConfirm();
  const { teamId, viewer } = useTeamHub();
  const { user } = useAuth();
  const [editing, setEditing] = useState<Editing>(null);
  const [name, setName] = useState("");
  const [folderId, setFolderId] = useState<string | null>(null);
  const [access, setAccess] = useState<Access>(accessOf(undefined));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (viewer.state !== "member" || !user) return null;
  const me = user;
  const base = `/v1/teams/${encodeURIComponent(teamId)}`;
  const byPos = <T extends { position?: number; name?: string }>(a: T, b: T) => (a.position ?? 0) - (b.position ?? 0) || (a.name ?? "").localeCompare(b.name ?? "");
  const sortedFolders = folders.slice().sort(byPos);
  const inFolder = (id: string | null) => rooms.filter((r) => (r.folderId ?? null) === id || (id === null && r.folderId && !folders.some((f) => f.id === r.folderId))).sort(byPos);

  async function run(path: string, method: string, body?: unknown) {
    setBusy(true);
    setError(null);
    try {
      await callApi(me, path, { method, body });
      return true;
    } catch (e) {
      setError((e as Error).message);
      return false;
    } finally {
      setBusy(false);
    }
  }

  function start(next: Editing, d?: ManagedRoom | ManagedFolder) {
    setEditing(next);
    setName(d?.name ?? "");
    setFolderId(next?.type === "room" ? ((d as ManagedRoom | undefined)?.folderId ?? null) : null);
    setAccess(accessOf(d));
    setError(null);
  }

  async function save(e: FormEvent) {
    e.preventDefault();
    if (!editing) return;
    let ok: boolean;
    if (editing.type === "room") {
      const body: SaveChatRoomRequest = { name: name.trim(), kind: editing.kind, folderId, access };
      ok = editing.id ? await run(`${base}/chat-rooms/${encodeURIComponent(editing.id)}`, "PATCH", body) : await run(`${base}/chat-rooms`, "POST", body);
    } else {
      const body = { name: name.trim(), access };
      ok = editing.id ? await run(`${base}/chat-folders/${encodeURIComponent(editing.id)}`, "PATCH", body) : await run(`${base}/chat-folders`, "POST", body);
    }
    if (ok) setEditing(null);
  }

  /** Moves [id] one place up or down within its folder (or the folder list). */
  async function shift(kind: "room" | "folder", id: string, by: number) {
    if (kind === "folder") {
      const ids = sortedFolders.map((f) => f.id);
      const at = ids.indexOf(id);
      if (at + by < 0 || at + by >= ids.length) return;
      [ids[at], ids[at + by]] = [ids[at + by]!, ids[at]!];
      await run(`${base}/chat-layout`, "PUT", { folders: ids.map((f, i) => ({ id: f, position: i })) });
      return;
    }
    const room = rooms.find((r) => r.id === id);
    const list = inFolder(room?.folderId && folders.some((f) => f.id === room.folderId) ? room.folderId : null);
    const ids = list.map((r) => r.id);
    const at = ids.indexOf(id);
    if (at + by < 0 || at + by >= ids.length) return;
    [ids[at], ids[at + by]] = [ids[at + by]!, ids[at]!];
    await run(`${base}/chat-layout`, "PUT", {
      rooms: ids.map((r, i) => ({ id: r, position: i, folderId: list.find((x) => x.id === r)?.folderId ?? null })),
    });
  }

  const roomRows = (list: Doc<ManagedRoom>[]) =>
    list.map((r, i) => (
      <li key={r.id}>
        <span className="role-main">
          <b>
            <span aria-hidden="true">{r.kind === "voice" ? "🔊 " : "# "}</span>
            {r.name || "Room"}
          </b>
        </span>
        <span className="post-admin">
          <button type="button" className="text-btn" disabled={busy || i === 0} aria-label={`Move ${r.name} up`} onClick={() => void shift("room", r.id, -1)}>
            ↑
          </button>
          <button type="button" className="text-btn" disabled={busy || i === list.length - 1} aria-label={`Move ${r.name} down`} onClick={() => void shift("room", r.id, 1)}>
            ↓
          </button>
          <button type="button" className="text-btn" disabled={busy} onClick={() => start({ type: "room", id: r.id, kind: r.kind ?? "text" }, r)}>
            Edit
          </button>
          {r.id !== "general" && (
            <button
              type="button"
              className="text-btn"
              disabled={busy}
              onClick={async () => {
                if ((await askConfirm({ message: `Delete #${r.name}? Its messages and files go too.`, confirmLabel: "Delete", destructive: true }))) void run(`${base}/chat-rooms/${encodeURIComponent(r.id)}`, "DELETE");
              }}
            >
              Delete
            </button>
          )}
        </span>
      </li>
    ));

  return (
    <div className="card thread chat-manager">
      <header className="thread-head">
        <h2>Manage rooms</h2>
        <span className="post-admin">
          <button type="button" className="text-btn" onClick={onDone}>
            Done
          </button>
        </span>
      </header>
      <div className="chat-manager-body">
        <div className="home-actions">
          <button type="button" className="btn btn-small" disabled={busy || rooms.length >= chatRoomLimits.rooms} onClick={() => start({ type: "room", id: null, kind: "text" })}>
            New room
          </button>
          <button type="button" className="btn btn-small" disabled={busy || rooms.length >= chatRoomLimits.rooms} onClick={() => start({ type: "room", id: null, kind: "voice" })}>
            New voice room
          </button>
          <button type="button" className="btn btn-small" disabled={busy || folders.length >= chatRoomLimits.folders} onClick={() => start({ type: "folder", id: null })}>
            New folder
          </button>
        </div>

        {editing && (
          <form className="settings-form role-editor" onSubmit={(e) => void save(e)}>
            <h3>
              {editing.id ? "Edit" : "New"} {editing.type === "folder" ? "folder" : editing.kind === "voice" ? "voice room" : "room"}
            </h3>
            <label>
              Name
              <input value={name} maxLength={chatRoomLimits.name} autoFocus onChange={(e) => setName(e.target.value)} />
            </label>
            {editing.type === "room" && (
              <label>
                Folder
                <select value={folderId ?? ""} onChange={(e) => setFolderId(e.target.value || null)}>
                  <option value="">No folder</option>
                  {sortedFolders.map((f) => (
                    <option key={f.id} value={f.id}>
                      {f.name || "Folder"}
                    </option>
                  ))}
                </select>
              </label>
            )}
            <fieldset>
              <legend>Who can see and post</legend>
              <AccessEditor value={access} onChange={setAccess} />
            </fieldset>
            <div className="home-actions">
              <button className="btn btn-primary btn-small" disabled={busy || !name.trim()}>
                {busy ? "Saving…" : "Save"}
              </button>
              <button type="button" className="btn btn-small" onClick={() => setEditing(null)}>
                Cancel
              </button>
            </div>
          </form>
        )}

        <ul className="role-list">{roomRows(inFolder(null))}</ul>
        {sortedFolders.map((f, i) => (
          <div key={f.id} className="chat-manager-folder">
            <div className="linked-team-row">
              <h3 className="chat-folder role-main">{f.name || "Folder"}</h3>
              <span className="post-admin">
                <button type="button" className="text-btn" disabled={busy || i === 0} aria-label={`Move ${f.name} up`} onClick={() => void shift("folder", f.id, -1)}>
                  ↑
                </button>
                <button type="button" className="text-btn" disabled={busy || i === sortedFolders.length - 1} aria-label={`Move ${f.name} down`} onClick={() => void shift("folder", f.id, 1)}>
                  ↓
                </button>
                <button type="button" className="text-btn" disabled={busy} onClick={() => start({ type: "folder", id: f.id }, f)}>
                  Edit
                </button>
                <button
                  type="button"
                  className="text-btn"
                  disabled={busy}
                  onClick={async () => {
                    if ((await askConfirm({ message: `Delete the ${f.name} folder? Its rooms stay, outside any folder.`, confirmLabel: "Delete", destructive: true }))) void run(`${base}/chat-folders/${encodeURIComponent(f.id)}`, "DELETE");
                  }}
                >
                  Delete
                </button>
              </span>
            </div>
            <ul className="role-list">{roomRows(inFolder(f.id))}</ul>
          </div>
        ))}
        {error && <p className="form-error" role="alert">{error}</p>}
      </div>
    </div>
  );
}
