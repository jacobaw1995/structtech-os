import "server-only";
import type { EmailSetup } from "@/lib/signing/remote";

// Is email set up? Answered BEFORE any send, so the office sees "email is not
// set up" as a standing fact rather than discovering it as a failed send.
//
// It reads the SAME two variable names Track X's sendEmail() refuses without
// (src/lib/email/send.ts: RESEND_API_KEY, EMAIL_FROM) — presence only. No value
// is read into anything that leaves this function, logged, or rendered.
//
// This is a second copy of X's check, and a copy can drift. The right home is an
// exported `emailSetup()` next to sendEmail() in X's file; reported to Track X.
const REQUIRED = ["RESEND_API_KEY", "EMAIL_FROM"] as const;

export function emailSetup(): EmailSetup {
  const missing = REQUIRED.filter((name) => !process.env[name]);
  return missing.length === 0 ? { configured: true } : { configured: false, missing: [...missing] };
}
