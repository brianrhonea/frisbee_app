import Link from "next/link";
import "./ui.css";

/**
 * A row of counts (the app's SummaryTiles): "2 Upcoming, 3 Teams, 12
 * Following". Each tile is a big number in the scoreboard face over a label;
 * give it an [href] and the whole tile is a link (at least 48 px high). A
 * list, so a screen reader hears "list, 3 items".
 */
export interface SummaryTile {
  id: string;
  label: string;
  value: number | string;
  href?: string;
}

export function SummaryTiles({ items, label }: { items: SummaryTile[]; /** Names the group for assistive tech. */ label?: string }) {
  return (
    <ul className="ui-tiles" aria-label={label}>
      {items.map((t) => {
        const face = (
          <>
            <b className="ui-tile-value">{t.value}</b>
            <span className="ui-tile-label">{t.label}</span>
          </>
        );
        return (
          <li key={t.id} className="ui-tile">
            {t.href ? (
              <Link className="ui-tile-face" href={t.href}>
                {face}
              </Link>
            ) : (
              <div className="ui-tile-face">{face}</div>
            )}
          </li>
        );
      })}
    </ul>
  );
}
