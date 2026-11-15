"use client";
// The checklist and strength meter under a new password (the app's
// PasswordStrengthMeter), from the shared password policy.
import { passwordChecklist, passwordStrength, passwordStrengthLabels } from "@stall10/shared";
import "./password_hints.css";

export function PasswordHints({ password }: { password: string }) {
  const strength = passwordStrength(password);
  return (
    <span className="password-hints" aria-live="polite">
      <span className="password-checks">
        {passwordChecklist(password).map((c) => (
          <span key={c.label} className={c.met ? "met" : ""}>
            {c.met ? "✓" : "○"} {c.label}
          </span>
        ))}
      </span>
      {password && (
        <span className={`password-strength strength-${strength}`}>
          <span className="password-meter" aria-hidden="true">
            <span />
          </span>
          {passwordStrengthLabels[strength]}
        </span>
      )}
    </span>
  );
}
