import type { Metadata } from "next";
import { Suspense } from "react";
import { AuthForm } from "@/components/AuthForm";

export const metadata: Metadata = { title: "Log in", robots: { index: false } };

export default function SignIn() {
  return (
    <div className="page">
      <Suspense>
        <AuthForm mode="sign-in" />
      </Suspense>
    </div>
  );
}
