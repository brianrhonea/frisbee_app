"use client";
import { useEffect } from "react";
import { installGlobalErrorReporting } from "@/lib/errorReport";

/** Mounted once in the root layout: reports uncaught errors and rejections (#7). */
export function ErrorReporter() {
  useEffect(() => installGlobalErrorReporting(), []);
  return null;
}
