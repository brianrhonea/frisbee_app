/** Sign-up's two steps, with the current one marked. */
export function SignUpSteps({ at }: { at: 1 | 2 }) {
  const steps = ["Account details", "About you"];
  return (
    <ol className="signup-steps" aria-label={`Step ${at} of ${steps.length}`}>
      {steps.map((label, i) => {
        const n = i + 1;
        const state = n < at ? "done" : n === at ? "on" : "";
        return (
          <li key={label} className={state} aria-current={n === at ? "step" : undefined}>
            <span className="signup-step-n" aria-hidden="true">
              {n < at ? "✓" : n}
            </span>
            {label}
          </li>
        );
      })}
    </ol>
  );
}
