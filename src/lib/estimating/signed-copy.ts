import "server-only";

// The signed copy: when a signature lands, the customer is emailed the signed
// estimate as a PDF.  Track X, X-W1.14, 2026-09-14.
//
// ── THE ORDERING GUARANTEE — A SEND THAT FAILS CANNOT LOSE THE SIGNATURE ─────
// sign_estimate() is one security-definer PL/pgSQL call: it inserts the
// signatures row and flips the estimate to 'signed' in ONE statement, so ONE
// transaction, and PostgREST commits it before it answers. This module is only
// ever called with the signature id that answer returned. So:
//   1. By the time any line here runs, the signature is already committed.
//   2. Nothing here writes to the database. There is no statement that could roll
//      the signature back, and no transaction for a failure to abort.
//   3. sendSignedCopy() never throws. Every failure — load, render, send — is a
//      returned state, so the caller's redirect cannot be replaced by an error page
//      that reads as "signing failed".
// What that does NOT guarantee: that the copy is sent. If the function is killed
// between the commit and the send (deploy, crash, platform timeout), the signature
// is kept and no copy leaves, and nothing records that it did not. Closing that
// needs the intent written INSIDE sign_estimate's transaction (an outbox row) and
// a sender that drains it — schema, so Track S's; proposed, not built here.
//
// ── WHAT IS DELIBERATELY NOT HERE ────────────────────────────────────────────
// Remote signing. Track S's spine (20260915004736, merged 2026-09-14 ~20:55 EDT,
// after this module was written) records a link signature as the SAME signatures
// row, via sign_estimate_by_link(token, …) called as anon. This module cannot be
// called from that path as it stands, and was deliberately not adapted:
//   · sign_estimate_by_link returns {state, business, signed_at} — no signature id;
//   · its caller is anon, and every read below (fetch_estimate, signatures,
//     tenant_modules) needs a member session.
// Both are S's model to extend (directive 2c: report and stop). What this needs is
// written in supabase/proposals/20260914_x_w1_14_signed_copy_outbox.md.
//
// IDEMPOTENT PER SIGNATURE — FOR 24 HOURS. The Resend Idempotency-Key is
// `signed-copy:<signature id>`. Per Resend's docs (read 2026-09-14; not measured
// against the live API — no key exists): keys are kept 24 hours; a reused key with
// a DIFFERENT payload is refused 409 invalid_idempotent_request; a reused key while
// the first request is in flight is refused 409 concurrent_idempotent_requests.
// So the PDF's dates are pinned to signed_at: pdf-lib stamps "now" by default, and
// two renders 1.1 s apart were measured NOT byte-identical unpinned, identical
// pinned. And a 409 is reported as UNCONFIRMED, not rejected: both 409s mean an
// earlier send with this key exists, which may well have been delivered.

import { PDFDocument } from "pdf-lib";
import type { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/supabase/database.types";
import { renderEstimatePdf } from "@/lib/estimating/pdf";
import { parseEstimateBranding } from "@/lib/estimating/branding";
import { sendEmail } from "@/lib/email/send";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];
type Signature = Database["public"]["Tables"]["signatures"]["Row"];

/**
 * What happened to the copy. Every state except `sent` means the SIGNATURE IS
 * SAVED and the copy is not confirmed — the page says both halves.
 */
export type SignedCopyState =
  | "sent" //           Resend accepted it (acceptance, not delivery)
  | "no_email" //       the estimate has no usable customer address
  | "not_configured" // RESEND_API_KEY / EMAIL_FROM absent — nothing was attempted
  | "rejected" //       Resend refused it (4xx); retrying the same send won't help
  | "unavailable" //    Resend did not answer / 5xx; it MAY have been sent
  | "render_failed"; // the document could not be loaded or rendered; nothing was sent

export const SIGNED_COPY_STATES: SignedCopyState[] = [
  "sent",
  "no_email",
  "not_configured",
  "rejected",
  "unavailable",
  "render_failed",
];

