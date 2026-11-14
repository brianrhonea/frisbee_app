"use client";
import Link from "next/link";
import { useAuth } from "./AuthProvider";

/** On Events, for members: their calendars and ones shared with them. */
export function ScheduleLink() {
  const { user } = useAuth();
  if (!user) return null;
  return (
    <p>
      <Link className="btn btn-small" href="/schedule">
        Your schedule
      </Link>
    </p>
  );
}
