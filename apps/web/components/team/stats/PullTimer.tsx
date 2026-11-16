"use client";
import { useEffect, useRef, useState } from "react";
import { Dialog } from "../../Dialog";
import "./stats.css";

/**
 * Times a pull (showPullTimer): pick the puller, start on release, stop
 * when it's caught or lands. Space starts and stops; O stops it as out of
 * bounds; Escape cancels.
 */
export function PullTimer({
  pullers,
  initial,
  onDone,
}: {
  pullers: Array<{ id: string; name: string }>;
  initial: string | null;
  onDone: (pull: { playerId: string; hangTimeMs: number; outOfBounds: boolean } | null) => void;
}) {
  const [puller, setPuller] = useState(initial);
  const [startedAt, setStartedAt] = useState<number | null>(null);
  const [, tick] = useState(0);
  const startRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (startedAt === null) return;
    const t = setInterval(() => tick((n) => n + 1), 50);
    return () => clearInterval(t);
  }, [startedAt]);

  const finish = (outOfBounds: boolean) => {
    if (startedAt === null || !puller) return;
    onDone({ playerId: puller, hangTimeMs: performance.now() - startedAt, outOfBounds });
  };

  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      // Esc is the dialog's (its onClose).
      if (e.key === " " || e.key === "Enter") {
        e.preventDefault();
        if (startedAt === null) {
          if (puller) setStartedAt(performance.now());
        } else finish(false);
      } else if (e.key.toLowerCase() === "o" && startedAt !== null) finish(true);
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  });

  useEffect(() => startRef.current?.focus(), []);

  const seconds = startedAt === null ? 0 : (performance.now() - startedAt) / 1000;
  return (
    <Dialog label="Pull" onClose={() => onDone(null)} className="card st-subcard st-pull">
      <h3 className="card-title">Pull</h3>
      <p className="muted small">Who&apos;s pulling?</p>
      <div className="st-chips">
        {pullers.map((p) => (
          <button
            key={p.id}
            type="button"
            className={`st-chip${puller === p.id ? " on" : ""}`}
            aria-pressed={puller === p.id}
            disabled={startedAt !== null}
            onClick={() => setPuller(p.id)}
          >
            {p.name}
          </button>
        ))}
      </div>
      <p className={`st-clock${startedAt !== null ? " running" : ""}`} aria-live="off">
        {seconds.toFixed(1)} s
      </p>
      <p className="muted small st-center">Hang time</p>
      {startedAt === null ? (
        <button ref={startRef} type="button" className="btn btn-primary st-big" disabled={!puller} onClick={() => setStartedAt(performance.now())}>
          {puller ? "Start on release (Space)" : "Pick the puller"}
        </button>
      ) : (
        <div className="st-row">
          <button type="button" className="btn btn-primary st-big st-good" onClick={() => finish(false)}>
            Caught / landed in (Space)
          </button>
          <button type="button" className="btn st-big st-bad" onClick={() => finish(true)}>
            Out of bounds (O)
          </button>
        </div>
      )}
      <button type="button" className="text-btn" onClick={() => onDone(null)}>
        Cancel
      </button>
    </Dialog>
  );
}
