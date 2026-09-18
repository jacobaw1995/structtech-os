"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { classifyLoginError } from "@/lib/auth/login-states";

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

  redirect("/select-workspace");
}
