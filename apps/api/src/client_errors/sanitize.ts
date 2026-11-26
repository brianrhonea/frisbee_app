// Scrubs what the website's error reporter sends (it scrubs too; this is the
// second pass, since anyone can POST here). Nothing that could identify a
// person or grant access may reach the logs: emails, tokens, long ids and
// query strings or fragments (which carry tokens and invite codes).

const jwt = /\beyJ[\w-]{5,}\.[\w-]{5,}\.[\w-]*/g;
const bearer = /\bBearer\s+[^\s"')]+/gi;
const email = /[^\s@<>()"',;:]+@[^\s@<>()"',;]+\.[^\s@<>()"',;]+/g;
const longId = /[A-Za-z0-9_-]{32,}/g;
// "https://host/app.js?v=1#x:10:5" keeps the ":10:5" a stack frame needs.
const urlTail = /(https?:\/\/[^\s?#()"']+)[?#][^\s:()"']*/g;

/** [text] with emails, JWTs, bearer tokens, 32+ character ids and URL queries/fragments replaced. */
export function redact(text: string): string {
  return text
    .replace(jwt, "[jwt]")
    .replace(bearer, "Bearer [token]")
    .replace(email, "[email]")
    .replace(urlTail, "$1")
    .replace(longId, "[id]");
}

/** The path of [url] (a path, or a full URL): no origin, query or fragment, redacted. Always starts with "/". */
export function sanitizePath(url: string): string {
  let path = url.trim();
  const abs = path.match(/^[a-z][a-z0-9+.-]*:\/\/[^/?#]*(.*)$/i);
  if (abs) path = abs[1];
  path = path.split(/[?#]/, 1)[0];
  path = redact(path).slice(0, 512);
  return path.startsWith("/") ? path : `/${path}`;
}
