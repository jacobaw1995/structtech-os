"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { classifyLoginError } from "@/lib/auth/login-states";
import { recordFieldEvent } from "@/lib/observability/field-events";

export async function login(formData: FormData) {
  const email = formData.get("email");
  const password = formData.get("password");

  if (typeof email !== "string" || typeof password !== "string") {
    redirect("/login?error=missing");
  }

  const supabase = createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    // A code, never the provider's message (lib/auth/login-states.ts).
    redirect(`/login?error=${classifyLoginError(error)}`);
  }

  // X-W1.19: every sign-in, durably (auth keeps only the last one). One row per
  // workspace the person belongs to. Bounded, never throws, never blocks sign-in.
  await recordFieldEvent(supabase, { orgId: null, event: "signed_in" });

  redirect("/select-workspace");
}
