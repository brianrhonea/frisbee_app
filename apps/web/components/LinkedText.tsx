import { splitLinks } from "@/lib/text";

/**
 * Post text whose web addresses are links (opened in a new tab), as the
 * app's LinkifiedText. Posts have no separate link tool: people paste
 * links into the words.
 */
export function LinkedText({ text }: { text: string }) {
  return (
    <>
      {splitLinks(text).map((p, i) =>
        p.href ? (
          <a key={i} href={p.href} target="_blank" rel="noopener nofollow ugc">
            {p.text}
          </a>
        ) : (
          p.text
        ),
      )}
    </>
  );
}
