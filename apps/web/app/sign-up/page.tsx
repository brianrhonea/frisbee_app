import type { Metadata } from "next";
import { Suspense } from "react";
import { AuthForm } from "@/components/AuthForm";

export const metadata: Metadata = {
  title: "Sign up",
  description: "Create a Stall 10 account to follow players, join teams and post.",
};

export default function SignUp() {
  return (
    <div className="page">
      <Suspense>
        <AuthForm mode="sign-up" />
      </Suspense>
    </div>
  );
}
