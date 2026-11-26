"use client";
import {
  adultOnlyMessage,
  birthDateLockedMessage,
  type Gender,
  genderLabels,
  genders,
  type PersonalDetails,
  type PersonalDetailsInput,
  personalDetailsSchema,
  personalLimits,
  splitDisplayName,
} from "@stall10/shared";
import type { User } from "firebase/auth";
import { type FormEvent, useMemo, useState } from "react";
import { adultBirthDateProblem, localToday } from "@/lib/accountGate";
import { ApiError, callApi, problem } from "@/lib/client";

/** Countries offered first; any other ISO code can be typed under "Other". */
const countryCodes = [
  "US", "CA", "MX", "GB", "IE", "AU", "NZ", "DE", "FR", "NL", "BE", "CH", "AT", "IT", "ES", "PT",
  "SE", "NO", "DK", "FI", "PL", "CZ", "JP", "KR", "CN", "TW", "HK", "SG", "PH", "IN", "CO", "BR",
  "AR", "CL", "ZA", "KE", "IL",
];

function countryName(code: string) {
  try {
    return new Intl.DisplayNames(["en"], { type: "region" }).of(code) ?? code;
  } catch {
    return code;
  }
}

/** Where a locked birth date points people. */
export const supportEmail = "support@stall10.app";

export { localToday };

type Form = {
  legalFirstName: string;
  legalLastName: string;
  birthDate: string;
  phone: string;
  gender: Gender | "";
  line1: string;
  line2: string;
  city: string;
  region: string;
  postalCode: string;
  country: string;
};

/** Where a new form starts: the names just typed, else the profile name split. */
type Prefill = { name?: string | null; first?: string; last?: string; birthDate?: string };

function initialForm(d: PersonalDetails | null, prefill: Prefill): Form {
  const split = splitDisplayName(prefill.name);
  const typed = prefill.first || prefill.last;
  return {
    legalFirstName: d?.legalFirstName ?? (typed ? (prefill.first ?? "") : split.first),
    legalLastName: d?.legalLastName ?? (typed ? (prefill.last ?? "") : split.last),
    birthDate: d?.birthDate ?? prefill.birthDate ?? "",
    phone: d?.phone ?? "",
    gender: d?.gender ?? "",
    line1: d?.address.line1 ?? "",
    line2: d?.address.line2 ?? "",
    city: d?.address.city ?? "",
    region: d?.address.region ?? "",
    postalCode: d?.address.postalCode ?? "",
    country: d?.address.country ?? "US",
  };
}

/** Field paths (zod's, the API's) to this form's names. */
const fieldOf: Record<string, keyof Form> = {
  "address.line1": "line1",
  "address.line2": "line2",
  "address.city": "city",
  "address.region": "region",
  "address.postalCode": "postalCode",
  "address.country": "country",
};

/**
 * The player's personal details (`PUT /v1/me/personal`): legal name,
 * birthday, phone, gender and address. Adults only (18+), so no guardian. The
 * birthday is read-only once saved.
 * Only they see them; the API keeps them encrypted.
 */
