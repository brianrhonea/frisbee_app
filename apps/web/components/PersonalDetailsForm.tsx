"use client";
import {
  adultAge,
  ageOn,
  birthDateProblem,
  type Gender,
  genderLabels,
  genders,
  type PersonalDetails,
  type PersonalDetailsInput,
  personalDetailsProblem,
  personalDetailsSchema,
  personalLimits,
  tooYoungMessage,
} from "@stall10/shared";
import type { User } from "firebase/auth";
import { type FormEvent, useMemo, useState } from "react";
import { ApiError, callApi } from "@/lib/client";

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

/** Today's calendar date where the browser is, YYYY-MM-DD. */
export function localToday(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

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
  gName: string;
  gRelationship: string;
  gEmail: string;
  gPhone: string;
};

function initialForm(d: PersonalDetails | null, prefill: { name?: string | null; birthDate?: string }): Form {
  const [first = "", ...rest] = (prefill.name ?? "").trim().split(/\s+/);
  return {
    legalFirstName: d?.legalFirstName ?? first,
    legalLastName: d?.legalLastName ?? rest.join(" "),
    birthDate: d?.birthDate ?? prefill.birthDate ?? "",
    phone: d?.phone ?? "",
    gender: d?.gender ?? "",
    line1: d?.address.line1 ?? "",
    line2: d?.address.line2 ?? "",
    city: d?.address.city ?? "",
    region: d?.address.region ?? "",
    postalCode: d?.address.postalCode ?? "",
    country: d?.address.country ?? "US",
    gName: d?.guardian?.name ?? "",
    gRelationship: d?.guardian?.relationship ?? "",
    gEmail: d?.guardian?.email ?? "",
    gPhone: d?.guardian?.phone ?? "",
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
  "guardian.name": "gName",
  "guardian.relationship": "gRelationship",
  "guardian.email": "gEmail",
  "guardian.phone": "gPhone",
  guardian: "gName",
};

/**
 * The player's personal details (`PUT /v1/me/personal`): legal name,
 * birthday, phone, gender, address and, under 18, a parent or guardian.
 * Only they see them; the API keeps them encrypted.
 */
export function PersonalDetailsForm({
  user,
  email,
  initial,
  prefill = {},
  submitLabel = "Save",
  onSaved,
  onTooYoung,
}: {
  user: User;
  email: string | null;
  initial: PersonalDetails | null;
  prefill?: { name?: string | null; birthDate?: string };
  submitLabel?: string;
  onSaved?: () => void;
  /** The API refused them for being under 13. */
  onTooYoung?: () => void;
}) {
  const [form, setForm] = useState<Form>(() => initialForm(initial, prefill));
  const [errors, setErrors] = useState<Partial<Record<keyof Form | "_", string>>>({});
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  const today = useMemo(localToday, []);
  const minor = /^\d{4}-\d{2}-\d{2}$/.test(form.birthDate) && ageOn(form.birthDate, today) < adultAge;
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
      ...(minor && {
        guardian: { name: form.gName, relationship: form.gRelationship, email: form.gEmail, phone: form.gPhone },
      }),
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
    // Finishing sign-up (e.g. after Google, which asks no birthday first):
    // under 13 ends here, without sending anything.
    if (onTooYoung && birthDateProblem(form.birthDate, today) === tooYoungMessage) return onTooYoung();
    const parsed = personalDetailsSchema.safeParse(body());
    if (!parsed.success) {
      const fields: Record<string, string> = {};
      for (const i of parsed.error.issues) fields[i.path.join(".") || "_"] ??= i.message;
      return showErrors(fields);
    }
    const problem = personalDetailsProblem(parsed.data, today);
    if (problem) return showErrors({ [problem.field]: problem.message });
    setBusy(true);
    try {
      await callApi(user, "/v1/me/personal", { method: "PUT", body: body() });
      setSaved(true);
      onSaved?.();
    } catch (err) {
      if (err instanceof ApiError && err.code === "failed_precondition" && err.fields?.birthDate) {
        if (onTooYoung) return onTooYoung();
      }
      if (err instanceof ApiError && err.fields) showErrors(err.fields);
      else setErrors({ _: err instanceof ApiError ? err.message : "Couldn't save. Try again." });
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
        {field("birthDate", "Date of birth", { type: "date", autoComplete: "bday", max: today, min: "1900-01-01" })}
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

      {minor && (
        <fieldset className="personal-guardian">
          <legend>Parent or guardian</legend>
          <p className="muted small">Players under {adultAge} need a parent or guardian&apos;s details.</p>
          <div className="form-grid">
            {field("gName", "Name", { maxLength: personalLimits.name })}
            {field("gRelationship", "Relationship (optional)", { maxLength: personalLimits.relationship, placeholder: "e.g. Mother" })}
            {field("gEmail", "Email", { type: "email", maxLength: personalLimits.email })}
            {field("gPhone", "Phone", { type: "tel", maxLength: personalLimits.phone })}
          </div>
        </fieldset>
      )}

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
export const signUpBirthDateProblem = (birthDate: string) => birthDateProblem(birthDate, localToday());
