import { type GuideSection } from "@stall10/shared";

/** A guide section's intro and points (guides.ts; the app's _Points in guide_screens.dart). */
export function GuidePoints({ section }: { section: GuideSection }) {
  return (
    <>
      {section.intro && <p>{section.intro}</p>}
      <ul>
        {section.points.map((p) => (
          <li key={p}>{p}</li>
        ))}
      </ul>
    </>
  );
}
