"use client";
import { onAuthStateChanged, type User } from "firebase/auth";
import { createContext, type ReactNode, useContext, useEffect, useState } from "react";
import { firebaseAuth } from "@/lib/firebase";

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
    return onAuthStateChanged(auth, setUser);
  }, []);
  return <AuthContext.Provider value={{ user }}>{children}</AuthContext.Provider>;
}

export const useAuth = () => useContext(AuthContext);
