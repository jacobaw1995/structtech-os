"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { classifyLinkSignError, type SignOutcome } from "@/lib/signing/link-states";
import { composeAndSendSignedCopy, isSignedCopyState, type SignedCopyState } from "@/lib/estimating/signed-copy";
import { parseEstimateBranding } from "@/lib/estimating/branding";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];
type Signature = Database["public"]["Tables"]["signatures"]["Row"];

// THE CUSTOMER SIGNS. Called by a person who is NOT a user of this system: the
// only authority in the request is the token, and it is checked in the database
// (sign_estimate_by_link, granted to anon). Nothing here reads a session as
// permission and nothing redirects to /login.
//
// ORDER IS THE GUARANTEE (controller condition 4). The signature row, the
// estimate's `signed` status, the link's `used_at` and the "copy owed" row in
// signed_copy_records are written by sign_estimate_by_link and its trigger in ONE
// transaction, committed before PostgREST answers. Only after a `signed` answer is
// the copy attempted, and that attempt never throws and writes nothing that could
// undo the signature. If the copy fails, or this function dies mid-send, the
// signature stands and the database still says a copy is owed.

const TOKEN_RE = /^[0-9a-f]{64}$/;

export async function signByLink(formData: FormData) {
  const token = formData.get("token");
  // A malformed token has nothing to look up; the page renders it as unavailable.
  if (typeof token !== "string" || !TOKEN_RE.test(token)) redirect("/sign/unavailable");
  const back = `/sign/${token}`;

  const text = (k: string) => {
    const v = formData.get(k);
    return typeof v === "string" ? v : "";
  };

  const supabase = createClient();
  // Loads a session if one happens to exist (an office user testing their own
  // link); anon otherwise. Not branched on — the token is the authorisation.
  await supabase.auth.getSession();

  let outcome: SignOutcome;
  let signed: { signature_id: string } | null = null;
  try {
    const { data, error } = await supabase.rpc("sign_estimate_by_link", {
      p_token: token,
      p_document_version: text("document_version"),
      p_signer_name: text("signer_name"),
      p_signer_role: text("signer_role"),
      p_signature_data: text("signature_data"),
    });
    if (error) {
      outcome = classifyLinkSignError(error);
    } else {
      const state = (data as { state?: unknown } | null)?.state;
      if (state === "signed") {
        outcome = "signed";
        const id = (data as { signature_id?: unknown }).signature_id;
        signed = typeof id === "string" ? { signature_id: id } : null;
      } else if (state === "document_changed") {
        outcome = "document_changed";
      } else {
        // already_signed / expired / unavailable: the page reads the link again
        // and shows that state itself, so no outcome code is needed.
        redirect(back);
      }
    }
  } catch (e) {
    // redirect() throws by design; let it through.
    if ((e as { digest?: string })?.digest?.startsWith("NEXT_REDIRECT")) throw e;
    outcome = "sign_unconfirmed";
  }

  if (outcome !== "signed") redirect(`${back}?r=${outcome}`);

  // Committed. Now, and only now, the copy.
  const copy = signed ? await sendCopyByLink(supabase, token) : null;
  redirect(`${back}?r=signed${copy ? `&copy=${copy}` : ""}`);
}

/** Never throws. Records the outcome against signed_copy_records when it can. */
async function sendCopyByLink(supabase: ReturnType<typeof createClient>, token: string): Promise<SignedCopyState | null> {
  try {
    const { data, error } = await supabase.rpc("signed_copy_by_link", { p_token: token });
    const p = (data ?? {}) as Record<string, unknown>;
    if (error || p.state !== "ready") return null; // already sent, or outside its window: nothing owed from here

    const result = await composeAndSendSignedCopy({
      estimate: p.estimate as Estimate,
      lineItems: (p.line_items ?? []) as LineItem[],
      signature: p.signature as Signature,
      branding: parseEstimateBranding(
        (p.estimating_config ?? null) as Database["public"]["Tables"]["tenant_modules"]["Row"]["config"],
        typeof p.org_name === "string" ? p.org_name : "Estimate"
      ),
    });

    // The record is best-effort: if it fails, the row stays `owed`, which is true.
    await supabase.rpc("record_signed_copy_outcome_by_link", {
      p_token: token,
      p_state: result.state,
      ...(result.providerMessageId ? { p_provider_message_id: result.providerMessageId } : {}),
    });
    return isSignedCopyState(result.state) ? result.state : null;
  } catch {
    return null;
  }
}
