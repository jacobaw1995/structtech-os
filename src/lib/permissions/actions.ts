"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// G3 — the first write this page has ever had.
//
// Every change goes through set_member_capability(p_org_id, p_user_id,
// p_capability, p_value) — migration 20260911233218 — and nothing else
// (CLAUDE.md rule 3). Its refusals were read from the live body on 2026-09-12
// and are surfaced VERBATIM rather than reworded (A1.3a's rule): Track S wrote
// them to name the role and the reason, and a paraphrase would lose both.
//
// What the RPC refuses, in its own words, so the surface can avoid OFFERING it:
//   - caller is not a manager:
//       "only an owner or admin can change what a member can do in this workspace"
//   - target is manager tier:
//       "this member is an % and already passes every capability check —
//        setting % here would change the stored row and nothing else.
//        Change their role instead."
//   - p_value null:
//       "a capability is granted or denied, never null"
//
// That last one has a consequence the UI must carry: THERE IS NO WAY BACK TO
// "NEVER WRITTEN". A key can move from undecided to granted or denied; nothing
// can move it back. So the first write onto a never-written key is not a
// toggle, it is a decision, and it is permanent in kind even though its value
// can still be flipped.

export async function setMemberCapability(formData: FormData) {
  const orgId = formData.get("orgId");
  const userId = formData.get("userId");
  const capability = formData.get("capability");
  const value = formData.get("value");

  if (
    typeof orgId !== "string" ||
    typeof userId !== "string" ||
    typeof capability !== "string" ||
    (value !== "true" && value !== "false")
  ) {
    throw new Error("setMemberCapability: malformed form");
  }

  const back = `/w/${orgId}/settings/permissions`;

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) redirect("/login");

  const { error } = await supabase.rpc("set_member_capability", {
    p_org_id: orgId,
    p_user_id: userId,
    p_capability: capability,
    p_value: value === "true",
  });

  // Return to the member the change was made on, open, so the result is on
  // screen where the decision was taken rather than at the top of the page.
  const anchor = `#member-${userId}`;
  if (error) {
    redirect(
      `${back}?edit=${encodeURIComponent(userId)}&error=${encodeURIComponent(error.message)}${anchor}`
    );
  }
  revalidatePath(back);
  redirect(`${back}?edit=${encodeURIComponent(userId)}${anchor}`);
}
