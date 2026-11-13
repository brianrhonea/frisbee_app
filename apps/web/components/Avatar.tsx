/** A round photo, or the name's first letter. */
export function Avatar({ name, url, size = 40 }: { name?: string; url?: string; size?: number }) {
  const style = { width: size, height: size, fontSize: size * 0.42 };
  if (url) return <img className="avatar" src={url} alt="" width={size} height={size} style={style} />;
  return (
    <span className="avatar" aria-hidden="true" style={style}>
      {(name?.trim()[0] ?? "?").toUpperCase()}
    </span>
  );
}
