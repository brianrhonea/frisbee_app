"use client";
import { useEffect, useRef, useState } from "react";
import { initials } from "@/lib/text";
import "./ui.css";

/**
 * People and teams as pictures, the website's Avatar, TeamLogo and
 * AvatarStack (the app's Avatar, TeamLogo, AvatarStack). Each shows the
 * image when there is one, the initials when there is only a name, and a
 * neutral glyph when there is neither; a picture that fails to load falls
 * back the same way. Colours are tokens, one per kind, never one per
 * person or team.
 *
 * They are decorative by default (the name is next to them): pass `label`
 * where the picture stands alone and needs a name.
 */

type Shape = "person" | "team" | "community" | "organization";

function Glyph({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <circle cx="12" cy="8.5" r="4" />
      <path d="M4 20c0-4 3.6-6.5 8-6.5s8 2.5 8 6.5z" />
    </svg>
  );
}

/** The picture, the initials or the glyph, in that order, inside a sized, shaped box. */
function Face({ className, name, url, size, letters, label, glyph }: { className: string; name?: string; url?: string; size: number; letters: number; label?: string; glyph: boolean }) {
  const [broken, setBroken] = useState(false);
  // A new address gets a fresh chance.
  useEffect(() => setBroken(false), [url]);
  // A picture that failed before the page was interactive never fires onError here.
  const img = useRef<HTMLImageElement>(null);
  useEffect(() => {
    const el = img.current;
    if (el && el.complete && el.naturalWidth === 0) setBroken(true);
  }, [url]);
  const style = { width: size, height: size, fontSize: size * (letters === 1 ? 0.42 : 0.45) };
  const a11y = label ? ({ role: "img", "aria-label": label } as const) : ({ "aria-hidden": true } as const);
  const trimmed = name?.trim() ?? "";
  if (url && !broken) {
    // eslint-disable-next-line @next/next/no-img-element -- user photos from Storage, sized by the box.
    return <img ref={img} className={className} src={url} alt={label ?? ""} width={size} height={size} style={style} referrerPolicy="no-referrer" onError={() => setBroken(true)} />;
  }
  return (
    <span className={className} style={style} {...a11y}>
      {trimmed || !glyph ? initials(trimmed || undefined, letters) : <Glyph size={size * 0.6} />}
    </span>
  );
}

/** A person: a round photo, their initial or a glyph. */
export function Avatar({ name, url, size = 40, label }: { name?: string; url?: string; size?: number; label?: string }) {
  return <Face className="avatar" name={name} url={url} size={size} letters={1} label={label} glyph />;
}

/**
 * A team, community or school: a rounded square in the team tone for a team,
 * a circle in the accent for a pickup community and the soft accent for a
 * school or club; its logo when it has one.
 */
export function TeamLogo({ name, kind = "team", url, size = 56, label }: { name: string; kind?: Exclude<Shape, "person">; url?: string; size?: number; label?: string }) {
  return <Face className={`ui-logo ui-logo-${kind}`} name={name || "Team"} url={url} size={size} letters={2} label={label} glyph={false} />;
}

export interface StackPerson {
  id: string;
  name?: string;
  url?: string;
}

/**
 * Overlapping avatars with a "+N" for the rest. Decorative unless `label`
 * is given (then the whole stack is one image with that name, e.g. "12
 * members").
 */
export function AvatarStack({ people, max = 4, size = 24, label }: { people: readonly StackPerson[]; max?: number; size?: number; label?: string }) {
  const shown = people.slice(0, Math.max(0, max));
  const more = people.length - shown.length;
  const a11y = label ? ({ role: "img", "aria-label": label } as const) : ({ "aria-hidden": true } as const);
  return (
    <span className="avatar-stack" {...a11y}>
      {shown.map((p) => (
        <Avatar key={p.id} name={p.name} url={p.url} size={size} />
      ))}
      {more > 0 && (
        <span className="avatar-stack-more" style={{ width: size, height: size, fontSize: Math.max(9, size * 0.38) }}>
          +{more}
        </span>
      )}
    </span>
  );
}