export function PersonalDetailsForm({
  user,
  email,
  initial,
  prefill = {},
  submitLabel = "Save",
  onSaved,
  onUnderAge,
  birthDateLocked = false,
}: {
  user: User;
  email: string | null;
  initial: PersonalDetails | null;
  prefill?: Prefill;
  submitLabel?: string;
  onSaved?: () => void;
  /** Under 18 (the form's check or the API's 412): the caller shows the dead-end page. Without it, the message shows in the form. */
  onUnderAge?: () => void;
  /** A birth date is already saved: shown read-only (the API refuses changes). */
  birthDateLocked?: boolean;
}) {
  const [form, setForm] = useState<Form>(() => initialForm(initial, prefill));
  const [errors, setErrors] = useState<Partial<Record<keyof Form | "_", string>>>({});
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  const today = useMemo(localToday, []);
  const us = form.country === "US";
  const otherCountry = !countryCodes.includes(form.country);

  const set = (k: keyof Form) => (e: { target: { value: string } }) => {
    setForm((f) => ({ ...f, [k]: e.target.value }));
    setErrors((x) => ({ ...x, [k]: undefined, _: undefined }));
    setSaved(false);
  };

  function body(): PersonalDetailsInput {
    return {
      legalFirstName: form.legalFirstName,
      legalLastName: form.legalLastName,
      birthDate: form.birthDate,
      phone: form.phone,
      gender: (form.gender || undefined) as Gender,
      address: {
        line1: form.line1,
        line2: form.line2,
        city: form.city,
        region: form.region,
        postalCode: form.postalCode,
        country: form.country,
      },
    };
  }

  function showErrors(fields: Record<string, string>) {
    const out: Partial<Record<keyof Form | "_", string>> = {};
    for (const [path, msg] of Object.entries(fields)) {
      const k = (fieldOf[path] ?? path) as keyof Form;
      if (k in form) out[k] ??= msg;
      else out._ ??= msg;
    }
    setErrors(out);
    // Move to the first problem.
    const first = Object.keys(out).find((k) => k !== "_");
    if (first) document.getElementById(`pd-${first}`)?.focus();
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    // Adults only: under 18 ends here, without sending anything. A saved
    // (locked) date is the server's to judge.
    const ageProblem = birthDateLocked ? null : adultBirthDateProblem(form.birthDate, today);
    if (ageProblem === adultOnlyMessage) {
      if (onUnderAge) return onUnderAge();
      return showErrors({ birthDate: ageProblem });
    }
    const parsed = personalDetailsSchema.safeParse(body());
    if (!parsed.success) {
      const fields: Record<string, string> = {};
      for (const i of parsed.error.issues) fields[i.path.join(".") || "_"] ??= i.message;
      return showErrors(fields);
    }
    const wrong = birthDateLocked ? null : adultBirthDateProblem(parsed.data.birthDate, today) && { field: "birthDate", message: adultBirthDateProblem(parsed.data.birthDate, today)! };
    if (wrong) return showErrors({ [wrong.field]: wrong.message });
    setBusy(true);
    try {
      await callApi(user, "/v1/me/personal", { method: "PUT", body: body() });
      setSaved(true);
      onSaved?.();
    } catch (err) {
      if (err instanceof ApiError && err.status === 412 && err.fields?.birthDate) {
        // Locked: say so and where to go. Anything else on the birth date is the age rule.
        if (err.message === birthDateLockedMessage) return showErrors({ birthDate: err.message });
        if (onUnderAge) return onUnderAge();
      }
      if (err instanceof ApiError && err.fields) showErrors(err.fields);
      else setErrors({ _: problem(err, "Couldn't save. Try again.") });
    } finally {
      setBusy(false);
    }
  }

  const field = (k: keyof Form, label: string, input: Record<string, unknown> = {}, hint?: string) => (
    <label>
      {label}
      <input
        id={`pd-${k}`}
        value={form[k]}
        onChange={set(k)}
        aria-invalid={errors[k] ? true : undefined}
        aria-describedby={errors[k] ? `pd-${k}-err` : undefined}
        {...input}
      />
      {hint && !errors[k] && <small className="muted">{hint}</small>}
      {errors[k] && (
        <small className="form-error" id={`pd-${k}-err`}>
          {errors[k]}
        </small>
      )}
    </label>
  );

  return (
    <form className="settings-form personal-form" onSubmit={(e) => void submit(e)} noValidate>
      <p className="personal-private muted small">
        <span aria-hidden="true">🔒</span> Only you can see these. We keep them encrypted and never show them on your
        profile or to teams.
      </p>

      <fieldset>
        <legend>Legal name</legend>
        <div className="form-grid">
          {field("legalFirstName", "First name", { autoComplete: "given-name", maxLength: personalLimits.name })}
          {field("legalLastName", "Last name", { autoComplete: "family-name", maxLength: personalLimits.name })}
        </div>
      </fieldset>

      <div className="form-grid">
        {field(
          "birthDate",
          "Date of birth",
          birthDateLocked
            ? { type: "date", autoComplete: "bday", readOnly: true, "aria-readonly": true }
            : { type: "date", autoComplete: "bday", max: today, min: "1900-01-01" },
          birthDateLocked ? `${birthDateLockedMessage} Email ${supportEmail}.` : undefined,
        )}
        <label>
          Gender
          <select
            id="pd-gender"
            value={form.gender}
            onChange={set("gender")}
            aria-invalid={errors.gender ? true : undefined}
          >
            <option value="" disabled>
              Choose…
            </option>
            {genders.map((g) => (
              <option key={g} value={g}>
                {genderLabels[g]}
              </option>
            ))}
          </select>
          {errors.gender && <small className="form-error">{errors.gender}</small>}
        </label>
      </div>

      <fieldset>
        <legend>Contact</legend>
        <div className="form-grid">
          <label>
            Email
            <input value={email ?? ""} readOnly disabled />
            <small className="muted">Your account&apos;s email.</small>
          </label>
          {field("phone", "Phone", { type: "tel", autoComplete: "tel", maxLength: personalLimits.phone })}
        </div>
      </fieldset>

      <fieldset>
        <legend>Mailing address</legend>
        <label>
          Country
          <select
            id="pd-country"
            value={otherCountry ? "" : form.country}
            onChange={(e) => set("country")({ target: { value: e.target.value || "" } })}
          >
            {countryCodes.map((c) => (
              <option key={c} value={c}>
                {countryName(c)}
              </option>
            ))}
            <option value="">Other…</option>
          </select>
        </label>
        {otherCountry &&
          field("country", "Country code", { maxLength: 2, autoComplete: "country", placeholder: "e.g. GH" }, "Two letters (ISO 3166).")}
        {field("line1", "Street address", { autoComplete: "address-line1", maxLength: personalLimits.line })}
        {field("line2", "Apartment, suite, etc. (optional)", { autoComplete: "address-line2", maxLength: personalLimits.line })}
        <div className="form-grid form-grid-3">
          {field("city", "City", { autoComplete: "address-level2", maxLength: personalLimits.city })}
          {field("region", us ? "State" : "State / province", { autoComplete: "address-level1", maxLength: personalLimits.region })}
          {field("postalCode", us ? "ZIP code" : "Postal code", { autoComplete: "postal-code", maxLength: personalLimits.postalCode })}
        </div>
      </fieldset>

      <div className="form-actions">
        {errors._ && (
          <span className="form-error" role="alert">
            {errors._}
          </span>
        )}
        {saved && !errors._ && <span className="form-ok">Saved.</span>}
        <button className="btn btn-primary" type="submit" disabled={busy}>
          {busy ? "Saving…" : submitLabel}
        </button>
      </div>
    </form>
  );
}

/** For the sign-up page's first step: the birthday's problem, or null. */
export const signUpBirthDateProblem = (birthDate: string) => adultBirthDateProblem(birthDate, localToday());