export function isSignedCopyState(v: unknown): v is SignedCopyState {
  return typeof v === "string" && (SIGNED_COPY_STATES as string[]).includes(v);
}

/** States where "Send again" is offered: a retry might change the outcome. */
export const RETRYABLE_COPY_STATES: SignedCopyState[] = ["unavailable", "rejected", "render_failed"];

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

type Supabase = ReturnType<typeof createClient>;

export async function sendSignedCopy(
  supabase: Supabase,
  { orgId, estimateId, signatureId }: { orgId: string; estimateId: string; signatureId: string }
): Promise<SignedCopyState> {
  try {
    const { data: fetched } = await supabase.rpc("fetch_estimate", { p_estimate_id: estimateId });
    const estimate = fetched?.[0] as Estimate | undefined;
    if (!estimate || estimate.org_id !== orgId) return "render_failed";

    const to = (estimate.email ?? "").trim();
    if (!EMAIL_RE.test(to)) return "no_email";

    const [{ data: lineItemsData }, { data: signaturesData }, { data: moduleRow }, { data: orgRows }] =
      await Promise.all([
        supabase
          .from("estimate_line_items")
          .select("*")
          .eq("estimate_id", estimate.id)
          .order("sort_order", { ascending: true }),
        // The signature by the id sign_estimate returned — not "the latest", which
        // is a different claim the moment an estimate can carry more than one.
        supabase.from("signatures").select("*").eq("estimate_id", estimate.id),
        supabase.from("tenant_modules").select("config").eq("org_id", orgId).eq("module_key", "estimating"),
        supabase.rpc("fetch_organization", { p_org_id: orgId }),
      ]);

    const signature = ((signaturesData ?? []) as Signature[]).find((s) => s.id === signatureId);
    if (!signature) return "render_failed";

    const branding = parseEstimateBranding(moduleRow?.[0]?.config ?? null, orgRows?.[0]?.name ?? "Estimate");
    const rendered = await renderEstimatePdf({
      estimate,
      lineItems: (lineItemsData ?? []) as LineItem[],
      signature,
      branding,
    });

    const pinned = await PDFDocument.load(rendered, { updateMetadata: false });
    pinned.setCreationDate(new Date(signature.signed_at));
    pinned.setModificationDate(new Date(signature.signed_at));
    const pdf = Buffer.from(await pinned.save()).toString("base64");

    const company = branding.companyName;
    const number = estimate.estimate_number ? ` ${estimate.estimate_number}` : "";
    const safeNumber = (estimate.estimate_number ?? "").replace(/[^A-Za-z0-9-]/g, "");
    const greeting = estimate.contact_name ? `Hi ${estimate.contact_name},` : "Hello,";
    const signedOn = new Date(signature.signed_at).toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
      timeZone: "America/New_York",
    });
    const lines = [
      greeting,
      `Attached is your signed copy of estimate${number} from ${company}, signed by ${signature.signer_name} on ${signedOn}.`,
      branding.phone || branding.email
        ? `Questions? Contact ${company}${branding.phone ? ` at ${branding.phone}` : ""}${branding.email ? `${branding.phone ? " or" : " at"} ${branding.email}` : ""}.`
        : `Keep this email for your records.`,
    ];

    const result = await sendEmail({
      to,
      subject: `Your signed estimate${number} from ${company}`,
      text: lines.join("\n\n"),
      html: lines.map((l) => `<p>${escapeHtml(l)}</p>`).join(""),
      replyTo: branding.email && EMAIL_RE.test(branding.email) ? branding.email : undefined,
      idempotencyKey: `signed-copy:${signature.id}`,
      attachments: [{ filename: safeNumber ? `signed-estimate-${safeNumber}.pdf` : "signed-estimate.pdf", content: pdf }],
    });

    if (result.ok) return "sent";
    if (result.reason === "rejected" && result.status === 409) return "unavailable";
    return result.reason;
  } catch {
    return "render_failed";
  }
}
