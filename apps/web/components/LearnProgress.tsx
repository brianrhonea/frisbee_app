"use client";
import { learnLessons, learnProgressLabel, learnReadAfterMs, learnReadIds, learnReadKey } from "@stall10/shared";
import { useCallback, useEffect, useRef, useState } from "react";

// The Learn guide's contents with reading progress (F9), as the app's
// LearnViewModel: a tick on each lesson read and "N of M read". A lesson
// counts as read once the end of its section has stayed on screen for
// learnReadAfterMs. Kept on this device (localStorage), like the app's
// shared preferences; not synced between devices.

function loadRead(): string[] {
  try {
    const raw = window.localStorage.getItem(learnReadKey);
    const list: unknown = raw ? JSON.parse(raw) : [];
    return Array.isArray(list) ? learnReadIds(list.filter((x): x is string => typeof x === "string")) : [];
  } catch {
    return [];
  }
}

function saveRead(ids: string[]) {
  try {
    if (ids.length === 0) window.localStorage.removeItem(learnReadKey);
    else window.localStorage.setItem(learnReadKey, JSON.stringify([...ids].sort()));
  } catch {
    // Shown unread again next time; nothing else depends on it.
  }
}

/** Whether the bottom of lesson [id]'s section is on screen. */
function endShown(id: string): boolean {
  const el = document.getElementById(id);
  if (!el) return false;
  const bottom = el.getBoundingClientRect().bottom;
  return bottom >= 0 && bottom <= window.innerHeight;
}

export function LearnToc() {
  // Nothing read until the browser has looked (the server renders it unread).
  const [read, setRead] = useState<string[]>([]);
  const readRef = useRef<string[]>([]);
  const timers = useRef(new Map<string, ReturnType<typeof setTimeout>>());

  const update = useCallback((ids: string[]) => {
    readRef.current = ids;
    setRead(ids);
    saveRead(ids);
  }, []);

  useEffect(() => {
    const saved = loadRead();
    readRef.current = saved;
    setRead(saved);
    const waiting = timers.current;
    let frame = 0;
    const check = () => {
      frame = 0;
      for (const { id } of learnLessons) {
        if (readRef.current.includes(id) || !endShown(id)) {
          clearTimeout(waiting.get(id));
          waiting.delete(id);
          continue;
        }
        if (waiting.has(id)) continue;
        waiting.set(
          id,
          setTimeout(() => {
            waiting.delete(id);
            if (endShown(id) && !readRef.current.includes(id)) update(learnReadIds([...readRef.current, id]));
          }, learnReadAfterMs),
        );
      }
    };
    const soon = () => {
      if (!frame) frame = requestAnimationFrame(check);
    };
    check();
    window.addEventListener("scroll", soon, { passive: true });
    window.addEventListener("resize", soon);
    return () => {
      window.removeEventListener("scroll", soon);
      window.removeEventListener("resize", soon);
      cancelAnimationFrame(frame);
      for (const t of waiting.values()) clearTimeout(t);
      waiting.clear();
    };
  }, [update]);

  return (
    <nav className="card learn-toc" aria-label="On this page">
      <div className="learn-progress">
        <span className="learn-progress-label">{learnProgressLabel(read)}</span>
        {read.length > 0 && (
          <button type="button" className="text-btn learn-unread" onClick={() => update([])}>
            Mark all unread
          </button>
        )}
      </div>
      <ol>
        {learnLessons.map(({ id, title }, i) => {
          const done = read.includes(id);
          return (
            <li key={id}>
              <a href={`#${id}`} className={done ? "read" : undefined}>
                <span className="learn-num" aria-hidden="true">
                  {done ? "✓" : String(i + 1).padStart(2, "0")}
                </span>
                <span>
                  {title}
                  {done && <span className="visually-hidden"> (read)</span>}
                </span>
              </a>
            </li>
          );
        })}
        {/* The rules of ultimate, after the lessons on the same page (not counted as read). */}
        <li>
          <a href="#rules" className="learn-toc-rules">
            <span className="learn-num" aria-hidden="true">
              ⚑
            </span>
            <span>The rules of ultimate</span>
          </a>
        </li>
      </ol>
    </nav>
  );
}
