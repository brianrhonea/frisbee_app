"use client";
import { onAuthStateChanged, type User } from "firebase/auth";
import { createContext, type ReactNode, useContext, useEffect, useState } from "react";
import { firebaseAuth } from "@/lib/firebase";
import { clearDrafts } from "@/lib/messages";

interface AuthState {
  /** undefined while Firebase restores the session; null when signed out. */
  user: User | null | undefined;
}

const AuthContext = createContext<AuthState>({ user: undefined });

/** Who is signed in on this browser (Firebase Auth keeps the session). */
export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null | undefined>(undefined);
  useEffect(() => {
    const auth = firebaseAuth();
    if (!auth) {
      setUser(null);
      return;
    }
    // Whoever signs out (Log out, deleting the account, a revoked session)
    // leaves no unsent drafts behind on this browser.
    let last: string | null = null;
    return onAuthStateChanged(auth, (next) => {
      if (last && last !== next?.uid) clearDrafts(last);
      last = next?.uid ?? null;
      setUser(next);
    });
  }, []);
  return <AuthContext.Provider value={{ user }}>{children}</AuthContext.Provider>;
}

export const useAuth = () => useContext(AuthContext);
