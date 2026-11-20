"use client";
import { competitionLevels, type CreateTeamRequest, type CreateTeamResponse, divisions, type JoinByCodeResponse } from "@stall10/shared";
import { useRouter, useSearchParams } from "next/navigation";
import { type FormEvent, useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "./AuthProvider";
import { ClubAgeNote } from "./ClubAge";

const kindCopy = {
  team: { title: "Create a team", name: "Team name", hint: "A club, college or league team with a roster, schedule and playbook." },
  community: { title: "Start a pickup community", name: "Community name", hint: "A pickup game or league anyone can find and join." },
  organization: { title: "Start a school or club community", name: "Community name", hint: "A school or club with teams of its own." },
} as const;
type Kind = keyof typeof kindCopy;
const divisionLabels: Record<string, string> = { mixed: "Mixed", open: "Open", women: "Women's", masters: "Masters" };
const levelLabels: Record<string, string> = { club: "Club", college: "College", youth: "Youth", league: "League", pickup: "Pickup" };

/** `POST /v1/teams`: a new team, group or community, owned by the signed-in member. */
export function CreateTeam() {
  const { user } = useAuth();
  const router = useRouter();
  const raw = useSearchParams().get("kind");
  const kind: Kind = raw === "community" || raw === "organization" ? raw : "team";
  const copy = kindCopy[kind];
  const [name, setName] = useState("");
  const [division, setDivision] = useState<string>("mixed");
  const [level, setLevel] = useState<string>(kind === "community" ? "pickup" : "club");
  const [city, setCity] = useState("");
  const [description, setDescription] = useState("");
  const [approval, setApproval] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function create(e: FormEvent) {
    e.preventDefault();
    if (!user) return;
    setBusy(true);
    setError(null);
    const body: CreateTeamRequest = {
      name: name.trim(),
      division: division as CreateTeamRequest["division"],
      level: level as CreateTeamRequest["level"],
      city: city.trim(),
      kind,
      ...(kind !== "team" && { description: description.trim(), requiresApproval: approval }),
    };
    try {
      const res = await callApi<CreateTeamResponse>(user, "/v1/teams", { method: "POST", body });
      router.push(`/teams/${encodeURIComponent(res.id)}`);
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  return (
    <form className="card settings-form" onSubmit={(e) => void create(e)}>
      <h2 className="card-title">{copy.title}</h2>
      <p className="muted small">{copy.hint}</p>
      <label>
        {copy.name}
        <input value={name} required maxLength={80} autoFocus onChange={(e) => setName(e.target.value)} />
      </label>
      <div className="form-row">
        <label>
          Division
          <select value={division} onChange={(e) => setDivision(e.target.value)}>
            {divisions.map((d) => (
              <option key={d} value={d}>
                {divisionLabels[d]}
              </option>
            ))}
          </select>
        </label>
        <label>
          Level
          <select value={level} onChange={(e) => setLevel(e.target.value)}>
            {competitionLevels.map((l) => (
              <option key={l} value={l}>
                {levelLabels[l]}
              </option>
            ))}
          </select>
        </label>
      </div>
      {kind === "team" && level === "club" && <ClubAgeNote />}
      <label>
        City <small className="muted">(optional)</small>
        <input value={city} maxLength={80} onChange={(e) => setCity(e.target.value)} />
      </label>
      {kind !== "team" && (
        <>
          <label>
            Description <small className="muted">(optional)</small>
            <textarea value={description} rows={3} maxLength={1000} onChange={(e) => setDescription(e.target.value)} />
          </label>
          <label className="switch-row">
            <input type="checkbox" checked={approval} onChange={(e) => setApproval(e.target.checked)} /> Approve who joins (private)
          </label>
        </>
      )}
      <div className="form-actions">
        {error && (
          <span className="form-error" role="alert">
            {error}
          </span>
        )}
        <button type="submit" className="btn btn-primary" disabled={busy || !name.trim()}>
          {busy ? "Creating…" : "Create"}
        </button>
      </div>
    </form>
  );
}

/**
 * Join with an invite code or link (`POST /v1/teams/join`), then open the
 * team, or hand its id to [onJoined]. [onCancel] adds a Cancel button.
 */
export function JoinWithCode({
  initial = "",
  auto = false,
  note,
  onJoined,
  onCancel,
}: {
  initial?: string;
  auto?: boolean;
  /** Shown under the title, e.g. the club age rule for a club team's link. */
  note?: string;
  onJoined?: (teamId: string) => void;
  onCancel?: () => void;
}) {
  const { user } = useAuth();
  const router = useRouter();
  const [code, setCode] = useState(initial);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function join(e?: FormEvent) {
    e?.preventDefault();
    if (!user || !code.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const res = await callApi<JoinByCodeResponse>(user, "/v1/teams/join", { method: "POST", body: { code: code.trim() } });
      if (onJoined) onJoined(res.teamId);
      else router.push(`/teams/${encodeURIComponent(res.teamId)}`);
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  return (
    <form className="card settings-form" onSubmit={(e) => void join(e)}>
      <h2 className="card-title">{auto ? "Join on the web" : "Join with a code"}</h2>
      {note && <p className="muted small">{note}</p>}
      {!auto && (
        <label>
          Invite code
          <input value={code} maxLength={64} autoComplete="off" onChange={(e) => setCode(e.target.value)} />
        </label>
      )}
      <div className="form-actions">
        {error && (
          <span className="form-error" role="alert">
            {error}
          </span>
        )}
        {onCancel && (
          <button type="button" className="btn" onClick={onCancel}>
            Cancel
          </button>
        )}
        <button type="submit" className="btn btn-primary" disabled={busy || !code.trim()}>
          {busy ? "Joining…" : "Join"}
        </button>
      </div>
    </form>
  );
}
