"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { sendEmail } from "@/lib/email/send";

// The email check: one real send, in whatever environment this runs in, to the
// signed-in manager's OWN address.  Track X, X-W1.17, 2026-09-16.
//
// WHY IT EXISTS. On 2026-09-16 the production variables were confirmed present by
// name, and production had never sent a message. The only production paths that
// send are signing and re-sending a signed copy, and every estimate in production
// belongs to a real customer, so exercising either would email a customer. This
// gives Jacob a single click that exercises the same sendEmail() the signed copy
// uses, to himself, leaving an `[email.send]` line in the runtime log.
//
// WHAT IT REFUSES TO BE:
//   · a way to mail anyone else — the recipient is getUser()'s email, verified by
//     the auth server, never a form field and never the cookie's copy of the user;
//   · a spam button — managers only, and the Idempotency-Key is per user per UTC
//     hour, so repeated clicks in the same hour are one message.
// The outcome is a CODE on the redirect; the page supplies the words.

export async function sendEmailCheck(formData: FormData) {
  const orgId = String(formData.get("orgId") ?? "");
  const back = (code: string) => redirect(`/w/${orgId}/settings/email-check?result=${code}`);

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { data: isManager } = await supabase.rpc("is_org_manager", { p_org_id: orgId });
  if (isManager !== true) back("not_allowed");

  const { data: userData } = await supabase.auth.getUser();
  const to = userData.user?.email;
  if (!to || !userData.user) back("no_address");

  const hour = new Date().toISOString().slice(0, 13); // UTC, e.g. 2026-09-16T21
  const result = await sendEmail({
    to: to as string,
    subject: "StructTech OS — email check",
    text: `This is the email check from StructTech OS, sent at ${new Date().toISOString()}. If you are reading it, transactional email works from this deployment.`,
    html: `<p>This is the email check from StructTech OS, sent at ${new Date().toISOString()}.</p><p>If you are reading it, transactional email works from this deployment.</p>`,
    idempotencyKey: `email-check:${userData.user!.id}:${hour}`,
    purpose: "email_check",
  });
  back(result.ok ? "sent" : result.reason);
}
