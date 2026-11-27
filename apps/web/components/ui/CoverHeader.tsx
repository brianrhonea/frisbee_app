import type { ReactNode } from "react";
import "./ui.css";

/**
 * A profile or team header (the app's CoverHeader): a cover photo with the
 * picture or logo sitting on its lower edge, then the name, a line under it
 * and the actions (Edit profile, Follow). Without a cover photo a plain
 * token gradient stands in, so the layout never jumps.
 *
 * The cover is decoration (empty alt). Pass the picture as [avatar], an
 * Avatar or TeamLogo from this folder, ideally 88 px or more.
 */
export interface CoverHeaderProps {
  coverUrl?: string | null;
  avatar: ReactNode;
  title: string;
  /** @handle, place, kind. */
  subtitle?: ReactNode;
  actions?: ReactNode;
  /** Heading level of the name; the page's own h1 is the default. */
  as?: "h1" | "h2" | "h3";
  /** Under the name: a bio, a row of SummaryTiles. */
  children?: ReactNode;
}

export function CoverHeader({ coverUrl, avatar, title, subtitle, actions, as: Heading = "h1", children }: CoverHeaderProps) {
  return (
    <header className="ui-cover">
      <div className="ui-cover-photo">
        {/* eslint-disable-next-line @next/next/no-img-element -- a user's uploaded cover, already sized */}
        {coverUrl ? <img src={coverUrl} alt="" loading="lazy" /> : null}
      </div>
      <div className="ui-cover-body">
        <div className="ui-cover-avatar">{avatar}</div>
        <div className="ui-cover-actions">{actions}</div>
        <div className="ui-cover-text">
          <Heading className="ui-cover-title">{title}</Heading>
          {subtitle ? <p className="ui-cover-sub">{subtitle}</p> : null}
        </div>
        {children ? <div className="ui-cover-extra">{children}</div> : null}
      </div>
    </header>
  );
}
