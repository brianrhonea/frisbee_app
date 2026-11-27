import { expect, test } from "@playwright/test";

// H10 Sign-in and sign-up (signed out, against the emulators): every sign-in option is still there,
// on the shared Button and TextField, and a failed attempt says so in an alert.
test.use({ storageState: { cookies: [], origins: [] } });

test("Sign in: Google, Apple, email or username, password, forgot, log in and create account", async ({ page }) => {
  await page.goto("/sign-in");
  await expect(page.getByRole("heading", { level: 1, name: "Welcome back" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Continue with Google" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Continue with Apple" })).toBeVisible();
  await expect(page.getByLabel("Email or username")).toBeVisible();
  await expect(page.getByLabel("Password")).toBeVisible();
  await expect(page.getByRole("button", { name: "Forgot your password?" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Create an account" })).toHaveAttribute("href", /\/sign-up/);
  // A wrong password is refused and said so.
  await page.getByLabel("Email or username").fill("nobody@example.test");
  await page.getByLabel("Password").fill("not-the-password");
  await page.getByRole("button", { name: "Log in", exact: true }).click();
  await expect(page.getByRole("alert").first()).toBeVisible();
});

test("Sign up: the fields, the terms, and an empty form is refused with a message", async ({ page }) => {
  await page.goto("/sign-up");
  await expect(page.getByRole("heading", { level: 1, name: "Create your account" })).toBeVisible();
  for (const l of ["First name", "Last name", "Date of birth", "Email", "Password"]) await expect(page.getByLabel(l, { exact: true })).toBeVisible();
  await expect(page.getByRole("main").getByRole("link", { name: "Terms of Service" })).toBeVisible();
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  await expect(page.getByRole("alert").first()).toBeVisible();
});
