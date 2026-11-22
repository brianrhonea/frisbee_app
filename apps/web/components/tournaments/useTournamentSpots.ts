"use client";
import type { PublicHostedList, TournamentSpots } from "@stall10/shared";
import type { User } from "firebase/auth";
import { useEffect, useState } from "react";
import { getPublicApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";

// Team spots left (F10) for members' tournament lists, which come live
// from Firestore without them: one `/v1/public/tournaments` read (where the
// API works them out) shared by every card on the page, reused for a
// minute, as the app's DiscoverRepository does. Visitors' cards are the
// public list itself and carry their spots already.
const fresh = 60_000;
let cached: { who: string; at: number; spots: Promise<Map<string, TournamentSpots>> } | null = null;

function load(user: User): Promise<Map<string, TournamentSpots>> {
  if (cached && cached.who === user.uid && Date.now() - cached.at < fresh) return cached.spots;
  const spots = getPublicApi<PublicHostedList>(user, "/v1/public/tournaments").then(
    (l) => new Map(l.tournaments.flatMap((t) => (t.spots ? [[t.id, t.spots] as const] : []))),
  );
  const entry = { who: user.uid, at: Date.now(), spots };
  cached = entry;
  // A failure isn't kept: the next view asks again.
  spots.catch(() => {
    if (cached === entry) cached = null;
  });
  return spots;
}

/** Spots left by tournament id for a signed-in member; empty until read, for visitors, or if it fails. */
export function useTournamentSpots(): Map<string, TournamentSpots> {
  const { user } = useAuth();
  const [spots, setSpots] = useState<Map<string, TournamentSpots>>(() => new Map());
  useEffect(() => {
    if (!user) return;
    let live = true;
    load(user).then(
      (s) => live && setSpots(s),
      () => {},
    );
    return () => {
      live = false;
    };
  }, [user]);
  return spots;
}
