"use client";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { useAuth } from "@/components/AuthProvider";

// A member's own profile is their player page; visitors log in first.
export default function Profile() {
  const { user } = useAuth();
  const router = useRouter();
  useEffect(() => {
    if (user) router.replace(`/players/${encodeURIComponent(user.uid)}`);
    else if (user === null) router.replace("/sign-in?next=/profile");
  }, [user, router]);
  return (
    <div className="page muted" aria-busy="true">
      Opening your profile…
    </div>
  );
}
