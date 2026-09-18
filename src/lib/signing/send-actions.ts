"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { sendEmail } from "@/lib/email/send";
import { parseEstimateBranding } from "@/lib/estimating/branding";
import { LINK_VALID_DAYS, type SendResult } from "@/lib/signing/remote";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];

// SEND THIS ESTIMATE FOR SIGNATURE. U-W1.19, 2026-09-16.
//
// 1. create_estimate_sign_link(estimate, 14) — Track S's function refuses a caller
//    without create_estimates or view_financials, a signed estimate, and one that
//    is not presented; issuing a link revokes any earlier live one.
// 2. sendEmail() — Track X's, with its three failure reasons kept apart.
// 3. ANY failure revokes the link just created, so a live link always means the
//    email service accepted a message carrying it (see lib/signing/remote.ts).
// The token exists in memory here only long enough to put it in the email; it is
// never logged, never returned to the browser, and never put in a URL we redirect to.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

// Where the customer's link points. SITE_URL when set (the same variable Track X's
// password reset reads); otherwise this request's own host. The caller is an
// authenticated office member sending to their own customer, so a forged Host
// header can only misdirect a link that member sends themselves.
function siteOrigin(): string {
  if (process.env.SITE_URL) return process.env.SITE_URL.replace(/\/+$/, "");
  const h = headers();
  const host = h.get("x-forwarded-host") ?? h.get("host") ?? "localhost:3000";
  const proto = h.get("x-forwarded-proto") ?? (host.startsWith("localhost") ? "http" : "https");
  return `${proto}://${host}`;
}

function classifyLinkRefusal(error: { message: string; hint?: string | null }): SendResult {
  // Named by its HINT, which Track S set for exactly this (not by its wording).
  if (error.hint === "no_presented_total") return "no_total";
  const message = error.message;
  if (/cannot send estimates|cannot view financials|not found or not accessible/i.test(message)) return "not_permitted";
  if (/already signed/i.test(message)) return "already_signed";
  if (/must be presented/i.test(message)) return "not_presented";
  return "link_failed";
}

export async function sendForSignature(formData: FormData) {
  const orgId = formData.get("orgId");
  const estimateId = formData.get("estimateId");
  if (typeof orgId !== "string" || typeof estimateId !== "string") {
    throw new Error("sendForSignature: malformed form");
  }
  const back = `/w/${orgId}/estimating/${estimateId}`;
  const done = (result: SendResult): never => {
    revalidatePath(back);
    redirect(`${back}?send=${result}#signature`);
  };

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const [{ data: fetched }, { data: moduleRow }, { data: orgRows }] = await Promise.all([
    supabase.rpc("fetch_estimate", { p_estimate_id: estimateId }),
    supabase.from("tenant_modules").select("config").eq("org_id", orgId).eq("module_key", "estimating"),
    supabase.rpc("fetch_organization", { p_org_id: orgId }),
  ]);
  const estimate = fetched?.[0] as Estimate | undefined;
  if (!estimate || estimate.org_id !== orgId) done("not_permitted");
  const est = estimate as Estimate;

  // Checked before a link exists, so "no address" never leaves a link behind.
  const to = (est.email ?? "").trim();
  if (!EMAIL_RE.test(to)) done("no_email");

  const { data: linkData, error: linkError } = await supabase.rpc("create_estimate_sign_link", {
    p_estimate_id: est.id,
    p_valid_days: LINK_VALID_DAYS,
  });
  if (linkError) done(classifyLinkRefusal(linkError));
  const link = (linkData ?? {}) as { token?: unknown; link_id?: unknown };
  if (typeof link.token !== "string" || typeof link.link_id !== "string") done("link_failed");
  const token = link.token as string;
  const linkId = link.link_id as string;

  const branding = parseEstimateBranding(moduleRow?.[0]?.config ?? null, orgRows?.[0]?.name ?? "Estimate");
  const company = branding.companyName;
  const number = est.estimate_number ? ` ${est.estimate_number}` : "";
  const url = `${siteOrigin()}/sign/${token}`;
  const expires = new Date(Date.now() + LINK_VALID_DAYS * 86_400_000).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "America/New_York",
  });
  const greeting = est.contact_name ? `Hi ${est.contact_name},` : "Hello,";
  const lines = [
    greeting,
    `${company} has sent you estimate${number} to review and sign.`,
    `Open this link to read it and sign: ${url}`,
    `The link works until ${expires}. It opens this one estimate and nothing else.`,
  ];

  let result: SendResult;
  try {
    const sent = await sendEmail({
      to,
      subject: `Review and sign your estimate${number} from ${company}`,
      text: lines.join("\n\n"),
      html:
        lines
          .slice(0, 2)
          .map((l) => `<p>${escapeHtml(l)}</p>`)
          .join("") +
        `<p><a href="${escapeHtml(url)}">Review and sign the estimate</a></p>` +
        `<p>${escapeHtml(lines[3])}</p>`,
      replyTo: branding.email && EMAIL_RE.test(branding.email) ? branding.email : undefined,
      // One logical message per link: a retried request cannot deliver it twice.
      idempotencyKey: `sign-link:${linkId}`,
    });
    result = sent.ok ? "sent" : sent.reason;
  } catch {
    result = "unavailable";
  }

  if (result !== "sent") {
    const { error: revokeError } = await supabase.rpc("revoke_estimate_sign_link", { p_link_id: linkId });
    if (revokeError) result = "cancel_failed";
  }
  done(result);
}
