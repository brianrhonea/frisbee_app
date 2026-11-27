"use client";
import { statsPlayerFrom } from "@stall10/shared";
import { collection, getDocs, limit, query, where } from "firebase/firestore";
import Link from "next/link";
import { useEffect, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { firestoreDb } from "@/lib/firebase";
import { useAuth } from "./AuthProvider";
import { ErrorNote } from "./StatusViews";
import { useMyTeams } from "./useMyTeams";
import { Button } from "./ui/Button";
import { useConfirm } from "./ui/ConfirmDialog";

/** A roster spot a team admin linked to the viewer: its team and the spot's name and number. */
export interface LinkedSpot {
  teamId: string;
  teamName: string;
  playerId: string;
  name: string;
  number: number | null;
}

/**
 * The roster spots linked to [uid] (the app's `linkedSpots`): one read of each of [teams]' rosters for the spot whose
 * `userId` is the member. Communities keep no roster. A team whose roster can't be read (the member left it) is
 * skipped. Undefined while loading.
 */
type SpotTeam = { id: string; name: string; kind?: string };

function useLinkedSpots(uid: string, teams: SpotTeam[] | undefined) {
  const [spots, setSpots] = useState<LinkedSpot[] | undefined>(undefined);
  const key = teams ? teams.map((t) => `${t.id}:${t.kind ?? "team"}`).join("|") : "loading";
  useEffect(() => {
    if (!teams) return;
    const db = firestoreDb();
    const real = teams.filter((t) => (t.kind ?? "team") === "team");
    if (!db || real.length === 0) {
      setSpots([]);
      return;
    }
    let live = true;
    Promise.all(
      real.map(async (t): Promise<LinkedSpot[]> => {
        try {
          const snap = await getDocs(query(collection(db, `teams/${t.id}/roster`), where("userId", "==", uid), limit(5)));
          return snap.docs.map((d) => {
            const p = statsPlayerFrom(d.id, d.data());
            return { teamId: t.id, teamName: t.name, playerId: d.id, name: p.name, number: p.number };
          });
        } catch {
          return [];
        }
      }),
    ).then((rows) => live && setSpots(rows.flat()));
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- [key] stands for teams.
  }, [uid, key]);
  return [spots, setSpots] as const;
}

/**
 * Your own profile's "Roster spots" card (the app's): the spots a team admin linked you to, whose stats count on
 * your profile. Linking is the admin's; you can only let go of your own, after a confirmation
 * (`PUT /v1/teams/:teamId/roster-players/:id/link` with `{ userId: null }`, the same call as "Unlink me"). Shows
 * nothing when you have none.
 */
export function RosterSpots({ uid }: { uid: string }) {
  const { user } = useAuth();
  const askConfirm = useConfirm();
  // The teams you are on (the profile's own teams list is filled by a Cloud Function and may lag).
  const mine = useMyTeams<{ name?: string; kind?: string }>(user?.uid);
  const teams = mine.data?.map((t) => ({ id: t.id, name: t.name || "Team", kind: t.kind }));
  const [spots, setSpots] = useLinkedSpots(uid, teams);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState("");
  if (!user || user.uid !== uid || !spots || spots.length === 0) return null;
  const me = user;

  async function unlink(s: LinkedSpot) {
    const ok = await askConfirm({
      title: `Unlink from ${s.teamName}?`,
      message: `Your stats from ${s.teamName} stop counting on your profile. A team admin can link you again.`,
      confirmLabel: "Unlink",
      destructive: true,
    });
    if (!ok) return;
    setBusy(s.playerId);
    setError("");
    try {
      await callApi(me, `/v1/teams/${encodeURIComponent(s.teamId)}/roster-players/${encodeURIComponent(s.playerId)}/link`, { method: "PUT", body: { userId: null } });
      setSpots((all) => all?.filter((x) => !(x.teamId === s.teamId && x.playerId === s.playerId)));
    } catch (e) {
      setError(problem(e, "Couldn't unlink you. Try again."));
    } finally {
      setBusy(null);
    }
  }

  return (
    <section className="card roster-spots" aria-labelledby="roster-spots-title">
      <h2 className="card-title" id="roster-spots-title">
        Roster spots
      </h2>
      <p className="muted small">A team admin links you to your spot on the roster.</p>
      <ul className="roster-spot-rows">
        {spots.map((s) => (
          <li key={`${s.teamId}/${s.playerId}`} className="roster-spot-row">
            <span className="roster-spot-text">
              <Link href={`/teams/${encodeURIComponent(s.teamId)}`}>{s.teamName}</Link>
              <span className="muted small">{[s.name, s.number != null ? `#${s.number}` : ""].filter(Boolean).join(" · ")}</span>
            </span>
            <Button size="small" loading={busy === s.playerId} disabled={busy !== null} aria-label={`Unlink from ${s.teamName}`} onClick={() => void unlink(s)}>
              Unlink
            </Button>
          </li>
        ))}
      </ul>
      {error && <ErrorNote>{error}</ErrorNote>}
    </section>
  );
}
